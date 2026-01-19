#!/bin/bash

# Display help for run_with_exit_prompt
run_with_exit_prompt_help() {
  cat <<'EOF'
run_with_exit_prompt: show a spinner while running a command, optionally allowing cancel with Esc/ctrl+c.

Usage:
  run_with_exit_prompt [-i|--interactive] "Message" -- <command> [args...]
  run_with_exit_prompt "Message" <command> [args...]
  run_with_exit_prompt -h|--help

Flags:
  -i, --interactive
      Run the command in the foreground so it can read from the TTY (passphrases, prompts, etc.).
      Note: Esc-to-cancel is disabled in interactive mode; use Ctrl+C.

  -h, --help
      Show this help.

Notes:
  - Default (non-interactive) mode runs the command in the background and buffers stdout to a temp file.
    This allows Esc-to-cancel, but commands that need stdin will not work properly (use -i).
  - Use "--" to separate the message from the command if you want.
EOF
}

function run_with_exit_prompt() {
  local interactive=0

  # parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--interactive) interactive=1; shift ;;
      -h|--help) run_with_exit_prompt_help; return 0 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  local wait_message="$1"
  shift

  # interactive path: foreground (stdin preserved)
  if [[ $interactive -eq 1 ]]; then
    gum spin --spinner minidot \
      --title "$wait_message (Ctrl+C to cancel)" \
      -- "$@"
    return $?
  fi

  # (rest of your existing non-interactive implementation stays the same,
  #  but make tmpfile local)
  local tmpfile
  tmpfile=$(mktemp)
  "$@" >"$tmpfile" &
  local cmd_pid=$!
  local spinner_pid=""

  gum spin --spinner minidot --title "$wait_message (Press Esc or ctrl+c to exit)" -- sleep 999999 >&2 &
  spinner_pid=$!

  while kill -0 "$cmd_pid" 2>/dev/null; do
    if read -rsn1 -t 0.1 key; then
      if [[ $key == $'\e' ]]; then
        printf "\nExiting...\n" >&2
        kill "$cmd_pid" 2>/dev/null || true
        [[ -n ${spinner_pid:-} ]] && kill "$spinner_pid" 2>/dev/null || true
        rm -f "$tmpfile"
        return 130
      fi
    fi
  done

  [[ -n ${spinner_pid:-} ]] && kill "$spinner_pid" 2>/dev/null || true
  [[ -n ${spinner_pid:-} ]] && wait "$spinner_pid" 2>/dev/null || true

  if wait "$cmd_pid"; then
    cat "$tmpfile"
    rm -f "$tmpfile"
  else
    rm -f "$tmpfile"
    return 1
  fi
}
