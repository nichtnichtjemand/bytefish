from move import Move

class Board:

    def __init__(self):
        self.board = [
                        ["r", "n", "b", "q", "k", "b", "n", "r"],
                        ["p", "p", "p", "p", "p", "p", "p", "p"],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["",  "",  "",  "",  "",  "",  "",  "" ],
                        ["P", "P", "P", "P", "P", "P", "P", "P"],
                        ["R", "N", "B", "Q", "K", "B", "N", "R"]
        ]

    def move(self, move: Move):

        from_column = ord(move.from_field[0].lower()) - ord("a")
        from_row = 8 - int(move.from_field[1])

        to_column = ord(move.to_field[0].lower()) - ord("a")
        to_row = 8 - int(move.to_field[1])

        piece = self.board[from_row][from_column]

        self.board[to_row][to_column] = piece
        self.board[from_row][from_column] = ""
        
        
    

