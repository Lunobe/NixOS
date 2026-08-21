{...}: {
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -g fish_greeting
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

      # -- eza aliases --

      # basic listings
      ls = "eza"; # standard list
      l = "eza -1"; # one column
      la = "eza -1a"; # one column with hidden files
      ll = "eza -l"; # long format
      lla = "eza -la"; # long format with hidden files

      # filtered listings
      ld = "eza -D"; # directories only
      lld = "eza -lD"; # long format, directories only
      lf = "eza -f"; # files only
      llf = "eza -lf"; # long format, files only

      # sort variants
      lsz = "eza -l --sort=size"; # sort by size
      lsx = "eza -l --sort=extension"; # sort by extension
      ltm = "eza -l --sort=modified"; # sort by modified time
      lcr = "eza -l --sort=created"; # sort by created time

      # git-aware
      lgit = "eza -l --git"; # show git status
      lx = "eza -lbhHigUmuS --git"; # extended info with git

      # tree
      lt = "eza --tree --level=3"; # tree, depth 3 by default
      lta = "eza -a --tree --level=3"; # tree with hidden files, depth 3
      llt = "eza -l --tree --level=3"; # long tree, depth 3
      llta = "eza -la --tree --level=3"; # long tree with hidden files, depth 3
    };
  };

  programs.eza = {
    enable = true;
    icons = "auto";
    extraOptions = [
      "--group-directories-first"
    ];
  };
}
