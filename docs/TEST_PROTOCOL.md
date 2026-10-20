# Test protocol — kept identical across both model builds

Everything in this directory is measured with the same protocol that was used
for the `drama3-small` run, so the two results are directly comparable.

## Fixed across both runs

| Variable | Value | Why |
|---|---|---|
| Runtime | `audio.cpp 0.9.2-drama3-base-small` (macOS arm64 Metal) | Same binary for both, so runtime differences are not confounded by engine version |
| Hardware | Apple M1 Pro, 10 cores, 16 GB unified memory, macOS 27.0.1 | — |
| Reference clip | `ref/voice_ref_8s.wav` — 8.0 s, 44.1 kHz, mono, PCM 16-bit | Same file, same transcript, same speaker |
| Reference transcript | `ref/reference_text.txt` | Mandatory for cloning; kept byte-identical |
| English text | `english_text.txt` — 67 words | Same text, same order |
| Norwegian text | `norwegian_text.txt` — 2 sentences | Same text, same order |
| Seed | `42` | Reproducible takes within a configuration |
| Threads | `10` | Matches the 10 physical cores |
| Backend | `metal` | GPU-accelerated path |
| Mode | `offline` | `--metrics` only works offline |
| Task | `clon` | Voice cloning with a reference |
| `context_length` | `2048` | Prompt + reference + generation capacity |
| `codec_backend` | `cpu` | Frees 747 MB of Metal memory for the model |
| `codec_encoder_chunk_samples` | `65536` | Lowers reference-encoder peak memory |
| `max_tokens` | `700` (English) / `400` (Norwegian) | ~33 s / ~19 s of audio at 21.5 frames/s |

## What varies between the two runs

Only the model file and the expert placement:

| Run | Model | Expert placement |
|---|---|---|
| Small | `drama3-small-IQ3_XXS.gguf` (9.74 GiB) | Fully resident, `cpu_expert_layers=0` |
| Full | `drama-3-backbone-4bit-experts-Q4_K_S.gguf` (21.78 GiB) | `disk_experts=true`, `expert_cache_size=8`, `cpu_expert_layers=0` |

## Measurement method

- **RTF** (real-time factor) from `metrics.rtf` — wall seconds ÷ audio seconds.
  Lower is better. This is the comparable number.
- **Wall-clock** is only used within a single run, never across runs, because
  the first run on a machine spends ~140 s compiling Metal kernels. After the
  first run the kernels are cached on disk.
- **Transcription** via Whisper `small` to check what was actually said,
  with the language forced for the Norwegian case and again with auto-detect
  to confirm the language of the audio.
- **Silence detection** via `ffmpeg silencedetect` to catch the known Drama 3
  failure where a take goes silent and never resumes.
- **Swap high-water mark** via `sysctl vm.swapusage` around each run, since
  the failure mode on a 16 GB Mac is a silent OOM kill with no log output.

## Files produced

| File | Produced by |
|---|---|
| `out/english_works.wav` | `scripts/run_english.sh` |
| `out/norwegian.wav` | `scripts/run_norwegian.sh` |
| `out/bench_*.wav` | `scripts/bench_expert_offloading.sh` |
| `audio/*.wav` | Copies of the above, metadata-stripped, for the repository |
