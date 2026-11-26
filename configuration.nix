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
    ./modules/libvirt
  ];

  # --- nix ---

  nixpkgs.config.allowUnfree = true;
  # Workarounds for nixpkgs regressions (2026-10 update); drop once fixed upstream.
  nixpkgs.overlays = [
    (_: prev: {
      # pywal16 passes "--prefix PATH : …" as one makeWrapperArgs element, which
      # structuredAttrs no longer word-splits, so makeWrapper rejects it.
      pywal16 = prev.pywal16.overrideAttrs (old: {
        makeWrapperArgs = lib.concatMap (lib.splitString " ") old.makeWrapperArgs;
      });
    })
  ];

  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  # avoids channels.nixos.org hitting GitHub's rate limit — nixpkgs is
  # pinned in flake.nix instead.
  nix.settings.flake-registry = "";
  programs.nix-ld.enable = true;

  system.stateVersion = "26.05";

  # --- boot ---

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;
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
    trustedInterfaces = ["zt+"];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  age.secrets.zerotierNetwork.file = "${repoDir}/secrets/zerotier-network.age";

  services.zerotierone.enable = true;
  # joinNetworks would put the network ID into the store and the public repo.
  systemd.services.zerotierone.preStart = lib.mkAfter ''
    touch "/var/lib/zerotier-one/networks.d/$(tr -d '[:space:]' < ${config.age.secrets.zerotierNetwork.path}).conf"
  '';

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
        "--remember-user-session"
        "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
        "--theme 'border=yellow;text=yellow;title=yellow;prompt=yellow;input=yellow;action=yellow;button=yellow;container=black;greet=lightyellow'"
      ];
      user = "greeter";
    };
  };

  # --- hardware ---

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # Intel VAAPI for the laptop (Moonlight decoding); inert on the AMD desktop.
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
    ];
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

  # --- programs ---

  systemd.tmpfiles.rules = [
    "z /.snapshots 0750 root root -"
    "z /home/.snapshots 0750 root root -"
    "Z ${repoDir} - ${username} users -"
    "d /var/lib/agenix-bootstrap 0700 root root -"
  ];

  services.printing.enable = true;

  programs.gamemode.enable = true;

  programs.steam.enable = true;

  programs.gamescope.enable = true;

  programs.ssh.knownHosts.github-com = {
    hostNames = ["github.com"];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  programs.ydotool.enable = true;

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

  services.sunshine = {
    enable = true;
    openFirewall = true;
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

  age.secrets.syncthingConfig = {
    file = "${repoDir}/secrets/syncthing-config.age";
    owner = username;
    mode = "0400";
  };

  # Devices/folders live in the syncthingConfig secret (Syncthing REST API JSON:
  # {devices: [...], folders: [...]}) instead of services.syncthing.settings,
  # which would publish device IDs and addresses. syncthing-secret-config
  # applies them and does the override itself, hence the module's is off.
  services.syncthing = {
    enable = true;
    user = username;
    dataDir = "/home/${username}";
    configDir = "/home/${username}/.config/syncthing";
    openDefaultPorts = true;
    overrideDevices = false;
    overrideFolders = false;
  };

  systemd.services.syncthing-secret-config = let
    st = config.services.syncthing;
  in {
    description = "Apply Syncthing devices and folders from the agenix secret";
    wantedBy = ["multi-user.target"];
    partOf = ["syncthing.service"];
    after = ["syncthing.service" "syncthing-init.service"];
    restartTriggers = [(builtins.hashFile "sha256" ./secrets/syncthing-config.age)];
    path = [pkgs.curl pkgs.jq pkgs.libxml2];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = st.user;
      RuntimeDirectory = "syncthing-secret-config";
      UMask = "0077";
    };
    script = ''
      set -euo pipefail
      cfg=${config.age.secrets.syncthingConfig.path}
      api=${st.guiAddress}/rest

      until key=$(xmllint --xpath 'string(configuration/gui/apikey)' ${st.configDir}/config.xml 2>/dev/null) && [ -n "$key" ]; do
        sleep 1
      done
      printf 'X-API-Key: %s\n' "$key" >"$RUNTIME_DIRECTORY/headers"
      req() { curl -sSfL -H "@$RUNTIME_DIRECTORY/headers" --retry 60 --retry-delay 1 --retry-all-errors "$@"; }

      jq -c '.devices[]' "$cfg" | while read -r d; do req --json "$d" -X POST "$api/config/devices"; done
      jq -c '.folders[]' "$cfg" | while read -r f; do req --json "$f" -X POST "$api/config/folders"; done

      self=$(req "$api/system/status" | jq -r .myID)
      req "$api/config/devices" |
        jq -r --arg self "$self" --slurpfile c "$cfg" \
          '($c[0].devices | map(.deviceID)) as $keep | .[].deviceID | select(. != $self and (. as $id | $keep | index($id) | not))' |
        while read -r id; do req -X DELETE "$api/config/devices/$id"; done
      req "$api/config/folders" |
        jq -r --slurpfile c "$cfg" \
          '($c[0].folders | map(.id)) as $keep | .[].id | select(. as $id | $keep | index($id) | not)' |
        while read -r id; do req -X DELETE "$api/config/folders/$id"; done
    '';
  };

  # --- users ---

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    description = "Lunobe";
    hashedPasswordFile = config.age.secrets.userPassword.path;
    extraGroups = ["networkmanager" "wheel" "libvirtd"];
  };
}
