# Placeholder so `nix flake check` can evaluate this host. install.sh
# replaces it with the real one when installing on the laptop.
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
  };
  nixpkgs.hostPlatform = "x86_64-linux";
}
