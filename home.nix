{
  repoDir,
  username,
  ...
}: {
  imports = [
    ./modules/home/packages.nix
    ./modules/home/fastfetch
    ./modules/home/shell.nix
    ./modules/home/obs-studio
    ./modules/home/ssh.nix
    ./modules/home/niri
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  # -- environment --

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # -- git --

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

  # -- editor --

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

  # -- kitty --

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
      scrollback_lines = 10000;
    };
  };
}
