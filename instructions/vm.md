# What kind of system is this with VMs

The machine runs VMware Workstation (`virtualisation.vmware.host.enable`), and the VMs themselves live in `~/vmware`. None of the actual VM configuration - disks, settings, snapshots inside VMware - is declared in the flake, all of that is done by hand through the GUI. The flake is only responsible for `~/vmware` existing on disk at all, as its own btrfs subvolume (`@vmware`, alongside `@`, `@home`, `@snapshots`), mounted in configuration.nix.

Backups go through `nx vm push` / `nx vm pull` / `nx vm log` / `nx vm del <id>`, using restic against a repo on Cloudflare R2. `push` first takes a read-only snapshot of `@vmware` (so VMware doesn't need to be stopped), backs up that snapshot, then deletes it. `pull` with no argument restores the latest backup, or you can pass a specific snapshot id from `nx vm log`; `--delete` actually removes files that aren't in the backup, not just adds new ones.

Because restic does content-defined chunking, a repeat `push` only uploads the blocks that actually changed, even inside one large `.vmdk`.

Access to R2 is backed by two agenix secrets: `r2Credentials` (keys/endpoint/bucket) and `resticPassword` (the password encrypting the restic repo itself, a random value nobody ever types). The bucket and the token for it are set up by hand in Cloudflare, none of that can be reproduced from this repo, so if you're rebuilding this from scratch you need the bucket to already exist before `r2Credentials` means anything.

There's no "keep the last N backups" retention, restic's repo only grows, old backups have to be cleaned up manually with `nx vm del`.
