# ik_llama.cpp-docker

This repository provides a bleeding-edge, highly specialized build configuration for `ik_llama.cpp` (a fork of `llama.cpp`), specifically optimized for **AMD Ryzen 9 9950X (Zen 5)** processors and modern **NVIDIA GPUs (RTX 30 series and higher)**.

It serves dual purposes:
1. **Arch Linux Package**: A dynamically versioned PKGBUILD for native host installation.
2. **Docker Sidecar**: A hyper-optimized container image designed to run as an OpenWebUI sidecar backend.

Both artifacts are built via GitHub Actions on every push to `main`, or manually via `workflow_dispatch`, pulling the absolute latest commits from the upstream `ik_llama.cpp` repository.

---

## 🚀 Extreme Optimizations

- **Modern GPU Targeting**: Compiles CUDA binaries strictly for `86;89;90` architectures (Ampere, Ada Lovelace, Hopper), reducing binary bloat and stripping out legacy Pascal/Turing support.
- **Aggressive CPU Tuning**: Forcibly overrides compiler flags with `-O3 -march=znver5 -mtune=znver5` to take absolute advantage of the Zen 5 pipeline during cross-compilation.
- **AVX-512 Domination**: Fully utilizes Zen 5's native 512-bit wide data paths with enabled `AVX512`, `VBMI`, `VNNI`, and `BF16` extensions.
- **LTO**: Link-Time Optimization is enabled for maximal cross-module tuning.

---

## 🐳 Docker Sidecar (OpenWebUI)

The Docker image (`ghcr.io/delfianto/ik_llama.cpp-zen5:latest`) is built on top of `nvidia/cuda:12.6.0-runtime-ubuntu24.04` and acts as a drop-in replacement for any OpenAI-compatible backend. 

### Advanced Features (MTP & QAT)
The container's dynamic entrypoint supports **Quantization Aware Training (QAT)** natively and handles **Multi-Token Prediction (MTP)** speculative decoding automatically (ideal for models like **Gemma 4**). 

If you pass an MTP draft model via the `MTP_MODEL_PATH` environment variable, the entrypoint will automatically hook the `--spec-draft-model` and `--spec-type draft-mtp` flags into the backend engine to accelerate generation.

### docker-compose.yml Integration

```yaml
services:
  llama-server-sidecar:
    image: ghcr.io/delfianto/ik_llama.cpp-zen5:latest
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

---

## 📦 Arch Linux Package Usage

If you prefer running it directly on your Arch host rather than via Docker, simply grab the latest `.pkg.tar.zst` from the **GitHub Actions Artifacts** page and install it locally:

```bash
sudo pacman -U ik-llama.cpp-zen5-git-*.pkg.tar.zst
```

*Note: Because this is hardcoded for `znver5` and RTX 30+, it will likely core dump or fail to execute if you attempt to run it on older hardware.*
