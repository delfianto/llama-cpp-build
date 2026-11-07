# Docker and Compose

The image runs the same package compiled on this workstation. It targets the Ryzen 9950X and CUDA SM 86/89 for the RTX 3060 and 4080. Containerization does not make those binaries portable.

## Host setup

Install the build dependencies from the [native build guide](build-and-run.md), plus Docker, Compose, and NVIDIA Container Toolkit:

```sh
sudo pacman -S --needed docker docker-compose nvidia-container-toolkit
sudo systemctl enable --now docker
nvidia-smi
```

The commands below assume your account can access the Docker daemon. Use your existing Docker access setup; a daemon permission error must be resolved before building.

For a Docker daemon that has not been configured for NVIDIA GPUs, NVIDIA documents this setup:

```sh
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

The first command updates the host's Docker daemon configuration. Restarting Docker can interrupt running containers; do this setup when appropriate for the host. See the [NVIDIA setup guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#configuring-docker). Rootless Docker needs the separate configuration described there.

## Build the image

```sh
just docker
# Fewer concurrent compiler jobs if other workloads need RAM:
BUILD_JOBS=8 just docker
```

`just docker` does the following:

1. Fetch upstream `master` HEAD into `.cache/llama.cpp-git/`.
2. Build the native Arch package with the Zen 5/CUDA profile.
3. Copy the selected package into `.cache/docker/`, removing older packages from that staging directory.
4. Build `ghcr.io/delfianto/llama.cpp:cuda` from [docker/Dockerfile](../docker/Dockerfile).

The Dockerfile uses `archlinux:latest`, installs CUDA/NCCL/OpenSSL from Arch repositories, then installs the staged package and entrypoint. Compilation happens on the host. Building this image does not install the package on the host, restart a server, or publish an image.

The first build downloads the toolkit dependencies into the image and can use substantial disk space. Later builds reuse Docker layers when their inputs match. The [Dockerfile-specific ignore file](../docker/Dockerfile.dockerignore) limits the context to the staged package and entrypoint, so model files and compiler work trees are not sent into the image.

Check the local result:

```sh
docker image inspect ghcr.io/delfianto/llama.cpp:cuda \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
docker run --rm --entrypoint /usr/bin/llama-server \
  ghcr.io/delfianto/llama.cpp:cuda --version
docker run --rm --gpus all --entrypoint /usr/bin/llama-server \
  ghcr.io/delfianto/llama.cpp:cuda --list-devices
```

The revision label identifies the upstream source used by `just docker`. The last command should list the 4080 and 3060. `--entrypoint` bypasses the model-serving wrapper, so these inspection commands do not need `MODEL_PATH`.

## Reuse an already-built package

`just docker` always fetches and invokes the package build. To package the existing local artifact without updating upstream or compiling again, run this in Bash from the repository root:

```bash
mkdir -p .cache/docker
mapfile -t package_paths < <(PKGDEST="$PWD/.cache/pkg" makepkg -D arch --packagelist)
for package_path in "${package_paths[@]}"; do
    test -f "$package_path" || exit 1
done
rm -f .cache/docker/*.pkg.tar.zst
cp "${package_paths[@]}" .cache/docker/
docker build -f docker/Dockerfile \
  --build-arg LLAMA_SHA=cf659f240b232e15700b1721bbb43c1d973c52e9 \
  -t ghcr.io/delfianto/llama.cpp:cuda .
```

The SHA above belongs to the verified baseline package. Replace it with the full source commit of the artifact you selected. Do not use a freshly fetched mirror's HEAD to label an older package. `--packagelist` selects the version currently recorded in `arch/PKGBUILD`; if that artifact is absent, build it or explicitly select an existing package and its matching source revision.

The upstream SHA does not identify a reproducible container dependency set: `archlinux:latest` and Arch repositories move independently. Record the image ID or tag a retained image when preserving a working deployment.

## Run a small vision model directly

This uses the local Gemma E2B model/projector pair and exposes the server on localhost:

```sh
docker run --rm --name llama-local --gpus device=0 \
  -p 127.0.0.1:8080:8080 \
  -v /mnt/sata1/models:/models:ro \
  -e MODEL_PATH=/models/hauhaucs/Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf \
  -e MMPROJ_PATH=/models/hauhaucs/mmproj-Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-f16.gguf \
  -e CTX_SIZE=8192 \
  ghcr.io/delfianto/llama.cpp:cuda \
  --parallel 1 --metrics
```

Use `nvidia-smi -L` to check GPU ordering before choosing device 0. For a text-only model, omit `MMPROJ_PATH` and set `MODEL_PATH` to its GGUF. Paths in environment variables are container paths: `/mnt/sata1/models/foo.gguf` on the host becomes `/models/foo.gguf` with this mount.

The foreground command logs to the terminal; Ctrl-C stops it. A projector must match its model. Loading one enables supported image/audio inputs; it does not add modalities the model does not implement. Video processing additionally requires `ffmpeg`, which this image does not install.

## Entrypoint settings

| Variable | Default | Purpose |
| --- | --- | --- |
| `MODEL_PATH` | Required | Model GGUF path inside the container |
| `MMPROJ_PATH` | Unset | Matching multimodal projector |
| `CTX_SIZE` | `8192` | Requested context capacity |
| `N_GPU_LAYERS` | `-1` | GPU-offloaded layers; inspect startup logs for actual placement |
| `THREADS` | `16` | CPU inference threads |
| `HOST` | `0.0.0.0` | Listener address inside the container |
| `PORT` | `8080` | Listener port inside the container |

Flash Attention and Jinja templates are enabled by the wrapper. Keep the internal listener on `0.0.0.0` when publishing a container port; restrict host access through the host port mapping if needed. If you change `PORT`, change the container side of the port mapping too.

Arguments after the image name are forwarded individually to `llama-server`. In Compose, use a list under `command`, for example:

```yaml
command: ["--parallel", "1", "--metrics", "--cache-type-k", "q8_0", "--cache-type-v", "q8_0"]
```

There is no `EXTRA_ARGS` or MTP-specific environment wrapper. Supply speculative-decoding options through these normal arguments after checking `llama-server --help` for the built revision.

## Compose workflow

Make a local copy of the example so model choices stay out of tracked files:

```sh
mkdir -p .cache
cp docker/compose.example.yml .cache/compose.yml
```

Edit `.cache/compose.yml`: replace `MODEL_PATH`, optionally enable `MMPROJ_PATH`, and keep the model mount consistent. For the E2B example, use the two `/models/hauhaucs/...` paths from the direct-run command. The example publishes `8080:8080`; change it to `127.0.0.1:8080:8080` for localhost access.

```sh
docker compose -f .cache/compose.yml config -q
docker compose -f .cache/compose.yml up -d
docker compose -f .cache/compose.yml ps
docker compose -f .cache/compose.yml logs -f --tail=100 llama-server
# Stop the service:
docker compose -f .cache/compose.yml down
```

`just compose ...` uses the tracked `docker/compose.example.yml` directly. Use it if you intentionally edited that file. It does not select `.cache/compose.yml` automatically. Compose starts the local image; it does not run `just docker` or build the native package.

## Choose one GPU or both

The example exposes both GPUs with `count: all`. To expose only the 4080, replace that device reservation with:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          device_ids: ["0"]
          capabilities: [gpu]
```

Use the host's current device index or GPU UUID. `count` and `device_ids` are mutually exclusive, as described in [Docker's GPU guide](https://docs.docker.com/compose/how-tos/gpu-support/). When one GPU is exposed, CUDA indices inside the container can differ from host indices; inspect `--list-devices` there.

For both GPUs, keep `count: all`. An explicit layer split can be passed as:

```yaml
command: ["--parallel", "1", "--split-mode", "layer", "--tensor-split", "4,3"]
```

`4,3` is a relative allocation ratio, not a guaranteed memory fit or fastest setting. Allow space for the projector, KV cache, compute buffers, desktop, and other GPU workloads. Start with upstream's default placement and inspect logs before tuning. The local 17 GiB Qwen 27B weights do not fit entirely on the 16 GiB 4080 by themselves; they require multiple GPUs or CPU offload.

## Check the API

After startup logs show the server is listening:

```sh
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:8080/v1/models
curl -fsS http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":64,"temperature":0}'
```

For a vision check, replace `image.png` with a local image and submit its data URL:

```sh
python - <<'PYIMAGE' | curl -fsS http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' --data-binary @-
import base64, json
from pathlib import Path
image = base64.b64encode(Path("image.png").read_bytes()).decode()
print(json.dumps({
    "messages": [{"role": "user", "content": [
        {"type": "text", "text": "Describe this image briefly."},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64," + image}}
    ]}],
    "max_tokens": 256,
    "temperature": 0
}))
PYIMAGE
```

Use the MIME type matching the actual image format. A container with a projector should accept the request; confirm the returned description also matches the image. HTTP success alone does not establish vision correctness.

## Update or roll back

Preserve the current local image under another tag before rebuilding if you want a rollback point:

```sh
docker tag ghcr.io/delfianto/llama.cpp:cuda llama.cpp:previous
just docker
docker compose -f .cache/compose.yml up -d --force-recreate
```

To roll back, set the service's `image` to `llama.cpp:previous` and recreate it. A new build does not replace a running container until it is recreated. No registry push occurs unless you explicitly run one.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Docker cannot select a GPU device driver | Check Container Toolkit setup, Docker runtime configuration, and the device reservation |
| No CUDA devices in the container | Compare host `nvidia-smi` with container `--list-devices`; confirm `--gpus` or Compose GPU reservations |
| Model/projector cannot be opened | Check the host file, read permissions, mount, and `/models/...` container path |
| CUDA out of memory | Inspect `nvidia-smi`; lower context/parallelism, use supported quantized KV, adjust placement, or choose a smaller model |
| Port 8080 already allocated | Stop the other listener or publish another host port, such as `127.0.0.1:8081:8080` |
| Custom template error | Keep `--jinja` enabled; the wrapper enables it by default |
| Docker COPY cannot find the package | Use `just docker`, or stage exactly one selected package in `.cache/docker/` before building manually |
| Driver/toolkit compatibility error | Compare the host driver with the CUDA toolkit installed in the image; rebuilding against rolling repositories can change CUDA |
| API client cannot connect | Check the port mapping, internal listener, container state, and startup logs before sending requests |

For interactive inspection, bypass the entrypoint:

```sh
docker run --rm -it --gpus all --entrypoint /bin/bash \
  ghcr.io/delfianto/llama.cpp:cuda
```

Validation recorded so far: native package and packaged vision API checks passed; Dockerfile and Compose configuration checks passed. A full container build and GPU serving run were not performed as part of those checks.
