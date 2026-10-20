#!/usr/bin/env bash

set -euo pipefail

if pgrep -f 'fuzzel.*--namespace=power-menu' >/dev/null; then
    pkill -f 'fuzzel.*--namespace=power-menu'
    exit 0
fi

if ! choice="$(printf '%s\n' 'logout' 'reboot' 'power off' 'suspend' \
    | fuzzel --dmenu --namespace=power-menu --prompt='system > ' --lines=4 --width=24 --no-sort)"; then
    exit 0
fi

case "$choice" in
    logout)
        hyprctl eval 'hl.dispatch(hl.dsp.exit())'
        ;;
    reboot)
        systemctl reboot
        ;;
    'power off')
        systemctl poweroff
        ;;
    suspend)
        systemctl suspend
        ;;
esac
