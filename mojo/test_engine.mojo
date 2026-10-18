from std.collections import Optional
from std.time import monotonic

from board import Board
from move import Move
from uci import (
    calculate_search_budget,
    handle_position,
    parse_uci_move,
    uci_move_to_string,
)


def perft(board: Board, depth: Int) raises -> Int:
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

    assert len(board.get_legal_moves()) == 20, "start position must have 20 legal moves"
    assert perft(board, 2) == 400, "start position perft(2) must be 400"
    assert board.evaluate() == 0, "start position evaluation must be balanced"

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

    var uci_board = Board()
    handle_position(uci_board, "position startpos moves e2e4")
    assert uci_board.to_fen() == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    var black_move = parse_uci_move("e7e5", uci_board)
    assert uci_move_to_string(black_move) == "e7e5"

    var search_board = Board()
    var searched = search_board.best_move(1)
    assert searched and uci_move_to_string(searched.value()) == "b1c3", "depth-1 search should match Python"

    var budget = calculate_search_budget(None, movetime_ms=Optional(1000))
    assert budget and budget.value() == 0.7
    var five_second_budget = calculate_search_budget(
        None, movetime_ms=Optional(5000)
    )
    assert five_second_budget and five_second_budget.value() == 3.5

    var timed_board = Board()
    var future_deadline = Optional(
        Float64(monotonic()) / 1_000_000_000.0 + 5.0
    )
    var timed_move = timed_board.best_move(1, future_deadline)
    var timed_move_found = False
    if timed_move:
        timed_move_found = True
    assert timed_move_found, "search with a future deadline should complete"

    var timed_out = False
    try:
        _ = timed_board.best_move(
            1, Optional(Float64(monotonic()) / 1_000_000_000.0 - 1.0)
        )
    except e:
        timed_out = True
    assert timed_out, "an expired search deadline should propagate as a timeout"

    print("Mojo engine smoke tests passed")
