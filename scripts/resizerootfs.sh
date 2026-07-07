#!/usr/bin/env bash
# Expand the rootfs partition + filesystem to fill the destination disk.
#
# Runs as a oneshot at every boot (idempotent — no-op once already at max).
# Why this exists: sled's stamp step dd's the L4T image onto the target NVMe
# bit-for-bit, so the GPT secondary header lands at the image's original
# end-of-image offset (~11 GB), leaving most of any larger destination disk
# invisible to the kernel. We:
#   1. Move the GPT secondary header to the actual disk end (sgdisk -e),
#      which on most layouts also extends the trailing partition into the
#      newly-visible space.
#   2. growpart as a follow-up in case sgdisk -e didn't grow the partition
#      (skipped if growpart isn't installed; ignored if it reports no changes).
#   3. resize2fs the ext4 filesystem online to match the new partition size.
#
# Detects the rootfs partition dynamically (findmnt + lsblk + sed on partnum)
# so the same script works for any disk layout — not just Jetson's partition 16.

set -e

ROOTPART=$(findmnt -no SOURCE /)
ROOTDEV="/dev/$(lsblk -no pkname "$ROOTPART")"
PARTNUM=$(printf %s "$ROOTPART" | sed -E 's|.*[^0-9]([0-9]+)$|\1|')

echo "resizerootfs: rootpart=$ROOTPART rootdev=$ROOTDEV partnum=$PARTNUM"

sgdisk -e "$ROOTDEV"
partprobe "$ROOTDEV" || true

if command -v growpart >/dev/null 2>&1; then
    growpart "$ROOTDEV" "$PARTNUM" || true
    partprobe "$ROOTDEV" || true
fi

resize2fs "$ROOTPART"
