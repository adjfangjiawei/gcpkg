#!/usr/bin/env bash
# Proxy support regression. Static part always runs; set
# GCPKG_PROXY_DYNAMIC=1 to also drive a real local HTTP CONNECT proxy.
set -euo pipefail

: "${HOME:?HOME must be set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR"
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/build/bin/gcpkg"
T=$(mktemp -d "$CACHE_DIR/gcpkg-proxy-test.XXXXXX")
PROXY_PID=""
cleanup() {
    [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true
    rm -rf "$T"
}
trap cleanup EXIT

export GCPKG_HOME="$T/home"
mkdir -p "$T/home"
# A deterministic environment: all precedence assertions below are explicit.
unset GCPKG_PROXY GCPKG_NO_PROXY HTTPS_PROXY https_proxy HTTP_PROXY http_proxy \
      ALL_PROXY all_proxy NO_PROXY no_proxy

GP=("$BIN" --ports "$ROOT/ports" --store "$T/store")
ok() { echo "  ok: $1"; }
fail() { echo "PROXY TEST FAILED: $1" >&2; exit 1; }
has() { grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"; }
hasnt() { ! grep -Fq -- "$2" "$1" || fail "unexpected '$2' in $1"; }

echo "== registry is still healthy =="
"${GP[@]}" check > "$T/check.log" 2>&1
python3 - "$T/check.log" <<'PY' || fail "registry check"
import re, sys
n = int(re.search(r"(\d+) ports OK", open(sys.argv[1]).read()).group(1))
sys.exit(0 if n >= 226 else 1)
PY
ok ">= 226 ports OK"

echo "== precedence: none / env / CLI / --no-proxy / --noproxy =="
"${GP[@]}" proxy > "$T/p0.log" 2>&1
has "$T/p0.log" "effective: none (direct)"

GCPKG_PROXY=http://env.example:8080 "${GP[@]}" proxy > "$T/p1.log" 2>&1
has "$T/p1.log" "effective: http://env.example:8080 [GCPKG_PROXY]"

GCPKG_PROXY=http://env.example:8080 "${GP[@]}" proxy --proxy=http://cli.example:9090 > "$T/p2.log" 2>&1
has "$T/p2.log" "effective: http://cli.example:9090 [--proxy]"

"${GP[@]}" proxy --no-proxy > "$T/p3.log" 2>&1
has "$T/p3.log" "effective: disabled (--no-proxy / direct)"
hasnt "$T/p3.log" "sample https://github.com : via proxy"

GCPKG_PROXY=http://env.example:8080 "${GP[@]}" proxy --noproxy='github.com,.internal' > "$T/p4.log" 2>&1
has "$T/p4.log" "sample https://github.com : bypassed"

GCPKG_NO_PROXY='localhost,.internal' "${GP[@]}" proxy > "$T/p5.log" 2>&1
has "$T/p5.log" "noproxy candidates        : localhost,.internal"
ok "precedence and bypass list"

echo "== project-specific vs public config, with credentials redacted =="
"${GP[@]}" new "$T/app" --name=app > "$T/new.log" 2>&1
"${GP[@]}" proxy 'http://user:s3cr3t@proj.example:3128' -C "$T/app" > "$T/set.log" 2>&1
has "$T/set.log" "http://***@proj.example:3128"
hasnt "$T/set.log" "s3cr3t"
has "$T/app/gcpkg.yaml" 'proxy: "http://user:s3cr3t@proj.example:3128"'
"${GP[@]}" list -C "$T/app" > "$T/list.log" 2>&1 ||
    fail "project yaml with proxy block broke the project workflow"

"${GP[@]}" proxy -C "$T/app" > "$T/show.log" 2>&1
has "$T/show.log" "effective: http://***@proj.example:3128 [project gcpkg.yaml]"
hasnt "$T/show.log" "s3cr3t"

"${GP[@]}" proxy http://global.example:8080 -g > "$T/setg.log" 2>&1
has "$T/home/gcpkg.yaml" 'proxy: "http://global.example:8080"'
"${GP[@]}" proxy -C "$T/app" > "$T/both.log" 2>&1
has "$T/both.log" "[project gcpkg.yaml]"

"${GP[@]}" proxy --unset -C "$T/app" > "$T/unset.log" 2>&1
"${GP[@]}" proxy -C "$T/app" > "$T/global.log" 2>&1
has "$T/global.log" '[$GCPKG_HOME/gcpkg.yaml]'
"${GP[@]}" proxy --unset -g > "$T/unsetg.log" 2>&1
"${GP[@]}" proxy -C "$T/app" > "$T/clean.log" 2>&1
has "$T/clean.log" "effective: none (direct)"
ok "two scopes + redaction + unset"

echo "== doctor / help / invalid URL / engine integration =="
"${GP[@]}" doctor > "$T/doctor.log" 2>&1
has "$T/doctor.log" "proxy               :"
"${GP[@]}" --help > "$T/help.log" 2>&1
has "$T/help.log" "gcpkg proxy [URL|--unset]"
has "$T/help.log" "--no-proxy"
if "${GP[@]}" --proxy='not-a-url' check > "$T/invalid.log" 2>&1; then
    fail "invalid proxy URL was accepted"
fi
has "$T/invalid.log" "invalid proxy URL"
grep -Fq 'env = proxy.env()' "$ROOT/lua/gcpkg/net.lua" || fail "curl download lost proxy env"
[ "$(grep -c 'env = proxy.env()' "$ROOT/lua/gcpkg/net.lua")" -ge 2 ] ||
    fail "git clone lost proxy env"
grep -Fq 'proxy.env()' "$ROOT/lua/gcpkg/port.lua" || fail "build hooks lost proxy env"
grep -Fq 'proxy.env()' "$ROOT/lua/gcpkg/project.lua" || fail "project builds lost proxy env"
ok "CLI surface, validation, engine wiring"

if [ "${GCPKG_PROXY_DYNAMIC:-0}" != "1" ]; then
    echo "proxy test OK (static)"
    exit 0
fi

echo "== dynamic: real downloads through a local CONNECT proxy =="
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 "$ROOT/tests/fixtures/test-proxy.py" "$PORT" "$T/proxy.log" &
PROXY_PID=$!
for _ in $(seq 1 30); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1',$PORT),1).close()" 2>/dev/null && break
    sleep 0.2
done
python3 -c "import socket; socket.create_connection(('127.0.0.1',$PORT),2).close()" ||
    fail "local proxy did not start"

# 1. one-shot --proxy with credentials: curl must CONNECT, and the password
#    must never appear in the CLI output or any build log.
timeout 300 "${GP[@]}" install inih --store "$T/store-a" \
    --proxy="http://user:s3cr3t@127.0.0.1:$PORT" -j 2 > "$T/a.log" 2>&1 ||
    fail "proxied install failed: $(tail -4 "$T/a.log" | tr '\n' ' ')"
has "$T/proxy.log" "CONNECT codeload.github.com:443"
hasnt "$T/a.log" "s3cr3t"
if grep -R -F -q 's3cr3t' "$T/store-a/logs" 2>/dev/null; then
    fail "proxy credentials leaked into build logs"
fi
N1=$(grep -c '^CONNECT ' "$T/proxy.log" || true)
ok "--proxy with credentials: CONNECT logged, no credential leak"

# 2. --no-proxy must bypass everything, even with GCPKG_PROXY set.
GCPKG_PROXY="http://127.0.0.1:$PORT" timeout 300 "${GP[@]}" install zopfli \
    --store "$T/store-b" --no-proxy -j 2 > "$T/b.log" 2>&1 ||
    fail "direct install failed: $(tail -4 "$T/b.log" | tr '\n' ' ')"
N2=$(grep -c '^CONNECT ' "$T/proxy.log" || true)
[ "$N1" = "$N2" ] || fail "--no-proxy still used the proxy ($N1 -> $N2)"
ok "--no-proxy bypassed the proxy"

# 3. project-level config must reach downloads (no CLI --proxy here).
"${GP[@]}" proxy "http://127.0.0.1:$PORT" -C "$T/app" > "$T/set2.log" 2>&1
timeout 300 "${GP[@]}" install yyjson --store "$T/store-c" -C "$T/app" -j 2 \
    > "$T/c.log" 2>&1 || fail "project-config install failed: $(tail -4 "$T/c.log" | tr '\n' ' ')"
N3=$(grep -c '^CONNECT ' "$T/proxy.log" || true)
[ "$N3" -gt "$N2" ] || fail "project gcpkg.yaml proxy was not used ($N2 -> $N3)"
ok "project gcpkg.yaml proxy reached curl"

# 4. git clones get the same proxy environment (fake git records $https_proxy).
mkdir -p "$T/probe-ports/gitproxyprobe" "$T/fakebin"
cat > "$T/fakebin/git" <<'SH'
#!/bin/sh
printf '%s\n' "$https_proxy" > "$GCPKG_TEST_GIT_ENV"
last=""
for a in "$@"; do last="$a"; done
mkdir -p "$last"
echo probe > "$last/probe.txt"
exit 0
SH
chmod +x "$T/fakebin/git"
cat > "$T/probe-ports/gitproxyprobe/build.lua" <<'LUA'
return {
    name = "gitproxyprobe", version = "1.0.0",
    source = { git = "https://example.invalid/repo.git", ref = "main" },
    dependencies = {},
    build = function(ctx)
        return { includes = {}, libdirs = {}, libs = {}, binaries = {} }
    end,
}
LUA
printf 'schema: 1\nport: gitproxyprobe\nfeatures: {}\n' > "$T/probe-ports/gitproxyprobe/features.yaml"
GCPKG_TEST_GIT_ENV="$T/git.env" PATH="$T/fakebin:$PATH" \
    timeout 120 "${GP[@]}" install gitproxyprobe --ports "$T/probe-ports" \
        --store "$T/store-git" --proxy="http://127.0.0.1:$PORT" > "$T/git.log" 2>&1 ||
    fail "git-clone probe failed: $(tail -4 "$T/git.log" | tr '\n' ' ')"
has "$T/git.env" "http://127.0.0.1:$PORT"
ok "git clone inherited https_proxy"

echo "proxy test OK (dynamic: curl proxy, bypass, project config, git env, no leaks)"
