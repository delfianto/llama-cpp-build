# Upstream v1.0.0, Zen 5, and only the CUDA GPUs installed in this machine.
mirror := ".cache/llama.cpp-git"
source_url := "https://github.com/ggml-org/llama.cpp.git"
llama_tag := "v1.0.0"

_default:
    @just --list --unsorted

# Fetch upstream v1.0.0 into a shared shallow source cache.
fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache
    if [[ ! -d "{{ mirror }}" ]]; then
        git clone --bare --depth=1 --single-branch --branch "{{ llama_tag }}" "{{ source_url }}" "{{ mirror }}"
    fi
    git -C "{{ mirror }}" remote set-url origin "{{ source_url }}"
    git -C "{{ mirror }}" fetch --depth=1 --force origin "refs/tags/{{ llama_tag }}:refs/tags/{{ llama_tag }}"
    commit=$(git -C "{{ mirror }}" rev-parse "refs/tags/{{ llama_tag }}^{commit}")
    git -C "{{ mirror }}" update-ref --no-deref HEAD "$commit"
    git -C "{{ mirror }}" log -1 --format='%h %s'

# Build the Arch package from the fetched v1.0.0 tag.
pkg action="build": fetch
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/pkg .cache/build
    export SRCDEST="$PWD/.cache" PKGDEST="$PWD/.cache/pkg" BUILDDIR="$PWD/.cache/build"
    case {{ quote(action) }} in
        build|install) ;;
        *) echo 'Usage: just pkg [build|install]' >&2; exit 2 ;;
    esac
    makepkg -D arch --holdver --force
    if [[ {{ quote(action) }} == install ]]; then
        mapfile -t packages < <(makepkg -D arch --packagelist)
        sudo pacman -U "${packages[@]}"
    fi

# Install the package built from current upstream HEAD.
install: (pkg "install")

srcinfo:
    cd arch && makepkg --printsrcinfo > .SRCINFO

# Build one CUDA image using the same native Arch package and toolchain.
docker: pkg
    #!/usr/bin/env bash
    set -euo pipefail
    export SRCDEST="$PWD/.cache" PKGDEST="$PWD/.cache/pkg" BUILDDIR="$PWD/.cache/build"
    mkdir -p .cache/docker
    rm -f .cache/docker/*.pkg.tar.zst
    mapfile -t packages < <(makepkg -D arch --packagelist)
    cp "${packages[@]}" .cache/docker/
    sha=$(git -C "{{ mirror }}" rev-parse HEAD)
    docker build -f docker/Dockerfile --build-arg LLAMA_SHA="$sha" -t ghcr.io/delfianto/llama.cpp:cuda .

[positional-arguments]
compose *args:
    docker compose -f docker/compose.example.yml {{ args }}

# Check recipe syntax and metadata without compiling.
verify:
    bash -n arch/PKGBUILD arch/build-config.sh docker/entrypoint.sh
    just --fmt --check
    cd arch && makepkg --printsrcinfo | diff - .SRCINFO
    git diff --check

# Keep sources; remove generated build trees and packages.
clean:
    rm -rf .cache/build .cache/pkg .cache/docker arch/src arch/pkg
