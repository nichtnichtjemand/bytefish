from board import Board
from std.time import perf_counter


def run_operation(mut board: Board, operation: Int) raises -> Int:
    if operation == 0:
        return len(board.get_legal_moves())
    if operation == 1:
        var copied = board.copy()
        return len(copied.board)
    if operation == 2:
        return board.evaluate()
    if operation == 3:
        return Int(board.is_square_attacked(7, 4, False))
    if operation == 4:
        return len(board.order_moves(board.get_legal_moves()))
    if operation == 5:
        var searched = Board()
        var best = searched.best_move(1)
        if best:
            return 1
        return 0
    return 0


def measure(
    name: String, repeats: Int, operation: Int, mut board: Board
) raises:
    var warmup_result = run_operation(board, operation)
    var total = 0.0
    var best = Float64(1.0e30)
    var checksum = 0

    for _ in range(repeats):
        var start = perf_counter()
        var result = run_operation(board, operation)
        checksum += result
        var elapsed = perf_counter() - start

        total += elapsed
        if elapsed < best:
            best = elapsed

    var average = total / Float64(repeats)

    print(
        name,
        " avg ",
        average * 1000.0,
        " ms   best ",
        best * 1000.0,
        " ms",
    )
    print("  checksum ", checksum)


def main() raises:
    var board = Board()

    print("Bytefish Mojo benchmark")
    print("-----------------------")

    measure("legal move generation", 30, 0, board)
    measure("board copy", 30, 1, board)
    measure("position evaluation", 30, 2, board)
    measure("attack detection", 30, 3, board)
    measure("move ordering", 30, 4, board)
    measure("best move depth 1", 1, 5, board)
