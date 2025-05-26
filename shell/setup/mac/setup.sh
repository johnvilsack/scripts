sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install)
mkdir ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

echo 'export PATH=$PATH:/run/current-system/sw/bin/darwin-rebuild' >> ~/.zshrc
source ~/.zshrc

darwin-rebuild switch  --flake ~/.config/nix#JV-Macbook

