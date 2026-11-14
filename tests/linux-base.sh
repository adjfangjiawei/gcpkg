#!/usr/bin/env bash
# Linux base-library ports: registry, graphs and optional real builds.
#
# Static by default (no download, no compile):
#   * registry / features / two bottom-up graphs
#   * 37 build.lua + features.yaml pairs, real 64-hex SHA256, no sandbox paths
#   * every declared dependency resolves to another port
# GCPKG_BASE_DYNAMIC=1 additionally really compiles a representative subset
# into $GCPKG_STORE (defaults to the shared Linux store so existing L0 ports
# are reused). The remaining ports are validated on the user's machine.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${GCPKG_BIN:-"$ROOT/build/bin/gcpkg"}
PORTS="$ROOT/ports"
STORE=${GCPKG_STORE:-"$HOME/.cache/gcpkg-linux-store"}
LOGDIR=${GCPKG_BASE_LOGDIR:-"$HOME/.cache/gcpkg-base-logs"}

if [[ ! -x "$BIN" ]]; then
    echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j" >&2
    exit 1
fi

NAMES=(
    gmp mpfr mpc nettle libtasn1 libunistring libidn2 libgpg-error libgcrypt
    libsodium mbedtls gnutls libevent libuv jansson sqlite3 ncurses readline
    oniguruma utf8proc xxhash libdeflate libpng libjpeg-turbo libtiff
    freetype fontconfig harfbuzz glib libxslt libusb elfutils libbpf
    libattr libacl libnfnetlink libnetfilter_conntrack
)

echo "--- registry (static) ---"
CHECK=$("$BIN" check --ports "$PORTS")
echo "$CHECK" | tail -1
echo "$CHECK" | python3 -c 'import re,sys; n=int(re.search(r"(\d+) ports OK", sys.stdin.read()).group(1)); assert n >= 111, n; print("registry:", n, "ports")'

echo "--- bottom-up graphs (static) ---"
GN=$("$BIN" graph gnutls --ports "$PORTS")
GN="$GN" python3 - <<'PY'
import os, re
n = [m.group(2) for line in os.environ["GN"].splitlines()
     for m in [re.search(r"\b(\d+)\.\s+([A-Za-z0-9_.+-]+)", line)] if m]
for dep, top in [("gmp", "nettle"), ("gmp", "gnutls"), ("nettle", "gnutls"),
                 ("libunistring", "libidn2"), ("libidn2", "gnutls"),
                 ("libtasn1", "gnutls"), ("zlib", "gnutls")]:
    assert n.index(dep) < n.index(top), (dep, top, n)
print("gnutls chain OK:", " -> ".join(n))
PY
echo "$GN" | tail -3
BP=$("$BIN" graph libbpf --ports "$PORTS")
BP="$BP" python3 - <<'PY'
import os, re
n = [m.group(2) for line in os.environ["BP"].splitlines()
     for m in [re.search(r"\b(\d+)\.\s+([A-Za-z0-9_.+-]+)", line)] if m]
for dep, top in [("zlib", "elfutils"), ("zstd", "elfutils"), ("xz", "elfutils"),
                 ("elfutils", "libbpf")]:
    assert n.index(dep) < n.index(top), (dep, top, n)
print("libbpf chain OK:", " -> ".join(n))
PY
FC=$("$BIN" graph fontconfig --ports "$PORTS")
echo "$FC" | grep -q 'freetype' && echo "$FC" | grep -q 'expat' || { echo "fontconfig graph broken" >&2; exit 1; }
echo "fontconfig chain OK: $(echo "$FC" | grep -c 'gcpkg:info') steps"

echo "--- 37 port declarations (static, no download) ---"
python3 - "$PORTS" "${NAMES[@]}" <<'PY'
import os, re, sys
root, names = sys.argv[1], sys.argv[2:]
all_ports = {n for n in os.listdir(root) if os.path.isfile(os.path.join(root, n, "build.lua"))}
for name in names:
    d = os.path.join(root, name)
    lua = open(os.path.join(d, "build.lua")).read()
    yml = open(os.path.join(d, "features.yaml")).read()
    assert "name = " in lua and "version = " in lua, name
    assert "schema: 1" in yml and "features:" in yml and "port: " + name in yml, name
    local_home = os.path.expanduser("~")
    assert local_home not in lua and local_home not in yml, "sandbox path: " + name
    sha = re.search(r'sha256 = "([0-9a-f]{64})"', lua)
    assert sha, "missing real SHA256: " + name
    url = re.search(r'url = "(https?://[^"]+)"', lua)
    assert url, "missing URL: " + name
    block = lua.split("dependencies =", 1)[1].split("}", 1)[0] if "dependencies =" in lua else ""
    for dep in re.findall(r'"([^"]+)"', block):
        assert dep in all_ports, "unresolved dep %s -> %s" % (name, dep)
print(len(names), "port declarations OK (real URL/SHA256, resolvable deps)")
assert len(all_ports) >= 111, len(all_ports)
print("registry has", len(all_ports), "ports total")
PY
"$BIN" features gnutls --ports "$PORTS" >/dev/null   # YAML is loadable

if [[ "${GCPKG_BASE_DYNAMIC:-0}" == "1" ]]; then
    echo "--- real builds (subset; store: $STORE) ---"
    mkdir -p "$LOGDIR"
    LIST=(xxhash libdeflate jansson utf8proc libpng libgpg-error libsodium
          libattr libacl libnfnetlink ncurses readline libxslt libusb)
    PASS=0; FAIL=0
    for p in "${LIST[@]}"; do
        if timeout 420 "$BIN" install "$p" --store "$STORE" --ports "$PORTS" -j 4 \
                > "$LOGDIR/$p.log" 2>&1; then
            # Cache hits log "reusing ..." instead of a compdb count.
            N=$(grep -o '[0-9]* compile commands' "$LOGDIR/$p.log" | tail -1) || N="cached"
            echo "  PASS $p $N"; PASS=$((PASS+1))
        else
            echo "  FAIL $p (see $LOGDIR/$p.log)"; FAIL=$((FAIL+1))
        fi
    done
    echo "dynamic subset: $PASS PASS / $FAIL FAIL"
    [[ $FAIL -eq 0 ]] || exit 1
    python3 - "$STORE" "${LIST[@]}" <<'PY'
import glob, json, os, sys
store, names = sys.argv[1], sys.argv[2:]
total = 0
for n in names:
    hits = glob.glob(os.path.join(store, "manifest", n + "-*.json"))
    if not hits: continue
    m = json.load(open(hits[0])); total += m.get("compdb_entries", 0)
    print("  %-20s %5d compile commands  libs=%s" % (n, m.get("compdb_entries", 0), m.get("libs", [])[:3]))
print("subset compdb total:", total)
PY
fi

echo "linux base test OK (static)"
