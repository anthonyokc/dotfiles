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

  --shell
      Run the command in the current shell (no background). Needed for bash builtins / job control:
      wait, jobs, fg, bg, disown, cd, export, set, trap, etc.
      Note: Esc-to-cancel is disabled in --shell mode; use Ctrl+C.

  -h, --help
      Show this help.

Notes:
  - Default (non-interactive) mode runs the command in the background and buffers stdout to a temp file.
    This allows Esc-to-cancel, but commands that need stdin will not work properly (use -i).
  - If the command is a bash builtin/keyword, run_with_exit_prompt automatically switches to --shell.
    Use --pid for cancellable waiting on a child process.
  - Use "--" to separate the message from the command if you want.
EOF
}

function run_with_exit_prompt() {
	local interactive=0
	local shell_mode=0

	# parse flags
	# # -- separates flags from positional args
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --interactive)
			interactive=1
			shift
			;;
		--shell)
			shell_mode=1
			shift
			;;
		-h | --help)
			run_with_exit_prompt_help
			return 0
			;;
		--)
			shift
			break
			;;
		*) break ;;
		esac
	done

	# ensure we have at least 2 args left: message + command
	local wait_message="$1"
	shift

	# If the command is a bash builtin/keyword, it must run in this shell.
	if [[ $# -gt 0 ]] && [[ $shell_mode -eq 0 ]]; then
		local t
		t=$(type -t -- "$1" 2>/dev/null || true)
		if [[ "$t" == "builtin" || "$t" == "keyword" ]]; then
			shell_mode=1
		fi
	fi

	# same-shell path: foreground (stdin preserved)
	# Ctrl+C to cancel; Esc-to-cancel disabled
	if [[ $shell_mode -eq 1 ]]; then
		local spinner_pid=""
		gum spin --spinner minidot \
			--title "$wait_message (Ctrl+C to cancel)" \
			-- sleep 999999 >&2 &
		spinner_pid=$!

		"$@"
		local rc=$?

		kill "$spinner_pid" 2>/dev/null || true
		wait "$spinner_pid" 2>/dev/null || true
		return $rc
	fi

	# interactive path: foreground (stdin preserved)
	# Ctrl+C to cancel; Esc-to-cancel disabled
	if [[ $interactive -eq 1 ]]; then
		gum spin --spinner minidot \
			--title "$wait_message (Ctrl+C to cancel)" \
			-- "$@"  # Run command in foreground with spinner
		return $? # Return command exit status
	fi

	# Non-interactive path: background (stdin not preserved)
	# Esc-to-cancel enabled
	# Buffer stdout to temp file to avoid interleaving with spinner
	local tmpfile
	tmpfile=$(mktemp)    # safely create unique temp file
	"$@" >"$tmpfile" &   # Run command in background, redirecting stdout to temp file
	local cmd_pid=$!     # Capture command PID
	local spinner_pid="" # Initialize spinner PID variable

	# Start spinner in background redirected to stderr (to avoid mixing with command output)
	gum spin --spinner minidot --title "$wait_message (Press Esc or ctrl+c to exit)" -- sleep 999999 >&2 &
	spinner_pid=$! # Capture spinner PID

	# Loop to check if command is done, and read for Esc keypress to kill command if needed
	while kill -0 "$cmd_pid" 2>/dev/null; do
		# -r: raw mode (no echo), to avoid interpreting backslashes
		# -s: silent (no echo), do not print input to terminal
		# -n1: read 1 character
		# -t 0.1: timeout after 0.1 seconds, so we can loop and check if command is done
		local key=""
		if read -rsn1 -t 0.1 key; then
			if [[ $key == $'\e' ]]; then # Esc key pressed
				printf "\nExiting...\n" >&2
				kill "$cmd_pid" 2>/dev/null || true
				[[ -n ${spinner_pid:-} ]] && kill "$spinner_pid" 2>/dev/null || true
				rm -f "$tmpfile"
				return 130
			fi
		fi
	done

	# Clean up spinner after command completes
	[[ -n ${spinner_pid:-} ]] && kill "$spinner_pid" 2>/dev/null || true
	[[ -n ${spinner_pid:-} ]] && wait "$spinner_pid" 2>/dev/null || true

	# Check command exit status
	if wait "$cmd_pid"; then
		# On success, output buffered stdout
		cat "$tmpfile"
		rm -f "$tmpfile"
	else
		# On failure, clean up and return error
		rm -f "$tmpfile"
		return 1
	fi
}
