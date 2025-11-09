#!/bin/bash

# Show a waiting message while running a command; allows Esc/ctrl+c to cancel the subprocess.
# Usage: run_with_exit_prompt "Message" <command> [args...]
# The helper pipes command output through a temp file so we can surface it only after success.
# The spinner leans on a long-lived `sleep` so gum keeps animating until we explicitly kill it.
function run_with_exit_prompt() {
  local wait_message="$1"
  shift

  tmpfile=$(mktemp)    # Buffer stdout so we emit it only if the command completes
  "$@" >"$tmpfile" &   # Run the target command in background
  local cmd_pid=$!
  local spinner_pid=""

  # Fire up a gum spinner backed by a "never-ending" sleep so we can kill it once the command finishes.
  gum spin --spinner minidot --title "$wait_message (Press Esc or ctrl+c to exit)" -- sleep 999999 >&2 &
  spinner_pid=$!

  # Poll the process; bail out early if the user presses Esc
  while kill -0 "$cmd_pid" 2>/dev/null; do
    if read -rsn1 -t 0.1 key; then
      if [[ $key == $'\e' ]]; then
        printf "\nExiting...\n" >&2
        kill "$cmd_pid" 2>/dev/null || true
        if [[ -n ${spinner_pid:-} ]]; then
          kill "$spinner_pid" 2>/dev/null || true
        fi
        rm -f "$tmpfile"
        return 130
      fi
    fi
  done

  if [[ -n ${spinner_pid:-} ]]; then
    kill "$spinner_pid" 2>/dev/null || true
    wait "$spinner_pid" 2>/dev/null || true
  fi

  # Emit buffered output on success; ensure we don't swallow non-zero exits
  if wait "$cmd_pid"; then
    cat "$tmpfile"
    rm -f "$tmpfile"
  else
    rm -f "$tmpfile"
    return 1
  fi
}
