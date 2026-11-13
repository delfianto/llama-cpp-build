#!/usr/bin/env bash
# Shared by makepkg and Docker. Targets Ryzen 9950X (Zen 5) and RTX 3000+ GPUs.
set -euo pipefail
cmake -S "$1" -B "$2" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_CUDA_HOST_COMPILER=g++ \
    -DCMAKE_C_FLAGS="-O3 -march=znver5 -mtune=znver5 -mprefer-vector-width=512" \
    -DCMAKE_CXX_FLAGS="-O3 -march=znver5 -mtune=znver5 -mprefer-vector-width=512" \
    -DCMAKE_CUDA_FLAGS="-Xcompiler=-march=znver5,-mtune=znver5,-mprefer-vector-width=512" \
    '-DCMAKE_CUDA_ARCHITECTURES=86-real;89-real;120' \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_CPU_ALL_VARIANTS=OFF \
    -DGGML_BACKEND_DL=ON \
    -DGGML_BACKEND_DIR=/usr/lib/ggml \
    -DGGML_AVX512=ON \
    -DGGML_AVX512_VBMI=ON \
    -DGGML_AVX512_VNNI=ON \
    -DGGML_AVX512_BF16=ON \
    -DGGML_AVX_VNNI=ON \
    -DGGML_LTO=ON \
    -DGGML_OPENMP=ON \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_FA=ON \
    -DGGML_CUDA_FA_QUANTS=all \
    -DGGML_CUDA_GRAPHS=ON \
    -DGGML_CUDA_NCCL=ON \
    -DGGML_RPC=OFF \
    -DGGML_BLAS=OFF \
    -DGGML_VULKAN=OFF \
    -DGGML_HIP=OFF \
    -DGGML_SYCL=OFF \
    -DGGML_OPENCL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=ON \
    -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_BUILD_APP=OFF \
    -DLLAMA_BUILD_MTMD=ON \
    -DLLAMA_OPENSSL=ON
