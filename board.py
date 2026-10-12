from move import Move
from piece import Piece

class Board:

    def __init__(self):
        setup = [
                        ["r", "n", "b", "q", "k", "b", "n", "r"],
                        ["p", "p", "p", "p", "p", "p", "p", "p"],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["P", "P", "P", "P", "P", "P", "P", "P"],
                        ["R", "N", "B", "Q", "K", "B", "N", "R"]
        ]
        self.current_turn = True # True = White, False = Black
        self.board = []
        for row in setup:
            new_row = []
            for char in row:
                if char != "":
                    new_row.append(Piece(char))
                else:
                    new_row.append("")
            self.board.append(new_row)



    def move(self, move: Move):

        
        if (
            move.from_row < 0 or move.from_row > 7 or
            move.from_column < 0 or move.from_column > 7 or
            move.to_row < 0 or move.to_row > 7 or
            move.to_column < 0 or move.to_column > 7
        ):
            return ValueError("Koordinaten außerhalb des Bretts")

        from_column = move.from_column
        from_row = move.from_row
        to_column = move.to_column
        to_row = move.to_row

        if (move.from_row < 0) or (move.to_row < 0) or (move.from_column < 0) or (move.to_column < 0) or (move.from_row > 7) or (move.to_row > 7) or (move.from_column > 7) or (move.to_column > 7):
            return False

        from_piece = self.board[from_row][from_column]
        to_piece = self.board[to_row][to_column]
        if from_piece == "":
            return ValueError(f"The field is empty")
        if to_piece != "":
            if from_piece.color == to_piece.color:
                return ValueError("Colors of start and end pieces can't be the same")
        if from_piece.color != self.current_turn:
            return ValueError("It's not this color's turn")
        if from_column == to_column and from_row == to_row:
            return ValueError("The start and end piece coordinates are the same")
        
        self.board[to_row][to_column] = from_piece
        self.board[from_row][from_column] = ""
        self.current_turn = False if self.current_turn else True