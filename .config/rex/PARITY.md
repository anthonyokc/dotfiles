# Rex parity with tmux and Ghostty

This configuration targets Rex Beta 0.1.0 (1347) on macOS.
It leaves the original tmux configuration, Ghostty configuration, and repository scripts unchanged.

## Configured equivalents

All keys in this table follow Ctrl+S unless the table states otherwise.
Ctrl+A passes through to tmux without starting a Rex sequence.

| Keys | Rex behavior |
| --- | --- |
| Shift+R | Reload the Rex configuration. |
| r | Rename the tab. |
| : | Open the command palette instead of the tmux command prompt. |
| Shift+S | Open the selector for sessions. |
| w | Create a tab. |
| Shift+N / p | Select the next / previous tab. |
| 1 through 9 | Select a tab by its current position. |
| Ctrl+W / double quote | Open the command palette, not a dedicated list of tabs. |
| v / vertical bar | Split to the right. |
| s | Split down. |
| j / k / l / Left | Focus down / up / right / left. |
| z | Toggle zoom for the focused pane. |
| c | Close the focused pane. |
| x | Move the pane down, not an exact cyclic tmux swap. |
| comma / period / minus / equals | Resize left / right / down / up by 10 percent of the split. |
| Shift+E, then h/j/k/l | Enter repeatable resize mode. Escape or Enter exits the mode. |
| a | Send Ctrl+A to the terminal. |
| Ctrl+S | Send Ctrl+S to the terminal. |
| left bracket | Open Find, not vi copy mode. |
| f | Search Rex sessions and local directories, including repositories and worktrees under `~/code`. |
| Shift+F | Search Rex sessions. |
| h | Run the existing script that opens a repository in a browser. |
| Shift+H | Run the existing clone script with a Rex-specific replacement for `sesh connect`. |
| o | Run the existing creation script with the same Rex-specific replacement. |
| m | Run the existing script for commit messages in a floating terminal. |
| g / Shift+G | Open LazyGit / GitUI in the current directory. |
| i / Shift+O | Open GitHub Dash in the current directory / home directory. |
| q | Open OpenCode in the current directory. |
| Shift+Q | Open the existing Codex command, with LazyGit below it inside a Git worktree. |
| Shift+D | Open Neovim with DBUI in the current directory. |
| t | Open a floating shell in the current directory. |
| u | Open `top` in a floating terminal. |
| asterisk | List connected Rex clients instead of synchronizing panes. |
| Shift+X | Explode the focused pane with `explode/explode.lua`: `explode/boomfx` lifts an exact copy of the pane over the screen, shakes it and blows it apart in 3D with a fireball, sparks and smoke. Needs Screen Recording and Accessibility for Rex; without them, or over SSH, an ASCII explosion runs inside Rex instead. The pane is detached, and its program keeps running. |
| Shift+U | Restore the pane that the newest explosion detached, beside the focused pane. |
| Alt+X, without prefix | Close the tab. |
| Alt+Q, without prefix | Close the session. |

Rex numbers tabs from one in their current order.
Rex retains its standard Cmd shortcuts alongside these bindings.
Each tool launcher explicitly asks the app to select the new tab by its returned window ID.
The project picker reuses an exact session label or creates a session for the selected directory.
If several sessions use the same project label, the picker reports an error instead of choosing one.
The clone and creation scripts retain their existing prompts, dependencies, and behavior apart from connecting to Rex.
The configuration does not run either repository operation during setup.

## Appearance

`Anthony Ghostty Mocha.conf` matches Ghostty's effective foreground, background, cursor, selection, and 16 palette colors.
It includes the custom `#1b2b36` background and white palette entry 7.
The imported theme applies through Rex's `client.theme.import` action.
Rex stores font settings separately from `init.lua`.
The Ghostty font is BerkeleyMono Nerd Font at size 16.
Rex now uses BerkeleyMono Nerd Font at size 14, with the Dark color scheme selected.

## Remaining differences

- Rex's documented actions do not expose a global quick terminal equivalent to Ghostty's Cmd+grave shortcut.
- This configuration does not reproduce opacity 0.95, blur 60, asymmetric padding, or automatic non-native fullscreen.
- The configuration does not implement tmux vi copy mode or `v`/`y` selection commands.
- The configuration does not implement synchronized input, server locking, or tmux detach commands.
- The configuration does not implement switching to the last session or the last tab with Ctrl+A Ctrl+A.
- Resize steps use percentages, not tmux's 20 columns and 7 rows.
- The project picker does not reproduce sesh's filter modes or its shortcut for deleting sessions.
- The floating shell creates a new terminal rather than toggling one persistent Floax terminal.
- The configuration does not reproduce the Catppuccin status bar, its clock, or its automatic layout changes.
- The floating `top` terminal replaces access to CPU and memory information, not its persistent status display.
- Rex keeps sessions on its server, but setup does not establish restoration after a server restart or reboot.
- Setup does not establish parity with tmux-resurrect, tmux-continuum, tmux-yank, or tmux-sensible.
- Setup does not verify Yazi images, sixel, clipboard escape sequences, or application-driven cursor shapes.

## Verification

`rex config check` accepts 60 bindings, one mode, and 17 custom actions.
`rex keymap` reports no diagnostics when supplied with the installed app's declared actions.
A temporary Rex session verified that the floating-shell action creates one centered floating terminal.
The verification removed only that temporary session.
Checks for the project picker cover session reuse, session creation, duplicate labels, missing directories, bare checkouts, and cancellation.
The clone and creation workflows remain unverified because they can modify local and GitHub repositories.
The Rex Settings interface confirms font size 14 and the selected Dark color scheme.
The macOS preference `Workspace.terminalFontPointSize` also records 14.
Checks with a simulated Rex API verify that all seven tool launchers select the tab they create.
If creating a tab fails, the launchers do not request a tab change.
