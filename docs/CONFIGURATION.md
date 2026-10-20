# Runtime and configuration reference

## Versions

| Component | Value |
|---|---|
| Runtime | `audio.cpp` `0.9.2-drama3-base-small` |
| Runtime commit | `507495611b22dc4593e0e5609e05e8096384e33f` (2026-10-18) |
| Compiler | `apple-clang 21.0.0.21000101` |
| Target | `Darwin arm64` |
| Build type | Release |
| Enabled backends | `cpu`, `metal` |
| Runtime archive | `audio-v0.9.2-drama3-base-small-bin-macos-arm64-metal.tar.gz` |
| Runtime SHA256 | `1281998c1acd170a7d92139853fe6ce6ab920e211d2ad3359775d43ad9ba616d` |
| Model | `drama-3-backbone-4bit-experts-Q4_K_S.gguf` |
| Model repo | `Jmica/Drama-3-GGUF` (upstream `fishaudio/drama-3`) |
| Model size | 21.78 GiB (23.4 GB) |
| Model SHA256 | see `SHA256SUMS.txt` |

The `v0.9.2-drama3-base-small` runtime tag is used because it is the first
release where the `fish_drama3` family, IQ quant types, per-layer expert counts
and the disk-backed expert offload are all present in one build. The runtime
exposes the model as a built-in package preset named `fish_drama3_q4_backbone`.

## Host

| Component | Value |
|---|---|
| Chip | Apple M1 Pro |
| Cores | 10 physical / 10 logical |
| Unified memory | 16 GB |
| OS | macOS 27.0.1 (build 26A434) |
| Metal working set | 12,713.12 MB (`recommendedMaxWorkingSetSize`) |

## Model comparison

Two builds of Drama 3 were run on the same machine, with the same runtime, the
same reference clip, the same seed and the same text.

| | drama3-small (IQ3_XXS) | Drama 3 full (Q4_K_S) |
|---|---|---|
| File | `drama3-small-IQ3_XXS.gguf` | `drama-3-backbone-4bit-experts-Q4_K_S.gguf` |
| Size | 9.74 GiB | 21.78 GiB |
| Routed experts | 256 in layers 0/1/2/36, 100 elsewhere | 256 per layer |
| Expert quant | IQ3_XXS (~3 bit) | Q4_K |
| Backbone | Q8_0 | Q4_K + Q4_0 text embedding |
| Audio tower / codec | Q8_0 / F16 | FP16 / FP16 |
| Output head | EOS + 4,096 semantic rows (speech only) | Full 252,288-row vocabulary |
| Trained languages | Japanese, English (distilled) | 83 languages |
| Fits in 16 GB RAM | Yes, fully resident | No — requires disk-backed offload |
| Needs pruning/distillation | Yes | No, quantisation only |

The full model is a straight quantisation of the original Drama 3 checkpoint
and keeps its full output head and full 83-language coverage. The small model
is a pruned *and* distilled derivative, which is why its language coverage
collapses to the distillation corpus.

## Expert offloading configuration

The full model at 21.78 GiB cannot be fully resident in 16 GB of unified
memory. `audio.cpp` provides disk-backed expert offloading for exactly this
case.

| Option | Value | Effect |
|---|---|---|
| `fish_drama3.disk_experts` | `true` | Keeps the routed expert banks in the GGUF file and reads only the selected experts into a bounded resident cache. No GGUF conversion needed. |
| `fish_drama3.expert_cache_size` | `8` (default), tested 8/16/32 | Resident expert slots per layer. Range 8–256. Larger caches trade unified memory for fewer disk reads. |
| `fish_drama3.cpu_expert_layers` | `0` | Number of the 40 expert banks evaluated on CPU. `0` means the expert matmuls still run on the GPU — only the *weight streaming* is offloaded. This is the key distinction from the resident configuration. |
| `fish_drama3.pin_experts` | `true` (optional) | Loads full expert banks into pinned host memory once, so cache misses upload directly without an intermediate host copy. Requires `disk_experts=true` and pinned host-buffer support; allocation failure is an error, not a fallback. |

### How prefill behaves with disk offload

With `cpu_expert_layers=0`, prompt prefill groups tokens by expert within each
layer, so one disk upload serves multiple tokens. Attention and shared/router
projections keep the resident batched-prefill path; cached experts retain their
vector projection path. With mixed CPU/backend expert execution, prefill stays
token-wise.

### Logging

`--log` reports the following on session teardown:

- `disk_experts.bytes_read` — total bytes streamed from the GGUF
- `disk_experts.expert_loads` — number of expert loads
- `disk_experts.cache_hits` — cache hit count
- `disk_experts.buffer_mb` — cache size in MiB
- `disk_experts.host_buffer_mb` — pinned host buffer in MiB

These describe expert I/O and cache allocation, not total process peak memory.

## CLI invocation (full model, English)

```
./bin/audiocpp_cli \
  --task clon \
  --family fish_drama3 \
  --backend metal \
  --mode offline \
  --model models/drama-3-backbone-4bit-experts-Q4_K_S.gguf \
  --voice-ref ref/voice_ref_8s.wav \
  --request-option "reference_text=<transcript>" \
  --text "<text>" \
  --max-tokens 700 \
  --seed 42 \
  --threads 10 \
  --session-option fish_drama3.disk_experts=true \
  --session-option fish_drama3.expert_cache_size=8 \
  --session-option fish_drama3.cpu_expert_layers=0 \
  --session-option fish_drama3.context_length=2048 \
  --session-option fish_drama3.codec_backend=cpu \
  --session-option fish_drama3.codec_encoder_chunk_samples=65536 \
  --log \
  --metrics \
  --out out/english_works.wav
```

## Request options

| Option | Value | Notes |
|---|---|---|
| `reference_text` | transcript of the reference clip | Required for cloning. |
| `max_tokens` | `700` | ~33 s of audio at 21.5 frames/second. Higher caps let the model emit trailing silence. |
| `seed` | `42` | Reproducible within the same configuration. Changing offload placement can change the sampled take. |
| `temperature` / `top_p` / `top_k` | defaults (1.0 / 0.9 / 4097) | The uncapped `top_k` matches Fish's own Drama 3 Space. |

## Reference clip requirements

- 44.1 kHz, mono, PCM 16-bit
- 8–12 s tested; longer references stall prefill on a 16 GB Mac
- Accurate `reference_text` is mandatory
- Resample with: `ffmpeg -i in.wav -ar 44100 -ac 1 -c:a pcm_s16le out.wav`
