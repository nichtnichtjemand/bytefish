class Piece:
    """Arguments: piece \"Q\", Upper means White, Lower means Black
    self.color: True = White, False = Black"""
    def __init__(self, piece):
        self.color = (piece != piece.lower())