#!/usr/bin/env bash
# Emoji picker — rofi dmenu, gruvbox dark.
# Enter    = copy emoji to clipboard (wl-copy) — mouse click also copies
# Ctrl+f   = toggle favourite (⭐), favourites are listed first
# Ctrl+Shift+Up / Ctrl+Shift+Down = reorder favourites
# Up/Down  = move a row (both columns at once)
# Left/Right = move one emoji left/right within the row
# Mouse wheel = scroll a full page of the menu
# Esc      = quit

set -euo pipefail

DIR="$HOME/.config/hypr"
THEME="$DIR/emoji-picker.rasi"
FAVS="$DIR/emoji-favorites.txt"
SRC="/usr/share/noctalia/assets/emoji.json"

# "★ emoji name" for favourites (in FAVS file order), rest after.
build_list() {
    python3 - "$SRC" "$FAVS" <<'PY'
import json, os, sys

src, favs = sys.argv[1], sys.argv[2]
emojis = json.load(open(src))
lines = {e["emoji"]: f'{e["emoji"]} {e["name"]}' for e in emojis}

order = []
if os.path.exists(favs):
    order = [l.rstrip("\n") for l in open(favs, encoding="utf-8") if l.strip()]
order = [x for x in dict.fromkeys(order) if x in lines]  # dedupe, drop stale

fav_lines = ["★ " + lines[x] for x in order]
rest = [l for x, l in lines.items() if x not in order]

print("\n".join(fav_lines + rest), end="")
PY
}

# The emoji is the run of non-space chars at the start of the line
# (after the optional "★ " favourite marker). Multi-codepoint emoji
# (ZWJ sequences, skin tones) contain no spaces, so this is safe.
emoji_of() {
    local line="$1"
    line="${line#★ }"
    printf '%s' "${line%% *}"
}

is_fav() {
    grep -Fxq "$1" "$FAVS" 2>/dev/null
}

toggle_fav() {
    local emoji="$1" tmp
    if is_fav "$emoji"; then
        tmp="$(mktemp)"
        grep -Fxv "$emoji" "$FAVS" > "$tmp" || true
        mv "$tmp" "$FAVS"
    else
        echo "$emoji" >> "$FAVS"
    fi
}

# Move a favourited emoji up/down within the favourites list (file order).
# Ignored silently if the emoji is not in the favourites file.
move_fav() {
    local emoji="$1" dir="$2"
    [[ -f "$FAVS" && -s "$FAVS" ]] || return 0
    python3 - "$FAVS" "$emoji" "$dir" <<'PY'
import sys
favs, emoji, direction = sys.argv[1], sys.argv[2], sys.argv[3]
lines = [l.rstrip("\n") for l in open(favs, encoding="utf-8") if l.strip()]
if emoji not in lines:
    sys.exit(0)
i = lines.index(emoji)
j = i - 1 if direction == "up" else i + 1
if 0 <= j < len(lines):
    lines[i], lines[j] = lines[j], lines[i]
with open(favs, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY
}

# toggle: if the picker's rofi is already open, close it and exit
if pgrep -f 'rofi -dmenu.*-name emoji-picker' >/dev/null; then
    pkill -f 'rofi -dmenu.*-name emoji-picker'
    exit 0
fi

while true; do
    rc=0
    choice="$(build_list | rofi -dmenu \
        -i -p 'emoji' -name emoji-picker -theme "$THEME" \
        -kb-move-char-back "" \
        -kb-move-char-forward "" \
        -kb-row-left "Left" \
        -kb-row-right "Right" \
        -kb-custom-1 "Ctrl+f" \
        -kb-custom-2 "Control+Shift+Up" \
        -kb-custom-3 "Control+Shift+Down")" || rc=$?

    # rofi exits 10 for kb-custom-1 (Ctrl+f)
    if [[ $rc -eq 10 ]]; then
        toggle_fav "$(emoji_of "$choice")"
        continue
    fi

    # kb-custom-2/3: move favourited emoji up/down (Ctrl+Shift+Up/Down)
    if [[ $rc -eq 11 || $rc -eq 12 ]]; then
        move_fav "$(emoji_of "$choice")" "$([[ $rc -eq 11 ]] && echo up || echo down)"
        continue
    fi

    [[ $rc -eq 0 && -n "${choice:-}" ]] || exit 0

    emoji="$(emoji_of "$choice")"
    printf '%s' "$emoji" | wl-copy
    exit 0
done
