#!/usr/bin/env bash
# install.sh — one-shot installer for narla's Hyprland + Quickshell shell.
#
# Arch Linux only. In order it:
#   1. sanity-checks the checkout and the machine
#   2. installs every runtime package (all official repos — no AUR helper)
#   3. backs up existing live configs under ~/.local/state/rice-backup/
#   4. mirrors hypr/, quickshell/, kitty/, starship/ with ./sync.sh (same excludes and
#      never-delete semantics; live-only files such as emoji-favorites.txt,
#      personal kitty themes and backups are preserved)
#   5. installs and enables the cliphist systemd user service
#   6. verifies the mirror and prints next steps

set -euo pipefail

# ────────────────────────────────────────────────────────────────── output
if [ -t 1 ]; then
    BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' YLW=$'\033[33m' RST=$'\033[0m'
else
    BOLD= DIM= RED= YLW= RST=
fi

say()  { printf '%s\n' "$*"; }
warn() { printf '%swarning:%s %s\n' "$YLW" "$RST" "$*" >&2; }
die()  { printf '%sinstall.sh: error:%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

step() { printf '\n%s── %s%s\n' "$BOLD" "$*" "$RST"; }

DRY=0
SKIP_PKGS=0
case "${1:-}" in
    "") ;;
    --dry-run)     DRY=1 ;;
    --no-packages) SKIP_PKGS=1 ;;
    -h|--help)
        cat <<'EOF'
install.sh — one-shot installer for narla's Hyprland + Quickshell shell.

Arch Linux only. It installs the runtime packages, backs up any existing
configs to ~/.local/state/rice-backup/<timestamp>/, mirrors hypr/,
quickshell/, kitty/ and starship/ into $XDG_CONFIG_HOME via ./sync.sh, and enables the
cliphist systemd user service.

Usage: ./install.sh [--dry-run] [--no-packages] [--help]
  --dry-run       print every action, change nothing
  --no-packages   skip the pacman step entirely
EOF
        exit 0 ;;
    *) die "unknown option '${1:-}' — try --help" ;;
esac

# Print a command, or run it. Every mutation goes through here.
run() {
    if [ "$DRY" -eq 1 ]; then
        printf '  %s(dry-run)%s ' "$DIM" "$RST"
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# ────────────────────────────────────────────────────────────────── sanity
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${XDG_CONFIG_HOME:-$HOME/.config}"

for f in sync.sh hypr/hyprland.lua quickshell/shell.qml kitty/kitty.conf \
         starship/starship.toml systemd/user/cliphist.service; do
    [ -f "$REPO/$f" ] || die "not a rice checkout — missing $REPO/$f"
done

[ "$(id -u)" -eq 0 ] && die "run this as your user, not root (it installs into \$HOME)"

command -v pacman >/dev/null 2>&1 || die "pacman not found — this installer is Arch Linux only"
os_id="$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
os_like="$(grep -E '^ID_LIKE=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
if [ "$os_id" != "arch" ] && [[ "$os_like" != *arch* ]]; then
    die "$os_id is not Arch-based — this installer needs pacman"
fi

case "$dest" in ""|"/"|"."|"..") die "bad XDG_CONFIG_HOME: '$dest'" ;; esac
[ "$dest" = "$REPO" ] && die "XDG_CONFIG_HOME points at the repo itself"
run mkdir -p "$dest"

if command -v sudo >/dev/null 2>&1; then
    PACMAN=(sudo pacman)
elif command -v doas >/dev/null 2>&1; then
    PACMAN=(doas pacman)
else
    die "no sudo or doas — install the packages yourself, then re-run with --no-packages"
fi

# ──────────────────────────────────────────────────────────────── packages
# Everything the configs and scripts spawn at runtime, in one list. All are
# official-repo packages, so no AUR helper is needed. rsync is required by
# sync.sh, pw-play (flowstate bells) lives in pipewire-audio, the emoji data
# in noctalia, the bell sounds in sound-theme-freedesktop.
packages=(
    hyprland quickshell kitty
    networkmanager
    pipewire pipewire-audio wireplumber
    cliphist wl-clipboard libnotify
    playerctl brightnessctl
    hyprshot grim slurp
    noctalia sound-theme-freedesktop
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd
    starship
    rsync
)

step "packages"
missing=()
for p in "${packages[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
done

if [ "$SKIP_PKGS" -eq 1 ]; then
    command -v rsync >/dev/null 2>&1 || die "rsync is missing and required by sync.sh"
    say "skipped (--no-packages)"
elif [ "${#missing[@]}" -eq 0 ]; then
    say "all ${#packages[@]} runtime packages already present"
else
    say "installing ${#missing[@]} of ${#packages[@]}: ${missing[*]}"
    run "${PACMAN[@]}" -S --needed -- "${missing[@]}"
    for p in "${missing[@]}"; do
        pacman -Q "$p" >/dev/null 2>&1 || die "pacman finished but $p is not installed"
    done
fi

# hyprland.lua needs Hyprland >= 0.56 (Lua config support)
hlver="$(pacman -Q hyprland 2>/dev/null | cut -d' ' -f2 || true)"
hlver="${hlver%%-*}"
if [ -n "$hlver" ] && [ "$(printf '%s\n%s\n' "$hlver" 0.56 | sort -V | head -1)" != "0.56" ]; then
    warn "hyprland $hlver is older than 0.56 — hyprland.lua needs >= 0.56"
fi

# ───────────────────────────────────────────────────────────────── backup
backup="${XDG_STATE_HOME:-$HOME/.local/state}/rice-backup/$(date +%Y%m%d-%H%M%S)"
backed_up=0

# Back up an existing live path into $backup. Directories are copied but
# left in place (the mirror overwrites files, never deletes), so live-only
# files survive the install. Symlinks and stray files are moved aside so
# real directories can be created in their place.
backup_rel() {
    local live="$dest/$1" bk="$backup/$1"
    if [ -L "$live" ] || [ -f "$live" ]; then
        run mkdir -p "$(dirname "$bk")"
        run mv "$live" "$bk"
        backed_up=1
    elif [ -d "$live" ]; then
        run mkdir -p "$(dirname "$bk")"
        run cp -a "$live" "$bk"
        backed_up=1
    fi
}

step "backup existing configs"
unit_src="$REPO/systemd/user/cliphist.service"
unit_dest="$dest/systemd/user/cliphist.service"
unit_modified=0
if [ -f "$unit_dest" ]; then
    if [ "$(cat "$unit_src")" != "$(cat "$unit_dest")" ]; then
        unit_modified=1
        backup_rel systemd/user/cliphist.service
    fi
fi
backup_rel hypr
backup_rel quickshell
backup_rel kitty
backup_rel starship
if [ "$backed_up" -eq 1 ]; then
    say "backup dir: $backup"
else
    say "nothing to back up — fresh install"
fi

# ──────────────────────────────────────────────────────────────── mirror
step "mirror configs (hypr, quickshell, kitty, starship)"
if [ "$DRY" -eq 1 ]; then
    run "$REPO/sync.sh" --dry-run
else
    run "$REPO/sync.sh"
fi

# ─────────────────────────────────────────────── cliphist systemd service
step "cliphist user service"
if [ "$unit_modified" -eq 1 ]; then
    warn "replacing modified live cliphist.service with the repo version (old copy kept in backup)"
fi
run install -D -m 644 "$unit_src" "$unit_dest"

if [ "$DRY" -eq 1 ]; then
    run systemctl --user daemon-reload
    run systemctl --user enable cliphist.service
else
    if out="$(systemctl --user daemon-reload 2>&1)"; then
        if systemctl --user is-active -q graphical-session.target; then
            systemctl --user enable --now cliphist.service
            say "cliphist.service enabled and started (session is live)"
        else
            systemctl --user enable cliphist.service
            say "cliphist.service enabled (starts on next login)"
        fi
    else
        warn "systemctl --user failed: $out"
        warn "the unit is installed; Hyprland also enables it at first login, or run:"
        warn "  systemctl --user enable cliphist.service"
    fi
fi

# ──────────────────────────────────────────────────────────────── verify
step "verify"
if [ "$DRY" -eq 0 ]; then
    if ! diff_out="$("$REPO/sync.sh" --dry-run 2>&1)"; then
        die "sync.sh --dry-run failed: ${diff_out:-<no output>}"
    fi
    if [ -n "$diff_out" ]; then
        die "mirror verification failed, sync.sh --dry-run still reports: $diff_out"
    fi
    say "mirror is clean — repo and $dest are identical"
fi

missbin=()
if [ "$DRY" -eq 1 ]; then
    say "skipping binary check in dry-run"
else
    for c in quickshell qs kitty hyprctl hyprshot grim slurp wpctl pw-play \
             cliphist wl-copy wl-paste nmcli playerctl brightnessctl notify-send rsync starship; do
        command -v "$c" >/dev/null 2>&1 || missbin+=("$c")
    done
fi
if [ "${#missbin[@]}" -gt 0 ]; then
    warn "missing binaries: ${missbin[*]}"
    if [ "$SKIP_PKGS" -eq 0 ]; then
        die "the package install should have provided these — aborting"
    fi
fi

# Keybinds that launch optional personal apps; absence is not fatal.
for app in btop zen-browser nautilus obsidian spotify zeditor opencode; do
    command -v "$app" >/dev/null 2>&1 ||
        warn "keybind app '$app' is not installed (optional — install it manually if wanted)"
done

# The shell runs its own NotificationServer; a second daemon breaks it.
if command -v pgrep >/dev/null 2>&1; then
    for d in mako dunst swaync; do
        if pgrep -x "$d" >/dev/null 2>&1; then
            warn "notification daemon '$d' is running — this shell has its own notification server, disable $d"
        fi
    done
fi

# ───────────────────────────────────────────────────────────── next steps
step "done"
if [ "$DRY" -eq 1 ]; then
    say "dry run complete — nothing was changed"
    exit 0
fi
say "installed to: $dest/{hypr,quickshell,kitty,starship} (+ systemd/user/cliphist.service)"
say "preserved as-is: emoji-favorites.txt, ~/.local/state/{flowstate,narla-shell}, live-only extras"
say ""
say "next:"
say "  - log into a Hyprland session (re-login is the cleanest start);"
say "    if you installed inside a live session, Hyprland auto-reloads and"
say "    quickshell hot-reloads its QML — check 'qs log' and 'hyprctl configerrors'"
say "  - super+enter kitty · super+space launcher · super+esc system menu · print screenshot"
if [ "$backed_up" -eq 1 ]; then
    say "  - rollback: cp -a $backup/{hypr,quickshell,kitty,starship} $dest/"
fi
