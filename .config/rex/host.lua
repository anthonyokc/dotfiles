-- Config runs on its server; pane operations must follow the focused host.
local M = {}
local uname = rex.exec({ "uname", "-s" })
M.macos = uname and uname.ok and uname.stdout:match("Darwin") ~= nil
M.rex = M.macos and ((os.getenv("REX_BIN_DIR") or (os.getenv("HOME")
  .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS")) .. "/rex") or "rex"

function M.api(ctx)
  return ctx.server and rex.server(ctx.server) or rex
end

function M.session(ctx, method, args)
  args = args or {}
  args.session_id = ctx.session_id
  return M.api(ctx).session[method](args)
end

-- Resolve HOME, login environment, and executable names on the target host.
M.shell = "/bin/zsh"
M.top = 'if [ "$(uname -s)" = Darwin ]; then top -o cpu; else top; fi'
M.profile = '[ ! -f "$HOME/.zprofile" ] || source "$HOME/.zprofile"; '
return M
