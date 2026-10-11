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
# Brettinitialisierung
# ─────────────────────────────────────────

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


# ─────────────────────────────────────────
# Board.move(): Fehlerfälle
# ─────────────────────────────────────────

def test_move_rejects_empty_start_field(board):
    result = board.move(Move("e4", "e5"))

    assert isinstance(result, ValueError)


def test_move_rejects_wrong_color(board):
    result = board.move(Move("a7", "a6"))

    assert isinstance(result, ValueError)


def test_move_rejects_same_field(board):
    result = board.move(Move("e2", "e2"))

    assert isinstance(result, ValueError)


# ─────────────────────────────────────────
# Board.move(): erfolgreicher Zug
# ─────────────────────────────────────────

def test_move_changes_board_and_turn(board):
    white_pawn = board.board[6][4]

    result = board.move(Move("e2", "e4"))

    assert result is None
    assert board.board[4][4] is white_pawn
    assert board.board[6][4] == ""
    assert board.current_turn is False
