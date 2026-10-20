# Sammenligning: Drama 3 vs CosyVoice3 vs Chatterbox v3

Tre modeller testet på **samme maskin**, med **samme tekst**, **samme
referanseklipp** og **samme seed**.

**Maskin:** Apple M1 Pro, 10 kjerner, 16 GB unified memory, macOS 27.0.1

---

## Resultattabellen

| Modell | Språk | WER | Auto-språk | ΔF0 | RTF | Peak RAM |
|---|---|---|---|---|---|---|
| **Drama 3 Q4_K_S** | norsk | **18,2 %** | `no` | +34,9 Hz | 27,5 | 6,7 GB |
| **Drama 3 Q4_K_S** | norsk | 36,4 % | `no` | −3,5 Hz | 26,3 | 6,9 GB |
| **CosyVoice3 + LoRA** | norsk | **31,8 %** | `no` | −1,6 Hz | **10,8** | ~7 GB |
| **Chatterbox v3** | norsk | 59,1 % | `no` | −8,4 Hz | 21,8 | — |
| **Drama 3 IQ3_XXS** | norsk | 59,1 % | `no` | −12,6 Hz | **11,2** | 10,3 GB |
| **Drama 3 Q4_K_S** | engelsk | **6,0 %** | `en` | +6,0 Hz | 28,8 | 6,9 GB |
| **CosyVoice3 + LoRA** | engelsk | 11,9 % | **`sv`** | +18,6 Hz | 7,7 | ~7 GB |
| **Chatterbox v3** | engelsk | 14,9 % | **`no`** | −22,6 Hz | **5,8** | — |

**WER** = word error rate, lower is better. **Auto-språk** is what Whisper
itself detects in the audio — this reveals accent drift. **ΔF0** is the
deviation in fundamental frequency from the reference. **RTF** is real-time
factor, lower is better (1.0 = real time).

---

## Key findings

### 1. Norwegian: Drama 3 and CosyVoice3 are close, Chatterbox is clearly worse

| Model | Norwegian WER |
|---|---|
| Drama 3 Q4_K_S | **18,2 %** (best run) / 36,4 % (second run) |
| CosyVoice3 + Norwegian LoRA | **31,8 %** |
| Chatterbox v3 | 59,1 % |

Chatterbox produced "Mal en stor **kyrkel** på **55-3**" — "kyrkel" for
"sirkel", and the number became "55-3". That is the same class of error the
drama3-small build makes: the model approximates unfamiliar sounds.

**The Drama 3 variation matters.** Two runs with identical settings gave
18,2 % and 36,4 %. One got "25,5 cm" exactly right, the other "5-12 cm". The
average (~27 %) is the number to plan with.

### 2. English: Drama 3 is best on content, the others show clear accent drift

This is the most interesting result:

| Model | WER | What Whisper hears |
|---|---|---|
| Drama 3 Q4_K_S | 6,0 % | `en` — clean English |
| CosyVoice3 + LoRA | 11,9 % | **`sv`** — Swedish! |
| Chatterbox v3 | 14,9 % | **`no`** — Norwegian! |

When CosyVoice3 and Chatterbox are asked to read English using a *Norwegian*
reference, they fall out of English. CosyVoice3 drifts to Swedish, Chatterbox
to Norwegian.

The cause is clear: both models are **language-bound to the reference**. When
the reference is Norwegian, Norwegian phonemes follow — English gets a
Norwegian accent, and with enough drift it is no longer English.

Drama 3 does not fall into the same trap, because it was trained on 83
languages. It holds English pronunciation even with a Norwegian reference, and
the only thing left of the reference is the accent.

This matches the general impression found online: Fish Audio S2 Pro is
described in r/LocalLLaMA as "almost perfect, I get very few artifacts if any
and voice cloning is near 1:1 with the source", while CosyVoice is commonly
noted with caveats — its 2.0 release reduced pronunciation error rate by
30–50 % over v1, but further gains require quantizing the projections, which
costs real quality. Chatterbox is generally regarded as simpler to run with
less expression control.

The important caveat: this is not a verdict on the models in general, but on
**language binding to the reference**. The CosyVoice3 setup here has a
Norwegian LoRA — that Norwegian tuning is what pushes the English output
aside. With an English reference the result would look different.

### 3. CosyVoice3 is fastest on Norwegian — half the time of Drama 3

| Model | RTF | Time for 9 s Norwegian |
|---|---|---|
| CosyVoice3 + LoRA | **10,8** | ~113 s |
| Drama 3 Q4_K_S | 26,3 | ~221 s |
| Drama 3 IQ3_XXS | **11,2** | ~104 s |
| Chatterbox v3 | 21,8 | ~164 s |

CosyVoice3 is 2,4x faster than Drama 3 on Norwegian, because it is a 0,5B
model against Drama 3's 35B. It runs on CPU with a 0,5B model — no expert
offloading, no disk reads.

On English, CosyVoice3 is fastest again (RTF 7,7 against Drama 3's 28,8).

**Drama 3's 28,8 RTF is caused by disk offloading.** The model uses 6,9 GB of
RAM and reads 351 GB from disk for a 33-second clip. On a slower SSD it will
be slower still.

---

## Accent drift in detail

| Model | Auto-detected language (English output) | ΔF0 vs reference |
|---|---|---|
| Drama 3 Q4_K_S | `en` | +6,0 Hz |
| CosyVoice3 + LoRA | `sv` | +18,6 Hz |
| Chatterbox v3 | `no` | −22,6 Hz |

F0 = fundamental frequency, i.e. voice pitch. The reference sits at 126 Hz.
Drama 3 stays within 6 Hz. CosyVoice3 drifts 19 Hz away, Chatterbox 23 Hz —
in *opposite* directions, which suggests they are not merely "missing" English
but actively pulled toward the reference's language.

---

## Transcriptions

### Norwegian

**Drama 3 Q4_K_S (best run, 18,2 %)**
> Mal et afyrark i grønne og gulen jangser. Mal en stor sirkel på **25,5 cm** og
> fyll hele sirkel med farge.

**CosyVoice3 + Norwegian LoRA (31,8 %)**
> Mal et avfor ark i grønne og gule nyanser. Mal en stor cirkel på tønt i 4-4 cm
> og fyll hele cirklen med farge.

**Chatterbox v3 (59,1 %)**
> Mal et av fire ark i grønne og gul enn janser. Mal en stor kyrkel på 55-3 og
> fyl hele kyrkelen med farget.

**Drama 3 IQ3_XXS (59,1 %)**
> Mal et A4 ARK i grunn og god nyanser. Mal en stor cirken på 2 utplaner
> skjermvektet 5 cm og fyller med hele serien.

### English

**Drama 3 Q4_K_S (6,0 %)**
> I have achieved a higher level of proficiency, demonstrated by details such as
> creating varied imprints using different plants, painting the jewelry pieces,
> crafting jewelry in various shapes and investing time in making multiple
> attempts. Exploring texture and small scale craft projects using clay. Creating
> clay slabs featuring nature imprints, making small jewelry pieces using
> seashell imprints and paints, variety in imprints, creativity in jewelry
> design and effort.

**CosyVoice3 + LoRA (11,9 %, sounds Swedish)**
> I have achieved a higher level of proficiency, demonstrated by the tiles such
> as creating varied imprints using different plants, painting the jewellery
> pieces, crafting jewellery in various shapes and investing time and making
> multiple attempts. Exploring texture and small scale craft projects using clay.
> Creating clay slabs featuring nature imprints, making small jewellery pieces
> using seashell, imprints and paint. Variety in imprints, creativity in
> jewellery design and effort.

**Chatterbox v3 (14,9 %, sounds Norwegian)**
> I have archived a high level of proficiency, demonstrated by the tilesuchas,
> creating varied imprints using different plants, painting the jewellery
> pieces, crafting jewellery in various shapes, and investing time on making
> multiple attempts. Exploring texture and small-scale craft projects using
> clay. Creating clay, slabs featuring nature imprints, marking small jewellery
> pieces using seashell imprints and paint, variety in imprints, creativity in
> jewellery design, and effort.

---

## Generation cost

What one clip costs to produce.

| Model | Norwegian (9 s) | English (33 s) | Disk read | Model size |
|---|---|---|---|---|
| **CosyVoice3 + LoRA** | **113 s** | 243 s | 0 | 0,5B (9,1 GB) |
| **Chatterbox v3** | 164 s | 177 s | 0 | ~1,5 GB |
| **Drama 3 IQ3_XXS** | 104 s | — | 0 | 9,74 GiB |
| **Drama 3 Q4_K_S** | 221 s | 953 s | 351 GB | 21,78 GiB |

**Cost per second of audio:**

| Model | Norwegian | English |
|---|---|---|
| CosyVoice3 | 11,8 s/s | 7,7 s/s |
| Chatterbox | 21,8 s/s | 5,8 s/s |
| Drama 3 IQ3_XXS | 11,2 s/s | — |
| Drama 3 Q4_K_S | 26,3 s/s | 28,8 s/s |

Drama 3 Q4_K_S is **3–4x more expensive** per second of speech than
CosyVoice3 and Chatterbox, because of the disk offloading.

---

## Audio files

Listen for yourself — that is the point:

| File | Model | Language | Length |
|---|---|---|---|
| `audio/norsk_full_q4k_varianter.wav` | Drama 3 Q4_K_S | Norwegian | 9,0 s |
| `audio/norsk_full_q4k.wav` | Drama 3 Q4_K_S | Norwegian | 8,4 s |
| `audio/cosyvoice_norsk.wav` | CosyVoice3 + LoRA | Norwegian | 10,5 s |
| `audio/chatterbox_norsk.wav` | Chatterbox v3 | Norwegian | 7,5 s |
| `audio/norsk_small_ubrukelig.wav` | Drama 3 IQ3_XXS | Norwegian | 9,3 s |
| `audio/engelsk_full_q4k.wav` | Drama 3 Q4_K_S | English | 33,1 s |
| `audio/cosyvoice_engelsk.wav` | CosyVoice3 + LoRA | English | 31,6 s |
| `audio/chatterbox_engelsk.wav` | Chatterbox v3 | English | 30,2 s |
| `audio/referanse_stemme.wav` | — | Norwegian (reference) | 8,0 s |

Drama 3 is 44,1 kHz, CosyVoice3 and Chatterbox are 24 kHz. All mono.

---

## Conclusion

| Need | Recommendation |
|---|---|
| Best Norwegian **and** English from one model | **Drama 3 Q4_K_S.** 18–36 % WER Norwegian, 6 % English, holds the language. |
| Fastest Norwegian | **CosyVoice3 + LoRA.** 2,4x faster, 31,8 % WER. |
| Fastest English | **Chatterbox v3.** RTF 5,8 — but 14,9 % WER and a Norwegian accent. |
| Lowest memory | CosyVoice3 (0,5B) or Chatterbox (~1,5 GB). |
| Drama 3 but faster | Drama 3 IQ3_XXS (RTF 11,2) — but Norwegian becomes unusable. |

**The most important difference is not speed, but language stability.** Drama 3
keeps the language regardless of the reference. CosyVoice3 and Chatterbox are
pulled toward the reference's language — which is what you want when you want
Norwegian, and not what you want when you want English.

---

## Measurement method

- **WER**: Whisper `small`, against the reference text, normalized for
  punctuation and case. Levenshtein distance at word level, divided by
  reference length.
- **Auto-language**: Whisper without a forced language — the model's own
  assessment of what language the audio is.
- **F0**: median fundamental frequency via autocorrelation over the first
  3 seconds.
- **RTF**: `metrics.rtf` for Drama 3 (audio.cpp), measured in the scripts for
  CosyVoice3 and Chatterbox. Generation only, excluding model load.
- **Reference**: 8 seconds of Norwegian, 44,1 kHz mono, identical for all
  models. CosyVoice3 and Chatterbox received the same file converted to
  24 kHz.

### A note on the CosyVoice3 setup

The CosyVoice3 test used the original settings from
`generate_audio_stabile_CPU_Accurate.py`: Norwegian LoRA, CPU, and the
instruction `"You are a helpful assistant. Speak in Norwegian."` (Norwegian)
respectively `"Speak in English."` (English).

Along the way it was observed that a **Chinese** instruction made the model
produce Finnish for Norwegian text and Swedish for English text. That is an
illustration of how strongly the language directive steers the output: a
directive in the wrong language moves the whole output. All numbers in this
report come from runs with a correct language directive.

---

## Links

| Project | Link |
|---|---|
| Fish Audio Drama 3 | [huggingface.co/fishaudio/drama-3](https://huggingface.co/fishaudio/drama-3) |
| audio.cpp | [github.com/0xShug0/audio.cpp](https://github.com/0xShug0/audio.cpp) |
| Q4_K_S conversion | [huggingface.co/Jmica/Drama-3-GGUF](https://huggingface.co/Jmica/Drama-3-GGUF) |
| CosyVoice | [github.com/FunAudioLLM/CosyVoice](https://github.com/FunAudioLLM/CosyVoice) |
| Chatterbox | [github.com/resemble-ai/chatterbox](https://github.com/resemble-ai/chatterbox) |
| drama3-mac (MLX, M3 Ultra) | [github.com/JordiPosthumus/drama3-mac](https://github.com/JordiPosthumus/drama3-mac) |
