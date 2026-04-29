#!/usr/bin/env bash

# Build a MergeTB jetson merge image. Hard-coded to Jetson Orin Nano on NVMe
# with l4t36. Expects ./rootfs/ to already exist (run
# build-merge-jetson-rootfs.sh first).

set -e

NO_CACHE=""
for arg in "$@"; do
    case "$arg" in
        --rebuild) NO_CACHE="--no-cache" ;;
        -h | --help)
            echo "Usage: $0 [--rebuild]"
            echo "  --rebuild   force a clean podman build (no layer cache)"
            exit 0
            ;;
        *)
            printf "\e[31mUnknown argument: %s\e[0m\n" "$arg"
            exit 1
            ;;
    esac
done

if [ ! -d "rootfs" ]; then
    printf "\e[31mError: ./rootfs not found. Run build-merge-jetson-rootfs.sh first.\e[0m\n"
    exit 1
fi

L4T_PACKAGES=""
if [[ -f "l4t_packages.txt" ]]; then
    while IFS= read -r line; do
        if [[ ${line} != \#* ]]; then
            L4T_PACKAGES+=" $line"
        fi
    done <"l4t_packages.txt"
fi
L4T_PACKAGES="${L4T_PACKAGES# }"

sudo -E XDG_RUNTIME_DIR= DBUS_SESSION_BUS_ADDRESS= podman build \
    $NO_CACHE \
    --cap-add=all \
    --jobs=4 \
    --network=host \
    --build-arg L4T_PACKAGES="$L4T_PACKAGES" \
    -f Containerfile.image.l4t36.merge \
    -t jetson-merge-build-image-l4t36

sudo podman run \
    --rm \
    --network=host \
    --privileged \
    -v .:/jetson \
    localhost/jetson-merge-build-image-l4t36:latest \
    create-merge-jetson-image.sh
