#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output="$(printf 'position startpos\ngo movetime 1000\nquit\n' | "$script_dir/start_bot.sh")"

grep -q '^info string budget:' <<<"$output"
grep -q '^bestmove [a-h][1-8][a-h][1-8]' <<<"$output"

printf '%s\n' "Mojo UCI time-control smoke test passed"
