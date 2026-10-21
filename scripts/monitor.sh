#!/bin/bash
#
#  OVERVÅKINGSVINDU for Drama 3-pruning-prosjektet
#  -------------------------------------------------
#  Kjøres i et eget screen-vindu (eller Terminal) og oppdateres hvert 5 sekunder.
#
#  Viser: fremdrift, status, målinger, og hva som skjer nå.
#
set -u
cd ~/fish_drama3_35b_exert_offloading

PROJ=~/fish_drama3_35b_exert_offloading
PRUNE=~/drama3-prune

refresh() {
    clear
    NOW=$(date +"%H:%M:%S")
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    printf "║  DRAMA 3 PRUNING — M1 Pro 16 GB          %-22s ║\n" "$NOW"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""

    # ── Steg-status ────────────────────────────────────────────
    echo "▸ PIPELINESTEG  (orkestrator, deadline 10:00)"
    ORC="$PROJ/out/orchestrator.log"
    get_step() { grep -q "$1" "$ORC" 2>/dev/null && echo "✔ ferdig" || echo "…"; }
    printf "  %-42s %s\n" "1. Routing-statistikk (norsk)" "$([ -f "$PROJ/out/routing_no.txt" ] && echo "pågår ($(wc -l < "$PROJ/out/routing_no.txt" 2>/dev/null | tr -d ' ') linjer)" || echo '…')"
    printf "  %-42s %s\n" "2. Routing -> .pt" "$(get_step 'STEG 2: ferdig' || echo '…')"
    printf "  %-42s %s\n" "3. Prune Q4_K_S -> 100 eksperter" "$([ -f "$PROJ/models/drama3-pruned-no-100.gguf" ] && echo '✔ ferdig' || echo '…')"
    printf "  %-42s %s\n" "4. Validering mot Q4_K_S" "$([ -f "$PROJ/out/valid_pruned100_norsk.wav" ] && echo '✔ ferdig' || echo '…')"
    printf "  %-42s %s\n" "5. Q2_K-test: offload" "$([ -f "$PROJ/out/q2k_norsk_offload.wav" ] && echo '✔ ferdig' || echo '…')"
    printf "  %-42s %s\n" "6. Q2_K-test: resident" "$([ -f "$PROJ/out/q2k_norsk_resident.wav" ] && echo '✔ ferdig' || echo '…')"
    echo ""
    echo "  Deadline: 10:00  |  " $(tail -1 "$ORC" 2>/dev/null | cut -c1-70)
    echo ""

    # ── Aktive prosesser ───────────────────────────────────────
    echo "▸ AKTIVE PROSESSER"
    FOUND=0
    while read -r PID CPU CMD; do
        [ -z "$PID" ] && continue
        FOUND=1
        printf "  PID %-7s CPU %-6s %s\n" "$PID" "$CPU" "$(echo "$CMD" | cut -c1-46)"
    done < <(ps aux | grep -E "audiocpp_cli|samle_routing|orchestrator|prune_gguf|convert_pruned" | grep -v grep | awk '{printf "%s %s %s\n", $2, $3"%", substr($0, index($0,$11), 46)}')
    [ $FOUND -eq 0 ] && echo "  (ingen)"
    echo ""

    # ── Tidslinje ──────────────────────────────────────────────
    echo "▸ TIDSLINJE"
    DL=$(python3 -c "
from datetime import datetime, timedelta
now = datetime.now()
dl = now.replace(hour=10, minute=0, second=0, microsecond=0)
if dl < now: dl += timedelta(days=1)
m = int((dl-now).total_seconds()//60)
print(f'{m//60}t {m%60:02d}m igjen til deadline 10:00')
" 2>/dev/null)
    echo "  $DL"
    if [ -f "$PROJ/out/orchestrator.log" ]; then
        tail -4 "$PROJ/out/orchestrator.log" | sed 's/^/  /' | cut -c1-84
    fi
    echo ""

    # ── Routing-fremdrift ───────────────────────────────────────
    if [ -f "$PROJ/out/routing_no.txt" ]; then
        RL=$(wc -l < "$PROJ/out/routing_no.txt" | tr -d ' ')
        echo "▸ ROUTING-STATISTIKK (norsk)"
        echo "  linjer samlet: $RL / 35 000   (40 lag × 256 eksperter × 35 setninger)"
        python3 - << 'PYEOF' 2>/dev/null
import collections
c = collections.Counter()
try:
    for line in open('/Users/sondre/fish_drama3_35b_exert_offloading/out/routing_no.txt'):
        if line.startswith('#'):
            continue
        p = line.split()
        if len(p) == 4:
            c[int(p[0])] += int(p[2])
    if c:
        tot = sum(c.values())
        print(f"  routing-hendelser: {tot}   lag med data: {len(c)}/40")
except Exception:
    pass
PYEOF
        echo ""
    fi

    # ── Modeller på disk ────────────────────────────────────────
    echo "▸ MODELLER"
    for m in models/drama-3-backbone-4bit-experts-Q4_K_S.gguf \
             models/drama-3-backbone-8bit-experts-Q2_K.gguf \
             models/drama3-small-IQ3_XXS.gguf \
             models/drama3-pruned-no-100.gguf; do
        if [ -f "$PROJ/$m" ]; then
            printf "  %-48s %s\n" "$(basename $m)" "$(du -h "$PROJ/$m" | cut -f1)"
        fi
    done
    echo ""

    # ── Målinger fra tidligere kjøringer ────────────────────────
    echo "▸ MÅLINGER (fra tidligere kjøringer)"
    for f in out/q2k_norsk_offload.wav out/q2k_norsk_resident.wav; do
        [ -f "$PROJ/$f" ] && echo "  ✔ $f"
    done
    if [ -f "$PROJ/out/q2k_resultat.txt" ]; then
        echo "  ── Q2_K resultat ──"
        grep -E "exit=|wall=|peak|lyd:|Variant" "$PROJ/out/q2k_resultat.txt" 2>/dev/null | sed 's/^/  /' | head -20
    fi
    echo ""

    # ── Siste logglinjer ───────────────────────────────────────
    echo "▸ SISTE LOGGLINJER"
    for L in out/q2k_offload.log out/q2k_resident.log out/routing_no.log; do
        if [ -f "$PROJ/$L" ]; then
            echo "  ── $L ──"
            tail -3 "$PROJ/$L" 2>/dev/null | grep -vE "compiling|loaded kernel" | cut -c1-88 | sed 's/^/  /'
        fi
    done
    echo ""

    # ── Systemressurser ─────────────────────────────────────────
    echo "▸ SYSTEM"
    top -l 1 -n 0 | grep PhysMem | sed 's/^/  /'
    sysctl vm.swapusage | sed 's/^/  swap: /'
    echo "  disk: $(df -h / | tail -1 | awk '{print $4" ledig ("$5" brukt)"}')"
    echo ""
    echo "  Oppdateres hvert 5. sekund. Ctrl+C for å lukke."
}

while true; do
    refresh
    sleep 5
done
