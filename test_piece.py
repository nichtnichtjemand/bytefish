import pytest

from board import Board
from move import Move
from piece import Piece


# ─────────────────────────────────────────
# Testbretter
# ─────────────────────────────────────────

@pytest.fixture
def board():
    return Board()


@pytest.fixture
def empty_board():
    board = Board()
    board.board = [["" for _ in range(8)] for _ in range(8)]
    return board


# ─────────────────────────────────────────
# Läufer: gültige diagonale Züge
# ─────────────────────────────────────────

@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("c1", "f4"),
        ("c1", "a3"),
        ("d4", "a7"),
        ("d4", "g7"),
        ("h8", "a1"),
        ("e5", "b2"),
    ],
)
def test_bishop_diagonal(empty_board, start, end):
    bishop = Piece("B")
    move = Move(start, end)

    assert bishop.is_legal_move(empty_board, move) is True


# ─────────────────────────────────────────
# Läufer: ungültige Züge
# ─────────────────────────────────────────

@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("c1", "c4"),
        ("c1", "f1"),
        ("d4", "d5"),
        ("d4", "e4"),
        ("d4", "d4"),
        ("a1", "b3"),
        ("c1", "e2"),
    ],
)
def test_bishop_invalid_moves(empty_board, start, end):
    bishop = Piece("B")
    move = Move(start, end)

    assert bishop.is_legal_move(empty_board, move) is False


# ─────────────────────────────────────────
# Läufer: eigene Figur darf nicht geschlagen werden
# ─────────────────────────────────────────

def test_bishop_cannot_capture_own_piece(empty_board):
    bishop = Piece("B")
    empty_board.board[4][5] = Piece("P")

    move = Move("c1", "f4")

    assert bishop.is_legal_move(empty_board, move) is False


# ─────────────────────────────────────────
# Läufer: gegnerische Figur darf geschlagen werden
# ─────────────────────────────────────────

def test_bishop_can_capture_enemy_piece(empty_board):
    bishop = Piece("B")
    empty_board.board[4][5] = Piece("p")

    move = Move("c1", "f4")

    assert bishop.is_legal_move(empty_board, move) is True


# ─────────────────────────────────────────
# Turm (Rook): gültige und ungültige Züge
# ─────────────────────────────────────────

@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("a1", "a8"),
        ("a1", "h1"),
        ("d4", "d8"),
        ("d4", "a4"),
    ],
)
def test_rook_valid_moves(empty_board, start, end):
    rook = Piece("R")
    move = Move(start, end)
    assert rook.is_legal_move(empty_board, move) is True


@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("a1", "b2"),
        ("d4", "e6"),
        ("a1", "a1"),
    ],
)
def test_rook_invalid_moves(empty_board, start, end):
    rook = Piece("R")
    move = Move(start, end)
    assert rook.is_legal_move(empty_board, move) is False


# ─────────────────────────────────────────
# Springer (Knight): gültige und ungültige Züge
# ─────────────────────────────────────────

@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("b1", "c3"),
        ("b1", "a3"),
        ("d4", "e6"),
        ("d4", "b5"),
        ("d4", "f3"),
    ],
)
def test_knight_valid_moves(empty_board, start, end):
    knight = Piece("N")
    move = Move(start, end)
    assert knight.is_legal_move(empty_board, move) is True


@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("b1", "b3"),
        ("d4", "d6"),
        ("b1", "d4"),
    ],
)
def test_knight_invalid_moves(empty_board, start, end):
    knight = Piece("N")
    move = Move(start, end)
    assert knight.is_legal_move(empty_board, move) is False


# ─────────────────────────────────────────
# Dame (Queen): Kombination aus Turm und Läufer
# ─────────────────────────────────────────

@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("d1", "d8"),
        ("d1", "h5"),
        ("d1", "a4"),
        ("d1", "d2"),
    ],
)
def test_queen_valid_moves(empty_board, start, end):
    queen = Piece("Q")
    move = Move(start, end)
    assert queen.is_legal_move(empty_board, move) is True


@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("d1", "f4"),
        ("d1", "c3"),
    ],
)
def test_queen_invalid_moves(empty_board, start, end):
    queen = Piece("Q")
    move = Move(start, end)
    assert queen.is_legal_move(empty_board, move) is False



@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("e1", "e2"),
        ("e1", "f1"),
        ("e1", "f2"),
        ("d4", "c5"),
    ],
)
def test_king_valid_moves(empty_board, start, end):
    king = Piece("K")
    move = Move(start, end)
    assert king.is_legal_move(empty_board, move) is True


@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("e1", "e3"),
        ("e1", "g1"),
        ("d4", "d6"),
    ],
)
def test_king_invalid_moves(empty_board, start, end):
    king = Piece("K")
    move = Move(start, end)
    assert king.is_legal_move(empty_board, move) is False


@pytest.mark.parametrize(
    ("start", "end", "is_white"),
    [
        ("e2", "e3", True),
        ("e2", "e4", True),
        ("e7", "e6", False),
        ("e7", "e5", False),
    ],
)
def test_pawn_forward_moves(empty_board, start, end, is_white):
    pawn_symbol = "P" if is_white else "p"
    pawn = Piece(pawn_symbol)
    move = Move(start, end)
    assert pawn.is_legal_move(empty_board, move) is True


def test_pawn_diagonal_capture_valid(empty_board):
    white_pawn = Piece("P")
    
    empty_board.board[3][3] = Piece("p") 
    
    empty_board.board[4][2] = white_pawn
    
    move = Move("c4", "d5")
    
    assert white_pawn.is_legal_move(empty_board, move) is True



def test_rook_blocked_by_piece(empty_board):
    rook = Piece("R")
    empty_board.board[7][4] = Piece("P") 
    
    move = Move("a1", "h1")
    assert rook.is_legal_move(empty_board, move) is False



def test_board_starts_with_32_pieces(board):
    pieces = [
        piece
        for row in board.board
        for piece in row
        if piece != ""
    ]

    assert len(pieces) == 32


def test_board_starts_with_white_to_move(board):
    assert board.current_turn is True



def test_move_rejects_empty_start_field(board):
    result = board.move(Move("e4", "e5"))

    assert isinstance(result, ValueError)


def test_move_rejects_wrong_color(board):
    result = board.move(Move("a7", "a6"))

    assert isinstance(result, ValueError)


def test_move_rejects_same_field(board):
    result = board.move(Move("e2", "e2"))

    assert isinstance(result, ValueError)


@pytest.mark.parametrize(
    ("start", "end"),
    [
        ("i9", "e4"),
        ("e2", "x9"),
        ("z0", "y1"),
    ],
)
def test_move_rejects_out_of_bounds(board, start, end):
    result = board.move(Move(start, end))
    assert isinstance(result, ValueError)



def test_move_changes_board_and_turn(board):
    white_pawn = board.board[6][4]

    result = board.move(Move("e2", "e4"))

    assert result is None
    assert board.board[4][4] is white_pawn
    assert board.board[6][4] == ""
    assert board.current_turn is False