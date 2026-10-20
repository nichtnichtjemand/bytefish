#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output="$(printf 'uci\nsetoption name Threads value 2\nposition startpos\ngo movetime 1000\nquit\n' | "$script_dir/start_bot.sh")"

grep -q '^option name Threads type spin' <<<"$output"
grep -q '^info string budget:' <<<"$output"
grep -q '^info depth [1-9]' <<<"$output"
grep -Eq '^info depth [0-9]+ .*nodes [1-9][0-9]* nps [0-9]+' <<<"$output"
grep -Eq '^info nodes [0-9]+ nps [0-9]+' <<<"$output"
grep -q '^bestmove [a-h][1-8][a-h][1-8]' <<<"$output"

printf '%s\n' "Mojo UCI time-control smoke test passed"
