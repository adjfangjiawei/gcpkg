-- curl 8.13.0 -- R20 new-standard re-audit, final curl-chain port.
-- Declarative recipe.cmake keeps the framework absolute-no-probe injection.
-- Positive features.yaml args drive every capability; seven dynamic requires
-- edges replace the old static dependencies table. pre_build measures host
-- tools/service facts ONCE, pins all CMake find_program results and source
-- package prefixes, and restricts PKG_CONFIG_PATH/LIBDIR to the source ports.
-- post_install truly builds testdeps and curl-examples, runs the upstream
-- runtests.pl custom target, verifies generated docs/pkgconfig/upstream CONFIG
-- and runs independent consumers plus a direct C sanity binary.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")
local triplet = require("gcpkg.triplet")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local DEP_FEATURES = {
    { feature = "openssl", port = "openssl", version = "3.4.1" },
    { feature = "zlib", port = "zlib", version = "1.3.1" },
    { feature = "brotli", port = "brotli", version = "1.1.0" },
    { feature = "zstd", port = "zstd", version = "1.5.7" },
    { feature = "cares", port = "cares", version = "1.34.5" },
    { feature = "http2", port = "nghttp2", version = "1.65.0" },
    { feature = "ssh", port = "libssh2", version = "1.11.1" },
}

local function dep_prefix(ctx, name)
    local m = ctx.dep(name)
    assert(m and m.prefix, "gcpkg: curl: missing dependency prefix: " .. tostring(name))
    return m.prefix
end

local function libdir_of(prefix)
    local p = util.join(prefix, "lib")
    if fs.isdir(p) then return p end
    return util.join(prefix, "lib64")
end

local function pick_lib(prefix, names)
    local dir = libdir_of(prefix)
    for _, name in ipairs(names) do
        local p = util.join(dir, name)
        if fs.isfile(p) then return p end
    end
    return nil
end

local function dep_prefixes(ctx)
    local out = {}
    for _, d in ipairs(DEP_FEATURES) do
        out[#out + 1] = dep_prefix(ctx, d.port)
    end
    return util.uniq(out)
end

local function dep_libdirs(ctx)
    local out = {}
    for _, p in ipairs(dep_prefixes(ctx)) do out[#out + 1] = libdir_of(p) end
    return util.uniq(out)
end

local function dep_includes(ctx)
    local out = {}
    for _, p in ipairs(dep_prefixes(ctx)) do out[#out + 1] = util.join(p, "include") end
    return util.uniq(out)
end

local function pkgconfig_dirs(ctx)
    local out = {}
    for _, p in ipairs(dep_prefixes(ctx)) do
        for _, rel in ipairs({ "lib/pkgconfig", "lib64/pkgconfig", "share/pkgconfig" }) do
            local d = util.join(p, rel)
            if fs.isdir(d) then out[#out + 1] = d end
        end
    end
    return util.uniq(out)
end

local function assert_pc_version(prefix, rel, name, version)
    local p = util.join(prefix, rel, name)
    local text = assert(fs.read(p), "gcpkg: curl: cannot read " .. p)
    assert(text:find("Version: " .. version, 1, true),
           "gcpkg: curl: unexpected pkg-config version in " .. p)
end

local function trim(s)
    local out = (s or ""):gsub("%s+", "")
    return out
end

local function split_colon(s)
    local out = {}
    for part in (tostring(s or "") .. ":"):gmatch("([^:]+):") do
        out[#out + 1] = part
    end
    return out
end

local function fact(text, name)
    return text:match(name .. "=([^\r\n]+)") or ""
end

return recipe.cmake {
    name = "curl",
    version = "8.13.0",
    description = "libcurl with OpenSSL, zlib, Brotli, Zstd, c-ares, nghttp2 and libssh2 source ports",
    license = "curl",
    homepage = "https://curl.se",
    source = {
        url = "https://curl.se/download/curl-8.13.0.tar.gz",
        sha256 = "c261a4db579b289a7501565497658bbd52d3138fdbaccf1490fa918129ab45bc",
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        local on = ctx.features.enabled
        for _, d in ipairs(DEP_FEATURES) do
            assert(on[d.feature],
                   "gcpkg: curl: " .. d.feature .. " feature must be ON for the source-only chain")
        end
        assert(on["static"] or on["shared"],
               "gcpkg: curl: at least one of static/shared must be ON")
        assert(on["shared"],
               "gcpkg: curl: shared libcurl is required by consumers/sanity")
        for _, k in ipairs({ "library", "headers", "cli", "tests", "examples", "docs",
                             "license", "ipv6", "unix-sockets", "tls-srp",
                             "picky-compiler", "pkgconfig", "cmake-package",
                             "consumers", "sanity" }) do
            assert(on[k], "gcpkg: curl: positive feature must be ON: " .. k)
        end

        fs.mkdirs(ctx.build_dir)
        local vdir = util.join(ctx.build_dir, "verify")
        local home = util.join(vdir, "home")
        local tmp = util.join(vdir, "tmp")
        fs.mkdirs(vdir)
        fs.mkdirs(home)
        fs.mkdirs(tmp)

        -- One install-task platform/tool/service measurement. No compiler
        -- probe, no network, no source patch. Facts are written before
        -- configure, so a later failure still leaves the measured boundary.
        local facts_file = util.join(vdir, "platform-facts.txt")
        local probe = util.join(vdir, "platform-facts.sh")
        fs.write(probe, [==[
set -u
out="$1"; root="$2"; src="$3"; vdir="$4"
tool() { command -v "$1" 2>/dev/null || echo ABSENT; }
fs_type="$(stat -f -c %T "$root" 2>/dev/null || echo UNKNOWN)"
wsl=NO
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then wsl=YES; fi
test_data_count="$(find "$src/tests/data" -maxdepth 1 -type f -name 'test[0-9]*' 2>/dev/null | wc -l)"
listen_8990="$( (ss -ltn 2>/dev/null || true) | grep -c ':8990 ' || true)"
listen_4711="$( (ss -ltn 2>/dev/null || true) | grep -c ':4711 ' || true)"
# Upstream tests/servers.pm hard-codes NOLISTENPORT=47. Measure whether an
# IPv4 connect to that port is actually REFUSED on THIS host; on WSL/v9fs it
# can TIMEOUT instead, which changes the expected CURLE error code. IPv6 ::1
# is measured as a control. This is a host network-stack fact, not a probe of
# libcurl and not a static test-number blacklist.
low_port_rc="$(timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/47' >/dev/null 2>&1; echo $?)"
if [ "$low_port_rc" = "124" ]; then low_port_state=TIMEOUT
elif [ "$low_port_rc" = "1" ]; then low_port_state=REFUSED
else low_port_state="OTHER_$low_port_rc"
fi
ipv6_low_port_rc="$(timeout 2 bash -c 'exec 3<>/dev/tcp/::1/47' >/dev/null 2>&1; echo $?)"
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\nfs_type=%s\nwsl=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" "$fs_type" "$wsl" > "$out"
printf 'tool_perl=%s\ntool_python3=%s\ntool_pkgconfig=%s\ntool_cmake=%s\n' \
  "$(tool perl)" "$(tool python3)" "$(tool pkg-config)" "$(tool cmake)" >> "$out"
printf 'tool_ninja=%s\ntool_make=%s\ntool_sh=%s\ntool_bash=%s\n' \
  "$(tool ninja)" "$(tool make)" "$(tool sh)" "$(tool bash)" >> "$out"
printf 'tool_pytest=%s\ntool_nghttpx=%s\ntool_caddy=%s\ntool_vsftpd=%s\n' \
  "$(tool pytest)" "$(tool nghttpx)" "$(tool caddy)" "$(tool vsftpd)" >> "$out"
printf 'tool_httpd=%s\ntool_apxs=%s\ntool_stunnel=%s\ntool_valgrind=%s\n' \
  "$(tool httpd)" "$(tool apxs)" "$(tool stunnel)" "$(tool valgrind)" >> "$out"
printf 'tool_sshd=%s\ntool_docker=%s\nid_u=%s\n' \
  "$(tool sshd)" "$(tool docker)" "$(id -u)" >> "$out"
printf 'listen_8990=%s\nlisten_4711=%s\n' "$listen_8990" "$listen_4711" >> "$out"
printf 'low_port_probe_port=47\nipv4_low_port_connect=%s\nipv4_low_port_rc=%s\nipv6_low_port_rc=%s\n' \
  "$low_port_state" "$low_port_rc" "$ipv6_low_port_rc" >> "$out"
printf 'test_data_count=%s\n' "$test_data_count" >> "$out"
printf 'no_download=YES\nno_compiler_probe=YES\nno_source_patch=YES\n' >> "$out"
printf 'ca_bundle=none\nca_path=none\nca_fallback=OFF\n' >> "$out"
printf 'ca_reason=no_independent_ca_bundle_source_port_no_etc_ssl_probe\n' >> "$out"
printf 'capability_policy=full_upstream_runtests_pl_capability_run_then_official_E_file_only_for_measured_host_service_or_tool_failures\n' >> "$out"
printf 'test_target=test-quiet\ntest_selector=all\n' >> "$out"
printf 'prefill=ON reason=official_upstream_unix_cache_plus_shared_triplet_facts_no_compiler_probe\n' >> "$out"
]==])
        assert(ctx.exec({ "sh", probe, facts_file, ctx.build_dir, ctx.src, vdir },
                        { cwd = ctx.build_dir, log = ctx.log }) == 0,
               "gcpkg: curl: platform facts script failed")

        -- Source-only pkg-config: the R20 wrapper is kept, but BOTH PATH and
        -- LIBDIR are pinned to the exact seven source-port .pc directories.
        r20.restrict_pkgconfig(ctx)
        local pc_dirs = pkgconfig_dirs(ctx)
        local pc_path = table.concat(pc_dirs, ":")
        local prefixes = dep_prefixes(ctx)
        local prefix_path = table.concat(prefixes, ";")
        local libs = dep_libdirs(ctx)
        local includes = dep_includes(ctx)
        local ld_path = table.concat(libs, ":") .. ":" .. util.join(ctx.prefix, "lib") ..
                        ":" .. ((ctx.env or {}).LD_LIBRARY_PATH or "")
        local rpath = table.concat(libs, ";") .. ";" .. util.join(ctx.prefix, "lib") ..
                      ";$ORIGIN/../lib"
        local wrapper = ctx.env.PKG_CONFIG
        assert(wrapper and fs.isfile(wrapper),
               "gcpkg: curl: source-only pkg-config wrapper missing")
        ctx.env.PKG_CONFIG_PATH = pc_path
        ctx.env.PKG_CONFIG_LIBDIR = pc_path
        ctx.env.PKG_CONFIG_EXECUTABLE = wrapper
        ctx.env.GCPKG_PKG_CONFIG_INCLUDE_PREFIXES =
            table.concat(includes, ":") .. ":" .. util.join(ctx.prefix, "include")
        ctx.env.CMAKE_PREFIX_PATH = prefix_path
        ctx.env.LD_LIBRARY_PATH = ld_path
        ctx.env.HOME = home
        ctx.env.TMPDIR = tmp
        ctx.env.CURL_HOME = home
        ctx.env.XDG_CONFIG_HOME = util.join(home, ".config")
        ctx.env.XDG_CACHE_HOME = util.join(home, ".cache")
        ctx.env.XDG_DATA_HOME = util.join(home, ".local", "share")
        ctx.env.http_proxy = ""
        ctx.env.https_proxy = ""
        ctx.env.HTTP_PROXY = ""
        ctx.env.HTTPS_PROXY = ""
        ctx.env.ALL_PROXY = ""
        ctx.env.all_proxy = ""
        ctx.env.NO_PROXY = "127.0.0.1,localhost"
        ctx.env.no_proxy = "127.0.0.1,localhost"

        -- Verify all seven installed source ports through their own .pc files.
        assert_pc_version(dep_prefix(ctx, "openssl"), "lib/pkgconfig", "openssl.pc", "3.4.1")
        assert_pc_version(dep_prefix(ctx, "zlib"), "share/pkgconfig", "zlib.pc", "1.3.1")
        assert_pc_version(dep_prefix(ctx, "brotli"), "lib/pkgconfig", "libbrotlidec.pc", "1.1.0")
        assert_pc_version(dep_prefix(ctx, "zstd"), "lib/pkgconfig", "libzstd.pc", "1.5.7")
        assert_pc_version(dep_prefix(ctx, "cares"), "lib/pkgconfig", "libcares.pc", "1.34.5")
        assert_pc_version(dep_prefix(ctx, "nghttp2"), "lib/pkgconfig", "libnghttp2.pc", "1.65.0")
        assert_pc_version(dep_prefix(ctx, "libssh2"), "lib/pkgconfig", "libssh2.pc", "1.11.1")

        -- Shared one-probe triplet facts become explicit SIZEOF_* values and
        -- curl_config.h.cmake SIZEOF_*_CODE strings. curl_socket_t is int and
        -- curl_off_t is 64-bit off_t on this measured Linux/x86_64 triplet.
        local f = triplet.facts()
        local sizes = f.sizes or {}
        local size_map = {
            { "INT", sizes["int"] }, { "LONG", sizes["long"] },
            { "LONG_LONG", sizes["long long"] }, { "OFF_T", sizes["off_t"] },
            { "CURL_OFF_T", sizes["off_t"] }, { "CURL_SOCKET_T", sizes["int"] },
            { "SIZE_T", sizes["size_t"] }, { "TIME_T", sizes["time_t"] },
        }
        local size_lines = {}
        for _, item in ipairs(size_map) do
            assert(tonumber(item[2]), "gcpkg: curl: missing triplet size for " .. item[1])
            size_lines[#size_lines + 1] = "size_" .. item[1] .. "=" .. tostring(item[2])
        end
        local test_jobs = math.min(tonumber(ctx.jobs) or 8, 8)
        local extra = {
            "ctx_os=" .. tostring(ctx.os),
            "ctx_arch=" .. tostring(ctx.arch),
            "jobs=" .. tostring(ctx.jobs),
            "test_jobs=" .. tostring(test_jobs),
            "test_base_flags=-n -j" .. tostring(test_jobs) .. " -am",
            "perl_exe=" .. fact(assert(fs.read(facts_file), "facts"), "tool_perl"),
            "pkgconfig_exe=" .. fact(assert(fs.read(facts_file), "facts"), "tool_pkgconfig"),
            "pkgconfig_wrapper=" .. wrapper,
            "pc_path_pinned=" .. pc_path,
            "cmake_prefix_pinned=" .. prefix_path,
            "ld_library_path_pinned=" .. ld_path,
            "rpath_pinned=" .. rpath,
            "include_prefixes_pinned=" .. table.concat(includes, ":"),
            "home_override=" .. home,
            "tmpdir_override=" .. tmp,
            "openssl_prefix=" .. dep_prefix(ctx, "openssl"),
            "zlib_prefix=" .. dep_prefix(ctx, "zlib"),
            "brotli_prefix=" .. dep_prefix(ctx, "brotli"),
            "zstd_prefix=" .. dep_prefix(ctx, "zstd"),
            "cares_prefix=" .. dep_prefix(ctx, "cares"),
            "nghttp2_prefix=" .. dep_prefix(ctx, "nghttp2"),
            "libssh2_prefix=" .. dep_prefix(ctx, "libssh2"),
            "dynamic_requires=7",
            "dependencies_empty=1",
            "",
        }
        for _, line in ipairs(size_lines) do extra[#extra + 1] = line end
        extra[#extra + 1] = ""
        fs.write(facts_file, assert(fs.read(facts_file), "gcpkg: curl: missing facts") ..
                            table.concat(extra, "\n"))
        gcpkg.log.info("curl: install-task platform/tool/source-port facts recorded once")
    end,
    cmake = {
        defines = function(ctx)
            local on = ctx.features.enabled
            local text = assert(fs.read(util.join(ctx.build_dir, "verify", "platform-facts.txt")),
                                "gcpkg: curl: missing platform facts for defines")
            local function f(name) return fact(text, name) end
            local perl = f("perl_exe")
            local pkgconfig = f("pkgconfig_wrapper")
            assert(perl ~= "" and perl ~= "ABSENT", "gcpkg: curl: Perl fact missing")
            assert(pkgconfig ~= "" and pkgconfig ~= "ABSENT", "gcpkg: curl: pkg-config wrapper missing")
            local d = {
                CMAKE_BUILD_TYPE = "Release",
                CMAKE_INSTALL_LIBDIR = "lib",
                CMAKE_INSTALL_INCLUDEDIR = "include",
                CMAKE_INSTALL_BINDIR = "bin",
                CMAKE_INSTALL_MANDIR = "share/man",
                CMAKE_INSTALL_DOCDIR = "share/doc/curl",
                CMAKE_INSTALL_RPATH_USE_LINK_PATH = "ON",
                CMAKE_SKIP_BUILD_RPATH = "OFF",
                -- Known-good libssh2 model: CMAKE_PREFIX_PATH + exact
                -- per-dependency pins + disabled package registries. Do NOT
                -- impose FIND_ROOT_PATH_MODE_* here: that can hide host
                -- system libraries from curl's own check_library_exists
                -- paths, while all seven source ports are already pinned
                -- explicitly below.
                CMAKE_PREFIX_PATH = f("cmake_prefix_pinned"),
                CMAKE_INSTALL_RPATH = f("rpath_pinned"),
                CMAKE_BUILD_RPATH = f("rpath_pinned"),
                CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
                CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
                CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
                PKG_CONFIG_EXECUTABLE = pkgconfig,
                PERL_EXECUTABLE = perl,
                -- find_program variables are not compiler probes, but R20
                -- forbids build-time discovery. An empty string is DEFINED and
                -- skips the search; no *-NOTFOUND value is ever used.
                CLANG_TIDY = "",
                TEST_NGHTTPX = "",
                CADDY = "",
                VSFTPD = "",
                HTTPD = "",
                APXS = "",
                HTTPD_NGHTTPX = "",
                GCOV_PATH = "",
                -- Upstream's official Unix no-probe cache plus shared triplet
                -- facts. Framework CMAKE_PROJECT_INCLUDE short-circuits every
                -- check_*/try_compile, so this is a result table, not a probe.
                _CURL_PREFILL = "ON",
                HAVE_BORINGSSL = "0",
                HAVE_AWSLC = "0",
                HAVE_LIBRESSL = "0",
                HAVE_SSL_SET0_WBIO = "1",
                HAVE_OPENSSL_SRP = "1",
                HAVE_LIBSOCKET = "0",
                -- Positive capability defaults.
                BUILD_CURL_EXE = on["cli"] and "ON" or "OFF",
                BUILD_SHARED_LIBS = on["shared"] and "ON" or "OFF",
                BUILD_STATIC_LIBS = on["static"] and "ON" or "OFF",
                BUILD_STATIC_CURL = "OFF",
                BUILD_TESTING = on["tests"] and "ON" or "OFF",
                BUILD_EXAMPLES = on["examples"] and "ON" or "OFF",
                BUILD_LIBCURL_DOCS = on["docs"] and "ON" or "OFF",
                BUILD_MISC_DOCS = on["docs"] and "ON" or "OFF",
                ENABLE_CURL_MANUAL = on["docs"] and "ON" or "OFF",
                CURL_ENABLE_EXPORT_TARGET = on["cmake-package"] and "ON" or "OFF",
                CURL_USE_PKGCONFIG = on["pkgconfig"] and "ON" or "OFF",
                PICKY_COMPILER = on["picky-compiler"] and "ON" or "OFF",
                ENABLE_IPV6 = on["ipv6"] and "ON" or "OFF",
                ENABLE_UNIX_SOCKETS = on["unix-sockets"] and "ON" or "OFF",
                CURL_DISABLE_SRP = on["tls-srp"] and "OFF" or "ON",
                CURL_USE_OPENSSL = on["openssl"] and "ON" or "OFF",
                CURL_ZLIB = on["zlib"] and "ON" or "OFF",
                CURL_BROTLI = on["brotli"] and "ON" or "OFF",
                CURL_ZSTD = on["zstd"] and "ON" or "OFF",
                ENABLE_ARES = on["cares"] and "ON" or "OFF",
                USE_NGHTTP2 = on["http2"] and "ON" or "OFF",
                CURL_USE_LIBSSH2 = on["ssh"] and "ON" or "OFF",
                -- Safe, deterministic capability boundary.
                CURL_WERROR = "OFF",
                CURL_LTO = "OFF",
                CURL_CLANG_TIDY = "OFF",
                CURL_TEST_BUNDLES = "OFF",
                ENABLE_DEBUG = "OFF",
                ENABLE_CURLDEBUG = "OFF",
                ENABLE_THREADED_RESOLVER = "OFF",
                CURL_DISABLE_INSTALL = "OFF",
                CURL_DISABLE_OPENSSL_AUTO_LOAD_CONFIG = "ON",
                CURL_CA_BUNDLE = "none",
                CURL_CA_PATH = "none",
                CURL_CA_FALLBACK = "OFF",
                CURL_CA_EMBED = "",
                -- Missing independent source ports stay OFF; CMake cannot find
                -- host packages. REQUIRED source-port packages are pinned below.
                CURL_USE_LIBPSL = "OFF",
                USE_LIBIDN2 = "OFF",
                CURL_USE_GSSAPI = "OFF",
                CURL_USE_LIBSSH = "OFF",
                USE_LIBRTMP = "OFF",
                CURL_DISABLE_LDAP = "ON",
                CURL_DISABLE_LDAPS = "ON",
                CURL_USE_WOLFSSH = "OFF",
                CURL_USE_GSASL = "OFF",
                CURL_USE_LIBUV = "OFF",
                USE_OPENSSL_QUIC = "OFF",
                USE_NGTCP2 = "OFF",
                USE_QUICHE = "OFF",
                USE_MSH3 = "OFF",
                USE_HTTPSRR = "OFF",
                USE_ECH = "OFF",
                USE_SSLS_EXPORT = "OFF",
                CURL_USE_MBEDTLS = "OFF",
                CURL_USE_BEARSSL = "OFF",
                CURL_USE_WOLFSSL = "OFF",
                CURL_USE_GNUTLS = "OFF",
                CURL_USE_RUSTLS = "OFF",
                CURL_USE_SCHANNEL = "OFF",
                CURL_USE_SECTRANSP = "OFF",
                -- Optional non-REQUIRED package modules only. Never disable
                -- OpenSSL/Cares/Brotli/Zstd/ZLIB/NGHTTP2/Libssh2 REQUIRED calls.
                CMAKE_DISABLE_FIND_PACKAGE_Libpsl = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libidn2 = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libssh = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_WolfSSH = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libgsasl = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_GSS = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libuv = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Librtmp = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_LDAP = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_MbedTLS = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_BearSSL = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_WolfSSL = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_GnuTLS = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Rustls = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Nettle = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_NGTCP2 = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_NGHTTP3 = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Quiche = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_MSH3 = "ON",
            }
            -- SIZEOF_* and their generated curl_config.h.cmake CODE strings.
            for _, key in ipairs({ "INT", "LONG", "LONG_LONG", "OFF_T",
                                   "CURL_OFF_T", "CURL_SOCKET_T", "SIZE_T", "TIME_T" }) do
                local value = f("size_" .. key)
                assert(tonumber(value), "gcpkg: curl: missing size fact " .. key)
                d["SIZEOF_" .. key] = value
                d["SIZEOF_" .. key .. "_CODE"] = "#define SIZEOF_" .. key .. " " .. value
                d["HAVE_SIZEOF_" .. key] = "TRUE"
            end

            -- Exact source-port pins. Pre-defining the upstream find module
            -- input variables also skips every pkg_check_modules() search.
            local ssl = dep_prefix(ctx, "openssl")
            local z = dep_prefix(ctx, "zlib")
            local br = dep_prefix(ctx, "brotli")
            local zst = dep_prefix(ctx, "zstd")
            local ca = dep_prefix(ctx, "cares")
            local h2 = dep_prefix(ctx, "nghttp2")
            local ssh = dep_prefix(ctx, "libssh2")
            local ssl_inc = util.join(ssl, "include")
            local z_inc = util.join(z, "include")
            local br_inc = util.join(br, "include")
            local zst_inc = util.join(zst, "include")
            local ca_inc = util.join(ca, "include")
            local h2_inc = util.join(h2, "include")
            local ssh_inc = util.join(ssh, "include")
            assert(fs.isfile(util.join(ssl_inc, "openssl", "ssl.h")))
            assert(fs.isfile(util.join(z_inc, "zlib.h")))
            assert(fs.isfile(util.join(br_inc, "brotli", "decode.h")))
            assert(fs.isfile(util.join(zst_inc, "zstd.h")))
            assert(fs.isfile(util.join(ca_inc, "ares.h")))
            assert(fs.isfile(util.join(h2_inc, "nghttp2", "nghttp2.h")))
            assert(fs.isfile(util.join(ssh_inc, "libssh2.h")))
            d.OPENSSL_ROOT_DIR = ssl
            d.OPENSSL_INCLUDE_DIR = ssl_inc
            d.OPENSSL_SSL_LIBRARY = assert(pick_lib(ssl, { "libssl.so", "libssl.a" }))
            d.OPENSSL_CRYPTO_LIBRARY = assert(pick_lib(ssl, { "libcrypto.so", "libcrypto.a" }))
            d.OPENSSL_USE_STATIC_LIBS = "OFF"
            d.ZLIB_ROOT = z
            d.ZLIB_INCLUDE_DIR = z_inc
            d.ZLIB_LIBRARY = assert(pick_lib(z, { "libz.so", "libz.a" }))
            d.BROTLI_INCLUDE_DIR = br_inc
            d.BROTLIDEC_LIBRARY = assert(pick_lib(br, { "libbrotlidec.so", "libbrotlidec.a" }))
            d.BROTLICOMMON_LIBRARY = assert(pick_lib(br, { "libbrotlicommon.so", "libbrotlicommon.a" }))
            d.ZSTD_INCLUDE_DIR = zst_inc
            d.ZSTD_LIBRARY = assert(pick_lib(zst, { "libzstd.so", "libzstd.a" }))
            d.CARES_INCLUDE_DIR = ca_inc
            d.CARES_LIBRARY = assert(pick_lib(ca, { "libcares.so", "libcares.a" }))
            -- FindCares.cmake's pkg_check_modules branch normally supplies
            -- CARES_CFLAGS; CMakeLists.txt appends it to the GLOBAL
            -- CMAKE_C_FLAGS. With direct source-port pins that branch is
            -- skipped, and lib/CMakeLists.txt's local CARES_INCLUDE_DIRS
            -- covers only libcurl, not tests/server/*. Upstream itself uses
            -- this CFLAGS mechanism for all targets, so pin it explicitly.
            d.CARES_CFLAGS = "-I" .. ca_inc
            d.CARES_LIBRARY_DIRS = libdir_of(ca)
            d.CARES_VERSION = "1.34.5"
            d.NGHTTP2_INCLUDE_DIR = h2_inc
            d.NGHTTP2_LIBRARY = assert(pick_lib(h2, { "libnghttp2.so", "libnghttp2.a" }))
            d.LIBSSH2_INCLUDE_DIR = ssh_inc
            d.LIBSSH2_LIBRARY = assert(pick_lib(ssh, { "libssh2.so", "libssh2.a" }))
            return d
        end,
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "curl" },
        binaries = { "@PREFIX@/bin/curl" },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local prefix = ctx.prefix
        local libdir = util.join(prefix, "lib")
        if not fs.isdir(libdir) then libdir = util.join(prefix, "lib64") end
        local incdir = util.join(prefix, "include")
        local bindir = util.join(prefix, "bin")
        local pkgdir = util.join(libdir, "pkgconfig")
        local cmakedir = util.join(libdir, "cmake", "CURL")
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(vdir)
        local platform = assert(fs.read(util.join(vdir, "platform-facts.txt")),
                                "gcpkg: curl: missing platform facts")
        local function f(name) return fact(platform, name) end
        local ld_path = f("ld_library_path_pinned")
        local rpath = f("rpath_pinned")
        local pc_path = f("pc_path_pinned") .. ":" .. util.join(prefix, "lib", "pkgconfig")
        local include_prefixes = f("include_prefixes_pinned") .. ":" .. incdir
        local home = f("home_override")
        local tmp = f("tmpdir_override")
        local pkgconfig_exe = f("pkgconfig_exe")
        local pkgconfig_wrapper = f("pkgconfig_wrapper")
        local jobs = tonumber(ctx.jobs) or 8
        local test_jobs = tonumber(f("test_jobs")) or 8
        assert(pkgconfig_exe ~= "" and pkgconfig_exe ~= "ABSENT",
               "gcpkg: curl: pkg-config fact missing")
        assert(pkgconfig_wrapper ~= "" and fs.isfile(pkgconfig_wrapper),
               "gcpkg: curl: pkg-config wrapper missing")

        local tenv = util.merge(ctx.env, {
            HOME = home,
            TMPDIR = tmp,
            CURL_HOME = home,
            XDG_CONFIG_HOME = util.join(home, ".config"),
            XDG_CACHE_HOME = util.join(home, ".cache"),
            XDG_DATA_HOME = util.join(home, ".local", "share"),
            LD_LIBRARY_PATH = ld_path,
            PKG_CONFIG_PATH = pc_path,
            PKG_CONFIG_LIBDIR = pc_path,
            PKG_CONFIG_EXECUTABLE = pkgconfig_wrapper,
            GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = include_prefixes,
            http_proxy = "", https_proxy = "", HTTP_PROXY = "", HTTPS_PROXY = "",
            ALL_PROXY = "", all_proxy = "",
            NO_PROXY = "127.0.0.1,localhost", no_proxy = "127.0.0.1,localhost",
        })

        local function run_capture(cmd, out, rcfile)
            local q = cmd .. " > " .. out .. " 2>&1; echo $? > " .. rcfile
            assert(ctx.exec({ "sh", "-c", q }, { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: curl: capture wrapper failed")
            local rc = trim(assert(fs.read(rcfile), "gcpkg: curl: missing rc file"))
            assert(tonumber(rc), "gcpkg: curl: malformed rc file")
            return rc
        end

        local function count_files(dir, pattern, out)
            local q = "find " .. dir .. " -maxdepth 1 -type f -name '" .. pattern ..
                      "' 2>/dev/null | wc -l > " .. out
            assert(ctx.exec({ "sh", "-c", q }, { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: curl: count_files failed")
            return tonumber(trim(assert(fs.read(out), "gcpkg: curl: missing count")))
        end

        -- Library / headers / CLI / upstream-generated curl-config.
        local curl_so = pick_lib(prefix, { "libcurl.so", "libcurl.so.4", "libcurl.so.4.8.0" })
        if on["library"] then
            if on["static"] then
                assert(fs.isfile(util.join(libdir, "libcurl.a")),
                       "gcpkg: curl: static libcurl.a missing")
            end
            if on["shared"] then
                assert(curl_so, "gcpkg: curl: shared libcurl.so missing")
            end
        end
        if on["headers"] then
            for _, name in ipairs({ "curl.h", "curlver.h", "easy.h", "multi.h", "system.h", "urlapi.h" }) do
                assert(fs.isfile(util.join(incdir, "curl", name)),
                       "gcpkg: curl: installed header missing: " .. name)
            end
            local hdr = assert(fs.read(util.join(incdir, "curl", "curlver.h")),
                               "gcpkg: curl: cannot read curlver.h")
            assert(hdr:find('"8.13.0"', 1, true),
                   "gcpkg: curl: installed header is not 8.13.0")
        end
        if on["cli"] then
            local curl_exe = util.join(bindir, "curl")
            local curl_config = util.join(bindir, "curl-config")
            assert(fs.isfile(curl_exe), "gcpkg: curl: curl executable missing")
            assert(fs.isfile(curl_config), "gcpkg: curl: curl-config missing")
            local ver_out = util.join(vdir, "curl-version.out")
            local ver_rc = util.join(vdir, "curl-version.rc")
            assert(run_capture(curl_exe .. " --version", ver_out, ver_rc) == "0",
                   "gcpkg: curl: curl --version failed")
            local ver = assert(fs.read(ver_out), "gcpkg: curl: missing curl --version")
            for _, needle in ipairs({ "libcurl/8.13.0", "OpenSSL/3.4.1", "zlib/1.3.1",
                                      "brotli/1.1.0", "zstd/1.5.7", "c-ares/1.34.5",
                                      "nghttp2/1.65.0", "libssh2/1.11.1" }) do
                assert(ver:find(needle, 1, true),
                       "gcpkg: curl: curl --version missing " .. needle)
            end
            local cfg_ver_out = util.join(vdir, "curl-config-version.out")
            local cfg_ver_rc = util.join(vdir, "curl-config-version.rc")
            assert(run_capture(curl_config .. " --version", cfg_ver_out, cfg_ver_rc) == "0",
                   "gcpkg: curl: curl-config --version failed")
            assert((assert(fs.read(cfg_ver_out), "missing curl-config version")):find("8.13.0", 1, true),
                   "gcpkg: curl: curl-config version is not 8.13.0")
            local feat_out = util.join(vdir, "curl-config-features.out")
            local feat_rc = util.join(vdir, "curl-config-features.rc")
            assert(run_capture(curl_config .. " --features", feat_out, feat_rc) == "0",
                   "gcpkg: curl: curl-config --features failed")
            local features = (assert(fs.read(feat_out), "missing features")):lower()
            for _, needle in ipairs({ "ssl", "libz", "brotli", "zstd", "asynchdns", "http2",
                                      "ipv6", "unixsockets", "largefile", "alt-svc", "hsts",
                                      "tls-srp", "https-proxy" }) do
                assert(features:find(needle, 1, true),
                       "gcpkg: curl: curl-config --features missing " .. needle)
            end
            assert(not features:find("psl", 1, true) and not features:find("http3", 1, true),
                   "gcpkg: curl: capability boundary violated in curl-config features")
            local proto_out = util.join(vdir, "curl-config-protocols.out")
            local proto_rc = util.join(vdir, "curl-config-protocols.rc")
            assert(run_capture(curl_config .. " --protocols", proto_out, proto_rc) == "0",
                   "gcpkg: curl: curl-config --protocols failed")
            -- curl-config --protocols prints uppercase names (e.g. "SCP SFTP"),
            -- while curl_version_info()->protocols uses lowercase. Compare the
            -- tool output case-insensitively; no capability is weakened.
            local protocols = (assert(fs.read(proto_out), "missing protocols")):lower()
            assert(protocols:find("scp", 1, true) and protocols:find("sftp", 1, true),
                   "gcpkg: curl: SCP/SFTP protocols missing")
        end

        -- docs: upstream Perl-generated man pages, no prebuilt .1/.3 in tarball.
        if on["docs"] then
            local man3 = util.join(prefix, "share", "man", "man3")
            local man1 = util.join(prefix, "share", "man", "man1")
            local man3_count = count_files(man3, "*.3", util.join(vdir, "man3.count"))
            local man1_count = count_files(man1, "*.1", util.join(vdir, "man1.count"))
            assert(man3_count >= 500,
                   "gcpkg: curl: expected at least 500 generated man3 pages, got " .. tostring(man3_count))
            assert(man1_count >= 3,
                   "gcpkg: curl: expected at least 3 generated man1 pages, got " .. tostring(man1_count))
            assert(fs.isfile(util.join(man1, "curl.1")),
                   "gcpkg: curl: generated curl.1 missing")
        end
        if on["license"] then
            r20.license(ctx, { "COPYING", "README", "RELEASE-NOTES", "docs/FAQ",
                               "docs/KNOWN_BUGS", "docs/THANKS", "docs/BUGS.md" })
            local docdir = util.join(prefix, "share", "doc", "curl")
            for _, name in ipairs({ "COPYING", "README", "RELEASE-NOTES", "FAQ",
                                    "KNOWN_BUGS", "THANKS", "BUGS.md" }) do
                assert(fs.isfile(util.join(docdir, name)),
                       "gcpkg: curl: upstream document missing: " .. name)
            end
        end

        -- examples: docs/examples targets are EXCLUDE_FROM_ALL; build the
        -- official curl-examples target and verify every check_PROGRAMS name.
        if on["examples"] then
            assert(ctx.exec({ "cmake", "--build", ctx.build_dir, "--parallel", tostring(jobs),
                              "--target", "curl-examples" },
                            { cwd = ctx.build_dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: curl: upstream curl-examples build failed")
            local inc = assert(fs.read(util.join(ctx.src, "docs", "examples", "Makefile.inc")),
                               "gcpkg: curl: cannot read upstream examples Makefile.inc")
            local start = assert(inc:find("check_PROGRAMS = \\", 1, true),
                                 "gcpkg: curl: check_PROGRAMS missing")
            local stop = assert(inc:find("COMPLICATED_EXAMPLES", start, true),
                                "gcpkg: curl: COMPLICATED_EXAMPLES missing")
            local chunk = inc:sub(start, stop - 1)
            local names = {}
            for line in chunk:gmatch("[^\r\n]+") do
                local name = line:match("^%s+([%w_%.%-]+)%s*\\?%s*$")
                if name and name ~= "" then names[#names + 1] = name end
            end
            assert(#names >= 100, "gcpkg: curl: too few upstream examples: " .. tostring(#names))
            fs.write(util.join(vdir, "example.count"), tostring(#names) .. "\n")
            for _, name in ipairs(names) do
                assert(fs.isfile(util.join(ctx.build_dir, "docs", "examples", name)),
                       "gcpkg: curl: upstream example not built: " .. name)
            end
        end

        -- tests: curl is not a ctest project. Build testdeps then run the
        -- upstream test-quiet custom target (runtests.pl). A full capability
        -- run is authoritative; measured host-service/tool failures are fed to
        -- the official -E exclude-file mechanism, with facts written first.
        if on["tests"] then
            assert(on["cli"], "gcpkg: curl: tests need the curl CLI feature")
            assert(ctx.exec({ "cmake", "--build", ctx.build_dir, "--parallel", tostring(jobs),
                              "--target", "testdeps" },
                            { cwd = ctx.build_dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: curl: upstream testdeps build failed")
            local test_script = util.join(vdir, "run-runtests.sh")
            fs.write(test_script, [==[
set -u
out="$1"; rcfile="$2"; build="$3"; target="$4"; tflags="$5"
export TFLAGS="$tflags"
cmake --build "$build" --target "$target" > "$out" 2>&1
echo $? > "$rcfile"
exit 0
]==])
            local cap_log = util.join(vdir, "runtests-capability.log")
            local cap_rc_file = util.join(vdir, "runtests-capability.rc")
            local final_log = util.join(vdir, "runtests.log")
            local final_rc_file = util.join(vdir, "runtests.rc")
            local facts_file = util.join(vdir, "capability-facts.txt")
            local exclude_file = util.join(vdir, "runtests-exclude.txt")
            local base_flags = f("test_base_flags")
            assert(base_flags ~= "", "gcpkg: curl: test flags fact missing")
            assert(ctx.exec({ "sh", test_script, cap_log, cap_rc_file, ctx.build_dir,
                              "test-quiet", base_flags },
                            { cwd = vdir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: curl: capability runtests wrapper failed")
            local cap_rc = trim(assert(fs.read(cap_rc_file), "missing capability rc"))
            local cap_text = assert(fs.read(cap_log), "missing capability log")
            local cap_ok, cap_total, cap_pct = cap_text:match("TESTDONE: (%d+) tests out of (%d+) reported OK: (%d+)%%")
            local failed_numbers, failed_lines, seen_numbers = {}, {}, {}
            local cap_lines = {}
            for line in cap_text:gmatch("[^\r\n]+") do cap_lines[#cap_lines + 1] = line end
            local function add_failure(num, line)
                failed_lines[#failed_lines + 1] = line
                if not seen_numbers[num] then
                    seen_numbers[num] = true
                    failed_numbers[#failed_numbers + 1] = num
                end
            end
            -- runtests.pl emits BOTH automake "FAIL: N - ..." lines and a
            -- final "FAIL N: 'name' keywords" summary. The TESTFAIL list is
            -- authoritative: every number there must be parsed above.
            local testfail_numbers = {}
            for line in cap_text:gmatch("[^\r\n]+") do
                local num = line:match("^FAIL: (%d+) %- ")
                if num then add_failure(num, line) end
                num = line:match("^FAIL (%d+): ")
                if num then add_failure(num, line) end
                local list = line:match("^TESTFAIL: These test cases failed: ([%d%s]+)$")
                if list then
                    for n in list:gmatch("%d+") do
                        testfail_numbers[#testfail_numbers + 1] = n
                    end
                end
            end
            for _, n in ipairs(testfail_numbers) do
                assert(seen_numbers[n], "gcpkg: curl: TESTFAIL number not parsed: " .. n)
            end
            local missing_tools = {}
            for _, tool in ipairs({ "pytest", "nghttpx", "caddy", "vsftpd", "httpd",
                                    "apxs", "stunnel", "valgrind" }) do
                if f("tool_" .. tool) == "ABSENT" then
                    missing_tools[#missing_tools + 1] = tool
                end
            end
            -- Facts-driven ONLY. A failure is excludable iff it is explicitly
            -- attributable to (a) a tool measured ABSENT in this install task,
            -- or (b) the measured host network-stack fact that IPv4 low-port
            -- connects TIMEOUT instead of returning ECONNREFUSED, for an
            -- upstream test whose OWN data file uses %NOLISTENPORT and expects
            -- error 7/120. No test numbers, enabled feature names, generic
            -- "timeout"/"connect" words, or +/-8-line context are used: any
            -- other failure stays unclassified and HARD-FAILS below, so a real
            -- libcurl regression can never be masked by the official -E file.
            local low_port_state = f("ipv4_low_port_connect")
            local function test_is_nolisten(num)
                local td = fs.read(util.join(ctx.src, "tests", "data", "test" .. num))
                if not td then return false end
                if not td:find("NOLISTENPORT", 1, true) then return false end
                local ec = td:match("<errorcode>%s*(%d+)%s*</errorcode>")
                if ec ~= "7" and ec ~= "120" then return false end
                return td:lower():find("connect to non-listen", 1, true)
            end
            local function classify_line(line)
                local low = line:lower()
                for _, tool in ipairs(missing_tools) do
                    if low:find(tool, 1, true) and
                       (low:find("not found", 1, true) or low:find("failed to start", 1, true) or
                        low:find("missing", 1, true) or low:find("unsupported", 1, true)) then
                        return true
                    end
                end
                return low_port_state == "TIMEOUT" and
                       low:find("connect to non-listen", 1, true)
            end
            local function classify_number(num, line)
                if classify_line(line) then return true end
                return low_port_state == "TIMEOUT" and test_is_nolisten(num)
            end
            local unclassified = {}
            for _, line in ipairs(failed_lines) do
                local num = line:match("^FAIL: (%d+) %- ") or line:match("^FAIL (%d+): ")
                if not num or not classify_number(num, line) then
                    unclassified[#unclassified + 1] = line
                end
            end
            local final_rc, final_text, excluded = cap_rc, cap_text, 0
            local final_flags = base_flags
            local write_facts = function(frc, fok, ftotal, fpct)
                fs.write(facts_file, table.concat({
                    "policy=full upstream runtests.pl capability run; official -E exclude file only for failures attributed to measured ABSENT host tools or the measured IPv4 low-port connect TIMEOUT host network-stack limitation; all other failures hard-fail; facts written first; no test/feature/number blacklist; no source/assertion edits; not ctest",
                    "test_target=test-quiet",
                    "test_selector=all",
                    "test_data_count=" .. f("test_data_count"),
                    "test_jobs=" .. tostring(test_jobs),
                    "capability_flags=" .. base_flags,
                    "capability_rc=" .. cap_rc,
                    "capability_ok=" .. tostring(cap_ok or "ABSENT"),
                    "capability_total=" .. tostring(cap_total or "ABSENT"),
                    "capability_percent=" .. tostring(cap_pct or "ABSENT"),
                    "capability_failed_count=" .. tostring(#failed_numbers),
                    "capability_failed_numbers=" .. table.concat(failed_numbers, ","),
                    "capability_failed_lines=" .. table.concat(failed_lines, " | "),
                    "unclassified_failure_lines=" .. table.concat(unclassified, " | "),
                    "missing_tools=" .. table.concat(missing_tools, ","),
                    "low_port_probe_port=47",
                    "ipv4_low_port_connect=" .. low_port_state,
                    "ipv4_low_port_rc=" .. f("ipv4_low_port_rc"),
                    "ipv6_low_port_rc=" .. f("ipv6_low_port_rc"),
                    "exclude_file=" .. tostring(exclude_file),
                    "excluded=" .. tostring(excluded),
                    "final_flags=" .. final_flags,
                    "final_rc=" .. tostring(frc),
                    "final_ok=" .. tostring(fok or "ABSENT"),
                    "final_total=" .. tostring(ftotal or "ABSENT"),
                    "final_percent=" .. tostring(fpct or "ABSENT"),
                    "",
                }, "\n"))
            end
            write_facts(final_rc, cap_ok, cap_total, cap_pct)
            assert(cap_total, "gcpkg: curl: capability runtests summary missing; facts written")
            assert(#unclassified == 0,
                   "gcpkg: curl: non-service/tool capability failure; facts written: " ..
                   table.concat(unclassified, " | "))
            if #failed_numbers > 0 then
                fs.write(exclude_file, "test: " .. table.concat(failed_numbers, ",") ..
                         ": measured host network-stack/tool capability failure; upstream test data uses %NOLISTENPORT and IPv4 low-port connect was measured TIMEOUT, not REFUSED\n")
                final_flags = base_flags .. " -E " .. exclude_file
                excluded = #failed_numbers
                assert(ctx.exec({ "sh", test_script, final_log, final_rc_file, ctx.build_dir,
                                  "test-quiet", final_flags },
                                { cwd = vdir, env = tenv, log = ctx.log }) == 0,
                       "gcpkg: curl: final runtests wrapper failed")
                final_rc = trim(assert(fs.read(final_rc_file), "missing final rc"))
                final_text = assert(fs.read(final_log), "missing final log")
            else
                fs.write(final_log, final_text)
                fs.write(final_rc_file, final_rc)
            end
            local final_ok, final_total, final_pct =
                final_text:match("TESTDONE: (%d+) tests out of (%d+) reported OK: (%d+)%%")
            write_facts(final_rc, final_ok, final_total, final_pct)
            assert(final_rc == "0", "gcpkg: curl: final runtests rc is not zero")
            assert(not final_text:find("TESTFAIL", 1, true),
                   "gcpkg: curl: final runtests reported TESTFAIL")
            assert(not final_text:find("No tests were performed", 1, true),
                   "gcpkg: curl: runtests performed no tests")
            assert(final_pct == "100", "gcpkg: curl: final runtests is not 100%")
            assert(final_ok == final_total and tonumber(final_total) >= 100,
                   "gcpkg: curl: unexpected final runtests OK/total")
            assert(final_text:find("TESTDONE:", 1, true),
                   "gcpkg: curl: upstream TESTDONE summary missing")
            assert(tonumber(f("test_data_count")) >= 1700,
                   "gcpkg: curl: upstream test-data count unexpectedly small")
            if excluded > 0 then
                assert(tonumber(final_total) == tonumber(cap_total) - excluded,
                       "gcpkg: curl: exclude-file did not remove exactly measured failures")
            end
        end

        -- pkgconfig / upstream CMake package files.
        if on["pkgconfig"] then
            local pc = util.join(pkgdir, "libcurl.pc")
            assert(fs.isfile(pc), "gcpkg: curl: libcurl.pc missing")
            local pct = assert(fs.read(pc), "gcpkg: curl: cannot read libcurl.pc")
            assert(pct:find("Version: 8.13.0", 1, true),
                   "gcpkg: curl: libcurl.pc version is not 8.13.0")
            for _, needle in ipairs({ "openssl", "zlib", "libbrotlidec", "libbrotlicommon",
                                      "libzstd", "libcares", "libnghttp2", "libssh2", "-lcurl" }) do
                assert(pct:find(needle, 1, true),
                       "gcpkg: curl: libcurl.pc missing " .. needle)
            end
        end
        if on["cmake-package"] then
            local config = util.join(cmakedir, "CURLConfig.cmake")
            local version = util.join(cmakedir, "CURLConfigVersion.cmake")
            local targets = util.join(cmakedir, "CURLTargets.cmake")
            local release = util.join(cmakedir, "CURLTargets-release.cmake")
            assert(fs.isfile(config) and fs.isfile(version) and fs.isfile(targets) and fs.isfile(release),
                   "gcpkg: curl: upstream CMake package files missing")
            local ct = assert(fs.read(config), "gcpkg: curl: cannot read CURLConfig.cmake")
            assert(ct:find("find_dependency(OpenSSL", 1, true) and
                   ct:find("find_dependency(ZLIB", 1, true) and
                   ct:find("CURLTargets.cmake", 1, true) and
                   ct:find("CURL::libcurl ALIAS", 1, true),
                   "gcpkg: curl: upstream CURLConfig.cmake is incomplete")
            local tt = assert(fs.read(targets), "gcpkg: curl: cannot read CURLTargets.cmake")
            assert(tt:find("CURL::libcurl_shared", 1, true) and
                   tt:find("CURL::libcurl_static", 1, true),
                   "gcpkg: curl: both exported upstream targets are required")
            assert(not fs.isfile(util.join(cmakedir, "curl-config.cmake")),
                   "gcpkg: curl: homemade lowercase config must not exist")
        end

        -- Independent external consumers: FindPkgConfig, upstream CONFIG and
        -- CMake's FindCURL module. All dependency prefixes/rpaths are pinned.
        local function consumer(dirname, cmake_text, extra_args, tag)
            local src = util.join(vdir, dirname, "src")
            local bin = util.join(vdir, dirname, "build")
            fs.mkdirs(src); fs.mkdirs(bin)
            fs.write(util.join(src, "CMakeLists.txt"), cmake_text)
            local main_tpl = [==[
#include <curl/curl.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != 0) return 2;
    const char *v = curl_version();
    if (!v || !strstr(v, "libcurl/8.13.0")) return 3;
    printf("gcpkg curl @TAG@ consumer ok: %s\n", v);
    curl_global_cleanup();
    return 0;
}
]==]
            fs.write(util.join(src, "main.c"), (main_tpl:gsub("@TAG@", tag)))
            local args = {
                "cmake", "-S", src, "-B", bin,
                "-DCMAKE_PREFIX_PATH=" .. f("cmake_prefix_pinned") .. ";" .. prefix,
                "-DCMAKE_BUILD_RPATH=" .. rpath,
                "-DCMAKE_INSTALL_RPATH=" .. rpath,
                "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON",
                "-DCMAKE_SKIP_BUILD_RPATH=OFF",
                "-DPKG_CONFIG_EXECUTABLE=" .. pkgconfig_wrapper,
                "-DOPENSSL_ROOT_DIR=" .. f("openssl_prefix"),
                "-DOPENSSL_INCLUDE_DIR=" .. util.join(f("openssl_prefix"), "include"),
                "-DOPENSSL_SSL_LIBRARY=" .. assert(pick_lib(f("openssl_prefix"), { "libssl.so", "libssl.a" })),
                "-DOPENSSL_CRYPTO_LIBRARY=" .. assert(pick_lib(f("openssl_prefix"), { "libcrypto.so", "libcrypto.a" })),
                "-DOPENSSL_USE_STATIC_LIBS=OFF",
                "-DZLIB_ROOT=" .. f("zlib_prefix"),
                "-DZLIB_INCLUDE_DIR=" .. util.join(f("zlib_prefix"), "include"),
                "-DZLIB_LIBRARY=" .. assert(pick_lib(f("zlib_prefix"), { "libz.so", "libz.a" })),
                "-DCURL_DIR=" .. cmakedir,
                "-DCURL_INCLUDE_DIR=" .. incdir,
                "-DCURL_LIBRARY=" .. assert(curl_so, "gcpkg: curl: shared libcurl needed by consumers"),
            }
            for _, a in ipairs(extra_args or {}) do args[#args + 1] = a end
            assert(ctx.exec(args, { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: curl: " .. tag .. " consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", bin, "--parallel", tostring(jobs) },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: curl: " .. tag .. " consumer build failed")
            local out = util.join(vdir, dirname .. ".out")
            assert(ctx.exec({ "sh", "-c", util.join(bin, "consumer") .. " > " .. out .. " 2>&1" },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: curl: " .. tag .. " consumer run failed")
            assert((assert(fs.read(out), "missing " .. tag .. " output")):find(tag .. " consumer ok: libcurl/8.13.0", 1, true),
                   "gcpkg: curl: " .. tag .. " consumer did not use installed 8.13.0")
        end

        if on["consumers"] then
            assert(on["pkgconfig"] and on["cmake-package"],
                   "gcpkg: curl: consumers need pkgconfig and cmake-package")
            consumer("pkgconfig-consumer", table.concat({
                "cmake_minimum_required(VERSION 3.16)",
                "project(curl_pkgconfig_consumer C)",
                "find_package(PkgConfig REQUIRED)",
                "pkg_check_modules(CURL REQUIRED IMPORTED_TARGET libcurl>=8.13.0)",
                "add_executable(consumer main.c)",
                "target_link_libraries(consumer PRIVATE PkgConfig::CURL)",
                "",
            }, "\n"), {}, "FindPkgConfig")
            consumer("config-consumer", table.concat({
                "cmake_minimum_required(VERSION 3.16)",
                "project(curl_config_consumer C)",
                "find_package(CURL 8.13.0 CONFIG REQUIRED)",
                "add_executable(consumer main.c)",
                "target_link_libraries(consumer PRIVATE CURL::libcurl)",
                "",
            }, "\n"), {}, "CONFIG")
            consumer("module-consumer", table.concat({
                "cmake_minimum_required(VERSION 3.16)",
                "project(curl_module_consumer C)",
                "find_package(CURL 8.13.0 REQUIRED MODULE)",
                "add_executable(consumer main.c)",
                "target_include_directories(consumer PRIVATE ${CURL_INCLUDE_DIRS})",
                "target_link_libraries(consumer PRIVATE ${CURL_LIBRARIES})",
                "",
            }, "\n"), { "-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=OFF" }, "FindCURL")
        end

        -- ldd must show source-port shared libraries, never host libssl/libz/...
        local ldd_out = util.join(vdir, "ldd.out")
        assert(ctx.exec({ "sh", "-c", "ldd " .. assert(curl_so) .. " > " .. ldd_out .. " 2>&1" },
                        { cwd = vdir, env = tenv }) == 0,
               "gcpkg: curl: ldd failed")
        local ldd_text = assert(fs.read(ldd_out), "gcpkg: curl: missing ldd output")
        local source_roots = split_colon(f("cmake_prefix_pinned"):gsub(";", ":"))
        local function line_has_source_prefix(line)
            for _, root in ipairs(source_roots) do
                if line:find(root, 1, true) then return true end
            end
            return false
        end
        for _, lib in ipairs({ "libssl.so", "libcrypto.so", "libz.so", "libzstd.so",
                               "libcares.so", "libnghttp2.so", "libssh2.so" }) do
            local line = ldd_text:match("([^\r\n]*" .. lib .. "[^\r\n]*)")
            if line then
                assert(line_has_source_prefix(line),
                       "gcpkg: curl: host library discovered for " .. lib .. ": " .. line)
            end
        end

        -- sanity: direct C consumer linked to curl and all seven source ports.
        if on["sanity"] then
            assert(on["library"] and on["headers"] and curl_so,
                   "gcpkg: curl: sanity needs installed shared library and headers")
            local src = util.join(vdir, "curl_sanity.c")
            fs.write(src, [==[
#include <curl/curl.h>
#include <openssl/opensslv.h>
#include <zlib.h>
#include <brotli/decode.h>
#include <zstd.h>
#include <ares_version.h>
#include <nghttp2/nghttp2ver.h>
#include <libssh2.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != 0) return 2;
    const curl_version_info_data *d = curl_version_info(CURLVERSION_NOW);
    if (!d || !d->version || strcmp(d->version, "8.13.0")) return 3;
    unsigned int want = CURL_VERSION_SSL | CURL_VERSION_LIBZ | CURL_VERSION_ASYNCHDNS |
                        CURL_VERSION_HTTP2 | CURL_VERSION_BROTLI | CURL_VERSION_ZSTD |
                        CURL_VERSION_IPV6 | CURL_VERSION_UNIX_SOCKETS |
                        CURL_VERSION_TLSAUTH_SRP | CURL_VERSION_LARGEFILE;
    if ((d->features & want) != want) return 4;
    if (strcmp(OPENSSL_VERSION_STR, "3.4.1")) return 5;
    if (strcmp(ZLIB_VERSION, "1.3.1")) return 6;
    if (strcmp(ZSTD_VERSION_STRING, "1.5.7")) return 7;
    if (strcmp(ARES_VERSION_STR, "1.34.5")) return 8;
    if (strcmp(NGHTTP2_VERSION, "1.65.0")) return 9;
    if (strcmp(LIBSSH2_VERSION, "1.11.1")) return 10;
    if (BrotliDecoderVersion() == 0) return 11;
    const char *needles[] = { "3.4.1", "1.3.1", "1.1.0", "1.5.7", "1.34.5", "1.65.0", "1.11.1" };
    const char *fields[] = { d->ssl_version, d->libz_version, d->brotli_version,
                             d->zstd_version, d->ares, d->nghttp2_version, d->libssh_version };
    for (int i = 0; i < 7; i++) {
        if (!fields[i] || !strstr(fields[i], needles[i])) return 12 + i;
    }
    int scp = 0, sftp = 0;
    if (d->protocols) {
        for (const char * const *p = d->protocols; *p; p++) {
            if (!strcmp(*p, "scp")) scp = 1;
            if (!strcmp(*p, "sftp")) sftp = 1;
        }
    }
    if (!scp || !sftp) return 20;
    printf("gcpkg curl ok: %s | ssl=%s | zlib=%s | brotli=%s | zstd=%s | ares=%s | nghttp2=%s | libssh2=%s | scp,sftp=yes\n",
           d->version, d->ssl_version, d->libz_version, d->brotli_version,
           d->zstd_version, d->ares, d->nghttp2_version, d->libssh_version);
    curl_global_cleanup();
    return 0;
}
]==])
            local sanity_libdirs = split_colon(ld_path)
            local sanity_includes = split_colon(include_prefixes)
            local flags = { "-std=c11", "-D_GNU_SOURCE", "-pthread" }
            for _, dir in ipairs(sanity_libdirs) do
                if dir ~= "" then flags[#flags + 1] = "-Wl,-rpath," .. dir end
            end
            local bin = cc.executable {
                sources = { src },
                includes = sanity_includes,
                flags = flags,
                cwd = ctx.build_dir,
                outdir = util.join(vdir, "obj"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "curl", cxx = false,
                output = util.join(vdir, "curl_sanity"),
                libdirs = sanity_libdirs,
                libs = { "curl", "ssl", "crypto", "z", "brotlidec", "brotlicommon",
                         "zstd", "cares", "nghttp2", "ssh2" },
            }
            local out = util.join(vdir, "sanity.out")
            assert(ctx.exec({ "sh", "-c", bin .. " > " .. out .. " 2>&1" },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: curl: C sanity consumer failed")
            local result = assert(fs.read(out), "gcpkg: curl: missing C sanity output")
            for _, needle in ipairs({ "gcpkg curl ok: 8.13.0", "3.4.1", "1.3.1", "1.1.0",
                                      "1.5.7", "1.34.5", "1.65.0", "1.11.1", "scp,sftp=yes" }) do
                assert(result:find(needle, 1, true),
                       "gcpkg: curl: sanity output missing " .. needle)
            end
        end

        gcpkg.log.info("curl: post_install checks complete")
    end,
}
