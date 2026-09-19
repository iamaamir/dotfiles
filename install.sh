
#install brew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

#install brew packages
./brew.sh

# kitty 
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin

# all clones goest here
mkdir -p ~/git

echo "upnext run 'sh ./ssh.sh <email@xyz.com>' to generate ssh key"
