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
  # Workarounds for nixpkgs regressions (2026-10 update); drop once fixed upstream.
  nixpkgs.overlays = [
    (_: prev: {
      # pywal16 passes "--prefix PATH : …" as one makeWrapperArgs element, which
      # structuredAttrs no longer word-splits, so makeWrapper rejects it.
      pywal16 = prev.pywal16.overrideAttrs (old: {
        makeWrapperArgs = lib.concatMap (lib.splitString " ") old.makeWrapperArgs;
      });
      # patchelf >= 0.18 leaves vmnet-natd with a PHDR outside any LOAD
      # segment, so it segfaults in ld.so and vmware-networks fails to start.
      vmware-workstation = prev.vmware-workstation.overrideAttrs (old: {
        preFixup =
          (old.preFixup or "")
          + ''
            export PATH=${prev.patchelf.overrideAttrs {
              version = "0.15.2";
              src = prev.fetchurl {
                url = "https://github.com/NixOS/patchelf/releases/download/0.15.2/patchelf-0.15.2.tar.bz2";
                hash = "sha256-F3RfVkFZyOIo/EEtplogSLhGxLa0Igt3y/IkFuAvLXw=";
              };
            }}/bin:$PATH
          '';
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
  # vmware-modules installs .ko files by hand, bypassing nixpkgs' kmodigest
  # signing, so the kernel-modules aggregator fails on missing *.ko.cer.
  # Sign in postFixup so stripping can't drop the appended signature.
  # Temporary (2026-10 update); drop once nixpkgs' vmware package signs them.
  boot.kernelPackages = pkgs.linuxPackages.extend (_: super: {
    vmware = super.vmware.overrideAttrs (old: {
      postFixup =
        (old.postFixup or "")
        + ''
          for ko in "$out"/lib/modules/*/misc/*.ko; do
            ${lib.getExe pkgs.buildPackages.kmodigest} "$ko"
          done
        '';
    });
  });
  boot.consoleLogLevel = 0;
  boot.kernelParams = ["quiet" "udev.log_level=3" "vfio-pci.ids=1002:164e,1002:1640"];
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

  # Bridge br0 over eno1 so VMs (virt-manager → "Bridge device: br0") get an IP
  # straight from the home router instead of libvirt NAT.
  networking.networkmanager.ensureProfiles.profiles = {
    br0 = {
      connection = {
        id = "br0";
        type = "bridge";
        interface-name = "br0";
        autoconnect-slaves = 1;
      };
      bridge.stp = false;
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
    br0-eno1 = {
      connection = {
        id = "br0-eno1";
        type = "ethernet";
        interface-name = "eno1";
        master = "br0";
        slave-type = "bridge";
      };
    };
  };

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

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.zerotierone = {
    enable = true;
    joinNetworks = [
      "8d1c312afa14c104"
    ];
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

  # Docker loads br_netfilter, which makes the host firewall filter bridged VM
  # traffic (breaks inbound to the malware-lab VMs, and the host sees their packets).
  boot.kernelModules = ["br_netfilter"];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
  };

  virtualisation.vmware.host.enable = true;

  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.swtpm.enable = true;
  virtualisation.libvirtd.onShutdown = "shutdown";
  virtualisation.libvirtd.hooks.qemu.igpu-reset = pkgs.writeShellScript "igpu-reset" ''
    export PATH=${lib.makeBinPath [pkgs.coreutils pkgs.util-linux]}
    [ "$1" = malware-win11 ] && [ "$2" = release ] && [ "$3" = end ] || exit 0
    gpu=0000:0d:00.0
    audio=0000:0d:00.1
    rebind() {
      dev=/sys/bus/pci/devices/$1
      [ -e $dev/driver ] && echo $1 > $dev/driver/unbind
      echo $2 > $dev/driver_override
      echo $1 > /sys/bus/pci/drivers_probe
    }
    rebind $gpu amdgpu
    for _ in $(seq 30); do
      [ "$(basename "$(readlink /sys/bus/pci/devices/$gpu/driver)")" = amdgpu ] && break
      sleep 1
    done
    sleep 3
    rebind $gpu vfio-pci
    rebind $audio vfio-pci
    logger -t igpu-reset "iGPU now on $(basename "$(readlink /sys/bus/pci/devices/$gpu/driver)")"
  '';
  # amdgpu init resets the iGPU between guest runs; keep it out of the desktop seat meanwhile
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNELS=="0000:0d:00.0", TAG-="seat", TAG-="master-of-seat", TAG-="uaccess", ENV{ID_SEAT}="seat-igpu"
  '';
  # iGPU (and its HDMI audio) is passed through to malware-win11
  boot.initrd.kernelModules = ["vfio_pci" "vfio" "vfio_iommu_type1"];
  programs.virt-manager.enable = true;

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

  services.syncthing = {
    enable = true;
    user = "lunobe";
    dataDir = "/home/lunobe";
    configDir = "/home/lunobe/.config/syncthing";
    openDefaultPorts = true;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices = {
        potato = {
          id = "443ROIT-5VQ553Y-QLT3K33-HFCLH2K-PLYWTAQ-K4YY2G7-W6DVFE6-CZVFIQH";
          addresses = ["tcp://lunobe.xyz:22000" "tcp://10.100.102.55:22000" "dynamic"];
        };
        phone.id = "7BBAYUA-EEBULTS-B566YE7-4XIULJX-RF2ZFBO-B4VQWFY-QB43K43-FAF2EQX";
      };
      folders = {
        dreamlog = {
          path = "/home/lunobe/Documents/My awesome vault/dreamlog";
          devices = ["potato" "phone"];
        };
        diary = {
          path = "/home/lunobe/Documents/My awesome vault/diary";
          devices = ["potato" "phone"];
        };
      };
    };
  };

  # --- users ---

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    description = "Lunobe";
    hashedPasswordFile = config.age.secrets.userPassword.path;
    extraGroups = ["networkmanager" "wheel" "docker" "libvirtd"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB6HS+1ewVfU4Mm+L68yT4TdxhJQSWKiRCXHIXUvA87E u0_a554@localhost"
    ];
  };
}
