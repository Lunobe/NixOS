{pkgs, ...}: {
  imports = [./hardware-configuration.nix];

  # Intel VAAPI for Moonlight decoding.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    intel-vaapi-driver
  ];
}
