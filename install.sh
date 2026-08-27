#!/usr/bin/env bash
# Installer for https://github.com/Lunobe/NixOS — Lunobe's
# personal machine, not a general-purpose template. See the warning at
# the top of README.md.
#
# Run on a freshly `nixos-install`'d system (disk partitioned, @/@home
# Btrfs subvolumes created, booted into that fresh system with network
# access). Does everything the README's "Installation" section describes,
# interactively — this script is a convenience wrapper around exactly
# those steps, not a different path. Read it before piping it into bash
# if you'd rather not take that on faith.
set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes"

REPO_HTTPS="https://github.com/Lunobe/NixOS"
REPO_SSH="git@github.com:Lunobe/NixOS.git"
TARGET=/etc/nixos

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

step "NixOS installer"

step "Cloning repository"
CLONE_DIR=$(mktemp -d)
nix shell nixpkgs#git -c git clone --quiet "$REPO_HTTPS" "$CLONE_DIR"
sudo mkdir -p "$TARGET"
sudo cp -r "$CLONE_DIR"/. "$TARGET"/
rm -rf "$CLONE_DIR"
sudo chown -R "$(id -u):$(id -g)" "$TARGET"

step "hardware-configuration.nix"
read -rp "Copy hardware-configuration.nix from repo to this machine? [Y/n] " KEEP_HW
case "$KEEP_HW" in
  n|N|no|No|NO)
    nixos-generate-config --show-hardware-config | sudo tee "$TARGET/hardware-configuration.nix" >/dev/null
    ;;
  *)
    echo "Keeping the version from the repo."
    ;;
esac

step "Btrfs subvolumes for snapshots and the VM library"
cat <<'EOF'
Creates @snapshots and @home-snapshots for the snapper config, and @vmware
for the VMware VM library (mounted at ~/vmware by configuration.nix). This
needs your Btrfs partition — this script will not guess it, since getting
this wrong touches disk layout. Below is your current block device list;
leave blank to skip this step entirely.
EOF
lsblk -f
echo
read -rp "Btrfs partition (UUID or /dev/x path): " BTRFS_PART_INPUT
if [ -n "$BTRFS_PART_INPUT" ]; then
  if [[ "$BTRFS_PART_INPUT" == /dev/* ]]; then
    BTRFS_PART="$BTRFS_PART_INPUT"
  else
    BTRFS_PART="/dev/disk/by-uuid/$BTRFS_PART_INPUT"
  fi
  if [ "$(sudo blkid -o value -s TYPE "$BTRFS_PART" 2>/dev/null)" != "btrfs" ]; then
    echo "'$BTRFS_PART' is not a Btrfs filesystem — pass the partition (e.g. /dev/sda2), not the whole disk." >&2
    exit 1
  fi
  sudo mkdir -p /mnt/btrfs-root
  sudo mount -t btrfs -o subvolid=5 "$BTRFS_PART" /mnt/btrfs-root
  sudo rmdir /.snapshots /home/.snapshots 2>/dev/null || true
  sudo btrfs subvolume create /mnt/btrfs-root/@snapshots
  sudo btrfs subvolume create /mnt/btrfs-root/@home-snapshots
  sudo btrfs subvolume create /mnt/btrfs-root/@vmware
  sudo chown "$(id -u):$(id -g)" /mnt/btrfs-root/@vmware
  sudo umount /mnt/btrfs-root
  sudo rmdir /mnt/btrfs-root
else
  echo "Skipped — create @snapshots/@home-snapshots/@vmware manually before deploying."
fi

step "Secrets identity"
echo "Enter the passphrase for secrets/identity.txt.age:"
nix shell nixpkgs#age -c age -d -o /tmp/agenix-identity.txt "$TARGET/secrets/identity.txt.age"
sudo install -D -m 600 -o root -g root /tmp/agenix-identity.txt /var/lib/agenix-bootstrap/identity.txt
shred -u /tmp/agenix-identity.txt

step "Building and switching"
sudo nixos-rebuild switch --flake "$TARGET#nixos" --option experimental-features "nix-command flakes"

step "Git"
cd "$TARGET"
nix shell nixpkgs#git -c git remote set-url origin "$REPO_SSH"

step "Done"
read -rp "Reboot now? [y/N] " DO_REBOOT
case "$DO_REBOOT" in
  y|Y|yes|Yes|YES) sudo reboot ;;
esac
