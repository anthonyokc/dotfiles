#!/bin/bash
set -euo pipefail

# Get the current status count
current_status_count=$(tmux show -g status | grep -oE '[0-9]+$')

# Convert the current_status_count to an integer
current_status_count=$((current_status_count))

if [ "$current_status_count" -lt 2 ]; then
  echo "not enough"
else
  echo "enough"
fi

