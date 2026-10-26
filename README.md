# Narla's dotfiles

My Arch Linux Hyprland + Quickshell setup. 

Here is the youtube Video link: https://youtu.be/LRPfbdlwcIs?si=jAXinFnIYocbr1lF

## Included

- **Hyprland** — Lua config, Dwindle tiling, keybinds, window rules, media keys
- **Quickshell** — Miasma bar, Arch logo, clock/date calendar, Rockman wallpaper
- **Fuzzel** — Miasma app launcher, power menu, Wi-Fi menu, and audio-device menu
- **Kitty** — Gruvbox Material theme, 25% transparency, transparent TUI backgrounds
- **btop** — terminal background transparency support

## Layout

```text
hypr/       Hyprland config and helper scripts
quickshell/ Bar, calendar, wallpaper, and theme
fuzzel/     Fuzzel launcher styling
kitty/      Kitty config and theme
btop/       btop config
```

## Install

Back up existing configs first, then copy or symlink the directories:

```bash
mkdir -p ~/.config
cp -a hypr ~/.config/hypr
cp -a quickshell ~/.config/quickshell
cp -a fuzzel ~/.config/fuzzel
cp -a kitty ~/.config/kitty
cp -a btop ~/.config/btop
```

The setup expects Hyprland, Quickshell, Fuzzel, Kitty, btop, NetworkManager,
PipeWire/WirePlumber, `hyprshot`, `grim`, `slurp`, and `wl-clipboard`.

## Main keybinds

- `SUPER + RETURN` — Kitty
- `SUPER + SPACE` — toggle Fuzzel app launcher
- `SUPER + ESCAPE` — toggle Fuzzel power menu
- `SUPER + SHIFT + C` — OpenCode CLI in Kitty
- `SUPER + SHIFT + Z` — Zed
- `SUPER + 1..5` — switch workspace
- `SUPER + SHIFT + 1..5` — move window to workspace
- `PRINT` — toggle screenshot region selector

## License

MIT. See [LICENSE](LICENSE).
