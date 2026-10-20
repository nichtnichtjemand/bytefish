import time

from move import Move
from piece import Piece
import piece_square_tables as tables
from syzygy import SyzygyTablebase


# The UCI process uses a fork-based pool on Linux. Each worker inherits its own
# snapshot of this board and searches independent root moves in that snapshot.
_PARALLEL_SEARCH_BOARD = None


def _search_root_move(task):
    move, depth, deadline = task
    board = _PARALLEL_SEARCH_BOARD
    if board is None:
        raise RuntimeError("Parallel search worker was not initialized")

    board._check_deadline(deadline)
    child = board.copy()
    if not child.move(move):
        return move, 0
    return move, child.minimax(
        depth - 1, float("-inf"), float("inf"), deadline
    )


def create_search_executor(board, workers=2):
    """Create a two-process root-search pool on platforms that support fork."""
    global _PARALLEL_SEARCH_BOARD
    import multiprocessing
    from concurrent.futures import ProcessPoolExecutor

    if "fork" not in multiprocessing.get_all_start_methods():
        return None

    _PARALLEL_SEARCH_BOARD = board
    return ProcessPoolExecutor(
        max_workers=workers,
        mp_context=multiprocessing.get_context("fork"),
    )


class SearchTimeout(Exception):
    """Raised when the UCI search budget has expired."""


class Board:

    def __init__(self, tablebase: SyzygyTablebase | None = None):
        setup = [
                        ["r", "n", "b", "q", "k", "b", "n", "r"],
                        ["p", "p", "p", "p", "p", "p", "p", "p"],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["P", "P", "P", "P", "P", "P", "P", "P"],
                        ["R", "N", "B", "Q", "K", "B", "N", "R"]
        ]
        self.current_turn = True # True = White, False = Black
        self.history = {}
        self.transposition_table = {}
        self.transposition_table_limit = 4096
        self.repetition_counts = {}
        self.board = []
        for row in setup:
            new_row = []
            for char in row:
                if char != "":
                    new_row.append(Piece(char))
                else:
                    new_row.append("")
            self.board.append(new_row)
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self.tablebase = tablebase
        if self.tablebase is None:
            default_path = SyzygyTablebase.default_path()
            if default_path is not None:
                self.tablebase = SyzygyTablebase(default_path)
        self._record_position()



    def move(self, move: Move):

        from_column = move.from_column
        from_row = move.from_row
        to_column = move.to_column
        to_row = move.to_row

        if (from_row < 0) or (to_row < 0) or (from_column < 0) or (to_column < 0) or (from_row > 7) or (to_row > 7) or (from_column > 7) or (to_column > 7):
            return False

        from_piece = self.board[from_row][from_column]
        to_piece = self.board[to_row][to_column]
        if from_piece == "":
            return False

        is_en_passant = self.is_en_passant(move)
        if to_piece != "":
            if from_piece.color == to_piece.color:
                return False
        if from_piece.color != self.current_turn:
            return False
        if from_column == to_column and from_row == to_row:
            return False

        is_castling = (
            from_piece.type == "k"
            and from_row == to_row
            and abs(to_column - from_column) == 2
        )

        if is_castling:
            if not self._can_castle(move):
                return False

            rook_from_column = 7 if to_column > from_column else 0
            rook_to_column = 5 if to_column > from_column else 3
            rook = self.board[from_row][rook_from_column]

            self.board[to_row][to_column] = from_piece
            self.board[from_row][from_column] = ""
            self.board[from_row][rook_to_column] = rook
            self.board[from_row][rook_from_column] = ""
            self._remove_castling_rights(from_piece)
            self._finish_move(move, from_piece, to_piece)
            return True

        if not from_piece.is_legal_move(self, move):
            return False

        if is_en_passant:
            captured_row = to_row + (1 if from_piece.color else -1)
            self.board[captured_row][to_column] = ""
        
        if from_piece.type == "p" and to_row in (0, 7):
            promotion = move.promotion or "q"

            if promotion.lower() not in ("q", "r", "b", "n"):
                return False

            promoted_piece = promotion.lower()

            if from_piece.color:
                promoted_piece = promoted_piece.upper()

            self.board[to_row][to_column] = Piece(promoted_piece)
        else:
            if move.promotion is not None:
                return False

            self.board[to_row][to_column] = from_piece

        self.board[from_row][from_column] = ""
        self._update_castling_rights(move, from_piece, to_piece)
        self._finish_move(
            move,
            from_piece,
            to_piece,
            is_capture=to_piece != "" or is_en_passant,
        )
        self._record_position()

        return True

    def is_en_passant(self, move):
        """Return whether move is a legal en-passant capture shape."""
        if self.en_passant_square == "-":
            return False

        from_piece = self.board[move.from_row][move.from_column]
        target = self.board[move.to_row][move.to_column]
        if from_piece == "" or from_piece.type != "p" or target != "":
            return False

        if move.to_field.lower() != self.en_passant_square.lower():
            return False

        direction = -1 if from_piece.color else 1
        if move.to_row - move.from_row != direction:
            return False
        if abs(move.to_column - move.from_column) != 1:
            return False

        captured = self.board[move.from_row][move.to_column]
        return (
            captured != ""
            and captured.type == "p"
            and captured.color != from_piece.color
        )

    def _finish_move(self, move, from_piece, to_piece, is_capture=False):
        """Update clocks and the en-passant target after a successful move."""
        was_double_pawn_move = (
            from_piece.type == "p"
            and abs(move.to_row - move.from_row) == 2
        )
        self.en_passant_square = "-"
        if was_double_pawn_move:
            target_row = (move.from_row + move.to_row) // 2
            self.en_passant_square = (
                f"{move.from_field[0].lower()}{8 - target_row}"
            )

        if from_piece.type == "p" or is_capture:
            self.halfmove_clock = 0
        else:
            self.halfmove_clock += 1

        self.current_turn = not self.current_turn
        if self.current_turn:
            self.fullmove_number += 1

    def _position_key(self):
        """Return the repetition identity, excluding move counters."""
        return (
            tuple(
                piece.piece if piece != "" else ""
                for row in self.board
                for piece in row
            ),
            self.current_turn,
            self.castling_rights,
            self.en_passant_square,
        )

    def _record_position(self):
        key = self._position_key()
        self.repetition_counts[key] = self.repetition_counts.get(key, 0) + 1

    def is_threefold_repetition(self):
        """Return whether the current position has occurred three times."""
        return self.repetition_counts.get(self._position_key(), 0) >= 3

    def _can_castle(self, move):
        row = move.from_row
        is_white = self.current_turn
        king_side = move.to_column > move.from_column
        right = ("K" if king_side else "Q") if is_white else ("k" if king_side else "q")
        rook_column = 7 if king_side else 0
        between_columns = (5, 6) if king_side else (1, 2, 3)
        transit_columns = (5,) if king_side else (3,)

        if move.from_column != 4 or move.to_row != row:
            return False
        if right not in self.castling_rights:
            return False
        if any(self.board[row][column] != "" for column in between_columns):
            return False

        rook = self.board[row][rook_column]
        if rook == "" or rook.type != "r" or rook.color != is_white:
            return False
        if self.is_in_check(is_white):
            return False

        enemy_color = not is_white
        for column in transit_columns:
            if self.is_square_attacked(row, column, enemy_color):
                return False

        return True

    def _remove_castling_rights(self, piece):
        if piece.color:
            self.castling_rights = self.castling_rights.replace("K", "").replace("Q", "")
        else:
            self.castling_rights = self.castling_rights.replace("k", "").replace("q", "")

    def _update_castling_rights(self, move, from_piece, to_piece):
        if from_piece.type == "k":
            self._remove_castling_rights(from_piece)
        elif from_piece.type == "r":
            if move.from_field.lower() == "a1":
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif move.from_field.lower() == "h1":
                self.castling_rights = self.castling_rights.replace("K", "")
            elif move.from_field.lower() == "a8":
                self.castling_rights = self.castling_rights.replace("q", "")
            elif move.from_field.lower() == "h8":
                self.castling_rights = self.castling_rights.replace("k", "")

        if to_piece != "" and to_piece.type == "r":
            if move.to_field.lower() == "a1":
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif move.to_field.lower() == "h1":
                self.castling_rights = self.castling_rights.replace("K", "")
            elif move.to_field.lower() == "a8":
                self.castling_rights = self.castling_rights.replace("q", "")
            elif move.to_field.lower() == "h8":
                self.castling_rights = self.castling_rights.replace("k", "")


    def get_legal_moves(self):
        legal_moves = []

        for from_row in range(8):
            for from_column in range(8):
                piece = self.board[from_row][from_column]

                if piece == "" or piece.color != self.current_turn:
                    continue

                from_field = (
                    chr(ord("a") + from_column)
                    + str(8 - from_row)
                )

                for candidate in piece.get_candidate_moves(
                    self, from_row, from_column
                ):
                    to_row = candidate.to_row
                    to_column = candidate.to_column

                    to_field = (
                        chr(ord("a") + to_column)
                        + str(8 - to_row)
                    )

                    promotions = (
                        ("q", "r", "b", "n")
                        if piece.type == "p" and to_row in (0, 7)
                        else (None,)
                    )

                    for promotion in promotions:
                        move = Move(from_field, to_field, promotion)

                        is_castling = (
                            piece.type == "k"
                            and from_column == 4
                            and to_column in (2, 6)
                            and from_row == to_row
                        )

                        if is_castling and not self._can_castle(move):
                            continue

                        if not is_castling and not piece.is_legal_move(
                            self, move
                        ):
                            continue

                        child = self.copy()

                        if not child.move(move):
                            continue

                        if not child.is_in_check(self.current_turn):
                            legal_moves.append(move)

                # Rochade separat prüfen, da der König
                # normalerweise nur ein Feld weit zieht.
                if piece.type == "k" and from_column == 4:
                    for to_column in (2, 6):
                        to_field = (
                            chr(ord("a") + to_column)
                            + str(8 - from_row)
                        )

                        move = Move(from_field, to_field)

                        if not self._can_castle(move):
                            continue

                        child = self.copy()

                        if not child.move(move):
                            continue

                        if not child.is_in_check(self.current_turn):
                            legal_moves.append(move)

        return legal_moves

    def get_material_score(self):
        rating = 0

        piece_values = {
            "p": 100, "n": 300, "b": 300, "r": 500, "q": 900, "k": 0, 
            "P": -100, "N": -300, "B": -300, "R": -500, "Q": -900, "K": 0
        }
        
        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece !=  "":
                    rating += piece_values[piece.piece]
        return rating

    def copy(self):
        new_board = object.__new__(Board)

        new_board.board = [row[:] for row in self.board]
        new_board.current_turn = self.current_turn

        new_board.castling_rights = self.castling_rights
        new_board.en_passant_square = self.en_passant_square
        new_board.halfmove_clock = self.halfmove_clock
        new_board.fullmove_number = self.fullmove_number

        new_board.history = self.history.copy()
        new_board.transposition_table = self.transposition_table
        new_board.transposition_table_limit = self.transposition_table_limit
        new_board.repetition_counts = self.repetition_counts.copy()
        new_board.tablebase = self.tablebase

        return new_board

    def find_mate_in_one(self, moves=None, deadline=None):
        if moves is None:
            moves = self.get_legal_moves()
        for move in moves:
            self._check_deadline(deadline)
            test_board = self.copy()

            if not test_board.move(move):
                continue

            if test_board.is_checkmate(test_board.current_turn):
                return move

        return None



    def reset(self):
        setup = [
                        ["r", "n", "b", "q", "k", "b", "n", "r"],
                        ["p", "p", "p", "p", "p", "p", "p", "p"],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["P", "P", "P", "P", "P", "P", "P", "P"],
                        ["R", "N", "B", "Q", "K", "B", "N", "R"]
        ]
        self.current_turn = True # True = White, False = Black
        self.board = []
        for row in setup:
            new_row = []
            for char in row:
                if char != "":
                    new_row.append(Piece(char))
                else:
                    new_row.append("")
            self.board.append(new_row)
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self.history = {}
        self.transposition_table = {}
        self.repetition_counts = {}
        self._record_position()


    def get_position_score(self):
        score = 0

        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece != "":
                    table_row = row if piece.color else 7 - row
                    bonus = tables.PIECE_SQUARE_TABLES[piece.type][table_row][column]

                    if piece.color:
                        score -= bonus
                    else:
                        score += bonus 

        return score

    def _piece_count(self):
        return sum(
            piece != ""
            for row in self.board
            for piece in row
        )

    def is_endgame(self):
        """Return whether the position is sparse enough for endgame rules."""
        return self._piece_count() - 2 <= 10

    def _is_passed_pawn(self, row, column, color):
        """Return whether a pawn has no opposing pawn blocking its files."""
        enemy_pawn = "p" if color else "P"
        for enemy_row in range(8):
            enemy = self.board[enemy_row][column]
            if enemy != "" and enemy.piece == enemy_pawn:
                if (color and enemy_row < row) or (not color and enemy_row > row):
                    return False
            for adjacent_column in (column - 1, column + 1):
                if 0 <= adjacent_column < 8:
                    enemy = self.board[enemy_row][adjacent_column]
                    if enemy != "" and enemy.piece == enemy_pawn:
                        if (color and enemy_row < row) or (
                            not color and enemy_row > row
                        ):
                            return False
        return True

    def get_endgame_score(self):
        """Score king activity, pawn races, and opposition in sparse positions."""
        if not self.is_endgame():
            return 0

        score = 0
        center_row, center_column = 3.5, 3.5

        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece == "":
                    continue

                sign = -1 if piece.color else 1
                if piece.type == "k":
                    distance = abs(row - center_row) + abs(column - center_column)
                    score += sign * int((7 - distance) * 12)
                elif piece.type == "p":
                    rank = 7 - row if piece.color else row
                    score += sign * rank * 8
                    if self._is_passed_pawn(row, column, piece.color):
                        score += sign * (35 + rank * 12)
                        # A king that supports its passer is more valuable
                        # than a passer whose promotion square is unreachable.
                        king_distance = self._distance_to_king(
                            row, column, piece.color
                        )
                        score += sign * max(0, 24 - king_distance * 4)

        # Reward the side to move for taking the opposition in king-and-pawn
        # endings.  The tempo is often the deciding endgame resource.
        if self._piece_count() <= 4:
            kings = self._king_squares()
            if len(kings) == 2 and self.current_turn:
                score += self._opposition_score(kings)
            elif len(kings) == 2:
                score -= self._opposition_score(kings)

        return score

    def _king_squares(self):
        return [
            (row, column)
            for row in range(8)
            for column in range(8)
            if (
                self.board[row][column] != ""
                and self.board[row][column].type == "k"
            )
        ]

    def _distance_to_king(self, row, column, color):
        king = next(
            (
                (king_row, king_column)
                for king_row in range(8)
                for king_column in range(8)
                if (
                    self.board[king_row][king_column] != ""
                    and self.board[king_row][king_column].type == "k"
                    and self.board[king_row][king_column].color == color
                )
            ),
            None,
        )
        if king is None:
            return 8
        return max(abs(row - king[0]), abs(column - king[1]))

    @staticmethod
    def _opposition_score(kings):
        (first_row, first_column), (second_row, second_column) = kings
        if first_column != second_column and first_row != second_row:
            return 0
        distance = max(
            abs(first_row - second_row),
            abs(first_column - second_column),
        )
        return 10 if distance % 2 == 0 else -10

    def get_hanging_piece_score(self):
        """Penalize non-king pieces that can be taken without protection."""
        piece_values = {
            "p": 50,
            "n": 150,
            "b": 160,
            "r": 250,
            "q": 450,
        }
        score = 0

        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece == "" or piece.type == "k":
                    continue

                enemy = not piece.color
                if not self.is_square_attacked(row, column, enemy):
                    continue
                if self.is_square_attacked(row, column, piece.color):
                    continue

                penalty = piece_values[piece.type]
                score += penalty if piece.color else -penalty

        return score

    def get_pawn_structure_score(self):
        """Score pawn weaknesses and useful pawn formations."""
        score = 0
        pawns_by_file = {True: [0] * 8, False: [0] * 8}

        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece != "" and piece.type == "p":
                    pawns_by_file[piece.color][column] += 1

        for color in (True, False):
            sign = -1 if color else 1
            pawns = pawns_by_file[color]
            for column, count in enumerate(pawns):
                if count > 1:
                    score += sign * (count - 1) * 12
                if count == 0:
                    continue

                has_neighbour = (
                    column > 0 and pawns[column - 1] > 0
                ) or (
                    column < 7 and pawns[column + 1] > 0
                )
                if not has_neighbour:
                    score += sign * count * 14

        return score

    def get_mobility_score(self):
        """Reward useful space and active non-pawn pieces."""
        piece_weights = {"n": 4, "b": 4, "r": 2, "q": 1, "k": 1}
        score = 0
        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece == "" or piece.type not in piece_weights:
                    continue
                mobility = sum(
                    self.board[move.to_row][move.to_column] == ""
                    or self.board[move.to_row][move.to_column].color != piece.color
                    for move in piece.get_candidate_moves(self, row, column)
                )
                sign = -1 if piece.color else 1
                score += sign * mobility * piece_weights[piece.type]
        return score

    def get_king_safety_score(self):
        """Reward a pawn shield while the queens are still on the board."""
        if not any(
            piece != "" and piece.type == "q"
            for row in self.board
            for piece in row
        ):
            return 0

        score = 0
        for color in (True, False):
            king = next(
                (
                    (row, column)
                    for row in range(8)
                    for column in range(8)
                    if (
                        self.board[row][column] != ""
                        and self.board[row][column].type == "k"
                        and self.board[row][column].color == color
                    )
                ),
                None,
            )
            if king is None:
                continue
            row, column = king
            pawn_row = row - 1 if color else row + 1
            shield = 0
            if 0 <= pawn_row < 8:
                for shield_column in range(max(0, column - 1), min(8, column + 2)):
                    piece = self.board[pawn_row][shield_column]
                    if piece != "" and piece.type == "p" and piece.color == color:
                        shield += 1
            sign = -1 if color else 1
            score += sign * shield * 12
        return score

    def _endgame_move_bonus(self, move):
        """Prioritize promotion races, passed pawns, and active kings."""
        piece = self.board[move.from_row][move.from_column]
        if piece == "":
            return 0

        bonus = 0
        if piece.type == "p":
            if move.to_row in (0, 7):
                bonus += 900
            elif self._is_passed_pawn(move.from_row, move.from_column, piece.color):
                bonus += 120
        elif piece.type == "k":
            old_distance = abs(move.from_row - 3.5) + abs(move.from_column - 3.5)
            new_distance = abs(move.to_row - 3.5) + abs(move.to_column - 3.5)
            if new_distance < old_distance:
                bonus += 45
        return bonus


    def evaluate(self, board):
        if board.tablebase is not None:
            wdl = board.tablebase.probe_wdl(board)
            if wdl is not None:
                # Existing scores are positive for Black and negative for White.
                perspective = -1 if board.current_turn else 1
                return perspective * wdl * 100000

        score = board.get_material_score() + board.get_position_score()
        score += board.get_pawn_structure_score()
        score += board.get_mobility_score()
        score += board.get_king_safety_score()
        score += board.get_hanging_piece_score()
        return score + board.get_endgame_score()
    

    def best_move(
        self, depth, deadline=None, executor=None, root_moves=None
    ):
        legal_moves = self.get_legal_moves()
        if root_moves is not None:
            allowed = {self._move_key(move) for move in root_moves}
            legal_moves = [
                move for move in legal_moves if self._move_key(move) in allowed
            ]
        moves = self.order_moves(legal_moves)

        if not moves:
            return None

        self._check_deadline(deadline)

        tablebase_move = self._best_tablebase_move(moves, deadline)
        if tablebase_move is not None:
            return tablebase_move

        tablebase_transition = self._best_tablebase_transition_move(
            moves, deadline
        )
        if tablebase_transition is not None:
            return tablebase_transition

        mate_move = self.find_mate_in_one(moves, deadline)

        if mate_move is not None:
            return mate_move

        best_move = None
        alpha = float("-inf")
        beta = float("inf")

        if self.current_turn:
            best_score = float("inf")
        else:
            best_score = float("-inf") 

        if executor is not None:
            scored_moves = executor.map(
                _search_root_move,
                ((move, depth, deadline) for move in moves),
            )
            for move, score in scored_moves:
                self._check_deadline(deadline)
                if self.current_turn:
                    if score < best_score:
                        best_score = score
                        best_move = move
                elif score > best_score:
                    best_score = score
                    best_move = move
        else:
            for move in moves:
                self._check_deadline(deadline)
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta, deadline)

                if self.current_turn:
                    if score < best_score:
                        best_score = score
                        best_move = move

                    beta = min(beta, best_score)
                else:
                    if score > best_score:
                        best_score = score
                        best_move = move

                    alpha = max(alpha, best_score)

        return best_move

    @staticmethod
    def _check_deadline(deadline):
        if deadline is not None:
            if time.monotonic() >= deadline:
                raise SearchTimeout

    def _best_tablebase_move(self, moves, deadline=None):
        """Select a move by probing every resulting tablebase position."""
        if self.tablebase is None or self.tablebase.probe_wdl(self) is None:
            return None

        scored_moves = []
        for move in moves:
            self._check_deadline(deadline)
            child = self.copy()
            if not child.move(move):
                continue

            if child.tablebase.probe_wdl(child) is None:
                # A missing child table must not turn a known WDL position
                # into a heuristic tablebase move.
                return None

            score = child.evaluate(child)
            probe_dtz = getattr(child.tablebase, "probe_dtz", None)
            dtz = probe_dtz(child) if probe_dtz is not None else None
            scored_moves.append((score, dtz, move))

        if not scored_moves:
            return None

        return self._select_tablebase_move(scored_moves)

    def _select_tablebase_move(self, scored_moves):
        """Select by root WDL first, then by DTZ when WDL is equal."""
        root_scores = [
            (-score if self.current_turn else score, dtz, move)
            for score, dtz, move in scored_moves
        ]
        best_root_score = max(item[0] for item in root_scores)
        candidates = [
            item for item in root_scores if item[0] == best_root_score
        ]

        if len(candidates) == 1:
            return candidates[0][2]

        root_dtz = [
            abs(item[1])
            for item in candidates
            if item[1] is not None
        ]
        if not root_dtz:
            return candidates[0][2]

        if best_root_score < 0:
            # When losing, delay the zeroing move if no drawing/winning move
            # exists. This is the usual defensive DTZ preference.
            wanted_dtz = max(root_dtz)
        else:
            # When winning or drawing, reach a zeroing move quickly.
            wanted_dtz = min(root_dtz)

        return next(
            item[2] for item in candidates
            if item[1] is not None and abs(item[1]) == wanted_dtz
        )

    def _best_tablebase_transition_move(self, moves, deadline=None):
        """Prefer a capture that makes a six-piece position tablebase-known."""
        if self.tablebase is None or self._piece_count() != 6:
            return None

        scored_moves = []
        for move in moves:
            self._check_deadline(deadline)
            child = self.copy()
            if not child.move(move) or child._piece_count() > 5:
                continue

            wdl = child.tablebase.probe_wdl(child)
            if wdl is not None:
                probe_dtz = getattr(child.tablebase, "probe_dtz", None)
                dtz = probe_dtz(child) if probe_dtz is not None else None
                scored_moves.append((child.evaluate(child), dtz, move))

        if not scored_moves:
            return None

        return self._select_tablebase_move(scored_moves)


    def minimax(
        self,
        depth,
        alpha=float("-inf"),
        beta=float("inf"),
        deadline=None,
    ):
        self._check_deadline(deadline)

        if self.is_threefold_repetition() or self.halfmove_clock >= 100:
            return 0

        if self.tablebase is not None:
            tablebase_score = self.evaluate(self)
            if abs(tablebase_score) >= 100000:
                return tablebase_score

        if depth <= 0:
            return self.quiescence(alpha, beta, deadline)

        transposition_key = (
            self._position_key(),
            depth,
            self.halfmove_clock,
            self.repetition_counts.get(self._position_key(), 0),
        )
        cached_score = self.transposition_table.get(transposition_key)
        if cached_score is not None:
            return cached_score

        moves = self.order_moves(self.get_legal_moves())

        if not moves:
            if self.is_in_check(self.current_turn):
                if self.current_turn:
                    return 100000 + depth
                else:
                    return -100000 - depth

            return 0

        cutoff = False
        if self.current_turn:
            best_score = float("inf")

            for move in moves:
                self._check_deadline(deadline)
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta, deadline)
                best_score = min(best_score, score)
                beta = min(beta, best_score)

                if beta <= alpha:
                    cutoff = True
                    key = (
                        move.from_row,
                        move.from_column,
                        move.to_row,
                        move.to_column
                    )
                    self.history[key] = self.history.get(key, 0) + depth * depth
                    break

        else:
            best_score = float("-inf")

            for move in moves:
                self._check_deadline(deadline)
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta, deadline)
                best_score = max(best_score, score)
                alpha = max(alpha, best_score)

                if beta <= alpha:
                    cutoff = True
                    key = (
                        move.from_row,
                        move.from_column,
                        move.to_row,
                        move.to_column
                    )
                    self.history[key] = self.history.get(key, 0) + depth * depth
                    break

        if not cutoff:
            self.transposition_table[transposition_key] = best_score
            while len(self.transposition_table) > self.transposition_table_limit:
                self.transposition_table.pop(next(iter(self.transposition_table)))
        return best_score

    def quiescence(self, alpha, beta, deadline=None, remaining_depth=2):
        """Resolve forcing captures before accepting a leaf evaluation."""
        self._check_deadline(deadline)
        legal_moves = self.get_legal_moves()
        in_check = self.is_in_check(self.current_turn)

        if not legal_moves:
            if in_check:
                return 100000 if self.current_turn else -100000
            return 0

        if self.is_threefold_repetition() or self.halfmove_clock >= 100:
            return 0

        if not in_check:
            stand_pat = self.evaluate(self)
            if self.current_turn:
                beta = min(beta, stand_pat)
                if beta <= alpha or remaining_depth <= 0:
                    return stand_pat
            else:
                alpha = max(alpha, stand_pat)
                if beta <= alpha or remaining_depth <= 0:
                    return stand_pat

        if in_check:
            # A checked side has no stand-pat option: every legal evasion,
            # including king moves, must be searched even at the qsearch limit.
            tactical_moves = legal_moves
        else:
            tactical_moves = [
                move for move in legal_moves
                if (
                    (
                        self.board[move.to_row][move.to_column] != ""
                        and self.board[move.to_row][move.to_column].type != "k"
                    )
                    or move.promotion is not None
                    or self.is_en_passant(move)
                )
            ]

        if not tactical_moves:
            return self.evaluate(self)

        tactical_moves = self.order_moves(tactical_moves)
        if self.current_turn:
            best_score = float("inf")
            for move in tactical_moves:
                self._check_deadline(deadline)
                child = self.copy()
                child.move(move)
                best_score = min(
                    best_score,
                    child.quiescence(
                        alpha, beta, deadline, remaining_depth - 1
                    ),
                )
                beta = min(beta, best_score)
                if beta <= alpha:
                    break
            return best_score

        best_score = float("-inf")
        for move in tactical_moves:
            self._check_deadline(deadline)
            child = self.copy()
            child.move(move)
            best_score = max(
                best_score,
                child.quiescence(
                    alpha, beta, deadline, remaining_depth - 1
                ),
            )
            alpha = max(alpha, best_score)
            if beta <= alpha:
                break
        return best_score

    def is_losing_for_side_to_move(self):
        """Return whether the static evaluation is clearly unfavorable."""
        score = self.evaluate(self)
        return (self.current_turn and score > 250) or (
            not self.current_turn and score < -250
        )


    def order_moves(self, moves):
        def move_value(move):

            from_piece = self.board[move.from_row][move.from_column]
            to_piece = self.board[move.to_row][move.to_column]
            piece_values = {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9, "k": 0}
            score = 0
            if to_piece != "":
                score += 1000 + (piece_values[to_piece.piece.lower()] * 10 - piece_values[from_piece.piece.lower()])

            if move.promotion is not None:
                promoted_value = {"q": 9, "r": 5, "b": 3, "n": 3}.get(
                    move.promotion.lower(), 0
                )
                score += 800 + promoted_value * 10

            if self.is_en_passant(move):
                score += 1000 + 10 - piece_values["p"]

            if self.is_endgame():
                score += self._endgame_move_bonus(move)

            key = (move.from_row, move.from_column, move.to_row, move.to_column)
            score += self.history.get(key, 0)
            return score

        return sorted(moves, key=move_value, reverse=True)

    @staticmethod
    def _move_key(move):
        return (
            move.from_row,
            move.from_column,
            move.to_row,
            move.to_column,
            move.promotion,
        )



    def is_in_check(self, color):

        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]

                if (
                    piece != ""
                    and piece.type == "k"
                    and piece.color == color
                ):
                    enemy_color = not color

                    return self.is_square_attacked(
                        row,
                        column,
                        enemy_color
                    )

        raise ValueError("König nicht gefunden")


    def is_square_attacked(self, row, column, by_color):
        for from_row in range(8):
            for from_column in range(8):
                piece = self.board[from_row][from_column]

                if piece == "" or piece.color != by_color:
                    continue

                # Bauern greifen diagonal an
                if piece.type == "p":
                    direction = 1 if piece.color is False else -1

                    if (
                        row == from_row + direction
                        and abs(column - from_column) == 1
                    ):
                        return True

                    continue

                move = Move(
                    chr(ord("a") + from_column) + str(8 - from_row),
                    chr(ord("a") + column) + str(8 - row)
                )

                if piece.is_legal_move(self, move):
                    return True

        return False

    def is_checkmate(self, color):
        if not self.is_in_check(color):
            return False

        old_turn = self.current_turn
        self.current_turn = color

        try:
            return len(self.get_legal_moves()) == 0
        finally:
            self.current_turn = old_turn


    def load_fen(self, fen: str) -> None:
        parts = fen.split()

        if len(parts) != 6:
            raise ValueError("FEN must have exactly 6 fields")

        position, turn, castling, en_passant, halfmove, fullmove = parts
        ranks = position.split("/")

        if len(ranks) != 8:
            raise ValueError("FEN must have exactly 8 rows")

        new_board = []

        valid_pieces = set("pnbrqkPNBRQK")

        for rank in ranks:
            row = []

            for char in rank:
                if char in "12345678":
                    row.extend([""] * int(char))
                elif char in valid_pieces:
                    row.append(Piece(char))
                else:
                    raise ValueError(f"Invalid FEN-Piece: {char}")

            if len(row) != 8:
                raise ValueError("Every FEN-Row must have 8 fields")

            new_board.append(row)

        if turn not in ("w", "b"):
            raise ValueError("Invalid Move Color")

        if castling != "-" and (
            any(char not in "KQkq" for char in castling)
            or len(set(castling)) != len(castling)
        ):
            raise ValueError("Invalid Castling Rights")

        if en_passant != "-" and (
            len(en_passant) != 2
            or en_passant[0] not in "abcdefgh"
            or en_passant[1] not in "36"
        ):
            raise ValueError("Invalid En-passant-Field")

        try:
            halfmove_number = int(halfmove)
            fullmove_number = int(fullmove)
        except ValueError:
            raise ValueError("Invalid Move Counter") from None

        if halfmove_number < 0 or fullmove_number < 1:
            raise ValueError("Invalid Move Counter")

        self.board = new_board
        self.current_turn = turn == "w"
        self.castling_rights = castling
        self.en_passant_square = en_passant
        self.halfmove_clock = halfmove_number
        self.fullmove_number = fullmove_number
        self.repetition_counts = {}
        self._record_position()

    def to_fen(self) -> str:
        """Return the current position in standard Forsyth-Edwards notation."""
        rows = []
        for row in self.board:
            empty = 0
            notation = []
            for piece in row:
                if piece == "":
                    empty += 1
                else:
                    if empty:
                        notation.append(str(empty))
                        empty = 0
                    notation.append(piece.piece)
            if empty:
                notation.append(str(empty))
            rows.append("".join(notation))

        return " ".join(
            (
                "/".join(rows),
                "w" if self.current_turn else "b",
                self.castling_rights or "-",
                self.en_passant_square,
                str(self.halfmove_clock),
                str(self.fullmove_number),
            )
        )
