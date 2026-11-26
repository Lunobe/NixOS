{
  description = "NixOS configuration for Lunobe";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nx = {
      url = "github:Lunobe/Nx";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    # Fork adding X11 keyboard grab forwarding (xwayland-keyboard-grab-unstable-v1
    # -> keyboard-shortcuts-inhibit-unstable-v1) so XGrabKeyboard apps (VMware,
    # VirtualBox, remote-desktop) capture keys instead of niri intercepting them.
    # Tracks Supreeeme/xwayland-satellite#220 (unfixed).
    xwayland-satellite-patched = {
      url = "github:Lunobe/xwayland-satellite/keyboard-grab-forwarding";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    nix-index-database,
    agenix,
    nx,
    nix-flatpak,
    xwayland-satellite-patched,
    ...
  }: let
    repoDir = "/etc/nixos";
    username = "lunobe";
    hostName = "nixos";
    timeZone = "Asia/Jerusalem";
    system = "x86_64-linux";
    specialArgs = {inherit repoDir username hostName timeZone;};
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (nixpkgs) lib;

    # only code, so wallpapers/fastfetch images don't invalidate the checks
    lintSrc = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        (lib.fileset.fileFilter (f: f.hasExt "nix") ./.)
        ./statix.toml
        ./install.sh
      ];
    };
    lintCheck = name: inputs: cmd:
      pkgs.runCommand "check-${name}" {nativeBuildInputs = inputs;} ''
        cd ${lintSrc}
        ${cmd}
        touch $out
      '';
  in {
    formatter.${system} = pkgs.alejandra;

    checks.${system} = {
      format = lintCheck "format" [pkgs.alejandra] "alejandra --check .";
      statix = lintCheck "statix" [pkgs.statix] "statix check .";
      deadnix = lintCheck "deadnix" [pkgs.deadnix] "deadnix --fail --exclude hardware-configuration.nix .";
      shellcheck = lintCheck "shellcheck" [pkgs.shellcheck] "shellcheck install.sh";
    };

    nixosConfigurations.${hostName} = lib.nixosSystem {
      inherit system specialArgs;
      modules = [
        ./configuration.nix

        # pins the nixpkgs registry alias to this flake's locked input, so
        # `nix search`/`nix eval nixpkgs#...` resolve offline; freshness
        # comes from `nx up`, not a live lookup.
        {
          nix.registry.nixpkgs.flake = nixpkgs;
          nix.nixPath = ["nixpkgs=${nixpkgs}"];
        }

        {nixpkgs.overlays = [xwayland-satellite-patched.overlays.default];}

        nix-flatpak.nixosModules.nix-flatpak

        agenix.nixosModules.default
        {environment.systemPackages = [agenix.packages.${system}.default];}

        home-manager.nixosModules.default
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = ./home.nix;
          home-manager.sharedModules = [
            nix-index-database.homeModules.default
            nx.homeManagerModules.default
          ];
          home-manager.extraSpecialArgs = specialArgs;
        }
      ];
    };
  };
}
