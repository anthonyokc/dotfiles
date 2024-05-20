#!/bin/bash

ssh-keygen -t ed25519 -C "anthonyfloresokc@gmail.com" -f ~/.ssh/github_ed25519
cat ~/.ssh/github_ed25519.pub | clip.exe
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/github_ed25519.pub
git config --global commit.gpgsign true
touch ~/.ssh/allowed_signers
cat ~/.ssh/github_ed25519.pub >> ~/.ssh/allowed_signers
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github_ed25519
ssh-add -l
echo "Add the SSH key to your GitHub or GitLab account:
    - On GitHub, navigate to Settings → SSH and GPG keys → New SSH key.
    - On GitLab, go to Preferences → SSH Keys → Add an SSH key."
