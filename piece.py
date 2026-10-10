from move import Move
from board import Board

class Piece:
    """Arguments: piece \"Q\", Upper means White, Lower means Black
    self.color: True = White, False = Black"""
    def __init__(self, piece):
        self.color = (piece != piece.lower())
        self.piece = piece
        self.type = piece.lower()


    def is_legal_move(self, board, move: Move):
        if self.type == "r":
            if (move.from_row == move.to_row and move.from_column != move.to_column) or (move.from_row != move.to_row and move.from_column == move.to_column):
                return True
            else:
                return False
            
        if self.type == "p":
            if move.from_column != move.to_column:
                return False
            if board[move.to_row][move.to_column] != "":
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

            return (row_diff == column_diff) and (row_diff >= 1)

