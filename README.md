# dotfiles
My dotfiles for Linux.

# Migrating to New Setup

```
alias dotfiles='/usr/bin/git --git-dir=$HOME/dotfiles/ --work-tree=$HOME'

# Avoids possible recursion
echo "dotfiles" >> .gitignore

git clone --bare git@github.com:AnthonyOKC/dotfiles.git $HOME/dotfiles

# Backup any files that match dotfiles
mkdir -p .config-backup && \
dotfiles checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | \
xargs -I{} mv {} .config-backup/{}

dotfiles checkout

dotfiles config --local status.showUntrackedFiles no
```
