#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run as root" >&2
    exit 1
fi

apt-get update -qq
apt-get install -y -qq cloud-guest-utils e2fsprogs gdisk util-linux

ROOT_MOUNT=$(findmnt -n -o SOURCE /)
TARGET_DEVICE="${1:-}"
PARTITION_NUM="${2:-}"

if [ -z "$TARGET_DEVICE" ]; then
    PARENT_DISK=$(lsblk -no PKNAME "$ROOT_MOUNT" | head -n1)
    if [ -z "$PARENT_DISK" ]; then
        PARENT_DISK=$(echo "$ROOT_MOUNT" | sed -E 's/[0-9]+$//')
    else
        PARENT_DISK="/dev/$PARENT_DISK"
    fi
    TARGET_DEVICE="$PARENT_DISK"
fi

if [ -z "$PARTITION_NUM" ]; then
    PARTITION_NUM=$(echo "$ROOT_MOUNT" | grep -o '[0-9]*$')
fi

echo "Target device: $TARGET_DEVICE partition $PARTITION_NUM"
df -h /

GROW_EXIT=0
growpart "$TARGET_DEVICE" "$PARTITION_NUM" || GROW_EXIT=$?

if [ "$GROW_EXIT" -ne 0 ] && [ "$GROW_EXIT" -ne 1 ]; then
    echo "growpart failed with exit code $GROW_EXIT" >&2
    exit "$GROW_EXIT"
fi

FSTYPE=$(findmnt -n -o FSTYPE /)
if [ "$FSTYPE" = "ext4" ] || [ "$FSTYPE" = "ext3" ]; then
    resize2fs "$ROOT_MOUNT"
elif [ "$FSTYPE" = "xfs" ]; then
    xfs_growfs /
fi

df -h /
echo "Storage expansion completed"
