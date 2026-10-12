from move import Move
from piece import Piece
import piece_square_tables as tables

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



    def reset(self):
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


    def get_position_score(self):
        score = 0

        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece != "":

                    table_row = row if piece.color else 7 - row
                    bonus = tables.PIECE_SQUARE_TABLES[piece.type][table_row][column]

                    if piece.color:
                        score -= bonus
                    else:
                        score += bonus

        return score


    def evaluate(self, board):
        return board.get_material_score() + board.get_position_score()
    

    def best_move(self):
        moves = self.get_legal_moves()

        if not moves:
            return None

        best_move = None
        alpha = float("-inf")
        beta = float("inf")

        if self.current_turn:
            best_score = float("inf")  # Weiß minimiert
        else:
            best_score = float("-inf")  # Schwarz maximiert

        for move in moves:
            child = self.copy()
            child.move(move)

            score = child.minimax(3, alpha, beta)

            if self.current_turn:
                if score < best_score:
                    best_score = score
                    best_move = move

                beta = min(beta, best_score)
            else:
                if score > best_score:
                    best_score = score
                    best_move = move

                alpha = max(alpha, best_score)

        return best_move


    def minimax(self, depth, alpha=float("-inf"), beta=float("inf")):
        if depth == 0:
            return self.evaluate(self)

        moves = self.get_legal_moves()

        if not moves:
            # Schachmatt und Patt werden später separat behandelt.
            return self.evaluate(self)

        if self.current_turn:
            # Weiß minimiert den Score.
            best_score = float("inf")

            for move in moves:
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta)
                best_score = min(best_score, score)
                beta = min(beta, best_score)

                if beta <= alpha:
                    break

        else:
            # Schwarz maximiert den Score.
            best_score = float("-inf")

            for move in moves:
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta)
                best_score = max(best_score, score)
                alpha = max(alpha, best_score)

                if beta <= alpha:
                    break

        return best_score


        
        

import time

board = Board()

start = time.perf_counter()
move = board.best_move()
elapsed = time.perf_counter() - start

print(f"Zug: {move.from_field}{move.to_field}")
print(f"Zeit: {elapsed:.3f} Sekunden")