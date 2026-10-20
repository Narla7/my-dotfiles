#!/usr/bin/env bash

set -euo pipefail

if pgrep -f 'fuzzel.*--namespace=audio-menu' >/dev/null; then
    pkill -f 'fuzzel.*--namespace=audio-menu'
    exit 0
fi

volume="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100) "%"}')"
choice="$(
    {
        printf 'volume: %s\n' "$volume"
        wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -E '[0-9]+\.' || true
    } | fuzzel --dmenu --namespace=audio-menu --prompt='audio > ' --lines=8 --width=60 --no-sort
)" || exit 0

if [[ "$choice" =~ ([0-9]+)\. ]]; then
    wpctl set-default "${BASH_REMATCH[1]}"
fi
