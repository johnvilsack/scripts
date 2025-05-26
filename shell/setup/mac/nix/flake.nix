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

        # List packages installed in system profile. To search by name, run:
        # $ nix-env -qaP | grep wget
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
        ];

        # fonts.packages = [ 
        #   pkgs.nerd-fonts.fira-code
        #   pkgs.roboto 
        # ];

        homebrew = {
          enable = true;
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
            "font-fira-code"
            "font-roboto"
          ];
          masApps = {
            #"Microsoft365" = 1450038993;
            # 1password out of date
            # onedrive loses functionality
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
          # Set up applications.
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
          dock.autohide = true;
          #dock.persistent-apps = [
            #{ app = "/System/Applications/Safari.app";#}
            #{ app = "{$pkgs._1password-gui}/Applications/1Password.app";
            #}
            #"${pkgs.alacritty}/Applications/Alacritty.app"
            #"/System/Applications/Nix\ Apps/1Password.app"
            #"/System/Applications/Nix\ Apps/Discord.app"
            #"/System/Applications/Nix\ Apps/Visual\ Studio\ Code.app"
            #"/System/Applications/Nix\ Apps/Warp.app"
            #"/System/Applications/Github Desktop.app"
            #"/System/Applications/Safari.app"
            #"/System/Applications/Calendar.app"
          #];

          NSGlobalDomain.AppleInterfaceStyle = "Dark";
        };

        # Necessary for using flakes on this system.
        nix.settings.experimental-features = "nix-command flakes";

        # Enable alternative shell support in nix-darwin.
        # programs.fish.enable = true;

        # Set Git commit hash for darwin-version.
        system.configurationRevision = self.rev or self.dirtyRev or null;

        # Used for backwards compatibility, please read the changelog before changing.
        # $ darwin-rebuild changelog
        system.stateVersion = 6;

        # The platform the configuration will be used on.
        nixpkgs.hostPlatform = "aarch64-darwin";
      };
    in {
      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#simple
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
