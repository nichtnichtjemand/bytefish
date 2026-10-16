from move import Move


class Piece:

    def __init__(self, piece):
        self.color = piece != piece.lower()
        self.piece = piece
        self.type = piece.lower()

    def is_legal_move(self, board, move: Move):

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

    def get_candidate_moves(self, board, row, column):
        moves = []

        if self.type == "n":
            offsets = [
                (-2, -1), (-2, 1),
                (-1, -2), (-1, 2),
                (1, -2), (1, 2),
                (2, -1), (2, 1)
            ]

            for dr, dc in offsets:
                r, c = row + dr, column + dc

                if self._in_bounds(r, c):
                    moves.append(self._create_move(row, column, r, c))

        elif self.type == "k":
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if dr == 0 and dc == 0:
                        continue

                    r, c = row + dr, column + dc

                    if self._in_bounds(r, c):
                        moves.append(self._create_move(row, column, r, c))

        elif self.type == "p":
            direction = -1 if self.color else 1
            start_row = 6 if self.color else 1

            # Ein Feld vorwärts
            r = row + direction

            if self._in_bounds(r, column):
                moves.append(self._create_move(row, column, r, column))

                # Zwei Felder vom Startfeld
                if row == start_row:
                    r2 = row + 2 * direction

                    if self._in_bounds(r2, column):
                        moves.append(
                            self._create_move(row, column, r2, column)
                        )

            # Diagonale Schläge
            for dc in (-1, 1):
                r, c = row + direction, column + dc

                if self._in_bounds(r, c):
                    moves.append(self._create_move(row, column, r, c))

        elif self.type in ("r", "b", "q"):
            directions = []

            # Turm: gerade Richtungen
            if self.type in ("r", "q"):
                directions.extend([
                    (-1, 0), (1, 0),
                    (0, -1), (0, 1)
                ])

            # Läufer: diagonale Richtungen
            if self.type in ("b", "q"):
                directions.extend([
                    (-1, -1), (-1, 1),
                    (1, -1), (1, 1)
                ])

            for dr, dc in directions:
                r, c = row + dr, column + dc

                while self._in_bounds(r, c):
                    moves.append(self._create_move(row, column, r, c))

                    # Hinter einer Figur geht es nicht weiter
                    if board.board[r][c] != "":
                        break

                    r += dr
                    c += dc

        return moves


    def _in_bounds(self, row, column):
        return 0 <= row < 8 and 0 <= column < 8

    def _create_move(self, from_row, from_column, to_row, to_column):
        from_field = chr(ord("a") + from_column) + str(8 - from_row)
        to_field = chr(ord("a") + to_column) + str(8 - to_row)

        return Move(from_field, to_field)