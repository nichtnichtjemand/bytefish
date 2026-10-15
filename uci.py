
import sys

from board import Board
from move import Move

def uci_move_to_string(move: Move) -> str:
    return f"{move.from_field.lower()}{move.to_field.lower()}"


def parse_uci_move(uci_move: str) -> Move:
    if len(uci_move) != 4:
        raise ValueError(f"Unsupported UCI-Move: {uci_move}")

    from_field = uci_move[:2]
    to_field = uci_move[2:4]

    return Move(from_field, to_field)


def handle_position(board: Board, command: str) -> None:
    parts = command.split()

    depth = 4


    if len(parts) < 2:
        print("info string Invalid position command")
        return

    if parts[1] != "startpos":
        print("info string Only startpos for now")
        return

    board.reset()

    if "moves" not in parts:
        return

    moves_index = parts.index("moves")

    for uci_move in parts[moves_index + 1:]:
        try:
            move = parse_uci_move(uci_move)
            board.move(move)
        except (ValueError, IndexError) as error:
            print(f"info string Illegal Move {uci_move}: {error}")
            return



def handle_go(board: Board, command: str) -> None:
    parts = command.split()
    depth = 4

    if "depth" in parts:
        try:
            depth = int(parts[parts.index("depth") + 1])
            if depth < 1:
                raise ValueError
        except (ValueError, IndexError):
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
            print(f"id name Bytefish")
            print(f"id author nichtnichtjemand")
            print("uciok")

        elif command == "isready":
            print("readyok")

        elif command == "ucinewgame":
            board.reset()

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
