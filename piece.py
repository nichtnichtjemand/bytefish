from move import Move


class Piece:

    def __init__(self, piece):
        self.color = piece != piece.lower()
        self.piece = piece
        self.type = piece.lower()

    def is_legal_move(self, board, move: Move):

        if not (
            0 <= move.from_row < 8
            and 0 <= move.from_column < 8
            and 0 <= move.to_row < 8
            and 0 <= move.to_column < 8
        ):
            return False

        if (move.from_row < 0) or (move.to_row < 0) or (move.from_column < 0) or (move.to_column < 0) or (move.from_row > 7) or (move.to_row > 7) or (move.from_column > 7) or (move.to_column > 7):
            return False


        target = board.board[move.to_row][move.to_column]

        if target != "" and target.color == self.color:
            return False

        if self.type == "r":
            if (
                (
                    move.from_row == move.to_row
                    and move.from_column != move.to_column
                )
                or (
                    move.from_row != move.to_row
                    and move.from_column == move.to_column
                )
            ):
                return self._is_path_clear(board, move)

            return False

        if self.type == "p":

            direction = -1 if self.color else 1

            start_row = 6 if self.color else 1

            row_diff = move.to_row - move.from_row
            column_diff = abs(
                move.to_column - move.from_column
            )

            if column_diff == 0:

                if target != "":
                    return False

                if row_diff == direction:
                    return True

                if (
                    move.from_row == start_row
                    and row_diff == 2 * direction
                ):
                    middle_row = move.from_row + direction

                    return (
                        board.board[middle_row][move.from_column] == ""
                    )

                return False

            if column_diff == 1 and row_diff == direction:
                return (
                    target != ""
                    and target.color != self.color
                )

            return False

        if self.type == "b":
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(
                move.from_column - move.to_column
            )

            if row_diff == column_diff and row_diff >= 1:
                return self._is_path_clear(board, move)

            return False

        if self.type == "q":
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(
                move.from_column - move.to_column
            )

            is_diagonal = (
                row_diff == column_diff and row_diff >= 1
            )

            is_straight = (
                (
                    move.from_row == move.to_row
                    and move.from_column != move.to_column
                )
                or (
                    move.from_row != move.to_row
                    and move.from_column == move.to_column
                )
            )

            if is_diagonal or is_straight:
                return self._is_path_clear(board, move)

            return False
        
        if self.type == "k":
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(
                move.from_column - move.to_column
            )

            return (
                row_diff <= 1
                and column_diff <= 1
                and row_diff + column_diff >= 1
            )

        if self.type == "n":
            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            return (
                (row_diff == 1 and column_diff == 2)
                or (row_diff == 2 and column_diff == 1)
            )

        return False

    def _is_path_clear(self, board, move):
        row_step = (
            (move.to_row > move.from_row)
            - (move.to_row < move.from_row)
        )

        col_step = (
            (move.to_column > move.from_column)
            - (move.to_column < move.from_column)
        )

        row = move.from_row + row_step
        column = move.from_column + col_step

        while (row, column) != (
            move.to_row,
            move.to_column
        ):
            if board.board[row][column] != "":
                return False

            row += row_step
            column += col_step

        return True