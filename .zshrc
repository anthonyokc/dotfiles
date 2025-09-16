zmodload zsh/zprof
### This file includes
# ZSH Plugins 🔌
# ZSH Options ⚙️
# ZSH Keybindings ⌨️
# ZSH Completion ⚡
# Path Modifications 📁
# My Configs 🌐
# My Commands 🛠
# My Aliases 🕵️
# My Functions 🏭
# Plugins continued! 🔌



### ZSH Plugins 🔌
# Initialize zap (Zsh plugin manager) and install plugins if not already installed
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"
plug "romkatv/powerlevel10k" # A theme for Zsh
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
# Autosuggestions and syntax highlighting are located at the end of this file to avoid common conflicts/issues



### ZSH Options ⚙️
# General shell options
setopt glob_dots # Include hidden files in globbing, e.g., `ls *` will include files starting with a dot
setopt histignorealldups # Ignore duplicated commands in history, keeping only the most recent
setopt sharehistory # Share history between all sessions, so commands typed in one session are available in others
setopt CORRECT # Enable command correction, e.g., if you type `gti` instead of `git`, it will suggest the correct command

# ZLE (Zsh Line Editor) options,
set enable-bracketed-paste off

# Shell history options
HISTSIZE=1000 # Number of history entries to keep in memory
SAVEHIST=1000 # Number of history entries to save in the history file
HISTFILE=~/.zsh_history # History file location
HISTCONTROL=ignoreboth # Ignore duplicate lines or lines starting with a space in the history. See bash(1) for more options



### ZSH Keybindings ⌨️
export KEYTIMEOUT=1 # 10ms. ZSH uses the KEYTIMEOUT parameter to determine how long to wait (in hundredths of a second) for additional characters in sequence. Default is 0.4 seconds.
bindkey '^E' backward-kill-word # Ctrl + ; to delete the previous word
bindkey '^H' backward-kill-word # Ctrl + Backspace to delete the previous word
bindkey "^[[1;3C" forward-word # Alt + Right Arrow
bindkey "^[[1;3D" backward-word # Alt + Left Arrow
bindkey '^k' autosuggest-execute # Ctrl + k to execute the whole suggestion
bindkey '^j' autosuggest-accept # Ctrl + j to accept the whole suggestion

# Vim keybindings in ZSH and cursor shape
bindkey -v # Use vim keybindings
# Change cursor shape for different vi modes.
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] ||
     [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] ||
       [[ ${KEYMAP} == viins ]] ||
       [[ ${KEYMAP} = '' ]] ||
       [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select # call the function when the keymap is changed
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init # call the function when the line editor is initialized
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.



### ZSH Completion ⚡
# Enable command auto-completion, -U to not sort completions, -z to use zsh completion system
autoload -Uz compinit
# Initialize the completion system and use a specific dump file to speed up loading
# Otherwise, when two instances start there may be a race condition, and a
# second dump file may be created, which slows down startup time and creates
# clutter.
compinit -C -d "$HOME/.zcompdump" # -C: trust dump; -d: fixed cache path

# Completion settings
zstyle ':completion:*' auto-description 'specify: %d' # Show description of the command being completed
zstyle ':completion:*' completer _expand _complete _correct _approximate # Order of completion methods
zstyle ':completion:*' format 'Completing %d' # Format of the completion prompt
zstyle ':completion:*' group-name '' # No group names, just list completions
zstyle ':completion:*' menu select=2 # Use menu selection if there are 2 or more options
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS} # Use LS_COLORS for coloring the completion list
zstyle ':completion:*' list-colors '' # Disable list colors
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s # Prompt when listing completions
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*' # Case-insensitive matching and other matching rules
zstyle ':completion:*' menu select=long # Use menu selection for long lists
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s # Prompt when scrolling through completions
zstyle ':completion:*' use-compctl false # Don't use compctl
zstyle ':completion:*' verbose true # Verbose completion messages, e.g. "1 completion"

# Completion for `kill` command
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31' # Color PIDs in red
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd' # Command to list processes for completion



### Path Modifications 📁
# Function: only adds to path if it's not already there
# This way we can avoid duplicates in the PATH when sourcing this file multiple times
# Usage: add_to_path "/path/to/add"
add_to_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}

add_to_path "/usr/local/texlive/2022/bin/x86_64-linux"
add_to_path "$HOME/.local/bin"
add_to_path "/snap/bin"
add_to_path "/opt/nvim-linux64/bin"
add_to_path "$HOME/scripts"
add_to_path "$HOME/scripts/installers/"
add_to_path "/usr/local/go/bin"
add_to_path "/usr/local/cuda-12.5/bin"
[[ -d $NPM_CONFIG_PREFIX/bin ]] && add_to_path "$NPM_CONFIG_PREFIX/bin"
[[ -d $PYENV_ROOT/bin ]] && add_to_path "$PYENV_ROOT/bin"


# Test of a more general function that can be used for any path variable
# add_to_any_path($1) {
#     case ":$1:" in
#         *":$2:"*) ;;
#         *) export $1="$2:$1" ;;
#     esac
# }
# add_to_any_path "MANPATH" "/usr/local/texlive/2022/texmf-dist
export MANPATH="/usr/local/texlive/2022/texmf-dist/doc/man:$MANPATH"
# Preset Configuration
export INFOPATH="/usr/local/texlive/2022/texmf-dist/doc/info:$INFOPATH"

# Paths to look for dynamic (and shared) libraries
# Example of something we would replace with add_to_any_path
add_to_ld_library_path() {
    case ":$LD_LIBRARY_PATH:" in
        *":$1:"*) ;;
        *) export LD_LIBRARY_PATH="$1:$LD_LIBRARY_PATH" ;;
    esac
}
add_to_ld_library_path "/usr/lib/wsl/lib"
add_to_ld_library_path "/usr/local/cuda-12.5/lib64"



### Autoload Various Tools ⚙️ (after path modifications)
# Load zoxide, a smarter cd command
# cd to any directory you have visited before with a single command
# E.g., `z docs` to go to ~/Documents if you have been there before
eval "$(zoxide init zsh)"

# Load fnm, a fast Node.js version manager alternative to nvm.
# This command:
# 1. fnm env: Exports FNM_DIR and prepends to PATH so that the fnm binary can be found,
  # and so fnm's active Node version is used because it's at the front of PATH.
# 2. --use-on-cd --shell=zsh: Sets up shell integration so that fnm can automatically
  # switch Node versions when you cd into a directory with a .nvmrc or .node-version file.
  # When you 'cd' it searches and runs 'fnm use --silent' if it finds a version file.
eval "$(fnm env --use-on-cd --shell=zsh)"

# Load pyenv, a Python version manager
# Install build dependencies first: https://github.com/pyenv/pyenv/wiki#suggested-build-environment
eval "$(pyenv init - zsh)"

# Load caraspace, a fast, multi-shell completion library and binary
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'   # optional, but nice
source <(carapace _carapace)                            # registers all completers

# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)

# ZSH Syntax Highlighting Configurations
export ZSH_HIGHLIGHT_MAXLENGTH=200    # or 0 to disable on very long lines

# ZSH Autosuggestions Configurations
export ZSH_AUTOSUGGEST_STRATEGY=(history)  # lighter; no compsys query on each keystroke; add 'completion' for more suggestions from carapace, etc.
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=60 # max size of buffer to search for suggestions, 40-80 is recommended
export ZSH_AUTOSUGGEST_USE_ASYNC=1 # reduce lag; compute suggestions via zsh async background worker. Keystrokes are never blocked. May cause out-of-order suggestions if typing very fast.

### Environment Variables 🌐
export OPENSSL_CONF=/etc/ssl  # For phantomjs
export SUDO_EDITOR=$(which nvim)
export EDITOR=$(which nvim)
# Go
export GOPATH="$HOME/.cache/go" # Go module cache directory for downloaded modules and compiled package objects


# make less more friendly for non-text input files, see lesspipe(1)
# For example, this allows `less myfile.zip` to work as expected
# otherwise less would just show binary gibberish on the terminal
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"



### My Aliases 🕵️
if [ -f ~/.zsh_aliases ]; then
    . ~/.zsh_aliases
fi

# TODO: Get rid of this? enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    eval "$(dircolors -b)"
    alias ls='lsd --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'



### Plugins continued! 🔌
# Hooks into the line editor to show ghosted suggestions
# Needs to run after other plugins so they don’t overwrite it.
# But before zsh-syntax-highlighting, which needs to be last.
plug "zsh-users/zsh-autosuggestions"

# Syntax highlighting for the Z shell;
# It colors the command line right before it's drawn
# Must be last or it can break or override everything else.
plug "zsh-users/zsh-syntax-highlighting"

