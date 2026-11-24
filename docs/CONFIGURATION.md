# Configuring AeroHUD

## HUD options

Pass options to `configure` in `~/.hammerspoon/init.lua`, then reload Hammerspoon:

```lua
spoon.AeroHUD:configure({
  position = "bottom",
  duration = 0.8,
  showAppIcons = true,
  theme = "auto",
  peekKey = "alt",
}):start()
```

| Option | Default | Values |
|---|---|---|
| `position` | `"bottom"` | `"bottom"`, `"center"`, `"top"` |
| `duration` | `0.8` | seconds fully visible |
| `showAppIcons` | `true` | |
| `theme` | `"auto"` | `"auto"`, `"dark"`, `"light"` |
| `peekKey` | `nil` (off) | `"alt"`, `"ctrl"`, `"cmd"`, `"shift"`, `"fn"` |
| `peekDelay` | `0.3` | seconds the key is held before the HUD appears |

## Peeking

Set `peekKey` to show the HUD while you hold that modifier key on its own. It stays up while the key is down, updates as you switch workspaces, and fades out when you let go. Pressing any other key or clicking while holding it cancels the peek, so shortcuts that use the same modifier don't flash the HUD.

## Animating window moves

AeroSpace runs a callback when you switch workspaces, but not when you move a window. To animate moves, AeroHUD does the move itself: the installer changes simple bindings like

```toml
alt-shift-1 = 'move-node-to-workspace 1'
```

to

```toml
alt-shift-1 = "exec-and-forget /opt/homebrew/bin/hs -c 'spoon.AeroHUD:moveWindow(\"1\")' || /opt/homebrew/bin/aerospace move-node-to-workspace 1"
```

AeroHUD moves the focused window and flies its icon to the new workspace on the HUD. If Hammerspoon isn't running, the `||` falls back to a plain move, so the binding always works. Bindings with extra flags, or `next`/`prev`, are left as they are.
