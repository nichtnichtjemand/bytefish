from std.collections import List, Optional
from std.time import monotonic
from std.python import Python

from board import Board
from move import Move
from piece_types import EMPTY


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
        if board._piece_at(
            move.to_row, move.to_column
        ).kind != EMPTY or board.is_en_passant(move):
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


def perft(mut board: Board, depth: Int) raises -> Int:
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
    var nps = Int(Float64(nodes) * 1000.0 / Float64(max(elapsed_ms, 1)))
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
    var pondering = _find_token(parts, "ponder") >= 0
    var infinite = _find_token(parts, "infinite") >= 0
    var nodes_limit: Optional[Int]
    var mate_limit: Optional[Int]
    try:
        nodes_limit = _parse_clock_value(parts, "nodes")
        mate_limit = _parse_clock_value(parts, "mate")
    except e:
        print("info string Invalid search limit")
        return
    if nodes_limit and nodes_limit.value() == 0:
        print("info string Invalid nodes")
        return
    if mate_limit and mate_limit.value() == 0:
        print("info string Invalid mate")
        return
    if mate_limit and not has_depth_limit:
        depth = mate_limit.value() * 2
        has_depth_limit = True

    board.search_control[0] = False
    board.search_control[1] = pondering
    board.search_control[2] = None
    board.search_control[3] = 0.0
    board.search_control[4] = False
    board.search_control[5] = 0
    board.deadline_poll_count = 0
    board.search_control[6] = nodes_limit.value() if nodes_limit else 0
    board.node_limit = nodes_limit.value() if nodes_limit else 0
    board.search_control[7] = 0
    board.search_control[8] = 0.0

    if depth_index >= 0:
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
                token == "wtime"
                or token == "btime"
                or token == "winc"
                or token == "binc"
                or token == "movestogo"
                or token == "movetime"
                or token == "depth"
                or token == "nodes"
                or token == "mate"
                or token == "ponder"
                or token == "infinite"
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
    var tactical = factors[1]
    var remaining: Optional[Int]
    var increment: Int
    if board.current_turn:
        remaining = white_time
        increment = white_increment
    else:
        remaining = black_time
        increment = black_increment

    var available_time: Optional[Float64] = None
    var base_budget: Optional[Float64] = None
    if remaining:
        var own_ms = Float64(remaining.value())
        var reserve_ms = min(300.0, max(30.0, own_ms * 0.01))
        var available_ms = max(
            0.0, own_ms - Float64(move_overhead_ms) - reserve_ms
        )
        var moves_left = 60
        if moves_to_go:
            moves_left = max(1, moves_to_go.value())
        var increment_seconds = Float64(increment) / 1000.0
        var base_seconds = min(
            available_ms / 1000.0,
            available_ms / (1000.0 * Float64(moves_left))
            + increment_seconds * 0.5,
        )
        available_time = Optional(available_ms / 1000.0)
        base_budget = Optional(base_seconds)
    if movetime:
        var movetime_available = max(
            0.0,
            Float64(movetime.value() - move_overhead_ms) / 1000.0 * 0.75,
        )
        if available_time:
            available_time = Optional(
                min(available_time.value(), movetime_available)
            )
            base_budget = Optional(min(base_budget.value(), movetime_available))
        else:
            available_time = Optional(movetime_available)
            base_budget = Optional(movetime_available)

    var budget: Optional[Float64] = base_budget
    if budget:
        print("info string budget:", budget.value())
    else:
        print("info string no budget")

    var deadline: Optional[Float64] = None
    var soft_limit = 0.0
    var hard_limit = 0.0
    if budget and available_time:
        if movetime:
            soft_limit = min(available_time.value(), budget.value())
            hard_limit = soft_limit
        else:
            var tactical_bonus = 0.1 if tactical else 0.0
            var initial_factor = 1.0 + tactical_bonus
            soft_limit = min(
                available_time.value(), budget.value() * initial_factor
            )
            hard_limit = min(
                available_time.value(),
                max(soft_limit, budget.value() * 1.5),
            )
        # Pondering needs a hard ceiling available immediately on ponderhit;
        # ordinary search may extend from 1.5B to 2B after sustained instability.
        var ponder_hard = min(
            available_time.value(), max(soft_limit, budget.value() * 2.0)
        )
        board.search_control[3] = ponder_hard
        if not pondering and not infinite:
            deadline = Optional(search_started_at + hard_limit)

    if not deadline and not pondering and not infinite:
        var best = moves[0]
        var previous_best: Optional[Move] = None
        var total_nodes = 0
        var no_clock_max_depth = depth
        if nodes_limit and not has_depth_limit:
            no_clock_max_depth = 64
        for current_depth in range(1, no_clock_max_depth + 1):
            try:
                var result: Optional[Move]
                if workers > 1 and not nodes_limit:
                    result = board.best_move_two_workers(
                        current_depth,
                        None,
                        Optional(
                            root_moves.value().copy()
                        ) if root_moves else None,
                        previous_best,
                    )
                else:
                    result = board.best_move(
                        current_depth,
                        None,
                        Optional(
                            root_moves.value().copy()
                        ) if root_moves else None,
                        previous_best,
                    )
                if result:
                    best = result.value()
                    previous_best = Optional(best)
                    total_nodes += board.last_search_nodes
                    var elapsed_ms = Int(
                        (
                            Float64(monotonic()) / 1_000_000_000.0
                            - search_started_at
                        )
                        * 1000.0
                    )
                    var nps = Int(
                        Float64(total_nodes)
                        * 1000.0
                        / Float64(max(elapsed_ms, 1))
                    )
                    print(
                        "info depth",
                        current_depth,
                        "time",
                        elapsed_ms,
                        "nodes",
                        total_nodes,
                        "nps",
                        nps,
                        "pv",
                        uci_move_to_string(best),
                    )
                    if mate_limit and abs(board.last_search_score) >= 99000:
                        break
            except e:
                total_nodes += board.last_search_nodes
                print(
                    "info string search stopped before completing depth",
                    current_depth,
                )
                break
        print_search_totals(total_nodes, search_started_at)
        if String(py=board.search_control[4]) != "True":
            print("bestmove", uci_move_to_string(best))
        return

    var ordered_moves = board.order_moves(moves)
    var best_move = ordered_moves[0]
    var max_depth = depth
    var previous_best: Optional[Move] = None
    var total_nodes = 0
    var best_history = List[Move]()
    var score_history = List[Int]()
    if (pondering or infinite) and not has_depth_limit:
        max_depth = 64
    elif not has_depth_limit:
        max_depth = 64

    for current_depth in range(1, max_depth + 1):
        try:
            var candidate = board.best_move(
                current_depth,
                deadline,
                Optional(root_moves.value().copy()) if root_moves else None,
                previous_best,
            )
            if candidate:
                best_move = candidate.value()
                previous_best = Optional(best_move)
                total_nodes += board.last_search_nodes
                best_history.append(best_move)
                score_history.append(board.last_search_score)
                if len(best_history) > 3:
                    _ = best_history.pop(0)
                    _ = score_history.pop(0)

                var move_switches = 0
                for index in range(1, len(best_history)):
                    var earlier = best_history[index - 1]
                    var later = best_history[index]
                    if (
                        earlier.from_field != later.from_field
                        or earlier.to_field != later.to_field
                        or earlier.promotion != later.promotion
                    ):
                        move_switches += 1

                var score_swings = 0
                if len(score_history) >= 2:
                    for index in range(1, len(score_history)):
                        var old_score = score_history[index - 1]
                        var new_score = score_history[index]
                        if abs(old_score) < 90000 and abs(new_score) < 90000:
                            if abs(new_score - old_score) >= 150:
                                score_swings += 1

                var latest_move_stable = False
                var latest_score_stable = False
                if len(best_history) >= 2 and len(score_history) >= 2:
                    var prior_best = best_history[len(best_history) - 2]
                    var prior_score = score_history[len(score_history) - 2]
                    latest_move_stable = (
                        prior_best.from_field == best_move.from_field
                        and prior_best.to_field == best_move.to_field
                        and prior_best.promotion == best_move.promotion
                    )
                    if (
                        abs(prior_score) < 90000
                        and abs(board.last_search_score) < 90000
                    ):
                        latest_score_stable = (
                            abs(board.last_search_score - prior_score) < 150
                        )
                    elif (
                        abs(prior_score) >= 90000
                        and abs(board.last_search_score) >= 90000
                    ):
                        latest_score_stable = (
                            prior_score == board.last_search_score
                        )

                var p_factor = 0.0
                if move_switches == 1:
                    p_factor = 0.15
                elif move_switches >= 2:
                    p_factor = 0.5
                var v_factor = 0.0
                if score_swings >= 2:
                    v_factor = 0.5
                elif score_swings == 1:
                    v_factor = 0.2
                var c_factor = 0.1 if tactical else 0.0
                if len(moves) > 1 and board.last_search_gap < 40:
                    c_factor += 0.05
                var q_factor = 0.0
                if (
                    len(best_history) == 3
                    and move_switches == 0
                    and board.last_search_gap >= 100
                    and not tactical
                ):
                    q_factor = 0.3
                var stability_factor = max(
                    0.6,
                    min(2.0, 1.0 + p_factor + v_factor + c_factor - q_factor),
                )
                var hard_multiplier = 1.5
                if move_switches >= 2 and score_swings >= 2:
                    hard_multiplier = 2.0
                if available_time and base_budget and not movetime:
                    soft_limit = min(
                        available_time.value(),
                        base_budget.value() * stability_factor,
                    )
                    hard_limit = min(
                        available_time.value(),
                        max(soft_limit, base_budget.value() * hard_multiplier),
                    )
                    if not pondering and not infinite:
                        deadline = Optional(search_started_at + hard_limit)

                var elapsed_ms = Int(
                    (Float64(monotonic()) / 1_000_000_000.0 - search_started_at)
                    * 1000.0
                )
                var nps = Int(
                    Float64(total_nodes) * 1000.0 / Float64(max(elapsed_ms, 1))
                )
                print(
                    "info depth",
                    current_depth,
                    "time",
                    elapsed_ms,
                    "nodes",
                    total_nodes,
                    "nps",
                    nps,
                    "pv",
                    uci_move_to_string(best_move),
                )
                if available_time and not infinite:
                    var now = Float64(monotonic()) / 1_000_000_000.0
                    var active_start = search_started_at
                    if (
                        pondering
                        and not String(py=board.search_control[1]) == "True"
                    ):
                        var ponder_start = Float64(
                            String(py=board.search_control[8])
                        )
                        if ponder_start > 0.0:
                            active_start = ponder_start
                    var elapsed_search = now - active_start
                    if elapsed_search >= hard_limit:
                        break
                    if (
                        elapsed_search >= soft_limit
                        and move_switches == 0
                        and latest_move_stable
                        and latest_score_stable
                    ):
                        break
                if mate_limit and abs(board.last_search_score) >= 99000:
                    break
        except e:
            total_nodes += board.last_search_nodes
            print(
                "info string search stopped before completing depth",
                current_depth,
            )
            break

    print_search_totals(total_nodes, search_started_at)
    if String(py=board.search_control[4]) != "True":
        print("bestmove", uci_move_to_string(best_move))


def run() raises:
    var board = Board()
    var sys = Python.import_module("sys")
    var move_overhead_ms = 50
    var workers = 1

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
            print(
                "option name Move Overhead type spin default 50 min 0 max 1000"
            )
            print("option name Threads type spin default 1 min 1 max 2")
            print("uciok")
        elif parts[0] == "isready":
            print("readyok")
        elif parts[0] == "ucinewgame":
            board.reset()
        elif parts[0] == "position":
            handle_position(board, command)
        elif parts[0] == "go":
            handle_go(board, command, move_overhead_ms, workers)
            if String(py=board.search_control[4]) == "True":
                return
        elif parts[0] == "perft":
            if len(parts) < 2:
                print("info string perft requires a depth")
            else:
                try:
                    var perft_depth = Int(parts[1])
                    if perft_depth < 0:
                        print("info string Invalid perft depth")
                    else:
                        print(
                            "info string perft nodes", perft(board, perft_depth)
                        )
                except e:
                    print("info string Invalid perft depth")
        elif parts[0] == "quit":
            return
        elif parts[0] == "stop":
            board.search_control[0] = True
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
                    option_name == "Move"
                    and value_index == name_index + 3
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
