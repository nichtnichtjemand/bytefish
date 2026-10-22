# Bytefish
### A chess engine, in Mojo!

## How to play the bot
### Most time of the day, you can just challenge the bot on Lichess: https://lichess.org/@/Bytefish/
### If it is not online, look down!

## How to install and use (Linux only (Tested on Ubuntu))

### 1. Go to where you want to put the project in
### 2. Clone it:
```
git clone https://github.com/nichtnichtjemand/bytefish.git
```
Install an UCI Software, I recommend Xboard:
```
sudo apt install xboard polyglot
```

### 3. Now you can start the engine
- You against Bytefish:
```
xboard -scp "/path/to/your/bytefish/start_bot.sh" -sd "/path/to/your/bytefish" -sUCI
```
- It against itself, if you want to do that, you will need to change Mode to "2 Chess Programs":
```
xboard -fcp "/path/to/your/bytefish/start_bot.sh" -fd "/path/to/your/bytefish" -fUCI -scp "/path/to/your/bytefish/start_bot.sh" -sd "/path/to/your/bytefish" -sUCI
```


## Features
- Chess Rules, Check and Checkmate
- Minimax and Alpha-Beta-Pruning
- History Heuristic
- Syzygy tablebases for positions with up to five pieces (when available in `../syzygy` or `BYTEFISH_SYZYGY_PATH`)
- Working on Depth 5 normally, takes about 4 seconds per move

The UCI option `SyzygyPath` can be used to configure another tablebase directory:

```
setoption name SyzygyPath value /path/to/syzygy
```

The engine accepts standard UCI time controls. In clock mode, its base budget
uses the remaining time after configurable move overhead and a small reserve,
plus half the per-move increment. Without `movestogo`, it assumes 60 moves
remain. Iterative deepening adjusts a soft limit from best-move stability,
score swings, tactical signals, and the gap between the top candidates. It may
continue past the soft limit while the search remains unstable, up to a hard
limit capped by the available clock. `go movetime X` reserves the configured
overhead and uses 75% of the remainder as its soft and hard limit. `depth`,
`nodes`, and `mate` remain active alongside clock limits; `go infinite` ignores
clock limits until stopped.

```
go wtime 30000 btime 30000 winc 500 binc 500 movestogo 20
go movetime 1000
```

UCI pondering is supported. Send the anticipated opponent move as part of the
`position` command, then start `go ponder`. The engine searches that position
without using the clock. `ponderhit` starts the normal clock budget for the
current side; `stop` ends the search and returns its best move, and `quit`
exits without emitting a move.

The default move overhead is 50 ms and can be changed with the UCI `Move
Overhead` option. The reserve is 1% of the remaining clock, bounded between 30
and 300 ms. If the hard limit is reached during an iteration, Bytefish returns
the best move from the last fully completed iteration.

Positions can be sent with a complete FEN, optionally followed by moves:

```
position fen r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1 moves e1g1
```

## Contribute
### Feel free to create an Issue on Github when you find a problem, it helps me alot!
