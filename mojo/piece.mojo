from move import Move
from board import Board


struct Piece(Copyable):
    var color: Bool
    var piece: String
    var type: String

    def __init__(out self, piece: String):
        self.color = piece != piece.lower()
        self.piece = piece
        self.type = piece.lower()

    def __copyinit__(out self, other: Self):
        self.color = other.color
        self.piece = other.piece
        self.type = other.type

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

        if target != "" and target.color == self.color:
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
            direction = -1 if self.color else 1

            start_row = 6 if self.color else 1

            row_diff = move.to_row - move.from_row
            column_diff = abs(move.to_column - move.from_column)

            if column_diff == 0:
                if target != "":
                    return False

                if row_diff == direction:
                    return True

                if move.from_row == start_row and row_diff == 2 * direction:
                    middle_row = move.from_row + direction

                    return board.board[middle_row][move.from_column] == ""

                return False

            if column_diff == 1 and row_diff == direction:
                return (
                    target != "" and target.color != self.color
                ) or board.is_en_passant(move)

            return False

        if self.type == "b":
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            if row_diff == column_diff and row_diff >= 1:
                return self._is_path_clear(board, move)

            return False

        if self.type == "q":
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            is_diagonal = row_diff == column_diff and row_diff >= 1

            is_straight = (
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
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            return (
                row_diff <= 1
                and column_diff <= 1
                and row_diff + column_diff >= 1
            )

        if self.type == "n":
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            return (row_diff == 1 and column_diff == 2) or (
                row_diff == 2 and column_diff == 1
            )

        return False

    def _is_path_clear(self, board: Board, move: Move):
        var row_step = Int(move.to_row > move.from_row) - Int(
            move.to_row < move.from_row
        )

        var col_step = Int(move.to_column > move.from_column) - Int(
            move.to_column < move.from_column
        )

        var row = move.from_row + row_step
        var column = move.from_column + col_step

        while row != move.to_row or column != move.to_column:
            if board.board[row][column] != "":
                return False

            row += row_step
            column += col_step

        return True

    def get_candidate_moves(self, board: Board, row: Int, column: Int):
        var moves = List[Move]()

        # --- SPRINGER (Knight) ---
        if self.type == "n":
            var offsets = [
                Tuple(-2, -1),
                Tuple(-2, 1),
                Tuple(-1, -2),
                Tuple(-1, 2),
                Tuple(1, -2),
                Tuple(1, 2),
                Tuple(2, -1),
                Tuple(2, 1),
            ]

            for offset in offsets:
                var dr = offset[0]
                var dc = offset[1]
                var r = row + dr
                var c = column + dc

                if self._in_bounds(r, c):
                    moves.append(self._create_move(row, column, r, c))

        # --- KÖNIG (King) ---
        elif self.type == "k":
            for dr in [-1, 0, 1]:
                for dc in [-1, 0, 1]:
                    if dr == 0 and dc == 0:
                        continue

                    # KORREKTUR: Einzelne Deklarationen statt "var r, c"
                    var r = row + dr
                    var c = column + dc

                    if self._in_bounds(r, c):
                        moves.append(self._create_move(row, column, r, c))

        # --- BAUER (Pawn) ---
        elif self.type == "p":
            # KORREKTUR: Mojo-Ternary Operator (Bedingung ? Wahr : Falsch)
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
            var directions = List[Tuple[Int, Int]]()

            if self.type == "r" or self.type == "q":
                var straight: List[Tuple[Int, Int]] = [
                    (-1, 0),
                    (1, 0),
                    (0, -1),
                    (0, 1),
                ]
                directions.extend(straight^)

            if self.type == "b" or self.type == "q":
                var diagonal: List[Tuple[Int, Int]] = [
                    (-1, -1),
                    (-1, 1),
                    (1, -1),
                    (1, 1),
                ]
                directions.extend(diagonal^)

            for dir_tuple in directions:
                var dr = dir_tuple[0]
                var dc = dir_tuple[1]

                var r = row + dr
                var c = column + dc

                while self._in_bounds(r, c):
                    moves.append(self._create_move(row, column, r, c))

                    if board.board[r][c] != "":
                        break

                    r += dr
                    c += dc

        return moves

    def _in_bounds(self, row: Int, column: Int) -> Bool:
        return 0 <= row < 8 and 0 <= column < 8

    def _create_move(
        self, from_row: Int, from_column: Int, to_row: Int, to_column: Int
    ) -> Move:
        var from_field = chr(ord("a") + from_column) + String(8 - from_row)
        var to_field = chr(ord("a") + to_column) + String(8 - to_row)

        return Move(from_field, to_field)
