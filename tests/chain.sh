#!/usr/bin/env bash
# Bottom-up chain test: build the whole curl DAG, build a project on top of it,
# then verify the merged compilation database covers EVERY dependency layer.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${GCPKG_BIN:-"$ROOT/build/bin/gcpkg"}
STORE=${GCPKG_STORE:-"$HOME/.cache/gcpkg-chain-store"}
PROJECT="$ROOT/examples/web"

if [[ ! -x "$BIN" ]]; then
    echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j" >&2
    exit 1
fi
mkdir -p "$HOME/.cache"

"$BIN" graph curl --ports "$ROOT/ports"
"$BIN" install curl --store "$STORE" --ports "$ROOT/ports" -j "$(nproc)"
"$BIN" build "$PROJECT" --store "$STORE" --ports "$ROOT/ports" -j "$(nproc)"

python3 - "$PROJECT" <<'PY'
import json, os, sys, collections
project = sys.argv[1]
db = json.load(open(os.path.join(project, "compile_commands.json")))
layers = {
    "project": "examples/web",
    "curl": "curl-8.13.0",
    "libssh2": "libssh2-1.11.1",
    "nghttp2": "nghttp2-1.65.0",
    "openssl": "openssl-3.4.1",
    "zlib": "zlib-1.3.1",
    "brotli": "brotli-1.1.0",
    "zstd": "zstd-1.5.7",
}
counts = collections.Counter()
for e in db:
    assert os.path.isabs(e["file"]), e
    assert os.path.isfile(e["file"]), "stale source: " + e["file"]
    assert e.get("arguments") or e.get("command"), e
    # CMake writes CompilerId/probe units under <store>/build/...; they are
    # legitimate compdb entries but not upstream source files, so count them
    # separately and pick real sources for the clangd checks below.
    if "/build/" in e["file"]:
        counts["cmake-probes"] += 1
        continue
    for name, marker in layers.items():
        if marker in e["file"]:
            counts[name] += 1
            break
missing = [n for n in layers if not counts[n]]
assert not missing, "dependency layers missing from compdb: " + ", ".join(missing)
assert len(db) > 1000, f"too few compile commands: {len(db)}"
print("compile_commands.json:", len(db), "entries",
      "across", len({os.path.dirname(e["file"]) for e in db}), "directories")
for name, n in sorted(counts.items()):
    print(f"  {name:<13} {n}")
PY

"$PROJECT/.gcpkg/build/web-smoke"

CLANGD=""
for candidate in clangd clangd-22 clangd-19 clangd-18; do
    if command -v "$candidate" >/dev/null 2>&1; then CLANGD="$candidate"; break; fi
done
if [[ -n "$CLANGD" ]]; then
    CLANGD_LIST="$HOME/.cache/gcpkg-chain-clangd-files.txt"
    python3 - "$PROJECT" <<'PY' > "$CLANGD_LIST"
import json, os, sys
db = json.load(open(os.path.join(sys.argv[1], "compile_commands.json")))
for marker, prefer in [("examples/web", None), ("curl-8.13.0", None),
                       ("openssl-3.4.1", None), ("zlib-1.3.1", None),
                       ("libssh2-1.11.1", "session.c")]:
    e = None
    if prefer:
        e = next((x for x in db if marker in x["file"] and x["file"].endswith(prefer)), None)
    e = e or next((x for x in db if marker in x["file"] and "/build/" not in x["file"]), None)
    e = e or next((x for x in db if marker in x["file"]), None)
    if e: print(e["file"])
PY
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        "$CLANGD" --check="$f" --compile-commands-dir="$PROJECT" --log=error
        echo "clangd OK: $f"
    done < "$CLANGD_LIST"
else
    echo "clangd not installed; skipping clangd check"
fi

echo "chain test OK"
