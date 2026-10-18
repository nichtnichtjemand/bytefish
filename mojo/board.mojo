from std.python import Python, PythonObject
from std.time import monotonic
from std.collections import Optional

from move import Move
from piece import Piece


struct SearchTimeout:
    var message: String

    def __init__(out self, message: String = "SearchTimeout: The UCI search budget has expired."):
        self.message = message

    def error(self) -> Error:
        return Error(self.message)



struct Board:
    var current_turn: Bool
    var history: PythonObject
    var transposition_table: PythonObject
    var board: List[List[Piece]]
    var repetition_counts: PythonObject
    var castling_rights: String
    var en_passant_square: String
    var halfmove_clock: Int
    var fullmove_number: Int
    var tablebase: PythonObject

    def __init__(out self, tablebase: PythonObject = PythonObject()) raises:
        var setup = [
            ["r", "n", "b", "q", "k", "b", "n", "r"],
            ["p", "p", "p", "p", "p", "p", "p", "p"],
            ["", "", "", "", "", "", "", ""],
            ["", "", "", "", "", "", "", ""],
            ["", "", "", "", "", "", "", ""],
            ["", "", "", "", "", "", "", ""],
            ["P", "P", "P", "P", "P", "P", "P", "P"],
            ["R", "N", "B", "Q", "K", "B", "N", "R"],
        ]
        self.current_turn = True
        try:
            var py = Python.import_module("builtins")
            self.history = py.dict()
            self.transposition_table = py.dict()
            self.repetition_counts = py.dict()
            self.board = List[List[Piece]]()
        except e:
            raise Error("Failed to import builtins module")


        
        for row in setup:
            var new_row = List[Piece]()
            for char in row:
                new_row.append(Piece(char))
            self.board.append(new_row^)
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        
        if tablebase:
            self.tablebase = tablebase
        else:
            try:
                var syzygy = Python.import_module("syzygy")
                var default_path = syzygy.SyzygyTablebase.default_path()
                if default_path:
                    self.tablebase = syzygy.SyzygyTablebase(default_path)
                else:
                    self.tablebase = PythonObject()
            except:
                self.tablebase = PythonObject()
        self._record_position()

    def move(mut self, move: Move) -> Bool:
        var from_column = move.from_column
        var from_row = move.from_row
        var to_column = move.to_column
        var to_row = move.to_row

        if (
            (from_row < 0)
            or (to_row < 0)
            or (from_column < 0)
            or (to_column < 0)
            or (from_row > 7)
            or (to_row > 7)
            or (from_column > 7)
            or (to_column > 7)
        ):
            return False

        var from_piece = self.board[from_row][from_column]
        var to_piece = self.board[to_row][to_column]
        if from_piece.piece == "":
            return False

        var is_en_passant = self.is_en_passant(move)
        if to_piece.piece != "":
            if from_piece.color == to_piece.color:
                return False
        if from_piece.color != self.current_turn:
            return False
        if from_column == to_column and from_row == to_row:
            return False

        var is_castling = (
            from_piece.type == "k"
            and from_row == to_row
            and abs(to_column - from_column) == 2
        )

        if is_castling:
            if not self._can_castle(move):
                return False

            var rook_from_column = 7 if to_column > from_column else 0
            var rook_to_column = 5 if to_column > from_column else 3
            var rook = self.board[from_row][rook_from_column]

            self.board[to_row][to_column] = from_piece
            self.board[from_row][from_column] = Piece("")
            self.board[from_row][rook_to_column] = rook
            self.board[from_row][rook_from_column] = Piece("")
            self._remove_castling_rights(from_piece)
            self._finish_move(move, from_piece, to_piece, False)
            return True

        if not from_piece.is_legal_move(self, move):
            return False

        if is_en_passant:
            var captured_row = to_row + (1 if from_piece.color else -1)
            self.board[captured_row][to_column] = Piece("")

        if from_piece.type == "p" and to_row in (0, 7):
            var promotion = "q"
            if move.promotion:
                promotion = move.promotion.value()
            if promotion.lower() not in ("q", "r", "b", "n"):
                return False
            var promoted_piece = promotion.lower()
            if from_piece.color:
                promoted_piece = promoted_piece.upper()
            self.board[to_row][to_column] = Piece(promoted_piece)
        else:
            if move.promotion:
                return False
            self.board[to_row][to_column] = from_piece

        self.board[from_row][from_column] = Piece("")
        self._update_castling_rights(move, from_piece, to_piece)
        self._finish_move(
            move,
            from_piece,
            to_piece,
            is_capture=to_piece.piece != "" or is_en_passant,
        )
        self._record_position()
        return True

    def is_en_passant(self, move: Move) -> Bool:
        if self.en_passant_square == "-":
            return False
        var from_piece = self.board[move.from_row][move.from_column]
        var target = self.board[move.to_row][move.to_column]
        if from_piece.piece == "" or from_piece.type != "p" or target.piece != "":
            return False
        if move.to_field.lower() != self.en_passant_square.lower():
            return False
        var direction = -1 if from_piece.color else 1
        if move.to_row - move.from_row != direction:
            return False
        if abs(move.to_column - move.from_column) != 1:
            return False
        var captured = self.board[move.from_row][move.to_column]
        return (
            captured.piece != ""
            and captured.type == "p"
            and captured.color != from_piece.color
        )

    def _finish_move(
        mut self,
        move: Move,
        from_piece: Piece,
        to_piece: Piece,
        is_capture: Bool,
    ):
        var was_double_pawn_move = (
            from_piece.type == "p" and abs(move.to_row - move.from_row) == 2
        )
        self.en_passant_square = "-"
        if was_double_pawn_move:
            var target_row = (move.from_row + move.to_row) // 2
            self.en_passant_square = (
                move.from_field[byte=0].lower() + String(8 - target_row)
            )

        if from_piece.type == "p" or is_capture:
            self.halfmove_clock = 0
        else:
            self.halfmove_clock += 1

        self.current_turn = not self.current_turn
        if self.current_turn:
            self.fullmove_number += 1

    def _position_key(self) raises -> PythonObject:
        var py = Python.import_module("builtins")
        var pieces_list = py.list()
        for row in self.board:
            for piece in row:
                _ = pieces_list.append(piece.piece if piece.piece != "" else "")
        var key_parts = py.list()
        _ = key_parts.append(py.tuple(pieces_list))
        _ = key_parts.append(self.current_turn)
        _ = key_parts.append(self.castling_rights)
        _ = key_parts.append(self.en_passant_square)
        return py.tuple(key_parts)

    def _record_position(mut self) raises:
        var key = self._position_key()
        var count = self.repetition_counts.get(key, 0)
        self.repetition_counts[key] = Int(count) + 1

    def is_threefold_repetition(self) raises -> Bool:
        var key = self._position_key()
        var count = self.repetition_counts.get(key, 0)
        return Int(count) >= 3

    def _can_castle(self, move: Move) -> Bool:
        var row = move.from_row
        var is_white = self.current_turn
        var king_side = move.to_column > move.from_column
        var right = ("K" if king_side else "Q") if is_white else ("k" if king_side else "q")
        var rook_column = 7 if king_side else 0

        if move.from_column != 4 or move.to_row != row:
            return False
        if right not in self.castling_rights:
            return False

        if king_side:
            if self.board[row][5].piece != "" or self.board[row][6].piece != "":
                return False
        else:
            if self.board[row][1].piece != "" or self.board[row][2].piece != "" or self.board[row][3].piece != "":
                return False

        var rook = self.board[row][rook_column]
        if rook.piece == "" or rook.type != "r" or rook.color != is_white:
            return False
        if self.is_in_check(is_white):
            return False

        var enemy_color = not is_white
        var transit_column = 5 if king_side else 3
        if self.is_square_attacked(row, transit_column, enemy_color):
            return False
        return True

    def _remove_castling_rights(mut self, piece: Piece):
        if piece.color:
            self.castling_rights = self.castling_rights.replace("K", "").replace("Q", "")
        else:
            self.castling_rights = self.castling_rights.replace("k", "").replace("q", "")

    def _update_castling_rights(mut self, move: Move, from_piece: Piece, to_piece: Piece):
        if from_piece.type == "k":
            self._remove_castling_rights(from_piece)
        elif from_piece.type == "r":
            var from_field_lower = move.from_field.lower()
            if from_field_lower == "a1":
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif from_field_lower == "h1":
                self.castling_rights = self.castling_rights.replace("K", "")
            elif from_field_lower == "a8":
                self.castling_rights = self.castling_rights.replace("q", "")
            elif from_field_lower == "h8":
                self.castling_rights = self.castling_rights.replace("k", "")

        if to_piece.piece != "" and to_piece.type == "r":
            var to_field_lower = move.to_field.lower()
            if to_field_lower == "a1":
                self.castling_rights = self.castling_rights.replace("Q", "")
            elif to_field_lower == "h1":
                self.castling_rights = self.castling_rights.replace("K", "")
            elif to_field_lower == "a8":
                self.castling_rights = self.castling_rights.replace("q", "")
            elif to_field_lower == "h8":
                self.castling_rights = self.castling_rights.replace("k", "")

    def is_in_check(self, color: Bool) -> Bool:
        return False

    def is_square_attacked(self, row: Int, col: Int, color: Bool) -> Bool:
        return False

    def is_checkmate(self, color: Bool) -> Bool:
        return False

    def quiescence(self, alpha: Int, beta: Int, deadline: Optional[Float64]) -> Int:
        return self.evaluate()

    def order_moves(self, moves: List[Move]) -> List[Move]:
        return moves^

    def get_legal_moves(self) -> List[Move]:
        var legal_moves = List[Move]()
        for from_row in range(8):
            for from_column in range(8):
                var piece = self.board[from_row][from_column]
                if piece.piece == "" or piece.color != self.current_turn:
                    continue
                var from_field = chr(ord("a") + from_column) + String(8 - from_row)
                for candidate in piece.get_candidate_moves(self, from_row, from_column):
                    var to_row = candidate.to_row
                    var to_column = candidate.to_column
                    var to_field = chr(ord("a") + to_column) + String(8 - to_row)
                    if piece.type == "p" and to_row in (0, 7):
                        for promotion in ("q", "r", "b", "n"):
                            var move = Move(from_field, to_field, promotion)
                            var child = self.copy()
                            if child.move(move) and not child.is_in_check(self.current_turn):
                                legal_moves.append(move^)
                    else:
                        var move = Move(from_field, to_field, "")
                        var child = self.copy()
                        if child.move(move) and not child.is_in_check(self.current_turn):
                            legal_moves.append(move^)
        return legal_moves^

    def get_material_score(self) -> Int:
        var rating = 0
        for row in range(8):
            for column in range(8):
                var piece = self.board[row][column]
                if piece.piece != "":
                    var p_type = piece.piece
                    if p_type == "p": rating += 100
                    elif p_type == "n": rating += 300
                    elif p_type == "b": rating += 300
                    elif p_type == "r": rating += 500
                    elif p_type == "q": rating += 900
                    elif p_type == "P": rating -= 100
                    elif p_type == "N": rating -= 300
                    elif p_type == "B": rating -= 300
                    elif p_type == "R": rating -= 500
                    elif p_type == "Q": rating -= 900
        return rating

    def copy(self) -> Board:
        var new_board = Board(self.tablebase)
        new_board.board = List[List[Piece]]()
        for row in self.board:
            var new_row = List[Piece]()
            for piece in row:
                new_row.append(piece)
            new_board.board.append(new_row^)
        new_board.current_turn = self.current_turn
        new_board.castling_rights = self.castling_rights
        new_board.en_passant_square = self.en_passant_square
        new_board.halfmove_clock = self.halfmove_clock
        new_board.fullmove_number = self.fullmove_number
        new_board.history = self.history
        new_board.transposition_table = self.transposition_table
        new_board.repetition_counts = self.repetition_counts
        return new_board

    def find_mate_in_one(self) -> Optional[Move]:
        for move in self.get_legal_moves():
            var test_board = self.copy()
            if not test_board.move(move):
                continue
            if test_board.is_checkmate(test_board.current_turn):
                return move
        return None

    def reset(mut self):
        var setup = [
            ["r", "n", "b", "q", "k", "b", "n", "r"],
            ["p", "p", "p", "p", "p", "p", "p", "p"],
            ["", "", "", "", "", "", "", ""],
            ["", "", "", "", "", "", "", ""],
            ["", "", "", "", "", "", "", ""],
            ["", "", "", "", "", "", "", ""],
            ["P", "P", "P", "P", "P", "P", "P", "P"],
            ["R", "N", "B", "Q", "K", "B", "N", "R"],
        ]
        self.current_turn = True
        self.board = List[List[Piece]]()
        for row in setup:
            var new_row = List[Piece]()
            for char in row:
                new_row.append(Piece(char))
            self.board.append(new_row^)
        self.castling_rights = "KQkq"
        self.en_passant_square = "-"
        self.halfmove_clock = 0
        self.fullmove_number = 1
        var py = Python.import_module("builtins")
        self.history = py.dict()
        self.transposition_table = py.dict()
        self.repetition_counts = py.dict()
        self._record_position()

    def get_position_score(self) -> Int:
        var score = 0
        try:
            var tables = Python.import_module("piece_square_tables")
            var pst = tables.PIECE_SQUARE_TABLES
            for row in range(8):
                for column in range(8):
                    var piece = self.board[row][column]
                    if piece.piece != "":
                        var table_row = row if piece.color else 7 - row
                        var bonus = Int(pst[piece.type][table_row][column])
                        if piece.color:
                            score -= bonus
                        else:
                            score += bonus
        except:
            pass
        return score

    def _piece_count(self) -> Int:
        var count = 0
        for row in self.board:
            for piece in row:
                if piece.piece != "":
                    count += 1
        return count

    def is_endgame(self) -> Bool:
        return self._piece_count() - 2 <= 10

    def _is_passed_pawn(self, row: Int, column: Int, color: Bool) -> Bool:
        var enemy_pawn = "p" if color else "P"
        for enemy_row in range(8):
            var enemy = self.board[enemy_row][column]
            if enemy.piece != "" and enemy.piece == enemy_pawn:
                if (color and enemy_row < row) or (not color and enemy_row > row):
                    return False
            for adjacent_column in [column - 1, column + 1]:
                if 0 <= adjacent_column < 8:
                    var adj_enemy = self.board[enemy_row][adjacent_column]
                    if adj_enemy.piece != "" and adj_enemy.piece == enemy_pawn:
                        if (color and enemy_row < row) or (not color and enemy_row > row):
                            return False
        return True

    def get_endgame_score(self) -> Int:
        if not self.is_endgame():
            return 0
        var score = 0
        return score

    def get_hanging_piece_score(self) -> Int:
        return 0

    def get_pawn_structure_score(self) -> Int:
        return 0

    def get_mobility_score(self) -> Int:
        return 0

    def get_king_safety_score(self) -> Int:
        return 0

    def evaluate(self) -> Int:
        if self.tablebase:
            try:
                var wdl = self.tablebase.probe_wdl(self)
                if wdl:
                    var perspective = -1 if self.current_turn else 1
                    return perspective * Int(wdl) * 100000
            except:
                pass

        var score = self.get_material_score() + self.get_position_score()
        score += self.get_pawn_structure_score()
        score += self.get_mobility_score()
        score += self.get_king_safety_score()
        score += self.get_hanging_piece_score()
        return score

    def best_move(self, depth: Int, deadline: Optional[Float64] = None) -> Optional[Move]:
        var moves = self.order_moves(self.get_legal_moves())
        if len(moves) == 0:
            return None
        self._check_deadline(deadline)
        var mate_move = self.find_mate_in_one()
        if mate_move is not None:
            return mate_move
        return moves[0]

    @staticmethod
    def _check_deadline(deadline: Optional[Float64]):
        if deadline:
            if monotonic() >= deadline.value():
                raise SearchTimeout()

    def minimax(
        mut self,
        depth: Int,
        alpha: Int = -1000000,
        beta: Int = 1000000,
        deadline: Optional[Float64] = None,
    ) -> Int:
        self._check_deadline(deadline)
        if self.is_threefold_repetition() or self.halfmove_clock >= 100:
            return 0
        if depth <= 0:
            return self.quiescence(alpha, beta, deadline)
        return self.evaluate()