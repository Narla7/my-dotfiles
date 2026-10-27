#!/usr/bin/env bash
# flowstate.sh — tty-clock-style Pomodoro countdown, centered on screen.
#
# 4 × (25 min focus + 5 min break). Big block digits in the middle of the
# screen, session progress on a line below it. Focus = blue, break = red,
# and every timer always counts down. No music, no Spotify, nothing else.
#
# Usage:
#   flowstate.sh            toggle the timer window (start it, or close it)
#   flowstate.sh run        render the clock (used inside the timer window)
#   flowstate.sh pause      pause/resume the running session (SIGUSR1)
#   flowstate.sh stop       end the session and close the window
#
# Inside the timer window:  space = pause/resume · q = quit.
#
# Tunables (environment):
#   FOCUS_MIN=25  BREAK_MIN=5  CYCLES=4  SCALE=2  FONT_SIZE=16
#   FOCUS_SEC / BREAK_SEC override the minutes in raw seconds (handy for testing)
#   SOUND=0 disables the phase bells, NOTIFY=0 disables the end notification
#
# The bar widget reads phase + remaining seconds from
# ~/.local/state/flowstate/bar  ("focus 1499", "break 299 paused", "idle 0").

set -u

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/flowstate"
STATE="$STATE_DIR/bar"
mkdir -p "$STATE_DIR"

# Locale for correct multibyte width math (█ ● ○ are single characters).
export LC_ALL=C.UTF-8

FOCUS_MIN=$((10#${FOCUS_MIN:-25}))
BREAK_MIN=$((10#${BREAK_MIN:-5}))
CYCLES=$((10#${CYCLES:-4}))
FOCUS_SEC=$((10#${FOCUS_SEC:-$((FOCUS_MIN * 60))}))
BREAK_SEC=$((10#${BREAK_SEC:-$((BREAK_MIN * 60))}))
SCALE=$((10#${SCALE:-2}))          # 1 or 2 — horizontal+vertical digit doubling
FONT_SIZE="${FONT_SIZE:-16}"
SOUND="${SOUND:-1}"
NOTIFY="${NOTIFY:-1}"

# palette — muted, readable on dark terminals
RGB_FOCUS="138;138;126"   # #8a8a7e miasma muted grey (focus)
RGB_BREAK="247;118;142"   # #f7768e red   (break)
RGB_DONE="215;196;131"    # #d7c483 miasma cursor gold (done)
RGB_DIM="138;138;126"     # #8a8a7e miasma muted (paused / hollow dots)

ESC=$'\e'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
C_FOCUS="${ESC}[38;2;${RGB_FOCUS}m"
C_BREAK="${ESC}[38;2;${RGB_BREAK}m"
C_DONE="${ESC}[38;2;${RGB_DONE}m"
C_DIM="${ESC}[38;2;${RGB_DIM}m"

SND_BREAK="/usr/share/sounds/freedesktop/stereo/bell.oga"
SND_WORK="/usr/share/sounds/freedesktop/stereo/complete.oga"
SND_END="/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

write_state() { # $1 phase, $2 remaining seconds, $3 paused (0/1)
  local suffix=""
  (( ${3:-0} )) && suffix=" paused"
  printf '%s %s%s\n' "$1" "$2" "$suffix" > "$STATE"
}

cue() {
  [[ "$SOUND" == 1 && -f "$1" ]] || return 0
  pw-play --volume 1 "$1" >/dev/null 2>&1 &
}

notify_done() {
  [[ "$NOTIFY" == 1 ]] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send "Flowstate" "Session complete — ${CYCLES} × ${FOCUS_MIN}/${BREAK_MIN} min" 2>/dev/null
}

# ────────────────────────────────────────────────────────── clock rendering
# 7-segment block glyphs, 3 wide × 5 tall, drawn with '#' then translated
# to '█' at the end (keeps the doubling math ASCII/locale-proof).
init_glyphs() {
  local src=(
    $'###\n# #\n# #\n# #\n###'   # 0
    $'  #\n  #\n  #\n  #\n  #'   # 1
    $'###\n  #\n###\n#  \n###'   # 2
    $'###\n  #\n###\n  #\n###'   # 3
    $'# #\n# #\n###\n  #\n  #'   # 4
    $'###\n#  \n###\n  #\n###'   # 5
    $'###\n#  \n###\n# #\n###'   # 6
    $'###\n  #\n  #\n  #\n  #'   # 7
    $'###\n# #\n###\n# #\n###'   # 8
    $'###\n# #\n###\n  #\n###'   # 9
  )
  local d r rest
  for ((d = 0; d < 10; d++)); do
    rest=${src[$d]}
    for ((r = 0; r < 5; r++)); do
      GROW[$d:$r]=${rest%%$'\n'*}
      rest=${rest#*$'\n'}
    done
  done
}
declare -A GROW

double() { # double every character (SCALE = 2)
  local s=$1 out="" i
  for ((i = 0; i < ${#s}; i++)); do
    out+="${s:i:1}${s:i:1}"
  done
  printf '%s' "$out"
}

build_clock() { # $1=mm (2 digits) $2=ss (2 digits) $3=colon visible (0/1)
  local d1=${1:0:1} d2=${1:1:1} d3=${2:0:1} d4=${2:1:1} co=$3
  CLOCK_LINES=()
  local r line cm
  for ((r = 0; r < 5; r++)); do
    cm=" "
    (( co )) && { [[ $r == 1 || $r == 3 ]] && cm="#"; }
    line="${GROW[$d1:$r]} ${GROW[$d2:$r]} $cm ${GROW[$d3:$r]} ${GROW[$d4:$r]}"
    (( SCALE == 2 )) && line=$(double "$line")
    CLOCK_LINES+=("${line//#/█}")
  done
}

# ────────────────────────────────────────────────────────── session renderer
PAUSED=0
remain_at_pause=0

toggle_pause() {
  if (( PAUSED )); then
    PAUSED=0
    end=$(( $(date +%s) + remain_at_pause ))
  else
    PAUSED=1
    remain_at_pause=$(( end - $(date +%s) ))
    (( remain_at_pause < 0 )) && remain_at_pause=0
  fi
}

cleanup() {
  write_state idle 0
  printf '%s' "${ESC}[?25h${ESC}[?1049l"
}

run() {
  # guard: one session at a time (renderer_pid also matches this process)
  local other
  other=$(renderer_pid)
  if [[ -n $other && $other != "$$" ]]; then
    command -v notify-send >/dev/null 2>&1 && \
      notify-send "Flowstate" "A session is already running" 2>/dev/null
    exit 0
  fi
  init_glyphs
  printf '%s' "${ESC}[?1049h${ESC}[?25l"   # alt screen + hidden cursor
  trap cleanup EXIT
  trap 'exit 0' INT TERM HUP
  trap toggle_pause USR1

  # phase plan: CYCLES × (focus → break)
  PHASES=()
  TOTALS=()
  for ((i = 1; i <= CYCLES; i++)); do
    PHASES+=("focus" "break")
    TOTALS+=("$FOCUS_SEC" "$BREAK_SEC")
  done

  local idx=0 phase=${PHASES[0]} total=${TOTALS[0]}
  local now end remain=$total key
  end=$(( $(date +%s) + total ))
  local interactive=0
  [[ -t 0 ]] && interactive=1

  while :; do
    now=$(date +%s)
    if (( ! PAUSED )); then
      remain=$(( end - now ))
      if (( remain < 0 )); then
        idx=$(( idx + 1 ))
        if (( idx >= ${#PHASES[@]} )); then
          cue "$SND_END"
          notify_done
          write_state idle 0
          build_clock 00 00 1
          draw "${C_DONE}" "✓ session complete" "${C_DONE}" ""
          sleep 2
          exit 0
        fi
        phase=${PHASES[$idx]}
        total=${TOTALS[$idx]}
        end=$(( now + total ))
        remain=$total
        if [[ $phase == "break" ]]; then cue "$SND_BREAK"; else cue "$SND_WORK"; fi
      fi
    else
      remain=$remain_at_pause
      (( remain < 0 )) && remain=0
    fi

    local disp=$remain
    (( disp > 5999 )) && disp=5999        # keep the clock two digits wide
    build_clock "$(printf '%02d' $(( disp / 60 )))" "$(printf '%02d' $(( disp % 60 )))" "$(( now % 2 ))"

    # clock color: blue while focusing, red on break, dim while paused
    local C="$C_FOCUS"
    [[ $phase == "break" ]] && C="$C_BREAK"
    (( PAUSED )) && C="$C_DIM"

    # progress line: label · dots (filled = finished focus blocks)
    local filled=$(( idx / 2 ))
    [[ $phase == "break" ]] && filled=$(( (idx + 1) / 2 ))
    local dots="" c
    for ((c = 1; c <= CYCLES; c++)); do
      if (( c <= filled )); then dots+="${C}●${C_DIM}"; else dots+="${C_DIM}○"; fi
    done
    dots+="${RESET}"
    local label="⌖ focus $(( idx / 2 + 1 ))/${CYCLES}"
    [[ $phase == "break" ]] && label="☾ break"
    (( PAUSED )) && label="‖ paused"
    draw "$C" "$label" "$C" "$dots"

    write_state "$phase" "$remain" "$PAUSED"

    key=""
    if (( interactive )); then
      IFS= read -rsn1 -t 1 key || true
      [[ $key == " " ]] && toggle_pause
      [[ $key == q || $key == Q || $key == $'\e' ]] && exit 0
    else
      sleep 1
    fi
  done
}

draw() { # $1 clock color, $2 label, $3 progress color, $4 dots (colored)
  local cols lines pad_top pad_left sp
  cols=$(tput cols 2>/dev/null)
  lines=$(tput lines 2>/dev/null)
  cols=${cols:-80}
  lines=${lines:-24}
  local height=$(( ${#CLOCK_LINES[@]} + 2 ))
  pad_top=$(( (lines - height) / 2 ))
  (( pad_top < 0 )) && pad_top=0
  pad_left=$(( (cols - ${#CLOCK_LINES[0]}) / 2 ))
  (( pad_left < 0 )) && pad_left=0
  printf -v sp '%*s' "$pad_left" ''

  local frame="${ESC}[H${ESC}[2J" l i
  for ((i = 0; i < pad_top; i++)); do frame+=$'\n'; done
  for l in "${CLOCK_LINES[@]}"; do frame+="${sp}${1}${BOLD}${l}${RESET}"$'\n'; done
  frame+=$'\n'
  if [[ -n "$4" ]]; then
    frame+="${sp}${3}${2}${C_DIM} · ${4}"
  else
    frame+="${sp}${3}${2}${RESET}"
  fi
  printf '%s' "$frame"
}

# ────────────────────────────────────────────────────────── window plumbing
# Closing the timer is just terminating the renderer — kitty exits with its
# child. No window rules, no dispatches: Hyprland tiles the timer kitty like
# any other window, and the clock centers itself inside that terminal.
renderer_pid() {
  pgrep -f -- "^bash .*flowstate\.sh run$" | head -1
}

launch() {
  command -v kitty >/dev/null 2>&1 || { echo "flowstate: kitty not found" >&2; exit 1; }
  kitty --class flowstate --title flowstate -o font_size="$FONT_SIZE" \
    -e bash "$SELF" run >/dev/null 2>&1 &
}

case "${1:-toggle}" in
  run)
    run
    ;;
  toggle)
    if [[ -n $(renderer_pid) ]]; then
      kill -TERM "$(renderer_pid)" 2>/dev/null
      write_state idle 0
    else
      launch
    fi
    ;;
  pause)
    pid=$(renderer_pid)
    [[ -n $pid ]] && kill -USR1 "$pid" 2>/dev/null
    ;;
  stop)
    pkill -TERM -f -- "^bash .*flowstate\.sh run$" 2>/dev/null
    write_state idle 0
    ;;
  *)
    echo "usage: flowstate.sh [toggle|run|pause|stop]" >&2
    exit 2
    ;;
esac
