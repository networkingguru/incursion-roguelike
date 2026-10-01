#!/bin/bash
# Shared Docker plumbing for the Linux checks: an image per distro, and a clean
# export of the working tree. Sourced, never run.
#
# WHY IT EXISTS. tools/check_linux_build.sh was the only place that knew how to
# build the Debian 11 image and how to export the tracked tree into a temp dir.
# tools/linux_run.sh and tools/check_linux_save_roundtrip.sh need the same two
# moves, and a second copy of the export is a second place for the "never a
# bind mount of the checkout" rule to be forgotten. So the logic lives here,
# check_linux_build.sh sources it, and its behaviour and output do not change.
#
# A LINUX MACHINE IN A CONTAINER. This project has no Linux host. Docker on this
# arm64 Mac runs linux/amd64 containers, which execute real x86-64 code -- the
# same x86_64 the Steam Deck and ROG Ally use -- so a posix build and a scripted
# session there measure Linux behaviour the macOS build cannot.
#
# EXPORT, NEVER A BIND MOUNT OF THE CHECKOUT. A bind mount of the working
# directory would let the container's build write Linux objects and a
# Linux-built module into the developer's own build/ and mod/, and the next
# macOS build would link a mixture of the two. The tree goes in as an export of
# git ls-files at WORKING-TREE content, because a pre-commit check must see the
# change under test and `git archive HEAD` would silently export the last commit.
#
# Usage, from a sourcing script that has already cd'd to the repository root:
#   . "$(dirname "$0")/linux_docker.sh"
#   linux_docker_preflight || exit 2        # SKIP lines on stdout, exit 2
#   linux_ensure_image debian11 || exit 2
#   linux_export_tree "$TMP" || exit 2
#
# linux_run.sh builds one image per distro+compiler into a cached tree and bind
# mounts THAT export (not the checkout) into the container, which is why a bind
# mount is fine there: it is a copy the container is meant to own.

# linux_docker_preflight -> 0 docker reachable, 2 not. Prints check_linux_build's
# own SKIP wording so every caller reports a missing docker the same way.
linux_docker_preflight() {
    command -v docker >/dev/null || { echo "SKIP: docker not installed"; return 2; }
    docker info >/dev/null 2>&1 || { echo "SKIP: docker daemon not running"; return 2; }
    return 0
}

# linux_image_tag <distro> -> the image tag for that distro.
linux_image_tag() {
    case "$1" in
        debian11) echo "incursion-linux:bullseye" ;;
        arch)     echo "incursion-linux:arch" ;;
        *)        echo "unknown distro: $1" >&2; return 2 ;;
    esac
}

# linux_image_dockerfile <distro> -> the Dockerfile text on stdout.
# debian11 is the existing incursion-linux:bullseye image, unchanged. Debian 11
# is chosen on purpose: glibc 2.31 is the oldest we support, and linking against
# it sets the floor of who can run the release. arch is a rolling distro, kept
# so a failure can be told apart from "Debian's toolchain drifted"; it carries
# the same tools (clang, gcc, make, pkg-config, zlib, ncurses, SDL2), with Arch's
# own package names -- pkg-config is pkgconf, and zlib/ncurses ship headers in
# the base package.
linux_image_dockerfile() {
    case "$1" in
        debian11)
            cat <<'DOCKERFILE'
FROM --platform=linux/amd64 debian:11
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential clang pkg-config zlib1g-dev libncurses-dev \
        libsdl2-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
DOCKERFILE
            ;;
        arch)
            # DisableSandboxSyscalls: pacman 7.x restricts itself with seccomp,
            # and under qemu emulation (this Mac is arm64) that restriction
            # fails with "error restricting syscalls via seccomp: 22" before
            # any package is fetched. The sandbox is a pacman self-protection,
            # not a host one, so turning it off inside a throwaway build image
            # is safe. Debian's apt has no equivalent.
            cat <<'DOCKERFILE'
FROM --platform=linux/amd64 archlinux:latest
RUN sed -i 's/^#DisableSandboxSyscalls/DisableSandboxSyscalls/' /etc/pacman.conf \
    && pacman -Syu --noconfirm --needed \
        base-devel clang gcc make pkgconf zlib ncurses sdl2 \
    && pacman -Scc --noconfirm
WORKDIR /src
DOCKERFILE
            ;;
        *)
            echo "unknown distro: $1" >&2
            return 2
            ;;
    esac
}

# linux_ensure_image <distro> [tmpdir] -> 0 when the image exists (building it
# on first use), 2 when it could not be built.
linux_ensure_image() {
    local distro="$1"
    local image tag tmp
    tag="$(linux_image_tag "$distro")" || return 2

    if docker image inspect "$tag" >/dev/null 2>&1; then
        return 0
    fi

    echo "--- building $tag (first run only) ---"
    if [ -n "${2:-}" ]; then
        tmp="$2"
    else
        tmp="$(mktemp -d)" || return 2
        LINUX_DOCKER_MADE_TMP="$tmp"
    fi
    mkdir -p "$tmp"
    if ! linux_image_dockerfile "$distro" > "$tmp/Dockerfile"; then
        [ -z "${2:-}" ] && rm -rf "$tmp"
        return 2
    fi
    docker build --platform linux/amd64 -t "$tag" -q -f "$tmp/Dockerfile" "$tmp" >/dev/null \
        || { echo "FAIL: could not build $tag"; [ -z "${2:-}" ] && rm -rf "$tmp"; return 2; }
    rm -f "$tmp/Dockerfile"
    [ -z "${2:-}" ] && rm -rf "$tmp"
    return 0
}

# linux_export_tree <destdir> -> 0 when the working tree was exported there.
# Tracked files at their WORKING-TREE content, not at HEAD (see the header).
linux_export_tree() {
    local dest="$1"
    mkdir -p "$dest" || return 2
    git ls-files -z | xargs -0 tar -cf - 2>/dev/null | tar -x -C "$dest" || {
        echo "FAIL: could not export the working tree"; return 2; }
    return 0
}
