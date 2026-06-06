#!/bin/bash
# cu_map.sh — Read and display CU bitmap from DRM ioctl via libdrm.
#
# Optional health overlay:
#   ./cu_map.sh --health /var/lib/bc250-cu-health-test/results.tsv

set -euo pipefail

HEALTH="${BC250_CU_HEALTH_RESULTS:-/var/lib/bc250-cu-health-test/results.tsv}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --health)
            HEALTH="${2:?missing value for --health}"
            shift 2
            ;;
        --no-health)
            HEALTH=""
            shift
            ;;
        -h|--help)
            sed -n '1,10p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

BC250_CU_HEALTH_RESULTS="$HEALTH" python3 << 'PYEOF'
import ctypes, struct, os, sys

libdrm = ctypes.CDLL("libdrm_amdgpu.so.1")
fd = os.open("/dev/dri/renderD128", os.O_RDWR)
dev = ctypes.c_void_p()
maj, min_ = ctypes.c_uint32(), ctypes.c_uint32()
libdrm.amdgpu_device_initialize(fd, ctypes.byref(maj), ctypes.byref(min_), ctypes.byref(dev))

buf = (ctypes.c_uint8 * 1024)()
libdrm.amdgpu_query_info(dev, 0x16, 1024, ctypes.byref(buf))
raw = bytes(buf)

num_se = struct.unpack_from('<I', raw, 20)[0]
num_sh = struct.unpack_from('<I', raw, 24)[0]
cu_active = struct.unpack_from('<I', raw, 48)[0]

total = 0
rows = []
patterns = []
for se in range(num_se):
    for sh in range(num_sh):
        bm = struct.unpack_from('<I', raw, 56 + (se * 4 + sh) * 4)[0]
        n = bin(bm).count('1')
        total += n
        bar = ''.join('■' if bm & (1 << i) else '□' for i in range(10))
        # check if disabled CUs are contiguous (all packed at one end)
        disabled = [i for i in range(10) if not (bm & (1 << i))]
        if len(disabled) == 0:
            pattern = "full"
        elif disabled == list(range(disabled[0], disabled[0] + len(disabled))):
            pattern = "contiguous"
        else:
            pattern = "scattered"
        rows.append(f"SE{se} SH{sh}: {bar}")
        patterns.append(pattern)

possible = num_se * num_sh * 10
harvested = possible - total
print()
health_path = os.environ.get("BC250_CU_HEALTH_RESULTS", "")
health = {}
if health_path and os.path.exists(health_path):
    with open(health_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 5:
                continue
            _idx, se, sh, wgp, status = parts[:5]
            try:
                health[(int(se), int(sh), int(wgp))] = status
            except ValueError:
                continue

print("BC-250 CU Map" + (" + Health" if health else ""))
for r in rows:
    print(r)
print(f"{total}/{possible} CUs active, {harvested} harvested")

if health:
    usable = 0
    failed = 0
    print()
    print("BC-250 CU Map + Health")
    for se in range(num_se):
        for sh in range(num_sh):
            glyphs = []
            for cu in range(10):
                wgp = cu // 2
                status = health.get((se, sh, wgp))
                if status == "FAIL":
                    glyphs.append("✗")
                elif cu < 6:
                    glyphs.append("■")
                elif status == "PASS":
                    glyphs.append("✓")
                else:
                    glyphs.append("?")
            for wgp in range(5):
                status = health.get((se, sh, wgp))
                if status == "FAIL":
                    failed += 2
                elif wgp < 3 or status == "PASS":
                    usable += 2
            print(f"SE{se} SH{sh}: {''.join(glyphs)}")
    print(f"{usable}/{possible} CUs usable ({failed} defective, masked)")
elif health_path:
    print()
    print(f"Health overlay: no results file found at {health_path}")

libdrm.amdgpu_device_deinitialize(dev)
os.close(fd)
PYEOF
