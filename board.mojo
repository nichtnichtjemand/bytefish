from std.collections import List, Optional
from std.time import monotonic
from std.python import Python, PythonObject

from move import Move
from piece import Piece
from piece_types import EMPTY, PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING
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
    # Piece bitboards use the same indexing as board[row][column]: a8 = 0,
    # h1 = 63. Slots are white P/N/B/R/Q/K followed by black P/N/B/R/Q/K.
    var piece_bitboards: List[UInt64]
    var occupied_white: UInt64
    var occupied_black: UInt64
    var occupied_all: UInt64
    var white_king_square: Int
    var black_king_square: Int
    var castling_rights: String
    var en_passant_square: String
    var halfmove_clock: Int
    var fullmove_number: Int
    # Two 64-bit fingerprints per position keep repetition history compact.
    var repetition_counts: List[UInt64]
    var last_search_score: Int
    var last_search_nodes: Int
    var last_search_gap: Int
    var node_limit: Int
    var deadline_poll_count: Int
    # A Python list is deliberately shared by all board copies made during
    # search. It carries UCI stop/ponder state into the recursive search.
    var search_control: PythonObject

    def __init__(
        out self,
        empty: Bool = False,
        shared_search_control: Optional[PythonObject] = None,
    ) raises:
        self.current_turn = True
        self.board = List[List[Piece]]()
        self.piece_bitboards = List[UInt64]()
        for _ in range(12):
            self.piece_bitboards.append(UInt64(0))
        self.occupied_white = UInt64(0)
        self.occupied_black = UInt64(0)
        self.occupied_all = UInt64(0)
        self.white_king_square = -1
        self.black_king_square = -1
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self.repetition_counts = List[UInt64]()
        self.last_search_score = 0
        self.last_search_nodes = 0
        self.last_search_gap = 0
        self.node_limit = 0
        self.deadline_poll_count = 0
        if shared_search_control:
            self.search_control = shared_search_control.value()
        else:
            var builtins = Python.import_module("builtins")
            self.search_control = builtins.list()
            self.search_control.append(False)  # stop requested
            self.search_control.append(False)  # pondering
            self.search_control.append(None)   # active deadline
            self.search_control.append(0.0)    # time budget after ponderhit
            self.search_control.append(False)  # quit requested
            self.search_control.append(0)      # input polling counter
            self.search_control.append(0)      # optional node limit
            self.search_control.append(0)      # searched node counter
            self.search_control.append(0.0)    # clock start after ponderhit
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

        self._rebuild_bitboards()

        self.current_turn = True
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        self.repetition_counts = List[UInt64]()
        self._record_position()

    def copy(self) raises -> Board:
        # Search creates a board copy at nearly every node. Skip constructing
        # and then throwing away the initial position in that hot path.
        var result = Board(True, Optional(self.search_control))
        result.board = List[List[Piece]]()

        for row in range(8):
            result.board.append(self.board[row].copy())

        result.piece_bitboards = self.piece_bitboards.copy()
        result.occupied_white = self.occupied_white
        result.occupied_black = self.occupied_black
        result.occupied_all = self.occupied_all
        result.white_king_square = self.white_king_square
        result.black_king_square = self.black_king_square

        result.current_turn = self.current_turn
        result.castling_rights = self.castling_rights
        result.en_passant_square = self.en_passant_square
        result.halfmove_clock = self.halfmove_clock
        result.fullmove_number = self.fullmove_number
        result.repetition_counts = self.repetition_counts.copy()
        result.last_search_score = self.last_search_score
        result.last_search_nodes = self.last_search_nodes
        result.last_search_gap = self.last_search_gap
        result.node_limit = self.node_limit
        result.deadline_poll_count = self.deadline_poll_count
        result.search_control = self.search_control

        return result^

    def _bitboard_index(self, piece: Piece) -> Int:
        return Int(piece.color) * 6 + Int(piece.kind) - 1

    def _square_mask(self, row: Int, column: Int) -> UInt64:
        return UInt64(1) << UInt64(row * 8 + column)

    # Keep the mailbox lookup as the fast path for callers that need a Piece
    # value. Attack and occupancy queries operate directly on bitboards.
    def _piece_at(self, row: Int, column: Int) -> Piece:
        return self.board[row][column]

    def _rebuild_bitboards(mut self):
        self.piece_bitboards = List[UInt64]()
        for _ in range(12):
            self.piece_bitboards.append(UInt64(0))
        self.occupied_white = UInt64(0)
        self.occupied_black = UInt64(0)
        self.occupied_all = UInt64(0)
        self.white_king_square = -1
        self.black_king_square = -1
        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.kind != EMPTY:
                    var index = self._bitboard_index(piece)
                    self.piece_bitboards[index] = (
                        self.piece_bitboards[index]
                        | self._square_mask(row, column)
                    )
                    if piece.color:
                        self.occupied_white = (
                            self.occupied_white | self._square_mask(row, column)
                        )
                        if piece.kind == KING and self.white_king_square < 0:
                            self.white_king_square = row * 8 + column
                    else:
                        self.occupied_black = (
                            self.occupied_black | self._square_mask(row, column)
                        )
                        if piece.kind == KING and self.black_king_square < 0:
                            self.black_king_square = row * 8 + column
        self.occupied_all = self.occupied_white | self.occupied_black

    def _set_square(mut self, row: Int, column: Int, piece: Piece):
        var mask = self._square_mask(row, column)
        var previous = self.board[row][column]
        if previous.kind != EMPTY:
            var previous_index = self._bitboard_index(previous)
            self.piece_bitboards[previous_index] = (
                self.piece_bitboards[previous_index] & ~mask
            )
            if previous.color:
                self.occupied_white = self.occupied_white & ~mask
            else:
                self.occupied_black = self.occupied_black & ~mask
            if previous.kind == KING:
                if previous.color and self.white_king_square == row * 8 + column:
                    self.white_king_square = -1
                elif (
                    not previous.color
                    and self.black_king_square == row * 8 + column
                ):
                    self.black_king_square = -1
        if piece.kind != EMPTY:
            var index = self._bitboard_index(piece)
            self.piece_bitboards[index] = self.piece_bitboards[index] | mask
            if piece.color:
                self.occupied_white = self.occupied_white | mask
            else:
                self.occupied_black = self.occupied_black | mask
            if piece.kind == KING:
                if piece.color:
                    self.white_king_square = row * 8 + column
                else:
                    self.black_king_square = row * 8 + column
        self.occupied_all = self.occupied_white | self.occupied_black
        self.board[row][column] = piece

    def _piece_bitboard(self, kind: UInt8, color: Bool) -> UInt64:
        return self.piece_bitboards[Int(color) * 6 + Int(kind) - 1]

    def _has_piece(self, row: Int, column: Int, kind: UInt8, color: Bool) -> Bool:
        return (
            self._piece_bitboard(kind, color) & self._square_mask(row, column)
        ) != UInt64(0)

    def _inside(self, row: Int, column: Int) -> Bool:
        return row >= 0 and row < 8 and column >= 0 and column < 8

    def _square_name(self, row: Int, column: Int) -> String:
        var file = String(chr(97 + column))
        var rank = String(chr(56 - row))
        return file + rank

    def _find_king(self, color: Bool) -> Optional[KingPos]:
        var square = self.white_king_square if color else self.black_king_square
        if square < 0:
            return None
        return Optional(KingPos(square // 8, square % 8))

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
            if self._is_occupied(scan_row, scan_column):
                if self._has_piece(scan_row, scan_column, QUEEN, by_color):
                    return True
                if diagonal and self._has_piece(
                    scan_row, scan_column, BISHOP, by_color
                ):
                    return True
                if not diagonal and self._has_piece(
                    scan_row, scan_column, ROOK, by_color
                ):
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
            if self._has_piece(pawn_row, column - 1, PAWN, by_color):
                return True
        if self._inside(pawn_row, column + 1):
            if self._has_piece(pawn_row, column + 1, PAWN, by_color):
                return True

        for row_offset in range(-2, 3):
            for column_offset in range(-2, 3):
                if abs(row_offset) * abs(column_offset) != 2:
                    continue
                var source_row = row + row_offset
                var source_column = column + column_offset
                if self._inside(source_row, source_column):
                    if self._has_piece(
                        source_row, source_column, KNIGHT, by_color
                    ):
                        return True

        for row_offset in range(-1, 2):
            for column_offset in range(-1, 2):
                if row_offset == 0 and column_offset == 0:
                    continue
                var source_row = row + row_offset
                var source_column = column + column_offset
                if self._inside(source_row, source_column):
                    if self._has_piece(
                        source_row, source_column, KING, by_color
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
            if self._is_occupied(row, column):
                return False

            row += row_step
            column += column_step

        return True

    def _is_occupied(self, row: Int, column: Int) -> Bool:
        return (self.occupied_all & self._square_mask(row, column)) != UInt64(0)

    def is_in_check(self, color: Bool) -> Bool:
        var king = self._find_king(color)
        if not king:
            return True

        var position = king.value()
        return self.is_square_attacked(position.row, position.column, not color)

    def _is_pinned_piece(
        self, row: Int, column: Int, king_row: Int, king_column: Int,
        color: Bool,
    ) -> Bool:
        var row_delta = row - king_row
        var column_delta = column - king_column
        var row_step = 0
        var column_step = 0

        if row_delta == 0:
            column_step = 1 if column_delta > 0 else -1
        elif column_delta == 0:
            row_step = 1 if row_delta > 0 else -1
        elif abs(row_delta) == abs(column_delta):
            row_step = 1 if row_delta > 0 else -1
            column_step = 1 if column_delta > 0 else -1
        else:
            return False

        var scan_row = king_row + row_step
        var scan_column = king_column + column_step
        while scan_row != row or scan_column != column:
            if self._piece_at(scan_row, scan_column).kind != EMPTY:
                return False
            scan_row += row_step
            scan_column += column_step

        scan_row += row_step
        scan_column += column_step
        while self._inside(scan_row, scan_column):
            var attacker = self._piece_at(scan_row, scan_column)
            if attacker.kind != EMPTY:
                if attacker.color == color:
                    return False
                if attacker.kind == QUEEN:
                    return True
                if row_step == 0 or column_step == 0:
                    return attacker.kind == ROOK
                return attacker.kind == BISHOP
            scan_row += row_step
            scan_column += column_step

        return False

    def is_en_passant(self, move: Move) -> Bool:
        if self.en_passant_square == "-":
            return False

        if move.to_field != self.en_passant_square:
            return False

        var piece = self._piece_at(move.from_row, move.from_column)
        if piece.kind == EMPTY or piece.kind != PAWN:
            return False

        return (
            move.from_column != move.to_column
            and self._piece_at(move.to_row, move.to_column).kind == EMPTY
        )

    def _can_castle(self, move: Move) -> Bool:
        var piece = self._piece_at(move.from_row, move.from_column)

        if piece.kind == EMPTY or piece.kind != KING:
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
                self._piece_at(move.from_row, 5).kind != EMPTY
                or self._piece_at(move.from_row, 6).kind != EMPTY
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
                self._piece_at(move.from_row, 1).kind != EMPTY
                or self._piece_at(move.from_row, 2).kind != EMPTY
                or self._piece_at(move.from_row, 3).kind != EMPTY
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

    # Test king safety in place. Legal-move generation calls this for king
    # moves, checks, pins, and en-passant moves; cloning a whole Board there
    # also copies search and repetition state that this check never needs.
    def _move_is_king_safe(mut self, move: Move) -> Bool:
        var moving_piece = self._piece_at(move.from_row, move.from_column)
        var target_piece = self._piece_at(move.to_row, move.to_column)
        var en_passant = self.is_en_passant(move)
        var captured_row = move.to_row
        if en_passant:
            captured_row = move.to_row + 1
            if not moving_piece.color:
                captured_row = move.to_row - 1
        var captured_piece = self._piece_at(captured_row, move.to_column)

        var placed_piece = moving_piece
        if moving_piece.kind == PAWN and (
            move.to_row == 0 or move.to_row == 7
        ):
            var promotion = String("q")
            if move.promotion:
                promotion = move.promotion.value()
            if moving_piece.color:
                promotion = promotion.upper()
            placed_piece = Piece(promotion)

        self._set_square(move.to_row, move.to_column, placed_piece)
        self._set_square(move.from_row, move.from_column, Piece(""))
        if en_passant:
            self._set_square(captured_row, move.to_column, Piece(""))

        var rook_from = -1
        var rook_to = -1
        if moving_piece.kind == KING and abs(move.to_column - move.from_column) == 2:
            rook_from = 7 if move.to_column == 6 else 0
            rook_to = 5 if move.to_column == 6 else 3
            var rook = self._piece_at(move.from_row, rook_from)
            self._set_square(move.from_row, rook_to, rook)
            self._set_square(move.from_row, rook_from, Piece(""))

        var safe = not self.is_in_check(self.current_turn)

        if rook_from >= 0:
            var rook = self._piece_at(move.from_row, rook_to)
            self._set_square(move.from_row, rook_from, rook)
            self._set_square(move.from_row, rook_to, Piece(""))
        if en_passant:
            self._set_square(captured_row, move.to_column, captured_piece)
        self._set_square(move.from_row, move.from_column, moving_piece)
        self._set_square(move.to_row, move.to_column, target_piece)
        return safe

    def _remove_castling_rights(mut self, piece: Piece) raises:
        if piece.kind == KING and piece.color:
            self.castling_rights = self.castling_rights.replace("K", "")
            self.castling_rights = self.castling_rights.replace("Q", "")
        elif piece.kind == KING and not piece.color:
            self.castling_rights = self.castling_rights.replace("k", "")
            self.castling_rights = self.castling_rights.replace("q", "")

    def _update_castling_rights(
        mut self, move: Move, from_piece: Piece, to_piece: Piece
    ) raises:
        self._remove_castling_rights(from_piece)

        if from_piece.kind == ROOK and from_piece.color:
            if move.from_row == 7 and move.from_column == 0:
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif move.from_row == 7 and move.from_column == 7:
                self.castling_rights = self.castling_rights.replace("K", "")

        elif from_piece.kind == ROOK and not from_piece.color:
            if move.from_row == 0 and move.from_column == 0:
                self.castling_rights = self.castling_rights.replace("q", "")
            elif move.from_row == 0 and move.from_column == 7:
                self.castling_rights = self.castling_rights.replace("k", "")

        if to_piece.kind == ROOK and to_piece.color:
            if move.to_row == 7 and move.to_column == 0:
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif move.to_row == 7 and move.to_column == 7:
                self.castling_rights = self.castling_rights.replace("K", "")

        elif to_piece.kind == ROOK and not to_piece.color:
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

        if from_piece.kind == PAWN and (
            move.to_row - move.from_row == 2 or move.from_row - move.to_row == 2
        ):
            self.en_passant_square = self._square_name(
                (move.from_row + move.to_row) // 2,
                move.from_column,
            )

        if from_piece.kind == PAWN or is_capture:
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
            from_piece.kind == PAWN
            or is_capture
            or self.castling_rights != previous_castling_rights
        ):
            self.repetition_counts = List[UInt64]()
        self._record_position()

    def move(mut self, move: Move) raises -> Bool:
        if not self._inside(
            move.from_row, move.from_column
        ) or not self._inside(move.to_row, move.to_column):
            return False

        var from_piece = self._piece_at(move.from_row, move.from_column)
        var to_piece = self._piece_at(move.to_row, move.to_column)

        if from_piece.kind == EMPTY or from_piece.color != self.current_turn:
            return False

        if to_piece.kind != EMPTY and to_piece.color == self.current_turn:
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

        var is_capture = to_piece.kind != EMPTY
        var en_passant = self.is_en_passant(move)

        if en_passant:
            is_capture = True
            var captured_row = move.to_row + 1
            if not from_piece.color:
                captured_row = move.to_row - 1
            self._set_square(captured_row, move.to_column, Piece(""))

        self._set_square(move.to_row, move.to_column, from_piece)
        self._set_square(move.from_row, move.from_column, Piece(""))

        if from_piece.kind == KING and (
            move.to_column - move.from_column == 2
            or move.from_column - move.to_column == 2
        ):
            if move.to_column == 6:
                var rook = Piece(self._piece_at(move.from_row, 7).piece)
                self._set_square(move.from_row, 5, rook)
                self._set_square(move.from_row, 7, Piece(""))
            else:
                var rook = Piece(self._piece_at(move.from_row, 0).piece)
                self._set_square(move.from_row, 3, rook)
                self._set_square(move.from_row, 0, Piece(""))

        if from_piece.kind == PAWN and (move.to_row == 0 or move.to_row == 7):
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

    def get_legal_moves(
        mut self, captures_only: Bool = False
    ) raises -> List[Move]:
        var result = List[Move]()
        var candidates = List[Move]()
        var needs_king_safety = UInt64(0)

        var king = self._find_king(self.current_turn)
        var in_check = True
        if king:
            var king_position = king.value()
            in_check = self.is_square_attacked(
                king_position.row, king_position.column, not self.current_turn
            )
        for row in range(8):
            for column in range(8):
                var piece = self._piece_at(row, column)

                if piece.kind == EMPTY or piece.color != self.current_turn:
                    continue

                var must_test_king_safety = in_check or piece.kind == KING
                if not must_test_king_safety and king:
                    var king_position = king.value()
                    must_test_king_safety = self._is_pinned_piece(
                        row, column, king_position.row, king_position.column,
                        piece.color,
                    )

                if must_test_king_safety:
                    needs_king_safety = needs_king_safety | self._square_mask(
                        row, column
                    )
                piece.append_candidate_moves(self, row, column, candidates)

                if piece.kind == KING and not captures_only:
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

        var promotion_types = List[String]()
        promotion_types.append("q")
        promotion_types.append("r")
        promotion_types.append("b")
        promotion_types.append("n")
        for candidate in candidates:
            var piece = self._piece_at(candidate.from_row, candidate.from_column)
            var from_mask = self._square_mask(
                candidate.from_row, candidate.from_column
            )
            var must_test_king_safety = (
                needs_king_safety & from_mask
            ) != UInt64(0)

            if captures_only:
                var target = self._piece_at(candidate.to_row, candidate.to_column)
                var promotion = piece.kind == PAWN and (
                    candidate.to_row == 0 or candidate.to_row == 7
                )
                var capture = (
                    target.kind != EMPTY and target.kind != KING
                ) or self.is_en_passant(candidate)
                if not capture and not promotion:
                    continue

            if piece.kind == PAWN and (
                candidate.to_row == 0 or candidate.to_row == 7
            ):
                for promotion in promotion_types:
                    var promoted_move = Move(
                        candidate.from_field,
                        candidate.to_field,
                        Optional(promotion),
                    )
                    var validate = must_test_king_safety
                    if not validate and self.is_en_passant(promoted_move):
                        validate = True
                    if not validate or self._move_is_king_safe(promoted_move):
                        result.append(promoted_move)
            else:
                var validate = must_test_king_safety
                if (
                    not validate
                    and piece.kind == PAWN
                    and candidate.from_column != candidate.to_column
                    and self._piece_at(candidate.to_row, candidate.to_column).kind == EMPTY
                    and self.is_en_passant(candidate)
                ):
                    validate = True
                if not validate or self._move_is_king_safe(candidate):
                    result.append(candidate)

        return result^

    def _apply_unchecked(mut self, move: Move) raises -> Bool:
        if not self._inside(
            move.from_row, move.from_column
        ) or not self._inside(move.to_row, move.to_column):
            return False

        var piece = self._piece_at(move.from_row, move.from_column)
        if piece.kind == EMPTY:
            return False

        var promotion_piece = String("")
        if piece.kind == PAWN and (move.to_row == 0 or move.to_row == 7):
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

        var target = self._piece_at(move.to_row, move.to_column)
        var capture = target.kind != EMPTY
        var ep = self.is_en_passant(move)

        if ep:
            var captured_row = move.to_row + 1
            if not piece.color:
                captured_row = move.to_row - 1
            self._set_square(captured_row, move.to_column, Piece(""))
            capture = True

        self._set_square(move.to_row, move.to_column, piece)
        self._set_square(move.from_row, move.from_column, Piece(""))

        if piece.kind == KING and (
            move.to_column - move.from_column == 2
            or move.from_column - move.to_column == 2
        ):
            if move.to_column == 6:
                var rook = Piece(self._piece_at(move.from_row, 7).piece)
                self._set_square(move.from_row, 5, rook)
                self._set_square(move.from_row, 7, Piece(""))
            else:
                var rook = Piece(self._piece_at(move.from_row, 0).piece)
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
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY:
                    continue

                var value = tables.mg_value(piece.kind)

                if piece.color:
                    score -= value
                else:
                    score += value

        return score

    def get_position_score(self) -> Int:
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY:
                    continue

                var table_row = row
                if piece.color:
                    table_row = 7 - row
                var bonus = tables.mg_piece_square_bonus(
                    piece.kind, table_row, column
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
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY:
                    continue

                var table_row = row
                if piece.color:
                    table_row = 7 - row

                var mg_score = (
                    tables.mg_value(piece.kind)
                    + tables.mg_piece_square_bonus(
                        piece.kind, table_row, column
                    )
                )
                var eg_score = (
                    tables.eg_value(piece.kind)
                    + tables.eg_piece_square_bonus(
                        piece.kind, table_row, column
                    )
                )

                if piece.color:
                    white_mg += mg_score
                    white_eg += eg_score
                else:
                    black_mg += mg_score
                    black_eg += eg_score
                game_phase += tables.gamephase_increment(piece.kind)

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
                if self._piece_at(row, column).kind != EMPTY:
                    count += 1
        return count

    def is_endgame(self) -> Bool:
        var queens = 0
        var pieces = 0
        for row in range(8):
            for column in range(8):
                var piece = self._piece_at(row, column)
                if piece.kind != EMPTY:
                    pieces += 1
                    if piece.kind == QUEEN:
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
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY or piece.kind == KING:
                    continue
                if piece.kind == PAWN or piece.kind == ROOK or piece.kind == QUEEN:
                    return False
                if piece.kind == KNIGHT:
                    if piece.color:
                        white_knights += 1
                    else:
                        black_knights += 1
                elif piece.kind == BISHOP:
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

                var piece = self._piece_at(scan_row, scan_column)
                if (
                    piece.kind != EMPTY
                    and piece.kind == PAWN
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

        var king_positions_found = False
        var white_king: Optional[KingPos] = None
        var black_king: Optional[KingPos] = None
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY:
                    continue

                var sign = 1
                if piece.color:
                    sign = -1

                if piece.kind == PAWN:
                    var rank = 7 - row
                    if not piece.color:
                        rank = row
                    score += sign * rank * 8
                    if self._is_passed_pawn(row, column, piece.color):
                        score += sign * (35 + rank * 12)
                        if not king_positions_found:
                            white_king = self._find_king(True)
                            black_king = self._find_king(False)
                            king_positions_found = True
                        var king_distance = 8
                        var king = white_king
                        if not piece.color:
                            king = black_king
                        if king:
                            var king_position = king.value()
                            king_distance = max(
                                abs(row - king_position.row),
                                abs(column - king_position.column),
                            )
                        score += sign * max(0, 24 - king_distance * 4)
                elif piece.kind == ROOK:
                    for pawn_row in range(8):
                        var pawn = self._piece_at(pawn_row, column)
                        if (
                            pawn.kind == EMPTY
                            or pawn.kind != PAWN
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
                                if self._piece_at(scan_row, column).kind != EMPTY:
                                    path_clear = False
                                    break
                                scan_row += step
                            if path_clear:
                                score += sign * 20
                                break

        return score

    def get_hanging_piece_score(self) -> Int:
        var score = 0

        for row in range(8):
            for column in range(8):
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY or piece.kind == KING:
                    continue

                if self.is_square_attacked(row, column, not piece.color):
                    var defended = self.is_square_attacked(
                        row, column, piece.color
                    )

                    if not defended:
                        var penalty = 0
                        if piece.kind == PAWN:
                            penalty = 50
                        elif piece.kind == KNIGHT:
                            penalty = 150
                        elif piece.kind == BISHOP:
                            penalty = 160
                        elif piece.kind == ROOK:
                            penalty = 250
                        elif piece.kind == QUEEN:
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
                var piece = self._piece_at(row, column)
                if piece.kind != EMPTY and piece.kind == PAWN:
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
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY:
                    continue

                var weight = 0
                if piece.kind == KNIGHT or piece.kind == BISHOP:
                    weight = 4
                elif piece.kind == ROOK:
                    weight = 2
                elif piece.kind == QUEEN or piece.kind == KING:
                    weight = 1

                if weight > 0:
                    var mobility = piece.get_mobility(self, row, column)
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
                var piece = self._piece_at(row, column)
                if piece.kind == EMPTY:
                    continue
                if piece.kind == QUEEN:
                    has_queen = True
                elif piece.kind == KING:
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
                    var pawn = self._piece_at(pawn_row, pawn_column)
                    if (
                        pawn.kind != EMPTY
                        and pawn.kind == PAWN
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

    def _record_position(mut self) raises:
        var hash_a = UInt64(1469598103934665603)
        var hash_b = UInt64(2654435761)
        for index in range(12):
            var feature = self.piece_bitboards[index] ^ UInt64(index + 1)
            hash_a = (hash_a ^ feature) * UInt64(1099511628211)
            hash_b = (hash_b ^ (feature + UInt64(0x9E3779B9))) * UInt64(16777619)

        var rights = UInt64(0)
        if "K" in self.castling_rights:
            rights = rights | UInt64(1)
        if "Q" in self.castling_rights:
            rights = rights | UInt64(2)
        if "k" in self.castling_rights:
            rights = rights | UInt64(4)
        if "q" in self.castling_rights:
            rights = rights | UInt64(8)
        var ep_square = UInt64(64)
        if self.en_passant_square != "-":
            var ep_bytes = self.en_passant_square.as_bytes()
            var ep_column = Int(ep_bytes[0]) - 97
            var ep_row = 8 - (Int(ep_bytes[1]) - 48)
            ep_square = UInt64(ep_row * 8 + ep_column)

        var metadata = rights | (ep_square << 8)
        if self.current_turn:
            metadata = metadata | (UInt64(1) << 16)
        hash_a = (hash_a ^ metadata) * UInt64(1099511628211)
        hash_b = (hash_b ^ (metadata + UInt64(0x9E3779B9))) * UInt64(16777619)
        self.repetition_counts.append(hash_a)
        self.repetition_counts.append(hash_b)

    def is_threefold_repetition(self) -> Bool:
        if len(self.repetition_counts) == 0:
            return False

        var signature_width = 2
        var current_start = len(self.repetition_counts) - signature_width
        var count = 0
        var position_start = 0
        while position_start <= current_start:
            var matches = True
            for field in range(signature_width):
                if (
                    self.repetition_counts[position_start + field]
                    != self.repetition_counts[current_start + field]
                ):
                    matches = False
                    break
            if matches:
                count += 1
                if count == 3:
                    return True
            position_start += signature_width

        return False

    def is_checkmate(mut self, color: Bool) raises -> Bool:
        if not self.is_in_check(color):
            return False

        if color == self.current_turn:
            return len(self.get_legal_moves()) == 0

        var child = self.copy()
        child.current_turn = color
        return len(child.get_legal_moves()) == 0

    def is_stalemate(mut self) raises -> Bool:
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

    def _sift_move_heap(
        self,
        mut moves: List[Move],
        mut scores: List[Int],
        heap_size: Int,
        root: Int,
    ):
        var parent = root
        while True:
            var largest = parent
            var left = parent * 2 + 1
            var right = left + 1
            if left < heap_size and scores[left] > scores[largest]:
                largest = left
            if right < heap_size and scores[right] > scores[largest]:
                largest = right
            if largest == parent:
                break
            var move_tmp = moves[parent]
            moves[parent] = moves[largest]
            moves[largest] = move_tmp
            var score_tmp = scores[parent]
            scores[parent] = scores[largest]
            scores[largest] = score_tmp
            parent = largest

    def order_moves(self, moves: List[Move]) raises -> List[Move]:
        var ordered = List[Move]()
        var remaining = moves.copy()
        var scores = List[Int]()
        var endgame = self.is_endgame()
        var all_scores_zero = True

        # Compute each move's expensive positional score once. The previous
        # selection loop recalculated endgame and passed-pawn features every
        # time it compared a move with the remaining list.
        for move in remaining:
            var score = 0
            var target = self._piece_at(move.to_row, move.to_column)
            var moving_piece = self._piece_at(move.from_row, move.from_column)

            if target.kind != EMPTY:
                var victim_value = 0
                var attacker_value = 0
                if target.kind == PAWN:
                    victim_value = 1
                elif target.kind == KNIGHT or target.kind == BISHOP:
                    victim_value = 3
                elif target.kind == ROOK:
                    victim_value = 5
                elif target.kind == QUEEN:
                    victim_value = 9

                if moving_piece.kind == PAWN:
                    attacker_value = 1
                elif moving_piece.kind == KNIGHT or moving_piece.kind == BISHOP:
                    attacker_value = 3
                elif moving_piece.kind == ROOK:
                    attacker_value = 5
                elif moving_piece.kind == QUEEN:
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
                if moving_piece.kind == PAWN:
                    if move.to_row == 0 or move.to_row == 7:
                        score += 900
                    elif self._is_passed_pawn(
                        move.from_row,
                        move.from_column,
                        moving_piece.color,
                    ):
                        score += 120
                elif moving_piece.kind == KING:
                    var old_distance = abs(
                        Float64(move.from_row) - 3.5
                    ) + abs(Float64(move.from_column) - 3.5)
                    var new_distance = abs(
                        Float64(move.to_row) - 3.5
                    ) + abs(Float64(move.to_column) - 3.5)
                    if new_distance < old_distance:
                        score += 45
            if score != 0:
                all_scores_zero = False
            scores.append(score)

        if all_scores_zero:
            return remaining^

        var heap_size = len(remaining)
        var start = heap_size // 2
        while start > 0:
            start -= 1
            self._sift_move_heap(remaining, scores, heap_size, start)

        while heap_size > 0:
            ordered.append(remaining[0])
            heap_size -= 1
            if heap_size > 0:
                remaining[0] = remaining[heap_size]
                scores[0] = scores[heap_size]
                _ = remaining.pop()
                _ = scores.pop()
                self._sift_move_heap(remaining, scores, heap_size, 0)

        return ordered^

    def quiescence(
        mut self,
        alpha: Int,
        beta: Int,
        deadline: Optional[Float64] = None,
        remaining_depth: Int = 2,
    ) raises -> Int:
        self._check_deadline(deadline)
        self.last_search_nodes = 1
        self._count_search_node()

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

        var moves = self.get_legal_moves(not in_check)
        if len(moves) == 0:
            if in_check:
                if self.current_turn:
                    return MATE_SCORE
                return -MATE_SCORE
            return best_score

        var ordered = self.order_moves(moves)

        for move in ordered:
            var child = self.copy()
            child.last_search_nodes = 0
            if not child._apply_unchecked(move):
                continue

            var score = child.quiescence(
                local_alpha, local_beta, deadline, remaining_depth - 1
            )
            self.deadline_poll_count = child.deadline_poll_count
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
        # Quiescence already checks repetition, move-count draws and
        # insufficient material, so send horizon nodes there before doing
        # those same tests twice.
        if depth <= 0:
            return self.quiescence(alpha, beta, deadline)

        self._check_deadline(deadline)

        self.last_search_nodes = 1
        self._count_search_node()

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
                var child = self.copy()
                child.last_search_nodes = 0

                if not child._apply_unchecked(move):
                    continue

                var score = child.minimax(
                    depth - 1, local_alpha, local_beta, deadline
                )
                self.deadline_poll_count = child.deadline_poll_count
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
                var child = self.copy()
                child.last_search_nodes = 0

                if not child._apply_unchecked(move):
                    continue

                var score = child.minimax(
                    depth - 1, local_alpha, local_beta, deadline
                )
                self.deadline_poll_count = child.deadline_poll_count
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
        self._check_deadline(deadline)
        self.last_search_nodes = 1
        self._count_search_node()
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
        var second_best_score = INF
        var local_alpha = -INF
        var local_beta = INF

        if not self.current_turn:
            best_score = -INF
            second_best_score = -INF

        for move in ordered:
            var child = self.copy()
            child.last_search_nodes = 0
            if not child._apply_unchecked(move):
                continue

            var score = child.minimax(
                depth - 1, local_alpha, local_beta, deadline
            )
            self.deadline_poll_count = child.deadline_poll_count
            self.last_search_nodes += child.last_search_nodes

            if self.current_turn:
                if score < best_score:
                    second_best_score = best_score
                    best_score = score
                    best = move
                elif score < second_best_score:
                    second_best_score = score
                if best_score < local_beta:
                    local_beta = best_score
                if local_beta <= local_alpha:
                    break
            else:
                if score > best_score:
                    second_best_score = best_score
                    best_score = score
                    best = move
                elif score > second_best_score:
                    second_best_score = score
                if best_score > local_alpha:
                    local_alpha = best_score
                if local_beta <= local_alpha:
                    break

        self.last_search_score = best_score
        if second_best_score != INF and second_best_score != -INF:
            self.last_search_gap = abs(second_best_score - best_score)
        else:
            self.last_search_gap = 0
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

    def _check_deadline(mut self, deadline: Optional[Float64]) raises:
        # Poll stdin from inside search so UCI's synchronous outer loop still
        # reacts promptly to stop, ponderhit, quit, and isready.
        self.deadline_poll_count += 1
        if self.deadline_poll_count >= 256:
            self.deadline_poll_count = 0
            var select = Python.import_module("select")
            var sys = Python.import_module("sys")
            var ready = select.select([sys.stdin], [], [], 0.0)
            if len(ready[0]) > 0:
                var raw = sys.stdin.readline()
                var incoming = String(py=raw.strip())
                if incoming == "stop":
                    self.search_control[0] = True
                    self.search_control[1] = False
                elif incoming == "ponderhit":
                    if self.search_control[1]:
                        var now = Float64(monotonic()) / 1_000_000_000.0
                        self.search_control[1] = False
                        var ponder_duration = Float64(
                            String(py=self.search_control[3])
                        )
                        if ponder_duration > 0.0:
                            self.search_control[2] = now + ponder_duration
                        else:
                            self.search_control[2] = None
                        self.search_control[8] = now
                elif incoming == "quit":
                    self.search_control[0] = True
                    self.search_control[1] = False
                    self.search_control[4] = True
                elif incoming == "isready":
                    print("readyok")
            if String(py=self.search_control[0]) == "True":
                raise Error("Search stopped")
            if self.search_control[2] is not None:
                var active_deadline = Float64(String(py=self.search_control[2]))
                if Float64(monotonic()) / 1_000_000_000.0 >= active_deadline:
                    raise Error("Search deadline reached")
            if deadline:
                if Float64(monotonic()) / 1_000_000_000.0 >= deadline.value():
                    raise Error("Search deadline reached")

    def _count_search_node(mut self) raises:
        if self.node_limit <= 0:
            return
        var searched = Int(String(py=self.search_control[7])) + 1
        self.search_control[7] = searched
        if searched > self.node_limit:
            raise Error("Search node limit reached")

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
        self._rebuild_bitboards()
        self.current_turn = active_color == "w"
        self.castling_rights = String(parts[2])
        self.en_passant_square = String(parts[3])
        self.halfmove_clock = Int(String(parts[4]))
        self.fullmove_number = Int(String(parts[5]))
        self.repetition_counts = List[UInt64]()
        self._record_position()

    def to_fen(self) -> String:
        var result = String("")

        for row in range(8):
            var empty_count = 0

            for column in range(8):
                var piece = self._piece_at(row, column)

                if piece.kind == EMPTY:
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
