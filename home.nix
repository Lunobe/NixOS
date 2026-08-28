{
  config,
  lib,
  pkgs,
  repoDir,
  username,
  ...
}: let
  niriWalTheme = pkgs.writeShellApplication {
    name = "niri-wal-theme";
    runtimeInputs = [pkgs.pywal pkgs.jq pkgs.niri pkgs.gnugrep pkgs.gnused pkgs.awww pkgs.imagemagick];
    text = ''
      wallpaper=$(grep '^wallpaper' ~/.config/waypaper/config.ini | cut -d'=' -f2- | xargs)
      wallpaper=''${wallpaper/#\~/$HOME}
      [ -f "$wallpaper" ] || exit 0

      wal -q -n -e -s -i "$wallpaper"

      blurred=~/.cache/niri-wal-theme/blurred.png
      mkdir -p "$(dirname "$blurred")"
      magick "$wallpaper" -resize 25% -blur 0x12 "$blurred"
      awww img -n backdrop --resize crop "$blurred"

      hex_to_rgba() {
        local hex=''${1#\#} alpha=''${2:-1}
        printf 'rgba(%d, %d, %d, %s)' \
          "$((16#''${hex:0:2}))" "$((16#''${hex:2:2}))" "$((16#''${hex:4:2}))" "$alpha"
      }

      colors=~/.cache/wal/colors.json
      active=$(hex_to_rgba "$(jq -r '.colors.color1' "$colors")")
      inactive=$(hex_to_rgba "$(jq -r '.colors.color8' "$colors")")
      shadow=$(hex_to_rgba "$(jq -r '.special.background' "$colors")" 0.6)

      out=~/.cache/niri-wal-theme/colors.kdl
      mkdir -p "$(dirname "$out")"
      tmp_out="$out.tmp.$$"
      cat >"$tmp_out" <<EOF
      layout {
          border {
              active-color "$active"
              inactive-color "$inactive"
          }
          shadow {
              color "$shadow"
          }
      }
      EOF
      mv "$tmp_out" "$out"

      niri msg action load-config-file || true
    '';
  };
in {
  imports = [
    ./modules/packages.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  # --- environment ---

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # --- git ---

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Lunobe";
        email = "257240031+Lunobe@users.noreply.github.com";
      };
      init = {
        defaultBranch = "main";
      };
      safe = {
        directory = repoDir;
      };
    };
  };

  # --- editor ---

  programs.neovim = {
    enable = true;

    viAlias = true;
    vimAlias = true;

    defaultEditor = true;

    initLua = ''
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.keymap = "russian-jcukenwin"
      vim.opt.iminsert = 0
      vim.opt.imsearch = 0
      vim.opt.langmap = "ФИСВУАПРШОЛДЬТЩЗЙКЫЕГМЦЧНЯ;ABCDEFGHIJKLMNOPQRSTUVWXYZ,фисвуапршолдьтщзйкыегмцчня;abcdefghijklmnopqrstuvwxyz"

      vim.keymap.set("n", "<Tab>", ":bnext<CR>", { silent = true })
      vim.keymap.set("n", "<S-Tab>", ":bprevious<CR>", { silent = true })
    '';
  };

  # --- kitty ---

  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font Mono";
      size = 13;
    };

    themeFile = "Catppuccin-Mocha";

    settings = {
      # background_blur is a no-op without compositor blur-protocol support.
      background_opacity = 0.75;
      dynamic_background_opacity = true;
      background_blur = 13;

      # cursor trail
      cursor_shape = "beam";
      cursor_trail = 3;
      cursor_trail_decay_fast = 0.1;
      cursor_trail_decay_slow = 0.2;
      cursor_trail_start_threshold = 2;

      # layout
      window_padding_width = 10;
      hide_window_decorations = true;
      confirm_os_window_close = 0;
      remember_window_size = false;
      initial_window_width = "120c";
      initial_window_height = "35c";

      # tab bar
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";

      # misc
      enable_audio_bell = false;
      # -1 = unlimited — kitty keeps it in memory, so a long session can
      # grow RAM usage noticeably.
      scrollback_lines = -1;

      # lets `kitty @ get-text` (save-scrollback) talk to the running
      # instance without a configured listen_on socket.
      allow_remote_control = "yes";
    };
  };

  # --- shell ---

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -g fish_greeting

      pay-respects fish | source

      if test -r /run/agenix/ghToken
          set -gx GH_TOKEN (cat /run/agenix/ghToken)
      end

      # config.jsonc's module colors are ANSI indices, not fixed RGB, so
      # recoloring kitty's palette via wal below recolors fastfetch too.
      set -l ff_logo (find "${repoDir}/modules/fastfetch/images" -type f | shuf -n 1)
      if test -n "$ff_logo"
          wal -q -n -e -i "$ff_logo"
          command cat ~/.cache/wal/sequences
          fastfetch --logo "$ff_logo"
          mkdir -p ~/.cache/fastfetch
          basename "$ff_logo" >~/.cache/fastfetch/current_image
      else
          fastfetch
      end
    '';

    shellAliases = {
      svim = "sudo -E vim";
      svi = "sudo -E vi";
      cat = "bat -P --theme zenburn";
      # plain `clear` leaves scrollback intact in kitty; \e[3J erases it too.
      clear = "command clear; printf '\\e[3J'";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      c = "clear";
      cl = "clear";
      whichpic = "command cat ~/.cache/fastfetch/current_image";
      tb = "nc termbin.com 9999";
      "7z" = "7zz";

      # --- eza aliases ---

      # basic listings
      ls = "eza";
      l = "eza -1";
      la = "eza -1a";
      ll = "eza -l";
      lla = "eza -la";

      # filtered listings
      ld = "eza -D";
      lld = "eza -lD";
      lf = "eza -f";
      llf = "eza -lf";

      # sort variants
      lsz = "eza -l --sort=size";
      lsx = "eza -l --sort=extension";
      ltm = "eza -l --sort=modified";
      lcr = "eza -l --sort=created";

      # git-aware
      lgit = "eza -l --git";
      lx = "eza -lbhHigUmuS --git";

      # tree
      lt = "eza --tree --level=3";
      lta = "eza -a --tree --level=3";
      llt = "eza -l --tree --level=3";
      llta = "eza -la --tree --level=3";
    };

    functions = {
      # "-" writes to stdout instead of the default ~/kitty-scrollback.txt,
      # e.g. `save-scrollback - | tb`.
      save-scrollback = ''
        set -q argv[1]; or set argv ~/kitty-scrollback.txt
        if test "$argv[1]" = -
            kitty @ get-text --extent=all
        else
            kitty @ get-text --extent=all > $argv[1]
        end
      '';
    };
  };

  programs.eza = {
    enable = true;
    icons = "auto";
    extraOptions = [
      "--group-directories-first"
    ];
  };

  # --- ssh ---

  services.ssh-agent.enable = true;

  home.file.".ssh/id_ed25519" = {
    source = config.lib.file.mkOutOfStoreSymlink "/run/agenix/sshPrivateKey";
    force = true;
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = ["/run/agenix/sshHosts"];
    settings = {
      "*" = {AddKeysToAgent = "yes";};
    };
  };

  # --- fastfetch ---

  xdg.configFile."fastfetch/config.jsonc" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/fastfetch/config.jsonc";
    force = true;
  };

  # -s stops this from flashing colors during deploy; the runtime wal call
  # above omits it since it should recolor the terminal live.
  home.activation.warmFastfetchWalCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run bash -c '
      ${pkgs.findutils}/bin/find "${repoDir}/modules/fastfetch/images" -type f -print0 \
        | ${pkgs.findutils}/bin/xargs -0 -P"$(${pkgs.coreutils}/bin/nproc)" -I{} \
          ${pkgs.pywal}/bin/wal -q -n -e -s -i {}
    ' || true
  '';

  # --- niri ---

  xdg.configFile."niri/config.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/niri/config.kdl";
    force = true;
  };

  home.packages = [niriWalTheme];

  home.activation.applyNiriWalTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${niriWalTheme}/bin/niri-wal-theme || true
  '';

  # --- obs-studio ---

  xdg.configFile."obs-studio" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/obs-studio";
    force = true;
  };

  # re-patched every activation since OBS can rewrite this file at runtime —
  # the agenix secret is the source of truth, not the file. config.json is
  # gitignored, so it won't exist until OBS has run once; skip the patch then.
  home.activation.obsWebsocketPassword = lib.hm.dag.entryAfter ["writeBoundary"] ''
    obsWebsocketConfig="${repoDir}/modules/obs-studio/plugin_config/obs-websocket/config.json"
    obsWebsocketSecret="/run/agenix/obsWebsocketPassword"
    if [ -f "$obsWebsocketConfig" ]; then
      if [ ! -r "$obsWebsocketSecret" ]; then
        echo "obsWebsocketPassword: $obsWebsocketSecret is unreadable — leaving $obsWebsocketConfig untouched." >&2
      elif ! ${pkgs.jq}/bin/jq empty "$obsWebsocketConfig" 2>/dev/null; then
        echo "obsWebsocketPassword: $obsWebsocketConfig is not valid JSON — leaving it untouched." >&2
      elif [[ -v DRY_RUN ]]; then
        echo "would update server_password in $obsWebsocketConfig"
      else
        pw="$(cat "$obsWebsocketSecret")"
        ${pkgs.jq}/bin/jq --arg pw "$pw" '.server_password = $pw' \
          "$obsWebsocketConfig" > "$obsWebsocketConfig.new"
        mv "$obsWebsocketConfig.new" "$obsWebsocketConfig"
      fi
    fi
  '';

  # --- swaync ---

  xdg.configFile."swaync" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/swaync";
    force = true;
  };

  # --- icons ---

  # Copied into the store, not symlinked like the rest of this file — Steam's
  # pressure-vessel sandbox replaces /etc, so a symlink to ${repoDir} would
  # resolve to nothing inside it and steamwebhelper crash-loops on launch.
  home.file.".local/share/icons".source = ./modules/user/icons;

  # --- wallpapers ---

  home.file."Pictures/Wallpapers" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/user/wallpapers";
    force = true;
  };

  # --- waypaper ---

  xdg.configFile."waypaper" = {
    source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/waypaper";
    force = true;
  };
}
