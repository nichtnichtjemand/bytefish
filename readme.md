# Bytefish
### A chess engine, in python!

## How to install and use (Linux only (Tested on Ubuntu))

### 1. Go to where you want to put the project in
### 2. Clone it:
```
git clone https://github.com/nichtnichtjemand/bytefish.git
```
Install an UCI Software, I'm using Xboard:
```
sudo apt install xboard polyglot
```
### 3. I highly recommend using PyPy3 because it is much faster than the normal Python3!
You can install it this way:
```
sudo apt install pypy3
```
### 4. Now you can start the engine
- You against Bytefish:
```
xboard -scp "/path/to/your/bytefish/start_bot.sh" -sd "/path/to/your/bytefish" -sUCI
```
- It against itself, if you want to do that, you will need to change Mode to "2 Chess Programs":
```
xboard -fcp "/path/to/your/bytefish/start_bot.sh" -fd "/path/to/your/bytefish" -fUCI -scp "/path/to/your/bytefish/start_bot.sh" -sd "/path/to/your/bytefish" -sUCI
```

Before starting, install the project dependencies with `uv sync`. The start script
uses the project virtual environment and therefore also loads the Syzygy reader.
## How to install and use (Windows (Not tested, so it probably doesn't work!))
### 1. Go to where you want to put the project in
### 2. Clone it:
```
git clone https://github.com/nichtnichtjemand/bytefish.git
```
### 3. Download PyPy for Windows
1. Go to the [PyPy Download Page](https://pypy.org/download.html) and download the PyPy3 zip archive for Windows (64-bit).
2. Extract the folder (e.g., to `C:/pypy3`).
3. (Optional) Add `C:/pypy3` to your system's Environment Variables (PATH) so you can run `pypy3` from any command prompt.

### 4. Setting up Cute Chess
1. Download and install [Cute Chess](https://github.com/cutechess/cutechess/releases).
2. Open Cute Chess and go to **Tools** -> **Settings** -> **Engines**.
3. Click the **Add** (+) button and configure it as follows:
   - **Name:** `Bytefish`
   - **Command:** `C:/pypy3/pypy3.exe` *(Path to your PyPy executable)*
   - **Arguments:** `C:/path/to/your/bytefish/uci.py`
   - **Working Directory:** `C:/path/to/your/bytefish/`
   - **Protocol:** `UCI`
4. Click OK to save.
5. Now you can start a new game and select Bytefish!

## Features
- Chess Rules, Check and Checkmate
- Minimax and Alpha-Beta-Pruning
- History Heuristic
- Syzygy tablebases for positions with up to five pieces (when available in `../syzygy` or `BYTEFISH_SYZYGY_PATH`)
- Working on Depth 4 normally, takes about 20 seconds per move

The UCI option `SyzygyPath` can be used to configure another tablebase directory:

```
setoption name SyzygyPath value /path/to/syzygy
```
## To-Do
- Castling and En Passant
## Contribute
### Feel free to create an Issue on Github when you find a problem, it helps me alot!