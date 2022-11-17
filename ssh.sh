#!/bin/sh

# run `sh -s "your-email"`

#  credit https://github.com/driesvints/dotfiles/blob/main/ssh.sh
echo "Generating a new SSH key with ed25519"

# Generating a new SSH key
# https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
ssh-keygen -t ed25519 -C $1 -f ~/.ssh/id_ed25519

echo "Adding SSH key to the ssh-agent"
eval "$(ssh-agent -s)"


echo "Adding host config"
touch ~/.ssh/config
echo "Host *\n AddKeysToAgent yes\n UseKeychain yes\n IdentityFile ~/.ssh/id_ed25519" | tee ~/.ssh/config

echo "Adding key to the agent"
ssh-add -K ~/.ssh/id_ed25519

echo "Copying key to clipboard"
pbcopy < ~/.ssh/id_ed25519.pub

# Adding your SSH key to your GitHub account
echo "ssh key generated and copied"
