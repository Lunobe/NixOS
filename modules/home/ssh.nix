{config, ...}: {
  services.ssh-agent.enable = true;

  # force=true replaces the plain file that lived here before this migration.
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
}
