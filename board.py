from move import Move
from piece import Piece
import piece_square_tables as tables


class Board:

    def __init__(self):
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
            self.current_turn = not self.current_turn
            return True

        if not from_piece.is_legal_move(self, move):
            return False
        
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
        self.current_turn = not self.current_turn

        return True

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
        new_board = Board()

        new_board.board = [row[:] for row in self.board]
        new_board.current_turn = self.current_turn

        new_board.castling_rights = self.castling_rights
        new_board.en_passant_square = self.en_passant_square
        new_board.halfmove_clock = self.halfmove_clock
        new_board.fullmove_number = self.fullmove_number

        new_board.history = self.history.copy()

        return new_board

    def find_mate_in_one(self):
        for move in self.get_legal_moves():
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



    def evaluate(self, board):
        return board.get_material_score() + board.get_position_score()
    

    def best_move(self, depth):
        moves = self.order_moves(self.get_legal_moves())

        if not moves:
            return None

        mate_move = self.find_mate_in_one()

        if mate_move is not None:
            return mate_move

        best_move = None
        alpha = float("-inf")
        beta = float("inf")

        if self.current_turn:
            best_score = float("inf")
        else:
            best_score = float("-inf") 

        for move in moves:
            child = self.copy()
            child.move(move)

            score = child.minimax(depth, alpha, beta)

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


    def minimax(self, depth, alpha=float("-inf"), beta=float("inf")):
        if depth == 0:
            return self.evaluate(self)

        moves = self.order_moves(self.get_legal_moves())

        if not moves:
            if self.is_in_check(self.current_turn):
                if self.current_turn:
                    return 100000 + depth
                else:
                    return -100000 - depth

            return 0

        if self.current_turn:
            best_score = float("inf")

            for move in moves:
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta)
                best_score = min(best_score, score)
                beta = min(beta, best_score)

                if beta <= alpha:
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
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta)
                best_score = max(best_score, score)
                alpha = max(alpha, best_score)

                if beta <= alpha:
                    key = (
                        move.from_row,
                        move.from_column,
                        move.to_row,
                        move.to_column
                    )
                    self.history[key] = self.history.get(key, 0) + depth * depth
                    break

        return best_score


    def order_moves(self, moves):
        def move_value(move):

            from_piece = self.board[move.from_row][move.from_column]
            to_piece = self.board[move.to_row][move.to_column]
            
            score = 0
            if to_piece != "":
                piece_values = {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9, "k": 0}
                score += 1000 + (piece_values[to_piece.piece.lower()] * 10 - piece_values[from_piece.piece.lower()])
            
            key = (move.from_row, move.from_column, move.to_row, move.to_column)
            score += self.history.get(key, 0)
            return score

        return sorted(moves, key=move_value, reverse=True)



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
