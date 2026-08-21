# How are secrets handled here

Secrets are agenix, encrypted at rest in `secrets/*.age`. `secrets/secrets.nix` is just a map of "which file can be decrypted by which age key" - right now it's a single passphrase-protected identity (`lunobe`), reused across machines.

Separately there's `secrets/identity.txt.age`, the root identity itself, also passphrase-protected, so it's fine to commit and publish. The decrypted version only ever exists in one place, `/var/lib/agenix-bootstrap/identity.txt` on the running machine. It gets put there by hand via `install.sh` during first setup and never ends up in `/nix/store` or in git.

If you're setting up a new machine and want it to have access to existing secrets, editing `secrets.nix` alone isn't enough - it doesn't touch already-encrypted ciphertext. You need to generate the machine its own age keypair, add the public key to `secrets.nix`, append it to the relevant secret's `publicKeys`, and re-encrypt that secret.

To edit a secret, `nx secret <name>` decrypts it, opens it in your editor, and re-encrypts it afterward. That needs sudo plus the bootstrap identity present on the machine.

Decrypted secret contents (`/run/agenix/*`, `/var/lib/agenix-bootstrap/identity.txt`) should never leave the machine, not in commits, not in command output, nowhere.
