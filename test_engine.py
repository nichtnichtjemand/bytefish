import pytest

from board import Board
from move import Move
from piece import Piece


def make_move(from_field, to_field):
    return Move(from_field, to_field)


def empty_board():
    """Erstellt ein leeres Brett für isolierte Tests."""
    board = Board()
    board.board = [["" for _ in range(8)] for _ in range(8)]
    board.current_turn = True
    return board


def place_piece(board, field, piece):
    """Setzt eine Figur auf ein Feld, z. B. 'e4'."""
    column = ord(field[0].lower()) - ord("a")
    row = 8 - int(field[1])
    board.board[row][column] = Piece(piece)


def coordinates_valid(move):
    """Prüft, ob alle Zugkoordinaten auf dem Brett liegen."""
    return all(
        0 <= coordinate < 8
        for coordinate in (
            move.from_row,
            move.from_column,
            move.to_row,
            move.to_column,
        )
    )



def test_initial_board_has_32_pieces():
    board = Board()

    pieces = [
        piece
        for row in board.board
        for piece in row
        if piece != ""
    ]

    assert len(pieces) == 32


def test_initial_material_score_is_zero():
    board = Board()

    assert board.get_material_score() == 0


def test_initial_legal_moves_count():
    board = Board()

    assert len(board.get_legal_moves()) == 20



@pytest.mark.parametrize(
    ("from_field", "to_field"),
    [
        ("z9", "e4"),
        ("e2", "z9"),
        ("", "e4"),
        ("e2", ""),
        ("invalid", "e4"),
    ],
)
def test_invalid_move_coordinates(from_field, to_field):
    move = make_move(from_field, to_field)

    assert not coordinates_valid(move)


def test_valid_move_coordinates():
    move = make_move("e2", "e4")

    assert coordinates_valid(move)



@pytest.mark.parametrize(
    ("from_field", "to_field", "valid"),
    [
        ("e2", "e4", True),
        ("e2", "e5", False),
        ("b1", "c3", True),
        ("b1", "b3", False),
        ("e2", "e2", False),
        ("z9", "e4", False),
        ("e2", "z9", False),
    ],
)
def test_piece_movement(from_field, to_field, valid):
    board = Board()
    move = make_move(from_field, to_field)

    if not coordinates_valid(move):
        assert valid is False
        assert not board.move(move)
        return

    piece = board.board[move.from_row][move.from_column]

    if piece == "":
        assert not board.move(move)
    else:
        assert piece.is_legal_move(board, move) is valid


def test_knight_can_jump_over_pieces():
    board = Board()
    knight = board.board[7][1]

    assert knight.is_legal_move(board, make_move("b1", "c3"))


def test_rook_cannot_jump_over_pieces():
    board = Board()
    rook = board.board[7][0]

    assert not rook.is_legal_move(board, make_move("a1", "a3"))


def test_bishop_moves_diagonally():
    board = empty_board()
    place_piece(board, "c1", "B")
    bishop = board.board[7][2]

    assert bishop.is_legal_move(board, make_move("c1", "f4"))
    assert not bishop.is_legal_move(board, make_move("c1", "c4"))


def test_queen_moves_straight_and_diagonally():
    board = empty_board()
    place_piece(board, "d4", "Q")
    queen = board.board[4][3]

    assert queen.is_legal_move(board, make_move("d4", "d7"))
    assert queen.is_legal_move(board, make_move("d4", "g7"))
    assert not queen.is_legal_move(board, make_move("d4", "e6"))



def test_valid_move_changes_board():
    board = Board()

    assert board.move(make_move("e2", "e4"))
    assert board.board[4][4].piece == "P"
    assert board.board[6][4] == ""


def test_valid_move_changes_turn():
    board = Board()

    assert board.current_turn is True
    assert board.move(make_move("e2", "e4"))
    assert board.current_turn is False


def test_cannot_move_empty_square():
    board = Board()

    assert not board.move(make_move("e3", "e4"))


def test_cannot_move_opponents_piece():
    board = Board()

    assert not board.move(make_move("e7", "e5"))


def test_cannot_capture_own_piece():
    board = Board()

    assert not board.move(make_move("e2", "d2"))


def test_cannot_move_to_same_square():
    board = Board()

    assert not board.move(make_move("e2", "e2"))


def test_failed_move_does_not_change_turn():
    board = Board()

    assert not board.move(make_move("e2", "e5"))
    assert board.current_turn is True


@pytest.mark.parametrize(
    ("from_field", "to_field"),
    [
        ("z9", "e4"),
        ("e2", "z9"),
        ("", "e4"),
        ("e2", ""),
    ],
)
def test_board_rejects_invalid_coordinates(from_field, to_field):
    board = Board()

    assert not board.move(make_move(from_field, to_field))

