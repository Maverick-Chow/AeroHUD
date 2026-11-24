-- Example ~/.hammerspoon/init.lua
require("hs.ipc") -- needed for the `hs` CLI that AeroSpace calls

hs.loadSpoon("AeroHUD")
spoon.AeroHUD:configure({
  position = "bottom", -- "bottom" | "center" | "top"
  duration = 0.8,
  showAppIcons = true,
  theme = "auto",
  peekKey = "alt",     -- hold Option to show the HUD; remove to turn off
}):start()
