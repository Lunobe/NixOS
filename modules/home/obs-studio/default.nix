{
  config,
  lib,
  pkgs,
  repoDir,
  ...
}: {
  xdg.configFile."obs-studio".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/home/obs-studio/config";

  # re-patched on every activation since OBS can rewrite this file at
  # runtime; the agenix secret stays the source of truth, not the file.
  home.activation.obsWebsocketPassword = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${pkgs.jq}/bin/jq \
      --arg pw "$(cat /run/agenix/obsWebsocketPassword)" \
      '.server_password = $pw' \
      "${repoDir}/modules/home/obs-studio/config/plugin_config/obs-websocket/config.json" \
      > "${repoDir}/modules/home/obs-studio/config/plugin_config/obs-websocket/config.json.new"
    run mv "${repoDir}/modules/home/obs-studio/config/plugin_config/obs-websocket/config.json.new" \
      "${repoDir}/modules/home/obs-studio/config/plugin_config/obs-websocket/config.json"
  '';
}
