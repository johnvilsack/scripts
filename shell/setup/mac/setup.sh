#!/bin/bash

set -euo pipefail

echo "Installing Xcode Command Line Tools..."
xcode-select --install 2>/dev/null || echo "Already installed"
until xcode-select -p &>/dev/null; do sleep 5; done

echo "Installing Rosetta (for Apple Silicon)..."
softwareupdate --install-rosetta --agree-to-license || echo "Rosetta may already be installed"

echo "Installing Nix..."
sh <(curl --proto '=https' --tlsv1.2 -sSfL https://nixos.org/nix/install)

echo "Sourcing Nix profile..."
. "$HOME/.nix-profile/etc/profile.d/nix.sh"

echo "Enabling flakes support..."
mkdir -p "$HOME/.config/nix"
echo "experimental-features = nix-command flakes" > "$HOME/.config/nix/nix.conf"

echo "Setting hostname using serial number..."
serial=$(ioreg -l | awk -F'"' '/IOPlatformSerialNumber/ { print $4 }' | tr -d '\n')
hostname="JV-$serial"
sudo scutil --set HostName "$hostname"
sudo scutil --set ComputerName "$hostname"
sudo scutil --set LocalHostName "$hostname"

echo "Remove All Dock Icons"
defaults write com.apple.dock persistent-others -array

echo "Fetching flake..."
curl -sSL "https://raw.githubusercontent.com/johnvilsack/scripts/refs/heads/main/shell/setup/mac/nix/flake.nix" -o "$HOME/.config/nix/flake.nix"

echo "Running darwin-rebuild..."
darwin-rebuild switch --flake "$HOME/.config/nix#JV-Macbook"
