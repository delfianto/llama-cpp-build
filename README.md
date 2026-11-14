# llama.cpp for this machine

Read the [documentation index](docs/README.md), [Docker and Compose guide](docs/docker.md), or [native build and operation guide](docs/build-and-run.md) for full setup and usage instructions.

Builds unpatched [upstream llama.cpp](https://github.com/ggml-org/llama.cpp) from current `master` HEAD for this workstation:

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
just pkg                  # fetch upstream HEAD and build all split packages
just pkg install          # fetch/build HEAD and install all split packages
just build [target]       # build all|ggml|cpu|cuda|llama
just install [target]     # install all|ggml|cpu|cuda|llama
just list                 # show expected split package filenames and build status
just verify               # syntax, formatting, package metadata
```

`arch/PKGBUILD` produces three split packages:

- `ggml-znver5` — `libggml.so`, `libggml-base.so`, and the Zen 5 CPU backend (`libggml-cpu.so`).
- `ggml-cuda-znver5` — RTX 3000+ CUDA GPU backend (`libggml-cuda.so`, SM `86-real;89-real;120`).
- `llama.cpp-cuda-git` — `llama-server`, CLI/benchmark/quantization tools, `libllama`, `libmtmd`, and systemd unit.

Packages go to `.cache/pkg/`, build trees to `.cache/build/`, and the shared shallow Git cache to `.cache/llama.cpp-git/`. `just fetch` refreshes that cache. `makepkg` builds precisely that fetched commit, with its timestamp and short hash included in `pkgver` and binary build info. Running `cd arch && makepkg` directly also works via makepkg's normal VCS fetching.

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

The local package cache currently holds split packages built at upstream commit `b79696f1f556cb30b0c184838115007d929baca8`. Run `just verify` to check shell scripts, `justfile` formatting, and `.SRCINFO` consistency.
