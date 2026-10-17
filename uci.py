
from board import Board
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

    moves = board.get_legal_moves()

    if not moves:
        print("bestmove 0000")
        return

    best_move = board.best_move(depth)

    if best_move is None:
        print("bestmove 0000")
        return

    print(f"bestmove {uci_move_to_string(best_move)}")


def main() -> None:
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
