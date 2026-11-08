#!/usr/bin/env bash
# Fifth-round regression: media / AI / networking / vendor-SDK ports.
#
# Static by default (the user validates real builds on their own machine):
#   * registry + features + dependency graph are consistent
#   * every new port has build.lua + features.yaml
#   * downloadable ports carry a real URL + 64-hex SHA256
#   * vendor SDK ports declare the env var that locates the local SDK
#   * no absolute sandbox paths leak into committed port files
#   * all declared dependencies resolve to another port
# Nothing is downloaded and nothing is compiled unless
# GCPKG_MEDIA_DYNAMIC=1 is set.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${GCPKG_BIN:-"$ROOT/build/bin/gcpkg"}
PORTS="$ROOT/ports"
STORE=${GCPKG_STORE:-"$HOME/.cache/gcpkg-media-store"}

if [[ ! -x "$BIN" ]]; then
    echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j" >&2
    exit 1
fi

NAMES=(
    cmake lua alsa-lib libpsl libfuse live555 librtsp ucx
    folly fizz wangle mvfst proxygen redpanda
    vulkan-headers vulkan dcgm nv-image-codec cv-cuda
    nvidia cann nv-codec-sdk dahuaplayer
)
VENDOR=(nvidia cann nv-codec-sdk dahuaplayer)

echo "--- registry (static) ---"
CHECK=$("$BIN" check --ports "$PORTS")
echo "$CHECK" | python3 -c 'import re,sys; n=int(re.search(r"(\d+) ports OK", sys.stdin.read()).group(1)); assert n >= 74, n'
echo "$CHECK" | tail -1
EXT=$("$BIN" externals --ports "$PORTS")
echo "$EXT" | grep -qE '[4-9] external SDK ports' || { echo "expected >=4 vendor SDK ports" >&2; exit 1; }
echo "$EXT" | tail -5

echo "--- bottom-up graphs (static) ---"
ORDER=$("$BIN" graph proxygen --ports "$PORTS")
echo "$ORDER" | tail -4
ORDER="$ORDER" python3 - <<'PY'
import os, re
names = [m.group(2) for line in os.environ["ORDER"].splitlines()
         for m in [re.search(r"\b(\d+)\.\s+([A-Za-z0-9_.+-]+)", line)] if m]
for dep, top in [("cmake", "folly"), ("openssl", "folly"), ("zlib", "folly"),
                 ("folly", "fizz"), ("folly", "proxygen"), ("fizz", "wangle"),
                 ("wangle", "proxygen"), ("mvfst", "proxygen")]:
    assert names.index(dep) < names.index(top), (dep, top, names)
print("proxygen chain OK:", " -> ".join(names))
PY
NV=$("$BIN" graph nv-image-codec --ports "$PORTS")
echo "$NV" | grep -q 'nvidia' && echo "$NV" | grep -q 'cv-cuda' || { echo "CUDA graph broken" >&2; exit 1; }
echo "CUDA chain OK: $(echo "$NV" | grep -c 'gcpkg:info') steps"

echo "--- 23 port declarations (static, no download) ---"
python3 - "$PORTS" "${NAMES[@]}" <<'PY'
import os, re, sys
root, names = sys.argv[1], sys.argv[2:]
vendor = {"nvidia", "cann", "nv-codec-sdk", "dahuaplayer"}
all_ports = {n for n in os.listdir(root) if os.path.isfile(os.path.join(root, n, "build.lua"))}
total = 0
for name in names:
    d = os.path.join(root, name)
    lua = open(os.path.join(d, "build.lua")).read()
    yml = open(os.path.join(d, "features.yaml")).read()
    assert lua.count("name = ") >= 1 and "version = " in lua, name
    assert "schema: 1" in yml and "features:" in yml and "port: " + name in yml, name
    assert "/home/user" not in lua and "/home/user" not in yml, "sandbox path leaked: " + name
    if name in vendor:
        assert 'require("gcpkg.build.external")' in lua, name
        m = re.search(r'env = "(GCPKG_[A-Z_]+)"', lua)
        assert m, "external port without env var: " + name
        assert m.group(1) in yml, "env var not documented in features.yaml: " + name
        assert "external.declare" in lua, name
    else:
        sha = re.search(r'sha256 = "([0-9a-f]{64})"', lua)
        assert sha, "missing real SHA256: " + name
        url = re.search(r'url = "(https?://[^"]+)"', lua)
        assert url, "missing URL: " + name
    # dependency resolution is already covered by `gcpkg check`; here just
    # make sure every literal dep has a directory.
    block = lua.split("dependencies =", 1)[1].split("}", 1)[0] if "dependencies =" in lua else ""
    for dep in re.findall(r'"([^"]+)"', block):
        assert dep in all_ports, "unresolved dep %s -> %s" % (name, dep)
    total += 1
print(total, "port declarations OK (19 downloadable + 4 vendor SDK)")
assert len(all_ports) >= 74, len(all_ports)
print("registry has", len(all_ports), "ports total")
PY

if [[ "${GCPKG_MEDIA_DYNAMIC:-0}" == "1" ]]; then
    echo "--- optional dynamic smoke ---"
    "$BIN" install lua --store "$STORE" --ports "$PORTS" -j 4 >/dev/null
    "$STORE/pkg/lua-5.4.7/bin/lua" -v
    FAKE=$(mktemp -d)
    trap 'rm -rf "$FAKE"' EXIT
    mkdir -p "$FAKE/include" "$FAKE/lib64" "$FAKE/bin"
    printf '/* fake */\n' > "$FAKE/include/cuda_runtime.h"
    GCPKG_NVIDIA_HOME="$FAKE" "$BIN" install nvidia --store "$STORE" --ports "$PORTS" --no-cache >/dev/null
    python3 - "$STORE" "$FAKE" <<'PY'
import glob, json, os, sys
m = json.load(open(glob.glob(os.path.join(sys.argv[1], "manifest", "nvidia-*.json"))[0]))
assert m["includes"] == [sys.argv[2] + "/include"], m["includes"]
assert m["compdb_entries"] == 0
print("external SDK adapter OK:", m["libs"], "from", m["includes"][0])
PY
fi

echo "media stack test OK (static)"
