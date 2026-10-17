import pytest

from board import Board
from move import Move
from piece import Piece
from uci import parse_uci_move, uci_move_to_string


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


def test_fen_round_trip():
    board = Board()
    fen = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 4 12"

    board.load_fen(fen)

    assert board.to_fen() == fen


def test_syzygy_probe_for_five_or_fewer_pieces():
    board = Board()
    if board.tablebase is None:
        pytest.skip("Syzygy tablebases are not available")

    board.load_fen("7k/8/8/8/8/8/6Q1/7K w - - 0 1")

    assert board.tablebase.probe_wdl(board) == 2


def test_tablebase_move_selection_ignores_search_depth():
    board = Board()
    if board.tablebase is None:
        pytest.skip("Syzygy tablebases are not available")

    board.load_fen("7k/8/8/8/8/8/6Q1/7K w - - 0 1")

    shallow = board.best_move(1)
    deep = board.best_move(4)

    assert (shallow.from_field, shallow.to_field) == (
        deep.from_field,
        deep.to_field,
    )



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


def test_pawn_promotion_generates_all_promotion_choices():
    board = Board()
    board.load_fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")

    promotions = [
        move
        for move in board.get_legal_moves()
        if move.from_field == "a7" and move.to_field == "a8"
    ]

    assert [move.promotion for move in promotions] == ["q", "r", "b", "n"]


def test_uci_promotion_move_round_trip():
    move = parse_uci_move("a7a8q")

    assert move.promotion == "q"
    assert uci_move_to_string(move) == "a7a8q"


def test_pawn_promotion_applies_selected_piece():
    board = Board()
    board.load_fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")

    assert board.move(parse_uci_move("a7a8n"))
    assert board.board[0][0].piece == "N"


@pytest.mark.parametrize(
    ("notation", "king_field", "rook_field"),
    [
        ("e1g1", "g1", "f1"),
        ("O-O", "g1", "f1"),
        ("e1c1", "c1", "d1"),
        ("O-O-O", "c1", "d1"),
    ],
)
def test_white_castling_from_uci_notation(notation, king_field, rook_field):
    board = Board()
    board.load_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")

    assert board.move(parse_uci_move(notation, board))
    assert board.board[8 - int(king_field[1])][ord(king_field[0]) - ord("a")].piece == "K"
    assert board.board[8 - int(rook_field[1])][ord(rook_field[0]) - ord("a")].piece == "R"
    assert board.castling_rights == "kq"


@pytest.mark.parametrize(
    ("notation", "king_field", "rook_field"),
    [
        ("O-O", "g8", "f8"),
        ("O-O-O", "c8", "d8"),
    ],
)
def test_black_castling_from_short_notation(notation, king_field, rook_field):
    board = Board()
    board.load_fen("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")

    assert board.move(parse_uci_move(notation, board))
    assert board.board[8 - int(king_field[1])][ord(king_field[0]) - ord("a")].piece == "k"
    assert board.board[8 - int(rook_field[1])][ord(rook_field[0]) - ord("a")].piece == "r"
    assert board.castling_rights == "KQ"


def test_castling_is_generated_as_legal_move():
    board = Board()
    board.load_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")

    moves = {(move.from_field, move.to_field) for move in board.get_legal_moves()}

    assert {("e1", "g1"), ("e1", "c1")} <= moves
