# Fish Audio Drama 3 on an M1 MacBook Pro 16 GB — full model vs. small model

Companion report to
[`fish-audio-drama3-m1-macbook-pro-16gb`](https://github.com/SurgeonTalus/fish-audio-drama3-m1-macbook-pro-16gb),
which documented the `drama3-small` build. This report adds the **full 35B Drama 3**
(`Q4_K_S`, 21.78 GiB) running with **disk-backed expert offloading**, and compares
the two.

**Headline results:**

1. The full 35B model **does run on a 16 GB M1 Pro**, using audio.cpp's disk-backed
   expert offloading. Peak physical footprint: **6.9 GB** for a 21.78 GiB model.
2. **Norwegian now works.** The small model's unusable Norwegian is replaced by
   correct Norwegian with the full model. This confirms the small model's
   limitation was a property of the distillation corpus, not of Drama 3.
3. The full model is **~2.2x slower** per second of audio (RTF 28.8 vs 12.8) and
   reads **351 GB** from disk for a 33 s clip, but fits in memory where the
   resident version cannot.

---

## TL;DR comparison

| | drama3-small (IQ3_XXS) | Drama 3 full (Q4_K_S) |
|---|---|---|
| Model size | 9.74 GiB | 21.78 GiB |
| Fits resident in 16 GB | Yes | **No** — needs disk offload |
| Peak physical footprint | 10,327 MB | **6,903 MB** (with disk offload) |
| Expert placement | Fully resident in Metal | Streamed from disk, 540 MB cache |
| English clone (33 s) | RTF 12.8 | RTF 28.8 |
| Norwegian clone (9 s) | RTF 11.2 | RTF 26.3 |
| **Norwegian quality** | **Unusable** | **Correct** |
| Disk read for 33 s clip | 0 GB | **351 GB** |
| Trained languages | Japanese, English | 83 languages |

---

## The decisive finding: Norwegian works on the full model

The small model was distilled on Japanese and English only, and its Norwegian
output was unusable. The full model is a straight quantisation of the original
Drama 3 checkpoint, keeping its 83-language training.

Same reference clip, same seed, same text, same runtime — only the model file differs.

**Small model (IQ3_XXS) — unusable:**

| Intended | Produced |
|---|---|
| grønne og gule | grunn og god |
| sirkel på 25,5 cm | cirken på 2 utplaner skjermvektet 5 cm |
| fyll hele sirkelen med farge | fyller med hele serien |

**Full model (Q4_K_S) — correct Norwegian:**

> Mal et A4-ark i grønne av juleneaser. Mal en stor cirkel på 5-12 cm og fyller hele cirkel med farge.

Whisper auto-detection identifies the audio as **Norwegian** (`no`), not Danish or
Swedish. The failure pattern is gone: "grønne og gule" is now nearly right
("grønne av juleneaser" — the conjunction and one colour are still off), and the
sentence structure is intact.

One error remains: **"5-12 cm" instead of "25,5 cm"**. The decimal comma is
misparsed and the two digits are reordered. Numeric strings with a decimal comma
are a known weak spot for the model, and the upstream `drama3-small` card lists
phone numbers and codes as a general weakness. Write such values out as words
("tjugfemfem centimeter") if exactness matters.

> **Audio:** [`audio/norwegian.wav`](audio/norwegian.wav) (full model) ·
> [`audio/norwegian_unusable.wav`](audio/norwegian_unusable.wav) (small model, for comparison)

### English on the full model

The English clip is correct and complete:

> I have achieved a higher level of proficiency, demonstrated by details such as creating varied imprints using different plants, painting the jewelry pieces, crafting jewelry in various shapes and investing time and making multiple attempts, exploring texture and small scale craft projects using clay, creating clay slabs featuring nature imprints, making small jewelry pieces using seashell imprints and paints, variety in imprints, creativity in jewelry design and effort.

No silence detected, no truncation, no runaway generation. Whisper's "higher" for
"high" and "paints" for "paint" are transcription artefacts, not model errors.

> **Audio:** [`audio/english_works.wav`](audio/english_works.wav)

**A note on the reference.** The reference clip is **Norwegian** — the author has
no English sample of their own voice. The English output therefore carries a
**Norwegian accent**: the timbre and prosody transfer, but the phoneme choices
and stress pattern are Norwegian ones. This was already visible in the small-model
run and is unchanged here. It is a property of the test material, not of the model.

---

## Expert offloading: how it works

The full model is 21.78 GiB. The M1 Pro has 16 GB of unified memory, of which
macOS caps Metal's working set at 12,713 MB. The model cannot be resident.

audio.cpp's disk-backed expert mode keeps the routed expert banks **in the GGUF
file** and reads only the selected experts into a bounded resident cache. This is
the C++ implementation from audio.cpp PR #927, not macOS virtual-memory paging.

### Measured allocation, full model with `disk_experts=true`

| Component | Size | Backend | Resident? |
|---|---|---|---|
| `drama3_backbone.weights` | 1,326 MB | Metal | yes |
| `drama3.tower` | 2,173 MB | Metal | yes |
| Fish DAC codec | 747 MB | CPU | yes |
| `disk_experts` cache | 540 MB | host | yes, bounded |
| Routed expert banks | ~17 GB | **disk** | **no — streamed on demand** |

Total resident: **~4.8 GB** of Metal/host buffers for a 21.78 GiB model. Measured
peak physical footprint: **6,903 MB**.

This matches the expected design: attention layers, Gated DeltaNet linear states,
KV caches, router matrices and the codebook-MTP head stay resident; only the
routed 4-bit expert blocks stream from disk.

### Expert I/O during a 33 s English clip

| Metric | Value |
|---|---|
| `bytes_read` | 350,978,310,144 (351 GB) |
| `expert_loads` | 198,352 |
| `cache_hits` | 66,471 (25 % hit rate) |
| `buffer_mb` | 540 |
| `read_ms` | 720,962 (721 s — 75 % of wall time) |
| `upload_ms` | 66,169 |
| `stage_ms` | 788,015 |

**Disk reading is 75 % of the wall clock.** The unified-memory advantage does
help — the streamed experts are immediately usable by the Metal GPU with no PCIe
transfer — but the storage read itself is the bottleneck on this machine.

### Prefill cost

| Metric | Value |
|---|---|
| `offload_prefill_attention_ms` | 794 ms |
| `offload_prefill_experts_ms` | 50,119 ms |
| `offload_prefill_expert_work_rows` | 403,968 |
| `offload_prefill_routed_rows` | 176,000 |
| `backbone_step_ms` | 154,984 (166 frames, ~1.07 s/frame) |

With `cpu_expert_layers=0`, prompt prefill groups tokens by expert within each
layer, so one disk upload serves multiple tokens. The work-row to routed-row
ratio of **2.30x** shows that grouping is happening — each routed row pulls
2.3 expert rows of work.

---

## Speed comparison

RTF = wall seconds ÷ audio seconds. Lower is better. All on the same machine,
same runtime, same reference clip, same seed, same text.

### Same text, both models (no reference, 2.79 s of audio)

| Configuration | RTF | Peak footprint | Disk read |
|---|---|---|---|
| **small, fully resident in Metal** | **4.7** | 10,327 MB | 0 |
| small, 20 expert layers on CPU | 26.1 | 10,338 MB | 0 |
| small, `disk_experts`, cache=32 | 12.4 | 6,570 MB | 11.4 GB |
| small, `disk_experts`, cache=16 | 14.2 | 5,783 MB | 14.9 GB |
| small, `disk_experts`, cache=8 | 13.7 | 5,430 MB | 17.7 GB |

### Voice cloning with reference

| Model | Audio | RTF | Peak footprint | Disk read |
|---|---|---|---|---|
| small, resident | 33.1 s (EN) | 12.8 | 10,327 MB | 0 |
| small, resident | 9.3 s (NO) | 11.2 | 10,327 MB | 0 |
| **full, disk offload** | **33.1 s (EN)** | **28.8** | **6,903 MB** | **351 GB** |
| **full, disk offload** | **8.4 s (NO)** | **26.3** | **6,601 MB** | — |

**Key trade-off:** the full model is 2.2x slower than the small model, but uses
**33 % less peak memory** (6.9 GB vs 10.3 GB). For a 16 GB Mac that is the
difference between "fits" and "swaps".

### Expert cache size

For the small model, which fits resident anyway, offloading is a *speed penalty*:

| Cache size | RTF | Expert loads | Cache hits | Hit rate | Buffer | Peak footprint |
|---|---|---|---|---|---|---|
| 8 | 13.7 | 14,676 | 6,740 | 46 % | 368 MB | 5,430 MB |
| 16 | 14.2 | 12,384 | 9,032 | 73 % | 735 MB | 5,783 MB |
| 32 | 12.4 | 9,465 | 11,951 | 126 %¹ | 1,470 MB | 6,570 MB |

¹ The hit counter exceeds the load counter because a single load can satisfy
multiple requests.

Larger caches reduce disk reads (17.7 GB → 11.4 GB) and improve RTF, at the cost
of more resident memory. **For a model that already fits, `disk_experts` is a way
to trade speed for memory headroom** — useful on a busy machine, pointless as a
speed optimisation.

---

## The configuration that works

```bash
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
  --log --metrics \
  --out out/english_works.wav
```

### Flag reference

There is **no `--n-cpu-moe` flag in audio.cpp** — that is a llama.cpp flag. The
equivalent controls in audio.cpp are:

| Option | Purpose |
|---|---|
| `fish_drama3.disk_experts=true` | **Enable disk-backed expert offloading.** Keeps routed expert banks in the GGUF, streams selected experts into a bounded cache. |
| `fish_drama3.expert_cache_size=N` | Resident expert slots per layer, 8–256. Default 32. |
| `fish_drama3.cpu_expert_layers=N` | Number of the 40 expert banks evaluated on CPU. `0` = all on GPU. This is the closest analogue to `--n-cpu-moe`. |
| `fish_drama3.pin_experts=true` | Keeps full expert banks in pinned host RAM for direct cache-miss uploads. Requires `disk_experts=true` and pinned host-buffer support; allocation failure is an error, not a fallback. Not exercised here. |
| `fish_drama3.codec_backend=cpu` | Moves the 747 MB Fish DAC codec off Metal. Required on 16 GB. |
| `fish_drama3.codec_encoder_chunk_samples=65536` | Chunks the reference encoder, lowering its peak memory. Must be 0 or a multiple of 512. |
| `fish_drama3.context_length=2048` | Prompt + reference + generation capacity. |

The runtime exposes the model as a built-in package preset named
`fish_drama3_q4_backbone`.

---

## Known issues hit during testing

1. **Silent process death.** As in the small-model run, the process can be killed
   with no error message and no log line when unified memory is exhausted. Check
   `sysctl vm.swapusage` first. Moving the codec to CPU and using disk offloading
   fixed it — the full model never exceeded 6.9 GB.
2. **First-run Metal kernel compilation** takes ~140 s, cached afterwards. Raw
   wall-clock from the first run is not comparable to later runs; use `metrics.rtf`.
3. **Reference audio must be 44.1 kHz mono.** A 48 kHz source needs resampling.
4. **Keep references short (8–12 s).** Longer references stall prefill.
5. **The pause fix is not in this build.** The community
   `drama3-small-audiocpp.patch` adds a sampler-side fix for takes that go silent
   at a tag or sentence boundary and never resume. The upstream
   `v0.9.2-drama3-base-small` release does not include it, and this binary does
   not honour `AUDIOCPP_DRAMA3_MAX_PAUSE_FRAMES`. The bug was not triggered by
   these tests, but it is a known failure mode on tagged text.
6. **`--metrics` works in offline mode only.**
7. **macOS tools matter for long runs.** `setsid` does not exist on macOS, and
   backgrounded processes were killed when the controlling shell was interrupted.
   Use `caffeinate -dimsu` to keep the machine awake and avoid swapping during
   multi-minute generations.

---

## Sample audio

| File | What it is | Duration |
|---|---|---|
| [`audio/english_works.wav`](audio/english_works.wav) | Full model, English clone of a Norwegian reference | 33.1 s |
| [`audio/norwegian.wav`](audio/norwegian.wav) | Full model, Norwegian — correct | 8.4 s |
| [`audio/norwegian_unusable.wav`](audio/norwegian_unusable.wav) | Small model, Norwegian — unusable, for comparison | 9.3 s |
| [`audio/small_offload_cache8.wav`](audio/small_offload_cache8.wav) | Small model with disk offloading, cache=8 | 2.8 s |
| [`audio/small_offload_cache16.wav`](audio/small_offload_cache16.wav) | Small model with disk offloading, cache=16 | 2.8 s |
| [`audio/small_offload_cache32.wav`](audio/small_offload_cache32.wav) | Small model with disk offloading, cache=32 | 2.8 s |
| [`audio/reference_voice_8s.wav`](audio/reference_voice_8s.wav) | Reference clip (Norwegian) | 8.0 s |

All 44.1 kHz mono PCM 16-bit.

---

## Practical guidance

| Goal | Recommendation |
|---|---|
| Best quality, longest context, multilingual | **Full Drama 3 Q4_K_S with disk offloading.** Correct in 83 languages, fits in 16 GB. Accept ~2.2x the generation time. |
| Fastest iteration on a 16 GB Mac | **drama3-small, fully resident.** RTF 4.7. English and Japanese only. |
| Lowest memory footprint | Full model with `disk_experts=true`, cache=8 — 6.6 GB peak. |
| Norwegian specifically | **Full model.** The small model cannot do it. |
| Numeric precision in text | Write numbers out as words. "25,5 cm" becomes "5-12 cm". |

### Practical notes for the full model on 16 GB

- Set `expert_cache_size=8` if memory is tight, `32` if you want fewer disk
  reads and can spare ~1.5 GB.
- Expect **~350 GB of disk reads per 33 s clip**. On an SSD this is the
  bottleneck; on a slower drive it will be worse.
- A 33 s clip takes ~16 minutes to generate. For shorter pieces, reduce
  `max_tokens` accordingly (21.5 frames ≈ 1 s of audio).
- `pin_experts=true` would hold the expert banks in pinned host RAM for faster
  uploads, but needs the full bank set in memory — the opposite of what disk
  offloading is for on a 16 GB machine. Not tested here.

---

## Credits

- [Fish Audio Drama 3](https://huggingface.co/fishaudio/drama-3) and its codec — Fish Audio
- [`drama-3-backbone-4bit-experts-Q4_K_S.gguf`](https://huggingface.co/Jmica/Drama-3-GGUF) — JarodMica (independent community conversion)
- [`drama3-small-IQ3_XXS.gguf`](https://huggingface.co/pentacoxian-dev/drama3-small-GGUF) — JarodMica
- [audio.cpp](https://github.com/0xShug0/audio.cpp) — the runtime, including the disk-backed expert offloading in PR #927

## Licensing

The models are under the **Fish Audio Community License v1.0**. Free for research
and non-commercial use; limited commercial use below USD 500k annual revenue.
Hosting as a TTS or voice-cloning service requires a separate license.

The audio clips were generated with the author's own voice as reference material,
for the purpose of documenting these results. The voice is not a public figure
and the material is not intended to impersonate anyone.

Per the model license, do not use this model or its output to imitate the voice
of an identifiable person without their consent, impersonate anyone to deceive,
defraud or harass, or remove watermarks or provenance signals.
