from std.collections import List, Optional
from std.time import monotonic
from std.python import Python

from board import Board
from move import Move


def calculate_search_budget(
    remaining_ms: Optional[Int],
    increment_ms: Int = 0,
    moves_to_go: Optional[Int] = None,
    movetime_ms: Optional[Int] = None,
    complexity: Float64 = 1.0,
) -> Optional[Float64]:
    if movetime_ms:
        var requested = Float64(movetime_ms.value()) / 1000.0
        return Optional(min(requested * 0.8 * complexity, requested * 0.9))

    if not remaining_ms:
        return None

    var remaining = Float64(remaining_ms.value()) / 1000.0
    var increment = Float64(increment_ms) / 1000.0
    var base: Float64

    if remaining <= 2.0:
        base = min(remaining * 0.10 + increment * 0.35, 0.12)
    elif remaining <= 10.0:
        base = min(remaining * 0.12 + increment * 0.5, 0.5)
    else:
        var moves = 40
        if moves_to_go:
            if moves_to_go.value() > 0:
                moves = moves_to_go.value()
        base = min(
            remaining / Float64(moves) + increment * 0.8, remaining * 0.20
        )

    # Keep time for later moves: complexity may raise the allocation by at
    # most 10%, regardless of the position's raw complexity multiplier.
    return Optional(min(base * complexity, base * 1.10))


def uci_move_to_string(move: Move) -> String:
    var notation = move.from_field.lower() + move.to_field.lower()
    if move.promotion:
        notation += move.promotion.value().lower()
    return notation


def parse_uci_move(uci_move: String, board: Board) raises -> Move:
    var notation = uci_move.lower()

    if notation == "o-o" or notation == "0-0":
        var rank = "1"
        if not board.current_turn:
            rank = "8"
        return Move("e" + rank, "g" + rank)

    if notation == "o-o-o" or notation == "0-0-0":
        var rank = "1"
        if not board.current_turn:
            rank = "8"
        return Move("e" + rank, "c" + rank)

    if notation.byte_length() != 4 and notation.byte_length() != 5:
        raise Error("Unsupported UCI move")

    var from_field = String(notation[byte=0]) + String(notation[byte=1])
    var to_field = String(notation[byte=2]) + String(notation[byte=3])
    if notation.byte_length() == 5:
        var promotion = String(notation[byte=4])
        return Move(from_field, to_field, Optional(promotion))
    return Move(from_field, to_field)


def position_time_factor(
    board: Board, moves: List[Move]
) -> Tuple[Float64, Bool]:
    var captures = 0
    var promotions = 0

    for move in moves:
        if board.board[move.to_row][
            move.to_column
        ].piece != "" or board.is_en_passant(move):
            captures += 1
        if move.promotion:
            promotions += 1

    var tactical = (
        board.is_in_check(board.current_turn)
        or captures > 0
        or promotions > 0
        or len(moves) <= 5
    )
    var factor = 1.0
    if tactical:
        factor += 0.35
    if len(moves) >= 35:
        factor += 0.10
    elif len(moves) <= 12:
        factor -= 0.15
    if board.is_endgame():
        factor += 0.25
    if captures >= 6:
        factor += 0.10

    return (max(0.55, min(factor, 1.65)), tactical)


def _find_token(parts: List[String], token: String) -> Int:
    for index in range(len(parts)):
        if parts[index] == token:
            return index
    return -1


def _split_command(command: String) -> List[String]:
    var split_parts = command.split(" ")
    var parts = List[String]()
    for part in split_parts:
        var token = String(part)
        if token != "":
            parts.append(token)
    return parts^


def _parse_clock_value(
    parts: List[String], name: String
) raises -> Optional[Int]:
    var index = _find_token(parts, name)
    if index < 0:
        return None
    if index + 1 >= len(parts):
        raise Error("Invalid " + name)
    var value = Int(parts[index + 1])
    if value < 0:
        raise Error("Invalid " + name)
    return Optional(value)


def perft(board: Board, depth: Int) raises -> Int:
    if depth <= 0:
        return 1
    var nodes = 0
    for move in board.get_legal_moves():
        var child = board.copy()
        if child._apply_unchecked(move):
            nodes += perft(child, depth - 1)
    return nodes


def print_search_totals(nodes: Int, search_started_at: Float64):
    var elapsed_ms = Int(
        (Float64(monotonic()) / 1_000_000_000.0 - search_started_at) * 1000.0
    )
    var nps = Int(
        Float64(nodes) * 1000.0 / Float64(max(elapsed_ms, 1))
    )
    print("info nodes", nodes, "nps", nps)


def handle_position(mut board: Board, command: String) raises:
    var parts = _split_command(command)
    if len(parts) < 2:
        print("info string Invalid position command")
        return

    var moves_index = _find_token(parts, "moves")
    if parts[1] == "startpos":
        board.reset()
        if moves_index < 0:
            return
    elif parts[1] == "fen":
        var fen_end = len(parts)
        if moves_index >= 0:
            fen_end = moves_index
        if fen_end - 2 != 6:
            print("info string Invalid FEN")
            return

        var fen = String(parts[2])
        for index in range(3, fen_end):
            fen += " " + parts[index]
        try:
            board.load_fen(fen)
        except e:
            print("info string Invalid FEN")
            return
        if moves_index < 0:
            return
    else:
        print("info string Unsupported position command")
        return

    for index in range(moves_index + 1, len(parts)):
        var notation = parts[index]
        try:
            var move = parse_uci_move(notation, board)
            if not board.move(move):
                print("info string Illegal Move", notation)
                return
        except e:
            print("info string Illegal Move", notation)
            return


def handle_go(
    mut board: Board,
    command: String,
    move_overhead_ms: Int = 30,
    workers: Int = 2,
) raises:
    var search_started_at = Float64(monotonic()) / 1_000_000_000.0
    var parts = _split_command(command)
    var depth = 5
    var depth_index = _find_token(parts, "depth")
    var has_depth_limit = depth_index >= 0

    if has_depth_limit:
        if depth_index + 1 >= len(parts):
            print("info string Invalid depth")
            return
        try:
            depth = Int(parts[depth_index + 1])
        except e:
            print("info string Invalid depth")
            return
        if depth < 1:
            print("info string Invalid depth")
            return

    var movetime: Optional[Int]
    var white_time: Optional[Int]
    var black_time: Optional[Int]
    var white_increment = 0
    var black_increment = 0
    var moves_to_go: Optional[Int]

    try:
        movetime = _parse_clock_value(parts, "movetime")
        white_time = _parse_clock_value(parts, "wtime")
        black_time = _parse_clock_value(parts, "btime")
        var winc = _parse_clock_value(parts, "winc")
        var binc = _parse_clock_value(parts, "binc")
        moves_to_go = _parse_clock_value(parts, "movestogo")
        if winc:
            white_increment = winc.value()
        if binc:
            black_increment = binc.value()
    except e:
        print("info string Invalid clock value")
        return

    if moves_to_go and moves_to_go.value() == 0:
        print("info string Invalid movestogo")
        return

    var moves = board.get_legal_moves()
    if len(moves) == 0:
        print("bestmove 0000")
        return

    var searchmoves_index = _find_token(parts, "searchmoves")
    var root_moves: Optional[List[Move]] = None
    if searchmoves_index >= 0:
        var allowed = List[Move]()
        var index = searchmoves_index + 1
        while index < len(parts):
            var token = String(parts[index])
            if (
                token == "wtime" or token == "btime" or token == "winc"
                or token == "binc" or token == "movestogo"
                or token == "movetime" or token == "depth"
            ):
                break

            var requested: Move
            try:
                requested = parse_uci_move(token, board)
            except e:
                print("info string Invalid searchmove", token)
                return
            var matched = False
            for legal_move in moves:
                if (
                    requested.from_field == legal_move.from_field
                    and requested.to_field == legal_move.to_field
                    and requested.promotion == legal_move.promotion
                ):
                    allowed.append(legal_move)
                    matched = True
                    break
            if not matched:
                print("info string Illegal searchmove", token)
                return
            index += 1

        if len(allowed) == 0:
            print("info string searchmoves requires at least one move")
            return
        root_moves = Optional(allowed.copy())
        moves = allowed.copy()

    var factors = position_time_factor(board, moves)
    var complexity = factors[0]
    var tactical = factors[1]
    var remaining: Optional[Int]
    var increment: Int
    if board.current_turn:
        remaining = white_time
        increment = white_increment
    else:
        remaining = black_time
        increment = black_increment

    var budget: Optional[Float64]
    if movetime:
        budget = calculate_search_budget(
            None, movetime_ms=movetime, complexity=complexity
        )
    else:
        budget = calculate_search_budget(
            remaining, increment, moves_to_go, complexity=complexity
        )
    if budget:
        print("info string budget:", budget.value())
    else:
        print("info string no budget")

    var deadline: Optional[Float64] = None
    if budget:
        var safety = 0.95
        if remaining and remaining.value() <= 2000:
            safety = 0.85
        var usable_time = (
            budget.value() * safety - Float64(move_overhead_ms) / 1000.0
        )
        deadline = Optional(search_started_at + max(0.001, usable_time))

    if not deadline:
        var best = moves[0]
        var previous_best: Optional[Move] = None
        var total_nodes = 0
        for current_depth in range(1, depth + 1):
            try:
                var result: Optional[Move]
                if workers > 1:
                    result = board.best_move_two_workers(
                        current_depth,
                        None,
                        Optional(root_moves.value().copy()) if root_moves else None,
                        previous_best,
                    )
                else:
                    result = board.best_move(
                        current_depth, None,
                        Optional(root_moves.value().copy()) if root_moves else None,
                        previous_best,
                    )
                if result:
                    best = result.value()
                    previous_best = Optional(best)
                    total_nodes += board.last_search_nodes
                    var elapsed_ms = Int(
                        (Float64(monotonic()) / 1_000_000_000.0
                         - search_started_at) * 1000.0
                    )
                    var nps = Int(
                        Float64(total_nodes) * 1000.0
                        / Float64(max(elapsed_ms, 1))
                    )
                    print(
                        "info depth", current_depth, "time", elapsed_ms,
                        "nodes", total_nodes, "nps", nps,
                        "pv", uci_move_to_string(best),
                    )
            except e:
                total_nodes += board.last_search_nodes
                print(
                    "info string search stopped before completing depth",
                    current_depth,
                )
                break
        print_search_totals(total_nodes, search_started_at)
        print("bestmove", uci_move_to_string(best))
        return

    var ordered_moves = board.order_moves(moves)
    var best_move = ordered_moves[0]
    var max_depth = depth
    var previous_best: Optional[Move] = None
    var total_nodes = 0
    if not has_depth_limit:
        max_depth = 64
        if budget:
            if budget.value() <= 0.15:
                max_depth = 2
            elif budget.value() <= 0.5:
                max_depth = 3
        if tactical and max_depth < 4:
            max_depth = 4

    for current_depth in range(1, max_depth + 1):
        try:
            var candidate: Optional[Move]
            if workers > 1 and budget and budget.value() >= 0.8:
                candidate = board.best_move_two_workers(
                    current_depth,
                    deadline,
                    Optional(root_moves.value().copy()) if root_moves else None,
                    previous_best,
                )
            else:
                candidate = board.best_move(
                    current_depth, deadline,
                    Optional(root_moves.value().copy()) if root_moves else None,
                    previous_best,
                )
            if candidate:
                best_move = candidate.value()
                previous_best = Optional(best_move)
                total_nodes += board.last_search_nodes
                var elapsed_ms = Int(
                    (Float64(monotonic()) / 1_000_000_000.0
                     - search_started_at) * 1000.0
                )
                var nps = Int(
                    Float64(total_nodes) * 1000.0
                    / Float64(max(elapsed_ms, 1))
                )
                print(
                    "info depth", current_depth, "time", elapsed_ms,
                    "nodes", total_nodes, "nps", nps,
                    "pv", uci_move_to_string(best_move),
                )
        except e:
            total_nodes += board.last_search_nodes
            print(
                "info string search stopped before completing depth",
                current_depth,
            )
            break

    print_search_totals(total_nodes, search_started_at)
    print("bestmove", uci_move_to_string(best_move))


def run() raises:
    var board = Board()
    var sys = Python.import_module("sys")
    var move_overhead_ms = 30
    var workers = 2

    while True:
        var line = sys.stdin.readline()
        if line == "":
            return
        var stripped_line = line.strip()
        var command = String(py=stripped_line)
        var parts = _split_command(command)
        if len(parts) == 0:
            continue

        if parts[0] == "uci":
            print("id name Bytefish Mojo")
            print("id author nichtnichtjemand")
            print("option name Move Overhead type spin default 30 min 0 max 1000")
            print("option name Threads type spin default 2 min 1 max 2")
            print("uciok")
        elif parts[0] == "isready":
            print("readyok")
        elif parts[0] == "ucinewgame":
            board.reset()
        elif parts[0] == "position":
            handle_position(board, command)
        elif parts[0] == "go":
            handle_go(board, command, move_overhead_ms, workers)
        elif parts[0] == "perft":
            if len(parts) < 2:
                print("info string perft requires a depth")
            else:
                try:
                    var perft_depth = Int(parts[1])
                    if perft_depth < 0:
                        print("info string Invalid perft depth")
                    else:
                        print("info string perft nodes", perft(board, perft_depth))
                except e:
                    print("info string Invalid perft depth")
        elif parts[0] == "quit":
            return
        elif parts[0] == "stop":
            continue
        elif parts[0] == "setoption":
            var name_index = _find_token(parts, "name")
            var value_index = _find_token(parts, "value")
            if name_index < 0 or value_index < 0 or value_index <= name_index:
                print("info string Invalid setoption command")
            else:
                var option_name = String(parts[name_index + 1])
                if option_name == "Threads":
                    if value_index + 1 >= len(parts):
                        print("info string Threads must be 1 or 2")
                    else:
                        try:
                            var thread_count = Int(parts[value_index + 1])
                            if thread_count != 1 and thread_count != 2:
                                print("info string Threads must be 1 or 2")
                            else:
                                workers = thread_count
                                print("info string Threads set to", workers)
                        except e:
                            print("info string Threads must be 1 or 2")
                elif (
                    option_name == "Move" and value_index == name_index + 3
                    and String(parts[name_index + 2]) == "Overhead"
                    and value_index + 1 < len(parts)
                ):
                    try:
                        var overhead = Int(parts[value_index + 1])
                        if overhead < 0 or overhead > 1000:
                            print("info string Move Overhead must be 0 to 1000")
                        else:
                            move_overhead_ms = overhead
                            print("info string Move Overhead set to", overhead)
                    except e:
                        print("info string Move Overhead must be 0 to 1000")
                else:
                    print("info string Unsupported option")

        sys.stdout.flush()


def main() raises:
    run()
