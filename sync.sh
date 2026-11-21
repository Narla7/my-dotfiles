#!/usr/bin/env bash
# Mirror this repo's configs into the live XDG config directory.
# The repo is the source of truth: run this after every edit.
# Live-only files (personal state, backups, extra themes) are never deleted.
#
# Usage: ./sync.sh [--dry-run]

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${XDG_CONFIG_HOME:-$HOME/.config}"

dry=()
case "${1:-}" in
    "") ;;
    -n|--dry-run) dry=(-n) ;;
    -h|--help)
        echo "usage: $0 [--dry-run]" >&2
        exit 0
        ;;
    *)
        echo "usage: $0 [--dry-run]" >&2
        exit 2
        ;;
esac

# Never copy editor backups or personal state into the live config.
excludes=(
    --exclude='*.bak'
    --exclude='*.bak-*'
    --exclude='*.log'
    --exclude='*.swp'
    --exclude='*~'
    --exclude='emoji-favorites.txt'
)

for dir in hypr quickshell kitty starship; do
    mkdir -p "$dest/$dir"
    rsync -a --checksum --itemize-changes "${dry[@]}" "${excludes[@]}" "$repo/$dir/" "$dest/$dir/"
done
