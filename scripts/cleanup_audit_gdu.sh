#!/usr/bin/env bash
set -u

# cleanup-audit-gdu.sh
# Interactive cleanup audit for common Linux/WSL developer caches.
# Uses gdu for fast size checks.
# Defaults to safe-ish cache/trash cleanups. Destructive commands require y/N.

# Dependencies:
# - Required: bash, gdu, trash-cli via TRASH_CMD/TRASH_LIST_CMD/TRASH_EMPTY_CMD,
#   awk, sort, cut, tail, head, find, du, basename, dirname, clear, date, ls, tr,
#   grep.
# - Optional cleanup/audit tools used when present: uv, pip, pip3, bun, npm, pnpm,
#   brew, dpkg-query, tlmgr, nvcc, nix, nix-store, rustup, podman, docker, snap.

TRASH_CMD="${TRASH_CMD:-/home/linuxbrew/.linuxbrew/bin/trash}"
TRASH_BIN_DIR="$(dirname "$TRASH_CMD")"
TRASH_LIST_CMD="${TRASH_LIST_CMD:-$TRASH_BIN_DIR/trash-list}"
TRASH_EMPTY_CMD="${TRASH_EMPTY_CMD:-$TRASH_BIN_DIR/trash-empty}"
TRASHED_ITEMS=0
LAST_ACTION_MOVED_TO_TRASH=0

hr() {
  printf '\n%s\n' "------------------------------------------------------------"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

read_answer() {
  local prompt="$1"
  local var_name="$2"
  local answer

  if [ -r /dev/tty ]; then
    read -r -p "$prompt" answer </dev/tty
  else
    read -r -p "$prompt" answer
  fi

  printf -v "$var_name" '%s' "$answer"
}

require_startup_dependencies() {
  local missing=0

  if ! has_cmd gdu; then
    echo "Error: gdu is required but was not found in PATH." >&2
    missing=1
  fi

  if [ ! -x "$TRASH_CMD" ]; then
    echo "Error: trash move command is required but not executable: $TRASH_CMD" >&2
    echo "Set TRASH_CMD to the trash/trash-put executable if it is installed elsewhere." >&2
    missing=1
  fi

  if [ ! -x "$TRASH_LIST_CMD" ]; then
    echo "Error: trash list command is required but not executable: $TRASH_LIST_CMD" >&2
    echo "Set TRASH_LIST_CMD to the trash-list executable if it is installed elsewhere." >&2
    missing=1
  fi

  if [ ! -x "$TRASH_EMPTY_CMD" ]; then
    echo "Error: trash empty command is required but not executable: $TRASH_EMPTY_CMD" >&2
    echo "Set TRASH_EMPTY_CMD to the trash-empty executable if it is installed elsewhere." >&2
    missing=1
  fi

  [ "$missing" -eq 0 ] || exit 1
}

get_size() {
  # Print human-readable total disk usage for one path.
  # gdu -nps already prints a summarized human-readable size, so no conversion needed.
  local path="$1"

  [ -e "$path" ] || {
    echo "0 B"
    return 0
  }

  gdu -nps "$path" 2>/dev/null | awk '{print $1, $2}'
}

trash_path() {
  local path="$1"

  if "$TRASH_CMD" -- "$path"; then
    TRASHED_ITEMS=$((TRASHED_ITEMS + 1))
    LAST_ACTION_MOVED_TO_TRASH=1
    return 0
  fi

  return 1
}

list_trash() {
  "$TRASH_LIST_CMD"
}

confirm_empty_trash() {
  local estimate="$1"

  hr
  echo "Current trash contents:"
  list_trash || true

  confirm_and_run \
    "Permanently empty trash" \
    "$estimate" \
    "$HOME/.local/share/Trash" \
    "$(printf '%q' "$TRASH_EMPTY_CMD")" \
    "$TRASH_EMPTY_CMD"
}

print_size_row() {
  local label="$1"
  local path="$2"

  [ -e "$path" ] || return 0
  printf '%-48s %12s\n' "$label" "$(get_size "$path")"
}

print_child_size_rows() {
  local dir="$1"
  local p size_k

  for p in "$dir"/*; do
    [ -e "$p" ] || continue
    size_k=$(du -sk -- "$p" 2>/dev/null | awk '{print $1}')
    [ -n "$size_k" ] || size_k=0
    printf '%012d\t%12s  %s\n' "$size_k" "$(get_size "$p")" "$p"
  done | sort -n | cut -f2-
}

nix_wipe_history_then_gc() {
  nix profile wipe-history --older-than 30d && nix-store --gc
}

purge_pip_cache_or_trash() {
  local pip_cmd="$1"
  local cache_dir="$2"

  if "$pip_cmd" cache purge; then
    return 0
  fi

  echo "Moving pip cache directory to trash instead."
  trash_path "$cache_dir"
}

confirm_and_run() {
  local label="$1"
  local estimate="$2"
  local post_path="$3"
  local command_display="$4"
  shift 4

  hr
  echo "$label"
  echo "Estimated reclaimable/current size: ${estimate:-unknown}"
  echo
  echo "Command:"
  echo "  $command_display"
  echo
  read_answer "Run this cleanup? [y/N] " ans

  case "$ans" in
    y|Y|yes|YES)
      echo
      echo "Running..."
      LAST_ACTION_MOVED_TO_TRASH=0
      "$@"
      local status=$?
      if [ "$status" -ne 0 ]; then
        echo "Command exited with status $status"
      fi

      if [ -n "$post_path" ]; then
        echo
        echo "Size afterward:"
        if [ -e "$post_path" ]; then
          printf '%s\t%s\n' "$(du -sh -- "$post_path" 2>/dev/null | awk '{print $1}')" "$post_path"
        elif [ "$LAST_ACTION_MOVED_TO_TRASH" -eq 1 ]; then
          echo "moved to trash; missing at original path"
        else
          echo "missing at original path; command may have removed it or changed its location"
        fi
      fi
      ;;
    *)
      echo "Skipped."
      ;;
  esac
}

show_header() {
  clear
  echo "Cleanup audit for: $HOME"
  echo "Date: $(date)"
  echo
  echo "Size engine: gdu"
  echo "Trash move command: $TRASH_CMD"
  echo "Trash list command: $TRASH_LIST_CMD"
  echo "Trash empty command: $TRASH_EMPTY_CMD"
  echo
  echo "This script asks before every cleanup."
  echo "Cache cleanups may make future installs/downloads slower."
  echo "Trash cleanup is permanent."
}

show_summary() {
  hr
  echo "Current major cleanup candidates"
  echo

  printf '%-48s %12s\n' "Path / source" "Size"
  printf '%-48s %12s\n' "-------------" "----"

  print_size_row "~/.cache/huggingface" "$HOME/.cache/huggingface"
  print_size_row "~/.cache/llama.cpp" "$HOME/.cache/llama.cpp"
  print_size_row "~/.cache/whisper" "$HOME/.cache/whisper"
  print_size_row "~/.cache/uv" "$HOME/.cache/uv"
  print_size_row "~/.cache/pip" "$HOME/.cache/pip"
  print_size_row "~/.bun/install/cache" "$HOME/.bun/install/cache"
  print_size_row "~/.cache/Homebrew" "$HOME/.cache/Homebrew"
  print_size_row "~/.local/share/Trash" "$HOME/.local/share/Trash"
  print_size_row "~/.local/share/containers" "$HOME/.local/share/containers"
  print_size_row "~/.local/share/renv" "$HOME/.local/share/renv"
  print_size_row "~/.npm" "$HOME/.npm"
  print_size_row "~/.cache/pnpm" "$HOME/.cache/pnpm"
  print_size_row "~/.local/share/pnpm/store" "$HOME/.local/share/pnpm/store"
  print_size_row "~/.rustup/toolchains" "$HOME/.rustup/toolchains"
  print_size_row "~/.vscode-server" "$HOME/.vscode-server"
  print_size_row "~/.cursor-server" "$HOME/.cursor-server"
  print_size_row "~/.positron-server" "$HOME/.positron-server"
  print_size_row "~/.windsurf-server" "$HOME/.windsurf-server"
  print_size_row "~/.snap" "$HOME/.snap"
  print_size_row "~/snap" "$HOME/snap"
  print_size_row "~/.venvs" "$HOME/.venvs"
  print_size_row "~/.virtualenvs" "$HOME/.virtualenvs"
  print_size_row "~/py-venv" "$HOME/py-venv"
  print_size_row "/nix" "/nix"
  print_size_row "/var/lib/snapd" "/var/lib/snapd"
  print_size_row "/usr/local/texlive" "/usr/local/texlive"
  print_size_row "/usr/local/cuda-12.5" "/usr/local/cuda-12.5"
  print_size_row "/usr/lib/google-cloud-sdk" "/usr/lib/google-cloud-sdk"
  print_size_row "/usr/lib/rstudio" "/usr/lib/rstudio"
  print_size_row "/usr/share/positron" "/usr/share/positron"

  if has_cmd pnpm; then
    pnpm_store=$(pnpm store path 2>/dev/null || true)
    if [ -n "$pnpm_store" ] && [ -e "$pnpm_store" ]; then
      printf '%-48s %12s\n' "pnpm store: ${pnpm_store/#$HOME/~}" "$(get_size "$pnpm_store")"
    fi
  fi

  if has_cmd npm; then
    npm_cache=$(npm config get cache 2>/dev/null || true)
    if [ -n "$npm_cache" ] && [ -e "$npm_cache" ]; then
      printf '%-48s %12s\n' "npm cache: ${npm_cache/#$HOME/~}" "$(get_size "$npm_cache")"
    fi
  fi

  if has_cmd brew; then
    brew_cache=$(brew --cache 2>/dev/null || true)
    if [ -n "$brew_cache" ] && [ -e "$brew_cache" ]; then
      printf '%-48s %12s\n' "brew cache: ${brew_cache/#$HOME/~}" "$(get_size "$brew_cache")"
    fi
  fi

  if [ -d /var/cache/apt ] || [ -d /var/lib/apt/lists ]; then
    printf '%-48s %12s\n' "apt caches/lists" "requires sudo"
  fi
}

require_startup_dependencies
show_header
show_summary

hr
read_answer "Continue to interactive cleanup prompts? [y/N] " start
case "$start" in
  y|Y|yes|YES) ;;
  *) echo "Exiting."; exit 0 ;;
esac

# 1. Trash
if [ -d "$HOME/.local/share/Trash" ]; then
  confirm_empty_trash "$(get_size "$HOME/.local/share/Trash")"
fi

# 2. uv cache
if has_cmd uv && [ -d "$HOME/.cache/uv" ]; then
  confirm_and_run \
    "Clean uv package/build cache" \
    "$(get_size "$HOME/.cache/uv")" \
    "$HOME/.cache/uv" \
    "uv cache clean" \
    uv cache clean
fi

# 3. pip cache
if has_cmd pip; then
  pip_cache=$(pip cache dir 2>/dev/null || echo "$HOME/.cache/pip")
  if [ -d "$pip_cache" ]; then
    confirm_and_run \
      "Purge pip wheel/download cache" \
      "$(get_size "$pip_cache")" \
      "$pip_cache" \
      "$(printf 'pip cache purge || %q -- %q' "$TRASH_CMD" "$pip_cache")" \
      purge_pip_cache_or_trash pip "$pip_cache"
  fi
fi

# 4. pip3 cache fallback
if ! has_cmd pip && has_cmd pip3; then
  pip_cache=$(pip3 cache dir 2>/dev/null || echo "$HOME/.cache/pip")
  if [ -d "$pip_cache" ]; then
    confirm_and_run \
      "Purge pip3 wheel/download cache" \
      "$(get_size "$pip_cache")" \
      "$pip_cache" \
      "$(printf 'pip3 cache purge || %q -- %q' "$TRASH_CMD" "$pip_cache")" \
      purge_pip_cache_or_trash pip3 "$pip_cache"
  fi
fi

# 5. Bun cache
if has_cmd bun && [ -d "$HOME/.bun/install/cache" ]; then
  confirm_and_run \
    "Remove Bun global package cache" \
    "$(get_size "$HOME/.bun/install/cache")" \
    "$HOME/.bun/install/cache" \
    "bun pm -g cache rm" \
    bun pm -g cache rm
fi

# 6. npm cache
if has_cmd npm; then
  npm_cache=$(npm config get cache 2>/dev/null || true)
  if [ -n "$npm_cache" ] && [ -d "$npm_cache" ]; then
    confirm_and_run \
      "Clean npm cache" \
      "$(get_size "$npm_cache")" \
      "$npm_cache" \
      "npm cache clean --force" \
      npm cache clean --force
  fi
fi

# 7. pnpm store prune
if has_cmd pnpm; then
  pnpm_store=$(pnpm store path 2>/dev/null || true)
  if [ -n "$pnpm_store" ] && [ -d "$pnpm_store" ]; then
    confirm_and_run \
      "Prune unused pnpm store packages" \
      "$(get_size "$pnpm_store") current store; actual reclaimed may be less" \
      "$pnpm_store" \
      "pnpm store prune" \
      pnpm store prune
  fi
fi

# 8. Homebrew cleanup
if has_cmd brew; then
  brew_cache=$(brew --cache 2>/dev/null || true)
  dry=$(brew cleanup -n 2>/dev/null | tail -n 20 || true)
  sz="unknown cache size"
  if [ -n "$brew_cache" ] && [ -d "$brew_cache" ]; then
    sz=$(get_size "$brew_cache")
  fi

  hr
  echo "Homebrew cleanup dry run:"
  echo
  if [ -n "$dry" ]; then
    echo "$dry"
  else
    echo "No dry-run output or brew cleanup -n unavailable."
  fi

  confirm_and_run \
    "Run Homebrew cleanup" \
    "$sz" \
    "$brew_cache" \
    "brew cleanup" \
    brew cleanup
fi

# 9. System/package-manager audits and optional cleanups
hr
echo "System package and manual toolchain audit"
echo

echo "Largest apt/dpkg-installed packages:"
if has_cmd dpkg-query; then
  dpkg-query -Wf '${Installed-Size}	${Package}
' 2>/dev/null | sort -n | tail -50 | awk '{printf "%8.1f MiB  %s
", $1/1024, $2}'
else
  echo "dpkg-query not found."
fi

echo
if [ -d /usr/local/texlive ]; then
  echo "TeX Live detected: /usr/local/texlive ($(get_size /usr/local/texlive))"
  echo "TeX commands in use:"
  command -v pdflatex 2>/dev/null || true
  command -v xelatex 2>/dev/null || true
  command -v lualatex 2>/dev/null || true
  command -v tlmgr 2>/dev/null || true
  tlmgr --version 2>/dev/null | head -n 2 || true
  echo
  echo "No TeX cleanup is run automatically because this may be an actively used manual install."
fi

if [ -d /usr/local/cuda-12.5 ] || [ -e /usr/local/cuda ]; then
  echo
  echo "CUDA detected:"
  [ -d /usr/local/cuda-12.5 ] && echo "  /usr/local/cuda-12.5 ($(get_size /usr/local/cuda-12.5))"
  [ -e /usr/local/cuda ] && ls -ld /usr/local/cuda
  echo "CUDA commands/environment in use:"
  command -v nvcc 2>/dev/null || true
  nvcc --version 2>/dev/null | head -n 4 || true
  echo "CUDA_HOME=${CUDA_HOME:-}"
  echo "$PATH" | tr ':' '
' | grep -i cuda || true
  echo
  echo "No CUDA cleanup is run automatically because this may be needed for compiling GPU software."
fi

if [ -d /nix ] || has_cmd nix-store || has_cmd nix; then
  echo
  echo "Nix detected. Current /nix size: $(get_size /nix)"
  if has_cmd nix; then
    echo "Nix profiles/generations, if available:"
    nix profile history 2>/dev/null | tail -30 || true
  fi

  confirm_and_run \
    "Run Nix garbage collection" \
    "$(get_size /nix) current /nix size; actual reclaimed may be less" \
    "/nix" \
    "nix-store --gc" \
    nix-store --gc

  if has_cmd nix; then
    confirm_and_run \
      "Wipe old Nix profile history older than 30 days, then GC" \
      "$(get_size /nix) current /nix size; actual reclaimed may be less" \
      "/nix" \
      "nix profile wipe-history --older-than 30d && nix-store --gc" \
      nix_wipe_history_then_gc
  fi
fi

# 11. Rustup old nightlies
if has_cmd rustup && [ -d "$HOME/.rustup/toolchains" ]; then
  hr
  echo "Rust toolchains:"
  echo
  rustup toolchain list
  echo
  print_child_size_rows "$HOME/.rustup/toolchains"
  echo
  echo "Recommended: keep stable and any nightly you actively need."
  read_answer "Interactively uninstall Rust nightly toolchains one by one? [y/N] " rust_ans

  case "$rust_ans" in
    y|Y|yes|YES)
      while IFS= read -r tc; do
        case "$tc" in
          nightly-*)
            tc_name=$(echo "$tc" | awk '{print $1}')
            tc_path="$HOME/.rustup/toolchains/$tc_name"
            confirm_and_run \
              "Uninstall Rust toolchain: $tc_name" \
              "$(get_size "$tc_path")" \
              "$HOME/.rustup/toolchains" \
              "$(printf 'rustup toolchain uninstall %q' "$tc_name")" \
              rustup toolchain uninstall "$tc_name"
            ;;
        esac
      done < <(rustup toolchain list)
      ;;
    *) echo "Skipped Rust toolchain cleanup." ;;
  esac
fi

# 12. Editor server old versions
cleanup_editor_server() {
  local name="$1"
  local dir="$2"

  [ -d "$dir" ] || return 0

  hr
  echo "$name server installs:"
  echo
  print_child_size_rows "$dir"
  echo
  echo "These are usually old remote/editor server versions."
  echo "Keep the newest one or ones you actively use."

  read_answer "Interactively move entries in ${dir/#$HOME/~} to trash? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES)
      while IFS= read -r -d '' path; do
        [ -e "$path" ] || continue
        base=$(basename "$path")
        confirm_and_run \
          "Move $name server entry to trash: $base" \
          "$(get_size "$path")" \
          "$dir" \
          "$(printf '%q -- %q' "$TRASH_CMD" "$path")" \
          trash_path "$path"
      done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 | sort -z)
      ;;
    *) echo "Skipped $name server cleanup." ;;
  esac
}

cleanup_editor_server "VS Code" "$HOME/.vscode-server"
cleanup_editor_server "Cursor" "$HOME/.cursor-server"
cleanup_editor_server "Positron" "$HOME/.positron-server/bin"
cleanup_editor_server "Windsurf" "$HOME/.windsurf-server"

# 13. Container cleanup
if has_cmd podman || has_cmd docker; then
  hr
  echo "Container storage:"
  echo

  if has_cmd podman; then
    podman system df || true
    echo
    confirm_and_run "Prune unused Podman images" "see podman system df above" "" "podman image prune" podman image prune
    confirm_and_run "Prune stopped Podman containers" "see podman system df above" "" "podman container prune" podman container prune
    confirm_and_run "Prune unused Podman build cache" "see podman system df above" "" "podman builder prune" podman builder prune
    confirm_and_run "DANGEROUS: prune unused Podman volumes" "unknown; volumes may contain real data" "" "podman volume prune" podman volume prune
  fi

  if has_cmd docker; then
    docker system df || true
    echo
    confirm_and_run "Prune unused Docker images" "see docker system df above" "" "docker image prune" docker image prune
    confirm_and_run "Prune stopped Docker containers" "see docker system df above" "" "docker container prune" docker container prune
    confirm_and_run "Prune Docker build cache" "see docker system df above" "" "docker builder prune" docker builder prune
    confirm_and_run "DANGEROUS: prune unused Docker volumes" "unknown; volumes may contain real data" "" "docker volume prune" docker volume prune
  fi
fi

# 14. Optional model caches
optional_child_trash() {
  local label="$1"
  local dir="$2"
  local path base ans

  [ -d "$dir" ] || return 0

  hr
  echo "$label"
  echo
  print_child_size_rows "$dir"
  echo

  read_answer "Interactively move entries in ${dir/#$HOME/~} to trash? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES)
      while IFS= read -r -d '' path; do
        [ -e "$path" ] || continue
        base=$(basename "$path")
        confirm_and_run \
          "Move cache entry to trash: ${dir/#$HOME/~}/$base" \
          "$(get_size "$path")" \
          "$dir" \
          "$(printf '%q -- %q' "$TRASH_CMD" "$path")" \
          trash_path "$path"
      done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 | sort -z)
      ;;
    *) echo "Skipped cache entry trashing under ${dir/#$HOME/~}." ;;
  esac
}

hr
echo "Optional large model/app caches"
echo
echo "These may be expensive to re-download. Only trash them if you know you don't need them locally."
echo

read_answer "Prompt for optional model cache trashing? [y/N] " model_ans
case "$model_ans" in
  y|Y|yes|YES)
    if [ -d "$HOME/.cache/huggingface/hub" ]; then
      optional_child_trash "Hugging Face cached models/datasets/spaces" "$HOME/.cache/huggingface/hub"
    else
      optional_child_trash "Hugging Face cache entries" "$HOME/.cache/huggingface"
    fi
    optional_child_trash "llama.cpp cache entries" "$HOME/.cache/llama.cpp"
    optional_child_trash "Whisper cache entries" "$HOME/.cache/whisper"
    optional_child_trash "Cypress cache entries" "$HOME/.cache/Cypress"
    optional_child_trash "Puppeteer cache entries" "$HOME/.cache/puppeteer"
    ;;
  *) echo "Skipped optional model/app cache trashing." ;;
esac

# 15. Optional venv trashing
hr
echo "Optional Python virtualenv trashing"
echo
echo "This moves entire environments to trash, not just caches."
echo "Only trash envs you can recreate and know you do not use."
echo

for venv_root in "$HOME/.venvs" "$HOME/.virtualenvs" "$HOME/py-venv"; do
  [ -d "$venv_root" ] || continue

  echo
  echo "Virtualenv root: ${venv_root/#$HOME/~}"
  print_child_size_rows "$venv_root"
  echo

  read_answer "Interactively move envs under ${venv_root/#$HOME/~} to trash? [y/N] " venv_ans
  case "$venv_ans" in
    y|Y|yes|YES)
      while IFS= read -r -d '' env_path; do
        [ -d "$env_path" ] || continue
        base=$(basename "$env_path")
        confirm_and_run \
          "Move virtualenv to trash: ${venv_root/#$HOME/~}/$base" \
          "$(get_size "$env_path")" \
          "$venv_root" \
          "$(printf '%q -- %q' "$TRASH_CMD" "$env_path")" \
          trash_path "$env_path"
      done < <(find "$venv_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
      ;;
    *) echo "Skipped env trashing under ${venv_root/#$HOME/~}." ;;
  esac
done

if [ "$TRASHED_ITEMS" -gt 0 ]; then
  hr
  echo "Items moved to trash during this run: $TRASHED_ITEMS"
  confirm_empty_trash "$(get_size "$HOME/.local/share/Trash")"
fi

# 16. Snap audit only; removal requires sudo and is printed near the end.
if has_cmd snap; then
  hr
  echo "Disabled old snap revisions:"
  echo
  snap list --all 2>/dev/null | awk '/disabled/{print $1, $3, $4}' || true
  echo
  echo "Snap cleanup requires sudo, so the cleanup command is printed near the end instead of run here."
fi

show_summary

hr
echo "Done."
echo
echo "For a deeper manual pass, run:"
echo "  gdu ~"
echo
hr
echo "Optional sudo commands not run by this script"
echo
echo "APT cache/package cleanup:"
echo "  # Show the size of apt's downloaded package cache and package-list metadata."
echo "  sudo du -sh /var/cache/apt /var/lib/apt/lists 2>/dev/null"
echo
echo "  # Preview dependency packages apt considers no longer needed."
echo "  # --purge means it would also remove leftover config files for removed packages."
echo "  # --dry-run means it only prints what would happen; it does not change anything."
echo "  sudo apt autoremove --purge --dry-run"
echo
echo "  # Actually remove no-longer-needed dependency packages and purge their configs,"
echo "  # then delete cached .deb downloads from /var/cache/apt."
echo "  sudo apt autoremove --purge && sudo apt clean"
echo
echo "Snap old revision cleanup:"
echo "  # List disabled snap revisions. These are old package revisions retained for rollback."
echo "  snap list --all | awk '/disabled/{print \\\$1, \\\$3, \\\$4}'"
echo
echo "  # Remove only disabled old snap revisions, keeping the active revision installed."
echo "  snap list --all | awk '/disabled/{print \\\$1, \\\$3}' | while read -r snapname revision; do sudo snap remove \"\\$snapname\" --revision=\"\\$revision\"; done"
echo
echo "System directory scans:"
echo "  # Interactively inspect disk usage under /var, staying on the same filesystem."
echo "  sudo gdu -x /var"
echo "  # Interactively inspect apt/system-installed libraries and applications."
echo "  sudo gdu -x /usr"
echo "  # Interactively inspect the Nix store, if Nix is installed."
echo "  sudo gdu -x /nix"
