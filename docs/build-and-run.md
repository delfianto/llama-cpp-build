# Native builds and operation

This repository builds upstream llama.cpp from Git HEAD for the Ryzen 9950X (Zen 5) and RTX 3000+ CUDA GPUs (SM 86/89/120+). Run these commands from the repository root as your normal user; `makepkg` refuses to build as root.

## Dependencies and build

```sh
sudo pacman -S --needed base-devel git just cmake ninja cuda nccl openssl
just pkg
```

The [build profile](../arch/build-config.sh) sets GCC `-O3`, `-march=znver5`, `-mtune=znver5`, a 512-bit vector preference, AVX-512/VBMI/VNNI/BF16, OpenMP, and LTO. CUDA targets are `86-real;89-real;120` (native SASS for RTX 3000 SM 86, RTX 4000 SM 89, and RTX 5000 SM 120, plus PTX `compute_120` for newer architectures). CUDA graphs, all supported Flash Attention KV quant combinations, NCCL, server/tools, and multimodal support are enabled. Other accelerator backends and RPC are disabled.

The CPU backend remains necessary for host work and operations not offloaded to CUDA. The profile's explicit Zen 5 flags are why `GGML_NATIVE=OFF` does not imply a generic CPU build.

GCC must support `znver5` and satisfy the installed CUDA host-compiler checks. Do not bypass compiler compatibility checks to hide a toolchain mismatch.

The default is 16 concurrent jobs. All Flash Attention quant combinations take time to compile:

```sh
BUILD_JOBS=8 just pkg
```

## Split packages

`arch/PKGBUILD` builds three split packages:

| Package | Contents |
| --- | --- |
| `ggml-znver5` | `libggml.so`, `libggml-base.so`, Zen 5 `libggml-cpu.so`, headers, CMake config |
| `ggml-cuda-znver5` | `libggml-cuda.so` (RTX 3000+ CUDA backend) |
| `llama.cpp-cuda-git` | `llama-server`, CLI/quant/bench/mtmd tools, `libllama`, `libmtmd`, systemd unit |

Both `just build [target]` and `just install [target]` accept `all` (default), `ggml`/`cpu`, `cuda`, or `llama`.

## Source and version tracking

`just pkg` fetches current upstream `master` into the shallow bare repository `.cache/llama.cpp-git/` and runs `makepkg -D arch --force`. The package version contains the source commit timestamp and short hash, and `makepkg` updates `arch/PKGBUILD`'s `pkgver` when that revision changes.

```sh
git -C .cache/llama.cpp-git log -1 --format='%H %s'
just list
just srcinfo
just verify
```

Refresh `.SRCINFO` after a version or package metadata change. `just verify` checks shell syntax, justfile formatting, metadata consistency, and whitespace. It does not compile or test inference.

Because the source checkout is shallow, the binary's upstream build count can be 1. Use the reported commit hash to identify it; the count is not the normal full-history upstream release number.

Running `cd arch && makepkg` directly also works, but uses makepkg's ordinary VCS fetching and output paths instead of the repository's shallow-cache workflow.

## Install packages

```sh
just pkg install
# Or by target (all|ggml|cpu|cuda|llama):
just install all
just install llama
```

Both fetch and build current upstream HEAD before invoking `sudo pacman -U`. To install existing artifacts without fetching a new revision, pass the matching split package files to `pacman -U`:

```sh
sudo pacman -U \
  .cache/pkg/ggml-znver5-*.pkg.tar.zst \
  .cache/pkg/ggml-cuda-znver5-*.pkg.tar.zst \
  .cache/pkg/llama.cpp-cuda-git-*.pkg.tar.zst
```

Check `just list` to see the exact filenames expected for the current `PKGBUILD`. The packages conflict with separately packaged `llama.cpp`/`ggml` variants they replace, including `ggml-cuda` and `ggml-vulkan`. Review pacman's transaction before accepting it.

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
