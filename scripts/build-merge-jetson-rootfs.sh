#!/usr/bin/env bash

# Build the Ubuntu rootfs used as the base for a MergeTB jetson merge image.
# Mirrors build-base-rootfs.sh but uses the Containerfile.rootfs.<v>.merge
# variants (which create the 'test' user instead of 'jetson').

set -e

NO_CACHE=""
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --rebuild) NO_CACHE="--no-cache" ;;
        -h | --help)
            echo "Usage: $0 <22.04|24.04> [--rebuild]"
            echo "  --rebuild   force a clean podman build (no layer cache)"
            exit 0
            ;;
        22.04 | 24.04) VERSION="$arg" ;;
        *)
            printf "\e[31mUnknown argument: %s\e[0m\n" "$arg"
            exit 1
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Error: Ubuntu version required. Supported: 22.04, 24.04"
    exit 1
fi

case "$VERSION" in
"22.04")
    podman build \
        $NO_CACHE \
        --squash-all \
        --jobs=4 \
        --arch=arm64 \
        --network=host \
        -f Containerfile.rootfs.22_04.merge \
        -t jetson-merge-rootfs
    ;;

"24.04")
    podman build \
        $NO_CACHE \
        --squash-all \
        --jobs=4 \
        --arch=arm64 \
        --network=host \
        -f Containerfile.rootfs.24_04.merge \
        -t jetson-merge-rootfs
    ;;
esac

podman save --format docker-dir -o base jetson-merge-rootfs

mkdir rootfs

for layer in "$(jq -r '.layers[].digest' base/manifest.json | awk -F ':' '{print $2}')"; do
    tar xvf base/"$layer" --directory=rootfs
done

rm -rf rootfs/root/.bash_history
rm -rf base

echo "Merge rootfs created in rootfs directory"
