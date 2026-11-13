# llama.cpp for this machine

Read the [documentation index](docs/README.md), [Docker and Compose guide](docs/docker.md), or [native build and operation guide](docs/build-and-run.md) for full setup and usage instructions.

Builds unpatched [upstream llama.cpp](https://github.com/ggml-org/llama.cpp) from release tag `v1.0.0` for this workstation:

- AMD Ryzen 9 9950X: GCC `-O3 -march=znver5 -mtune=znver5`, 512-bit vector preference, AVX-512/VBMI/VNNI/BF16, OpenMP, and C/C++ LTO.
- RTX 3000+ GPUs: CUDA **86-real;89-real;120** (native SASS for RTX 3000 SM 86, RTX 4000 SM 89, and RTX 5000 SM 120, plus PTX `compute_120` for newer architectures).
- CUDA Flash Attention with all supported KV quant combinations, CUDA graphs, and NCCL for multi-GPU work. Upstream chooses MMQ/cuBLAS kernels at runtime.
- Server, CLI, benchmark, quantization, and upstream `mtmd` multimodal library/tools. CPU support remains necessary for tokenization, sampling, and operations that cannot run on CUDA.

No portable binaries, CPU-only variants, alternate accelerator backends, downstream patches, or fork synchronization. The canonical build flags are in [arch/build-config.sh](arch/build-config.sh), shared by the package and container.

Install build dependencies on Arch:

```sh
sudo pacman -S --needed base-devel git just cmake ninja cuda nccl openssl
```

GCC must understand `znver5` and be supported by the installed CUDA toolkit. The current machine has GCC 16.2 and CUDA 13.4; compiler version checks stay enabled.

```sh
just pkg          # fetch upstream HEAD and build
just pkg install  # fetch/build HEAD and install with pacman
just install      # alias for just pkg install
just verify       # syntax, formatting, package metadata
```

Packages go to `.cache/pkg/`, build trees to `.cache/build/`, and the shared shallow Git cache to `.cache/llama.cpp-git/`. `just fetch` refreshes that cache. `makepkg --holdver` then builds precisely that fetched commit, with its hash included in the package version and binary build info. The PKGBUILD also works directly with `cd arch && makepkg`; that path uses makepkg's normal VCS fetching.

Compilation defaults to 16 concurrent jobs to leave memory for CUDA template compilation and other running workloads. Override with `BUILD_JOBS=8 just pkg`. `just clean` removes builds and packages while keeping downloaded source.

The build uses current upstream APIs and options from its [build documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md) and [CUDA CMake configuration](https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cuda/CMakeLists.txt). HEAD moves; the recorded commit identifies what was actually built. These flags target this hardware, but performance still depends on the model, quantization, batch/context size, and GPU split; no benchmark speedup is assumed.

Run the installed server:

```sh
llama-server -m /path/model.gguf -ngl 99 -fa on -t 16 --jinja --host 127.0.0.1 --port 8080
```

For vision, add `--mmproj /path/matching-mmproj.gguf`. Keep `--jinja` enabled for models with custom chat templates. The projector must match the model. `llama-mtmd-cli` is included for direct image/audio testing; the exact supported inputs depend on the upstream model implementation.

The package includes an optional systemd unit. Set `LLAMA_ARGS` in `/etc/conf.d/llama.cpp` before enabling `llama.cpp.service`. Installing a package does not restart an already running server.

```sh
just docker       # build the same native package into one Arch-based CUDA image
just compose up -d
```

Edit [docker/compose.example.yml](docker/compose.example.yml) with the model and optional projector paths. The container uses the package compiled on this host, exposes both GPUs, and defaults to 16 threads and Flash Attention. It requires NVIDIA Container Toolkit on the host. Container dependencies follow Arch's current repositories. Nothing is pushed to a registry automatically.

Container environment: `MODEL_PATH` (required), `MMPROJ_PATH` (optional), `CTX_SIZE` (8192), `N_GPU_LAYERS` (-1), `THREADS` (16), `HOST` (0.0.0.0), `PORT` (8080). Additional command arguments are passed directly to `llama-server`.

Validated on this workstation on 2026-11-07 at upstream commit `cf659f240b232e15700b1721bbb43c1d973c52e9` with GCC 16.2.1 and CUDA 13.4.92: package build/install-tree checks, inference with Flash Attention on each GPU, and a Gemma E2B image request through the packaged server's `/v1/chat/completions` endpoint (HTTP 200). `cuobjdump` confirmed only SM 86/89 code and no embedded PTX in `libggml-cuda`. Dockerfile and Compose configuration checks passed; the container image was not built during this validation.
