{
  config,
  lib,
  pkgs,
  repoDir,
  ...
}: {
  xdg.configFile."fastfetch/config.jsonc".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/home/fastfetch/config.jsonc";

  # -s just stops this from flashing colors during deploy; the runtime wal
  # call below omits it since it should recolor the terminal live.
  home.activation.warmFastfetchWalCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run bash -c '
      ${pkgs.findutils}/bin/find "${repoDir}/modules/home/fastfetch/images" -type f -print0 \
        | ${pkgs.findutils}/bin/xargs -0 -P"$(${pkgs.coreutils}/bin/nproc)" -I{} \
          ${pkgs.pywal}/bin/wal -q -n -e -s -i {}
    ' || true
  '';

  programs.fish.interactiveShellInit = ''
    # config.jsonc's module colors are ANSI palette indices (0-15), not
    # fixed RGB, so recoloring kitty's palette via wal below recolors
    # fastfetch's output too, with no config.jsonc changes needed.
    set -l ff_logo (find "${repoDir}/modules/home/fastfetch/images" -type f | shuf -n 1)
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

  programs.fish.shellAliases.whichpic = "command cat ~/.cache/fastfetch/current_image";
}
