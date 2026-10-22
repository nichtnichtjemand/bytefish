# PeSTO middlegame/endgame material and piece-square tables.
# Table rows are indexed from rank 1 to rank 8; board.mojo mirrors white
# squares before lookup so both colors use the same piece-relative orientation.
comptime MG_VALUES = [82, 337, 365, 477, 1025, 0]
comptime EG_VALUES = [94, 281, 297, 512, 936, 0]
comptime GAMEPHASE_INCREMENTS = [0, 1, 1, 2, 4, 0]

comptime MG_PAWN_TABLE = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [98, 134, 61, 95, 68, 126, 34, -11],
    [-6, 7, 26, 31, 65, 56, 25, -20],
    [-14, 13, 6, 21, 23, 12, 17, -23],
    [-27, -2, -5, 12, 17, 6, 10, -25],
    [-26, -4, -4, -10, 3, 3, 33, -12],
    [-35, -1, -20, -23, -15, 24, 38, -22],
    [0, 0, 0, 0, 0, 0, 0, 0]
]

comptime EG_PAWN_TABLE = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [178, 173, 158, 134, 147, 132, 165, 187],
    [94, 100, 85, 67, 56, 53, 82, 84],
    [32, 24, 13, 5, -2, 4, 17, 17],
    [13, 9, -3, -7, -7, -8, 3, -1],
    [4, 7, -6, 1, 0, -5, -1, -8],
    [13, 8, 8, 10, 13, 0, 2, -7],
    [0, 0, 0, 0, 0, 0, 0, 0]
]

comptime MG_KNIGHT_TABLE = [
    [-167, -89, -34, -49, 61, -97, -15, -107],
    [-73, -41, 72, 36, 23, 62, 7, -17],
    [-47, 60, 37, 65, 84, 129, 73, 44],
    [-9, 17, 19, 53, 37, 69, 18, 22],
    [-13, 4, 16, 13, 28, 19, 21, -8],
    [-23, -9, 12, 10, 19, 17, 25, -16],
    [-29, -53, -12, -3, -1, 18, -14, -19],
    [-105, -21, -58, -33, -17, -28, -19, -23]
]

comptime EG_KNIGHT_TABLE = [
    [-58, -38, -13, -28, -31, -27, -63, -99],
    [-25, -8, -25, -2, -9, -25, -24, -52],
    [-24, -20, 10, 9, -1, -9, -19, -41],
    [-17, 3, 22, 22, 22, 11, 8, -18],
    [-18, -6, 16, 25, 16, 17, 4, -18],
    [-23, -3, -1, 15, 10, -3, -20, -22],
    [-42, -20, -10, -5, -2, -20, -23, -44],
    [-29, -51, -23, -15, -22, -18, -50, -64]
]

comptime MG_BISHOP_TABLE = [
    [-29, 4, -82, -37, -25, -42, 7, -8],
    [-26, 16, -18, -13, 30, 59, 18, -47],
    [-16, 37, 43, 40, 35, 50, 37, -2],
    [-4, 5, 19, 50, 37, 37, 7, -2],
    [-6, 13, 13, 26, 34, 12, 10, 4],
    [0, 15, 15, 15, 14, 27, 18, 10],
    [4, 15, 16, 0, 7, 21, 33, 1],
    [-33, -3, -14, -21, -13, -12, -39, -21]
]

comptime EG_BISHOP_TABLE = [
    [-14, -21, -11, -8, -7, -9, -17, -24],
    [-8, -4, 7, -12, -3, -13, -4, -14],
    [2, -8, 0, -1, -2, 6, 0, 4],
    [-3, 9, 12, 9, 14, 10, 3, 2],
    [-6, 3, 13, 19, 7, 10, -3, -9],
    [-12, -3, 8, 10, 13, 3, -7, -15],
    [-14, -18, -7, -1, 4, -9, -15, -27],
    [-23, -9, -23, -5, -9, -16, -5, -17]
]

comptime MG_ROOK_TABLE = [
    [32, 42, 32, 51, 63, 9, 31, 43],
    [27, 32, 58, 62, 80, 67, 26, 44],
    [-5, 19, 26, 36, 17, 45, 61, 16],
    [-24, -11, 7, 26, 24, 35, -8, -20],
    [-36, -26, -12, -1, 9, -7, 6, -23],
    [-45, -25, -16, -17, 3, 0, -5, -33],
    [-44, -16, -20, -9, -1, 11, -6, -71],
    [-19, -13, 1, 17, 16, 7, -37, -26]
]

comptime EG_ROOK_TABLE = [
    [13, 10, 18, 15, 12, 12, 8, 5],
    [11, 13, 13, 11, -3, 3, 8, 3],
    [7, 7, 7, 5, 4, -3, -5, -3],
    [4, 3, 13, 1, 2, 1, -1, 2],
    [3, 5, 8, 4, -5, -6, -8, -11],
    [-4, 0, -5, -1, -7, -12, -8, -16],
    [-6, -6, 0, 2, -9, -9, -11, -3],
    [-9, 2, 3, -1, -5, -13, 4, -20]
]

comptime MG_QUEEN_TABLE = [
    [-28, 0, 29, 12, 59, 44, 43, 45],
    [-24, -39, -5, 1, -16, 57, 28, 54],
    [-13, -17, 7, 8, 29, 56, 47, 57],
    [-27, -27, -16, -16, -1, 17, -2, 1],
    [-9, -26, -9, -10, -2, -4, 3, -3],
    [-14, 2, -11, -2, -5, 2, 14, 5],
    [-35, -8, 11, 2, 8, 15, -3, 1],
    [-1, -18, -9, 10, -15, -25, -31, -50]
]

comptime EG_QUEEN_TABLE = [
    [-9, 22, 22, 27, 27, 19, 10, 20],
    [-17, 20, 32, 41, 58, 25, 30, 0],
    [-20, 6, 9, 49, 47, 35, 19, 9],
    [3, 22, 24, 45, 57, 40, 57, 36],
    [-18, 28, 19, 47, 31, 34, 39, 23],
    [-16, -27, 15, 6, 9, 17, 10, 5],
    [-22, -23, -30, -16, -16, -23, -36, -32],
    [-33, -28, -22, -43, -5, -32, -20, -41]
]

comptime MG_KING_TABLE = [
    [-65, 23, 16, -15, -56, -34, 2, 13],
    [29, -1, -20, -7, -8, -4, -38, -29],
    [-9, 24, 2, -16, -20, 6, 22, -22],
    [-17, -20, -12, -27, -30, -25, -14, -36],
    [-49, -1, -27, -39, -46, -44, -33, -51],
    [-14, -14, -22, -46, -44, -30, -15, -27],
    [1, 7, -8, -64, -43, -16, 9, 8],
    [-15, 36, 12, -54, 8, -28, 24, 14]
]

comptime EG_KING_TABLE = [
    [-74, -35, -18, -18, -11, 15, 4, -17],
    [-12, 17, 14, 17, 17, 38, 23, 11],
    [10, 17, 23, 15, 20, 45, 44, 13],
    [-8, 22, 24, 27, 26, 33, 26, 3],
    [-18, -4, 21, 24, 27, 23, 9, -11],
    [-19, -3, 11, 21, 23, 16, 7, -9],
    [-27, -11, 4, 13, 14, 4, -5, -17],
    [-53, -34, -21, -11, -28, -14, -24, -43]
]

def _piece_index(piece_type: String) -> Int:
    if piece_type == "p":
        return 0
    if piece_type == "n":
        return 1
    if piece_type == "b":
        return 2
    if piece_type == "r":
        return 3
    if piece_type == "q":
        return 4
    return 5


def mg_value(piece_type: String) -> Int:
    return materialize[MG_VALUES]()[_piece_index(piece_type)]


def eg_value(piece_type: String) -> Int:
    return materialize[EG_VALUES]()[_piece_index(piece_type)]


def _piece_index(piece_kind: UInt8) -> Int:
    return Int(piece_kind) - 1


def mg_value(piece_kind: UInt8) -> Int:
    return materialize[MG_VALUES]()[_piece_index(piece_kind)]


def eg_value(piece_kind: UInt8) -> Int:
    return materialize[EG_VALUES]()[_piece_index(piece_kind)]


def gamephase_increment(piece_type: String) -> Int:
    return materialize[GAMEPHASE_INCREMENTS]()[_piece_index(piece_type)]


def gamephase_increment(piece_kind: UInt8) -> Int:
    return materialize[GAMEPHASE_INCREMENTS]()[_piece_index(piece_kind)]


def _piece_square_bonus(
    piece_type: String, row: Int, column: Int, endgame: Bool
) -> Int:
    if piece_type == "p":
        if endgame:
            return materialize[EG_PAWN_TABLE]()[row][column]
        return materialize[MG_PAWN_TABLE]()[row][column]
    if piece_type == "n":
        if endgame:
            return materialize[EG_KNIGHT_TABLE]()[row][column]
        return materialize[MG_KNIGHT_TABLE]()[row][column]
    if piece_type == "b":
        if endgame:
            return materialize[EG_BISHOP_TABLE]()[row][column]
        return materialize[MG_BISHOP_TABLE]()[row][column]
    if piece_type == "r":
        if endgame:
            return materialize[EG_ROOK_TABLE]()[row][column]
        return materialize[MG_ROOK_TABLE]()[row][column]
    if piece_type == "q":
        if endgame:
            return materialize[EG_QUEEN_TABLE]()[row][column]
        return materialize[MG_QUEEN_TABLE]()[row][column]
    if endgame:
        return materialize[EG_KING_TABLE]()[row][column]
    return materialize[MG_KING_TABLE]()[row][column]


def mg_piece_square_bonus(piece_type: String, row: Int, column: Int) -> Int:
    return _piece_square_bonus(piece_type, row, column, False)


def eg_piece_square_bonus(piece_type: String, row: Int, column: Int) -> Int:
    return _piece_square_bonus(piece_type, row, column, True)


def mg_piece_square_bonus(piece_kind: UInt8, row: Int, column: Int) -> Int:
    if piece_kind == UInt8(1):
        return materialize[MG_PAWN_TABLE]()[row][column]
    if piece_kind == UInt8(2):
        return materialize[MG_KNIGHT_TABLE]()[row][column]
    if piece_kind == UInt8(3):
        return materialize[MG_BISHOP_TABLE]()[row][column]
    if piece_kind == UInt8(4):
        return materialize[MG_ROOK_TABLE]()[row][column]
    if piece_kind == UInt8(5):
        return materialize[MG_QUEEN_TABLE]()[row][column]
    return materialize[MG_KING_TABLE]()[row][column]


def eg_piece_square_bonus(piece_kind: UInt8, row: Int, column: Int) -> Int:
    if piece_kind == UInt8(1):
        return materialize[EG_PAWN_TABLE]()[row][column]
    if piece_kind == UInt8(2):
        return materialize[EG_KNIGHT_TABLE]()[row][column]
    if piece_kind == UInt8(3):
        return materialize[EG_BISHOP_TABLE]()[row][column]
    if piece_kind == UInt8(4):
        return materialize[EG_ROOK_TABLE]()[row][column]
    if piece_kind == UInt8(5):
        return materialize[EG_QUEEN_TABLE]()[row][column]
    return materialize[EG_KING_TABLE]()[row][column]


# Kept for callers that need a phase-specific piece-square bonus.
def pawn_bonus(row: Int, column: Int) -> Int:
    return mg_piece_square_bonus("p", row, column)


def knight_bonus(row: Int, column: Int) -> Int:
    return mg_piece_square_bonus("n", row, column)


def bishop_bonus(row: Int, column: Int) -> Int:
    return mg_piece_square_bonus("b", row, column)


def rook_bonus(row: Int, column: Int) -> Int:
    return mg_piece_square_bonus("r", row, column)


def queen_bonus(row: Int, column: Int) -> Int:
    return mg_piece_square_bonus("q", row, column)


def king_bonus(row: Int, column: Int) -> Int:
    return mg_piece_square_bonus("k", row, column)


def king_endgame_bonus(row: Int, column: Int) -> Int:
    return eg_piece_square_bonus("k", row, column)
