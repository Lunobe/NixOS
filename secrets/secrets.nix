# `lunobe` is one shared passphrase-protected identity, reused across every
# machine (not "the primary of several"). To give a machine its own identity
# instead of sharing that passphrase:
#   1. generate a keypair there: age-keygen -o identity.txt (prints "age1...")
#   2. add it below: secondMachine = "age1...";
#   3. append it to the publicKeys of the secrets that machine needs, e.g.
#      "ssh-hosts.age".publicKeys = [lunobe secondMachine];
#   4. re-encrypt those secrets — editing this file alone doesn't touch
#      existing ciphertext
let
  lunobe = "age1ww58walst59sadpszs7mh6ktwvy6q3ad7seu4aw3ml2cj0cvha2q0eyln3";
in {
  "user-password.age".publicKeys = [lunobe];
  "ssh-hosts.age".publicKeys = [lunobe];
  "obs-websocket-password.age".publicKeys = [lunobe];
  "ssh-private-key.age".publicKeys = [lunobe];
  "r2-credentials.age".publicKeys = [lunobe];
  "restic-password.age".publicKeys = [lunobe];
  "gh-token.age".publicKeys = [lunobe];
  "zerotier-network.age".publicKeys = [lunobe];
  "syncthing-config.age".publicKeys = [lunobe];
}
