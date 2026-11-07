#!/usr/bin/env bash
set -euo pipefail
: "${MODEL_PATH:?Set MODEL_PATH to a GGUF model}"
args=(--model "$MODEL_PATH" --host "${HOST:-0.0.0.0}" --port "${PORT:-8080}"
      --ctx-size "${CTX_SIZE:-8192}" --n-gpu-layers "${N_GPU_LAYERS:--1}"
      --threads "${THREADS:-16}" --flash-attn on --jinja)
if [[ -n "${MMPROJ_PATH:-}" ]]; then
    args+=(--mmproj "$MMPROJ_PATH")
fi
exec /usr/bin/llama-server "${args[@]}" "$@"
