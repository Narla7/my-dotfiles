# Narla's dotfiles

My Arch Linux Hyprland + Quickshell setup. 

Here is the youtube Video link: https://youtu.be/LRPfbdlwcIs?si=jAXinFnIYocbr1lF

## Included

- **Hyprland** — Lua config, Dwindle tiling, keybinds, window rules, media keys
- **Quickshell** — gruvbox bar, right-edge panels (launcher, system menu, clipboard, calendar, wifi, audio, notifications, media), wallpaper
- **Kitty** — Gruvbox Material theme, 25% transparency, transparent TUI backgrounds
- **btop** — terminal background transparency support

## Layout

```text
hypr/       Hyprland config and helper scripts
quickshell/ Bar, right-edge panels, launcher, and theme
kitty/      Kitty config and theme
systemd/    cliphist clipboard-history user service
```

## Install

Arch Linux only, from the repo root:

```bash
./install.sh                 # packages + configs + cliphist service
./install.sh --dry-run       # preview every action, change nothing
./install.sh --no-packages   # skip pacman (configs only)
```

The installer installs the runtime packages (all official repos — Hyprland,
Quickshell, kitty, NetworkManager, PipeWire/WirePlumber, cliphist,
wl-clipboard, libnotify, playerctl, brightnessctl, hyprshot/grim/slurp,
noctalia, JetBrains Mono fonts), backs up any existing configs to
`~/.local/state/rice-backup/`, mirrors `hypr/ quickshell/ kitty/` via
`./sync.sh` (live-only files like `emoji-favorites.txt` are preserved), and
enables the `cliphist` user service. Then log into a Hyprland session.

## Main keybinds

- `SUPER + RETURN` — Kitty
- `SUPER + SPACE` — toggle the Quickshell app launcher (`Ctrl + F` inside pins/unpins the selected app)
- `SUPER + ESCAPE` — toggle the Quickshell system menu
- `SUPER + SHIFT + C` — OpenCode CLI in Kitty
- `SUPER + SHIFT + Z` — Zed
- `SUPER + 1..5` — switch workspace
- `SUPER + SHIFT + 1..5` — move window to workspace
- `PRINT` — toggle screenshot region selector
- `SUPER + .` — dismiss all notifications

## License

MIT. See [LICENSE](LICENSE).
