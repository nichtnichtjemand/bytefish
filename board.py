from move import Move
from piece import Piece

from copy import deepcopy

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

        from_column = move.from_column
        from_row = move.from_row
        to_column = move.to_column
        to_row = move.to_row

        if (from_row < 0) or (to_row < 0) or (from_column < 0) or (to_column < 0) or (from_row > 7) or (to_row > 7) or (from_column > 7) or (to_column > 7):
            return False

        from_piece = self.board[from_row][from_column]
        to_piece = self.board[to_row][to_column]
        if from_piece == "":
            return False
        if to_piece != "":
            if from_piece.color == to_piece.color:
                return False
        if from_piece.color != self.current_turn:
            return False
        if from_column == to_column and from_row == to_row:
            return False

        if not from_piece.is_legal_move(self, move):
            return False
        
        self.board[to_row][to_column] = from_piece
        self.board[from_row][from_column] = ""
        self.current_turn = not self.current_turn

        return True

    def get_legal_moves(self):
        legal_moves = []

        for from_row in range(8):
            for from_column in range(8):
                piece = self.board[from_row][from_column]

                if piece == "" or piece.color != self.current_turn:
                    continue

                from_field = chr(ord("a") + from_column) + str(8 - from_row)

                for to_row in range(8):
                    for to_column in range(8):
                        to_field = chr(ord("a") + to_column) + str(8 - to_row)

                        move = Move(from_field, to_field)

                        if piece.is_legal_move(self, move):
                            legal_moves.append(move)

        return legal_moves

    def get_material_score(self):
        rating = 0

        piece_values = {
            "p": 1, "n": 3, "b": 3, "r": 5, "q": 9, "k": 0, "P": -1, "N": -3, "B": -3, "R": -5, "Q": -9, "K": 0
        }

        
        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece !=  "":
                    rating += piece_values[piece.piece]
        return rating

    def copy(self):
        return deepcopy(self)

    def best_move(self):
        moves = self.get_legal_moves()
        ratings = {}
        for move in moves:
            copy: Board = self.copy()
            copy.move(move)
            rating = copy.get_material_score()
            ratings[move] = rating
        ratings = dict(sorted(ratings.items(), key=lambda x: x[1])) if self.current_turn else dict(sorted(ratings.items(), key=lambda x: x[1], reverse=True))
        return next(iter(ratings))
