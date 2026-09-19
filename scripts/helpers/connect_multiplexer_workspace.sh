#!/usr/bin/env bash

# Source this file, then call:
# connect_multiplexer_workspace PATH [LABEL] [path|label]
connect_multiplexer_workspace() {
  local workspace_path="$1"
  local label="${2:-}"
  local match_mode="${3:-path}"

  if [[ "${MULTIPLEXER:-}" != "herdr" && -z "${HERDR_SOCKET_PATH:-}" ]]; then
    sesh connect "$workspace_path"
    return
  fi

  if ! command -v herdr >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf 'Herdr workspace connection requires herdr and jq.\n' >&2
    return 1
  fi

  local canonical_path
  canonical_path="$(realpath -m "$workspace_path")"

  if [[ -z "$label" ]]; then
    if [[ "$canonical_path" == "$HOME/code/"* ]]; then
      local relative owner repo remainder
      relative="${canonical_path#"$HOME/code/"}"
      IFS=/ read -r owner repo remainder <<<"$relative"
      label="$repo"
      [[ -n "$remainder" ]] && label="$repo/$remainder"
    else
      label="$(basename "$canonical_path")"
    fi
  fi

  local workspace_id=""
  if [[ "$match_mode" == "label" ]]; then
    workspace_id="$(
      herdr workspace list 2>/dev/null |
        jq -r --arg label "$label" \
          '.result.workspaces[] | select(.label == $label) | .workspace_id' |
        head -n 1
    )"
  else
    workspace_id="$(
      herdr pane list 2>/dev/null |
        jq -r --arg path "$canonical_path" \
          '.result.panes[] | select(.cwd == $path) | .workspace_id' |
        head -n 1
    )"
  fi

  if [[ -n "$workspace_id" ]]; then
    herdr workspace focus "$workspace_id" >/dev/null
    return
  fi

  local response pane_id startup_command=""
  response="$(herdr workspace create --cwd "$canonical_path" --label "$label" --focus)"
  pane_id="$(jq -r '.result.root_pane.pane_id' <<<"$response")"

  case "$label" in
    "Server 🕋") startup_command='exec ssh -A -tt server' ;;
    "Laptop 💻") startup_command='exec ssh -A -tt laptop' ;;
    "Windows 🪟") startup_command='exec /mnt/c/Users/AnthonyFlores/AppData/Local/Programs/nu/bin/nu.exe -e "cd ~"' ;;
    "Configs ⚙️") startup_command='exec bash /home/anthony/scripts/sesh_startup_command_configs' ;;
    "Downloads 📥") startup_command='lsd -la' ;;
  esac

  if [[ -n "$startup_command" ]]; then
    herdr pane run "$pane_id" "$startup_command" >/dev/null
  fi
}
