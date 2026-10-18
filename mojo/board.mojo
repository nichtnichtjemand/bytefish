from std.collections import List, Optional
from std.time import monotonic

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
    var history: List[String]
    var repetition_counts: List[String]

    def __init__(out self) raises:
        self.current_turn = True
        self.board = List[List[Piece]]()
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self.history = List[String]()
        self.repetition_counts = List[String]()
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
        self.history = List[String]()
        self.repetition_counts = List[String]()
        self._record_position()

    def copy(self) raises -> Board:
        var result = Board()
        result.board = List[List[Piece]]()

        for row in range(8):
            result.board.append(self.board[row].copy())

        result.current_turn = self.current_turn
        result.castling_rights = self.castling_rights
        result.en_passant_square = self.en_passant_square
        result.halfmove_clock = self.halfmove_clock
        result.fullmove_number = self.fullmove_number
        result.history = self.history.copy()
        result.repetition_counts = self.repetition_counts.copy()

        return result^

    def _set_square(mut self, row: Int, column: Int, piece: Piece):
        var board_row = self.board[row].copy()
        board_row[column] = piece
        self.board[row] = board_row^

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

    def is_square_attacked(self, row: Int, column: Int, by_color: Bool) -> Bool:
        for source_row in range(8):
            for source_column in range(8):
                var piece = self.board[source_row][source_column]

                if piece.piece == "" or piece.color != by_color:
                    continue

                var dr = row - source_row
                var dc = column - source_column

                if piece.type == "p":
                    var direction = -1
                    if not piece.color:
                        direction = 1

                    if dr == direction and (dc == -1 or dc == 1):
                        return True

                elif piece.type == "n":
                    if ((dr == 2 or dr == -2) and (dc == 1 or dc == -1)) or (
                        (dc == 2 or dc == -2) and (dr == 1 or dr == -1)
                    ):
                        return True

                elif piece.type == "k":
                    if (
                        dr >= -1
                        and dr <= 1
                        and dc >= -1
                        and dc <= 1
                        and (dr != 0 or dc != 0)
                    ):
                        return True

                elif piece.type == "r" or piece.type == "q":
                    if dr == 0 or dc == 0:
                        if self._path_clear(
                            source_row, source_column, row, column
                        ):
                            return True

                if piece.type == "b" or piece.type == "q":
                    if dr != 0 and (dr == dc or dr == -dc):
                        if self._path_clear(
                            source_row, source_column, row, column
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

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]

                if piece.piece == "" or piece.color != self.current_turn:
                    continue

                var candidates = piece.get_candidate_moves(self, row, column)

                for candidate in candidates:
                    if not piece.is_legal_move(self, candidate):
                        continue

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

        if piece.type == "p" and (move.to_row == 0 or move.to_row == 7):
            var promotion = String("q")
            if move.promotion:
                promotion = move.promotion.value()
            if piece.color:
                promotion = promotion.upper()
            self._set_square(move.to_row, move.to_column, Piece(promotion))

        self._finish_move(move, piece, target, capture)
        return True

    def get_material_score(self) -> Int:
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue

                var value = 0
                if piece.type == "p":
                    value = 100
                elif piece.type == "n" or piece.type == "b":
                    value = 300
                elif piece.type == "r":
                    value = 500
                elif piece.type == "q":
                    value = 900

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
                if not piece.color:
                    table_row = 7 - row

                var bonus = 0

                if piece.type == "p":
                    bonus = tables.pawn_bonus(table_row, column)
                elif piece.type == "n":
                    bonus = tables.knight_bonus(table_row, column)
                elif piece.type == "b":
                    bonus = tables.bishop_bonus(table_row, column)
                elif piece.type == "r":
                    bonus = tables.rook_bonus(table_row, column)
                elif piece.type == "q":
                    bonus = tables.queen_bonus(table_row, column)
                elif piece.type == "k":
                    bonus = tables.king_bonus(table_row, column)

                if piece.color:
                    score -= bonus
                else:
                    score += bonus

        return score

    def _piece_count(self) -> Int:
        var count = 0
        for row in range(8):
            for column in range(8):
                if self.board[row][column].piece != "":
                    count += 1
        return count

    def is_endgame(self) -> Bool:
        var queens = 0
        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece != "" and piece.type == "q":
                    queens += 1
        return queens == 0 or self._piece_count() <= 12

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
        if self._piece_count() - 2 > 10:
            return 0

        var score = 0
        var center_row = 3.5
        var center_column = 3.5

        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece == "":
                    continue

                var sign = 1
                if piece.color:
                    sign = -1

                if piece.type == "k":
                    var distance = abs(Float64(row) - center_row) + abs(
                        Float64(column) - center_column
                    )
                    score += sign * Int((7.0 - distance) * 12.0)
                elif piece.type == "p":
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

        if self._piece_count() <= 4:
            var white_king = self._find_king(True)
            var black_king = self._find_king(False)
            if white_king and black_king:
                var white_pos = white_king.value()
                var black_pos = black_king.value()
                var opposition = 0
                if (
                    white_pos.column == black_pos.column
                    or white_pos.row == black_pos.row
                ):
                    var distance = max(
                        abs(white_pos.row - black_pos.row),
                        abs(white_pos.column - black_pos.column),
                    )
                    opposition = 10 if distance % 2 == 0 else -10
                if self.current_turn:
                    score += opposition
                else:
                    score -= opposition

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

        for column in range(8):
            var white_pawns = 0
            var black_pawns = 0

            for row in range(8):
                var piece = self.board[row][column]
                if piece.piece == "" or piece.type != "p":
                    continue

                if piece.color:
                    white_pawns += 1
                else:
                    black_pawns += 1

            if white_pawns > 1:
                score += (white_pawns - 1) * 12
            if black_pawns > 1:
                score -= (black_pawns - 1) * 12

            if white_pawns > 0:
                var isolated = True
                if column > 0:
                    for row in range(8):
                        if (
                            self.board[row][column - 1].piece != ""
                            and self.board[row][column - 1].type == "p"
                            and self.board[row][column - 1].color
                        ):
                            isolated = False
                if column < 7:
                    for row in range(8):
                        if (
                            self.board[row][column + 1].piece != ""
                            and self.board[row][column + 1].type == "p"
                            and self.board[row][column + 1].color
                        ):
                            isolated = False
                if isolated:
                    score += white_pawns * 14

            if black_pawns > 0:
                var isolated = True
                if column > 0:
                    for row in range(8):
                        if (
                            self.board[row][column - 1].piece != ""
                            and self.board[row][column - 1].type == "p"
                            and not self.board[row][column - 1].color
                        ):
                            isolated = False
                if column < 7:
                    for row in range(8):
                        if (
                            self.board[row][column + 1].piece != ""
                            and self.board[row][column + 1].type == "p"
                            and not self.board[row][column + 1].color
                        ):
                            isolated = False
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
        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece != "" and piece.type == "q":
                    has_queen = True
        if not has_queen:
            return 0

        var score = 0

        for color_index in range(2):
            var color = color_index == 1
            var king = self._find_king(color)
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
            self.get_material_score()
            + self.get_position_score()
            + self.get_endgame_score()
            + self.get_hanging_piece_score()
            + self.get_pawn_structure_score()
            + self.get_mobility_score()
            + self.get_king_safety_score()
        )

    def _position_key(self) -> String:
        return self.to_fen()

    def _record_position(mut self) raises:
        var key = self._position_key()
        self.history.append(key)
        self.repetition_counts.append(key)

    def is_threefold_repetition(self) -> Bool:
        var current = self._position_key()
        var count = 0

        for key in self.repetition_counts:
            if key == current:
                count += 1

        return count >= 3

    def is_checkmate(self, color: Bool) raises -> Bool:
        if not self.is_in_check(color):
            return False

        var child = self.copy()
        child.current_turn = color
        return len(child.get_legal_moves()) == 0

    def is_stalemate(self) raises -> Bool:
        if self.is_in_check(self.current_turn):
            return False
        return len(self.get_legal_moves()) == 0

    def find_mate_in_one(self) raises -> Optional[Move]:
        var moves = self.get_legal_moves()

        for move in moves:
            var child = self.copy()
            if child._apply_unchecked(move):
                if child.is_checkmate(child.current_turn):
                    return Optional(move)

        return None

    def order_moves(self, moves: List[Move]) raises -> List[Move]:
        var ordered = List[Move]()
        var remaining = moves.copy()

        while len(remaining) > 0:
            var best_index = 0
            var best_score = -INF

            for index in range(len(remaining)):
                var move = remaining[index]
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

                if self.is_endgame():
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

                if score > best_score:
                    best_score = score
                    best_index = index

            ordered.append(remaining[best_index])
            _ = remaining.pop(best_index)

        return ordered^

    def quiescence(
        mut self,
        alpha: Int,
        beta: Int,
        deadline: Optional[Float64] = None,
        remaining_depth: Int = 2,
    ) raises -> Int:
        Self._check_deadline(deadline)

        if self.is_threefold_repetition() or self.halfmove_clock >= 100:
            return 0

        var in_check = self.is_in_check(self.current_turn)
        if in_check and remaining_depth == 0:
            return self.evaluate()

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
            if remaining_depth == 0:
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
            if not child._apply_unchecked(move):
                continue

            var score = child.quiescence(
                local_alpha, local_beta, deadline, remaining_depth - 1
            )

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

        if self.is_threefold_repetition() or self.halfmove_clock >= 100:
            return 0

        if depth <= 0:
            return self.quiescence(alpha, beta, deadline)

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

                if not child._apply_unchecked(move):
                    continue

                var score = child.minimax(
                    depth - 1, local_alpha, local_beta, deadline
                )

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

                if not child._apply_unchecked(move):
                    continue

                var score = child.minimax(
                    depth - 1, local_alpha, local_beta, deadline
                )

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
    ) raises -> Optional[Move]:
        Self._check_deadline(deadline)

        if not deadline:
            var mate = self.find_mate_in_one()
            if mate:
                return mate

        var moves = self.get_legal_moves()
        if len(moves) == 0:
            return None

        var ordered = self.order_moves(moves)
        var best = ordered[0]
        var best_score = INF
        var local_alpha = -INF
        var local_beta = INF

        if not self.current_turn:
            best_score = -INF

        for move in ordered:
            Self._check_deadline(deadline)

            var child = self.copy()
            if not child._apply_unchecked(move):
                continue

            var score = child.minimax(
                depth - 1, local_alpha, local_beta, deadline
            )

            if self.current_turn:
                if score < best_score:
                    best_score = score
                    best = move
                if best_score < local_beta:
                    local_beta = best_score
            else:
                if score > best_score:
                    best_score = score
                    best = move
                if best_score > local_alpha:
                    local_alpha = best_score

        return Optional(best)

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
        self.history = List[String]()
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
