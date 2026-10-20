-- ~/.config/hypr/hyprland.lua
-- Narla's Hyprland config — Lua (Hyprland 0.55+ / 0.56)
-- Theme: Omarchy Miasma (github.com/OldJobobo/omarchy-miasma-theme)
--   bg #222222 · fg #c2c2b0 · accent-blue #78824b · cursor #d7c483
-- Old hyprlang config kept at hyprland.conf.bak

local mod = "SUPER + "
local configHome = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")

-- ──────────────────────────────────────────────────────────── environment
-- Electron/Chromium apps (zen, obsidian, spotify) pick the Wayland backend.
-- NIXOS_OZONE_WL is the NixOS-only spelling of this; on Arch use this one.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
-- Session identity: on NixOS the desktop module exports these; on Arch nothing does,
-- and xdg-desktop-portal / GTK need them.
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- ──────────────────────────────────────────────────────────── monitors (auto)
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "auto", scale = 1 })

-- ──────────────────────────────────────────────────────────── look (miasma)
hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        layout = "dwindle",
        col = {
            -- thin blue outline around the focused window
            active_border = { colors = { "rgb(78824b)", "rgb(3c4125)" }, angle = 35 },
            inactive_border = { colors = { "rgb(43492a)", "rgb(222222)" }, angle = 35 },
        },
    },
    decoration = {
        rounding = 0,
        active_opacity = 1.0,
        inactive_opacity = 0.96,
        dim_strength = 0.12,
        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            ignore_opacity = false,
        },
        shadow = {
            enabled = true,
            range = 10,
            render_power = 3,
            color = "rgba(0, 0, 0, 0.6)",
            offset = "2 2",
        },
    },
    animations = {
        enabled = true,
    },
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
        },
    },
    misc = {
        disable_hyprland_logo = true,
        focus_on_activate = true,
    },
    xwayland = {
        force_zero_scaling = true,
    },
    dwindle = {
        preserve_split = true,
        -- New tiled windows open on the right by default.
        force_split = 2,
    },
})

-- ──────────────────────────────────────────────────────────── curves/animations
-- Workspace slide curve.
hl.curve("fogbank", { type = "bezier", points = { { 0.70, 0.01 }, { 0.30, 1.00 } } })

-- Only workspace changes animate. Everything else is deliberately instant.
hl.animation({ leaf = "windows", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "windowsIn", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "windowsOut", enabled = false, speed = 0, bezier = "default" })
-- Window moves animate; all other window animations stay disabled.
hl.curve("miasma", { type = "bezier", points = { { 0.55, 0.02 }, { 0.38, 0.98 } } })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "miasma" })
hl.animation({ leaf = "border", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "fade", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "fadeIn", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "fadeOut", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "layers", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "layersIn", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "layersOut", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "specialWorkspace", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = false, speed = 0, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "fogbank", style = "slide" })

-- ──────────────────────────────────────────────────────────── 5 workspaces
hl.workspace_rule({ workspace = "1", persistent = true, default = true })
hl.workspace_rule({ workspace = "2", persistent = true })
hl.workspace_rule({ workspace = "3", persistent = true })
hl.workspace_rule({ workspace = "4", persistent = true })
hl.workspace_rule({ workspace = "5", persistent = true })

-- ──────────────────────────────────────────────────────────── window rules
-- Ignore app maximize requests so Kitty stays in the Dwindle tiling layout.
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Kitty stays tiled like every normal application.
hl.window_rule({ match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ match = { class = "^(pavucontrol)$" }, float = true })
-- Keep kitty corners square so rounded cutouts don't leak wallpaper/mismatched transparency.
hl.window_rule({ match = { class = "^(kitty)$" }, rounding = 0, border_size = 2, no_shadow = true })

-- ──────────────────────────────────────────────────────────── keybinds
-- apps
hl.bind(mod .. "SPACE", hl.dsp.exec_cmd("bash \"" .. configHome .. "/hypr/toggle-launcher.sh\""))
-- Arch: the AUR zen-browser-bin package installs /usr/bin/zen-browser (not "zen").
hl.bind(mod .. "SHIFT + RETURN", hl.dsp.exec_cmd("zen-browser"))
hl.bind(mod .. "SHIFT + F", hl.dsp.exec_cmd("nautilus"))
hl.bind(mod .. "RETURN", hl.dsp.exec_cmd("kitty"))
hl.bind(mod .. "SHIFT + O", hl.dsp.exec_cmd("obsidian"))
hl.bind(mod .. "SHIFT + S", hl.dsp.exec_cmd("spotify"))
hl.bind(mod .. "SHIFT + C", hl.dsp.exec_cmd("kitty -e opencode"))
hl.bind(mod .. "SHIFT + Z", hl.dsp.exec_cmd("zeditor"))
-- Resolved from PATH; install hermes-desktop wherever you keep it.
hl.bind(mod .. "A", hl.dsp.exec_cmd("hermes-desktop"))

-- window management
hl.bind(mod .. "W", hl.dsp.window.kill())
hl.bind(mod .. "F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mod .. "V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. "ESCAPE", hl.dsp.exec_cmd("bash \"" .. configHome .. "/hypr/system-menu.sh\""))

-- workspaces 1-5: switch + move window
for i = 1, 5 do
    hl.bind(mod .. tostring(i), hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind(mod .. "SHIFT + " .. tostring(i), hl.dsp.window.move({ workspace = tostring(i) }))
end

-- arrow-key focus only (vim letters are intentionally not bound)
hl.bind(mod .. "left", hl.dsp.focus({ direction = "l" }))
hl.bind(mod .. "down", hl.dsp.focus({ direction = "d" }))
hl.bind(mod .. "up", hl.dsp.focus({ direction = "u" }))
hl.bind(mod .. "right", hl.dsp.focus({ direction = "r" }))

-- Move + raise the focused window; windowsMove animates the transition.
local function moveFocused(direction)
    hl.dispatch(hl.dsp.window.move({ direction = direction }))
    hl.dispatch(hl.dsp.window.bring_to_top())
end

hl.bind(mod .. "SHIFT + left", function() moveFocused("l") end)
hl.bind(mod .. "SHIFT + down", function() moveFocused("d") end)
hl.bind(mod .. "SHIFT + up", function() moveFocused("u") end)
hl.bind(mod .. "SHIFT + right", function() moveFocused("r") end)

-- mouse
hl.bind(mod .. "mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. "mouse:273", hl.dsp.window.resize(), { mouse = true })

-- media keys (locked = keep working while the launcher/menu grabs keys)
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })

-- screenshot / brightness
hl.bind("PRINT", hl.dsp.exec_cmd("bash \"" .. configHome .. "/hypr/toggle-screenshot.sh\""))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true })

-- ──────────────────────────────────────────────────────────── autostart
hl.on("hyprland.start", function()
    -- Make the session env visible to the systemd user manager and D-Bus, so
    -- portals, screen sharing and file pickers work. NixOS did this for you.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("quickshell")
    -- own org.freedesktop.Notifications from session start (dunst)
    hl.exec_cmd("dunst")
end)
