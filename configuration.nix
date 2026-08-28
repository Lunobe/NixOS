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
  ];

  # --- nix ---

  nixpkgs.config.allowUnfree = true;

  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  # avoids channels.nixos.org hitting GitHub's rate limit — nixpkgs is
  # pinned in flake.nix instead.
  nix.settings.flake-registry = "";

  system.stateVersion = "26.05";

  # --- boot ---

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages;
  boot.consoleLogLevel = 0;
  boot.kernelParams = ["quiet" "udev.log_level=3"];
  systemd.settings.Manager.ShowStatus = false;

  # --- store cleanup ---
  # runs on boot, not every switch — avoids re-fetching/deleting the same
  # flake-eval sources across back-to-back switches.

  systemd.services.nix-gc-boot = {
    description = "Garbage-collect orphaned Nix store paths";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nix}/bin/nix-collect-garbage";
    };
  };

  # --- secrets ---
  # identity.txt is a manually-bootstrapped decrypted copy — never in
  # /nix/store or git; secrets/identity.txt.age is passphrase-encrypted
  # and safe to publish.

  age.identityPaths = ["/var/lib/agenix-bootstrap/identity.txt"];
  age.secrets.userPassword.file = "${repoDir}/secrets/user-password.age";

  age.secrets.sshHosts = {
    file = "${repoDir}/secrets/ssh-hosts.age";
    owner = username;
    mode = "0400";
  };

  age.secrets.obsWebsocketPassword = {
    file = "${repoDir}/secrets/obs-websocket-password.age";
    owner = username;
    mode = "0400";
  };

  age.secrets.sshPrivateKey = {
    file = "${repoDir}/secrets/ssh-private-key.age";
    owner = username;
    mode = "0400";
  };

  age.secrets.r2Credentials = {
    file = "${repoDir}/secrets/r2-credentials.age";
    owner = username;
    mode = "0400";
  };

  age.secrets.resticPassword = {
    file = "${repoDir}/secrets/restic-password.age";
    owner = username;
    mode = "0400";
  };

  age.secrets.ghToken = {
    file = "${repoDir}/secrets/gh-token.age";
    owner = username;
    mode = "0400";
  };

  # github: fetcher hits GitHub's 60 req/hour unauthenticated limit —
  # routine flake updates exhaust it. Can't set access-tokens directly from
  # the agenix secret (nix.conf is built before secrets decrypt), so an
  # activation script writes a runtime-only snippet nix.conf pulls in via
  # !include.
  system.activationScripts.nixAccessTokens = {
    deps = ["agenix"];
    text = ''
      install -d -m 755 /run/nix-conf-extra
      printf 'access-tokens = github.com=%s\n' "$(cat ${config.age.secrets.ghToken.path})" \
        > /run/nix-conf-extra/access-tokens.conf
      chown ${username} /run/nix-conf-extra/access-tokens.conf
      chmod 400 /run/nix-conf-extra/access-tokens.conf
    '';
  };
  nix.extraOptions = ''
    !include /run/nix-conf-extra/access-tokens.conf
  '';

  # --- networking ---

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

  # --- locale ---

  time.timeZone = timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # --- display ---

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = lib.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time"
        "--asterisks"
        "--remember"
        "--theme 'border=yellow;text=yellow;title=yellow;prompt=yellow;input=yellow;action=yellow;button=yellow;container=black;greet=lightyellow'"
      ];
      user = "greeter";
    };
  };

  # --- hardware ---

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # --- audio ---

  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # --- virtualisation ---

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      "registry-mirrors" = ["https://mirror.gcr.io"];
    };
  };

  virtualisation.vmware.host.enable = true;

  # --- programs ---

  systemd.tmpfiles.rules = [
    "z /.snapshots 0750 root root -"
    "z /home/.snapshots 0750 root root -"
    "Z ${repoDir} - ${username} users -"
    "z /home/${username}/vmware 0750 ${username} users -"
    "d /var/lib/agenix-bootstrap 0700 root root -"
  ];

  services.printing.enable = true;

  programs.gamemode.enable = true;

  programs.steam.enable = true;

  programs.ssh.knownHosts.github-com = {
    hostNames = ["github.com"];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  services.flatpak.enable = true;

  # flatpak's module only manages the daemon, not remotes — this makes
  # adding flathub self-healing instead of a one-off command a fresh
  # install would lack.
  systemd.services.flatpak-add-flathub = {
    description = "Add the Flathub Flatpak remote";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
    };
  };

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

  # --- users ---

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
