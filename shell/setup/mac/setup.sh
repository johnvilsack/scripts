echo "Download and Install Nix"
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install)

echo "Create directory for Nix configuration"
mkdir -p ~/.config/nix

echo "Create Nix configuration file"
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

echo "Set Nix Path"
echo 'export PATH=$PATH:/run/current-system/sw/bin/darwin-rebuild' >> ~/.zshrc
source ~/.zshrc

echo "Download Flake"
curl "https://raw.githubusercontent.com/johnvilsack/scripts/refs/heads/main/shell/setup/mac/nix/flake.nix" -o "~/.config/nix/flake.nix"

echo "Build Flake"
darwin-rebuild switch  --flake ~/.config/nix#JV-Macbook
