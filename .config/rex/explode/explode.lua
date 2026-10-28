-- explode.lua: shake a Rex pane, play a boom, and blow it into debris.
--
--   rex do -s SESSION ~/.config/rex/explode/explode.lua block=BLOCK_ID
--
-- Arguments:
--   block=ID      The pane to explode. Default: the focused pane of the active tab.
--   kill=true     Close the pane and end its program. Default: detach it, so the
--                 program keeps running off screen and restore= can bring it back.
--   sound=false   Skip the sound.
--   self=true     Allow exploding the pane that runs this script.
--   native=false  Skip the 3D effect (boomfx) and use the ASCII explosion.
--   live=false    Shake a still copy of the pane instead of the live pane.
--   trace=true    Print which tab holds the floating panes at each phase.
--   restore=ID    Put a detached pane back beside the focused pane. No explosion.
--                 restore=last restores the pane that the newest detach explosion removed.

local TERMINAL = "com.superlogical.terminal"
local FLAVOR = TERMINAL .. ".shell"
local HOME = os.getenv("HOME") or ""
local DIR = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):match("(.*)/")
if not DIR or DIR == "" then DIR = HOME .. "/.config/rex/explode" end

local args = rex.args or {}
local FPS = 60
local GRID_COLS, GRID_ROWS = 3, 3
local GRAVITY = 1.5 -- window heights per second squared

math.randomseed(os.time())

local function must(result, err)
  if result == nil then error(err or "Rex request failed", 0) end
  return result
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Keep [x, y, w, h] inside the window, as float_block and resize_layer require.
local function fit(x, y, w, h)
  w, h = clamp(w, 0.02, 1), clamp(h, 0.02, 1)
  return { clamp(x, 0, 1 - w), clamp(y, 0, 1 - h), w, h }
end

local function active_window(view)
  for _, w in ipairs(view.windows or {}) do
    if w.window_id == view.active_window_id then return w end
  end
end

-- Returns the window, the layer and the [x, y, w, h] rect that hold block_id.
local function locate(view, block_id)
  local function walk(node)
    if not node then return nil end
    if node.block_id == block_id then return node.rect end
    if node.split then return walk(node.split.before) or walk(node.split.after) end
  end
  for _, w in ipairs(view.windows or {}) do
    for _, layer in ipairs(w.layers or {}) do
      if layer.kind == "tiled" then
        local rect = walk(layer.layout)
        if rect then return w, layer, rect end
      else
        for _, b in ipairs(layer.blocks or {}) do
          if b.block_id == block_id then return w, layer, layer.bounds end
        end
      end
    end
  end
end

local view = must(rex.session.view{})
local LAST = DIR .. "/last"

-- LAST holds "BLOCK_ID WINDOW_ID": the newest detached pane and the tab it came from.
local restore_window = nil
if args.restore == "last" then
  local f = must(io.open(LAST, "r"), "no exploded pane to restore")
  local line = f:read("*l") or ""
  f:close()
  args.restore, restore_window = line:match("^(%S+)%s*(%S*)")
  must(args.restore, "no exploded pane to restore")
end

if args.restore then
  -- Restore into the pane's own tab if it still exists. Otherwise use the active tab.
  local w = nil
  for _, x in ipairs(view.windows or {}) do
    if x.window_id == restore_window then w = x end
  end
  w = must(w or active_window(view), "no active tab")
  local anchor = must(w.focused_block_id, "the tab has no pane to restore beside")
  must(rex.session.move_block{
    block_id = args.restore, anchor_block_id = anchor,
    direction = "horizontal", side = "after", ratio = 0.5,
  })
  rex.session.focus_block{ block_id = args.restore }
  return { restored = args.restore }
end

local target = args.block
if not target then
  target = must(active_window(view), "no active tab").focused_block_id
end
must(target, "no pane to explode: pass block=ID")
if target == rex.block_id and args.self ~= true then
  error("refusing to explode the pane that runs this script; pass self=true", 0)
end

local window, layer, rect = locate(view, target)
must(layer, "pane not found in this session: " .. target)
if layer.kind ~= "tiled" and #(layer.blocks or {}) > 1 then
  error("the pane shares a floating layer with other panes; explode is not supported there", 0)
end
local x0, y0, w0, h0 = rect[1], rect[2], rect[3], rect[4]

-- Read the screen before anything moves. Keep the last screenful of lines.
local text = rex.block.call(TERMINAL, "format", { block_id = target, format = "text" })
local size = rex.block.call(TERMINAL, "size", { block_id = target }) or {}
local cols, rows = size.columns or 80, size.rows or 24
local lines = {}
for line in ((text and text.content or "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
while #lines > rows do table.remove(lines, 1) end

local function chars(s)
  local t = {}
  for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = c end
  return t
end

-- Split the screen into a grid. Each piece becomes a file that a debris pane prints.
-- Each piece is a solid chunk: a hot background with light text, so it reads
-- against the tab behind it.
local HEAT = { { 88, 223 }, { 124, 229 }, { 130, 230 }, { 166, 231 }, { 202, 231 } }
local pieces = {}
for gy = 1, GRID_ROWS do
  for gx = 1, GRID_COLS do
    local c0, c1 = math.floor(cols * (gx - 1) / GRID_COLS) + 1, math.floor(cols * gx / GRID_COLS)
    local r0, r1 = math.floor(rows * (gy - 1) / GRID_ROWS) + 1, math.floor(rows * gy / GRID_ROWS)
    local out, blank = {}, true
    for r = r0, r1 do
      local cs = chars(lines[r] or "")
      local seg = table.concat(cs, "", c0, math.min(c1, #cs))
      if seg:find("%S") then blank = false end
      out[#out + 1] = seg
    end
    if blank then
      for i = 1, #out do out[i] = (" "):rep(math.random(0, 6)) .. ({ ".", "'", ",", "*", "" })[math.random(5)] end
    end
    local path = os.tmpname()
    local f = must(io.open(path, "w"))
    local heat = HEAT[math.random(#HEAT)]
    local bg, fg = heat[1], heat[2]
    -- Clearing with the background set fills the pane; \27[K fills the rest of each line.
    f:write("\27[?25l\27[48;5;" .. bg .. ";38;5;" .. fg .. ";1m\27[2J\27[H"
      .. table.concat(out, "\27[K\r\n") .. "\27[K")
    f:close()
    pieces[#pieces + 1] = {
      path = path,
      x = x0 + w0 * (gx - 1) / GRID_COLS, y = y0 + h0 * (gy - 1) / GRID_ROWS,
      w = w0 / GRID_COLS, h = h0 / GRID_ROWS,
    }
  end
end

-- This script is a Rex client, so the server gives it the blocks it creates
-- and sizes them for it (80x24). Disowning passes each block to the app,
-- which sizes the terminal to the pane on screen.
-- new_layer without window_id uses the session's active tab, which can differ
-- from the tab the app shows. Name the exploded pane's tab instead.
local function shell_layer(bounds, command)
  local made = rex.session.new_layer{
    window_id = window.window_id, bounds = bounds, focus = false,
    layout = rex.layout.block{ flavor = FLAVOR, options = { command = command, shell = "none" } },
  }
  if made then rex.session.disown_block{ block_ids = made.block_ids } end
  return made
end

-- Close the pane, or detach it and remember it for restore=last.
local function remove_target()
  if args.kill == true then
    must(rex.call("block.close", { session_id = rex.session_id, block_id = target }))
  else
    must(rex.session.detach_block{ block_id = target })
    local f = io.open(LAST, "w")
    if f then
      f:write(target, " ", window.window_id, "\n")
      f:close()
    end
  end
end

local function result()
  return {
    exploded = target,
    mode = args.kill == true and "killed" or "detached",
    restore = args.kill == true and nil
      or ("rex do -s " .. rex.session_id .. " " .. DIR .. "/explode.lua restore=" .. target),
  }
end

-- Native effect: boomfx (a small macOS app) captures the pane, covers it with
-- an exact copy above every window, and blows the copy apart in 3D. It needs
-- Screen Recording permission and the pane's tab on screen. Without them it
-- exits, and the ASCII explosion below runs instead.
local BOOMFX = DIR .. "/boomfx/boomfx"

local function app_pid()
  local list = rex.call("client.list", {}) or {}
  for _, c in ipairs(list.clients or {}) do
    if c.info and c.info.kind == "app" and c.principal then
      for _, id in ipairs(c.session_ids or {}) do
        if id == rex.session_id then return c.principal.pid end
      end
    end
  end
end

local function start_native()
  local function no(why)
    if args.trace == true then print("native: " .. why) end
    return false
  end
  if args.native == false then return no("native=false") end
  local f = io.open(BOOMFX, "r")
  if not f then return no("no " .. BOOMFX) end
  f:close()
  if window.window_id ~= view.active_window_id then return no("the pane's tab isn't the active tab") end
  local pid = app_pid()
  if not pid then return no("no Rex app attached to this session") end
  local ready = os.tmpname()
  os.remove(ready)
  -- Live mode: boomfx shows the pane live while it shakes, and writes `boom`
  -- just before the boom. The pane stays in place until then.
  local boom = nil
  if args.live ~= false then
    boom = os.tmpname()
    os.remove(boom)
  end
  -- boomfx's own messages (why it gave up, frame stats) go to explode.log.
  local cmd = { "/bin/sh", "-c", 'exec "$@" 2>>"' .. DIR .. '/explode.log"', "boomfx",
    BOOMFX, "--stats", "--rect", string.format("%.6f,%.6f,%.6f,%.6f", x0, y0, w0, h0),
    "--ready", ready, "--pid", tostring(pid) }
  if boom then
    cmd[#cmd + 1] = "--boom"
    cmd[#cmd + 1] = boom
  end
  if args.sound ~= false then
    cmd[#cmd + 1] = "--sound"
    cmd[#cmd + 1] = DIR .. "/boom.m4a"
  end
  rex.exec.start(cmd, { detach = true })
  -- boomfx gives up after 1.8 s, so 2 s of waiting can't race it.
  for _ = 1, 40 do
    rex.sleep(0.05)
    local r = io.open(ready, "r")
    if r then
      r:close()
      os.remove(ready)
      return true, boom
    end
  end
  return no("boomfx wasn't ready in 2 s")
end

local native, boom = start_native()
if native then
  for _, piece in ipairs(pieces) do os.remove(piece.path) end
  if boom then
    -- The copy covers the pane and shows it live while it shakes. Take the
    -- real pane away when boomfx says the boom is coming (about 1 s). If
    -- boomfx dies first, take it away anyway after 3 s.
    for _ = 1, 150 do
      local b = io.open(boom, "r")
      if b then
        b:close()
        break
      end
      rex.sleep(0.02)
    end
    os.remove(boom)
  end
  -- Without live mode the copy is still: take the real pane away under it at
  -- once, and its neighbours take the space while the copy lifts off.
  remove_target()
  return result()
end

local created = {} -- layer ids to close at the end
local placeholder = nil -- the blank pane that holds the exploded pane's place in the tiling
-- A tiled pane gets its own floating layer in step 1. A floating pane already has one.
local victim_layer = nil
if layer.kind ~= "tiled" then victim_layer = layer.layer_id end

-- Debug trace: prints which tab holds each floating layer at each phase.
local function trace(phase)
  if args.trace ~= true then return end
  local v = rex.session.view{} or {}
  local parts = {}
  for _, w in ipairs(v.windows or {}) do
    local n = 0
    for _, l in ipairs(w.layers or {}) do if l.kind ~= "tiled" then n = n + 1 end end
    parts[#parts + 1] = w.window_id:sub(-6) .. (w.window_id == v.active_window_id and "*" or "") .. "=" .. n
  end
  print(os.date("%H:%M:%S") .. " " .. phase .. " session=" .. tostring(rex.session_id):sub(-6) .. " " .. table.concat(parts, " "))
end

local ok, err = pcall(function()
  -- 1. Lift the pane out of the tiling and shake it harder and harder.
  -- A blank pane takes its place first. Without it the neighbors grow into the
  -- gap at once, and the shaking pane is lost against them.
  if not victim_layer then
    local hole = must(shell_layer(fit(x0, y0, w0, h0), { "/bin/sleep", "60" }))
    placeholder = hole.block_ids[1]
    must(rex.session.swap_blocks{ block_id = target, other_block_id = placeholder })
    victim_layer = hole.layer_id
  end
  -- The pane shrinks to 90% of its slot once, then only moves. A pane that
  -- fills its slot has no room to move: the window edge clamps it. Changing
  -- the size every frame would also re-wrap its text on every frame.
  local w, h = w0 * 0.9, h0 * 0.9
  local bx, by = x0 + (w0 - w) / 2, y0 + (h0 - h) / 2
  local shake = math.floor(FPS * 0.8)
  for i = 1, shake do
    local k = 0.3 + 0.7 * i / shake
    rex.session.resize_layer{
      layer_id = victim_layer,
      bounds = fit(bx + (math.random() * 2 - 1) * (w0 - w) / 2 * k,
        by + (math.random() * 2 - 1) * (h0 - h) / 2 * k, w, h),
    }
    rex.sleep(1 / FPS)
  end

  trace("shaken")
  -- 2. Boom: sound, fireball, and the pane disappears.
  if args.sound ~= false then
    local sound = DIR .. "/boom.m4a"
    local f = io.open(sound, "r")
    if f then
      f:close()
      rex.exec.start({ "/usr/bin/afplay", sound }, { detach = true })
    end
  end
  local fw, fh = math.max(w0, 0.3), math.max(h0, 0.35)
  local fire = shell_layer(fit(x0 + w0 / 2 - fw / 2, y0 + h0 / 2 - fh / 2, fw, fh),
    { "/usr/bin/python3", DIR .. "/fireball.py", "1.4" })
  if fire then created[#created + 1] = fire.layer_id end

  remove_target()
  victim_layer = nil

  -- 3. Debris: each piece flies away from the center, falls, and bounces.
  local cx, cy = x0 + w0 / 2, y0 + h0 / 2
  for _, p in ipairs(pieces) do
    local dx, dy = p.x + p.w / 2 - cx, p.y + p.h / 2 - cy
    p.vx = dx * 2.5 + (math.random() - 0.5) * 0.5
    p.vy = dy * 2 - 0.5 - math.random() * 0.4
    local made = shell_layer(fit(p.x, p.y, p.w, p.h),
      -- Wait for the app to size the terminal before printing the piece.
      { "/bin/sh", "-c", 'sleep 0.15; cat "$1"; rm -f "$1"; exec sleep 30', "sh", p.path })
    if made then
      p.layer = made.layer_id
      created[#created + 1] = made.layer_id
    end
  end

  trace("debris")
  local frames, dt = math.floor(FPS * 2.0), 1 / FPS
  for i = 1, frames do
    local shrink = clamp((frames - i) / (FPS * 0.5), 0.25, 1)
    for _, p in ipairs(pieces) do
      if p.layer then
        p.vy = p.vy + GRAVITY * dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        local w, h = p.w * shrink, p.h * shrink
        if p.y + h > 1 then p.y, p.vy, p.vx = 1 - h, -p.vy * 0.35, p.vx * 0.7 end
        if p.y < 0 then p.y, p.vy = 0, math.abs(p.vy) * 0.5 end
        if p.x < 0 or p.x + w > 1 then p.vx = -p.vx * 0.6 end
        local b = fit(p.x, p.y, w, h)
        p.x, p.y = b[1], b[2]
        rex.session.resize_layer{ layer_id = p.layer, bounds = b }
      end
    end
    rex.sleep(dt)
  end
end)

-- 4. Clean up every pane this script made, even after an error.
for _, id in ipairs(created) do pcall(rex.session.close_layer, { layer_id = id }) end
if placeholder then
  -- After an error before the boom, put the pane back in its place in the tiling.
  if not ok and victim_layer then
    pcall(rex.session.swap_blocks, { block_id = target, other_block_id = placeholder })
  end
  pcall(rex.call, "block.close", { session_id = rex.session_id, block_id = placeholder })
end
for _, p in ipairs(pieces) do os.remove(p.path) end
-- If the explosion failed before the pane was removed, the pane stays visible as a floating pane.
if not ok then error(err, 0) end

return result()
