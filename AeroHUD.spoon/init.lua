--- === AeroHUD ===
---
--- An animated on-screen HUD for AeroSpace workspace switches.
---
--- Wire it to AeroSpace with `exec-on-workspace-change` (see examples/aerospace.toml).

local obj = {}
obj.__index = obj

obj.name = "AeroHUD"
obj.version = "0.1.0"
obj.author = "Maverick Chow"
obj.homepage = "https://github.com/Maverick-Chow/AeroHUD"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.spoonPath = hs.spoons.scriptPath()

--- AeroHUD.aerospacePath
--- Variable
--- Path to the aerospace CLI. Defaults to the Homebrew location (Apple Silicon or Intel).
obj.aerospacePath = hs.fs.attributes("/opt/homebrew/bin/aerospace") and "/opt/homebrew/bin/aerospace"
  or "/usr/local/bin/aerospace"

local defaults = {
  position = "bottom",   -- "bottom" | "center" | "top"
  duration = 0.8,        -- seconds the HUD stays fully visible
  showAppIcons = true,
  theme = "auto",        -- "auto" | "dark" | "light"
  width = 240,           -- minimum; grows to fit one tile per workspace
  height = 120,
}

local TILE_WIDTH = 62    -- tile + gap in hud.css, used to size the window

local SEP = "@@AEROSPACE_HUD@@"

-- Quote a string for /bin/sh.
local function q(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function lines(s)
  local t = {}
  for line in s:gmatch("[^\n]+") do t[#t + 1] = line end
  return t
end

--- AeroHUD:configure(opts)
--- Method
--- Override any of the default options. Returns the Spoon for chaining.
function obj:configure(opts)
  self.opts = {}
  for k, v in pairs(defaults) do self.opts[k] = v end
  for k, v in pairs(opts or {}) do self.opts[k] = v end
  return self
end

function obj:_frame(screen, count)
  local f = screen:frame()
  local w = math.max(self.opts.width, (count or 0) * TILE_WIDTH + 80)
  local h = self.opts.height
  local x = f.x + (f.w - w) / 2
  local y
  if self.opts.position == "top" then
    y = f.y + 60
  elseif self.opts.position == "bottom" then
    y = f.y + f.h - h - 20
  else
    y = f.y + (f.h - h) / 2
  end
  return { x = x, y = y, w = w, h = h }
end

--- AeroHUD:start()
--- Method
--- Create the (hidden) HUD webview. Returns the Spoon for chaining.
function obj:start()
  if not self.opts then self:configure() end
  if self.webview then return self end

  local wv = hs.webview.new(self:_frame(hs.screen.mainScreen()))
  wv:windowStyle({ "borderless", "nonactivating" })
  wv:transparent(true)
  wv:level(hs.drawing.windowLevels.overlay)
  wv:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.stationary)
  wv:allowTextEntry(false)
  wv:shadow(false)
  wv:url("file://" .. self.spoonPath .. "hud.html")
  self.webview = wv

  -- The page calls back over this controller when its exit animation finishes.
  self.hideTimer = nil
  return self
end

--- AeroHUD:stop()
--- Method
--- Destroy the HUD.
function obj:stop()
  if self.hideTimer then self.hideTimer:stop() end
  if self.webview then self.webview:delete() end
  self.webview = nil
  return self
end

-- Run all aerospace queries in one background process. This must not block
-- Hammerspoon's main thread: the aerospace server queries every app over
-- Accessibility (Hammerspoon included), so a synchronous hs.execute deadlocks
-- until the AX timeout fires.
function obj:_query(callback)
  local a = q(self.aerospacePath)
  local script = table.concat({
    a .. " list-workspaces --all",
    "echo " .. SEP,
    a .. " list-windows --all --format '%{workspace}|%{app-bundle-id}|%{app-name}'",
  }, "; ")
  if self.task and self.task:isRunning() then self.task:terminate() end
  self.task = hs.task.new("/bin/sh", function(_, stdout)
    local parts = {}
    for part in ((stdout or "") .. SEP):gmatch("(.-)" .. SEP) do parts[#parts + 1] = part end
    callback(parts[1] or "", parts[2] or "")
  end, { "-c", script })
  self.task:start()
end

-- Encoding an icon as a PNG data URL is the slow part, so do it once per app.
function obj:_icon(bundle)
  self.iconCache = self.iconCache or {}
  if self.iconCache[bundle] == nil then
    local img = hs.image.imageFromAppBundle(bundle)
    self.iconCache[bundle] = img and img:setSize({ w = 64, h = 64 }):encodeAsURLString(false, "PNG") or false
  end
  return self.iconCache[bundle] or nil
end

function obj:_workspaceData(ws, prev, allOut, windowsOut)
  -- Unique apps per workspace, in window order.
  local appsByWs, seen, icons = {}, {}, {}
  for _, line in ipairs(lines(windowsOut)) do
    local w, bundle, name = line:match("^(.-)|(.-)|(.*)$")
    if w then
      appsByWs[w] = appsByWs[w] or {}
      seen[w] = seen[w] or {}
      if bundle ~= "" and not seen[w][bundle] then
        seen[w][bundle] = true
        table.insert(appsByWs[w], { bundle = bundle, name = name })
        if self.opts.showAppIcons and icons[bundle] == nil then
          icons[bundle] = self:_icon(bundle) or false
        end
      end
    end
  end

  local workspaces = {}
  for _, name in ipairs(lines(allOut)) do
    local apps = appsByWs[name] or {}
    workspaces[#workspaces + 1] = { name = name, occupied = #apps > 0, apps = apps }
  end

  return {
    workspace = ws,
    previous = prev,
    workspaces = workspaces,
    icons = icons,
  }
end

--- AeroHUD:show(workspace, previous)
--- Method
--- Show the HUD for a workspace switch. Called from AeroSpace's callback.
function obj:show(ws, prev)
  if not self.webview then self:start() end
  self:_query(function(allOut, windowsOut)
    local data = self:_workspaceData(ws, prev, allOut, windowsOut)
    data.theme = self.opts.theme
    data.duration = self.opts.duration
    data.showAppIcons = self.opts.showAppIcons

    local wv = self.webview
    wv:frame(self:_frame(hs.screen.mainScreen(), #data.workspaces))
    wv:show()
    wv:evaluateJavaScript("window.hud && window.hud.show(" .. hs.json.encode(data) .. ")")

    -- Hide the window after the exit animation so it never blocks clicks.
    if self.hideTimer then self.hideTimer:stop() end
    self.hideTimer = hs.timer.doAfter(self.opts.duration + 0.6, function() wv:hide() end)
  end)
end

return obj
