#!/usr/bin/env bash
# Installer for https://github.com/Lunobe/NixOS — Lunobe's
# personal machine, not a general-purpose template. See the warning at
# the top of README.md.
#
# Two modes, chosen interactively at the top:
#   - fresh install: run this on a NixOS installer (live) image with network
#     access. Partitions disk(s), creates the Btrfs pool and subvolumes (or
#     a single ext4 partition), then nixos-installs this flake straight in —
#     no separate reboot-and-rerun needed, everything below just operates on
#     /mnt-prefixed paths until the very last step's reboot.
#   - repo-only (the historical behavior): run this on an *already*
#     nixos-install'd, booted system (disk partitioned, @/@home Btrfs
#     subvolumes created) with network access. Clones the repo into
#     /etc/nixos and takes it from there with nixos-rebuild switch.
# Either way this is a convenience wrapper around exactly the steps the
# README's "Installation" section describes, not a different path. Read it
# before piping it into bash if you'd rather not take that on faith.
set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes"

REPO_HTTPS="https://github.com/Lunobe/NixOS"
REPO_SSH="git@github.com:Lunobe/NixOS.git"

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

step "NixOS installer"

read -rp "Perform a fresh NixOS install (partition disk(s), create the Btrfs pool, nixos-install) instead of installing the repo onto an already-installed system? [y/N] " FRESH_INSTALL
case "$FRESH_INSTALL" in
  y|Y|yes|Yes|YES) FRESH_INSTALL=true ;;
  *) FRESH_INSTALL=false ;;
esac

if [ "$FRESH_INSTALL" = true ]; then
  TARGET=/mnt/etc/nixos
  ROOT_PREFIX=/mnt
else
  TARGET=/etc/nixos
  ROOT_PREFIX=""
fi

if [ "$FRESH_INSTALL" = true ]; then
  step "Disk layout"
  sudo umount -R /mnt 2>/dev/null || true
  echo "Current block devices:"
  lsblk -f
  echo

  read -rp "Create the pool across two disks (raid1 metadata)? [Y/n] " MULTI_DISK
  case "$MULTI_DISK" in
    n|N|no|No|NO) MULTI_DISK=false ;;
    *) MULTI_DISK=true ;;
  esac

  read -rp "Primary disk — must be typed explicitly (e.g. /dev/nvme0n1 or a UUID), THIS WILL BE WIPED: " DISK1
  if [ -z "$DISK1" ]; then
    echo "A disk must be specified — aborting." >&2
    exit 1
  fi
  [[ "$DISK1" == /dev/* ]] || DISK1="/dev/disk/by-uuid/$DISK1"

  if [ "$MULTI_DISK" = true ]; then
    read -rp "Second disk — must be typed explicitly, THIS WILL BE WIPED: " DISK2
    if [ -z "$DISK2" ]; then
      echo "A second disk must be specified for a multi-disk pool — aborting." >&2
      exit 1
    fi
    [[ "$DISK2" == /dev/* ]] || DISK2="/dev/disk/by-uuid/$DISK2"
    read -rp "Pool label [mypool]: " POOL_LABEL
    POOL_LABEL="${POOL_LABEL:-mypool}"
  fi

  read -rp "Filesystem for the pool — btrfs or ext4 [btrfs]: " POOL_FS
  POOL_FS="${POOL_FS:-btrfs}"
  if [ "$POOL_FS" != btrfs ] && [ "$POOL_FS" != ext4 ]; then
    echo "Unknown filesystem '$POOL_FS' — must be btrfs or ext4." >&2
    exit 1
  fi

  read -rp "EFI system partition size [512MiB]: " ESP_SIZE
  ESP_SIZE="${ESP_SIZE:-512MiB}"

  SUBVOLS=()
  if [ "$POOL_FS" = btrfs ]; then
    read -rp "Change the default subvolume layout (@home, @nix, @home-snapshots, @snapshots)? [y/N] " CHANGE_LAYOUT
    case "$CHANGE_LAYOUT" in
      y|Y|yes|Yes|YES)
        echo 'Enter subvolumes as "@name /mount/point", one per line. Type "Done" when finished.'
        echo "(@ itself is always created and mounted at / — don't list it.)"
        while true; do
          read -rp "> " LAYOUT_LINE
          if [ "$LAYOUT_LINE" = "Done" ]; then
            break
          fi
          if [ -n "$LAYOUT_LINE" ]; then
            SUBVOLS+=("$LAYOUT_LINE")
          fi
        done
        ;;
      *)
        SUBVOLS=("@home /home" "@nix /nix" "@home-snapshots /home/.snapshots" "@snapshots /.snapshots")
        ;;
    esac
  fi

  echo
  echo "About to WIPE and partition:"
  echo "  Disk 1: $DISK1"
  if [ "$MULTI_DISK" = true ]; then
    echo "  Disk 2: $DISK2 (pool label: $POOL_LABEL)"
  fi
  echo "  Filesystem: $POOL_FS"
  if [ "$POOL_FS" = btrfs ]; then
    echo "  Subvolumes: @ -> /"
    for s in "${SUBVOLS[@]}"; do
      echo "              $s"
    done
  fi
  echo
  read -rp "Type ERASE to continue: " CONFIRM_ERASE
  if [ "$CONFIRM_ERASE" != "ERASE" ]; then
    echo "Aborted."
    exit 1
  fi

  part_suffix() {
    case "$1" in
      *nvme*|*mmcblk*) echo p ;;
      *) echo ;;
    esac
  }

  step "Partitioning $DISK1"
  sudo parted "$DISK1" --script mklabel gpt \
    mkpart ESP fat32 1MiB "$ESP_SIZE" set 1 esp on \
    mkpart primary "$POOL_FS" "$ESP_SIZE" 100%
  SFX=$(part_suffix "$DISK1")
  EFI_PART="${DISK1}${SFX}1"
  POOL_PART="${DISK1}${SFX}2"
  sudo mkfs.fat -F32 -n EFI "$EFI_PART"

  if [ "$POOL_FS" = btrfs ]; then
    if [ "$MULTI_DISK" = true ]; then
      sudo mkfs.btrfs -f -d single -m raid1 "$POOL_PART" "$DISK2" --label "$POOL_LABEL"
    else
      sudo mkfs.btrfs -f "$POOL_PART"
    fi

    sudo mount "$POOL_PART" /mnt
    sudo btrfs subvolume create /mnt/@
    for s in "${SUBVOLS[@]}"; do
      sudo btrfs subvolume create "/mnt/${s%% *}"
    done
    sudo umount /mnt

    # compress=zstd here (not just later in hardware-configuration.nix) means
    # everything nixos-install is about to write — the whole store closure —
    # lands compressed the first time, instead of needing a separate
    # recompress pass afterward like the repo-only path does (there, the
    # base subvolumes were already populated by an earlier manual install
    # that didn't set this, so recompressing after the fact is the only option)
    sudo mount -o subvol=@,compress=zstd "$POOL_PART" /mnt
    for s in "${SUBVOLS[@]}"; do
      name="${s%% *}"
      mp="${s#* }"
      sudo mkdir -p "/mnt${mp}"
      sudo mount -o "subvol=$name,compress=zstd" "$POOL_PART" "/mnt${mp}"
    done
    sudo mkdir -p /mnt/boot
    sudo mount "$EFI_PART" /mnt/boot

    # feeds the existing "Btrfs subvolumes for snapshots and the VM
    # library" step below — its idempotency check means it'll skip
    # whatever we already created here and only actually create @vmware
    BTRFS_PART="$POOL_PART"
    BTRFS_PART_INPUT="$BTRFS_PART"
  else
    sudo mkfs.ext4 -F "$POOL_PART"
    sudo mount "$POOL_PART" /mnt
    sudo mkdir -p /mnt/boot
    sudo mount "$EFI_PART" /mnt/boot
    echo "ext4 chosen — no subvolumes, no snapshots, no VM library support (those all assume Btrfs); snapper and 'nx vm' won't work until you switch to Btrfs by hand."
    BTRFS_PART_INPUT=""
  fi
fi

step "Cloning repository"
CLONE_DIR=$(mktemp -d)
nix shell nixpkgs#git -c git clone --quiet "$REPO_HTTPS" "$CLONE_DIR"
sudo mkdir -p "$TARGET"
nix shell nixpkgs#rsync -c sudo rsync -a --delete "$CLONE_DIR"/ "$TARGET"/
rm -rf "$CLONE_DIR"
sudo chown -R "$(id -u):$(id -g)" "$TARGET"

# read back out of the flake we just cloned instead of hardcoding it here
# too — flake.nix is the single source of truth for this
USERNAME=$(sed -n 's/^ *username = "\(.*\)";.*/\1/p' "$TARGET/flake.nix" | head -n1)
if [ -z "$USERNAME" ]; then
  echo "Could not find 'username = \"...\";' in $TARGET/flake.nix — aborting." >&2
  exit 1
fi

step "Btrfs subvolumes for snapshots and the VM library"
if [ -z "${BTRFS_PART_INPUT+x}" ]; then
  cat <<'EOF'
Creates @snapshots and @home-snapshots for the snapper config, and @vmware
for the VMware VM library (mounted at ~/vmware by configuration.nix). This
needs your Btrfs partition — this script will not guess it, since getting
this wrong touches disk layout. Below is your current block device list;
leave blank to skip this step entirely (you'll need to create the
subvolumes and their hardware-configuration.nix entries by hand later).
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
  fi
fi

if [ -n "$BTRFS_PART_INPUT" ]; then
  sudo mkdir -p /mnt/btrfs-root
  sudo mount -t btrfs -o subvolid=5 "$BTRFS_PART" /mnt/btrfs-root
  cleanup_btrfs_mount() {
    sudo umount /mnt/btrfs-root 2>/dev/null || true
    sudo rmdir /mnt/btrfs-root 2>/dev/null || true
  }
  trap cleanup_btrfs_mount EXIT

  sudo rmdir "$ROOT_PREFIX/.snapshots" "$ROOT_PREFIX/home/.snapshots" 2>/dev/null || true
  for subvol in @snapshots @home-snapshots @vmware; do
    if sudo btrfs subvolume show "/mnt/btrfs-root/$subvol" >/dev/null 2>&1; then
      echo "/mnt/btrfs-root/$subvol already exists — skipping."
    else
      sudo btrfs subvolume create "/mnt/btrfs-root/$subvol"
    fi
  done
  sudo chown "$(id -u):$(id -g)" /mnt/btrfs-root/@vmware

  cleanup_btrfs_mount
  trap - EXIT
else
  echo "Skipped — create @snapshots/@home-snapshots/@vmware manually before deploying."
fi

step "hardware-configuration.nix"
# Always regenerated for this machine's actual disk UUIDs — the repo's copy
# is machine-specific to whichever box it was last generated on and is
# never usable as-is on a fresh install (see the file's own "Do not modify"
# header). nixos-generate-config only picks up filesystems that are
# currently mounted, so @snapshots/@home-snapshots/@vmware (not mounted
# anywhere until configuration.nix declares them) are added below by hand,
# reusing the Btrfs partition's UUID and the same mount options as the
# base subvolumes it did detect (/, /nix, /home).
NIXOS_GENERATE_CONFIG_ARGS=()
if [ -n "$ROOT_PREFIX" ]; then
  NIXOS_GENERATE_CONFIG_ARGS+=(--root "$ROOT_PREFIX")
fi
nixos-generate-config "${NIXOS_GENERATE_CONFIG_ARGS[@]}" --show-hardware-config | sudo tee "$TARGET/hardware-configuration.nix" >/dev/null
sudo chown "$(id -u):$(id -g)" "$TARGET/hardware-configuration.nix"

if [ -n "$BTRFS_PART_INPUT" ]; then
  BTRFS_UUID=$(sudo blkid -o value -s UUID "$BTRFS_PART")
  # rotational status is per-device, not a property of Btrfs itself — the
  # "ssd" mount option disables optimizations meant for spinning disks, so
  # it's only correct to add it if $BTRFS_PART actually reports non-rotational
  if [ "$(lsblk -dno ROTA "$BTRFS_PART" 2>/dev/null)" = "1" ]; then
    BTRFS_IS_SSD=false
  else
    BTRFS_IS_SSD=true
  fi

  emit_fs_block() {
    local mountpoint="$1" subvol="$2"
    # nixos-generate-config already wrote a fileSystems entry for this
    # mountpoint if it was actually mounted when it ran — true for
    # @snapshots/@home-snapshots in fresh-install mode specifically, since
    # Phase 0 mounts the whole chosen layout at its real final paths before
    # this step, unlike repo-only (where they only exist under the
    # transient /mnt/btrfs-root subvolid=5 view) or @vmware (never mounted
    # at its final path here either way). Appending a second definition for
    # an already-declared mountpoint is a hard Nix eval error, not a warning.
    if grep -qF "fileSystems.\"$mountpoint\"" "$TMP_HW"; then
      echo "$mountpoint is already declared (nixos-generate-config found it mounted) — not duplicating."
      return 0
    fi
    {
      echo
      echo "  fileSystems.\"$mountpoint\" = {"
      echo "    device = \"/dev/disk/by-uuid/$BTRFS_UUID\";"
      echo "    fsType = \"btrfs\";"
      echo "    options = ["
      echo "      \"subvol=$subvol\""
      if [ "$BTRFS_IS_SSD" = true ]; then
        echo "      \"ssd\""
      fi
      echo "      \"compress=zstd\""
      echo "      \"noatime\""
      echo "      \"space_cache=v2\""
      echo "    ];"
      echo "  };"
    } >>"$TMP_HW"
  }

  TMP_HW=$(mktemp)
  head -n -1 "$TARGET/hardware-configuration.nix" >"$TMP_HW"
  emit_fs_block "/.snapshots" "@snapshots"
  emit_fs_block "/home/.snapshots" "@home-snapshots"
  emit_fs_block "/home/$USERNAME/vmware" "@vmware"
  echo "}" >>"$TMP_HW"

  mv "$TMP_HW" "$TARGET/hardware-configuration.nix"
  echo "Added @snapshots/@home-snapshots/@vmware entries to hardware-configuration.nix (ssd option: $BTRFS_IS_SSD)."
else
  echo "No Btrfs subvolumes were created — hardware-configuration.nix has only the base filesystems; add @snapshots/@home-snapshots/@vmware entries by hand if you create those subvolumes later."
fi

step "Secrets identity"
echo "Enter the passphrase for secrets/identity.txt.age:"
nix shell nixpkgs#age -c age -d -o /tmp/agenix-identity.txt "$TARGET/secrets/identity.txt.age"
sudo install -D -m 600 -o root -g root /tmp/agenix-identity.txt "$ROOT_PREFIX/var/lib/agenix-bootstrap/identity.txt"
shred -u /tmp/agenix-identity.txt

if [ "$FRESH_INSTALL" = true ]; then
  step "Installing"
  sudo nixos-install --root /mnt --flake "$TARGET#nixos" --no-root-passwd --option experimental-features "nix-command flakes"
else
  step "Building and switching"
  sudo nixos-rebuild switch --flake "$TARGET#nixos" --option experimental-features "nix-command flakes"
fi

NIX_STORE_REMOUNTED_RW=false
if [ "$FRESH_INSTALL" = true ]; then
  step "Recompressing existing data with zstd"
  echo "Skipped — Phase 0 mounted the pool with compress=zstd before nixos-install wrote anything, so everything (the whole store closure included) already landed compressed. Nothing to redo here."
else
  step "Recompressing existing data with zstd"
  cat <<'EOF'
compress=zstd only affects newly written data — anything already on these
subvolumes from before this point (the initial nixos-install closure,
mainly) stays uncompressed until forced. Defragmenting with -czstd
rewrites it in place. /nix/store is normally mounted read-only once the
system has booted for real, so it's remounted read-write for this if that
applies; the final reboot restores it to read-only. Every path below is
checked first and skipped (not a hard failure) if it isn't actually on
Btrfs — e.g. a layout without a separate @nix or @home subvolume, or no
Btrfs at all.
EOF

  is_btrfs() {
    [ "$(findmnt -no FSTYPE --target "$1" 2>/dev/null)" = "btrfs" ]
  }
  defrag_if_btrfs() {
    if is_btrfs "$1"; then
      sudo btrfs filesystem defragment -r -v -czstd "$1"
    else
      echo "$1 is not on Btrfs — skipping."
    fi
  }

  for path in "$ROOT_PREFIX/" "$ROOT_PREFIX/nix" "$ROOT_PREFIX/home"; do
    defrag_if_btrfs "$path"
  done

  if mountpoint -q "$ROOT_PREFIX/nix/store"; then
    if is_btrfs "$ROOT_PREFIX/nix/store"; then
      sudo mount -o remount,rw "$ROOT_PREFIX/nix/store"
      NIX_STORE_REMOUNTED_RW=true
      sudo btrfs filesystem defragment -r -v -czstd "$ROOT_PREFIX/nix/store"
    else
      echo "$ROOT_PREFIX/nix/store is a separate mount but not Btrfs — skipping."
    fi
  else
    echo "$ROOT_PREFIX/nix/store is not a separate mount — already covered by the $ROOT_PREFIX/nix or $ROOT_PREFIX/ pass above."
  fi

  if [ -n "$BTRFS_PART_INPUT" ]; then
    for path in "$ROOT_PREFIX/.snapshots" "$ROOT_PREFIX/home/.snapshots" "$ROOT_PREFIX/home/$USERNAME/vmware"; do
      defrag_if_btrfs "$path"
    done
  fi
fi

step "Git"
cd "$TARGET"
nix shell nixpkgs#git -c git remote set-url origin "$REPO_SSH"

step "Done"
if [ "$FRESH_INSTALL" = true ]; then
  echo "Base system installed. A reboot is required to actually boot into it."
  read -rp "Reboot now? [Y/n] " DO_REBOOT
  case "$DO_REBOOT" in
    n|N|no|No|NO) echo "Remember to reboot to boot into the new system." ;;
    *) sudo reboot ;;
  esac
elif [ "$NIX_STORE_REMOUNTED_RW" = true ]; then
  read -rp "/nix/store is currently read-write from the recompression step above — reboot now to restore it to read-only? [Y/n] " DO_REBOOT
  case "$DO_REBOOT" in
    n|N|no|No|NO) echo "Remember to reboot before relying on /nix/store being read-only." ;;
    *) sudo reboot ;;
  esac
else
  read -rp "Reboot now? [y/N] " DO_REBOOT
  case "$DO_REBOOT" in
    y|Y|yes|Yes|YES) sudo reboot ;;
  esac
fi
