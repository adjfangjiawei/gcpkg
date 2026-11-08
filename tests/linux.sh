#!/usr/bin/env bash
# Linux plumbing stack regression.
#
# The Linux/X/Wayland/systemd/netfilter ports were all really compiled into a
# store. This test verifies the graph is still bottom-up, every port has a
# usable compilation database (with valid absolute source paths), key artifacts
# exist, and clangd can load several dependency compdbs.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${GCPKG_BIN:-"$ROOT/build/bin/gcpkg"}
PORTS="$ROOT/ports"
STORE=${GCPKG_STORE:-"$HOME/.cache/gcpkg-linux-store"}

if [[ ! -x "$BIN" ]]; then
    echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j" >&2
    exit 1
fi

echo "--- registry / graph ---"
CHECK=$("$BIN" check --ports "$PORTS")
echo "$CHECK"
# Forward-compatible: the registry only grows as more ports are added.
echo "$CHECK" | python3 -c 'import re,sys; n=int(re.search(r"(\d+) ports OK", sys.stdin.read()).group(1)); assert n >= 51, n; print("registry:", n, "ports")'
ORDER=$("$BIN" graph xserver --ports "$PORTS")
echo "$ORDER" | tail -6
ORDER="$ORDER" python3 - <<'PY'
import os, re
names = [m.group(2) for line in os.environ["ORDER"].splitlines()
         for m in [re.search(r"\b(\d+)\.\s+([A-Za-z0-9_.+-]+)", line)] if m]
for dep, top in [("xorgproto", "xserver"), ("libxcb", "libX11"),
                 ("libX11", "xserver"), ("fontutil", "xserver"),
                 ("pixman", "xserver"), ("libdrm", "xserver")]:
    assert names.index(dep) < names.index(top), (dep, top, names)
print("bottom-up order OK:", len(names), "ports for xserver")
PY

echo "--- conditional feature dependency still resolves ---"
"$BIN" graph openssl --ports "$PORTS" --feature=openssl:zlib | grep -q 'zlib'

echo "--- 36 compiled ports: manifests, compdb, artifacts ---"
python3 - "$STORE" <<'PY'
import glob, json, os, sys
store = sys.argv[1]
expected = [
    "libnuma", "libcap", "libseccomp", "libcap-ng", "libmnl", "libnl", "popt",
    "json-c", "libyaml", "libpcap", "libaio", "liburing", "libpciaccess",
    "pixman", "xorgproto", "xcb-proto", "libxkbcommon", "kmod", "util-linux",
    "libxml2", "libnftnl", "iptables", "ipvsadm", "libXau", "libXdmcp",
    "libxcb", "libX11", "dbus", "wayland", "wayland-protocols", "libdrm",
    "libevdev", "libinput", "xserver", "systemd", "fontutil",
]
data_only = {"fontutil", "xcb-proto"}   # headers / XML / .pc only: no TU
total = 0
for name in expected:
    hits = glob.glob(os.path.join(store, "manifest", name + "-*.json"))
    assert hits, "no manifest for " + name
    m = json.load(open(hits[0]))
    n = m.get("compdb_entries", 0)
    total += n
    if name not in data_only:
        assert n > 0, "no compile commands for " + name
    jsonl = os.path.join(store, "compdb", m["key"] + ".jsonl")
    assert os.path.isfile(jsonl), "missing compdb JSONL for " + name
    for line in open(jsonl):
        line = line.strip()
        if not line:
            continue
        e = json.loads(line)
        assert os.path.isabs(e["file"]), (name, e["file"])
        assert os.path.isfile(e["file"]), "stale source: " + e["file"]
    print(f"  {name:<20} {n:>5} compile commands")
print("36 ports checked,", total, "compile commands, all source paths valid")

artifacts = [
    "pkg/xserver-21.1.16/bin/Xvfb",
    "pkg/systemd-257.7/lib/libsystemd.so",
    "pkg/systemd-257.7/lib/libudev.so",
    "pkg/libnuma-2.0.19/lib/libnuma.a",
    "pkg/libX11-1.8.12/lib/libX11.a",
    "pkg/wayland-1.23.1/lib/libwayland-server.a",
    "pkg/libinput-1.28.1/lib/libinput.so",
    "pkg/libxml2-2.14.5/lib/libxml2.a",
    "pkg/iptables-1.8.11/sbin/iptables",
    "pkg/ipvsadm-1.31/sbin/ipvsadm",
    "pkg/xorgproto-2024.1/include/X11/Xproto.h",
    "pkg/fontutil-1.4.2/lib/pkgconfig/fontutil.pc",
]
for rel in artifacts:
    p = os.path.join(store, rel)
    assert os.path.isfile(p) or os.path.islink(p), "missing artifact: " + p
print("key artifacts OK:", len(artifacts))
PY

echo "--- clangd can load dependency compile databases ---"
CLANGD=""
for candidate in clangd clangd-22 clangd-19 clangd-18; do
    if command -v "$candidate" >/dev/null 2>&1; then CLANGD="$candidate"; break; fi
done
if [[ -n "$CLANGD" ]]; then
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    for key in libnuma-2.0.19 wayland-1.23.1 libX11-1.8.12 xserver-21.1.16 systemd-257.7; do
        cp "$STORE/compdb/$key.json" "$TMP/compile_commands.json"
        FILE=$(python3 - "$STORE/compdb/$key.json" <<'PY'
import json, sys
db = json.load(open(sys.argv[1]))
e = next((x for x in db if "/src/" in x["file"] and x["file"].endswith(".c")), db[0])
print(e["file"])
PY
)
        OUT=$("$CLANGD" --check="$FILE" --compile-commands-dir="$TMP" --log=error 2>&1) || true
        # clangd-22 exits non-zero for its own "tweak: SwapBinaryOperands
        # ==> FAIL" noise on some macro-heavy files; that is not a compile
        # diagnostic and the compilation database is still loadable.
        if grep -qE '(^| )error:|fatal error:' <<<"$OUT"; then
            echo "  clangd FAILED: $key ($(basename "$FILE"))" >&2
            echo "$OUT" >&2
            exit 1
        fi
        echo "  clangd OK: $key ($(basename "$FILE"))"
    done
else
    echo "clangd not installed; skipping clangd check"
fi

echo "linux stack test OK"
