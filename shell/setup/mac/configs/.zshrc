export PATH="/run/current-system/sw/bin:$PATH"

# Make sure colors are available for the prompt
autoload -U colors && colors

# Check if running in VS Code's integrated terminal
if [[ "$TERM_PROGRAM" == "vscode" ]]; then
  #PS1='%{$fg[blue]%}> %{$reset_color%}'
  PS1='%F{blue}> %f'
fi

alias nano='micro'
alias te='open -a TextEdit'
alias sbash='source ~/.zshrc'
alias ebash='nano ~/.zshrc'
alias eflake='code ~/.config/nix/nix.code-workspace'
alias rflake='darwin-rebuild switch  --flake ~/.config/nix#JV-Macbook'
alias uflake="darwin-rebuild update  --flake ~/.config/nix#JV-Macbook"
alias psh='pwsh'
alias ls='eza -baX'
alias lsa='eza -lbax --width=80'
alias cls='clear'
alias clr='clear'

alias ports="lsof -i"
alias listen="sudo lsof -i | grep LISTEN"
alias wanip="dig +short myip.opendns.com @resolver1.opendns.com"
alias localip="ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'"
alias flushdns="sudo discoveryutil mdnsflushcache;sudo discoveryutil udnsflushcaches;say flushed"

alias loc="scc"
alias win11="pwsh ~/github/scripts/powershell/entra/Get-Win11UpgradeUpdate.ps1"
alias intune11="pwsh ~/github/scripts/powershell/entra/Get-Win11Intune.ps1"
alias ssnewuser="pwsh ~/github/scripts/powershell/entra/Add-NewUser.ps1"
alias tkill="kill-port 5173"
alias twatch="source ~/github/vtasks/.scripts/watch.sh"
alias copystuff="source ~/github/scripts/shell/setup/mac/copystuff.sh"
alias epwsh="code ~/.config/powershell/Microsoft.PowerShell_profile.ps1"
alias codebash="code ~/.zshrc"
alias ghhome="cd ~/github"
alias usage="npx ccusage@latest"

# Wire up pwsh to connect to all modules
pwsh() {
  if [[ "$1" == "-connect" ]]; then
    shift
    # Run Connect-All.ps1 as a file.  This will load your profile first, then run the script.
    command pwsh -NoExit -File "$HOME/.config/powershell/Connect-All.ps1"
  else
    command pwsh "$@"
  fi
}

