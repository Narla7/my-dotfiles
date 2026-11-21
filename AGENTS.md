# AGENTS.md

Personal Arch Linux dotfiles: Hyprland (Lua config) + Quickshell + kitty.
No build, tests, lint, or CI. Verify by syncing to `~/.config` and using the
running Wayland session.

## Repo is the source of truth — always sync

- After **any** edit here, run `./sync.sh` (preview with `./sync.sh --dry-run`).
  It mirrors `hypr/`, `quickshell/`, `kitty/`, and `starship/` into
  `${XDG_CONFIG_HOME:-$HOME/.config}` so repo and live files are identical.
- Never edit files directly under `~/.config`; edit here, then sync. If a
  live-only change must be kept, copy it into this repo first, then sync.
- `sync.sh` overwrites config files but does **not** delete live-only extras
  (personal state, backups, extra themes). It excludes `*.bak`, `*.bak-*`,
  `*.log`, `*.swp`, `*~`, and `emoji-favorites.txt`. Deleting a file here leaves
  the live copy in place; remove that by hand if you really want it gone.
- Scripts and QML invoke `$HOME/.config/hypr/*.sh` by absolute path, so the live
  copy is what actually runs; a change is only testable after syncing.
- Check with `diff -r hypr ~/.config/hypr` (same for the other dirs). Remaining
  diffs should only be live-only extras such as `emoji-favorites.txt`, backups,
  and extra kitty themes — never repo files.
- `install.sh` is the one-shot installer for fresh machines: it verifies the
  checkout, installs the runtime packages (official repos only), backs up live
  configs to `~/.local/state/rice-backup/`, calls `sync.sh` for the mirroring,
  then installs + enables `systemd/user/cliphist.service`. Keep the mirror
  semantics in `sync.sh`; don't duplicate them in `install.sh`.
- `hypr/flowstate.sh` is byte-identical to `~/Projects/flowstate/flowstate.sh`
  (separate repo). Mirror changes to both.

## How it is wired

- `hypr/hyprland.lua` is the active config on Hyprland 0.56+ (machine has
  0.57.2). There is no hyprlang fallback — Lua configs are required.
- Workspace count is duplicated: `hyprland.lua` rules + keybind loop, and
  `quickshell/Bar.qml`'s `[1, 2, 3, 4, 5]` model. Change both together.
- Fuzzel was fully removed: the launcher, system menu, wifi menu and audio menu
  are all QML side panels now. The old `toggle-launcher.sh`, `system-menu.sh`,
  `wifi-menu.sh` and `audio-menu.sh` fuzzel scripts were deleted — don't
  reintroduce fuzzel for anything keyboard-driven; prefer QML panels.
- `quickshell/shell.qml` is the entrypoint. It exposes IPC targets `bar`
  (`wifi`, `audio`, `close`, `clipboard`, `emoji`, `calendar`, `launcher`,
  `system`, `notifications`, `mpris`) and `notifications` (`dismiss`,
  `dismissAll`), used as `qs ipc call <target> <fn>`; list live ones with
  `qs ipc show`.
- The right-edge side panels (`clipboard`, `emoji`, `launcher`, `system`,
  `notifications` (history centre), `media` (MPRIS), `wifi`, `audio`) all
  derive from `quickshell/SidePanelWindow.qml` (gruvbox via
  `Gruvbox.qml`). Adding one means: new QML file deriving SidePanelWindow,
  an `xxxOpen` property + branch in `closeAllBut()`/`sidePanelOpen` in
  `shell.qml`, an IPC function on the `bar` target, and a keybind in
  `hyprland.lua`. `calendar` is its own PanelWindow (Miasma, top overlay)
  and also lives in that open/close plumbing.
- `NotificationCenter.qml` reads a `historyModel` owned by `Notifications.qml`
  (the popup window); `shell.unreadNotifications` drives the bar bell's dot and
  is cleared whenever the centre opens. `MprisPanel.qml` and the bar's media
  widget both pick the first *playing* MPRIS player, else the first known one.
- `quickshell/Clipboard.qml` depends on `cliphist` and `wl-clipboard`. Its
  systemd unit (`~/.config/systemd/user/cliphist.service`) and the package are
  outside this repo, so don't assume a fresh restore has clipboard history.
- `hypr/flowstate.sh` writes `~/.local/state/flowstate/bar` as
  `phase seconds [paused]`; `Bar.qml` parses that exact format. Change the
  protocol in both or the bar widget breaks.
- The emoji picker is a QML panel now (`quickshell/EmojiPicker.qml`,
  opened by `mod+E` via `qs ipc call bar emoji`). The old rofi implementation
  (`hypr/emoji-picker.sh` + `hypr/emoji-picker.rasi`) was deleted; don't
  reintroduce fuzzel or rofi for anything keyboard-driven — prefer QML
  panels. Favorites live at
  `~/.config/hypr/emoji-favorites.txt` (one emoji per line, excluded from
  `sync.sh`) is shared by the picker; the emoji data source
  is `/usr/share/noctalia/assets/emoji.json` (noctalia package).
- Theme split is mostly settled on gruvbox: the bar and right-edge panels read
  `quickshell/Gruvbox.qml` (same palette as the clipboard column); calendar,
  notifications, and wallpaper still use Miasma
  (`quickshell/Miasma.qml`). Kitty and the emoji picker use Gruvbox Material.
- The starship prompt config lives in `starship/starship.toml` (gruvbox palette
  matching Gruvbox.qml). Fish loads it via `starship init fish | source` in
  `~/.config/fish/config.fish`, which is live-only and outside this repo.

## Verify changes

- Hyprland: the config auto-reloads on save; force it with `hyprctl reload`,
  then check `hyprctl configerrors` and the Hyprland log for Lua/parse errors.
- With a Lua config, `hyprctl dispatch` expects a Lua expression
  (`hyprctl dispatch 'hl.dsp.focus({ workspace = "2" })'`); old hyprlang strings
  like `hyprctl dispatch workspace 2` fail. Use `hyprctl eval` for ad-hoc Lua.
- Quickshell: hot reloads saved QML automatically and logs errors to `qs log`;
  a broken file keeps the last valid version.
- Shell scripts: `bash -n path.sh`, then `./sync.sh` and run the installed copy.
  They assume Hyprland, NetworkManager, WirePlumber, and kitty.
- Side panels can be driven headlessly: toggle with `qs ipc call bar <target>`,
  confirm with `hyprctl layers | grep <namespace>`, close with
  `qs ipc call bar close`. `qs log` must stay free of QML/JS errors
  (ignore its unrelated Qt textinput/portal warnings).
- Limits hit so far: `hyprctl getoption` can't read animation leaves on
  0.57 (only plain options like `animations:enabled`), and `hl.get_config()`
  inside `hyprctl eval` doesn't expose them either — animation settings are
  verified by reading the config file, not by querying Hyprland.

## QML gotchas

- In a `TextInput`, specific handlers (`Keys.onUpPressed`,
  `Keys.onReturnPressed`, …) run **before** a generic `Keys.onPressed` and
  accept the event, so modified combos like Ctrl+Shift+Up never reach it.
  This silently broke favourite reordering once. Use one `Keys.onPressed`
  handler that switches on key + modifiers and `event.accepted = true`.
- rofi was dropped for the emoji picker because its keybind/scroll behavior
  couldn't be verified from a script (`rofi -dmenu` exits instantly, rc=1,
  when spawned outside an interactive grab) and the user kept fighting its
  navigation. Prefer QML panels for anything keyboard-driven.

## Deliberate quirks — don't "fix" them

- `quirks.skip_non_kms_dmabuf_formats = false` in `hyprland.lua`: required on the
  old Intel GPU here; otherwise transparent surfaces render black and kitty
  fails with "No EGLConfigs returned".
- kitty's `background_opacity 0.5625` with `@1.0` alpha modifiers: this equalizes
  text and padding alpha. Changing either value reintroduces the visible band.
- `Bar.qml` reads volume via `wpctl` because Quickshell's PipeWire node binding
  is broken in 0.3.x; don't replace it with the Qt binding.
