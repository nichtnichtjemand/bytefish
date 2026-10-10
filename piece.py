from move import Move

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
