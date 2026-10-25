# Bytefish

Bytefish is a chess engine written in the Mojo programming language.

## How to Play

### Online
Challenge the bot directly on Lichess: [Bytefish on Lichess](https://lichess.org/@/Bytefish)

### Local Installation (Linux / Ubuntu)
Clone the repository and install a UCI-compatible interface like Xboard or Polyglot:
```bash
git clone https://github.com/nichtnichtjemand/bytefish.git
cd bytefish
sudo apt install xboard polyglot
```
Start the engine for Human vs. Bytefish or Engine Duels with Xboard commands where ChatGPT can surely tell you how.

## Engine Features
* Full chess rule implementation (check/checkmate detection).
* Minimax search framework with Alpha-Beta pruning and History Heuristic.
* Syzygy tablebases support and a default search depth of 5 (~4 seconds per move).

## UCI Configuration & Technical Details
* **Tablebase Path:** Configured via `setoption name SyzygyPath value /path/to/syzygy` or environment variables.
* **Time Management:** Supports standard UCI time controls, clock modes, iterative deepening with dynamic soft/hard limits, and `go infinite`/`movetime` constraints.
* **Pondering & Positions:** Supports background calculation during opponent turns with `go ponder` and FEN-based board initializations.

## Contributing
Issues and suggestions can be submitted on GitHub, I'm very happy for every help!
