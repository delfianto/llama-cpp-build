# ik_llama.cpp-docker

This repository provides a bleeding-edge, highly specialized build configuration for `ik_llama.cpp` (a fork of `llama.cpp`), specifically optimized for **AMD Ryzen 9 9950X (Zen 5)** processors and modern **NVIDIA GPUs (RTX 30 series and higher)**.

It serves dual purposes:
1. **Arch Linux Package**: A dynamically versioned PKGBUILD for native host installation.
2. **Docker Sidecar**: A hyper-optimized container image designed to run as an OpenWebUI sidecar backend.

Everything is built **locally**. There is no CI: a Zen 5 + LTO + CUDA build on a shared GitHub runner takes hours, and the resulting binaries can't even run on the runner that produced them.

---

## 🚀 Extreme Optimizations

- **Modern GPU Targeting**: Compiles CUDA binaries strictly for `86;89;90` architectures (Ampere, Ada Lovelace, Hopper), reducing binary bloat and stripping out legacy Pascal/Turing support.
- **Aggressive CPU Tuning**: Forcibly overrides compiler flags with `-O3 -march=znver5 -mtune=znver5` to take absolute advantage of the Zen 5 pipeline.
- **AVX-512 Domination**: Fully utilizes Zen 5's native 512-bit wide data paths with enabled `AVX512`, `VBMI`, `VNNI`, and `BF16` extensions.
- **LTO**: Link-Time Optimization is enabled for maximal cross-module tuning.

All of the above applies to **both** image variants — the CPU image is just as Zen 5-specific as the CUDA one.

---

## 🐳 Building the images

Two variants come out of the single `Dockerfile`, selected by the `VARIANT` build arg. `just` is the entry point:

| Tag | Base | Unpacked / pull | Contents |
| --- | --- | --- | --- |
| `:cuda` | `nvidia/cuda:13.3.0-runtime-ubuntu24.04` | 4.03 GB / 2.94 GB | CUDA + NCCL, arch `86;89;90`, FA all-quants |
| `:cpu` | `ubuntu:24.04` | 0.17 GB / 0.06 GB | No CUDA at all — Zen 5 / AVX-512 only |

```bash
just            # list recipes
just check      # has upstream moved since each image was built?
just cpu        # build ghcr.io/delfianto/ik_llama.cpp-zen5:cpu
just cuda       # build ghcr.io/delfianto/ik_llama.cpp-zen5:cuda
just all        # both
just pkg        # the Arch package, via makepkg
```

BuildKit only builds the stages the selected variant references, so `just cpu` never pulls the multi-gigabyte CUDA images.

> `docker images` will report these as 6.97 GB and 231 MB. That is a containerd
> image-store artifact — it sums the compressed blobs *and* the unpacked
> snapshots, double-counting every layer. The table above is the real size.

### The source mirror

`./ik_llama.cpp` is a bare mirror of upstream and the **single source of truth**. It is the same clone `makepkg` populates from the PKGBUILD's `source=git+...`, so `just pkg` and the docker builds never clone twice.

Each build runs `git archive <sha>` from that mirror into `.build/src`, which bake passes to the Dockerfile as the `ikllama` named context. No network, no re-clone, no `.git` in the image. `git archive` is byte-deterministic (mtimes come from the commit), so an unchanged commit re-extracts identically and the `COPY` layer still cache-hits.

Because the source arrives as a named context, a bare `docker build .` no longer works — use `just`, or run bake yourself with `.build/src` already materialised.

### Tracking upstream

Each image records the commit it was built from as an `org.opencontainers.image.revision` label, so the image is self-describing and there is no stamp file to drift. `just check` fetches the mirror and diffs upstream against that label:

```console
$ just check
upstream main @ 1fddd12ba861  (18 hours ago -- New op: ggml_sum_rows_ext (#2132))

  cpu:  up to date
  cuda: STALE at bbc7de47c1a2 (37 commits behind)
```

`just cpu` / `just cuda` skip the build entirely when the image already matches upstream. Override with `FORCE=1`, or build a specific ref with `IK_LLAMA_REF` (a branch, tag, or full SHA):

```bash
FORCE=1 just cuda
IK_LLAMA_REF=bbc7de47 just cuda
```

`ccache` is mounted across builds (separate cache per variant), so a bump that only moves upstream a few commits recompiles a small fraction of the tree. The LTO link step still runs in full — expect ~20-25 min for a cold `:cuda` build.

### Pushing

Images are tagged into the `ghcr.io/delfianto` namespace but nothing pushes automatically. When you want them published:

```bash
docker push ghcr.io/delfianto/ik_llama.cpp-zen5:cuda
```

---

## 🐳 Docker Sidecar (OpenWebUI)

The image acts as a drop-in replacement for any OpenAI-compatible backend.

### Advanced Features (MTP & QAT)
The container's dynamic entrypoint supports **Quantization Aware Training (QAT)** natively and handles **Multi-Token Prediction (MTP)** speculative decoding automatically (ideal for models like **Gemma 4**).

If you pass an MTP draft model via the `MTP_MODEL_PATH` environment variable, the entrypoint will automatically hook the `--spec-draft-model` and `--spec-type draft-mtp` flags into the backend engine to accelerate generation.

### docker-compose.yml Integration

```yaml
services:
  llama-server-sidecar:
    image: ghcr.io/delfianto/ik_llama.cpp-zen5:cuda
    container_name: llama-server-sidecar
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./models:/models
    environment:
      # Main QAT quantized model
      - MODEL_PATH=/models/gemma-4-main-qat.gguf

      # Draft model for MTP speculative decoding
      - MTP_MODEL_PATH=/models/gemma-4-draft-mtp.gguf

      - CTX_SIZE=8192
      - N_GPU_LAYERS=-1
      - THREADS=16
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

For the `:cpu` image, use the same block with the tag swapped and the `deploy:` section removed. `N_GPU_LAYERS` is ignored by a CPU-only build.

See `docker-compose.example.yml` for a full stack including OpenWebUI.

---

## 📦 Arch Linux Package Usage

If you prefer running it directly on your Arch host rather than via Docker, build it locally:

```bash
makepkg -si
```

*Note: Because this is hardcoded for `znver5` and RTX 30+, it will likely core dump or fail to execute if you attempt to run it on older hardware.*
