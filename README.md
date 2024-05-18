# dotfiles
My dotfiles for Linux.

# Migrating to New Setup

```
alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'

# Avoids possible recursion
echo "dotfiles" >> .gitignore

git clone --bare git@github.com:AnthonyOKC/dotfiles.git $HOME/dotfiles

# Backup any files that match dotfiles
mkdir -p .config-backup && \
config checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | \
xargs -I{} mv {} .config-backup/{}

config checkout

config config --local status.showUntrackedFiles no
```
