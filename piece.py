from move import Move

class Piece:
    """Arguments: piece \"Q\", Upper means White, Lower means Black
    self.color: True = White, False = Black"""
    def __init__(self, piece):
        self.color = (piece != piece.lower())
        self.piece = piece
        self.type = piece.lower()


    def is_legal_move(self, board, move: Move):

        if board.board[move.to_row][move.to_column] != "":
            if board.board[move.to_row][move.to_column].color == board.current_turn:
                return False 


        if self.type == "r":

            if (move.from_row == move.to_row and move.from_column != move.to_column) or (move.from_row != move.to_row and move.from_column == move.to_column):
                if not self._is_path_clear(board, move):
                    return False
                return True
            else:
                return False


            
        if self.type == "p":

            if move.from_column != move.to_column:
                return False
            if board.board[move.to_row][move.to_column] != "":
                return False
            if self.color:
                if move.from_row == 6:
                    return (move.to_row >= 4 and move.to_row <= 5)
                else:
                    if move.from_row >= 1 and move.from_row <= 5:
                        return (move.from_row - move.to_row == 1)
                    else:
                        return False

            else:
                if move.from_row == 1:
                    return (move.to_row >= 2 and move.to_row <= 3)
                else:
                    if move.from_row >= 2 and move.from_row <= 6:
                        return (move.to_row - move.from_row == 1)
                    else:
                        return False

        if self.type == "b":

            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            if (row_diff == column_diff) and (row_diff >= 1):
                return self._is_path_clear(board, move)
            else:
                return False
                 

        if self.type == "q":

            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            if ((row_diff == column_diff) and (row_diff >= 1)) or (move.from_row == move.to_row and move.from_column != move.to_column) or (move.from_row != move.to_row and move.from_column == move.to_column):
                return self._is_path_clear(board, move)
            else:
                return False

        if self.type == "k":

            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            return (row_diff <= 1 and column_diff <=1 and row_diff + column_diff >= 1)
        
        if self.type == "n":

            row_diff = abs(move.from_row - move.to_row)
            column_diff = abs(move.from_column - move.to_column)

            return (row_diff == 1 and column_diff == 2) or (row_diff == 2 and column_diff == 1)


    def _is_path_clear(self, board, move):
        row_step = (move.to_row > move.from_row) - (move.to_row < move.from_row)
        col_step = (move.to_column > move.from_column) - (move.to_column < move.from_column)

        row = move.from_row + row_step
        column = move.from_column + col_step

        while (row, column) != (move.to_row, move.to_column):
            if board.board[row][column] != "":
                return False

            row += row_step
            column += col_step

        return True
    