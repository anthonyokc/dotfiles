### This file includes
# ZSH plugins
# ZSH options
# ZSH keybindings
# ZSH completion
# Path modifications
# My Configs
# My Commands
# My Aliases
# My Functions
# GWSL

### ZSH Plugins
# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"
plug "zsh-users/zsh-autosuggestions"
bindkey '^k' autosuggest-execute
bindkey '^j' autosuggest-accept
plug "zap-zsh/supercharge"
plug "zsh-users/zsh-syntax-highlighting"
plug "romkatv/powerlevel10k"
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

### ZSH Options
setopt histignorealldups sharehistory
# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# Use vim keybindings
bindkey -v
export KEYTIMEOUT=1 # 10ms. ZSH uses the KEYTIMEOUT parameter to determine how long to wait (in hundredths of a second) for additional characters in sequence. Default is 0.4 seconds.
bindkey '^E' backward-kill-word # Ctrl + ;
bindkey '^H' backward-kill-word # Ctrl + Backspace
bindkey "^[[1;3C" forward-word
bindkey "^[[1;3D" backward-word

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
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.

### ZSH Completion
# Use modern completion system
autoload -Uz compinit
compinit

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'


### Path Modifications
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
add_to_path "/home/anthony/.local/bin"
add_to_path "/snap/bin"
add_to_path "/opt/nvim-linux64/bin"
add_to_path "/home/anthony/scripts"
add_to_path "/usr/local/go/bin"
add_to_path "/usr/local/cuda-12.5/bin"

# Add Homebrew to PATH
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

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

### My Configs
## My Commands
set enable-bracketed-paste Off
# source /usr/share/autojump/autojump.sh
source <(fzf --zsh) # Set up fzf key bindings and fuzzy completion

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export OPENSSL_CONF=/etc/ssl  # For phantomjs
export SUDO_EDITOR=$(which nvim)
export EDITOR=$(which nvim)
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket" # For ssh-agent

## Autostart
eval "$(zoxide init zsh)"

### My Aliases
alias zs='source ~/.zshrc'

# some more ls aliases
alias ll='lsd -alF'
alias la='lsd -A'
alias l='lsd'

# update/upgrade
alias update='sudo apt update && apt list --upgradable'
alias upgrade='sudo apt upgrade && sudo apt autoremove'

# Vim
alias v='nvim'
alias vim='nvim'
alias vf='nvim -c "FZF"'
alias vz='nvim ~/.zshrc'

# tmux
alias t='tmux new-session -s "Home 🏠"'
alias ta='tmux attach'
alias tk='tmux kill-server'

# yazi
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# Working with Git
alias sa='ssh-add ~/.ssh/github_ed25519.pub'
alias ga='git add'
alias gc='git commit -m'
alias gca='git commit -am'
alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias gl='git log'
alias gplf= 'git fetch --all; git reset --hard HEAD; git merge @{u}'
alias gpl='git pull'
alias gps='git push'
alias gch='git checkout'
alias gf='git fetch'
function gcl() {
    git clone git@github.com:$1.git
}

alias hb='hub browse'

alias bfg='java -jar $HOME/scripts/bfg-1.14.0.jar'


# Working with dotfiles
alias dotfiles='/usr/bin/git --git-dir=$HOME/dotfiles/ --work-tree=$HOME'
alias dotfiles-push='dotfiles push git@github.com:AnthonyOKC/dotfiles.git'
alias da='dotfiles add -u'
alias dc='dotfiles commit -m'
alias ds='dotfiles status'
alias dp='dotfiles-push'

# tmux bare git repo
alias tmux-repo='/usr/bin/git --git-dir=$HOME/tmux/ --work-tree=$HOME'

# xfce4
alias start-noshow='pgrep -x bspwm > /dev/null || (bspwm &> /dev/null &) && startxfce4 &> ~/log/xfce4.log'
alias start='pgrep -x bspwm > /dev/null || (bspwm &> /dev/null &) && startxfce4'


###  Preset Configuration
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
    else
    color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='lsd --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'


# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.zsh_aliases ]; then
    . ~/.zsh_aliases
fi

### Setting up GWSL
# Comment out the following lines if you are not using GWSL
# export DISPLAY=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2; exit;}'):0.0 #GWSL
# export PULSE_SERVER=tcp:$(cat /etc/resolv.conf | grep nameserver | awk '{print $2; exit;}') #GWSL
#
# export GDK_SCALE=1 #GWSL
# export QT_SCALE_FACTOR=1 #GWSL
#
# export LIBGL_ALWAYS_INDIRECT=1 #GWSL

### Setting up WSLg
export GDK_DPI_SCALE=1.5 # My monitor works best with 150% DPI Scaling

xrdb -load ~/.Xresources
