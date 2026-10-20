#!/usr/bin/env bash

set -euo pipefail

# hyprshot waits for slurp while the region selector is open. Kill hyprshot
# first, then slurp, so cancellation cannot fall through to save_geometry.
hyprshot_pids="$(pgrep -f '[ /]hyprshot( |$)' || true)"
if [[ -n "$hyprshot_pids" ]] || pgrep -x slurp >/dev/null; then
    if [[ -n "$hyprshot_pids" ]]; then
        kill -KILL $hyprshot_pids 2>/dev/null || true
    fi
    pkill -KILL -x slurp 2>/dev/null || true
else
    hyprshot -m region --clipboard-only
fi
