{
  repoDir,
  username,
  ...
}: {
  # identity.txt is a manually-bootstrapped decrypted copy that
  # never enters /nix/store or git; secrets/identity.txt.age is passphrase-
  # encrypted and safe to publish.
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
}
