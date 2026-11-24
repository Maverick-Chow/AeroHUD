--- === AeroHUD ===
---
--- An animated on-screen HUD for AeroSpace workspace switches.
---
--- Wire it to AeroSpace with `exec-on-workspace-change` (see examples/aerospace.toml).

local obj = {}
obj.__index = obj

obj.name = "AeroHUD"
obj.version = "0.2.1"
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
local WINDOW_FORMAT = "'%{window-id}|%{workspace}|%{app-bundle-id}|%{app-name}'"

-- slot names the caller: a new query cancels a still-running one in the same
-- slot (only the latest switch matters), but never one in another slot.
function obj:_query(slot, callback)
  local a = q(self.aerospacePath)
  local script = table.concat({
    a .. " list-workspaces --all",
    "echo " .. SEP,
    a .. " list-windows --all --format " .. WINDOW_FORMAT,
    "echo " .. SEP,
    a .. " list-windows --focused --format " .. WINDOW_FORMAT .. " 2>/dev/null",
  }, "; ")
  self.tasks = self.tasks or {}
  local old = self.tasks[slot]
  if old and old:isRunning() then old:terminate() end
  self.tasks[slot] = hs.task.new("/bin/sh", function(_, stdout)
    self.tasks[slot] = nil
    local parts = {}
    for part in ((stdout or "") .. SEP):gmatch("(.-)" .. SEP) do parts[#parts + 1] = part end
    callback(lines(parts[1] or ""), self:_parseWindows(parts[2] or ""), self:_parseWindows(parts[3] or "")[1])
  end, { "-c", script })
  self.tasks[slot]:start()
end

-- Every show/move gets a sequence number when it is called, so results that
-- come back out of order can't put the highlight on a stale workspace.
function obj:_nextSeq()
  self.seq = (self.seq or 0) + 1
  return self.seq
end

function obj:_setFocus(ws, seq)
  if not self.focus or self.focus.seq < seq then self.focus = { ws = ws, seq = seq } end
  return self.focus.ws
end

function obj:_parseWindows(out)
  local windows = {}
  for _, line in ipairs(lines(out)) do
    local id, ws, bundle, name = line:match("^(.-)|(.-)|(.-)|(.*)$")
    if id then windows[#windows + 1] = { id = id, workspace = ws, bundle = bundle, name = name } end
  end
  return windows
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

function obj:_workspaceData(ws, names, windows)
  -- Unique apps per workspace, in window order.
  local appsByWs, seen, icons = {}, {}, {}
  for _, w in ipairs(windows) do
    appsByWs[w.workspace] = appsByWs[w.workspace] or {}
    seen[w.workspace] = seen[w.workspace] or {}
    if w.bundle ~= "" and not seen[w.workspace][w.bundle] then
      seen[w.workspace][w.bundle] = true
      table.insert(appsByWs[w.workspace], { bundle = w.bundle, name = w.name })
      if self.opts.showAppIcons and icons[w.bundle] == nil then
        icons[w.bundle] = self:_icon(w.bundle) or false
      end
    end
  end

  local workspaces = {}
  for _, name in ipairs(names) do
    local apps = appsByWs[name] or {}
    workspaces[#workspaces + 1] = { name = name, occupied = #apps > 0, apps = apps }
  end

  return { workspace = ws, workspaces = workspaces, icons = icons }
end

-- Show the webview and hand the data to window.hud[method] in the page.
function obj:_present(method, data, extraTime)
  data.theme = self.opts.theme
  data.duration = self.opts.duration
  data.showAppIcons = self.opts.showAppIcons

  local wv = self.webview
  local count = #(data.workspaces or data.after.workspaces)
  wv:frame(self:_frame(hs.screen.mainScreen(), count))
  wv:show()
  wv:evaluateJavaScript("window.hud && window.hud." .. method .. "(" .. hs.json.encode(data) .. ")")

  -- Hide the window after the exit animation so it never blocks clicks.
  if self.hideTimer then self.hideTimer:stop() end
  self.hideTimer = hs.timer.doAfter(self.opts.duration + 0.6 + (extraTime or 0), function() wv:hide() end)
end

--- AeroHUD:show(workspace, previous)
--- Method
--- Show the HUD for a workspace switch. Called from AeroSpace's callback.
function obj:show(ws, prev)
  if not self.webview then self:start() end
  self:_setFocus(ws, self:_nextSeq())
  self:_query("show", function(names, windows)
    local data = self:_workspaceData(ws, names, windows)
    data.previous = prev
    self:_present("show", data)
  end)
end

--- AeroHUD:moveWindow(workspace)
--- Method
--- Move the focused window to a workspace and animate it on the HUD. Bind it in
--- place of AeroSpace's `move-node-to-workspace` (see docs/INSTALL.md), since
--- AeroSpace has no callback for window moves.
function obj:moveWindow(target)
  if not self.webview then self:start() end
  target = tostring(target)
  local seq = self:_nextSeq()
  -- Each move gets its own slot so a quick workspace switch can't cancel it.
  self:_query("move" .. seq, function(names, windows, focused)
    if not focused or focused.workspace == target then return end
    self:_setFocus(focused.workspace, seq)

    self.moveTasks = self.moveTasks or {}
    self.moveTasks[seq] = hs.task.new(self.aerospacePath, function(code)
      self.moveTasks[seq] = nil
      if code ~= 0 then return end

      local after, hasTarget = {}, false
      for _, w in ipairs(windows) do
        after[#after + 1] = w.id == focused.id
          and { id = w.id, workspace = target, bundle = w.bundle, name = w.name } or w
      end
      for _, name in ipairs(names) do hasTarget = hasTarget or name == target end
      local afterNames = names
      if not hasTarget then
        afterNames = { table.unpack(names) }
        afterNames[#afterNames + 1] = target
      end

      -- If you switched workspaces since pressing the key, keep the highlight
      -- on the workspace you are on now.
      local current = self.focus.ws
      local data = {
        before = self:_workspaceData(current, afterNames, windows),
        after = self:_workspaceData(current, afterNames, after),
        moved = { bundle = focused.bundle, from = focused.workspace, to = target },
      }
      self:_present("move", data, 0.7)
    end, { "move-node-to-workspace", "--window-id", focused.id, target })
    self.moveTasks[seq]:start()
  end)
end

return obj
