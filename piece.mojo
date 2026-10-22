from move import Move
from board import Board
from piece_types import EMPTY, PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING


struct Piece(Copyable, ImplicitlyCopyable, Movable):
    var color: Bool
    var piece: String
    var kind: UInt8

    def __init__(out self, piece: String):
        self.piece = piece
        self.color = False
        self.kind = EMPTY
        if piece.byte_length() > 0:
            var character = Int(piece.as_bytes()[0])
            if character >= 65 and character <= 90:
                self.color = True
                character += 32
            if character == 112:
                self.kind = PAWN
            elif character == 110:
                self.kind = KNIGHT
            elif character == 98:
                self.kind = BISHOP
            elif character == 114:
                self.kind = ROOK
            elif character == 113:
                self.kind = QUEEN
            elif character == 107:
                self.kind = KING

    def is_legal_move(self, board: Board, move: Move) -> Bool:
        if (
            (move.from_row < 0)
            or (move.to_row < 0)
            or (move.from_column < 0)
            or (move.to_column < 0)
            or (move.from_row > 7)
            or (move.to_row > 7)
            or (move.from_column > 7)
            or (move.to_column > 7)
        ):
            return False

        var target = board._piece_at(move.to_row, move.to_column)

        if target.kind != EMPTY and target.color == self.color:
            return False

        if self.kind == ROOK:
            if (
                move.from_row == move.to_row
                and move.from_column != move.to_column
            ) or (
                move.from_row != move.to_row
                and move.from_column == move.to_column
            ):
                return self._is_path_clear(board, move)

            return False

        if self.kind == PAWN:
            var direction = -1 if self.color else 1

            var start_row = 6 if self.color else 1

            var row_diff = move.to_row - move.from_row
            var column_diff = abs(move.to_column - move.from_column)

            if column_diff == 0:
                if target.kind != EMPTY:
                    return False

                if row_diff == direction:
                    return True

                if move.from_row == start_row and row_diff == 2 * direction:
                    var middle_row = move.from_row + direction

                    return board._piece_at(middle_row, move.from_column).kind == EMPTY

                return False

            if column_diff == 1 and row_diff == direction:
                return (
                    target.kind != EMPTY and target.color != self.color
                ) or board.is_en_passant(move)

            return False

        if self.kind == BISHOP:
            var row_diff = abs(move.from_row - move.to_row)
            var column_diff = abs(move.from_column - move.to_column)

            if row_diff == column_diff and row_diff >= 1:
                return self._is_path_clear(board, move)

            return False

        if self.kind == QUEEN:
            var row_diff = abs(move.from_row - move.to_row)
            var column_diff = abs(move.from_column - move.to_column)

            var is_diagonal = row_diff == column_diff and row_diff >= 1

            var is_straight = (
                move.from_row == move.to_row
                and move.from_column != move.to_column
            ) or (
                move.from_row != move.to_row
                and move.from_column == move.to_column
            )

            if is_diagonal or is_straight:
                return self._is_path_clear(board, move)

            return False

        if self.kind == KING:
            var row_diff = abs(move.from_row - move.to_row)
            var column_diff = abs(move.from_column - move.to_column)

            return (
                row_diff <= 1
                and column_diff <= 1
                and row_diff + column_diff >= 1
            )

        if self.kind == KNIGHT:
            var row_diff = abs(move.from_row - move.to_row)
            var column_diff = abs(move.from_column - move.to_column)

            return (row_diff == 1 and column_diff == 2) or (
                row_diff == 2 and column_diff == 1
            )

        return False

    def _is_path_clear(self, board: Board, move: Move) -> Bool:
        var row_step = Int(move.to_row > move.from_row) - Int(
            move.to_row < move.from_row
        )

        var col_step = Int(move.to_column > move.from_column) - Int(
            move.to_column < move.from_column
        )

        var row = move.from_row + row_step
        var column = move.from_column + col_step

        while row != move.to_row or column != move.to_column:
            if board._piece_at(row, column).kind != EMPTY:
                return False

            row += row_step
            column += col_step

        return True

    def append_candidate_moves(
        self, board: Board, row: Int, column: Int, mut moves: List[Move]
    ) raises:
        if self.kind == KNIGHT:
            var offsets = [
                (-2, -1),
                (-2, 1),
                (-1, -2),
                (-1, 2),
                (1, -2),
                (1, 2),
                (2, -1),
                (2, 1),
            ]

            for offset in offsets:
                var r = row + offset[0]
                var c = column + offset[1]

                if self._in_bounds(r, c):
                    var target = board._piece_at(r, c)
                    if target.kind == EMPTY or target.color != self.color:
                        moves.append(self._create_move(row, column, r, c))

        elif self.kind == KING:
            for dr in [-1, 0, 1]:
                for dc in [-1, 0, 1]:
                    if dr == 0 and dc == 0:
                        continue

                    var r = row + dr
                    var c = column + dc

                    if self._in_bounds(r, c):
                        var target = board._piece_at(r, c)
                        if target.kind == EMPTY or target.color != self.color:
                            moves.append(self._create_move(row, column, r, c))

        elif self.kind == PAWN:
            var direction = -1 if self.color else 1
            var start_row = 6 if self.color else 1
            var r = row + direction

            if self._in_bounds(r, column) and board._piece_at(r, column).kind == EMPTY:
                moves.append(self._create_move(row, column, r, column))

                if row == start_row:
                    var r2 = row + 2 * direction
                    if (
                        self._in_bounds(r2, column)
                        and board._piece_at(r2, column).kind == EMPTY
                    ):
                        moves.append(self._create_move(row, column, r2, column))

            for dc in [-1, 1]:
                var diag_r = row + direction
                var diag_c = column + dc

                if self._in_bounds(diag_r, diag_c):
                    var target = board._piece_at(diag_r, diag_c)
                    var move = self._create_move(row, column, diag_r, diag_c)
                    if (
                        (target.kind != EMPTY and target.color != self.color)
                        or board.is_en_passant(move)
                    ):
                        moves.append(move)

        elif self.kind == ROOK or self.kind == BISHOP or self.kind == QUEEN:
            var directions = [
                (-1, 0),
                (1, 0),
                (0, -1),
                (0, 1),
                (-1, -1),
                (-1, 1),
                (1, -1),
                (1, 1),
            ]

            for dir_index in range(len(directions)):
                var dr = directions[dir_index][0]
                var dc = directions[dir_index][1]
                var is_diagonal = dr != 0 and dc != 0

                if self.kind == ROOK and is_diagonal:
                    continue
                if self.kind == BISHOP and not is_diagonal:
                    continue

                var r = row + dr
                var c = column + dc

                while self._in_bounds(r, c):
                    var target = board._piece_at(r, c)
                    if target.kind != EMPTY and target.color == self.color:
                        break

                    moves.append(self._create_move(row, column, r, c))

                    if target.kind != EMPTY:
                        break

                    r += dr
                    c += dc

    def get_mobility(self, board: Board, row: Int, column: Int) -> Int:
        var mobility = 0

        if self.kind == KNIGHT:
            var offsets = [
                (-2, -1), (-2, 1), (-1, -2), (-1, 2),
                (1, -2), (1, 2), (2, -1), (2, 1),
            ]
            for offset in offsets:
                var target_row = row + offset[0]
                var target_column = column + offset[1]
                if self._in_bounds(target_row, target_column):
                    var target = board._piece_at(target_row, target_column)
                    if target.kind == EMPTY or target.color != self.color:
                        mobility += 1
        elif self.kind == KING:
            for row_offset in range(-1, 2):
                for column_offset in range(-1, 2):
                    if row_offset == 0 and column_offset == 0:
                        continue
                    var target_row = row + row_offset
                    var target_column = column + column_offset
                    if self._in_bounds(target_row, target_column):
                        var target = board._piece_at(target_row, target_column)
                        if target.kind == EMPTY or target.color != self.color:
                            mobility += 1
        elif self.kind == ROOK or self.kind == BISHOP or self.kind == QUEEN:
            var directions = [
                (-1, 0), (1, 0), (0, -1), (0, 1),
                (-1, -1), (-1, 1), (1, -1), (1, 1),
            ]
            for direction in directions:
                var row_step = direction[0]
                var column_step = direction[1]
                var diagonal = row_step != 0 and column_step != 0
                if (self.kind == ROOK and diagonal) or (
                    self.kind == BISHOP and not diagonal
                ):
                    continue
                var target_row = row + row_step
                var target_column = column + column_step
                while self._in_bounds(target_row, target_column):
                    var target = board._piece_at(target_row, target_column)
                    if target.kind != EMPTY and target.color == self.color:
                        break
                    mobility += 1
                    if target.kind != EMPTY:
                        break
                    target_row += row_step
                    target_column += column_step

        return mobility

    def _in_bounds(self, row: Int, column: Int) -> Bool:
        return 0 <= row < 8 and 0 <= column < 8

    def _create_move(
        self, from_row: Int, from_column: Int, to_row: Int, to_column: Int
    ) raises -> Move:
        return Move(from_row, from_column, to_row, to_column)
