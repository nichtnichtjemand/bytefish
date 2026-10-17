#!/usr/bin/env python3
import sys
import time

from board import Board, SearchTimeout
from move import Move
from syzygy import SyzygyTablebase


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


def handle_go(board: Board, command: str) -> None:
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

    if movetime is not None:
        # movetime is a maximum, not a requirement. Leave time for the GUI
        # and avoid spending the whole allocation on a stable shallow search.
        budget = movetime / 1000 * 0.8
    else:
        remaining = white_time if board.current_turn else black_time
        increment = white_increment if board.current_turn else black_increment

        if remaining is not None:
            moves = moves_to_go or 30
            budget = remaining / 1000 / moves + increment / 1000 * 0.8
            budget = min(budget, remaining / 1000 * 0.25)
        else:
            budget = None

    if budget is not None:
        # Keep a small safety margin for UCI output and scheduling delays.
        deadline = time.monotonic() + max(0.001, budget * 0.95)

    moves = board.get_legal_moves()

    if not moves:
        print("bestmove 0000")
        return

    if deadline is None:
        best_move = board.best_move(depth)
    else:
        best_move = moves[0]
        # The last fully completed iteration is always a legal fallback.
        max_depth = depth if has_depth_limit else 64
        stable_move = None
        stable_depths = 0
        for current_depth in range(1, max_depth + 1):
            try:
                candidate = board.best_move(current_depth, deadline)
            except SearchTimeout:
                break
            if candidate is not None:
                best_move = candidate
                if stable_move == uci_move_to_string(candidate):
                    stable_depths += 1
                else:
                    stable_move = uci_move_to_string(candidate)
                    stable_depths = 1

                # Four plies are already the engine's normal search depth.
                # If the best move has not changed for two completed
                # iterations, deeper search is usually not worth the time.
                if not has_depth_limit and current_depth >= 4 and stable_depths >= 2:
                    break

    if best_move is None:
        print("bestmove 0000")
        return

    print(f"bestmove {uci_move_to_string(best_move)}")


def main() -> None:
    # UCI engines usually communicate through pipes, where stdout is otherwise
    # block-buffered and responses would not reach the GUI immediately.
    sys.stdout.reconfigure(line_buffering=True)
    board = Board()

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
            print("uciok")

        elif command == "isready":
            print("readyok")

        elif command == "ucinewgame":
            board.reset()

        elif command.startswith("setoption name SyzygyPath"):
            prefix = "setoption name SyzygyPath"
            path = command[len(prefix):].strip()
            if path.startswith("value "):
                path = path[6:].strip()
            if not path:
                print("info string SyzygyPath requires a directory")
                continue
            try:
                tablebase = SyzygyTablebase(path)
                if board.tablebase is not None:
                    board.tablebase.close()
                board.tablebase = tablebase
                print(f"info string Syzygy tablebases loaded from {path}")
            except (FileNotFoundError, OSError, ValueError) as error:
                print(f"info string Could not load Syzygy tablebases: {error}")

        elif command.startswith("position "):
            handle_position(board, command)

        elif command == "go" or command.startswith("go "):
            handle_go(board, command)

        elif command == "stop":
            pass

        elif command == "quit":
            break


if __name__ == "__main__":
    main()
