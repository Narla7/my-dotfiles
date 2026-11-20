#!/usr/bin/env bash

# wifi menu: pick a network, enter the password if it has one, connect.

set -euo pipefail

# toggle: kill any open instance
if pgrep -f 'fuzzel.*--namespace=wifi-menu' >/dev/null; then
    pkill -f 'fuzzel.*--namespace=wifi-menu'
    exit 0
fi

notify() {
    command -v notify-send >/dev/null && notify-send -a wifi "$1" "${2:-}"
}

device="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1; exit }')"
[[ -n "$device" ]] || { notify "wifi" "no wifi device found"; exit 0; }

# rescan so freshly enabled/hidden networks show up
nmcli device wifi rescan ifname "$device" >/dev/null 2>&1 || true
sleep 1

current="$(nmcli -t -f ACTIVE,SSID dev wifi list ifname "$device" \
    | awk -F: '$1 == "yes" { print $2; exit }')"

# map: displayed entry -> $'security\tssid'
declare -A meta=()
entries=("connected: ${current:-none}")

# terse mode escapes ':' inside the ssid as '\:'; protect it before splitting
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    line="${line//\\:/$'\x01'}"
    inuse="${line%%:*}"; line="${line#*:}"
    ssid="${line%%:*}"; line="${line#*:}"
    signal="${line%%:*}"; security="${line#*:}"
    ssid="${ssid//$'\x01'/:}"
    [[ -n "$ssid" ]] || continue # skip hidden networks
    display="${inuse:+* }${ssid}  (${signal}%, ${security})"
    meta["$display"]="${security}"$'\t'"${ssid}"
    entries+=("$display")
done < <(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list ifname "$device")

choice="$(printf '%s\n' "${entries[@]}" \
    | fuzzel --dmenu --namespace=wifi-menu --prompt='wifi > ' --lines=10 --width=60 --no-sort)" || exit 0

# header line or anything not a scanned network: nothing to do
[[ -n "${meta[$choice]+x}" ]] || exit 0

security="${meta[$choice]%%$'\t'*}"
ssid="${meta[$choice]#*$'\t'}"

args=(device wifi connect "$ssid" ifname "$device")
prompted=0
if [[ -n "$security" && "$security" != "--" ]]; then
    password="$(fuzzel --dmenu --namespace=wifi-menu --password \
        --prompt-only "password for $ssid: " --cache /dev/null)" || exit 0
    if [[ -n "$password" ]]; then
        args+=(password "$password")
        prompted=1
    fi
    # empty password: fall through and let nmcli use a saved profile, if any
fi

if out="$(nmcli "${args[@]}" 2>&1)"; then
    notify "wifi" "connected to $ssid"
else
    # a bad password leaves a broken profile behind that would fail every
    # future attempt; remove it so the next try asks again
    if (( prompted )); then
        nmcli connection delete "$ssid" >/dev/null 2>&1 || true
    fi
    notify "wifi" "failed to connect to $ssid" "${out}"
fi
