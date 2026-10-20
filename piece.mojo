from move import Move
from board import Board


struct Piece(Copyable, ImplicitlyCopyable, Movable):
    var color: Bool
    var piece: String
    var type: String

    def __init__(out self, piece: String):
        self.color = piece != piece.lower()
        self.piece = piece
        self.type = piece.lower()

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

        var target = board.board[move.to_row][move.to_column]

        if target.piece != "" and target.color == self.color:
            return False

        if self.type == "r":
            if (
                move.from_row == move.to_row
                and move.from_column != move.to_column
            ) or (
                move.from_row != move.to_row
                and move.from_column == move.to_column
            ):
                return self._is_path_clear(board, move)

            return False

        if self.type == "p":
            var direction = -1 if self.color else 1

            var start_row = 6 if self.color else 1

            var row_diff = move.to_row - move.from_row
            var column_diff = abs(move.to_column - move.from_column)

            if column_diff == 0:
                if target.piece != "":
                    return False

                if row_diff == direction:
                    return True

                if move.from_row == start_row and row_diff == 2 * direction:
                    var middle_row = move.from_row + direction

                    return board.board[middle_row][move.from_column].piece == ""

                return False

            if column_diff == 1 and row_diff == direction:
                return (
                    target.piece != "" and target.color != self.color
                ) or board.is_en_passant(move)

            return False

        if self.type == "b":
            var row_diff = abs(move.from_row - move.to_row)
            var column_diff = abs(move.from_column - move.to_column)

            if row_diff == column_diff and row_diff >= 1:
                return self._is_path_clear(board, move)

            return False

        if self.type == "q":
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

        if self.type == "k":
            var row_diff = abs(move.from_row - move.to_row)
            var column_diff = abs(move.from_column - move.to_column)

            return (
                row_diff <= 1
                and column_diff <= 1
                and row_diff + column_diff >= 1
            )

        if self.type == "n":
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
            if board.board[row][column].piece != "":
                return False

            row += row_step
            column += col_step

        return True

    def get_candidate_moves(
        self, board: Board, row: Int, column: Int
    ) raises -> List[Move]:
        var moves = List[Move]()

        if self.type == "n":
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
                    moves.append(self._create_move(row, column, r, c))

        elif self.type == "k":
            for dr in [-1, 0, 1]:
                for dc in [-1, 0, 1]:
                    if dr == 0 and dc == 0:
                        continue

                    var r = row + dr
                    var c = column + dc

                    if self._in_bounds(r, c):
                        moves.append(self._create_move(row, column, r, c))

        elif self.type == "p":
            var direction = -1 if self.color else 1
            var start_row = 6 if self.color else 1
            var r = row + direction

            if self._in_bounds(r, column):
                moves.append(self._create_move(row, column, r, column))

                if row == start_row:
                    var r2 = row + 2 * direction
                    if self._in_bounds(r2, column):
                        moves.append(self._create_move(row, column, r2, column))

            for dc in [-1, 1]:
                var diag_r = row + direction
                var diag_c = column + dc

                if self._in_bounds(diag_r, diag_c):
                    moves.append(self._create_move(row, column, diag_r, diag_c))

        elif self.type == "r" or self.type == "b" or self.type == "q":
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

                if self.type == "r" and is_diagonal:
                    continue
                if self.type == "b" and not is_diagonal:
                    continue

                var r = row + dr
                var c = column + dc

                while self._in_bounds(r, c):
                    moves.append(self._create_move(row, column, r, c))

                    if board.board[r][c].piece != "":
                        break

                    r += dr
                    c += dc

        return moves^

    def _in_bounds(self, row: Int, column: Int) -> Bool:
        return 0 <= row < 8 and 0 <= column < 8

    def _create_move(
        self, from_row: Int, from_column: Int, to_row: Int, to_column: Int
    ) raises -> Move:
        var from_field = chr(ord("a") + from_column) + String(8 - from_row)
        var to_field = chr(ord("a") + to_column) + String(8 - to_row)

        return Move(from_field, to_field)
