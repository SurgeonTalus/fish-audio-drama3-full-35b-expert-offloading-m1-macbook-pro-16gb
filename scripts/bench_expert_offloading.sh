#!/bin/bash
# Expert-offloading sweep for Fish Audio Drama 3 (full 35B, Q4_K_S) on
# Apple Silicon / Metal.
#
# The question: how does the full model behave on a 16 GB Mac, and what does
# disk-backed expert offloading cost in speed?
#
# Configurations tested:
#   disk_experts=off  + cpu_expert_layers=0   -> everything resident in Metal
#                      (expected to fail or swap on 16 GB with a 23.4 GB model)
#   disk_experts=off  + cpu_expert_layers=20  -> experts on CPU, no disk streaming
#   disk_experts=on   + cache=8/16/32          -> experts streamed from disk
#   disk_experts=on   + cache=32 + pin_experts -> experts pinned in host RAM
#
# Note: the first run on a machine spends ~140 s compiling Metal kernels.
# Compare metrics.rtf, not wall-clock.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

BIN="$ROOT/bin/audiocpp_cli"
MODEL="$ROOT/models/drama-3-backbone-4bit-experts-Q4_K_S.gguf"
TEXT="Mal et A4-ark i grønne og gule nyanser. Mal en stor sirkel på 25,5 cm."

mkdir -p "$ROOT/out"

if [ ! -f "$MODEL" ]; then
    echo "ERROR: model not found: $MODEL" >&2
    exit 1
fi

run_case () {
    local label="$1"; shift
    local start end
    start=$(date +%s)
    if ! "$BIN" \
        --task tts \
        --family fish_drama3 \
        --backend metal \
        --mode offline \
        --model "$MODEL" \
        --text "$TEXT" \
        --max-tokens 60 \
        --seed 42 \
        --threads 10 \
        --session-option fish_drama3.context_length=1024 \
        --session-option fish_drama3.codec_backend=cpu \
        "$@" \
        --metrics \
        --out "$ROOT/out/bench_${label}.wav" > "$ROOT/out/bench_${label}.log" 2>&1; then
        end=$(date +%s)
        printf '%-22s FAILED after %ss\n' "$label" "$((end-start))"
        tail -5 "$ROOT/out/bench_${label}.log" | sed 's/^/    /'
        return 0
    fi
    end=$(date +%s)
    printf '%-22s wall=%-5ss ' "$label" "$((end-start))"
    local rtf
    rtf=$(grep -oE 'metrics\.rtf=[0-9.]+' "$ROOT/out/bench_${label}.log" | tail -1 | cut -d= -f2)
    echo "RTF=${rtf:-?}"
}

echo "=== Expert offloading sweep: full Drama 3 Q4_K_S on M1 Pro 16 GB ==="
echo

echo "--- 1. Resident (no disk offload), 0 expert layers on CPU ---"
run_case resident_gpu0 \
    --session-option fish_drama3.cpu_expert_layers=0

echo "--- 2. Resident, 20 expert layers on CPU ---"
run_case resident_cpu20 \
    --session-option fish_drama3.cpu_expert_layers=20

echo "--- 3. Disk-backed offload, cache=8 ---"
run_case disk_cache8 \
    --session-option fish_drama3.disk_experts=true \
    --session-option fish_drama3.expert_cache_size=8 \
    --session-option fish_drama3.cpu_expert_layers=0

echo "--- 4. Disk-backed offload, cache=16 ---"
run_case disk_cache16 \
    --session-option fish_drama3.disk_experts=true \
    --session-option fish_drama3.expert_cache_size=16 \
    --session-option fish_drama3.cpu_expert_layers=0

echo "--- 5. Disk-backed offload, cache=32 ---"
run_case disk_cache32 \
    --session-option fish_drama3.disk_experts=true \
    --session-option fish_drama3.expert_cache_size=32 \
    --session-option fish_drama3.cpu_expert_layers=0

echo
echo "=== Swap high-water mark during the sweep ==="
sysctl vm.swapusage
