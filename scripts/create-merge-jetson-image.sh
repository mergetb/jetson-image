#!/usr/bin/env bash

# Create a Jetson Orin Nano merge image and stamp a merge-known PARTUUID on
# the rootfs partition, so the testbed bootloader/initrd flow can reference it
# deterministically. Target is always the Jetson Orin Nano devkit on NVMe.

set -e

ROOT_PARTUUID="a0000000-0000-0000-0000-00000000000a"

# NVIDIA's jetson-disk-image-creator.sh accepts -d SD or USB only (no NVMe
# branch; the GPT layout is identical either way and is governed by the
# board's hard-coded `storage="sdcard"`). `-d USB` selects the external
# block device profile (BOOTDEV=sda1 baked into bootloader configs). Our
# PARTUUID rewrite below makes that value irrelevant at runtime — initramfs
# resolves PARTUUID against whichever device the rootfs lands on (NVMe in
# production).
printf "Creating merge image for Jetson Orin Nano (external block device profile; deploy target: NVMe)\n"
sudo ./jetson-disk-image-creator.sh -o jetson.img -b jetson-orin-nano-devkit -d USB

printf "Locating APP partition in jetson.img\n"
APP_PART=$(sgdisk -p jetson.img | awk '$NF == "APP" {print $1; exit}')
if [ -z "$APP_PART" ]; then
    printf "\e[31mCould not locate APP partition in jetson.img\e[0m\n"
    sgdisk -p jetson.img >&2
    exit 1
fi
printf "APP partition is #%s\n" "$APP_PART"

printf "Setting rootfs PARTUUID to %s\n" "$ROOT_PARTUUID"
sgdisk -u "${APP_PART}:${ROOT_PARTUUID}" jetson.img

printf "Mounting APP partition to update extlinux.conf\n"
LOOP_DEV=$(sudo losetup --show -f jetson.img)
sudo kpartx -av "$LOOP_DEV"
PART_DEV="/dev/mapper/$(basename "$LOOP_DEV")p${APP_PART}"

MNT=$(mktemp -d)
sudo mount "$PART_DEV" "$MNT"

EXTLINUX="$MNT/boot/extlinux/extlinux.conf"
if [ -f "$EXTLINUX" ]; then
    # Rewrite whatever root=<device> jetson-disk-image-creator.sh baked in to
    # our PARTUUID — making the kernel cmdline device-agnostic.
    sudo sed -i -E "s|root=[^[:space:]]+|root=PARTUUID=${ROOT_PARTUUID}|g" "$EXTLINUX"

    # Disable predictable network interface naming so eth0 is stable
    if ! grep -q 'net\.ifnames=0' "$EXTLINUX"; then
        sudo sed -i -E 's|^(\s*APPEND\s+)|\1net.ifnames=0 |' "$EXTLINUX"
    fi

    printf "Updated %s:\n" "$EXTLINUX"
    grep -E '^\s*APPEND' "$EXTLINUX" || true
else
    printf "\e[33mWarning: %s not found; skipping kernel cmdline rewrite\e[0m\n" "$EXTLINUX"
fi

# Extract kernel + initrd + dtb + extlinux.conf for kexec / network-boot
# scenarios (testbed nodes may boot these directly instead of from disk).
# These come straight out of the mounted APP partition, so they're the same
# files the on-disk install will boot.
printf "\n=== Extracting boot artifacts to boot-files/ ===\n"
sudo mkdir -p /jetson/boot-files
sudo cp -v "$MNT/boot/Image" /jetson/boot-files/Image
sudo cp -v "$MNT/boot/initrd" /jetson/boot-files/initrd
sudo cp -v "$MNT/boot/extlinux/extlinux.conf" /jetson/boot-files/extlinux.conf
sudo find "$MNT/boot/dtb" -maxdepth 1 -name '*.dtb' -exec cp -v {} /jetson/boot-files/ \;

sudo umount "$MNT"
rmdir "$MNT"
sudo kpartx -dv "$LOOP_DEV"
sudo losetup -d "$LOOP_DEV"

printf "\n=== Final GPT layout ===\n"
sgdisk -p jetson.img
printf "\n=== APP partition (#%s) details ===\n" "$APP_PART"
sgdisk -i "$APP_PART" jetson.img

cp jetson.img /jetson/
printf "[OK]\n"
