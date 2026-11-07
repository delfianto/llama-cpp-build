# Native builds and operation

This repository builds upstream llama.cpp from Git HEAD for the Ryzen 9950X and RTX 4080/3060. Run these commands from the repository root as your normal user; `makepkg` refuses to build as root.

## Dependencies and build

```sh
sudo pacman -S --needed base-devel git just cmake ninja cuda nccl openssl
just pkg
```

The [build profile](../arch/build-config.sh) sets GCC `-O3`, `-march=znver5`, `-mtune=znver5`, a 512-bit vector preference, AVX-512/VBMI/VNNI/BF16, OpenMP, and LTO. CUDA targets are exactly `86-real;89-real`, with no embedded PTX fallback. CUDA graphs, all supported Flash Attention KV quant combinations, NCCL, server/tools, and multimodal support are enabled. Other accelerator backends and RPC are disabled.

The CPU backend remains necessary for host work and operations not offloaded to CUDA. The profile's explicit Zen 5 flags are why `GGML_NATIVE=OFF` does not imply a generic CPU build.

GCC must support `znver5` and satisfy the installed CUDA host-compiler checks. The verified toolchain is GCC 16.2.1 with CUDA 13.4.92. Do not bypass compiler compatibility checks to hide a toolchain mismatch.

The default is 16 concurrent jobs. All Flash Attention quant combinations take time to compile:

```sh
BUILD_JOBS=8 just pkg
```

## Source and version tracking

`just pkg` fetches current upstream `master` into the shallow bare repository `.cache/llama.cpp-git/`. It invokes `makepkg --holdver`, which builds the fetched revision rather than doing a second remote update. The package version contains the source commit timestamp and short hash. `makepkg` updates `arch/PKGBUILD`'s `pkgver` when that revision changes.

```sh
git -C .cache/llama.cpp-git log -1 --format='%H %s'
just srcinfo
just verify
```

Refresh `.SRCINFO` after a version or package metadata change. `just verify` checks shell syntax, justfile formatting, metadata consistency, and whitespace. It does not compile or test inference.

Because the source checkout is shallow, the binary's upstream build count can be 1. Use the reported commit hash to identify it; the count is not the normal full-history upstream release number.

Running `cd arch && makepkg` directly also works, but uses makepkg's ordinary VCS fetching and output paths instead of the repository's shallow-cache workflow.

## Install a package

```sh
just pkg install
# Equivalent alias:
just install
```

Both fetch/build current upstream HEAD before invoking `sudo pacman -U`. To install an existing artifact without fetching a new revision, use its explicit path:

```sh
sudo pacman -U .cache/pkg/llama.cpp-cuda-git-1794038487.cf659f2-1-x86_64.pkg.tar.zst
```

That filename is the verified baseline; choose the actual file for another revision. The package conflicts with the separately packaged llama.cpp/ggml variants it replaces, including ggml-cuda and ggml-vulkan. Review pacman's transaction before accepting it.

Installation does not restart an existing server. A process already running can retain its old loaded binaries and libraries until restarted.

## Start the server

```sh
llama-server -m /path/model.gguf -ngl 99 -fa on -t 16 \
  -c 8192 --parallel 1 --jinja --host 127.0.0.1 --port 8080
```

For vision, add `--mmproj /path/matching-mmproj.gguf`. Use the projector belonging to the model. Input formats and modalities depend on upstream model support. The package includes `llama-mtmd-cli` for direct multimodal checks and an optional dependency on `ffmpeg` for video input.

```sh
llama-server --version
llama-server --list-devices
llama-server --help
```

Help output is the reference for flags accepted by that build of moving upstream HEAD. The [Docker guide](docker.md#check-the-api) includes text and image API requests that also work against a native server.

Use `CUDA_VISIBLE_DEVICES=0` before the command to restrict a native process to the current host GPU 0. Check `nvidia-smi -L` first. For larger models, keep both GPUs visible and inspect the actual layer/KV placement in startup logs.

## Optional systemd service

The package installs `llama.cpp.service` and backs up `/etc/conf.d/llama.cpp` as a package configuration file. Set `LLAMA_ARGS` there, for example:

```sh
LLAMA_ARGS="--model /mnt/sata1/models/hauhaucs/Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf --mmproj /mnt/sata1/models/hauhaucs/mmproj-Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-f16.gguf --ctx-size 8192 --parallel 1 --n-gpu-layers 99 --flash-attn on --threads 16 --jinja --host 127.0.0.1 --port 8080"
```

This is an environment file, not a shell script; use literal arguments and paths without shell substitutions. The included service has no `User=` directive and runs with system-service defaults. Review the unit if you need a dedicated service account or different runtime restrictions.

```sh
sudo systemctl enable --now llama.cpp.service
systemctl status llama.cpp.service
journalctl -u llama.cpp.service -f
# After changing LLAMA_ARGS or installing a new package:
sudo systemctl restart llama.cpp.service
```

Do not start the native service and a container on the same host port. Neither package installation nor the Docker build enables this service automatically.

## Build output and cleanup

| Path | Contents |
| --- | --- |
| `.cache/llama.cpp-git/` | Shared shallow upstream Git source |
| `.cache/build/llama.cpp-cuda-git/src/` | makepkg source checkout and CMake build tree |
| `.cache/build/llama.cpp-cuda-git/src/build/bin/` | Uninstalled binaries and libraries |
| `.cache/pkg/` | Finished Arch packages |
| `.cache/docker/` | Package selected for the Docker context |

Uninstalled build-tree binaries are useful for testing before installation. An extracted package may need `LD_LIBRARY_PATH` pointing to its extracted `usr/lib`; prefer a normal package installation for regular operation.

```sh
just clean
```

This removes generated build trees, packages, and Docker staging while retaining the upstream Git cache. It does not remove Docker images or models. Preserve any package you need for rollback before cleaning. Compiler caches managed by ccache are separate from these paths.

For experimental changes, read the [patch audit](patch-candidates.md). Its applicability checks do not replace compile, output-correctness, image, and performance checks on a candidate build.
