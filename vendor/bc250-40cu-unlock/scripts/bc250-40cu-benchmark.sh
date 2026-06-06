#!/usr/bin/env bash
# bc250-40cu-benchmark.sh — Reproducible A/B benchmark for 40 CU unlock
#
# Runs llama-bench at 24 CU and 40 CU with matched clocks and cooldown.
# Requires: UMR, Vulkan llama-bench, a GGUF model, patched amdgpu (bc250_cc_write_mode=3)
#
# Usage:
#   sudo ./bc250-40cu-benchmark.sh [model_path] [llama_bench_path]

set -euo pipefail

MODEL="${1:-}"
BENCH="${2:-}"
UMR="${UMR:-}"
COOL_TARGET=76000

info() { printf '\033[0;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[E]\033[0m %s\n' "$*" >&2; exit 1; }

find_umr() {
    for p in /opt/umr/build/src/app/umr /usr/local/bin/umr /usr/bin/umr; do
        [ -x "$p" ] && UMR="$p" && return 0
    done
    return 1
}

find_model() {
    for p in /opt/models/*.gguf /opt/models/*/*.gguf /root/models/*.gguf; do
        [ -f "$p" ] && echo "$p" && return 0
    done
    return 1
}

find_bench() {
    for p in \
        /opt/llama.cpp/build-vulkan/bin/llama-bench \
        /opt/bc250/llama-vulkan-build/bin/llama-bench \
        /usr/local/bin/llama-bench; do
        [ -x "$p" ] && echo "$p" && return 0
    done
    return 1
}

get_temp() {
    cat /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1
}

get_power() {
    cat /sys/kernel/debug/dri/0/amdgpu_pm_info 2>/dev/null | grep "current SoC" | awk '{print $1}'
}

get_sclk() {
    cat /sys/kernel/debug/dri/0/amdgpu_pm_info 2>/dev/null | grep "SCLK" | head -1 | awk '{print $1}'
}

get_vddgfx() {
    cat /sys/kernel/debug/dri/0/amdgpu_pm_info 2>/dev/null | grep "VDDGFX" | awk '{print $1}'
}

wait_cool() {
    local t
    while true; do
        t=$(get_temp)
        [ "$t" -lt "$COOL_TARGET" ] 2>/dev/null && break
        sleep 5
    done
}

set_24cu() {
    "$UMR" -w cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK 0x7 2>/dev/null
    "$UMR" -w cyan_skillfish.gfx1013.mmRLC_PG_ALWAYS_ON_WGP_MASK 0x3 2>/dev/null
}

set_40cu() {
    "$UMR" -w cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK 0x1f 2>/dev/null
    "$UMR" -w cyan_skillfish.gfx1013.mmRLC_PG_ALWAYS_ON_WGP_MASK 0x1f 2>/dev/null
}

run_bench() {
    local label="$1" outfile="$2"
    local spi
    spi=$("$UMR" -r cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK 2>&1 | grep "=>" | awk '{print $NF}')
    local t0
    t0=$(get_temp)

    local benchlib
    benchlib=$(dirname "$BENCH")
    LD_LIBRARY_PATH="$benchlib" "$BENCH" \
        -m "$MODEL" -p 512 -n 0 -ngl 99 -r 1 > "$outfile" 2>&1 &
    local bpid=$!
    sleep 2
    local pwr clk vdd t1
    pwr=$(get_power)
    clk=$(get_sclk)
    vdd=$(get_vddgfx)
    t1=$(get_temp)
    wait $bpid
    local tps
    tps=$(grep "pp512" "$outfile" | sed 's/.*|[[:space:]]*//' | awk '{print $1}')

    printf "  %-35s  %7s tok/s  %5s MHz  %5s mV  %6s W  %s->%sC\n" \
        "$label (SPI=$spi)" "$tps" "$clk" "$vdd" "$pwr" "$((t0/1000))" "$((t1/1000))"
}

# --- auto-detect ---
[ "$(id -u)" = "0" ] || die "Must run as root"

if [ -z "$UMR" ]; then
    find_umr || die "UMR not found. Install from: https://gitlab.freedesktop.org/tomstdenis/umr"
fi
if [ -z "$MODEL" ]; then
    MODEL=$(find_model) || die "No GGUF model found. Pass path as first argument."
fi
if [ -z "$BENCH" ]; then
    BENCH=$(find_bench) || die "No Vulkan llama-bench found. Pass path as second argument."
fi

[ -f "$MODEL" ] || die "Model not found: $MODEL"
[ -x "$BENCH" ] || die "llama-bench not found: $BENCH"

# verify patched amdgpu
cc_mode=$(cat /sys/module/amdgpu/parameters/bc250_cc_write_mode 2>/dev/null || echo "N/A")
if [ "$cc_mode" != "3" ]; then
    die "bc250_cc_write_mode=$cc_mode (need 3). Enable the patched amdgpu first."
fi

cu_count=$(dmesg | grep -o 'active_cu_number [0-9]*' | tail -1 | awk '{print $2}')

echo "================================================================="
echo " BC-250 40 CU A/B/A Benchmark"
echo "================================================================="
echo ""
echo "  Model:  $(basename "$MODEL")"
echo "  Bench:  $BENCH"
echo "  UMR:    $UMR"
echo "  CU enum: $cu_count  CC mode: $cc_mode"
echo "  Governor: $(cat /etc/cyan-skillfish-governor/config.toml 2>/dev/null | grep 'frequency' | tail -1 | tr -d ' ')"
echo ""
printf "  %-35s  %7s        %5s      %5s     %6s    %s\n" \
    "State" "tok/s" "SCLK" "VDDGFX" "Power" "Temp"
printf "  %-35s  %7s        %5s      %5s     %6s    %s\n" \
    "---" "-----" "----" "------" "-----" "----"

# A: 24 CU
set_24cu
wait_cool
run_bench "24 CU (SPI=0x7)" /tmp/bench_24cu.txt

# B: 40 CU
set_40cu
wait_cool
run_bench "40 CU (SPI=0x1F)" /tmp/bench_40cu.txt

# A: 24 CU confirm
set_24cu
wait_cool
run_bench "24 CU confirm (SPI=0x7)" /tmp/bench_24cu_confirm.txt

# Restore 40 CU
set_40cu

echo ""

# Extract tok/s for ratio
tps_24=$(grep "pp512" /tmp/bench_24cu.txt | sed 's/.*|[[:space:]]*//' | awk '{print $1}')
tps_40=$(grep "pp512" /tmp/bench_40cu.txt | sed 's/.*|[[:space:]]*//' | awk '{print $1}')
ratio=$(awk "BEGIN {printf \"%.2f\", $tps_40 / $tps_24}")

echo "  Ratio: $tps_40 / $tps_24 = ${ratio}x"
echo ""
echo "  Expected: ~1.5-1.67x for compute-bound PP"
echo "  If ~1.0x: SPI write may not have taken effect (check dmesg)"
echo ""
echo "================================================================="
