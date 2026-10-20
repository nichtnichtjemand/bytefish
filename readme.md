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

The engine accepts standard UCI time controls. Clock time is divided into
small per-move budgets (with a safety reserve), and `movetime` is treated as a
maximum rather than a requirement. The search also stops early when the best
move remains stable:

Without `movestogo`, clock allocation assumes 40 moves remain and scales down
with the current clock. Tactical positions can add at most 10% to that
allocation, preserving time for later moves. A `movetime` request is kept below
its limit even in tactical positions.

```
go wtime 30000 btime 30000 winc 500 binc 500 movestogo 20
go movetime 1000
```

Time management is position-aware: tactical positions (check, captures,
promotions, or very few legal moves) receive more time, while quiet positions
and simple endgames receive less. Legal-move count, material phase, increment,
remaining time, and `movestogo` are combined before the deadline is chosen.
Bullet and fast blitz still receive conservative safety reserves for
communication and network lag. For example, with one second remaining and no
increment, a quiet position targets about 85 ms, while a tactical position may
receive more without risking the clock.

Positions can be sent with a complete FEN, optionally followed by moves:

```
position fen r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1 moves e1g1
```

## Contribute
### Feel free to create an Issue on Github when you find a problem, it helps me alot!
