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
    hostName = "nixos";
    timeZone = "Asia/Jerusalem";
    system = "x86_64-linux";
    specialArgs = {inherit repoDir username hostName timeZone;};
  in {
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;

    nixosConfigurations.${hostName} = nixpkgs.lib.nixosSystem {
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
