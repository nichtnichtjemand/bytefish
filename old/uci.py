#!/usr/bin/env python3
import sys
import time

from board import Board, SearchTimeout, create_search_executor
from move import Move
from syzygy import SyzygyTablebase


def calculate_search_budget(
    remaining_ms,
    increment_ms=0,
    moves_to_go=None,
    movetime_ms=None,
    complexity=1.0,
):
    """Return a conservative budget before position-specific adjustments."""
    if movetime_ms is not None:
        return movetime_ms / 1000 * 0.7 * complexity

    if remaining_ms is None:
        return None

    remaining = remaining_ms / 1000
    increment = increment_ms / 1000

    if remaining <= 2:
        base = min(remaining * 0.10 + increment * 0.35, 0.12)
        return base * complexity
    if remaining <= 10:
        base = min(remaining * 0.12 + increment * 0.5, 0.5)
        return base * complexity

    moves = moves_to_go or 30
    base = min(
        remaining / moves + increment * 0.8,
        remaining * 0.20,
    )
    return base * complexity


def position_time_factor(board: Board, moves) -> tuple[float, bool]:
    """Return a search multiplier and whether the position is tactical."""
    captures = sum(
        board.board[move.to_row][move.to_column] != ""
        or board.is_en_passant(move)
        for move in moves
    )
    promotions = sum(
        move.promotion is not None
        for move in moves
    )
    tactical = (
        board.is_in_check(board.current_turn)
        or captures > 0
        or promotions > 0
        or len(moves) <= 5
    )

    factor = 1.0
    if tactical:
        factor += 0.35
    if len(moves) >= 35:
        factor += 0.10
    elif len(moves) <= 12:
        factor -= 0.15
    if board.is_endgame():
        # Endgames need deeper quiet-move searches: a check is not
        # automatically useful, and one wasted tempo can change the result.
        factor += 0.25
    if captures >= 6:
        factor += 0.10

    return max(0.55, min(factor, 1.65)), tactical


def uci_move_to_string(move: Move) -> str:
    promotion = move.promotion.lower() if move.promotion else ""
    return f"{move.from_field.lower()}{move.to_field.lower()}{promotion}"


def parse_uci_move(uci_move: str, board: Board | None = None) -> Move:
    notation = uci_move.upper()

    if notation in ("O-O", "0-0"):
        rank = "1" if board is None or board.current_turn else "8"
        return Move(f"e{rank}", f"g{rank}")

    if notation in ("O-O-O", "0-0-0"):
        rank = "1" if board is None or board.current_turn else "8"
        return Move(f"e{rank}", f"c{rank}")

    if len(uci_move) not in (4, 5):
        raise ValueError(f"Unsupported UCI-Move: {uci_move}")

    from_field = uci_move[:2]
    to_field = uci_move[2:4]
    promotion = uci_move[4].lower() if len(uci_move) == 5 else None

    return Move(from_field, to_field, promotion)


def handle_position(board: Board, command: str) -> None:
    parts = command.split()

    if len(parts) < 2:
        print("info string Invalid position command")
        return

    if parts[1] == "startpos":
        board.reset()
        moves_index = 2

    elif parts[1] == "fen":
        if "moves" in parts:
            moves_index = parts.index("moves")
        else:
            moves_index = len(parts)

        fen_parts = parts[2:moves_index]

        if len(fen_parts) != 6:
            print("info string Invalid FEN")
            return

        try:
            board.load_fen(" ".join(fen_parts))
        except ValueError as error:
            print(f"info string Invalid FEN: {error}")
            return

    else:
        print("info string Unsupported position command")
        return

    if "moves" not in parts:
        return

    for uci_move in parts[moves_index + 1:]:
        try:
            move = parse_uci_move(uci_move, board)

            if not board.move(move):
                print(f"info string Illegal Move {uci_move}")
                return

        except (ValueError, IndexError) as error:
            print(f"info string Illegal Move {uci_move}: {error}")
            return


def handle_go(board: Board, command: str, workers: int = 2) -> None:
    search_started = time.monotonic()
    parts = command.split()
    depth = 4
    has_depth_limit = "depth" in parts
    deadline = None

    if "depth" in parts:
        try:
            depth_index = parts.index("depth")

            if depth_index + 1 >= len(parts):
                raise ValueError

            depth = int(parts[depth_index + 1])

            if depth < 1:
                raise ValueError

        except ValueError:
            print("info string Invalid depth")
            return

    def parse_milliseconds(name):
        if name not in parts:
            return None

        try:
            value = int(parts[parts.index(name) + 1])
        except (ValueError, IndexError):
            raise ValueError(f"Invalid {name}") from None

        if value < 0:
            raise ValueError(f"Invalid {name}")
        return value

    try:
        movetime = parse_milliseconds("movetime")
        white_time = parse_milliseconds("wtime")
        black_time = parse_milliseconds("btime")
        white_increment = parse_milliseconds("winc") or 0
        black_increment = parse_milliseconds("binc") or 0
        moves_to_go = parse_milliseconds("movestogo")
    except ValueError as error:
        print(f"info string {error}")
        return

    if moves_to_go == 0:
        print("info string Invalid movestogo")
        return

    moves = board.get_legal_moves()
    if "searchmoves" in parts:
        start = parts.index("searchmoves") + 1
        go_fields = {
            "wtime", "btime", "winc", "binc", "movestogo", "movetime",
            "depth", "nodes", "mate", "infinite", "ponder",
        }
        end = next(
            (index for index in range(start, len(parts)) if parts[index] in go_fields),
            len(parts),
        )
        requested = parts[start:end]
        if not requested:
            print("info string searchmoves requires at least one move")
            return
        legal_by_name = {uci_move_to_string(move): move for move in moves}
        invalid = [name.lower() for name in requested if name.lower() not in legal_by_name]
        if invalid:
            print("info string Illegal searchmove", invalid[0])
            return
        allowed = {name.lower() for name in requested}
        moves = [move for move in moves if uci_move_to_string(move) in allowed]

    if not moves:
        print("bestmove 0000")
        return

    complexity, tactical = position_time_factor(board, moves)

    remaining = None
    if movetime is not None:
        budget = calculate_search_budget(
            None,
            movetime_ms=movetime,
            complexity=complexity,
        )
    else:
        remaining = white_time if board.current_turn else black_time
        increment = white_increment if board.current_turn else black_increment
        budget = calculate_search_budget(
            remaining,
            increment,
            moves_to_go,
            complexity=complexity,
        )

    if budget is not None:
        # Keep a larger safety margin for UCI output, lag, and clock updates.
        safety = 0.75 if remaining is not None and remaining <= 2_000 else 0.85
        deadline = time.monotonic() + max(0.001, budget * safety)

    # The default launcher runs on Linux (including Raspberry Pi OS), where
    # fork lets two independent search workers reuse this position cheaply.
    # Very short budgets stay serial so worker startup does not eat the search.
    executor = None
    if workers > 1 and len(moves) > 1 and (
        deadline is None or budget is None or budget >= 0.8
    ):
        try:
            executor = create_search_executor(board, workers=workers)
        except (OSError, RuntimeError, ValueError) as error:
            print(f"info string parallel search unavailable: {error}")

    if executor is not None:
        print(f"info string search workers: {workers}")

    try:
        if deadline is None:
            try:
                best_move = board.best_move(
                    depth, executor=executor, root_moves=moves
                )
            except Exception as error:
                if executor is None:
                    raise
                executor.shutdown(wait=True, cancel_futures=True)
                executor = None
                print(f"info string parallel search failed; retrying serially: {error}")
                best_move = board.best_move(depth, root_moves=moves)
            if best_move is not None:
                elapsed_ms = int((time.monotonic() - search_started) * 1000)
                print(
                    f"info depth {depth} time {elapsed_ms} "
                    f"pv {uci_move_to_string(best_move)}"
                )
        else:
            best_move = moves[0]
            # The last fully completed iteration is always a legal fallback.
            max_depth = depth if has_depth_limit else 64
            if not has_depth_limit and budget is not None:
                if budget <= 0.15:
                    max_depth = 2
                elif budget <= 0.5:
                    max_depth = 3
            if tactical and not has_depth_limit:
                max_depth = max(max_depth, 4)
            stable_move = None
            stable_depths = 0
            defensive_search = board.is_losing_for_side_to_move()
            for current_depth in range(1, max_depth + 1):
                try:
                    candidate = board.best_move(
                        current_depth,
                        deadline,
                        executor=executor,
                        root_moves=moves,
                    )
                except SearchTimeout:
                    break
                except Exception as error:
                    if executor is None:
                        raise
                    executor.shutdown(wait=True, cancel_futures=True)
                    executor = None
                    print(
                        "info string parallel search failed; retrying serially: "
                        + str(error)
                    )
                    try:
                        candidate = board.best_move(
                            current_depth, deadline, root_moves=moves
                        )
                    except SearchTimeout:
                        break
                if candidate is not None:
                    best_move = candidate
                    elapsed_ms = int((time.monotonic() - search_started) * 1000)
                    print(
                        f"info depth {current_depth} time {elapsed_ms} "
                        f"pv {uci_move_to_string(candidate)}"
                    )
                    if stable_move == uci_move_to_string(candidate):
                        stable_depths += 1
                    else:
                        stable_move = uci_move_to_string(candidate)
                        stable_depths = 1

                    # Do not stop on a stable shallow move in a quiet endgame:
                    # a waiting move or a pointless check can hide the real plan.
                    minimum_depth = 4
                    required_stable_depths = 3
                    if (
                        not has_depth_limit
                        and current_depth >= minimum_depth
                        and stable_depths >= required_stable_depths
                        and not defensive_search
                    ):
                        break
    finally:
        if executor is not None:
            executor.shutdown(wait=True, cancel_futures=True)

    if best_move is None:
        print("bestmove 0000")
        return

    print(f"bestmove {uci_move_to_string(best_move)}")


def main() -> None:
    # UCI engines usually communicate through pipes, where stdout is otherwise
    # block-buffered and responses would not reach the GUI immediately.
    sys.stdout.reconfigure(line_buffering=True)
    board = Board()
    workers = 2

    while True:
        try:
            command = input().strip()
        except EOFError:
            break

        if not command:
            continue

        if command == "uci":
            print("id name Bytefish")
            print("id author nichtnichtjemand")
            print("option name SyzygyPath type string default")
            print("option name Hash type spin default 16 min 1 max 128")
            print("option name Threads type spin default 2 min 1 max 2")
            print("option name Clear Hash type button")
            print("uciok")

        elif command == "isready":
            print("readyok")

        elif command == "ucinewgame":
            board.reset()

        elif command.startswith("setoption "):
            option = command[len("setoption "):].strip().split()
            if not option or option[0] != "name":
                print("info string Invalid setoption command")
                continue
            try:
                value_index = option.index("value")
                name = " ".join(option[1:value_index])
                value = " ".join(option[value_index + 1:])
            except ValueError:
                name = " ".join(option[1:])
                value = ""

            if name == "Clear Hash":
                board.transposition_table.clear()
                print("info string Hash cleared")
            elif name == "Hash":
                try:
                    megabytes = int(value)
                    if not 1 <= megabytes <= 128:
                        raise ValueError
                    board.transposition_table_limit = megabytes * 256
                    while len(board.transposition_table) > board.transposition_table_limit:
                        board.transposition_table.pop(next(iter(board.transposition_table)))
                except ValueError:
                    print("info string Hash must be between 1 and 128 MB")
            elif name == "Threads":
                try:
                    requested_workers = int(value)
                    if requested_workers not in (1, 2):
                        raise ValueError
                    workers = requested_workers
                except ValueError:
                    print("info string Threads must be 1 or 2")
            elif name == "SyzygyPath":
                if not value:
                    print("info string SyzygyPath requires a directory")
                    continue
                try:
                    tablebase = SyzygyTablebase(value)
                    if board.tablebase is not None:
                        board.tablebase.close()
                    board.tablebase = tablebase
                    print(f"info string Syzygy tablebases loaded from {value}")
                except (FileNotFoundError, OSError, ValueError) as error:
                    print(f"info string Could not load Syzygy tablebases: {error}")
            else:
                print("info string Unsupported option", name)

        elif command.startswith("position "):
            handle_position(board, command)

        elif command == "go" or command.startswith("go "):
            handle_go(board, command, workers)

        elif command == "stop":
            # Search is synchronous; a stop arriving during search is read
            # after bestmove, so there is no active search left to cancel.
            pass

        elif command == "ponderhit":
            pass

        elif command == "quit":
            break


if __name__ == "__main__":
    main()
