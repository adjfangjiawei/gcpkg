#!/usr/bin/env bash
# End-to-end smoke test: build OpenSSL, build the example project, verify the
# merged compilation database and run the produced binary.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=${GCPKG_BIN:-"$ROOT/build/bin/gcpkg"}
STORE=${GCPKG_STORE:-"$HOME/.cache/gcpkg-smoke-store"}
PROJECT="$ROOT/examples/hello"

if [[ ! -x "$BIN" ]]; then
    echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j" >&2
    exit 1
fi
mkdir -p "$HOME/.cache"

"$BIN" doctor
"$BIN" build "$PROJECT" --store "$STORE" --ports "$ROOT/ports" -j "$(nproc)"

python3 - "$PROJECT" <<'PY'
import json, os, sys
project = sys.argv[1]
db = json.load(open(os.path.join(project, "compile_commands.json")))
assert len(db) > 100, f"too few compile commands: {len(db)}"
openssl = [e for e in db if "/openssl-3.4.1/" in e["file"] and e["file"].endswith(".c")]
project_files = [e for e in db if e["file"].endswith("src/main.c")]
assert openssl, "no OpenSSL translation units in merged compdb"
assert project_files, "no project translation units in merged compdb"
for e in db[:2000]:
    assert os.path.isabs(e["file"]), e
    assert os.path.isfile(e["file"]), "stale source path: " + e["file"]
    assert e.get("arguments") or e.get("command"), e
inc = [a for a in project_files[0]["arguments"] if a.startswith("-I")]
assert any("openssl-3.4.1" in i and i.endswith("include") for i in inc), inc
print(f"compile_commands.json: {len(db)} entries "
      f"({len(openssl)} OpenSSL C files, {len(project_files)} project files)")
print("all referenced source files exist -> clangd can navigate dependency sources")
PY

"$PROJECT/.gcpkg/build/hello-gcpkg"

# If clangd is available, prove that BOTH the project file and an OpenSSL
# source file can be parsed with the merged compilation database.
CLANGD=""
for candidate in clangd clangd-22 clangd-19 clangd-18; do
    if command -v "$candidate" >/dev/null 2>&1; then
        CLANGD="$candidate"
        break
    fi
done
if [[ -n "$CLANGD" ]]; then
    DEP_FILE=$(python3 - "$PROJECT" <<'PY'
import json, os, sys
db = json.load(open(os.path.join(sys.argv[1], "compile_commands.json")))
print(next(e["file"] for e in db if "/openssl-3.4.1/" in e["file"]))
PY
)
    "$CLANGD" --check="$PROJECT/src/main.c" --compile-commands-dir="$PROJECT" --log=error
    "$CLANGD" --check="$DEP_FILE" --compile-commands-dir="$PROJECT" --log=error
    echo "clangd check OK (project source + dependency source)"
else
    echo "clangd not installed; skipping clangd check"
fi

echo "smoke test OK"
