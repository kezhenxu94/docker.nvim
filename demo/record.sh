#!/usr/bin/env bash
# Record the demo with asciinema: a script types into Neovim in tmux, against the
# demo containers (demo/setup.sh). Usage: demo/record.sh [file.cast]
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
out=${1:-$dir/docker-nvim.cast}
tmux=(tmux -L docker-nvim-demo -f "$dir/tmux.conf")

# Neovim's state (e.g. the context of :Docker context) and data, apart from the user's
xdg=$(mktemp -d)
trap 'rm -rf "$xdg"' EXIT

"${tmux[@]}" kill-server 2>/dev/null || true
"${tmux[@]}" new-session -d -s demo -x 120 -y 32 -c "$(dirname "$dir")" \
  -e XDG_STATE_HOME="$xdg/state" -e XDG_DATA_HOME="$xdg/data" \
  -e XDG_CACHE_HOME="$xdg/cache" -e BASH_SILENCE_DEPRECATION_WARNING=1 "bash --rcfile demo/bashrc"

TERM=xterm-256color asciinema rec --headless --overwrite --window-size 120x32 --idle-time-limit 2 \
  --title "docker.nvim" -c "${tmux[*]} attach -t demo" "$out" &
recording=$!
sleep 1

keys() { "${tmux[@]}" send-keys -t demo "$@"; }
typed() {
  local text=$1
  for ((i = 0; i < ${#text}; i++)); do
    keys -l -- "${text:i:1}"
    sleep 0.05
  done
}
run() {
  typed "$1"
  keys Enter
  sleep "${2:-2}"
}

run "nvim" 1
# The kinds
run ":e docker://" 3

# The containers of the compose project, unhealthy ones are diagnostics
run ":e docker://containers?project=docker-nvim-demo" 3
keys ']d' && sleep 1
keys C-w d && sleep 4
keys l && sleep 1

# Follow logs, <C-c> stops
run "/api" 1
keys gL && sleep 5
keys C-c && sleep 2
keys C-o && sleep 2

# Logs of the failed container
run "/migrate" 1
keys gl && sleep 3
keys C-o && sleep 2

# Operations
run "/cache" 1
keys gra && sleep 3
run "6" 2
run "1" 4

# A shell
run "/web" 1
keys gs && sleep 3
run "nginx -v" 2
keys C-\\ C-n && sleep 1
keys C-o && sleep 2

# <C-]> on the image, <CR> its history, <C-t> back
run "/nginx:alpine" 1
keys C-] && sleep 3
keys Enter && sleep 3
keys C-t && sleep 2

# docker inspect
run "/web" 1
keys gd && sleep 3
keys C-o && sleep 2

# Delete a line and :w to remove the container
run "/migrate" 1
keys dd && sleep 1
run ":w" 2
run "1" 3

# Watch
keys gw && sleep 8
keys gw && sleep 1

# The containers using a volume
run ":e docker://volumes?name=docker-nvim-demo" 3
keys Enter && sleep 3

keys 'g?' && sleep 5
keys q && sleep 1

run ":qa!" 1
"${tmux[@]}" kill-server
wait "$recording"
echo "Recorded $out"
