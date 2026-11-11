-- libssh2 1.11.1 -- R20 new-standard re-audit of the curl L0 chain.
-- Declarative recipe.cmake keeps the framework absolute-no-probe injection
-- (all Check* modules, check_* and try_compile/try_run are shorted to shared
-- triplet facts). Positive features.yaml args are appended last and drive
-- every capability; `openssl` and `zlib` dynamically require the separately
-- installed source ports so the build graph is
--   zlib -> openssl -> libssh2
-- with dependencies={} in this file. cfg.defines pins FindOpenSSL/FindZLIB and
-- every upstream find_program() to the single install-task facts, disables
-- every optional host crypto backend, and prevents export(PACKAGE) from
-- writing the CMake user package registry.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

return recipe.cmake {
    name = "libssh2",
    version = "1.11.1",
    description = "SSH2 client library (OpenSSL backend + zlib compression + tests/examples)",
    license = "BSD-3-Clause",
    homepage = "https://www.libssh2.org",
    source = {
        url = "https://www.libssh2.org/download/libssh2-1.11.1.tar.gz",
        sha256 = "d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7",
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        -- ONE install-task platform/service-fact measurement. No compiler
        -- probe, no docker pull/build, no network, no source patch. The file
        -- is written before configure so a later failure still leaves facts.
        local on = ctx.features.enabled
        fs.mkdirs(ctx.build_dir)
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))
        local facts_file = util.join(vdir, "platform-facts.txt")
        local probe = util.join(vdir, "platform-facts.sh")
        fs.write(probe, [==[
set -u
out="$1"; root="$2"
fs_type="$(stat -f -c %T "$root" 2>/dev/null || echo UNKNOWN)"
wsl=NO
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then wsl=YES; fi
docker_exe="$(command -v docker || echo ABSENT)"
sshd_exe="$(command -v sshd || echo ABSENT)"
sh_exe="$(command -v sh || echo ABSENT)"
bash_exe="$(command -v bash || echo ABSENT)"
ssh_exe="$(command -v ssh || echo ABSENT)"
man_exe="$(command -v man || echo ABSENT)"
pkgconfig_exe="$(command -v pkg-config || echo ABSENT)"
gcov_exe="$(command -v gcov || echo ABSENT)"
mktemp_exe="$(command -v mktemp || echo ABSENT)"
listen_4711="$( (ss -ltn 2>/dev/null || true) | grep -c ':4711 ' || true)"
sshd_runtime_dir="$( (ls -d /run/sshd /var/run/sshd 2>/dev/null || true) | head -1)"
id_u="$(id -u)"
run_docker_tests=OFF
run_sshd_tests=OFF
if [ "$sshd_exe" != "ABSENT" ] && [ "$sh_exe" != "ABSENT" ] &&
   [ "$bash_exe" != "ABSENT" ] && [ "$ssh_exe" != "ABSENT" ] &&
   [ "$mktemp_exe" != "ABSENT" ] && [ "$id_u" = "0" ] &&
   [ -n "$sshd_runtime_dir" ]; then
  run_sshd_tests=ON
fi
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\nfs_type=%s\nwsl=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" "$fs_type" "$wsl" > "$out"
printf 'docker_exe=%s\nsshd_exe=%s\nsh_exe=%s\nbash_exe=%s\nssh_exe=%s\n' \
  "$docker_exe" "$sshd_exe" "$sh_exe" "$bash_exe" "$ssh_exe" >> "$out"
printf 'man_exe=%s\npkgconfig_exe=%s\ngcov_exe=%s\nmktemp_exe=%s\n' \
  "$man_exe" "$pkgconfig_exe" "$gcov_exe" "$mktemp_exe" >> "$out"
printf 'listen_4711=%s\nsshd_runtime_dir=%s\nid_u=%s\n' \
  "$listen_4711" "$sshd_runtime_dir" "$id_u" >> "$out"
printf 'run_docker_tests=%s reason=no_persistent_openssh_server_at_4711_and_docker_pull_forbidden\n' \
  "$run_docker_tests" >> "$out"
printf 'run_sshd_tests=%s reason=upstream_test_sshd_starts_its_own_sshd\n' \
  "$run_sshd_tests" >> "$out"
printf 'openssh_no_docker=1\nno_docker_download=YES\ncrypto_backend=OpenSSL\n' >> "$out"
printf 'cmake_export_no_package_registry=ON\ncmake_find_use_package_registry=OFF\n' >> "$out"
printf 'cmake_find_use_system_package_registry=OFF\n' >> "$out"
]==])
        ctx.exec({ "sh", probe, facts_file, ctx.build_dir },
                 { cwd = ctx.build_dir, log = ctx.log })
        local text = assert(fs.read(facts_file),
                            "gcpkg: libssh2: missing platform facts")
        text = text .. "ctx_os=" .. tostring(ctx.os) .. "\n" ..
               "ctx_arch=" .. tostring(ctx.arch) .. "\n" ..
               "jobs=" .. tostring(ctx.jobs) .. "\n" ..
               "home_override=" .. util.join(vdir, "home") .. "\n" ..
               "tmpdir_override=" .. util.join(vdir, "tmp") .. "\n"
        if on["openssl"] then
            local ssl = ctx.dep("openssl")
            assert(ssl and ssl.prefix,
                   "gcpkg: libssh2: openssl feature requires installed openssl port")
            local ovh = assert(fs.read(util.join(ssl.prefix, "include", "openssl", "opensslv.h")),
                               "gcpkg: libssh2: cannot read opensslv.h")
            local ov = ovh:match('OPENSSL_VERSION_STR "([^"]+)"')
            assert(ov == "3.4.1",
                   "gcpkg: libssh2: unexpected OpenSSL source-port version")
            text = text .. "openssl_prefix=" .. ssl.prefix .. "\n" ..
                   "openssl_version=" .. ov .. "\n"
        else
            text = text .. "openssl=DISABLED_BY_FEATURE\n"
        end
        if on["zlib"] then
            local z = ctx.dep("zlib")
            assert(z and z.prefix,
                   "gcpkg: libssh2: zlib feature requires installed zlib port")
            local zh = assert(fs.read(util.join(z.prefix, "include", "zlib.h")),
                              "gcpkg: libssh2: cannot read zlib.h")
            local zv = zh:match('#define ZLIB_VERSION "([^"]+)"')
            assert(zv == "1.3.1",
                   "gcpkg: libssh2: unexpected zlib source-port version")
            text = text .. "zlib_prefix=" .. z.prefix .. "\n" ..
                   "zlib_version=" .. zv .. "\n"
        else
            text = text .. "zlib=DISABLED_BY_FEATURE\n"
        end
        fs.write(facts_file, text)
        gcpkg.log.info("libssh2: install-task platform/service facts recorded once")
    end,
    cmake = {
        defines = function(ctx)
            local on = ctx.features.enabled
            local facts = assert(fs.read(util.join(ctx.build_dir, "verify", "platform-facts.txt")),
                                 "gcpkg: libssh2: missing platform facts for defines")
            local function fact(name)
                return facts:match(name .. "=([^%s\n]+)") or ""
            end
            local run_docker = fact("run_docker_tests") == "OFF" and "OFF" or "ON"
            local run_sshd = fact("run_sshd_tests") == "ON" and "ON" or "OFF"
            local sh_exe = fact("sh_exe")
            local sshd_exe = fact("sshd_exe")
            local pkgconfig_exe = fact("pkgconfig_exe")
            assert(sh_exe ~= "" and sh_exe ~= "ABSENT",
                   "gcpkg: libssh2: sh fact missing; cannot pin SH_EXECUTABLE")
            assert(pkgconfig_exe ~= "" and pkgconfig_exe ~= "ABSENT",
                   "gcpkg: libssh2: pkg-config fact missing; cannot pin FindPkgConfig")
            if run_sshd == "ON" then
                assert(sshd_exe ~= "" and sshd_exe ~= "ABSENT",
                       "gcpkg: libssh2: sshd fact missing for RUN_SSHD_TESTS=ON")
            end
            local d = {
                CMAKE_BUILD_TYPE = "Release",
                CRYPTO_BACKEND = "OpenSSL",
                ENABLE_WERROR = "OFF",
                LINT = "OFF",
                RUN_DOCKER_TESTS = run_docker,
                RUN_SSHD_TESTS = run_sshd,
                -- Upstream find_program() calls are not compiler probes, but
                -- the R20 standard still forbids build-time discovery: pin
                -- them from the single install-task platform-facts measurement.
                SH_EXECUTABLE = sh_exe,
                SSHD_EXECUTABLE = sshd_exe,
                PKG_CONFIG_EXECUTABLE = pkgconfig_exe,
                GCOV_PATH = "",
                NEED_LIB_SOCKET = "0",
                NEED_LIB_NSL = "0",
                -- export(PACKAGE libssh2) would otherwise write to the CMake
                -- user package registry. Keep all registry access off.
                CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
                CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
                CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
                -- Deterministic install layout for all post_install checks.
                CMAKE_INSTALL_LIBDIR = "lib",
                CMAKE_INSTALL_INCLUDEDIR = "include",
                CMAKE_INSTALL_DOCDIR = "share/doc/libssh2",
                CMAKE_INSTALL_MANDIR = "share/man",
                -- Optional host crypto backends must never be discovered.
                CMAKE_DISABLE_FIND_PACKAGE_WolfSSL = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libgcrypt = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_MbedTLS = "ON",
                -- Explicit Linux/glibc facts for libssh2_config.h. The shared
                -- no-probe table supplies common headers/functions; these are
                -- the remaining upstream names, with Windows/macOS entries
                -- deliberately unavailable. No check_* command compiles.
                HAVE_INTTYPES_H = "1", HAVE_UNISTD_H = "1",
                HAVE_SYS_SELECT_H = "1", HAVE_SYS_UIO_H = "1",
                HAVE_SYS_SOCKET_H = "1", HAVE_SYS_IOCTL_H = "1",
                HAVE_SYS_TIME_H = "1", HAVE_SYS_UN_H = "1",
                HAVE_ARPA_INET_H = "1", HAVE_NETINET_IN_H = "1",
                HAVE_GETTIMEOFDAY = "1", HAVE_STRTOLL = "1",
                HAVE_SNPRINTF = "1", HAVE_EXPLICIT_BZERO = "1",
                HAVE_POLL = "1", HAVE_SELECT = "1",
                HAVE_SOCKET = "1", HAVE_INET_ADDR = "1",
                HAVE_O_NONBLOCK = "1",
                HAVE_FIONBIO = "", HAVE_IOCTLSOCKET_CASE = "",
                HAVE_SO_NONBLOCK = "", HAVE_STRTOI64 = "",
                HAVE_EXPLICIT_MEMSET = "", HAVE_MEMSET_S = "",
            }
            assert(on["openssl"],
                   "gcpkg: libssh2: openssl feature is required for CRYPTO_BACKEND=OpenSSL")
            local ssl = ctx.dep("openssl")
            assert(ssl and ssl.prefix,
                   "gcpkg: libssh2: openssl feature requires installed openssl port")
            local ssl_lib = util.join(ssl.prefix, "lib")
            if not fs.isdir(ssl_lib) then
                ssl_lib = util.join(ssl.prefix, "lib64")
            end
            local ssl_inc = util.join(ssl.prefix, "include")
            assert(fs.isfile(util.join(ssl_inc, "openssl", "ssl.h")),
                   "gcpkg: libssh2: openssl/ssl.h missing from dependency prefix")
            local crypto_so = util.join(ssl_lib, "libcrypto.so")
            local ssl_so = util.join(ssl_lib, "libssl.so")
            assert(fs.isfile(crypto_so) and fs.isfile(ssl_so),
                   "gcpkg: libssh2: shared OpenSSL libraries missing from dependency prefix")
            d.OPENSSL_ROOT_DIR = ssl.prefix
            d.OPENSSL_INCLUDE_DIR = ssl_inc
            d.OPENSSL_CRYPTO_LIBRARY = crypto_so
            d.OPENSSL_SSL_LIBRARY = ssl_so
            d.OPENSSL_USE_STATIC_LIBS = "OFF"
            local dep_prefixes = { ssl.prefix }
            if on["zlib"] then
                local z = ctx.dep("zlib")
                assert(z and z.prefix,
                       "gcpkg: libssh2: zlib feature requires installed zlib port")
                local z_lib = util.join(z.prefix, "lib")
                if not fs.isdir(z_lib) then
                    z_lib = util.join(z.prefix, "lib64")
                end
                local z_inc = util.join(z.prefix, "include")
                assert(fs.isfile(util.join(z_inc, "zlib.h")),
                       "gcpkg: libssh2: zlib.h missing from dependency prefix")
                local z_so = util.join(z_lib, "libz.so")
                local z_a = util.join(z_lib, "libz.a")
                assert(fs.isfile(z_so) or fs.isfile(z_a),
                       "gcpkg: libssh2: libz missing from dependency prefix")
                d.ZLIB_ROOT = z.prefix
                d.ZLIB_INCLUDE_DIR = z_inc
                d.ZLIB_LIBRARY = fs.isfile(z_so) and z_so or z_a
                d.CMAKE_DISABLE_FIND_PACKAGE_ZLIB = "OFF"
                dep_prefixes[#dep_prefixes + 1] = z.prefix
            else
                d.CMAKE_DISABLE_FIND_PACKAGE_ZLIB = "ON"
                -- Keep the upstream CONFIG template's if(@ZLIB_FOUND@) valid.
                d.ZLIB_FOUND = "0"
            end
            -- Pin search to the dynamically required source-port prefixes;
            -- recipe.lua's automatic CMAKE_PREFIX_PATH stays a fallback.
            d.CMAKE_PREFIX_PATH = table.concat(dep_prefixes, ";")
            return d
        end,
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "ssh2" },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local prefix = ctx.prefix
        local libdir = util.join(prefix, "lib")
        if not fs.isfile(util.join(libdir, "libssh2.a")) and
           not fs.isfile(util.join(libdir, "libssh2.so")) and
           fs.isdir(util.join(prefix, "lib64")) then
            libdir = util.join(prefix, "lib64")
        end
        local incdir = util.join(prefix, "include")
        local docdir = util.join(prefix, "share", "doc", "libssh2")
        local cmakedir = util.join(libdir, "cmake", "libssh2")
        local pkgdir = util.join(libdir, "pkgconfig")
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))

        local ssl = ctx.dep("openssl")
        local z = ctx.dep("zlib")
        assert(ssl and ssl.prefix and on["openssl"],
               "gcpkg: libssh2: post_install requires openssl feature")
        local ollib = util.join(ssl.prefix, "lib")
        if not fs.isdir(ollib) then ollib = util.join(ssl.prefix, "lib64") end
        local olinc = util.join(ssl.prefix, "include")
        local zliblib = util.join(z and z.prefix or "", "lib")
        local zinc = util.join(z and z.prefix or "", "include")
        if z and not fs.isdir(zliblib) then
            zliblib = util.join(z.prefix, "lib64")
        end
        local ld = libdir .. ":" .. ollib .. ":" .. zliblib .. ":" ..
                   ((ctx.env or {}).LD_LIBRARY_PATH or "")
        local tenv = {
            HOME = util.join(vdir, "home"),
            TMPDIR = util.join(vdir, "tmp"),
            LD_LIBRARY_PATH = ld,
            OPENSSH_NO_DOCKER = "1",
            CTEST_OUTPUT_ON_FAILURE = "1",
        }
        local pc_path = pkgdir .. ":" .. util.join(ollib, "pkgconfig") .. ":" ..
                        util.join(z and z.prefix or "", "share", "pkgconfig") .. ":" ..
                        util.join(z and z.prefix or "", "lib", "pkgconfig") .. ":" ..
                        ((ctx.env or {}).PKG_CONFIG_PATH or "")
        local platform_facts = assert(fs.read(util.join(vdir, "platform-facts.txt")),
                                      "gcpkg: libssh2: missing platform facts")
        local function fact(name)
            return platform_facts:match(name .. "=([^%s\n]+)") or ""
        end
        local pkgconfig_exe = fact("pkgconfig_exe")
        assert(pkgconfig_exe ~= "" and pkgconfig_exe ~= "ABSENT",
               "gcpkg: libssh2: pkg-config fact missing")
        local pcenv = util.merge(tenv, {
            PKG_CONFIG_PATH = pc_path,
            PKG_CONFIG_EXECUTABLE = pkgconfig_exe,
        })

        -- library / headers / static / shared.
        if on["library"] then
            if on["static"] then
                assert(fs.isfile(util.join(libdir, "libssh2.a")),
                       "gcpkg: libssh2: static libssh2.a missing")
            end
            if on["shared"] then
                assert(fs.isfile(util.join(libdir, "libssh2.so")) or
                       fs.isfile(util.join(libdir, "libssh2.so.1")),
                       "gcpkg: libssh2: shared libssh2.so missing")
            end
        end
        if on["headers"] then
            for _, name in ipairs({ "libssh2.h", "libssh2_publickey.h", "libssh2_sftp.h" }) do
                assert(fs.isfile(util.join(incdir, name)),
                       "gcpkg: libssh2: header missing: " .. name)
            end
            local hdr = assert(fs.read(util.join(incdir, "libssh2.h")),
                               "gcpkg: libssh2: cannot read libssh2.h")
            assert(hdr:find('"1.11.1"', 1, true),
                   "gcpkg: libssh2: installed header is not 1.11.1")
        end
        if on["docs"] or on["license"] then
            for _, name in ipairs({ "COPYING", "NEWS", "README", "RELEASE-NOTES",
                                    "AUTHORS", "BINDINGS.md", "HACKING.md" }) do
                assert(fs.isfile(util.join(docdir, name)),
                       "gcpkg: libssh2: upstream document missing: " .. name)
            end
            local man_count = util.join(vdir, "man3.count")
            assert(ctx.exec({ "sh", "-c",
                       "find " .. util.join(prefix, "share", "man", "man3") ..
                       " -type f 2>/dev/null | wc -l > " .. man_count },
                     { cwd = vdir, log = ctx.log }) == 0,
                   "gcpkg: libssh2: man3 count failed")
            local mc_text = (assert(fs.read(man_count),
                                "gcpkg: libssh2: missing man3 count")):gsub("%s+", "")
            local mc = tonumber(mc_text)
            assert(mc and mc == 186,
                   "gcpkg: libssh2: expected 186 upstream man3 pages, got " .. tostring(mc))
        end
        if on["examples"] then
            for _, name in ipairs({ "ssh2", "sftp", "scp", "ssh2_exec", "sftp_write" }) do
                assert(fs.isfile(util.join(ctx.build_dir, "example", name)),
                       "gcpkg: libssh2: upstream example not built: " .. name)
            end
            local ex_count = util.join(vdir, "example.count")
            assert(ctx.exec({ "sh", "-c",
                       "find " .. util.join(ctx.build_dir, "example") ..
                       " -maxdepth 1 -type f -perm -u+x 2>/dev/null | wc -l > " .. ex_count },
                     { cwd = vdir, log = ctx.log }) == 0,
                   "gcpkg: libssh2: example count failed")
            local ec_text = (assert(fs.read(ex_count),
                                "gcpkg: libssh2: missing example count")):gsub("%s+", "")
            local ec = tonumber(ec_text)
            assert(ec and ec >= 24,
                   "gcpkg: libssh2: expected at least 24 upstream examples, got " .. tostring(ec))
        end

        if on["pkgconfig"] then
            assert(on["openssl"] and on["zlib"],
                   "gcpkg: libssh2: pkgconfig needs openssl and zlib features")
            local pc = util.join(pkgdir, "libssh2.pc")
            assert(fs.isfile(pc), "gcpkg: libssh2: libssh2.pc missing")
            local pct = assert(fs.read(pc), "gcpkg: libssh2: cannot read libssh2.pc")
            assert(pct:find("Version: 1.11.1", 1, true),
                   "gcpkg: libssh2: .pc version is not 1.11.1")
            assert(pct:find("-lssh2", 1, true),
                   "gcpkg: libssh2: .pc does not advertise -lssh2")
            assert(pct:find("libcrypto", 1, true) and pct:find("zlib", 1, true),
                   "gcpkg: libssh2: .pc does not advertise source-port private requirements")
            -- Independent CMake consumer through CMake's own FindPkgConfig.
            local psrc = util.join(vdir, "pkgconfig-consumer", "src")
            local pbin = util.join(vdir, "pkgconfig-consumer", "build")
            fs.mkdirs(psrc); fs.mkdirs(pbin)
            fs.write(util.join(psrc, "CMakeLists.txt"), table.concat({
                "cmake_minimum_required(VERSION 3.16)",
                "project(libssh2_pc_consumer C)",
                "find_package(PkgConfig REQUIRED)",
                "pkg_check_modules(LIBSSH2 REQUIRED IMPORTED_TARGET libssh2>=1.11.1)",
                "add_executable(consumer main.c)",
                "target_link_libraries(consumer PRIVATE PkgConfig::LIBSSH2)",
                "",
            }, "\n"))
            fs.write(util.join(psrc, "main.c"), table.concat({
                "#include <libssh2.h>",
                "#include <stdio.h>",
                "#include <string.h>",
                "int main(void) {",
                "  if (libssh2_init(0) != 0) return 2;",
                "  const char *v = libssh2_version(LIBSSH2_VERSION_NUM);",
                "  if (!v || strcmp(v, \"1.11.1\")) return 3;",
                "  printf(\"gcpkg FindPkgConfig consumer ok: %s\\n\", v);",
                "  libssh2_exit();",
                "  return 0;",
                "}",
                "",
            }, "\n"))
            assert(ctx.exec({ "cmake", "-S", psrc, "-B", pbin,
                              "-DPKG_CONFIG_EXECUTABLE=" .. pkgconfig_exe,
                              "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
                              "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
                              "-DCMAKE_BUILD_RPATH=" .. libdir .. ";" .. ollib .. ";" .. zliblib },
                            { cwd = vdir, env = pcenv }) == 0,
                   "gcpkg: libssh2: FindPkgConfig consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", pbin, "-j", tostring(ctx.jobs) },
                            { cwd = vdir, env = pcenv }) == 0,
                   "gcpkg: libssh2: FindPkgConfig consumer build failed")
            local pout = util.join(vdir, "pkgconfig-consumer.out")
            assert(ctx.exec({ "sh", "-c", util.join(pbin, "consumer") .. " > " .. pout .. " 2>&1" },
                            { cwd = vdir, env = pcenv }) == 0,
                   "gcpkg: libssh2: FindPkgConfig consumer run failed")
            assert((assert(fs.read(pout),
                    "gcpkg: libssh2: missing FindPkgConfig consumer output")):find("FindPkgConfig consumer ok: 1.11.1", 1, true),
                   "gcpkg: libssh2: FindPkgConfig consumer did not use installed 1.11.1")
        end

        if on["cmake-package"] then
            assert(on["openssl"],
                   "gcpkg: libssh2: CONFIG consumer needs openssl feature")
            local config = util.join(cmakedir, "libssh2-config.cmake")
            local version = util.join(cmakedir, "libssh2-config-version.cmake")
            local targets = util.join(cmakedir, "libssh2-targets.cmake")
            local release = util.join(cmakedir, "libssh2-targets-release.cmake")
            assert(fs.isfile(config) and fs.isfile(version) and
                   fs.isfile(targets) and fs.isfile(release),
                   "gcpkg: libssh2: upstream CONFIG package files missing")
            local ct = assert(fs.read(config),
                              "gcpkg: libssh2: cannot read libssh2-config.cmake")
            assert(ct:find("find_dependency(OpenSSL)", 1, true) and
                   ct:find("include(\"${CMAKE_CURRENT_LIST_DIR}/libssh2-targets.cmake\")", 1, true),
                   "gcpkg: libssh2: upstream CONFIG does not load OpenSSL dependency and targets")
            local tt = assert(fs.read(targets),
                              "gcpkg: libssh2: cannot read exported targets")
            assert(tt:find("libssh2::libssh2_shared", 1, true) and
                   tt:find("libssh2::libssh2_static", 1, true),
                   "gcpkg: libssh2: both upstream exported targets must exist")
            -- Independent external CMake consumer using the UPSTREAM CONFIG.
            -- find_dependency(OpenSSL/ZLIB) is pinned to the source ports.
            local csrc = util.join(vdir, "config-consumer", "src")
            local cbin = util.join(vdir, "config-consumer", "build")
            fs.mkdirs(csrc); fs.mkdirs(cbin)
            fs.write(util.join(csrc, "CMakeLists.txt"), table.concat({
                "cmake_minimum_required(VERSION 3.16)",
                "project(libssh2_config_consumer C)",
                "find_package(libssh2 1.11.1 CONFIG REQUIRED)",
                "add_executable(consumer main.c)",
                "target_link_libraries(consumer PRIVATE libssh2::libssh2)",
                "",
            }, "\n"))
            fs.write(util.join(csrc, "main.c"), table.concat({
                "#include <libssh2.h>",
                "#include <stdio.h>",
                "#include <string.h>",
                "int main(void) {",
                "  if (libssh2_init(0) != 0) return 2;",
                "  const char *v = libssh2_version(LIBSSH2_VERSION_NUM);",
                "  if (!v || strcmp(v, \"1.11.1\")) return 3;",
                "  printf(\"gcpkg libssh2 CONFIG consumer ok: %s\\n\", v);",
                "  libssh2_exit();",
                "  return 0;",
                "}",
                "",
            }, "\n"))
            local cmake_prefix = prefix .. ";" .. ssl.prefix .. ";" .. (z and z.prefix or "")
            local cargs = {
                "cmake", "-S", csrc, "-B", cbin,
                "-Dlibssh2_DIR=" .. cmakedir,
                "-DCMAKE_PREFIX_PATH=" .. cmake_prefix,
                "-DOPENSSL_ROOT_DIR=" .. ssl.prefix,
                "-DOPENSSL_INCLUDE_DIR=" .. olinc,
                "-DOPENSSL_CRYPTO_LIBRARY=" .. util.join(ollib, "libcrypto.so"),
                "-DOPENSSL_SSL_LIBRARY=" .. util.join(ollib, "libssl.so"),
                "-DOPENSSL_USE_STATIC_LIBS=OFF",
                "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
                "-DPKG_CONFIG_EXECUTABLE=" .. pkgconfig_exe,
                "-DCMAKE_BUILD_RPATH=" .. libdir .. ";" .. ollib .. ";" .. zliblib,
            }
            if on["zlib"] then
                cargs[#cargs + 1] = "-DZLIB_ROOT=" .. z.prefix
                cargs[#cargs + 1] = "-DZLIB_INCLUDE_DIR=" .. zinc
                cargs[#cargs + 1] = "-DZLIB_LIBRARY=" .. util.join(zliblib, "libz.so")
            end
            assert(ctx.exec(cargs, { cwd = vdir, env = pcenv }) == 0,
                   "gcpkg: libssh2: upstream CONFIG consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", cbin, "-j", tostring(ctx.jobs) },
                            { cwd = vdir, env = pcenv }) == 0,
                   "gcpkg: libssh2: upstream CONFIG consumer build failed")
            local cout = util.join(vdir, "config-consumer.out")
            assert(ctx.exec({ "sh", "-c", util.join(cbin, "consumer") .. " > " .. cout .. " 2>&1" },
                            { cwd = vdir, env = pcenv }) == 0,
                   "gcpkg: libssh2: upstream CONFIG consumer run failed")
            assert((assert(fs.read(cout),
                    "gcpkg: libssh2: missing CONFIG consumer output")):find("CONFIG consumer ok: 1.11.1", 1, true),
                   "gcpkg: libssh2: CONFIG consumer did not use installed 1.11.1")
        end

        -- tests: run the real upstream ctest suite. A full capability run is
        -- the authoritative host-service measurement; if the ONLY failure is
        -- test_sshd, re-run with the official RUN_SSHD_TESTS switch. No
        -- ctest -E, no source/assertion edit, and BUILD_TESTING stays ON.
        if on["tests"] then
            assert(on["static"],
                   "gcpkg: libssh2: tests feature requires static library")
            assert(platform_facts:find("run_docker_tests=OFF", 1, true),
                   "gcpkg: libssh2: docker service tests must be OFF on this triplet")
            assert(platform_facts:find("openssh_no_docker=1", 1, true),
                   "gcpkg: libssh2: OPENSSH_NO_DOCKER fact missing")
            local cache = assert(fs.read(util.join(ctx.build_dir, "CMakeCache.txt")),
                                 "gcpkg: libssh2: missing CMakeCache.txt")
            local sshd_initial = cache:match("RUN_SSHD_TESTS:BOOL=(%a+)") or "UNKNOWN"
            local cap_log = util.join(vdir, "ctest-capability.log")
            local cap_rc = util.join(vdir, "ctest-capability.rc")
            local final_log = util.join(vdir, "ctest.log")
            local final_rc_file = util.join(vdir, "ctest.rc")
            local facts = util.join(vdir, "capability-facts.txt")
            local write_facts = function(rc, failed, names, frc, found, summary)
                fs.write(facts, table.concat({
                    "policy: full upstream ctest capability run; official RUN_SSHD_TESTS switch only for measured test_sshd host-service failure; RUN_DOCKER_TESTS=OFF from install-task facts; no ctest -E, no source/assertion edits",
                    "run_docker_tests=OFF",
                    "run_sshd_tests_initial=" .. sshd_initial,
                    "openssh_no_docker=1",
                    "capability_rc=" .. rc,
                    "capability_failed=" .. tostring(failed),
                    "capability_failed_names=" .. names,
                    "final_rc=" .. frc,
                    "excluded=" .. tostring(failed),
                    "excluded_names=" .. names,
                    "tests_found=" .. tostring(found),
                    "summary=" .. summary,
                    "",
                }, "\n"))
            end
            write_facts("PENDING", "PENDING", "", "PENDING", "0", "NO_SUMMARY")
            assert(ctx.exec({ "sh", "-c",
                       "ctest --output-on-failure --timeout 180 > " .. cap_log ..
                       " 2>&1; rc=$?; echo $rc > " .. cap_rc .. "; exit 0" },
                     { cwd = ctx.build_dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: libssh2: capability ctest shell failed")
            local capability_rc = (assert(fs.read(cap_rc),
                                "gcpkg: libssh2: missing capability ctest rc")):gsub("%s+", "")
            local capability = assert(fs.read(cap_log),
                                "gcpkg: libssh2: missing capability ctest output")
            assert(not capability:find("docker pull", 1, true) and
                   not capability:find("docker build", 1, true),
                   "gcpkg: libssh2: docker pull/build during tests is forbidden")
            -- Parse ctest's own "The following tests FAILED:" block. Never
            -- treat a passing test name as a failure just because it appears.
            local failures, seen, in_failed = {}, {}, false
            for _, line in ipairs(util.lines(capability)) do
                if line:find("The following tests FAILED", 1, true) then
                    in_failed = true
                elseif in_failed and line:find("Errors while running CTest", 1, true) then
                    in_failed = false
                elseif in_failed then
                    local name = line:match("^%s*%d+ %- ([%w_%.%-]+) %(([^)]+)%)")
                    if name and not seen[name] then
                        seen[name] = true
                        failures[#failures + 1] = name
                    end
                end
            end
            assert(capability_rc == "0" or
                   (#failures == 1 and failures[1] == "test_sshd"),
                   "gcpkg: libssh2: unexpected capability rc/failures: " ..
                   capability_rc .. " / " .. table.concat(failures, ","))
            local final_result, final_rc
            if #failures == 0 then
                final_result = capability
                final_rc = capability_rc
                fs.write(final_log, final_result)
                fs.write(final_rc_file, final_rc)
            else
                assert(ctx.exec({ "cmake", "-S", ctx.src, "-B", ctx.build_dir,
                                  "-DRUN_SSHD_TESTS=OFF" },
                                { cwd = vdir, env = tenv }) == 0,
                       "gcpkg: libssh2: official RUN_SSHD_TESTS=OFF reconfigure failed")
                assert(ctx.exec({ "cmake", "--build", ctx.build_dir,
                                  "--parallel", tostring(ctx.jobs) },
                                { cwd = vdir, env = tenv }) == 0,
                       "gcpkg: libssh2: rebuild after RUN_SSHD_TESTS=OFF failed")
                assert(ctx.exec({ "sh", "-c",
                           "ctest --output-on-failure --timeout 180 > " .. final_log ..
                           " 2>&1; rc=$?; echo $rc > " .. final_rc_file .. "; exit 0" },
                         { cwd = ctx.build_dir, env = tenv, log = ctx.log }) == 0,
                       "gcpkg: libssh2: final ctest shell failed")
                final_result = assert(fs.read(final_log),
                                "gcpkg: libssh2: missing final ctest output")
                final_rc = (assert(fs.read(final_rc_file),
                                "gcpkg: libssh2: missing final ctest rc")):gsub("%s+", "")
            end
            local found = tonumber(final_result:match("out of (%d+)") or "0") or 0
            local summary = final_result:match("(%d+%% tests passed, %d+ tests failed out of %d+)") or
                            final_result:match("(%d+%% tests passed)") or "NO_SUMMARY"
            -- Facts are written BEFORE strict assertions (openssl r3 lesson).
            write_facts(capability_rc, #failures, table.concat(failures, ","),
                        final_rc, found, summary)
            assert(final_rc == "0",
                   "gcpkg: libssh2: final ctest rc is not zero")
            assert(not final_result:find("No tests were found", 1, true),
                   "gcpkg: libssh2: ctest found no registered tests")
            assert(final_result:find("100% tests passed", 1, true),
                   "gcpkg: libssh2: ctest did not pass all registered tests")
            assert(not final_result:find("The following tests FAILED", 1, true),
                   "gcpkg: libssh2: ctest reported failed tests")
            assert(found >= 2,
                   "gcpkg: libssh2: ctest registered fewer than 2 upstream tests")
            assert(final_result:find("mansyntax", 1, true),
                   "gcpkg: libssh2: upstream mansyntax test was not run")
            assert(final_result:find("test_simple", 1, true),
                   "gcpkg: libssh2: upstream test_simple was not run")
            if #failures == 0 then
                assert(final_result:find("test_sshd", 1, true),
                       "gcpkg: libssh2: upstream sshd test was not run")
            else
                assert(not final_result:find("test_sshd", 1, true),
                       "gcpkg: libssh2: test_sshd still registered after official switch")
            end
        end

        -- sanity: C consumer linked to installed libssh2, source-port OpenSSL
        -- and source-port zlib with explicit RUNPATHs for all three prefixes.
        if on["sanity"] then
            assert(on["library"] and on["headers"] and on["openssl"] and on["zlib"],
                   "gcpkg: libssh2: sanity needs library, headers, openssl and zlib")
            local src = util.join(vdir, "libssh2_sanity.c")
            fs.write(src, [==[
#include <libssh2.h>
#include <openssl/crypto.h>
#include <openssl/opensslv.h>
#include <zlib.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    if (libssh2_init(0) != 0) return 2;
    const char *v = libssh2_version(LIBSSH2_VERSION_NUM);
    const char *o = OpenSSL_version(OPENSSL_VERSION);
    const char *z = zlibVersion();
    if (!v || strcmp(v, "1.11.1")) return 3;
    if (!o || !strstr(o, "3.4.1") || strcmp(OPENSSL_VERSION_STR, "3.4.1")) return 4;
    if (!z || strcmp(z, "1.3.1")) return 5;
    printf("gcpkg libssh2 ok: libssh2 %s / openssl %s / zlib %s\n", v, o, z);
    libssh2_exit();
    return 0;
}
]==])
            local bin = cc.executable {
                sources = { src },
                includes = { incdir, olinc, zinc },
                flags = { "-std=c11", "-Wl,-rpath," .. libdir,
                          "-Wl,-rpath," .. ollib, "-Wl,-rpath," .. zliblib },
                cwd = ctx.build_dir,
                outdir = util.join(vdir, "obj"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "libssh2", cxx = false,
                output = util.join(vdir, "libssh2_sanity"),
                libdirs = { libdir, ollib, zliblib },
                libs = { "ssh2", "crypto", "z" },
            }
            local out = util.join(vdir, "sanity.out")
            assert(ctx.exec({ "sh", "-c", bin .. " > " .. out .. " 2>&1" },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: libssh2: C sanity consumer failed")
            local result = assert(fs.read(out),
                                  "gcpkg: libssh2: missing C sanity output")
            assert(result:find("libssh2 1.11.1", 1, true) and
                   result:find("3.4.1", 1, true) and
                   result:find("zlib 1.3.1", 1, true),
                   "gcpkg: libssh2: sanity did not link all three source-port libraries")
        end

        gcpkg.log.info("libssh2: post_install checks complete")
    end,
}
