#!/usr/bin/env bash
# managed workspace dynamic fixture: managed workspace with local Git origins, recursive
# submodules, dependency injection, cross-project edges and five inner-system
# combinations.  No network access; every Git origin and port is local.
set -euo pipefail
ROOT="${GCPKG_WORKSPACE_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
BIN="${GCPKG_WORKSPACE_BIN:-$ROOT/build/bin/gcpkg}"
ROOT_PORTS="$ROOT/ports"
: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"
W="${GCPKG_WORKSPACE_PROBE_DIR:-$(mktemp -d "$CACHE_DIR/gcpkg-managed-probe.XXXXXX")}"
if [ "${GCPKG_WORKSPACE_KEEP:-0}" != 1 ]; then
    trap 'rm -rf "$W"' EXIT
fi
rm -rf "$W"
mkdir -p "$W/origin" "$W/ws" "$W/gcpkg-ports/fixturemath" "$W/fixture-src" "$W/store"
[ -x "$BIN" ] || { echo "build gcpkg first: cmake -S $ROOT -B $ROOT/build && cmake --build $ROOT/build -j"; exit 1; }
GN_STORE="${GCPKG_WORKSPACE_GN_STORE:-}"
if [ -n "$GN_STORE" ] && [ -x "$GN_STORE/gn" ]; then export PATH="$GN_STORE:$PATH"; fi
GN_ON=0; MESON_ON=0
command -v gn >/dev/null 2>&1 && GN_ON=1
command -v meson >/dev/null 2>&1 && MESON_ON=1
echo "GN_ON=$GN_ON MESON_ON=$MESON_ON"

git_init() {
  local d="$1"; mkdir -p "$d"; cd "$d"
  git init -q -b main
  git config user.name "gcpkg Probe"; git config user.email "probe@example.com"
}

# ---- local gcpkg port, no network -----------------------------------------
cat > "$W/fixture-src/gcpkgmath.h" <<'EOF'
#ifndef GCPKG_MATH_H
#define GCPKG_MATH_H
static inline int gcpkg_math(void) { return 7; }
int gcpkg_math_lib(void);
#endif
EOF
cat > "$W/fixture-src/math.c" <<'EOF'
#include "gcpkgmath.h"
int gcpkg_math_lib(void) { return gcpkg_math(); }
EOF
cat > "$W/gcpkg-ports/fixturemath/build.lua" <<EOF
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local cc = require("gcpkg.build.cc")
return {
    name = "fixturemath",
    version = "1.0.0",
    source = { dir = "${W}/fixture-src" },
    dependencies = {},
    build = function(ctx)
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        fs.mkdirs(incdir); fs.mkdirs(libdir)
        local objs = cc.compile {
            sources = { "math.c" }, includes = { ctx.src }, cwd = ctx.src,
            outdir = util.join(ctx.build_dir, "obj"),
            compiler = ctx.compiler.wrapper_cc, exec = ctx.exec,
            record = ctx.record, log = ctx.log, tag = ctx.key,
        }
        local lib = util.join(libdir, "libfixturemath.a")
        ctx.exec({ "ar", "rcs", lib, objs[1] }, { log = ctx.log })
        ctx.exec({ "cp", "-a", util.join(ctx.src, "gcpkgmath.h"), incdir }, { log = ctx.log })
        return { includes = { incdir }, libdirs = { libdir },
                 libs = { "fixturemath" }, binaries = {} }
    end,
}
EOF
cat > "$W/gcpkg-ports/fixturemath/features.yaml" <<'EOF'
features: {}
versions:
  1.0.0: {}
EOF

# ---- inner Conan package manager stand-in --------------------------------
cat > "$W/fake-conan.py" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
cfg_path = sys.argv[1]
cfg = json.loads(Path(cfg_path).read_text())
assert cfg["inner_package_manager"] == "conan", cfg.get("inner_package_manager")
required = [
    "CONAN_DEPS_JSON", "CONAN_CMAKE_TOOLCHAIN_FILE", "CONAN_MESON_NATIVE_FILE",
    "CONAN_GN_GNI", "CONAN_MAKE_FLAGS_FILE", "CONAN_PREFIX_PATH",
    "CONAN_CMAKE_PREFIX_PATH", "CONAN_INCLUDE_PATH", "CONAN_LIBRARY_PATH",
    "CONAN_PKG_CONFIG_PATH", "CONAN_COMPILE_COMMANDS", "GCPKG_BUILD_DIR",
    "GCPKG_INSTALL_PREFIX", "CONAN_CPPFLAGS", "CONAN_LDFLAGS", "CONAN_LDLIBS",
]
for key in required:
    assert os.environ.get(key), "missing " + key
# Legacy CANON_* aliases are still exported.
for key in ("CANON_ROOT", "CANON_DEPS_JSON", "CANON_ENV_FILE",
            "CANON_CMAKE_TOOLCHAIN_FILE", "CANON_MESON_NATIVE_FILE",
            "CANON_GN_GNI", "CANON_MAKE_FLAGS_FILE", "CANON_PREFIX_PATH",
            "CANON_INCLUDE_PATH", "CANON_LIBRARY_PATH", "CANON_LDLIBS"):
    assert os.environ.get(key), "missing legacy " + key
for key in ("ROOT", "CMAKE_TOOLCHAIN_FILE", "MESON_NATIVE_FILE",
            "GN_GNI", "MAKE_FLAGS_FILE", "PREFIX_PATH", "INCLUDE_PATH",
            "LIBRARY_PATH", "LDLIBS"):
    assert os.environ["CONAN_" + key] == os.environ["CANON_" + key], key
assert Path(os.environ["CANON_DEPS_JSON"]).is_file()
assert Path(os.environ["CANON_ENV_FILE"]).is_file()
for key in ["CONAN_CMAKE_TOOLCHAIN_FILE", "CONAN_MESON_NATIVE_FILE",
            "CONAN_GN_GNI", "CONAN_MAKE_FLAGS_FILE", "CONAN_DEPS_JSON"]:
    assert Path(os.environ[key]).is_file(), os.environ[key]
assert "fixturemath" in os.environ["CONAN_PREFIX_PATH"]
assert os.environ["CONAN_LDLIBS"].find("-lfixturemath") >= 0, os.environ["CONAN_LDLIBS"]
build = Path(os.environ["GCPKG_BUILD_DIR"])
inc = build / "include"
inc.mkdir(parents=True, exist_ok=True)
(inc / "conan_generated.h").write_text("#define CONAN_VALUE 400\n")
src = Path(os.environ["CONAN_PROJECT_DIR"]) / "src/main.cc"
entry = {
    "directory": str(src.parent), "file": str(src),
    "arguments": [os.environ.get("CXX", "c++"), "-c", str(src),
                  "-o", str(build / "conan.o")],
}
Path(os.environ["CONAN_COMPILE_COMMANDS"]).write_text(json.dumps([entry], indent=2) + "\n")
print("conan-inner-ok")
EOF
chmod +x "$W/fake-conan.py"

# ---- nested git submodules -------------------------------------------------
git_init "$W/origin/nested"
mkdir -p include
cat > include/gcpkgnested.h <<'EOF'
#ifndef GCPKG_NESTED_H
#define GCPKG_NESTED_H
#define GCPKG_NESTED_VALUE 200
#endif
EOF
git add -A; git commit -qm nested

git_init "$W/origin/sub"
mkdir -p include
cat > include/gcpkgsub.h <<'EOF'
#ifndef GCPKG_SUB_H
#define GCPKG_SUB_H
#define GCPKG_SUB_VALUE 30
#endif
EOF
git add -A; git commit -qm sub
git -c protocol.file.allow=always submodule add -q "$W/origin/nested" nested
git -c user.name="gcpkg Probe" -c user.email=probe@example.com commit -qam "add nested submodule"

git_init "$W/origin/core"
mkdir -p include src
cat > include/gcpkgcore.h <<'EOF'
#ifndef GCPKG_CORE_H
#define GCPKG_CORE_H
#ifdef __cplusplus
extern "C" {
#endif
int gcpkg_core(void);
#ifdef __cplusplus
}
#endif
#endif
EOF
cat > src/core.c <<'EOF'
#include "gcpkgcore.h"
#include "gcpkgsub.h"
#include "gcpkgnested.h"
#include "gcpkgmath.h"
int gcpkg_core(void) {
    return gcpkg_math_lib() + GCPKG_SUB_VALUE + GCPKG_NESTED_VALUE;
}
EOF
cat > CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(gcpkg_core C)
add_library(core STATIC src/core.c)
target_include_directories(core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/vendor/sub/include
    ${CMAKE_CURRENT_SOURCE_DIR}/vendor/sub/nested/include)
install(TARGETS core ARCHIVE DESTINATION lib)
install(FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/include/gcpkgcore.h
    ${CMAKE_CURRENT_SOURCE_DIR}/vendor/sub/include/gcpkgsub.h
    ${CMAKE_CURRENT_SOURCE_DIR}/vendor/sub/nested/include/gcpkgnested.h
    DESTINATION include)
EOF
git add -A; git commit -qm core
git -c protocol.file.allow=always submodule add -q "$W/origin/sub" vendor/sub
git -c user.name="gcpkg Probe" -c user.email=probe@example.com commit -qam "add sub submodule"

# ---- CMake + Meson + Makefile + GN + Conan/CMake projects ------------------
if [ "$MESON_ON" = 1 ]; then
  git_init "$W/origin/mesonapp"
  mkdir -p src
  cat > meson.build <<'EOF'
project('mesonapp', 'c')
executable('mesonapp', 'src/main.c', install: true)
EOF
  cat > src/main.c <<'EOF'
#include <stdio.h>
#include "gcpkgcore.h"
#include "gcpkgmath.h"
int main(void) {
    printf("meson %d %d\n", gcpkg_core(), gcpkg_math());
    return 0;
}
EOF
  git add -A; git commit -qm mesonapp
fi

git_init "$W/origin/makeapp"
mkdir -p src
cat > Makefile <<'EOF'
CC ?= cc
CPPFLAGS ?=
CFLAGS ?=
LDFLAGS ?=
LDLIBS ?=
PREFIX ?= /usr/local
all: makeapp
makeapp: src/main.o
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)
src/main.o: src/main.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
install: makeapp
	mkdir -p $(PREFIX)/bin
	cp makeapp $(PREFIX)/bin/
clean:
	rm -f makeapp src/main.o
.PHONY: all install clean
EOF
cat > src/main.c <<'EOF'
#include <stdio.h>
#include "gcpkgcore.h"
#include "gcpkgmath.h"
int main(void) {
    printf("make %d %d\n", gcpkg_core(), gcpkg_math());
    return 0;
}
EOF
cat > gcpkg.yaml <<'EOF'
schema: 1
project: makeapp
dependencies: [fixturemath@1.0.0]
system: makefile
features: {}
EOF
git add -A; git commit -qm makeapp

if [ "$GN_ON" = 1 ]; then
  git_init "$W/origin/gnapp"
  mkdir -p src build/toolchain
  cat > .gn <<'EOF'
buildconfig = "//build/BUILDCONFIG.gn"
EOF
  cat > build/BUILDCONFIG.gn <<'EOF'
if (target_os == "") { target_os = host_os }
if (target_cpu == "") { target_cpu = host_cpu }
if (current_cpu == "") { current_cpu = target_cpu }
if (current_os == "") { current_os = target_os }
set_default_toolchain("//build/toolchain:gcc")
EOF
  cat > build/toolchain/BUILD.gn <<'EOF'
toolchain("gcc") {
  tool("cc") {
    depfile = "{{output}}.d"
    command = "gcc -MMD -MF $depfile {{defines}} {{include_dirs}} {{cflags}} -c {{source}} -o {{output}}"
    depsformat = "gcc"
    description = "CC {{output}}"
    outputs = [ "{{source_out_dir}}/{{target_output_name}}.{{source_name_part}}.o" ]
  }
  tool("cxx") {
    depfile = "{{output}}.d"
    command = "g++ -MMD -MF $depfile {{defines}} {{include_dirs}} {{cflags}} {{cflags_cc}} -c {{source}} -o {{output}}"
    depsformat = "gcc"
    description = "CXX {{output}}"
    outputs = [ "{{source_out_dir}}/{{target_output_name}}.{{source_name_part}}.o" ]
  }
  tool("alink") {
    command = "ar rcs {{output}} {{inputs}}"
    description = "AR {{target_output_name}}{{output_extension}}"
    outputs = [ "{{target_out_dir}}/{{target_output_name}}{{output_extension}}" ]
    default_output_extension = ".a"
    output_prefix = "lib"
  }
  tool("solink") {
    soname = "{{target_output_name}}{{output_extension}}"
    sofile = "{{output_dir}}/$soname"
    os_specific_option = "-Wl,-soname=$soname"
    rspfile = "$soname.rsp"
    rspfile_content = "-Wl,--whole-archive {{inputs}} {{solibs}} -Wl,--no-whole-archive {{libs}}"
    command = "g++ -shared {{ldflags}} -o $sofile $os_specific_option @$rspfile"
    description = "SOLINK $soname"
    default_output_extension = ".so"
    default_output_dir = "{{root_out_dir}}"
    outputs = [ sofile ]
    link_output = sofile
    depend_output = sofile
    output_prefix = "lib"
  }
  tool("link") {
    outfile = "{{target_output_name}}{{output_extension}}"
    rspfile = "$outfile.rsp"
    rspfile_content = "{{inputs}}"
    command = "g++ {{ldflags}} -o $outfile -Wl,--start-group @$rspfile {{solibs}} -Wl,--end-group {{libs}}"
    description = "LINK $outfile"
    default_output_dir = "{{root_out_dir}}"
    outputs = [ outfile ]
  }
  tool("stamp") { command = "touch {{output}}" }
  tool("copy") { command = "cp -af {{source}} {{output}}" }
}
EOF
  cat > BUILD.gn <<'EOF'
executable("gnapp") {
  sources = [ "src/main.cc" ]
}
EOF
  cat > src/main.cc <<'EOF'
#include <iostream>
#include "gcpkgmath.h"
int main() {
  std::cout << "gn " << gcpkg_math() << "\n";
  return 0;
}
EOF
  git add -A; git commit -qm gnapp
fi

git_init "$W/origin/conanapp"
mkdir -p src
cat > conanfile.txt <<'EOF'
# Inner Conan package-manager marker. gcpkg never renames conanfile.py/txt.
[requires]
EOF
cat > canonfile <<'EOF'
# Legacy `canon` compatibility marker for Conan.
name = "conanapp"
EOF
cat > CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(conanapp CXX)
include_directories("$ENV{GCPKG_BUILD_DIR}/include")
add_executable(conanapp src/main.cc)
install(TARGETS conanapp RUNTIME DESTINATION bin)
EOF
cat > src/main.cc <<'EOF'
#include <iostream>
#include "gcpkgcore.h"
#include "gcpkgmath.h"
#include "conan_generated.h"
int main() {
    std::cout << "conan+cmake " << gcpkg_core() << " " << gcpkg_math()
              << " " << CONAN_VALUE << "\n";
    return 0;
}
EOF
git add -A; git commit -qm conanapp

git_init "$W/origin/final"
cat > README.md <<'EOF'
Dependency-tree leaf; system: none.
EOF
git add -A; git commit -qm final

# ---- managed workspace -----------------------------------------------------
"$BIN" workspace new "$W/ws" --name=managed-demo
"$BIN" workspace add -C "$W/ws" --name=core --url="$W/origin/core" --ref=main --submodules=recursive --system=cmake
if [ "$MESON_ON" = 1 ]; then
  "$BIN" workspace add -C "$W/ws" --name=mesonapp --url="$W/origin/mesonapp" --ref=main --depends=core --system=meson
fi
"$BIN" workspace add -C "$W/ws" --name=makeapp --url="$W/origin/makeapp" --ref=main --depends=core --system=makefile
if [ "$GN_ON" = 1 ]; then
  "$BIN" workspace add -C "$W/ws" --name=gnapp --url="$W/origin/gnapp" --ref=main --depends=core --system=gn
fi
"$BIN" workspace add -C "$W/ws" --name=conanapp --url="$W/origin/conanapp" --ref=main --depends=core --system=conan,cmake --cmd="python3 $W/fake-conan.py @conan@"
FINAL_DEPS="mesonapp,makeapp,conanapp"
[ "$GN_ON" = 1 ] && FINAL_DEPS="$FINAL_DEPS,gnapp"
[ "$MESON_ON" = 0 ] && FINAL_DEPS="makeapp,conanapp"
"$BIN" workspace add -C "$W/ws" --name=final --url="$W/origin/final" --ref=main --depends="$FINAL_DEPS" --system=none
python3 - <<PY
from pathlib import Path
p = Path("$W/ws/workspace.yaml")
s = p.read_text()
s = s.replace('workspace: "managed-demo"\n', 'workspace: "managed-demo"\npackages: ["fixturemath@1.0.0"]\n', 1)
p.write_text(s)
PY
echo === workspace.yaml ===
cat "$W/ws/workspace.yaml"

echo === graph ===
"$BIN" workspace graph -C "$W/ws" --store "$W/store"
echo === sync ===
"$BIN" workspace sync -C "$W/ws" --store "$W/store"
echo === submodule add ===
"$BIN" workspace submodule add -C "$W/ws" --store "$W/store" --repo=core --url="$W/origin/nested" --path=vendor/extra --git-commit
echo === submodule sync ===
"$BIN" workspace submodule sync core -C "$W/ws" --store "$W/store"
echo === submodule status ===
"$BIN" workspace submodule status core -C "$W/ws" --store "$W/store"
echo === submodule pin ===
"$BIN" workspace submodule pin core -C "$W/ws" --store "$W/store"
echo === pin core ===
"$BIN" workspace pin core -C "$W/ws" --store "$W/store"
echo === unpin/re-pin core ===
"$BIN" workspace pin core --unpin -C "$W/ws" --store "$W/store"
if grep -q '^    commit:' "$W/ws/workspace.yaml"; then
    echo "unpin left a commit in workspace.yaml"; exit 1
fi
"$BIN" workspace pin core -C "$W/ws" --store "$W/store"
grep -q '^    commit: "' "$W/ws/workspace.yaml" || { echo "pin did not write commit"; exit 1; }
echo === update ===
"$BIN" workspace update -C "$W/ws" --store "$W/store"
echo === status ===
"$BIN" workspace status -C "$W/ws" --store "$W/store"
echo === dry-run only conanapp ===
"$BIN" workspace build -C "$W/ws" --store "$W/store" --only=conanapp --dry-run
echo === inject core ===
"$BIN" workspace inject core -C "$W/ws" --store "$W/store" --ports "$W/gcpkg-ports:$ROOT/ports"

echo === full build ===
"$BIN" workspace build -C "$W/ws" --store "$W/store" --ports "$W/gcpkg-ports:$ROOT_PORTS" -j2 | tee "$W/full-build.log"

echo === post-build status ===
"$BIN" workspace status -C "$W/ws" --store "$W/store" | tee "$W/status-after.log"
REPO_COUNT=$(grep -c '^  - name:' "$W/ws/workspace.lock" || true)
CLEAN_COUNT=$(grep -c ' clean ' "$W/status-after.log" || true)
[ "$REPO_COUNT" -ge 4 ] || { echo "too few repositories: $REPO_COUNT"; exit 1; }
[ "$CLEAN_COUNT" -eq "$REPO_COUNT" ] || { echo "dirty tracked repository state after $REPO_COUNT builds"; exit 1; }
grep -Eq 'core +.*submodules=3' "$W/status-after.log" || { echo "recursive submodules not recorded"; exit 1; }

echo === lock pin assertions ===
grep -q 'path: "vendor/sub"' "$W/ws/workspace.lock"
grep -q 'path: "vendor/sub/nested"' "$W/ws/workspace.lock"
grep -q 'path: "vendor/extra"' "$W/ws/workspace.lock"
grep -q '^    commit: "' "$W/ws/workspace.yaml"
grep -q 'generated_by: gcpkg' "$W/ws/workspace.lock"
grep -q 'fixturemath-1.0.0' "$W/ws/workspace.lock"

echo === generated CMake / Meson / GN / env / flags syntax ===
D="$W/ws/.gcpkg/inject/conanapp"
for f in "$D"/*.sh; do bash -n "$f"; done
cmake -P "$D/gcpkg-toolchain.cmake"
cmake -P "$D/gcpkg-cache.cmake"
if command -v gn >/dev/null 2>&1; then
    gn format --stdin < "$D/gcpkg-gn.gni" > /dev/null
    gn format --stdin < "$D/gcpkg-gn-args.gn" > /dev/null
    echo "  GN .gni and args files parse"
fi
cat > "$W/env-check.sh" <<EOF
set -eu
. '$D/gcpkg-env.sh'
test -n "\$GCPKG_INJECT_DIR"
test -n "\$CONAN_DEPS_JSON"
test -n "\$CONAN_CMAKE_TOOLCHAIN_FILE"
test -n "\$CONAN_MESON_NATIVE_FILE"
test -n "\$CONAN_GN_GNI"
test -n "\$CONAN_MAKE_FLAGS_FILE"
test -n "\$CONAN_COMPILE_COMMANDS"
test -n "\$CONAN_LDLIBS"
test -n "\$CANON_ROOT"
test -n "\$CANON_DEPS_JSON"
test -n "\$CANON_CMAKE_TOOLCHAIN_FILE"
test -n "\$CANON_LDLIBS"
test "\$CONAN_ROOT" = "\$CANON_ROOT"
test "\$CONAN_LDLIBS" = "\$CANON_LDLIBS"
test -n "\$CPPFLAGS"
test -n "\$PKG_CONFIG_PATH"
EOF
bash -n "$W/env-check.sh" && bash "$W/env-check.sh"
echo "  shell wrappers, env, CMake scripts and Meson native file OK"

python3 - "$W" <<'PY'
import json, os, sys
W = sys.argv[1]
D = os.path.join(W, "ws", ".gcpkg", "inject", "conanapp")
generic = json.load(open(os.path.join(D, "gcpkg-deps.json")))
conan = json.load(open(os.path.join(D, "gcpkg-conan.json")))
canon_alias = json.load(open(os.path.join(D, "gcpkg-canon.json")))
for manifest in (generic, conan, canon_alias):
    assert manifest["generator"] == "gcpkg"
assert conan["inner_package_manager"] == "conan"
assert canon_alias["inner_package_manager"] == "canon"
assert "conan" in conan["note"].lower()
assert "conan" in canon_alias["note"].lower()
for key in ("CONAN_ROOT", "CONAN_DEPS_JSON", "CONAN_LDLIBS",
            "CANON_ROOT", "CANON_DEPS_JSON", "CANON_LDLIBS"):
    assert key in conan["environment"], key
assert conan["environment"]["CONAN_ROOT"] == conan["environment"]["CANON_ROOT"]
assert len(conan["dependencies"]) >= 1
assert os.path.isfile(conan["files"]["toolchain"])
meson = open(os.path.join(D, "gcpkg-meson.ini")).read()
for line in meson.splitlines():
    if line.startswith(("c_args", "cpp_args", "c_link_args", "cpp_link_args")):
        assert '"' not in line, line
        assert "'" in line, line
flags = open(os.path.join(D, "gcpkg-flags.mk")).read().splitlines()
for key, needle in [("GCPKG_CPPFLAGS", "-I"), ("GCPKG_LDFLAGS", "-L"), ("GCPKG_LDLIBS", "-l")]:
    line = next(l for l in flags if l.startswith(key + " :="))
    value = line.split(":=", 1)[1].lstrip()
    assert needle in value, line
    assert not value.startswith(("'", '"')), line
entries = json.load(open(os.path.join(W, "ws", "compile_commands.json")))
assert len(entries) >= 5, len(entries)
for e in entries:
    assert os.path.isabs(e["file"]), e
    assert os.path.isfile(e["file"]), e
    assert os.path.isabs(e.get("directory", "")), e
    assert e.get("arguments") or e.get("command"), e
link = open(os.path.join(W, "ws", ".gcpkg", "build", "conanapp",
                         "CMakeFiles", "conanapp.dir", "link.txt")).read()
obj = link.find("main.cc.o")
core = link.find("-lcore")
math = link.find("-lfixturemath")
assert 0 <= obj < core < math, link
cache = open(os.path.join(W, "ws", ".gcpkg", "build", "conanapp", "CMakeCache.txt")).read().splitlines()
seen_flags = seen_ldflags = seen_libs = False
for line in cache:
    if line.startswith("CMAKE_CXX_FLAGS:STRING="):
        seen_flags = True
        assert line.count("-I") == 2, line
    if line.startswith("CMAKE_EXE_LINKER_FLAGS:STRING="):
        seen_ldflags = True
        assert line.count("-L") == 2, line
    if line.startswith("CMAKE_CXX_STANDARD_LIBRARIES:STRING="):
        seen_libs = True
        assert "-lcore -lfixturemath" in line, line
assert seen_flags and seen_ldflags and seen_libs
repos = sum(1 for line in open(os.path.join(W, "ws", "workspace.lock"))
            if line.startswith("  - name:"))
with open(os.path.join(W, "results.env"), "w") as f:
    f.write("REPOS=%d\nCOMPDB=%d\n" % (repos, len(entries)))
print("  manifests, machine files, compdb and CMake link order OK")
PY

echo === manual Makefile flags.mk compile ===
MD="$W/ws/.gcpkg/inject/makeapp"
printf 'include %s\nall:\n\t$(CC) $(GCPKG_CPPFLAGS) $(GCPKG_LDFLAGS) %s/ws/repos/makeapp/src/main.c -o %s/manual-make $(GCPKG_LDLIBS)\n' \
    "$MD/gcpkg-flags.mk" "$W" "$W" | make -f - CC=cc
manual_out="$("$W/manual-make")"
echo "manual flags.mk: $manual_out"
[ "$manual_out" = "make 237 7" ] || { echo "manual flags.mk build failed"; exit 1; }

echo === results ===
ls -la "$W/ws/.gcpkg/prefix/core/lib" "$W/ws/.gcpkg/prefix/core/include"
echo === binaries ===
for b in "$W/ws/.gcpkg/prefix/mesonapp/bin/mesonapp" "$W/ws/.gcpkg/prefix/makeapp/bin/makeapp" "$W/ws/.gcpkg/build/gnapp/gnapp" "$W/ws/.gcpkg/prefix/conanapp/bin/conanapp"; do
    if [ -x "$b" ]; then
        out="$("$b")"
        echo "RUN $b -> $out"
        case "$b" in
            *mesonapp*) [ "$out" = "meson 237 7" ] || exit 1 ;;
            *makeapp*)  [ "$out" = "make 237 7" ] || exit 1 ;;
            *gnapp*)    [ "$out" = "gn 7" ] || exit 1 ;;
            *conanapp*) [ "$out" = "conan+cmake 237 7 400" ] || exit 1 ;;
        esac
    fi
done
[ -f "$W/ws/.gcpkg/prefix/core/lib/libcore.a" ]
[ -f "$W/ws/.gcpkg/prefix/core/include/gcpkgcore.h" ]

echo === top-level inject --install from makeapp ===
test ! -f "$W/ws/repos/makeapp/gcpkg.lua"
"$BIN" inject -C "$W/ws/repos/makeapp" --install --store "$W/store" --ports "$W/gcpkg-ports:$ROOT_PORTS"
[ -f "$W/ws/repos/makeapp/gcpkg.lock" ]
echo === top-level build no gcpkg.lua ===
"$BIN" build -C "$W/ws/repos/makeapp" --system=makefile --store "$W/store" --ports "$W/gcpkg-ports:$ROOT_PORTS" -j2
echo === top-level compdb ===
"$BIN" compdb -C "$W/ws/repos/makeapp" --system=makefile --store "$W/store" --ports "$W/gcpkg-ports:$ROOT_PORTS"
python3 - "$W/ws/repos/makeapp/compile_commands.json" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
print("project compdb entries", len(d))
assert len(d) > 0
for e in d:
    assert os.path.isfile(e["file"]), e
PY

echo === upstream tracked sources are untouched ===
for repo in "$W/ws"/repos/*; do
    [ -d "$repo/.git" ] || continue
    if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
        echo "tracked source modified in $repo"
        git -C "$repo" status --porcelain --untracked-files=no
        exit 1
    fi
done
cat "$W/results.env"
echo "managed workspace dynamic OK ($(sed -n 's/^REPOS=//p' "$W/results.env") repositories, $(sed -n 's/^COMPDB=//p' "$W/results.env") compile commands)"
