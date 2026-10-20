#!/usr/bin/env bash

set -euo pipefail

if pgrep -f 'fuzzel.*--namespace=wifi-menu' >/dev/null; then
    pkill -f 'fuzzel.*--namespace=wifi-menu'
    exit 0
fi

device="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1; exit }')"
[[ -n "$device" ]] || exit 0

current="$(nmcli -t -f ACTIVE,SSID dev wifi list ifname "$device" \
    | awk -F: '$1 == "yes" { print $2; exit }')"

choice="$(
    {
        printf 'connected: %s\n' "${current:-none}"
        nmcli -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list ifname "$device" \
            | sed '1d' | sed '/^$/d'
    } | fuzzel --dmenu --namespace=wifi-menu --prompt='wifi > ' --lines=10 --width=60 --no-sort
)" || exit 0

[[ "$choice" == connected:* ]] && exit 0

ssid="$(printf '%s\n' "$choice" | sed -E 's/^[* ]+//; s/[[:space:]]+[0-9]+[[:space:]]+(WPA[0-9+ -]*|WEP|--).*$//')"
[[ -n "$ssid" ]] && nmcli device wifi connect "$ssid" ifname "$device"
