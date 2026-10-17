from __future__ import annotations

import argparse
import time
from collections.abc import Callable

from board import Board
from move import Move


Benchmark = tuple[str, Callable[[], object]]


def measure(name: str, operation: Callable[[], object], repeats: int) -> None:
    """Measure an operation and print the average and best runtime."""
    samples = []

    for _ in range(repeats):
        started = time.perf_counter()
        operation()
        samples.append(time.perf_counter() - started)

    average = sum(samples) / len(samples)
    best = min(samples)
    print(f"{name:<28} avg {average * 1000:>9.2f} ms   best {best * 1000:>9.2f} ms")


def make_benchmarks(depth: int) -> list[Benchmark]:
    board = Board()
    opening_move = Move("e2", "e4")

    def generate_legal_moves() -> object:
        return board.get_legal_moves()

    def copy_board() -> object:
        return board.copy()

    def evaluate_position() -> object:
        return board.evaluate(board)

    def check_attacks() -> object:
        return board.is_square_attacked(7, 4, False)

    def order_moves() -> object:
        return board.order_moves(board.get_legal_moves())

    def validate_move() -> object:
        piece = board.board[opening_move.from_row][opening_move.from_column]
        return piece.is_legal_move(board, opening_move)

    def apply_move() -> object:
        test_board = Board()
        test_board.move(opening_move)
        return test_board

    def search() -> object:
        return Board().best_move(depth)

    return [
        ("legal move generation", generate_legal_moves),
        ("board copy", copy_board),
        ("position evaluation", evaluate_position),
        ("attack detection", check_attacks),
        ("move ordering", order_moves),
        ("single move validation", validate_move),
        ("apply move", apply_move),
        (f"best move (depth {depth})", search),
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark Bytefish engine operations")
    parser.add_argument(
        "--depth",
        type=int,
        default=2,
        help="search depth for the complete search benchmark (default: 2)",
    )
    parser.add_argument(
        "--repeats",
        type=int,
        default=30,
        help="number of samples per benchmark (default: 30)",
    )
    args = parser.parse_args()

    if args.depth < 1:
        parser.error("--depth must be at least 1")
    if args.repeats < 1:
        parser.error("--repeats must be at least 1")

    print(f"Bytefish speed benchmark: depth={args.depth}, repeats={args.repeats}")
    print("-" * 76)

    for name, operation in make_benchmarks(args.depth):
        measure(name, operation, args.repeats)


if __name__ == "__main__":
    main()
