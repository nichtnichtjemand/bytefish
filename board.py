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
        self.history = {}
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

                for to_row in range(8):
                    for to_column in range(8):
                        from_field = (
                            chr(ord("a") + from_column)
                            + str(8 - from_row)
                        )
                        to_field = (
                            chr(ord("a") + to_column)
                            + str(8 - to_row)
                        )

                        move = Move(from_field, to_field)

                        if not piece.is_legal_move(self, move):
                            continue

                        # Zug auf einer Kopie ausprobieren
                        child = self.copy()
                        child.move(move)

                        # Eigener König darf nicht im Schach stehen
                        if not child.is_in_check(self.current_turn):
                            legal_moves.append(move)

        return legal_moves


    def get_material_score(self):
        rating = 0

        piece_values = {
            "p": 100, "n": 300, "b": 300, "r": 500, "q": 900, "k": 0, 
            "P": -100, "N": -300, "B": -300, "R": -500, "Q": -900, "K": 0
        }
        
        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]
                if piece !=  "":
                    rating += piece_values[piece.piece]
        return rating

    def copy(self):
        # Viel schneller als deepcopy, da nur die Listen kopiert werden
        new_board = Board()
        new_board.current_turn = self.current_turn
        # Erstellt flache Kopien der Zeilen (die Piece-Objekte bleiben gleich)
        new_board.board = [row[:] for row in self.board]
        return new_board



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
    

    def best_move(self, depth):
        moves = self.order_moves(self.get_legal_moves())

        if not moves:
            return None

        best_move = None
        alpha = float("-inf")
        beta = float("inf")

        if self.current_turn:
            best_score = float("inf")
        else:
            best_score = float("-inf") 

        for move in moves:
            child = self.copy()
            child.move(move)

            score = child.minimax(depth, alpha, beta)

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

        moves = self.order_moves(self.get_legal_moves())

        if not moves:
            if self.is_in_check(self.current_turn):
                if self.current_turn:
                    return 100000 + depth
                else:
                    return -100000 - depth

            return 0

        if self.current_turn:
            best_score = float("inf")

            for move in moves:
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta)
                best_score = min(best_score, score)
                beta = min(beta, best_score)

                if beta <= alpha:
                    key = (
                        move.from_row,
                        move.from_column,
                        move.to_row,
                        move.to_column
                    )
                    self.history[key] = self.history.get(key, 0) + depth * depth
                    break

        else:
            best_score = float("-inf")

            for move in moves:
                child = self.copy()
                child.move(move)

                score = child.minimax(depth - 1, alpha, beta)
                best_score = max(best_score, score)
                alpha = max(alpha, best_score)

                if beta <= alpha:
                    key = (
                        move.from_row,
                        move.from_column,
                        move.to_row,
                        move.to_column
                    )
                    self.history[key] = self.history.get(key, 0) + depth * depth
                    break

        return best_score


    def order_moves(self, moves):
        def move_value(move):

            from_piece = self.board[move.from_row][move.from_column]
            to_piece = self.board[move.to_row][move.to_column]
            
            score = 0
            if to_piece != "":
                piece_values = {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9, "k": 0}
                score += 1000 + (piece_values[to_piece.piece.lower()] * 10 - piece_values[from_piece.piece.lower()])
            
            key = (move.from_row, move.from_column, move.to_row, move.to_column)
            score += self.history.get(key, 0)
            return score

        return sorted(moves, key=move_value, reverse=True)



    def is_in_check(self, color):

        for row in range(8):
            for column in range(8):
                piece = self.board[row][column]

                if (
                    piece != ""
                    and piece.type == "k"
                    and piece.color == color
                ):
                    enemy_color = not color

                    return self.is_square_attacked(
                        row,
                        column,
                        enemy_color
                    )

        raise ValueError("König nicht gefunden")


    def is_square_attacked(self, row, column, by_color):
        for from_row in range(8):
            for from_column in range(8):
                piece = self.board[from_row][from_column]

                if piece == "" or piece.color != by_color:
                    continue

                # Bauern greifen diagonal an
                if piece.type == "p":
                    direction = 1 if piece.color is False else -1

                    if (
                        row == from_row + direction
                        and abs(column - from_column) == 1
                    ):
                        return True

                    continue

                move = Move(
                    chr(ord("a") + from_column) + str(8 - from_row),
                    chr(ord("a") + column) + str(8 - row)
                )

                if piece.is_legal_move(self, move):
                    return True

        return False

    def is_checkmate(self, color):
        if not self.is_in_check(color):
            return False

        old_turn = self.current_turn
        self.current_turn = color

        try:
            return len(self.get_legal_moves()) == 0
        finally:
            self.current_turn = old_turn
