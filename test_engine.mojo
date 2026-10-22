from std.collections import List, Optional
from std.time import monotonic

from board import Board
from move import Move
import piece_square_tables as tables
from uci import (
    calculate_search_budget,
    handle_position,
    parse_uci_move,
    uci_move_to_string,
)


def perft(mut board: Board, depth: Int) raises -> Int:
    if depth == 0:
        return 1

    var nodes = 0
    for move in board.get_legal_moves():
        var child = board.copy()
        if child.move(move):
            nodes += perft(child, depth - 1)
    return nodes


def main() raises:
    var board = Board()

    assert tables.mg_value("p") == 82
    assert tables.eg_value("q") == 936
    assert tables.gamephase_increment("r") == 2
    assert tables.mg_piece_square_bonus("p", 1, 0) == 98
    assert tables.eg_piece_square_bonus("p", 1, 0) == 178

    var tapered_eval_board = Board()
    tapered_eval_board.load_fen("4k3/8/8/8/8/8/P7/4K3 w - - 0 1")
    assert tapered_eval_board._get_tapered_material_position_score() == -272

    assert len(board.get_legal_moves()) == 20, "start position must have 20 legal moves"
    assert perft(board, 2) == 400, "start position perft(2) must be 400"
    assert perft(board, 3) == 8902, "start position perft(3) must be 8902"
    assert board.evaluate() == 0, "start position evaluation must be balanced"

    var pawn_attack = Board()
    pawn_attack.load_fen("4k3/8/8/3p4/4K3/8/8/8 w - - 0 1")
    assert pawn_attack.is_square_attacked(4, 4, False), "pawn diagonal attack must be detected"

    var knight_attack = Board()
    knight_attack.load_fen("4k3/8/8/8/4K3/5n2/8/8 w - - 0 1")
    assert knight_attack.is_square_attacked(3, 4, False), "knight jump attack must be detected"

    var blocked_rook_ray = Board()
    blocked_rook_ray.load_fen("4r1k1/8/8/8/4P3/8/8/4K3 w - - 0 1")
    assert not blocked_rook_ray.is_square_attacked(7, 4, False), "a piece must block rook attacks"

    var clear_bishop_ray = Board()
    clear_bishop_ray.load_fen("7k/8/8/5b2/8/3K4/8/8 w - - 0 1")
    assert clear_bishop_ray.is_square_attacked(5, 3, False), "diagonal bishop ray must be detected"

    var e4 = Move("e2", "e4")
    assert board.move(e4), "e2e4 should be legal"
    assert board.evaluate() == -57, "e2e4 evaluation should match Python"
    assert board.to_fen() == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    assert len(board.get_legal_moves()) == 20, "black should have 20 replies after e2e4"

    var e5 = Move("e7", "e5")
    assert board.move(e5), "e7e5 should be legal"
    var blocked_queen_move = Move("d1", "h5")
    assert not board.move(blocked_queen_move), "queen must not pass through the e2 pawn"
    assert board.move(Move("g1", "f3")), "g1f3 should be legal"
    assert board.evaluate() == -107, "Nf3 evaluation should match Python"

    var repetition_board = Board()
    var knight_cycle = List[Move]()
    knight_cycle.append(Move("g1", "f3"))
    knight_cycle.append(Move("g8", "f6"))
    knight_cycle.append(Move("f3", "g1"))
    knight_cycle.append(Move("f6", "g8"))
    for move in knight_cycle:
        assert repetition_board.move(move), "first knight cycle must be legal"
    assert not repetition_board.is_threefold_repetition(), "two visits are not threefold"
    for move in knight_cycle:
        assert repetition_board.move(move), "second knight cycle must be legal"
    assert repetition_board.is_threefold_repetition(), "threefold repetition must ignore FEN move counters"

    var checkmate_board = Board()
    checkmate_board.load_fen("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")
    var mate_score = checkmate_board.quiescence(-1_000_000, 1_000_000, None, 0)
    assert mate_score == -100_000, "quiescence must resolve checkmate at its horizon"
    checkmate_board.halfmove_clock = 100
    assert checkmate_board.minimax(2) == -100_002, "checkmate takes priority over the fifty-move draw"
    assert checkmate_board.quiescence(-1_000_000, 1_000_000, None, 0) == -100_000

    var fifty_move_draw = Board()
    fifty_move_draw.load_fen("7k/8/8/8/8/8/8/R3K3 w - - 100 1")
    assert fifty_move_draw.minimax(2) == 0, "the fifty-move draw must still be recognized"

    var bare_kings = Board()
    bare_kings.load_fen("7k/8/8/8/8/8/8/4K3 w - - 0 1")
    assert bare_kings.is_insufficient_material()
    assert bare_kings.minimax(2) == 0, "bare kings must evaluate as a draw"

    var bishop_vs_king = Board()
    bishop_vs_king.load_fen("7k/8/8/8/8/8/8/4KB2 w - - 0 1")
    assert bishop_vs_king.is_insufficient_material()

    var same_color_bishops = Board()
    same_color_bishops.load_fen("2b1k3/8/8/8/8/8/8/4KB2 w - - 0 1")
    assert same_color_bishops.is_insufficient_material()

    var opposite_color_bishops = Board()
    opposite_color_bishops.load_fen("5b1k/8/8/8/8/8/8/4KB2 w - - 0 1")
    assert not opposite_color_bishops.is_insufficient_material()

    var central_king = Board()
    central_king.load_fen("7k/8/8/8/4K3/8/8/8 w - - 0 1")
    var corner_king = Board()
    corner_king.load_fen("7k/8/8/8/8/8/8/4K3 w - - 0 1")
    assert central_king.evaluate() < corner_king.evaluate(), "endgame king should prefer the center"

    var advanced_pawn = Board()
    advanced_pawn.load_fen("4k3/8/P7/8/8/8/8/4K3 w - - 0 1")
    var less_advanced_pawn = Board()
    less_advanced_pawn.load_fen("4k3/8/8/8/P7/8/8/4K3 w - - 0 1")
    assert advanced_pawn.evaluate() < less_advanced_pawn.evaluate(), "advanced passed pawns should be favored"

    var rook_behind_passer = Board()
    rook_behind_passer.load_fen("4k3/8/P7/8/8/8/8/R3K3 w - - 0 1")
    var rook_off_file = Board()
    rook_off_file.load_fen("4k3/8/P7/8/8/8/8/4K2R w - - 0 1")
    assert rook_behind_passer.get_endgame_score() < rook_off_file.get_endgame_score(), "rook behind a passed pawn should be favored"

    var uci_board = Board()
    handle_position(uci_board, "position startpos moves e2e4")
    assert uci_board.to_fen() == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    var black_move = parse_uci_move("e7e5", uci_board)
    assert uci_move_to_string(black_move) == "e7e5"

    var promotion_types = List[String]()
    promotion_types.append("q")
    promotion_types.append("r")
    promotion_types.append("b")
    promotion_types.append("n")
    for promotion in promotion_types:
        var white_promotion_board = Board()
        white_promotion_board.load_fen(
            "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"
        )
        var white_promotion = parse_uci_move(
            "a7a8" + promotion, white_promotion_board
        )
        assert white_promotion_board.move(white_promotion), "white UCI promotion must be legal"
        assert white_promotion_board.board[0][0].piece == promotion.upper()
        assert uci_move_to_string(white_promotion) == "a7a8" + promotion

        var black_promotion_board = Board()
        black_promotion_board.load_fen(
            "4k3/8/8/8/8/8/p7/4K3 b - - 0 1"
        )
        var black_promotion = parse_uci_move(
            "a2a1" + promotion, black_promotion_board
        )
        assert black_promotion_board.move(black_promotion), "black UCI promotion must be legal"
        assert black_promotion_board.board[7][0].piece == promotion
        assert uci_move_to_string(black_promotion) == "a2a1" + promotion

        var capture_board = Board()
        capture_board.load_fen("1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        var capture_promotion = parse_uci_move(
            "a7b8" + promotion, capture_board
        )
        assert capture_board.move(capture_promotion), "capture promotion must be legal"
        assert capture_board.board[0][1].piece == promotion.upper()

    var capture_promotion_board = Board()
    capture_promotion_board.load_fen(
        "1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1"
    )
    var capture_promotions = 0
    for move in capture_promotion_board.get_legal_moves():
        if move.from_field == "a7" and move.to_field == "b8" and move.promotion:
            capture_promotions += 1
    assert capture_promotions == 4, "capture promotions must include all four pieces"

    var promotion_search_board = Board()
    promotion_search_board.load_fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    var selected_promotion = promotion_search_board.best_move(1)
    assert selected_promotion and uci_move_to_string(
        selected_promotion.value()
    ) == "a7a8q", "search must return a UCI promotion suffix"

    var search_board = Board()
    var searched = search_board.best_move(1)
    assert searched and uci_move_to_string(searched.value()) == "b1c3", "depth-1 search should match Python"
    assert search_board.last_search_nodes > 1, "search must count visited nodes"

    var budget = calculate_search_budget(None, movetime_ms=Optional(1000))
    assert budget and budget.value() == 0.8
    var five_second_budget = calculate_search_budget(
        None, movetime_ms=Optional(5000)
    )
    assert five_second_budget and five_second_budget.value() == 4.0
    var complex_movetime_budget = calculate_search_budget(
        None, movetime_ms=Optional(5000), complexity=1.65
    )
    assert complex_movetime_budget and complex_movetime_budget.value() == 4.5

    var clock_budget = calculate_search_budget(
        Optional(450_000), complexity=1.65
    )
    assert clock_budget and clock_budget.value() == 12.375
    var lower_clock_budget = calculate_search_budget(
        Optional(60_000), complexity=1.65
    )
    assert lower_clock_budget and lower_clock_budget.value() == 1.65

    var timed_board = Board()
    var future_deadline = Optional(
        Float64(monotonic()) / 1_000_000_000.0 + 5.0
    )
    var timed_move = timed_board.best_move(1, future_deadline)
    var timed_move_found = False
    if timed_move:
        timed_move_found = True
    assert timed_move_found, "search with a future deadline should complete"

    var worker_board = Board()
    var worker_move = worker_board.best_move_two_workers(1)
    var has_worker_move = False
    if worker_move:
        has_worker_move = True
    assert has_worker_move, "two-worker search should return a legal root move"
    var worker_result_is_legal = False
    for legal_move in worker_board.get_legal_moves():
        if (
            legal_move.from_field == worker_move.value().from_field
            and legal_move.to_field == worker_move.value().to_field
            and legal_move.promotion == worker_move.value().promotion
        ):
            worker_result_is_legal = True
    assert worker_result_is_legal, "worker result must be legal"
    assert worker_board.last_search_nodes > 1, "worker search must return combined node counts"

    var timed_out = False
    try:
        _ = timed_board.best_move(
            1, Optional(Float64(monotonic()) / 1_000_000_000.0 - 1.0)
        )
    except e:
        timed_out = True
    assert timed_out, "an expired search deadline should propagate as a timeout"

    var worker_timed_out = False
    try:
        _ = worker_board.best_move_two_workers(
            2, Optional(Float64(monotonic()) / 1_000_000_000.0 - 1.0)
        )
    except e:
        worker_timed_out = True
    assert worker_timed_out, "two-worker search must propagate expired deadlines"

    print("Mojo engine smoke tests passed")
