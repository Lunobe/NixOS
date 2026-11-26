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
    xwayland-satellite-patched,
    ...
  }: let
    repoDir = "/etc/nixos";
    username = "lunobe";
    timeZone = "Asia/Jerusalem";
    system = "x86_64-linux";
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
    mkHost = hostName: let
      specialArgs = {inherit repoDir username hostName timeZone;};
    in
      lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          ./configuration.nix
          ./hosts/${hostName}

          # pins the nixpkgs registry alias to this flake's locked input, so
          # `nix search`/`nix eval nixpkgs#...` resolve offline; freshness
          # comes from `nx up`, not a live lookup.
          {
            nix.registry.nixpkgs.flake = nixpkgs;
            nix.nixPath = ["nixpkgs=${nixpkgs}"];
          }

          {nixpkgs.overlays = [xwayland-satellite-patched.overlays.default];}

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
  in {
    formatter.${system} = pkgs.alejandra;

    checks.${system} = {
      format = lintCheck "format" [pkgs.alejandra] "alejandra --check .";
      statix = lintCheck "statix" [pkgs.statix] "statix check .";
      deadnix = lintCheck "deadnix" [pkgs.deadnix] "deadnix --fail --exclude hosts/*/hardware-configuration.nix .";
      shellcheck = lintCheck "shellcheck" [pkgs.shellcheck] "shellcheck install.sh";
    };

    # one entry per hosts/<name>; the name is also the machine's hostname
    nixosConfigurations = lib.genAttrs ["desktop" "laptop"] mkHost;
  };
}
