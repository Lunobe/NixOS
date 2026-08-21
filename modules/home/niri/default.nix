{
  config,
  repoDir,
  ...
}: {
  xdg.configFile."niri".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/modules/home/niri/config";
}
