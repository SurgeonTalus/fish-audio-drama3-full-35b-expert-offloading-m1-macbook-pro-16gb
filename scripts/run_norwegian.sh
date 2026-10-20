#!/bin/bash
# Fish Audio Drama 3 (full 35B, Q4_K_S) — Norwegian attempt
# on Apple Silicon (Metal) with disk-backed expert offloading.
#
# Unlike drama3-small, the FULL Drama 3 was distilled on 83 languages and
# should support Norwegian. This script checks that.
#
# Usage: ./run_norwegian.sh [text_file] [reference_wav] [reference_text_file]

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

BIN="$ROOT/bin/audiocpp_cli"
MODEL="$ROOT/models/drama-3-backbone-4bit-experts-Q4_K_S.gguf"
TEXT_FILE="${1:-$HERE/norwegian_text.txt}"
REF_WAV="${2:-$ROOT/ref/voice_ref_8s.wav}"
REF_TEXT_FILE="${3:-$ROOT/ref/reference_text.txt}"
OUT="${OUT:-$ROOT/out/norwegian.wav}"

for f in "$BIN" "$MODEL" "$TEXT_FILE" "$REF_WAV" "$REF_TEXT_FILE"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing required file: $f" >&2
        exit 1
    fi
done

mkdir -p "$ROOT/out"

REF_TEXT="$(cat "$REF_TEXT_FILE")"
TTS_TEXT="$(cat "$TEXT_FILE")"

echo "Model:     $(basename "$MODEL")"
echo "Reference: $REF_WAV"
echo "Output:    $OUT"
echo

exec "$BIN" \
    --task clon \
    --family fish_drama3 \
    --backend metal \
    --mode offline \
    --model "$MODEL" \
    --voice-ref "$REF_WAV" \
    --request-option "reference_text=$REF_TEXT" \
    --text "$TTS_TEXT" \
    --max-tokens 400 \
    --seed 42 \
    --threads 10 \
    --session-option fish_drama3.disk_experts=true \
    --session-option "fish_drama3.expert_cache_size=${EXPERT_CACHE_SIZE:-8}" \
    --session-option "fish_drama3.cpu_expert_layers=${CPU_EXPERT_LAYERS:-0}" \
    --session-option fish_drama3.context_length=2048 \
    --session-option fish_drama3.codec_backend=cpu \
    --session-option fish_drama3.codec_encoder_chunk_samples=65536 \
    --log \
    --metrics \
    --out "$OUT"
