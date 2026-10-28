local home = assert(os.getenv("HOME"), "HOME is missing")
local terminal = "com.superlogical.terminal"
local flavor = terminal .. ".shell"
local prefix = "ctrl+s>"
local host = require("host")

if host.macos then
  require("rex-image-paste").setup()
  rex.bind("cmd+shift+v", "image_paste")
end

local function checked(result, err)
  if not result then error(err or "Rex request failed") end
  return result
end

local function cwd(ctx)
  local api = host.api(ctx)
  local process = checked(api.block.call(terminal, "process", { block_id = ctx.block_id }))
  if process.foreground and process.foreground.cwd then return process.foreground.cwd end
  local result = checked(api.block.call(terminal, "pwd", { block_id = ctx.block_id }))
  if result.pwd and result.pwd:sub(1, 1) == "/" then return result.pwd end
  if result.pwd and result.pwd:match("^file://") then
    local path = result.pwd:match("^file://[^/]*(/.*)$")
    if path then
      return (path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
    end
  end
  return process.child and process.child.cwd or (not ctx.server and home or nil)
end

local function shell(ctx, command)
  return rex.layout.block{
    flavor = flavor,
    options = {
      cwd = cwd(ctx),
      command = command and { host.shell, "-lic", command } or nil,
      shell = command and "none" or nil,
    },
  }
end

local function action(name, title, key, run)
  rex.action{ name = name, title = title, category = "Tmux parity", run = run }
  if key then rex.bind(prefix .. key, name) end
end

local function popup(name, title, key, command, width)
  action(name, title, key, function(ctx)
    checked(host.session(ctx, "new_layer", {
      bounds = { (1 - width) / 2, 0.1, width, 0.8 },
      layout = shell(ctx, command),
      focus = true,
    }))
  end)
end

local function open_tool_window(ctx, title, layout)
  local window = checked(host.session(ctx, "new_window", { window_label = title, layout = layout }))
  rex.client.queue("session.select", {
    session_id = ctx.session_id,
    window_id = window.window_id,
  })
end

local function tool(name, title, key, command)
  action(name, title, key, function(ctx)
    open_tool_window(ctx, title, shell(ctx, command))
  end)
end

-- Ctrl+S leaves Ctrl+A available to tmux and keeps Rex's Cmd shortcuts.
local keys = {
  { "shift+r", "client.config.reload" },
  { "r", "client.tab.rename" },
  { "shift+;", "client.palette.toggle" },
  { "shift+s", "session.switch" },
  { "w", "client.tab.new" },
  { "shift+n", "client.tab.next" },
  { "p", "client.tab.previous" },
  { "ctrl+w", "client.palette.toggle" },
  { "shift+'", "client.palette.toggle" },
  { "v", "pane.split", { direction = "right" } },
  { "shift+\\", "pane.split", { direction = "right" } },
  { "s", "pane.split", { direction = "down" } },
  { "j", "pane.focus", { direction = "down" } },
  { "k", "pane.focus", { direction = "up" } },
  { "l", "pane.focus", { direction = "right" } },
  { "left", "pane.focus", { direction = "left" } },
  { "z", "pane.zoom" },
  { "c", "pane.close" },
  { "x", "pane.move", { direction = "down" } },
  { ",", "pane.resize", { direction = "left", amount = 10 } },
  { ".", "pane.resize", { direction = "right", amount = 10 } },
  { "-", "pane.resize", { direction = "down", amount = 10 } },
  { "=", "pane.resize", { direction = "up", amount = 10 } },
  { "a", "pane.send_key", { key = "ctrl+a" } },
  { "ctrl+s", "pane.send_key", { key = "ctrl+s" } },
  { "[", "client.find.open" },
}
for _, key in ipairs(keys) do
  rex.bind(prefix .. key[1], key[2], key[3])
end
for index = 1, 9 do
  rex.bind(prefix .. index, "client.tab.goto", { index = index })
end
rex.bind("alt+x", "client.tab.close")
rex.bind("alt+q", "session.close")

-- Resize mode permits repeated presses without another prefix. Escape exits.
rex.mode("resize", { exclusive = true })
rex.bind(prefix .. "shift+e", "client.mode.enter", { name = "resize" })
for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("resize/" .. key, "pane.resize", { direction = direction, amount = 10 })
end
rex.bind("resize/escape", "client.mode.exit_all")
rex.bind("resize/enter", "client.mode.exit_all")

tool("lazygit", "LazyGit", "g", "lazygit")
tool("gitui", "GitUI", "shift+g", "gitui")
tool("github_dash", "GitHub Dash", "i", "gh dash")
tool("github_dash_home", "GitHub Dash (home)", "shift+o", 'cd "$HOME" && gh dash')
tool("opencode", "OpenCode", "q", "opencode")
tool("dbui", "DBUI", "shift+d", "nvim -c DBUI")

action("codex_git", "Codex and LazyGit", "shift+q", function(ctx)
  local dir = cwd(ctx)
  local git = not ctx.server and checked(rex.exec({ "git", "rev-parse", "--is-inside-work-tree" }, { cwd = dir }))
  local layout = shell(ctx, "codex -m gpt-5.1-codex-max")
  if (git and git.ok) or ctx.server then layout = rex.layout.vertical(0.7, layout, shell(ctx, "lazygit")) end
  open_tool_window(ctx, "Codex", layout)
end)

local helper = 'python3 "$HOME/.config/rex/projects.py"'
-- The client ID prevents a popup from switching another connected app.
local function project_popup(name, title, key, mode)
  action(name, title, key, function(ctx)
    local command = "export REX_CLIENT=" .. string.format("%q", ctx.client_id)
      .. "; " .. helper .. " " .. mode
    checked(host.session(ctx, "new_layer", {
      bounds = { 0.1, 0.1, 0.8, 0.8 }, layout = shell(ctx, command), focus = true,
    }))
  end)
end
project_popup("projects", "Find Project or Rex Session", "f", "pick")
project_popup("sessions", "Find Rex Session", "shift+f", "sessions")
project_popup("clone_project", "Clone Repository and Open Rex Session", "shift+h", "clone")
project_popup("create_project", "Create Repository and Open Rex Session", "o", "create")
popup("repo_browser", "Find Repository in Browser", "h",
  host.profile .. '"$HOME/scripts/find_and_open_repo_in_browser"', 0.6)
popup("commit_message", "Create Conventional Commit Message", "m",
  host.profile .. '"$HOME/scripts/create_conventional_commit_ai_message"', 0.5)
popup("scratch", "Floating Shell", "t", nil, 0.8)
popup("system_status", "CPU and Memory", "u", host.top, 0.8)
popup("clients", "List Rex Clients", "shift+8", "rex client list; read -k 1 '?Press any key to close'", 0.8)

-- Config Lua cannot sleep, so the animation runs as a detached `rex do` script.
local rex_cli = host.rex
local explode = home .. "/.config/rex/explode/explode.lua"
local function explode_action(name, title, key, arg)
  action(name, title, key, function(ctx)
    if ctx.server then error("Run the explosion action from the target server's config; remote effects are not supported") end
    -- explode.log keeps every run's output and errors, each under a dated
    -- line, with a trace of why the 3D effect was skipped, when it was.
    checked(rex.exec.start({ "/bin/sh", "-c", '{ echo "== $(date "+%H:%M:%S") $3"; exec "$0" do -s "$1" "$2" "$3" trace=true; } >>"$4" 2>&1',
      rex_cli, ctx.session_id, explode, arg(ctx), home .. "/.config/rex/explode/explode.log" }, { detach = true }))
  end)
end
explode_action("explode_pane", "Explode Pane", "shift+x", function(ctx) return "block=" .. ctx.block_id end)
explode_action("restore_exploded_pane", "Restore Exploded Pane", "shift+u", function() return "restore=last" end)

action("ghostty_theme", "Import Anthony's Ghostty Theme", nil, function()
  rex.client.queue("client.theme.import", { path = home .. "/.config/rex/Anthony Ghostty Mocha.conf" })
end)

-- Added by `rexdiff setup`. An error in rexdiff does not stop the rest of this file.
do
  local ok, err = pcall(function()
    require("rexdiff").setup{
      bin = "rexdiff",
      key = "ctrl+alt+cmd+d",
    }
  end)
  if not ok then rex.log("error", "rexdiff: " .. tostring(err)) end
end
