--- Rex integration for rexdiff.
---
--- Adds a "rexdiff" action that opens rexdiff in a pane beside the focused
--- pane, or closes it when it is already open. Comments written in rexdiff
--- are pasted into the pane it opened beside, such as a Claude Code or Codex session.
---
--- Usage in ~/.config/rex/init.lua:
---
---   require("rexdiff").setup{ key = "ctrl+alt+cmd+d" }
---
--- Then press the key for the local changes, or run the action with a pull
--- request: rex do rexdiff pr=https://github.com/owner/repo/pull/123
local M = {}

--- Labels the rexdiff pane, so the action can find it again.
local LABEL = "rexdiff"

--- Finds the open rexdiff pane in the session, if there is one.
local function find_pane(ctx)
  local view = require("host").session(ctx, "view", {})
  for _, window in ipairs(view.windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.label == LABEL then return block.block_id end
      end
    end
  end
end

--- Gets the working directory of the program in a terminal pane, such as an
--- agent. It falls back to the directory the shell last reported.
local function pane_dir(ctx)
  local block_id = ctx.block_id
  local api = require("host").api(ctx)
  local terminal = "com.superlogical.terminal"

  local process = api.block.call(terminal, "process", { block_id = block_id })
  local program = process and (process.foreground or process.child)
  if program and program.cwd then return program.cwd end

  local reported = api.block.call(terminal, "pwd", { block_id = block_id })
  if reported and reported.pwd then return (reported.pwd:gsub("^file://[^/]*", "")) end

  return not ctx.server and os.getenv("HOME") or nil
end

--- Registers the rexdiff action.
---
--- Options:
---   bin    Path to the rexdiff binary. Rex starts it from a non-interactive
---          shell, so set a full path when the binary is not on that PATH.
---          Defaults to "rexdiff".
---   key    A key that toggles the pane, such as "ctrl+alt+cmd+d".
---   ratio  The share of the width that the focused pane keeps. Defaults to 0.55.
function M.setup(opts)
  opts = opts or {}
  local bin = opts.bin or "rexdiff"
  local ratio = opts.ratio or 0.55

  rex.action{
    name        = "rexdiff",
    title       = "Toggle Diff Review",
    description = "Review the local changes, or a pull request, beside the focused pane.",
    keywords    = "diff review pull request pr",
    args        = { pr = "string?" },
    run         = function(ctx, args)
      local host = require("host")
      local open = find_pane(ctx)
      if open then host.api(ctx).call("block.close", { session_id = ctx.session_id, block_id = open }) end

      -- Without a pull request the action toggles, so a second key press only closes the pane.
      if open and not args.pr then return { closed = open } end

      local executable = bin
      if host.macos and not ctx.server and bin == "rexdiff" then
        local bundled = os.getenv("HOME") .. "/.bun/install/global/node_modules/@segersniels/rexdiff-darwin-arm64/bin/rexdiff"
        local file = io.open(bundled, "r")
        if file then file:close(); executable = bundled end
      end
      local command = { executable }
      if ctx.block_id then
        table.insert(command, "--agent")
        table.insert(command, ctx.block_id)
      end
      if args.pr then table.insert(command, args.pr) end

      local result, err = host.session(ctx, "new_split", {
        anchor_id = ctx.block_id,
        direction = "horizontal",
        side      = "after",
        ratio     = ratio,
        focus     = ctx.origin == "key" or ctx.origin == "palette",
        layout    = { block = {
          flavor  = "com.superlogical.terminal.shell",
          label   = LABEL,
          options = { command = command, cwd = pane_dir(ctx) },
        } },
      })
      if err ~= nil then error(err, 0) end
      return result
    end,
  }

  if opts.key then rex.bind(opts.key, "rexdiff") end
end

return M
