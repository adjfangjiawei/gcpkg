#!/usr/bin/env bash
# Kernel-interface and storage ports: registry, graphs and optional builds.
#
# Static by default (no download, no compile):
#   * registry / features / three bottom-up graphs (incl. liburing -> libnvme)
#   * 34 build.lua + features.yaml pairs, real 64-hex SHA256, no sandbox paths
#   * every declared dependency resolves to another port
# GCPKG_KERNEL_DYNAMIC=1 really compiles a representative subset and re-checks
# the pre-existing liburing port into $GCPKG_STORE.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${GCPKG_BIN:-"$ROOT/build/bin/gcpkg"}
PORTS="$ROOT/ports"
STORE=${GCPKG_STORE:-"$HOME/.cache/gcpkg-linux-store"}
LOGDIR=${GCPKG_KERNEL_LOGDIR:-"$HOME/.cache/gcpkg-kernel-logs"}

if [[ ! -x "$BIN" ]]; then
    echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j" >&2
    exit 1
fi

NAMES=(
    libnvme nvme-cli libgudev udisks2 libstoragemgmt btrfs-progs e2fsprogs
    lvm2 pciutils libgpiod libiio hidapi libserialport libaudit libunwind
    rpcsvc-proto libconfuse sg3_utils smartmontools libtraceevent libtracefs
    xfsprogs lm-sensors i2c-tools dmidecode mdadm libparted libmicrohttpd
    libdaemon hdparm libatasmart keyutils libtirpc libselinux
)

echo "--- registry (static) ---"
CHECK=$("$BIN" check --ports "$PORTS")
echo "$CHECK" | tail -1
echo "$CHECK" | python3 -c 'import re,sys; n=int(re.search(r"(\d+) ports OK", sys.stdin.read()).group(1)); assert n >= 145, n; print("registry:", n, "ports")'

echo "--- bottom-up graphs (static) ---"
UD=$("$BIN" graph udisks2 --ports "$PORTS")
UD="$UD" python3 - <<'PY'
import os, re
n = [m.group(2) for line in os.environ["UD"].splitlines()
     for m in [re.search(r"\b(\d+)\.\s+([A-Za-z0-9_.+-]+)", line)] if m]
for dep, top in [("liburing", "libnvme"), ("libnvme", "udisks2"),
                 ("glib", "libgudev"), ("libgudev", "udisks2"),
                 ("util-linux", "libparted"), ("libparted", "udisks2"),
                 ("libattr", "libacl"), ("libacl", "udisks2"),
                 ("dbus", "udisks2"), ("libatasmart", "udisks2")]:
    assert n.index(dep) < n.index(top), (dep, top, n)
assert "liburing" in n, "liburing must be in the disk-info chain"
print("udisks2 chain OK (%d steps):" % len(n), " -> ".join(n))
PY
echo "$UD" | tail -3
NV=$("$BIN" graph nvme-cli --ports "$PORTS")
echo "$NV" | grep -q 'liburing' && echo "$NV" | grep -q 'libnvme' || { echo "nvme-cli graph broken" >&2; exit 1; }
echo "nvme-cli chain OK: $(echo "$NV" | grep -c 'gcpkg:info') steps"
TF=$("$BIN" graph libtracefs --ports "$PORTS")
echo "$TF" | grep -q 'libtraceevent' || { echo "tracefs graph broken" >&2; exit 1; }
echo "libtracefs chain OK: $(echo "$TF" | grep -c 'gcpkg:info') steps"

echo "--- 34 port declarations (static, no download) ---"
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
    assert re.search(r'sha256 = "([0-9a-f]{64})"', lua), "missing real SHA256: " + name
    assert re.search(r'url = "(https?://[^"]+)"', lua), "missing URL: " + name
    block = lua.split("dependencies =", 1)[1].split("}", 1)[0] if "dependencies =" in lua else ""
    for dep in re.findall(r'"([^"]+)"', block):
        assert dep in all_ports, "unresolved dep %s -> %s" % (name, dep)
print(len(names), "port declarations OK (real URL/SHA256, resolvable deps)")
assert len(all_ports) >= 145, len(all_ports)
print("registry has", len(all_ports), "ports total")
PY
"$BIN" features udisks2 --ports "$PORTS" >/dev/null
# liburing is part of the registry; keep its declaration available.
"$BIN" graph liburing --ports "$PORTS" | grep -q 'liburing' || { echo "liburing port missing" >&2; exit 1; }
echo "existing liburing port still resolvable"

if [[ "${GCPKG_KERNEL_DYNAMIC:-0}" == "1" ]]; then
    echo "--- real builds (subset; store: $STORE) ---"
    mkdir -p "$LOGDIR"
    LIST=(liburing libnvme nvme-cli libatasmart libtraceevent libtracefs
          keyutils dmidecode pciutils hdparm mdadm libconfuse libdaemon
          rpcsvc-proto libserialport hidapi libunwind sg3_utils smartmontools
          libgpiod libparted libiio)
    PASS=0; FAIL=0
    for p in "${LIST[@]}"; do
        if timeout 420 "$BIN" install "$p" --store "$STORE" --ports "$PORTS" -j 4 \
                > "$LOGDIR/$p.log" 2>&1; then
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
    d = m.get("deps", [])
    print("  %-20s %5d compile commands" % (n, m.get("compdb_entries", 0)))
print("subset compdb total:", total)
PY
fi

echo "linux kernel/disk test OK (static)"
