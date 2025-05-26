{
  description = "JV Macbook";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew }:
    let
      configuration = { pkgs, config, ... }: {

        nixpkgs.config.allowUnfree = true;

        environment.systemPackages = [
          pkgs.neofetch
          pkgs.mkalias
          pkgs.python3Full
          pkgs.htop
          pkgs.wget
          pkgs.nano
          pkgs.powershell
          pkgs.nixfmt
          pkgs.micro
          pkgs.python312Packages.pyinstaller
          pkgs.python312Packages.tkinter
          pkgs.chezmoi
          pkgs.gh
          pkgs.gum
          pkgs.nerd-fonts.fira-code
          pkgs.roboto
        ];

        fonts.packages = [
          pkgs.nerd-fonts.fira-code
          pkgs.roboto
        ];

        homebrew = {
          enable = true;
          taps = [ ];
          brews = [
            "mas"
            "ollama"
            "node"
            "scc"
          ];
          casks = [
            "github"
            "the-unarchiver"
            "discord"
            "visual-studio-code"
            "warp"
            "microsoft-teams"
            "google-chrome"
            "vmware-fusion"
            "utm"
            "appcleaner"
            "msty"
            "jordanbaird-ice"
            "crystalfetch"
            "bruno"
            "chatgpt"
          ];
          masApps = {
            "1Password Extension" = 1569813296;
            "Microsoft Word" = 462054704;
            "Microsoft Excel" = 462058435;
            "Microsoft PowerPoint" = 462062816;
            "Microsoft Outlook" = 985367838;
            "Microsoft OneNote" = 784801555;
            "Omnigraffle 7" = 1142578753;
            "Windows App" = 1295203466;
          };
          onActivation.cleanup = "zap";
          onActivation.autoUpdate = true;
          onActivation.upgrade = true;
        };

        system.activationScripts.applications.text = let
          env = pkgs.buildEnv {
            name = "system-applications";
            paths = config.environment.systemPackages;
            pathsToLink = "/Applications";
          };
        in pkgs.lib.mkForce ''
          echo "setting up /Applications..." >&2
          rm -rf /Applications/Nix\ Apps
          mkdir -p /Applications/Nix\ Apps
          find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
          while read -r src; do
            app_name=$(basename "$src")
            echo "copying $src" >&2
            ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
          done
        '';

        system.defaults = {
          finder = {
            NewWindowTarget = "Other";
            NewWindowTargetPath = "file://" + (if builtins ? getEnv && builtins.getEnv "HOME" != "" then builtins.getEnv "HOME" else "/Users/johnv") + "/";
            FXDefaultSearchScope = "SCcf";
            ShowPathbar = true;
            _FXSortFoldersFirst = true;
          };

          NSGlobalDomain = {
            AppleInterfaceStyle = "Dark";
            AppleShowAllExtensions = true;
            NSAutomaticSpellingCorrectionEnabled = false;
            NSAutomaticCapitalizationEnabled = false;
            NSAutomaticPeriodSubstitutionEnabled = false;
            NSAutomaticQuoteSubstitutionEnabled = false;
          };
        };

        nix.settings.experimental-features = "nix-command flakes";

        system.configurationRevision = self.rev or self.dirtyRev or null;
        system.stateVersion = 6;
        nixpkgs.hostPlatform = "aarch64-darwin";
      };

    in {
      darwinConfigurations."JV-Macbook" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              user = "johnv";
            };
          }
        ];
      };
    };
}
