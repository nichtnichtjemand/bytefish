from board import Board

def main() raises:
    var b = Board()
    b.load_fen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
    print(b.to_fen())
    print(b.en_passant_square)
