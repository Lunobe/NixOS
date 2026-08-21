{
  config,
  pkgs,
  lib,
  repoDir,
  username,
  hostName,
  timeZone,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./modules/system/secrets.nix
  ];

  # -- nix --

  nixpkgs.config.allowUnfree = true;
  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  # disables the live channels.nixos.org lookup that was hitting GitHub's
  # rate limit; the "nixpkgs" alias is pinned in flake.nix instead.
  nix.settings.flake-registry = "";

  system.stateVersion = "26.05";

  # -- boot --

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages;

  # -- store cleanup --
  # runs on boot rather than every switch, so back-to-back switches without
  # a reboot don't keep re-fetching/re-deleting the same flake-eval sources.

  systemd.services.nix-gc-boot = {
    description = "Garbage-collect orphaned Nix store paths";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nix}/bin/nix-collect-garbage";
    };
  };

  # -- networking --

  networking.hostName = hostName;
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      19762 # Minecraft
    ];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # -- locale --

  time.timeZone = timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # -- display --

  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # -- hardware --

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # -- audio --

  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # -- programs --

  systemd.tmpfiles.rules = [
    "z /.snapshots 0750 root root -"
    "z /home/.snapshots 0750 root root -"
    "Z ${repoDir} - ${username} users -"
    "d /var/lib/agenix-bootstrap 0700 root root -"
  ];

  services.printing.enable = true;

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      "registry-mirrors" = ["https://mirror.gcr.io"];
    };
  };

  virtualisation.vmware.host.enable = true;

  programs.steam.enable = true;

  programs.ssh.knownHosts.github-com = {
    hostNames = ["github.com"];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  services.flatpak.enable = true;

  services.wivrn = {
    enable = true;
    openFirewall = true;
  };

  programs.fish.enable = true;

  services.snapper.configs = {
    root = {
      SUBVOLUME = "/";
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    };
    home = {
      SUBVOLUME = "/home";
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    };
  };

  programs.niri.enable = true;
  services.displayManager.defaultSession = lib.mkForce "niri";

  # -- users --

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    description = "Lunobe";
    hashedPasswordFile = config.age.secrets.userPassword.path;
    extraGroups = ["networkmanager" "wheel" "docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB6HS+1ewVfU4Mm+L68yT4TdxhJQSWKiRCXHIXUvA87E u0_a554@localhost"
    ];
  };
}
