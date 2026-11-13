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

# Build and optionally install split Arch packages (target: all|ggml|cpu|cuda|llama).
pkg action="build" target="all": fetch
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .cache/pkg .cache/build
    export SRCDEST="$PWD/.cache" PKGDEST="$PWD/.cache/pkg" BUILDDIR="$PWD/.cache/build"
    case {{ quote(action) }} in
        build|install) ;;
        *) echo 'Usage: just pkg [build|install] [all|ggml|cpu|cuda|llama]' >&2; exit 2 ;;
    esac
    case {{ quote(target) }} in
        all|ggml|cpu|cuda|llama) ;;
        *) echo 'Usage: just pkg [build|install] [all|ggml|cpu|cuda|llama]' >&2; exit 2 ;;
    esac
    makepkg -D arch --holdver --force
    if [[ {{ quote(action) }} == install ]]; then
        mapfile -t all_pkgs < <(makepkg -D arch --packagelist)
        selected=()
        for p in "${all_pkgs[@]}"; do
            base=$(basename "$p")
            case {{ quote(target) }} in
                all)
                    selected+=("$p")
                    ;;
                ggml|cpu)
                    [[ $base == ggml-znver5-* ]] && selected+=("$p")
                    ;;
                cuda)
                    [[ $base == ggml-znver5-* || $base == ggml-cuda-znver5-* ]] && selected+=("$p")
                    ;;
                llama)
                    [[ $base == ggml-znver5-* || $base == llama.cpp-cuda-git-* ]] && selected+=("$p")
                    ;;
            esac
        done
        sudo pacman -U "${selected[@]}"
    fi

# Build split packages (alias for `just pkg build`).
build target="all": (pkg "build" target)

# Build and install split packages (all, ggml/cpu, cuda, or llama).
install target="all": (pkg "install" target)

# Show expected split package filenames and build status.
list:
    #!/usr/bin/env bash
    set -euo pipefail
    export SRCDEST="$PWD/.cache" PKGDEST="$PWD/.cache/pkg" BUILDDIR="$PWD/.cache/build"
    mapfile -t packages < <(makepkg -D arch --packagelist)
    for p in "${packages[@]}"; do
        if [[ -f "$p" ]]; then
            printf 'built   %s\n' "$p"
        else
            printf 'missing %s\n' "$p"
        fi
    done

srcinfo:
    cd arch && makepkg --printsrcinfo > .SRCINFO

# Build one CUDA image using the split Arch packages and toolchain.
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
