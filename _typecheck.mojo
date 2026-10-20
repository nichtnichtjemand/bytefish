from std.time import monotonic
from std.collections import Optional

def main() raises:
    var t = monotonic()
    print(t)
    var d: Optional[Float64] = Float64(t) + 1.0
    if d:
        if Float64(monotonic()) >= d.value():
            print("late")
        else:
            print("ok")

    var fen = String("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    var parts = fen.split(" ")
    var turn = String(parts[1])
    print(turn != "w")
    var c = String("p")
    print(c)
