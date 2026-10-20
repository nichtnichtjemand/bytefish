from std.collections import List, Optional
from std.time import monotonic
from std.python import Python, PythonObject

from move import Move
from piece import Piece
import piece_square_tables as tables


comptime INF = 1_000_000
comptime MATE_SCORE = 100_000


struct KingPos(Copyable, ImplicitlyCopyable, Movable):
    var row: Int
    var column: Int

    def __init__(out self, row: Int, column: Int):
        self.row = row
        self.column = column


struct Board:
    var current_turn: Bool
    var board: List[List[Piece]]
    var castling_rights: String
    var en_passant_square: String
    var halfmove_clock: Int
    var fullmove_number: Int
    var repetition_counts: List[String]
    var last_search_score: Int
    var last_search_nodes: Int

    def __init__(out self, empty: Bool = False) raises:
        self.current_turn = True
        self.board = List[List[Piece]]()
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self.repetition_counts = List[String]()
        self.last_search_score = 0
        self.last_search_nodes = 0
        if not empty:
            self.reset()

    def reset(mut self) raises:
        self.board = List[List[Piece]]()

        var setup = List[String]()
        setup.append("rnbqkbnr")
        setup.append("pppppppp")
        setup.append("........")
        setup.append("........")
        setup.append("........")
        setup.append("........")
        setup.append("PPPPPPPP")
        setup.append("RNBQKBNR")

        for row in range(8):
            var current_row = List[Piece]()
            for column in range(8):
                var character = String(setup[row][byte=column])
                if character == ".":
                    current_row.append(Piece(""))
                else:
                    current_row.append(Piece(character))
            self.board.append(current_row^)

        self.current_turn = True
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self.repetition_counts = List[String]()
        self._record_position()

    def copy(self) raises -> Board:
        # Search creates a board copy at nearly every node. Skip constructing
        # and then throwing away the initial position in that hot path.
        var result = Board(True)
        result.board = List[List[Piece]]()

        for row in range(8):
            result.board.append(self.board[row].copy())

        result.current_turn = self.current_turn
        result.castling_rights = self.castling_rights
        result.en_passant_square = self.en_passant_square
        result.halfmove_clock = self.halfmove_clock
        result.fullmove_number = self.fullmove_number
        result.repetition_counts = self.repetition_counts.copy()
        result.last_search_score = self.last_search_score
        result.last_search_nodes = self.last_search_nodes

        return result^

    def _set_square(mut self, row: Int, column: Int, piece: Piece):
        self.board[row][column] = piece

    def _inside(self, row: Int, column: Int) -> Bool:
        return row >= 0 and row < 8 and column >= 0 and column < 8

    def _square_name(self, row: Int, column: Int) -> String:
        var file = String(chr(97 + column))
        var rank = String(chr(56 - row))
        return file + rank

    def _find_king(self, color: Bool) -> Optional[KingPos]:
        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if (
                    piece.piece != ""
                    and piece.type == "k"
                    and piece.color == color
                ):
                    return Optional(KingPos(row, column))
        return None

    def _ray_attacked(
        self,
        row: Int,
        column: Int,
        by_color: Bool,
        row_step: Int,
        column_step: Int,
        diagonal: Bool,
    ) -> Bool:
        var scan_row = row + row_step
        var scan_column = column + column_step
        while self._inside(scan_row, scan_column):
            var piece = self.board[scan_row][scan_column]
            if piece.piece != "":
                if piece.color == by_color:
                    if piece.type == "q":
                        return True
                    if diagonal and piece.type == "b":
                        return True
                    if not diagonal and piece.type == "r":
                        return True
                return False
            scan_row += row_step
            scan_column += column_step
        return False

    def is_square_attacked(self, row: Int, column: Int, by_color: Bool) -> Bool:
        # Test the limited-range pieces by looking outward from the target,
        # then walk only the eight rays for sliders. This avoids scanning all
        # 64 squares on every king-safety check in move generation.
        var pawn_row = row + 1
        if not by_color:
            pawn_row = row - 1
        if self._inside(pawn_row, column - 1):
            var pawn = self.board[pawn_row][column - 1]
            if pawn.piece != "" and pawn.color == by_color and pawn.type == "p":
                return True
        if self._inside(pawn_row, column + 1):
            var pawn = self.board[pawn_row][column + 1]
            if pawn.piece != "" and pawn.color == by_color and pawn.type == "p":
                return True

        for row_offset in range(-2, 3):
            for column_offset in range(-2, 3):
                if abs(row_offset) * abs(column_offset) != 2:
                    continue
                var source_row = row + row_offset
                var source_column = column + column_offset
                if self._inside(source_row, source_column):
                    var attacker = self.board[source_row][source_column]
                    if (
                        attacker.piece != ""
                        and attacker.color == by_color
                        and attacker.type == "n"
                    ):
                        return True

        for row_offset in range(-1, 2):
            for column_offset in range(-1, 2):
                if row_offset == 0 and column_offset == 0:
                    continue
                var source_row = row + row_offset
                var source_column = column + column_offset
                if self._inside(source_row, source_column):
                    var attacker = self.board[source_row][source_column]
                    if (
                        attacker.piece != ""
                        and attacker.color == by_color
                        and attacker.type == "k"
                    ):
                        return True

        for row_step in range(-1, 2):
            for column_step in range(-1, 2):
                if row_step == 0 and column_step == 0:
                    continue
                var diagonal = row_step != 0 and column_step != 0
                if self._ray_attacked(
                    row, column, by_color, row_step, column_step, diagonal
                ):
                    return True
        return False

    def _path_clear(
        self,
        from_row: Int,
        from_column: Int,
        to_row: Int,
        to_column: Int,
    ) -> Bool:
        var row_step = 0
        var column_step = 0

        if to_row > from_row:
            row_step = 1
        elif to_row < from_row:
            row_step = -1

        if to_column > from_column:
            column_step = 1
        elif to_column < from_column:
            column_step = -1

        var row = from_row + row_step
        var column = from_column + column_step

        while row != to_row or column != to_column:
            if self.board[row][column].piece != "":
                return False

            row += row_step
            column += column_step

        return True

    def is_in_check(self, color: Bool) -> Bool:
        var king = self._find_king(color)
        if not king:
            return True

        var position = king.value()
        return self.is_square_attacked(position.row, position.column, not color)

    def is_en_passant(self, move: Move) -> Bool:
        if self.en_passant_square == "-":
            return False

        if move.to_field != self.en_passant_square:
            return False

        var piece = self.board[move.from_row][move.from_column]
        if piece.piece == "" or piece.type != "p":
            return False

        return (
            move.from_column != move.to_column
            and self.board[move.to_row][move.to_column].piece == ""
        )

    def _can_castle(self, move: Move) -> Bool:
        var piece = self.board[move.from_row][move.from_column]

        if piece.piece == "" or piece.type != "k":
            return False

        if move.from_column != 4 or move.to_row != move.from_row:
            return False

        if move.to_column == 6:
            if piece.color:
                if "K" not in self.castling_rights:
                    return False
            else:
                if "k" not in self.castling_rights:
                    return False

            if (
                self.board[move.from_row][5].piece != ""
                or self.board[move.from_row][6].piece != ""
            ):
                return False

            if self.is_in_check(piece.color):
                return False

            if self.is_square_attacked(move.from_row, 5, not piece.color):
                return False

            if self.is_square_attacked(move.from_row, 6, not piece.color):
                return False

            return True

        if move.to_column == 2:
            if piece.color:
                if "Q" not in self.castling_rights:
                    return False
            else:
                if "q" not in self.castling_rights:
                    return False

            if (
                self.board[move.from_row][1].piece != ""
                or self.board[move.from_row][2].piece != ""
                or self.board[move.from_row][3].piece != ""
            ):
                return False

            if self.is_in_check(piece.color):
                return False

            if self.is_square_attacked(move.from_row, 3, not piece.color):
                return False

            if self.is_square_attacked(move.from_row, 2, not piece.color):
                return False

            return True

        return False

    def _remove_castling_rights(mut self, piece: Piece) raises:
        if piece.piece == "K":
            self.castling_rights = self.castling_rights.replace("K", "")
            self.castling_rights = self.castling_rights.replace("Q", "")
        elif piece.piece == "k":
            self.castling_rights = self.castling_rights.replace("k", "")
            self.castling_rights = self.castling_rights.replace("q", "")

    def _update_castling_rights(
        mut self, move: Move, from_piece: Piece, to_piece: Piece
    ) raises:
        self._remove_castling_rights(from_piece)

        if from_piece.piece == "R":
            if move.from_row == 7 and move.from_column == 0:
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif move.from_row == 7 and move.from_column == 7:
                self.castling_rights = self.castling_rights.replace("K", "")

        elif from_piece.piece == "r":
            if move.from_row == 0 and move.from_column == 0:
                self.castling_rights = self.castling_rights.replace("q", "")
            elif move.from_row == 0 and move.from_column == 7:
                self.castling_rights = self.castling_rights.replace("k", "")

        if to_piece.piece == "R":
            if move.to_row == 7 and move.to_column == 0:
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif move.to_row == 7 and move.to_column == 7:
                self.castling_rights = self.castling_rights.replace("K", "")

        elif to_piece.piece == "r":
            if move.to_row == 0 and move.to_column == 0:
                self.castling_rights = self.castling_rights.replace("q", "")
            elif move.to_row == 0 and move.to_column == 7:
                self.castling_rights = self.castling_rights.replace("k", "")

        if self.castling_rights == "":
            self.castling_rights = "-"

    def _finish_move(
        mut self,
        move: Move,
        from_piece: Piece,
        to_piece: Piece,
        is_capture: Bool,
    ) raises:
        var previous_castling_rights = self.castling_rights
        self._update_castling_rights(move, from_piece, to_piece)

        self.en_passant_square = "-"

        if from_piece.type == "p" and (
            move.to_row - move.from_row == 2 or move.from_row - move.to_row == 2
        ):
            self.en_passant_square = self._square_name(
                (move.from_row + move.to_row) // 2,
                move.from_column,
            )

        if from_piece.type == "p" or is_capture:
            self.halfmove_clock = 0
        else:
            self.halfmove_clock += 1

        if not self.current_turn:
            self.fullmove_number += 1

        self.current_turn = not self.current_turn
        # Positions before a pawn move, capture, or castling-right loss can
        # never recur. Keeping only the reversible suffix makes repetition
        # checks and board copies cheaper without changing draw detection.
        if (
            from_piece.type == "p"
            or is_capture
            or self.castling_rights != previous_castling_rights
        ):
            self.repetition_counts = List[String]()
        self._record_position()

    def move(mut self, move: Move) raises -> Bool:
        if not self._inside(
            move.from_row, move.from_column
        ) or not self._inside(move.to_row, move.to_column):
            return False

        var from_piece = self.board[move.from_row][move.from_column]
        var to_piece = self.board[move.to_row][move.to_column]

        if from_piece.piece == "" or from_piece.color != self.current_turn:
            return False

        if to_piece.piece != "" and to_piece.color == self.current_turn:
            return False

        var legal_moves = self.get_legal_moves()
        var found = False

        for candidate in legal_moves:
            if (
                candidate.from_field == move.from_field
                and candidate.to_field == move.to_field
                and candidate.promotion == move.promotion
            ):
                found = True
                break

        if not found:
            return False

        var is_capture = to_piece.piece != ""
        var en_passant = self.is_en_passant(move)

        if en_passant:
            is_capture = True
            var captured_row = move.to_row + 1
            if not from_piece.color:
                captured_row = move.to_row - 1
            self._set_square(captured_row, move.to_column, Piece(""))

        self._set_square(move.to_row, move.to_column, from_piece)
        self._set_square(move.from_row, move.from_column, Piece(""))

        if from_piece.type == "k" and (
            move.to_column - move.from_column == 2
            or move.from_column - move.to_column == 2
        ):
            if move.to_column == 6:
                var rook = Piece(self.board[move.from_row][7].piece)
                self._set_square(move.from_row, 5, rook)
                self._set_square(move.from_row, 7, Piece(""))
            else:
                var rook = Piece(self.board[move.from_row][0].piece)
                self._set_square(move.from_row, 3, rook)
                self._set_square(move.from_row, 0, Piece(""))

        if from_piece.type == "p" and (move.to_row == 0 or move.to_row == 7):
            var promotion_piece = String("q")
            if move.promotion:
                promotion_piece = move.promotion.value()

            if promotion_piece == "n":
                promotion_piece = "n"
            elif promotion_piece == "b":
                promotion_piece = "b"
            elif promotion_piece == "r":
                promotion_piece = "r"
            else:
                promotion_piece = "q"

            if from_piece.color:
                promotion_piece = promotion_piece.upper()

            self._set_square(
                move.to_row, move.to_column, Piece(promotion_piece)
            )

        self._finish_move(move, from_piece, to_piece, is_capture)
        return True

    def get_legal_moves(self) raises -> List[Move]:
        var result = List[Move]()
        var promotion_types = List[String]()
        promotion_types.append("q")
        promotion_types.append("r")
        promotion_types.append("b")
        promotion_types.append("n")

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]

                if piece.piece == "" or piece.color != self.current_turn:
                    continue

                var candidates = piece.get_candidate_moves(self, row, column)

                for candidate in candidates:
                    if not piece.is_legal_move(self, candidate):
                        continue

                    if piece.type == "p" and (
                        candidate.to_row == 0 or candidate.to_row == 7
                    ):
                        for promotion in promotion_types:
                            var promoted_move = Move(
                                candidate.from_field,
                                candidate.to_field,
                                Optional(promotion),
                            )
                            var promoted_child = self.copy()
                            if promoted_child._apply_unchecked(promoted_move):
                                if not promoted_child.is_in_check(
                                    self.current_turn
                                ):
                                    result.append(promoted_move)
                    else:
                        var child = self.copy()
                        if child._apply_unchecked(candidate):
                            if not child.is_in_check(self.current_turn):
                                result.append(candidate)

                if piece.type == "k":
                    var kingside = Move(
                        self._square_name(row, column),
                        self._square_name(row, 6),
                    )
                    if self._can_castle(kingside):
                        result.append(kingside)

                    var queenside = Move(
                        self._square_name(row, column),
                        self._square_name(row, 2),
                    )
                    if self._can_castle(queenside):
                        result.append(queenside)

        return result^

    def _apply_unchecked(mut self, move: Move) raises -> Bool:
        if not self._inside(
            move.from_row, move.from_column
        ) or not self._inside(move.to_row, move.to_column):
            return False

        var piece = self.board[move.from_row][move.from_column]
        if piece.piece == "":
            return False

        var promotion_piece = String("")
        if piece.type == "p" and (move.to_row == 0 or move.to_row == 7):
            if not move.promotion:
                return False
            promotion_piece = move.promotion.value().lower()
            if (
                promotion_piece != "q"
                and promotion_piece != "r"
                and promotion_piece != "b"
                and promotion_piece != "n"
            ):
                return False

        var target = self.board[move.to_row][move.to_column]
        var capture = target.piece != ""
        var ep = self.is_en_passant(move)

        if ep:
            var captured_row = move.to_row + 1
            if not piece.color:
                captured_row = move.to_row - 1
            self._set_square(captured_row, move.to_column, Piece(""))
            capture = True

        self._set_square(move.to_row, move.to_column, piece)
        self._set_square(move.from_row, move.from_column, Piece(""))

        if piece.type == "k" and (
            move.to_column - move.from_column == 2
            or move.from_column - move.to_column == 2
        ):
            if move.to_column == 6:
                var rook = Piece(self.board[move.from_row][7].piece)
                self._set_square(move.from_row, 5, rook)
                self._set_square(move.from_row, 7, Piece(""))
            else:
                var rook = Piece(self.board[move.from_row][0].piece)
                self._set_square(move.from_row, 3, rook)
                self._set_square(move.from_row, 0, Piece(""))

        if promotion_piece != "":
            if piece.color:
                promotion_piece = promotion_piece.upper()
            self._set_square(
                move.to_row, move.to_column, Piece(promotion_piece)
            )

        self._finish_move(move, piece, target, capture)
        return True

    def get_material_score(self) -> Int:
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue

                var value = tables.mg_value(piece.type)

                if piece.color:
                    score -= value
                else:
                    score += value

        return score

    def get_position_score(self) -> Int:
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue

                var table_row = row
                if piece.color:
                    table_row = 7 - row
                var bonus = tables.mg_piece_square_bonus(
                    piece.type, table_row, column
                )

                if piece.color:
                    score -= bonus
                else:
                    score += bonus

        return score

    def _get_tapered_material_position_score(self) -> Int:
        var white_mg = 0
        var black_mg = 0
        var white_eg = 0
        var black_eg = 0
        var game_phase = 0

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue

                var table_row = row
                if piece.color:
                    table_row = 7 - row

                var mg_score = (
                    tables.mg_value(piece.type)
                    + tables.mg_piece_square_bonus(
                        piece.type, table_row, column
                    )
                )
                var eg_score = (
                    tables.eg_value(piece.type)
                    + tables.eg_piece_square_bonus(
                        piece.type, table_row, column
                    )
                )

                if piece.color:
                    white_mg += mg_score
                    white_eg += eg_score
                else:
                    black_mg += mg_score
                    black_eg += eg_score
                game_phase += tables.gamephase_increment(piece.type)

        var mg_phase = min(game_phase, 24)
        var eg_phase = 24 - mg_phase
        # Preserve the engine's current convention: positive scores favor
        # Black, negative scores favor White.
        var mg_total = black_mg - white_mg
        var eg_total = black_eg - white_eg
        var blended = mg_total * mg_phase + eg_total * eg_phase
        if blended < 0:
            return -((-blended) // 24)
        return blended // 24

    def _piece_count(self) -> Int:
        var count = 0
        for row in range(8):
            for column in range(8):
                if self.board[row][column].piece != "":
                    count += 1
        return count

    def is_endgame(self) -> Bool:
        var queens = 0
        var pieces = 0
        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece != "":
                    pieces += 1
                    if piece.type == "q":
                        queens += 1
        return queens == 0 or pieces <= 12

    def is_insufficient_material(self) -> Bool:
        var white_bishops = 0
        var black_bishops = 0
        var white_knights = 0
        var black_knights = 0
        var bishop_square_color = -1
        var bishops_share_square_color = True

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "" or piece.type == "k":
                    continue
                if piece.type == "p" or piece.type == "r" or piece.type == "q":
                    return False
                if piece.type == "n":
                    if piece.color:
                        white_knights += 1
                    else:
                        black_knights += 1
                elif piece.type == "b":
                    if piece.color:
                        white_bishops += 1
                    else:
                        black_bishops += 1
                    var square_color = (row + column) % 2
                    if bishop_square_color < 0:
                        bishop_square_color = square_color
                    elif bishop_square_color != square_color:
                        bishops_share_square_color = False
                else:
                    return False

        var minor_count = (
            white_bishops + black_bishops + white_knights + black_knights
        )
        if minor_count <= 1:
            return True

        return (
            minor_count == 2
            and white_bishops == 1
            and black_bishops == 1
            and white_knights == 0
            and black_knights == 0
            and bishops_share_square_color
        )

    def _is_passed_pawn(self, row: Int, column: Int, color: Bool) -> Bool:
        var direction = -1
        if not color:
            direction = 1

        var scan_row = row + direction

        while scan_row >= 0 and scan_row < 8:
            for offset in range(-1, 2):
                var scan_column = column + offset
                if not self._inside(scan_row, scan_column):
                    continue

                var piece = self.board[scan_row][scan_column]
                if (
                    piece.piece != ""
                    and piece.type == "p"
                    and piece.color != color
                ):
                    return False

            scan_row += direction

        return True

    def get_endgame_score(self) -> Int:
        return self._get_endgame_score(self.is_endgame())

    def _get_endgame_score(self, endgame: Bool) -> Int:
        if not endgame:
            return 0

        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue

                var sign = 1
                if piece.color:
                    sign = -1

                if piece.type == "p":
                    var rank = 7 - row
                    if not piece.color:
                        rank = row
                    score += sign * rank * 8
                    if self._is_passed_pawn(row, column, piece.color):
                        score += sign * (35 + rank * 12)
                        var king_distance = self._distance_to_king(
                            row, column, piece.color
                        )
                        score += sign * max(0, 24 - king_distance * 4)
                elif piece.type == "r":
                    for pawn_row in range(8):
                        var pawn = self.board[pawn_row][column]
                        if (
                            pawn.piece == ""
                            or pawn.type != "p"
                            or not self._is_passed_pawn(
                                pawn_row, column, pawn.color
                            )
                        ):
                            continue

                        var behind = False
                        if pawn.color and row > pawn_row:
                            behind = True
                        elif not pawn.color and row < pawn_row:
                            behind = True
                        if behind:
                            var path_clear = True
                            var step = 1
                            if row < pawn_row:
                                step = -1
                            var scan_row = pawn_row + step
                            while scan_row != row:
                                if self.board[scan_row][column].piece != "":
                                    path_clear = False
                                    break
                                scan_row += step
                            if path_clear:
                                score += sign * 20
                                break

        return score

    def _distance_to_king(self, row: Int, column: Int, color: Bool) -> Int:
        var king = self._find_king(color)
        if not king:
            return 8
        var position = king.value()
        return max(abs(row - position.row), abs(column - position.column))

    def get_hanging_piece_score(self) -> Int:
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "" or piece.type == "k":
                    continue

                if self.is_square_attacked(row, column, not piece.color):
                    var defended = self.is_square_attacked(
                        row, column, piece.color
                    )

                    if not defended:
                        var penalty = 0
                        if piece.type == "p":
                            penalty = 50
                        elif piece.type == "n":
                            penalty = 150
                        elif piece.type == "b":
                            penalty = 160
                        elif piece.type == "r":
                            penalty = 250
                        elif piece.type == "q":
                            penalty = 450

                        if piece.color:
                            score += penalty
                        else:
                            score -= penalty

        return score

    def get_pawn_structure_score(self) -> Int:
        var score = 0
        var white_pawns_by_file = List[Int]()
        var black_pawns_by_file = List[Int]()
        for _ in range(8):
            white_pawns_by_file.append(0)
            black_pawns_by_file.append(0)

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece != "" and piece.type == "p":
                    if piece.color:
                        white_pawns_by_file[column] += 1
                    else:
                        black_pawns_by_file[column] += 1

        for column in range(8):
            var white_pawns = white_pawns_by_file[column]
            var black_pawns = black_pawns_by_file[column]

            if white_pawns > 1:
                score += (white_pawns - 1) * 12
            if black_pawns > 1:
                score -= (black_pawns - 1) * 12

            if white_pawns > 0:
                var isolated = (
                    (column == 0 or white_pawns_by_file[column - 1] == 0)
                    and (column == 7 or white_pawns_by_file[column + 1] == 0)
                )
                if isolated:
                    score += white_pawns * 14

            if black_pawns > 0:
                var isolated = (
                    (column == 0 or black_pawns_by_file[column - 1] == 0)
                    and (column == 7 or black_pawns_by_file[column + 1] == 0)
                )
                if isolated:
                    score -= black_pawns * 14

        return score

    def get_mobility_score(self) raises -> Int:
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue

                var weight = 0
                if piece.type == "n" or piece.type == "b":
                    weight = 4
                elif piece.type == "r":
                    weight = 2
                elif piece.type == "q" or piece.type == "k":
                    weight = 1

                if weight > 0:
                    var candidates = piece.get_candidate_moves(
                        self, row, column
                    )
                    var mobility = 0
                    for move in candidates:
                        var target = self.board[move.to_row][move.to_column]
                        if target.piece == "" or target.color != piece.color:
                            mobility += 1
                    var bonus = mobility * weight
                    if piece.color:
                        score -= bonus
                    else:
                        score += bonus

        return score

    def get_king_safety_score(self) -> Int:
        var has_queen = False
        var white_king: Optional[KingPos] = None
        var black_king: Optional[KingPos] = None
        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue
                if piece.type == "q":
                    has_queen = True
                elif piece.type == "k":
                    if piece.color:
                        white_king = Optional(KingPos(row, column))
                    else:
                        black_king = Optional(KingPos(row, column))
        if not has_queen:
            return 0

        var score = 0

        for color_index in range(2):
            var color = color_index == 1
            var king = white_king
            if not color:
                king = black_king
            if not king:
                continue

            var position = king.value()
            var row = position.row
            var column = position.column
            var shield = 0
            for offset in range(-1, 2):
                var pawn_column = column + offset
                var pawn_row = row - 1 if color else row + 1

                if self._inside(pawn_row, pawn_column):
                    var pawn = self.board[pawn_row][pawn_column]
                    if (
                        pawn.piece != ""
                        and pawn.type == "p"
                        and pawn.color == color
                    ):
                        shield += 1

            if color:
                score -= shield * 12
            else:
                score += shield * 12

        return score

    def evaluate(self) raises -> Int:
        return (
            self._get_tapered_material_position_score()
            + self.get_endgame_score()
            + self.get_hanging_piece_score()
            + self.get_pawn_structure_score()
            + self.get_mobility_score()
            + self.get_king_safety_score()
        )

    def _position_key(self) -> String:
        var result = String("")
        for row in range(8):
            var empty_count = 0
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    empty_count += 1
                else:
                    if empty_count > 0:
                        result += String(empty_count)
                        empty_count = 0
                    result += piece.piece
            if empty_count > 0:
                result += String(empty_count)
            if row < 7:
                result += "/"

        result += " "
        if self.current_turn:
            result += "w"
        else:
            result += "b"
        result += " " + self.castling_rights + " " + self.en_passant_square
        return result

    def _record_position(mut self) raises:
        var key = self._position_key()
        self.repetition_counts.append(key)

    def is_threefold_repetition(self) -> Bool:
        var current = self._position_key()
        var count = 0

        for key in self.repetition_counts:
            if key == current:
                count += 1
                if count == 3:
                    return True

        return False

    def is_checkmate(self, color: Bool) raises -> Bool:
        if not self.is_in_check(color):
            return False

        if color == self.current_turn:
            return len(self.get_legal_moves()) == 0

        var child = self.copy()
        child.current_turn = color
        return len(child.get_legal_moves()) == 0

    def is_stalemate(self) raises -> Bool:
        if self.is_in_check(self.current_turn):
            return False
        return len(self.get_legal_moves()) == 0

    def find_mate_in_one(mut self) raises -> Optional[Move]:
        var moves = self.get_legal_moves()
        var tested_moves = 0

        for move in moves:
            var child = self.copy()
            if child._apply_unchecked(move):
                tested_moves += 1
                if child.is_checkmate(child.current_turn):
                    self.last_search_nodes += tested_moves
                    return Optional(move)

        self.last_search_nodes += tested_moves
        return None

    def order_moves(self, moves: List[Move]) raises -> List[Move]:
        var ordered = List[Move]()
        var remaining = moves.copy()
        var scores = List[Int]()
        var endgame = self.is_endgame()

        # Compute each move's expensive positional score once. The previous
        # selection loop recalculated endgame and passed-pawn features every
        # time it compared a move with the remaining list.
        for move in remaining:
            var score = 0
            var target = self.board[move.to_row][move.to_column]
            var moving_piece = self.board[move.from_row][move.from_column]

            if target.piece != "":
                var victim_value = 0
                var attacker_value = 0
                if target.type == "p":
                    victim_value = 1
                elif target.type == "n" or target.type == "b":
                    victim_value = 3
                elif target.type == "r":
                    victim_value = 5
                elif target.type == "q":
                    victim_value = 9

                if moving_piece.type == "p":
                    attacker_value = 1
                elif moving_piece.type == "n" or moving_piece.type == "b":
                    attacker_value = 3
                elif moving_piece.type == "r":
                    attacker_value = 5
                elif moving_piece.type == "q":
                    attacker_value = 9
                score += 1000 + victim_value * 10 - attacker_value

            if move.promotion:
                var promotion = move.promotion.value().lower()
                if promotion == "q":
                    score += 900
                elif promotion == "r":
                    score += 500
                elif promotion == "b" or promotion == "n":
                    score += 300

            if self.is_en_passant(move):
                score += 1000 + 10 - 1

            if endgame:
                if moving_piece.type == "p":
                    if move.to_row == 0 or move.to_row == 7:
                        score += 900
                    elif self._is_passed_pawn(
                        move.from_row,
                        move.from_column,
                        moving_piece.color,
                    ):
                        score += 120
                elif moving_piece.type == "k":
                    var old_distance = abs(
                        Float64(move.from_row) - 3.5
                    ) + abs(Float64(move.from_column) - 3.5)
                    var new_distance = abs(
                        Float64(move.to_row) - 3.5
                    ) + abs(Float64(move.to_column) - 3.5)
                    if new_distance < old_distance:
                        score += 45
            scores.append(score)

        while len(remaining) > 0:
            var best_index = 0
            var best_score = -INF

            for index in range(len(remaining)):
                var score = scores[index]
                if score > best_score:
                    best_score = score
                    best_index = index

            ordered.append(remaining[best_index])
            _ = remaining.pop(best_index)
            _ = scores.pop(best_index)

        return ordered^

    def quiescence(
        mut self,
        alpha: Int,
        beta: Int,
        deadline: Optional[Float64] = None,
        remaining_depth: Int = 2,
    ) raises -> Int:
        Self._check_deadline(deadline)
        self.last_search_nodes = 1

        var drawn = (
            self.is_threefold_repetition()
            or self.halfmove_clock >= 100
            or self.is_insufficient_material()
        )
        if drawn:
            if self.is_in_check(self.current_turn):
                if len(self.get_legal_moves()) == 0:
                    if self.current_turn:
                        return MATE_SCORE
                    return -MATE_SCORE
            return 0

        var in_check = self.is_in_check(self.current_turn)
        var local_alpha = alpha
        var local_beta = beta
        var best_score: Int

        if in_check:
            if self.current_turn:
                best_score = INF
            else:
                best_score = -INF
        else:
            best_score = self.evaluate()
            if remaining_depth <= 0:
                return best_score
            if self.current_turn:
                if best_score < local_beta:
                    local_beta = best_score
                if local_beta <= local_alpha:
                    return best_score
            else:
                if best_score > local_alpha:
                    local_alpha = best_score
                if local_alpha >= local_beta:
                    return best_score

        var moves = self.get_legal_moves()
        if len(moves) == 0:
            if in_check:
                if self.current_turn:
                    return MATE_SCORE
                return -MATE_SCORE
            return best_score

        var tactical_moves = List[Move]()

        for move in moves:
            if in_check:
                tactical_moves.append(move)
            elif (
                (
                    self.board[move.to_row][move.to_column].piece != ""
                    and self.board[move.to_row][move.to_column].type != "k"
                )
                or self.is_en_passant(move)
                or move.promotion
            ):
                tactical_moves.append(move)

        var ordered = self.order_moves(tactical_moves)

        for move in ordered:
            Self._check_deadline(deadline)

            var child = self.copy()
            child.last_search_nodes = 0
            if not child._apply_unchecked(move):
                continue

            var score = child.quiescence(
                local_alpha, local_beta, deadline, remaining_depth - 1
            )
            self.last_search_nodes += child.last_search_nodes

            if self.current_turn:
                if score < best_score:
                    best_score = score
                if score < local_beta:
                    local_beta = score
                if local_beta <= local_alpha:
                    break
            else:
                if score > best_score:
                    best_score = score
                if score > local_alpha:
                    local_alpha = score
                if local_alpha >= local_beta:
                    break

        return best_score

    def minimax(
        mut self,
        depth: Int,
        alpha: Int = -INF,
        beta: Int = INF,
        deadline: Optional[Float64] = None,
    ) raises -> Int:
        Self._check_deadline(deadline)

        # Quiescence already checks repetition, move-count draws and
        # insufficient material, so send horizon nodes there before doing
        # those same tests twice.
        if depth <= 0:
            return self.quiescence(alpha, beta, deadline)

        self.last_search_nodes = 1

        var drawn = (
            self.is_threefold_repetition()
            or self.halfmove_clock >= 100
            or self.is_insufficient_material()
        )
        if drawn:
            if self.is_in_check(self.current_turn):
                if len(self.get_legal_moves()) == 0:
                    if self.current_turn:
                        return MATE_SCORE + depth
                    return -MATE_SCORE - depth
            return 0

        var moves = self.get_legal_moves()

        if len(moves) == 0:
            if self.is_in_check(self.current_turn):
                if self.current_turn:
                    return MATE_SCORE + depth
                return -MATE_SCORE - depth
            return 0

        var ordered = self.order_moves(moves)
        var local_alpha = alpha
        var local_beta = beta
        var best_score: Int

        if self.current_turn:
            best_score = INF

            for move in ordered:
                Self._check_deadline(deadline)
                var child = self.copy()
                child.last_search_nodes = 0

                if not child._apply_unchecked(move):
                    continue

                var score = child.minimax(
                    depth - 1, local_alpha, local_beta, deadline
                )
                self.last_search_nodes += child.last_search_nodes

                if score < best_score:
                    best_score = score

                if best_score < local_beta:
                    local_beta = best_score

                if local_beta <= local_alpha:
                    break
        else:
            best_score = -INF

            for move in ordered:
                Self._check_deadline(deadline)
                var child = self.copy()
                child.last_search_nodes = 0

                if not child._apply_unchecked(move):
                    continue

                var score = child.minimax(
                    depth - 1, local_alpha, local_beta, deadline
                )
                self.last_search_nodes += child.last_search_nodes

                if score > best_score:
                    best_score = score

                if best_score > local_alpha:
                    local_alpha = best_score

                if local_beta <= local_alpha:
                    break

        return best_score

    def best_move(
        mut self,
        depth: Int,
        deadline: Optional[Float64] = None,
        root_moves: Optional[List[Move]] = None,
        preferred_move: Optional[Move] = None,
    ) raises -> Optional[Move]:
        self.last_search_nodes = 0
        Self._check_deadline(deadline)
        self.last_search_nodes = 1
        var moves = self.get_legal_moves()
        if root_moves:
            var allowed = root_moves.value().copy()
            var filtered = List[Move]()
            for move in moves:
                for allowed_move in allowed:
                    if (
                        move.from_field == allowed_move.from_field
                        and move.to_field == allowed_move.to_field
                        and move.promotion == allowed_move.promotion
                    ):
                        filtered.append(move)
                        break
            moves = filtered^

        if len(moves) == 0:
            return None

        if not deadline and not root_moves:
            var mate = self.find_mate_in_one()
            if mate:
                if self.current_turn:
                    self.last_search_score = -MATE_SCORE
                else:
                    self.last_search_score = MATE_SCORE
                return mate

        var ordered = self.order_moves(moves)
        if preferred_move:
            var preferred = preferred_move.value()
            var preferred_first = List[Move]()
            var found_preferred = False
            for move in ordered:
                if (
                    move.from_field == preferred.from_field
                    and move.to_field == preferred.to_field
                    and move.promotion == preferred.promotion
                ):
                    preferred_first.append(move)
                    found_preferred = True
                    break
            if found_preferred:
                for move in ordered:
                    if not (
                        move.from_field == preferred.from_field
                        and move.to_field == preferred.to_field
                        and move.promotion == preferred.promotion
                    ):
                        preferred_first.append(move)
                ordered = preferred_first^
        var best = ordered[0]
        var best_score = INF
        var local_alpha = -INF
        var local_beta = INF

        if not self.current_turn:
            best_score = -INF

        for move in ordered:
            Self._check_deadline(deadline)

            var child = self.copy()
            child.last_search_nodes = 0
            if not child._apply_unchecked(move):
                continue

            var score = child.minimax(
                depth - 1, local_alpha, local_beta, deadline
            )
            self.last_search_nodes += child.last_search_nodes

            if self.current_turn:
                if score < best_score:
                    best_score = score
                    best = move
                if best_score < local_beta:
                    local_beta = best_score
                if local_beta <= local_alpha:
                    break
            else:
                if score > best_score:
                    best_score = score
                    best = move
                if best_score > local_alpha:
                    local_alpha = best_score
                if local_beta <= local_alpha:
                    break

        self.last_search_score = best_score
        return Optional(best)

    def best_move_two_workers(
        mut self,
        depth: Int,
        deadline: Optional[Float64] = None,
        root_moves: Optional[List[Move]] = None,
        preferred_move: Optional[Move] = None,
    ) raises -> Optional[Move]:
        self.last_search_nodes = 0
        var moves = self.get_legal_moves()
        if root_moves:
            var allowed = root_moves.value().copy()
            var filtered = List[Move]()
            for move in moves:
                for allowed_move in allowed:
                    if (
                        move.from_field == allowed_move.from_field
                        and move.to_field == allowed_move.to_field
                        and move.promotion == allowed_move.promotion
                    ):
                        filtered.append(move)
                        break
            moves = filtered^

        if len(moves) < 2:
            return self.best_move(
                depth, deadline, Optional(moves.copy()), preferred_move
            )

        var ordered = self.order_moves(moves)
        var parent_moves = List[Move]()
        var child_moves = List[Move]()
        for index in range(len(ordered)):
            if index % 2 == 0:
                parent_moves.append(ordered[index])
            else:
                child_moves.append(ordered[index])

        var os = Python.import_module("os")
        if String(os.name) != "posix":
            return self.best_move(
                depth, deadline, Optional(moves.copy()), preferred_move
            )

        var pipe = os.pipe()
        var read_fd = Int(py=pipe[0])
        var write_fd = Int(py=pipe[1])
        var child_pid: Int
        try:
            child_pid = Int(py=os.fork())
        except e:
            os.close(read_fd)
            os.close(write_fd)
            return self.best_move(
                depth, deadline, Optional(moves.copy()), preferred_move
            )

        if child_pid == 0:
            os.close(read_fd)
            var payload = String("ERR 0")
            try:
                var child_result = self.best_move(
                    depth, deadline, Optional(child_moves.copy()), preferred_move
                )
                if child_result:
                    var selected = child_result.value()
                    var promotion = String("-")
                    if selected.promotion:
                        promotion = selected.promotion.value()
                    payload = (
                        selected.from_field + " " + selected.to_field + " "
                        + promotion + " " + String(self.last_search_score)
                        + " " + String(self.last_search_nodes)
                    )
            except e:
                payload = "ERR " + String(self.last_search_nodes)

            var encoded = PythonObject(payload).encode()
            _ = os.write(write_fd, encoded)
            os.close(write_fd)
            os._exit(0)
            return None

        os.close(write_fd)
        var parent_result: Optional[Move] = None
        var parent_failed = False
        try:
            parent_result = self.best_move(
                depth, deadline, Optional(parent_moves.copy()), preferred_move
            )
        except e:
            parent_failed = True

        var response = os.read(read_fd, 128)
        os.close(read_fd)
        _ = os.waitpid(child_pid, 0)

        var response_text = String(py=response.decode())
        var response_parts = response_text.split(" ")
        if len(response_parts) == 2 and String(response_parts[0]) == "ERR":
            self.last_search_nodes += Int(String(response_parts[1]))
            raise Error("Search deadline reached")
        if len(response_parts) != 5:
            if parent_failed:
                raise Error("Search deadline reached")
            if parent_result:
                return parent_result
            return None

        var child_nodes = Int(String(response_parts[4]))
        self.last_search_nodes += child_nodes
        if parent_failed:
            raise Error("Search deadline reached")

        var child_move: Move
        var child_promotion = String(response_parts[2])
        if child_promotion == "-":
            child_move = Move(
                String(response_parts[0]), String(response_parts[1])
            )
        else:
            child_move = Move(
                String(response_parts[0]),
                String(response_parts[1]),
                Optional(child_promotion),
            )
        var child_score = Int(String(response_parts[3]))
        if not parent_result:
            self.last_search_score = child_score
            return Optional(child_move)

        if (
            (self.current_turn and child_score < self.last_search_score)
            or (not self.current_turn and child_score > self.last_search_score)
        ):
            self.last_search_score = child_score
            return Optional(child_move)
        return parent_result

    @staticmethod
    def _check_deadline(deadline: Optional[Float64]) raises:
        if deadline:
            if Float64(monotonic()) / 1_000_000_000.0 >= deadline.value():
                raise Error("Search deadline reached")

    def load_fen(mut self, fen: String) raises:
        var parts = fen.split(" ")
        if len(parts) != 6:
            raise Error("FEN must have exactly 6 fields")

        var ranks = String(parts[0]).split("/")
        if len(ranks) != 8:
            raise Error("FEN must have exactly 8 rows")

        var new_board = List[List[Piece]]()

        for rank in ranks:
            var current_row = List[Piece]()

            for character in rank:
                var ch = String(character)
                if ch >= "1" and ch <= "8":
                    var empty_count = Int(ch)
                    for _ in range(empty_count):
                        current_row.append(Piece(""))
                elif (
                    ch == "p"
                    or ch == "n"
                    or ch == "b"
                    or ch == "r"
                    or ch == "q"
                    or ch == "k"
                    or ch == "P"
                    or ch == "N"
                    or ch == "B"
                    or ch == "R"
                    or ch == "Q"
                    or ch == "K"
                ):
                    current_row.append(Piece(ch))
                else:
                    raise Error("Invalid FEN piece")

            if len(current_row) != 8:
                raise Error("Every FEN row must have 8 squares")

            new_board.append(current_row^)

        var active_color = String(parts[1])
        if active_color != "w" and active_color != "b":
            raise Error("Invalid FEN active color")

        self.board = new_board^
        self.current_turn = active_color == "w"
        self.castling_rights = String(parts[2])
        self.en_passant_square = String(parts[3])
        self.halfmove_clock = Int(String(parts[4]))
        self.fullmove_number = Int(String(parts[5]))
        self.repetition_counts = List[String]()
        self._record_position()

    def to_fen(self) -> String:
        var result = String("")

        for row in range(8):
            var empty_count = 0

            for column in range(8):
                var piece = self.board[row][column]

                if piece.piece == "":
                    empty_count += 1
                else:
                    if empty_count > 0:
                        result += String(empty_count)
                        empty_count = 0
                    result += piece.piece

            if empty_count > 0:
                result += String(empty_count)

            if row < 7:
                result += "/"

        result += " "
        if self.current_turn:
            result += "w"
        else:
            result += "b"

        result += " " + self.castling_rights
        result += " " + self.en_passant_square
        result += " " + String(self.halfmove_clock)
        result += " " + String(self.fullmove_number)

        return result
