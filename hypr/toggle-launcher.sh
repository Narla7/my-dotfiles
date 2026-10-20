#!/usr/bin/env bash

set -euo pipefail

if pgrep -f 'fuzzel.*--namespace=app-launcher' >/dev/null; then
    pkill -f 'fuzzel.*--namespace=app-launcher'
else
    fuzzel --namespace=app-launcher
fi
