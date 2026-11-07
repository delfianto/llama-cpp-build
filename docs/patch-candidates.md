# Experimental patch candidates

Research snapshot: 2026-11-07. Baseline: upstream `cf659f240b232e15700b1721bbb43c1d973c52e9`, build-recipe commit `51fb53f`. Target: Ryzen 9 9950X, RTX 4080 (SM 89), RTX 3060 (SM 86). PR state and branch tips were read from GitHub; applicability was checked locally against the baseline using `git apply --check` on the per-file PR diffs. These are source applicability checks, not compilation, correctness, or performance results. The baseline source and build profile remain unchanged.

| Priority | Candidate | Local applicability | Main condition |
| --- | --- | --- | --- |
| 1 | [#31802: fuse quantized KV dequantization into CUDA Flash Attention](https://github.com/ggml-org/llama.cpp/pull/31802) | Clean; PR is draft | Long contexts, matching Q8/Q8 or Q4/Q4 KV, eligible 256-wide heads |
| 2 | [#31621: text prompt-cache reuse with a projector loaded](https://github.com/ggml-org/llama.cpp/pull/31621) | Clean | Repeated/edited text prompts on a vision-capable server |
| 3 | [#31533: CUDA small-batch quantized matmul](https://github.com/ggml-org/llama.cpp/pull/31533) | Runtime files clean; test file conflicts | Speculative verification or batches of 2-24 columns |
| 4 | [#30966: execute MoE cache misses on CPU](https://github.com/ggml-org/llama.cpp/pull/30966) | Clean | MoE experts partly resident in system RAM |
| 5 | [#30036: x86 VNNI repacking](https://github.com/ggml-org/llama.cpp/pull/30036) | Clean | CPU work on eligible 2-D Q4_0/Q8_0 weights |

All five were open at inspection. Author benchmark numbers below describe their hardware and workload; they are not predictions for this machine.

1. **Fused quantized KV: first CUDA experiment.** The author reports 17.6% faster decode at 32k and 33.9% at 64k on a 27B model across three RTX 2000 Ada GPUs, plus reduced scratch VRAM. Only two CUDA files change. The implementation requires K/V head widths of 256, GQA above 4, matching Q8_0 or matching Q4_0 caches, suitable strides/alignment, and selection of its multi-stage, non-sparse MMA path. F16 KV and mixed Q8/Q4 caches do not use the fused path. The runtime switch `GGML_CUDA_FATTN_MMA_FUSED=0` permits a control run with the patched binary; the default enables it. Value 2 is a routing assertion mode, not a normal performance preset. Head: `0c1543e189e490cdd1339a91e646fdfd2e5bc1b2`.

2. **Prompt reuse with vision loaded: first server experiment.** This restores reuse for text-only prompts while a projector is loaded; it does not make image-containing prompts reusable. The author measured an edited-prompt case falling from 0.35 to 0.04 seconds on an RTX 3080 Laptop with Gemma E4B. For Gemma's interleaved sliding-window cache, shifting requires `--swa-full`, which increases KV memory. Test with `--cache-reuse 256 --swa-full`, edited text, then alternating image/text requests. Head: `ba407159aca170954aca7ca4c97a683918f64b14`.

3. **Small-batch CUDA matmul: strongest speculative-decoding lead.** It adds kernels for supported quantizations at 2-24 columns, including Q4_K, Q5_K, Q6_K and Q8_0, on Ampere and newer NVIDIA GPUs. The author reports 34.9% higher speculative throughput on a 3090 Ti and 20.6% on a 5090 in their Qwen/DFlash benchmark. This is not a single-token decode acceleration. The diff does not add a new MUL_MAT_ID expert kernel; do not assume equal MoE gains. Only `tests/test-backend-ops.cpp` fails our apply check; excluding that file passes, but the tests need reconciliation before a trial. Head: `86db2f308364c900cfe196e5ed038262a1b0b5af`.

4. **CPU execution of MoE misses: use the 9950X alongside CUDA.** It adds a CPU-share parameter and a calibration script to balance CPU expert work against GPU uploads. The CPU remains within the CUDA-enabled build. This is relevant to the local 22 GiB Qwen MoE when VRAM is also needed for its context/projector or another server. It is a substantial scheduler/graph/cache change: 19 files, 1,213 additions and 173 deletions in the inspected revision. Maintainer discussion is still revising the integration. Establish the already-upstream cache baseline first. Head: `0290c8da41f7ec7284e6d2fbacf326c5c424f33c`.

5. **VNNI repack: exact CPU match, narrower workload.** The author tested a 9950X and reports Qwen3-4B Q8_0 prompt processing at 16 threads rising from 307 to 811 tokens/s, with essentially unchanged token generation. The code requires eligible 2-D Q4_0/Q8_0 weights; 3-D expert tensors do not take this new path. Most local models are K-quants and use GPU execution, so this is lower priority than the CUDA/server candidates. Head: `40288286c4fdd2e3d0617f62845a9e43561b1125`.

Local GGUF metadata supports the first experiment on the existing Qwen models:

| Model | Architecture | K/V head width | Query/KV head ratio | Assessment |
| --- | --- | --- | --- | --- |
| HauhauCS Qwen3.8 27B | qwen35 | 256/256 | 24/4 = 6 | Meets the basic shape gate; runtime routing still needs verification |
| sc117 Qwen3.6 35B-A3B | qwen35moe | 256/256 | 16/2 = 8 | Meets the basic shape gate; runtime routing still needs verification |
| HauhauCS Gemma E2B | gemma4 | Global 512; sliding-window 256 | 8/1 = 8 | Global attention is excluded; do not generalize the Qwen gains |
| HauhauCS Gemma 12B | gemma4 | Global 512; sliding-window 256 | Global 16; sliding-window 2 | Global width and local GQA gates exclude these respective layers |

The local Qwen 27B weights are about 17 GiB and the MoE weights about 22 GiB: neither fits wholly on the 16 GiB 4080. Trials must account for both GPUs, existing VRAM users, or deliberate CPU offload. Do not compare a change of offload layout as if it were a patch speedup.

Both local Qwen files also declare one NextN prediction layer, making ordinary upstream MTP a possible control before adding speculative patches. Companion compatibility and memory fitting still need testing.

Other leads checked:

- [#30196: consolidate sampling synchronizations](https://github.com/ggml-org/llama.cpp/pull/30196): author reports roughly 2-7% across speculative workloads on Blackwell. Conflicts in `common/speculative.cpp`; reviewer requests a rebase and API/server changes. Wait for a refreshed revision.
- [#27210: adaptive MTP depth](https://github.com/ggml-org/llama.cpp/pull/27210): interesting for mixed coding/prose workloads, but several source and test files conflict. It needs enough memory for larger maximum draft depths. Defer until a fixed-depth MTP baseline exists.
- [#25144: MTP positioning with vision](https://github.com/ggml-org/llama.cpp/pull/25144): draft, conflicts in `common/speculative.cpp`. Its report says shared-cache Gemma is unaffected; it is not a general Gemma vision fix.
- [#31732: self-speculative diffusion decoding](https://github.com/ggml-org/llama.cpp/pull/31732): applies cleanly, but requires appropriate diffusion-trained checkpoints. It does not turn the existing Gemma/Qwen checkpoints into self-drafting models. Reported tests are on H200. A separate model experiment, not an immediate build improvement.
- [#31469: direct-I/O expert streaming](https://github.com/ggml-org/llama.cpp/pull/31469): targets models exceeding physical host RAM, with a large I/O/scheduler redesign. Its 3060 results concern a constrained 16 GB RAM host; this machine has 60 GiB RAM. Lower priority; its diff was not checked locally.

The current baseline already includes `--moe-cache-mib`, ClassLRU/CRF expert replacement ([merged #31233](https://github.com/ggml-org/llama.cpp/pull/31233)), backend sampling, MTP, and the opt-in `GGML_CUDA_GRAPH_OPT=1` graph optimization. None requires restoring the removed fork code. Blackwell-specific SM 120 FP4 tensor-core patches are not a match for SM 86/89.

Recommended trials: independently compare #31802 on Qwen with Q8/Q8 KV at increasing prompt depth, and #31621 on Gemma with projector-loaded text reuse plus image regressions. Then reconcile #31533's test changes and compare fixed speculative depths. Keep Zen 5 and `86-real;89-real` throughout. Use baseline/candidate/candidate/baseline ordering, the same models and prompts, a fixed visible GPU set and split, and record latency, VRAM, generated tokens and speculative acceptance. Apply checks alone do not justify enabling a patch by default.

The inspected per-file patches, PR tips, and apply-check output are cached locally under `.cache/research/`. They are research artifacts; no experimental patch is enabled in the package.
