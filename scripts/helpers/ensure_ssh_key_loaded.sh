#!/usr/bin/env bash

source "$HOME/scripts/helpers/run_with_exit_prompt.sh"

ensure_ssh_key_loaded() {
  local private_key_path="${1:-$HOME/.ssh/github_ed25519}"
  local add_prompt="${2:-Adding SSH key to agent, enter passphrase 🔒}"
  local success_message="${3:-🎉 Success Added SSH key to agent!}"

  if [[ ! -f "$private_key_path" ]]; then
    printf '❌  SSH key not found: %s\n' "$private_key_path"
    return 1
  fi

  local public_key_path="${private_key_path}.pub"
  if [[ -f "$public_key_path" ]]; then
    local public_key
    public_key="$(<"$public_key_path")"
    if ssh-add -L 2>/dev/null | grep -Fqx "$public_key"; then
      return 0
    fi
  elif ssh-add -l >/dev/null 2>&1; then
    return 0
  fi

  if ! run_with_exit_prompt -i "$add_prompt" ssh-add "$private_key_path"; then
    printf '❌  Could not add SSH key - press any key to exit\n'
    read -n 1 -s -r keypress
    return 1
  fi

  printf '%s\n' "$success_message"
  return 0
}

ensure_github_ssh_key_loaded() {
  ensure_ssh_key_loaded \
    "$HOME/.ssh/github_ed25519" \
    "Adding GitHub SSH key to agent, enter passphrase 🔒" \
    "🎉 Success Added GitHub SSH key to agent!"
}

ensure_git_signing_ssh_key_loaded() {
  local signing_key="${1:-}"
  local key_to_add="$HOME/.ssh/github_ed25519"

  if [[ -n "$signing_key" ]]; then
    if [[ "$signing_key" == key::* ]]; then
      local embedded_public_key="${signing_key#key::}"
      if ssh-add -L 2>/dev/null | grep -Fqx "$embedded_public_key"; then
        return 0
      fi
    elif [[ "$signing_key" == *.pub ]]; then
      key_to_add="${signing_key%.pub}"
    else
      key_to_add="$signing_key"
    fi
  fi

  ensure_ssh_key_loaded \
    "$key_to_add" \
    "Adding SSH signing key to agent, enter passphrase 🔒" \
    "🎉 Success Added SSH signing key to agent!"
}
