-- nghttp2 1.65.0 -- R20 new-standard re-audit of the curl L0 chain.
-- Declarative recipe.cmake keeps the framework absolute-no-probe injection
-- (all Check* modules, check_type_size, check_struct_has_member, try_compile
-- and try_run are shorted to shared triplet facts). Positive features.yaml
-- args are appended last (dedup_defines) and drive every library capability;
-- the `zlib` feature's dynamic `requires: ["zlib"]` adds the source port to
-- the build graph and cfg.defines points FindZLIB at that exact prefix.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

return recipe.cmake {
    name = "nghttp2",
    version = "1.65.0",
    description = "HTTP/2 C library (static + shared + upstream unit tests)",
    license = "MIT",
    homepage = "https://nghttp2.org",
    source = {
        url = "https://github.com/nghttp2/nghttp2/releases/download/v1.65.0/nghttp2-1.65.0.tar.gz",
        sha256 = "8ca4f2a77ba7aac20aca3e3517a2c96cfcf7c6b064ab7d4a0809e7e4e9eb9914",
        strip = 1,
    },
    -- Static deps: none. `zlib` gets its dependency through features.yaml.
    dependencies = {},
    cmake = {
        -- Platform facts are measured once when the install task starts (the
        -- framework's shared no-probe table plus the explicit Linux/glibc
        -- results below). They are not compiler probes: every check_* call is
        -- shorted by gcpkg_probe_result against GCPKG_TRUE_RESULTS. Missing
        -- upstream source ports are represented by real OFF switches and by
        -- CMake's official CMAKE_DISABLE_FIND_PACKAGE_<Pkg> for every OPTIONAL
        -- host package that the top-level CMakeLists would otherwise search.
        defines = function(ctx)
            local d = {
                CMAKE_BUILD_TYPE = "Release",
                ENABLE_LIB_ONLY = "OFF",
                ENABLE_APP = "OFF",
                ENABLE_EXAMPLES = "OFF",
                ENABLE_HPACK_TOOLS = "OFF",
                ENABLE_HTTP3 = "OFF",
                ENABLE_WERROR = "OFF",
                ENABLE_DEBUG = "OFF",
                ENABLE_STATIC_CRT = "OFF",
                WITH_LIBXML2 = "OFF",
                WITH_JEMALLOC = "OFF",
                WITH_MRUBY = "OFF",
                WITH_NEVERBLEED = "OFF",
                WITH_LIBBPF = "OFF",
                WITH_WOLFSSL = "OFF",
                -- Disable all optional find_package calls for host libraries.
                -- Threads and ZLIB are deliberately NOT disabled.
                CMAKE_DISABLE_FIND_PACKAGE_Python3 = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libev = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libcares = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libbrotlienc = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libbrotlidec = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_OpenSSL = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_WolfSSL = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libngtcp2 = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libngtcp2_crypto_quictls = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libngtcp2_crypto_wolfssl = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libnghttp3 = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libbpf = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Systemd = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Jansson = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Libevent = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_LibXml2 = "ON",
                CMAKE_DISABLE_FIND_PACKAGE_Jemalloc = "ON",
                -- Explicit Linux/glibc results for upstream config.h checks
                -- not covered by the shared triplet fact table. Windows,
                -- BSD and macOS entries are deliberately left unavailable.
                HAVE_ARPA_INET_H = "1", HAVE_FCNTL_H = "1",
                HAVE_INTTYPES_H = "1", HAVE_LIMITS_H = "1",
                HAVE_NETDB_H = "1", HAVE_NETINET_IN_H = "1",
                HAVE_NETINET_IP_H = "1", HAVE_PWD_H = "1",
                HAVE_SYS_SOCKET_H = "1", HAVE_SYS_TIME_H = "1",
                HAVE_SYSLOG_H = "1", HAVE_UNISTD_H = "1",
                HAVE_STRUCT_TM_TM_GMTOFF = "1",
                HAVE_DECL_CLOCK_MONOTONIC = "1",
                HAVE_DECL_INITGROUPS = "1",
                HAVE__EXIT = "1", HAVE_ACCEPT4 = "1",
                HAVE_CLOCK_GETTIME = "1", HAVE_MKOSTEMP = "1",
                HAVE_PIPE2 = "1",
                HAVE_STD_FUTURE = "1", HAVE_STD_MAP_EMPLACE = "1",
                SIZEOF_SSIZE_T = "8",
            }
            if ctx.features.enabled["zlib"] then
                local zlib = ctx.dep("zlib")
                assert(zlib and zlib.prefix,
                       "gcpkg: nghttp2: zlib feature requires installed zlib port")
                local zincdir = util.join(zlib.prefix, "include")
                local zlibdir = util.join(zlib.prefix, "lib")
                if not fs.isdir(zlibdir) then
                    zlibdir = util.join(zlib.prefix, "lib64")
                end
                assert(fs.isfile(util.join(zincdir, "zlib.h")),
                       "gcpkg: nghttp2: zlib.h missing from dependency prefix")
                local zso = util.join(zlibdir, "libz.so")
                local za = util.join(zlibdir, "libz.a")
                assert(fs.isfile(zso) or fs.isfile(za),
                       "gcpkg: nghttp2: libz missing from dependency prefix")
                d.ZLIB_ROOT = zlib.prefix
                d.ZLIB_INCLUDE_DIR = zincdir
                d.ZLIB_LIBRARY = fs.isfile(zso) and zso or za
                d.CMAKE_DISABLE_FIND_PACKAGE_ZLIB = "OFF"
            else
                d.CMAKE_DISABLE_FIND_PACKAGE_ZLIB = "ON"
            end
            return d
        end,
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "nghttp2" },
    },
    pre_build = function(ctx)
        -- ONE install-task platform-fact measurement. No compiler probe, no
        -- network, no source patch. The file is written before configure so
        -- a later failure still leaves the measured facts behind.
        fs.mkdirs(ctx.build_dir)
        local facts = util.join(ctx.build_dir, "verify", "platform-facts.txt")
        fs.mkdirs(util.join(ctx.build_dir, "verify"))
        local probe = util.join(ctx.build_dir, "platform-facts.sh")
        fs.write(probe, [==[
set -u
out="$1"; root="$2"
fs_type="$(stat -f -c %T "$root" 2>/dev/null || echo UNKNOWN)"
wsl=NO
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then wsl=YES; fi
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\nfs_type=%s\nwsl=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" "$fs_type" "$wsl" > "$out"
]==])
        ctx.exec({ "sh", probe, facts, ctx.build_dir },
                 { cwd = ctx.build_dir, log = ctx.log })
        local text = assert(fs.read(facts),
                            "gcpkg: nghttp2: missing platform facts")
        text = text .. "ctx_os=" .. tostring(ctx.os) .. "\n" ..
               "ctx_arch=" .. tostring(ctx.arch) .. "\n" ..
               "jobs=" .. tostring(ctx.jobs) .. "\n" ..
               "enable_lib_only=OFF\n" ..
               "enable_app=OFF reason=libev_source_port_absent\n" ..
               "enable_examples=OFF reason=libevent_source_port_absent\n" ..
               "enable_hpack_tools=OFF reason=jansson_source_port_absent\n" ..
               "enable_http3=OFF reason=ngtcp2_nghttp3_source_ports_absent\n"
        if ctx.features.enabled["zlib"] then
            local zlib = ctx.dep("zlib")
            local zh = assert(fs.read(util.join(zlib.prefix, "include", "zlib.h")),
                              "gcpkg: nghttp2: cannot read zlib.h")
            local zv = zh:match('#define ZLIB_VERSION "([^"]+)"')
            assert(zv == "1.3.1",
                   "gcpkg: nghttp2: unexpected zlib source-port version")
            text = text .. "zlib_prefix=" .. zlib.prefix .. "\n" ..
                   "zlib_version=" .. zv .. "\n"
        else
            text = text .. "zlib=DISABLED_BY_FEATURE\n"
        end
        fs.write(facts, text)
        gcpkg.log.info("nghttp2: install-task platform facts recorded once")
    end,
    post_install = function(ctx)
        local on = ctx.features.enabled
        local prefix = ctx.prefix
        local libdir = util.join(prefix, "lib")
        if not fs.isfile(util.join(libdir, "libnghttp2.a")) and
           not fs.isfile(util.join(libdir, "libnghttp2.so")) and
           fs.isdir(util.join(prefix, "lib64")) then
            libdir = util.join(prefix, "lib64")
        end
        local incdir = util.join(prefix, "include")
        local docdir = util.join(prefix, "share", "doc", "nghttp2")
        local cmakedir = util.join(libdir, "cmake", "nghttp2")
        local pkgdir = util.join(libdir, "pkgconfig")
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(docdir)
        fs.mkdirs(vdir)

        -- library / headers / static / shared: assert real upstream artifacts.
        if on["library"] then
            if on["static"] then
                assert(fs.isfile(util.join(libdir, "libnghttp2.a")),
                       "gcpkg: nghttp2: static libnghttp2.a missing")
            end
            if on["shared"] then
                assert(fs.isfile(util.join(libdir, "libnghttp2.so")) or
                       fs.isfile(util.join(libdir, "libnghttp2.so.14")),
                       "gcpkg: nghttp2: shared libnghttp2.so missing")
            end
        end
        if on["headers"] then
            for _, name in ipairs({ "nghttp2.h", "nghttp2ver.h" }) do
                assert(fs.isfile(util.join(incdir, "nghttp2", name)),
                       "gcpkg: nghttp2: header missing: " .. name)
            end
            local verh = assert(fs.read(util.join(incdir, "nghttp2", "nghttp2ver.h")),
                                "gcpkg: nghttp2: cannot read nghttp2ver.h")
            assert(verh:find('"1.65.0"', 1, true),
                   "gcpkg: nghttp2: installed header is not 1.65.0")
        end
        if on["docs"] then
            for _, name in ipairs({ "nghttp.1", "nghttpd.1", "nghttpx.1", "h2load.1" }) do
                assert(fs.isfile(util.join(prefix, "share", "man", "man1", name)),
                       "gcpkg: nghttp2: upstream man page missing: " .. name)
            end
            assert(fs.isfile(util.join(docdir, "README.rst")),
                   "gcpkg: nghttp2: upstream README.rst missing")
        end
        if on["license"] then
            local src = util.join(ctx.src, "COPYING")
            assert(fs.isfile(src), "gcpkg: nghttp2: upstream COPYING missing")
            ctx.exec({ "cp", "-a", src, util.join(docdir, "COPYING") },
                     { cwd = ctx.src, log = ctx.log })
            assert(fs.isfile(util.join(docdir, "COPYING")),
                   "gcpkg: nghttp2: installed COPYING missing")
        end
        if on["pkgconfig"] then
            local pc = util.join(pkgdir, "libnghttp2.pc")
            assert(fs.isfile(pc), "gcpkg: nghttp2: libnghttp2.pc missing")
            local pct = assert(fs.read(pc), "gcpkg: nghttp2: cannot read libnghttp2.pc")
            assert(pct:find("Version: 1.65.0", 1, true),
                   "gcpkg: nghttp2: .pc version is not 1.65.0")
            assert(pct:find("-lnghttp2", 1, true),
                   "gcpkg: nghttp2: .pc does not advertise -lnghttp2")
            -- Independent CMake consumer through CMake's own FindPkgConfig
            -- module. PKG_CONFIG_PATH is scoped to this installed .pc only.
            local psrc = util.join(vdir, "pkgconfig-consumer", "src")
            local pbin = util.join(vdir, "pkgconfig-consumer", "build")
            fs.mkdirs(psrc); fs.mkdirs(pbin)
            fs.write(util.join(psrc, "CMakeLists.txt"), table.concat({
                "cmake_minimum_required(VERSION 3.16)",
                "project(nghttp2_pc_consumer C)",
                "find_package(PkgConfig REQUIRED)",
                "pkg_check_modules(NGHTTP2 REQUIRED IMPORTED_TARGET libnghttp2>=1.65.0)",
                "add_executable(consumer main.c)",
                "target_link_libraries(consumer PRIVATE PkgConfig::NGHTTP2)",
                "",
            }, "\n"))
            fs.write(util.join(psrc, "main.c"), table.concat({
                "#include <nghttp2/nghttp2.h>",
                "#include <stdio.h>",
                "#include <string.h>",
                "int main(void) {",
                "  nghttp2_info *i = nghttp2_version(0);",
                "  if (!i || !i->version_str || strcmp(i->version_str, \"1.65.0\")) return 2;",
                "  printf(\"gcpkg FindPkgConfig consumer ok: %s\\n\", i->version_str);",
                "  return 0;",
                "}",
                "",
            }, "\n"))
            local ld = libdir .. ":" .. ((ctx.env or {}).LD_LIBRARY_PATH or "")
            local penv = {
                PKG_CONFIG_PATH = pkgdir .. ":" .. ((ctx.env or {}).PKG_CONFIG_PATH or ""),
                LD_LIBRARY_PATH = ld,
            }
            assert(ctx.exec({ "cmake", "-S", psrc, "-B", pbin,
                              "-DCMAKE_BUILD_RPATH=" .. libdir },
                            { cwd = vdir, env = penv }) == 0,
                   "gcpkg: nghttp2: FindPkgConfig consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", pbin, "-j", tostring(ctx.jobs) },
                            { cwd = vdir, env = penv }) == 0,
                   "gcpkg: nghttp2: FindPkgConfig consumer build failed")
            local pout = util.join(vdir, "pkgconfig-consumer.out")
            assert(ctx.exec({ "sh", "-c", util.join(pbin, "consumer") .. " > " .. pout .. " 2>&1" },
                            { cwd = vdir, env = penv }) == 0,
                   "gcpkg: nghttp2: FindPkgConfig consumer run failed")
            local presult = assert(fs.read(pout),
                                   "gcpkg: nghttp2: missing FindPkgConfig consumer output")
            assert(presult:find("FindPkgConfig consumer ok: 1.65.0", 1, true),
                   "gcpkg: nghttp2: FindPkgConfig consumer did not use installed 1.65.0")
        end
        if on["cmake-exports"] then
            local targets = util.join(cmakedir, "nghttp2-targets.cmake")
            local release = util.join(cmakedir, "nghttp2-targets-release.cmake")
            assert(fs.isfile(targets),
                   "gcpkg: nghttp2: upstream nghttp2-targets.cmake missing")
            assert(fs.isfile(release),
                   "gcpkg: nghttp2: upstream nghttp2-targets-release.cmake missing")
            assert(not fs.isfile(util.join(cmakedir, "nghttp2Config.cmake")),
                   "gcpkg: nghttp2: unexpected Config.cmake (upstream 1.65.0 ships none)")
            local tt = assert(fs.read(targets),
                              "gcpkg: nghttp2: cannot read exported targets")
            local have_shared = on["shared"]
            local have_static = on["static"]
            assert(have_shared or have_static,
                   "gcpkg: nghttp2: exported-target consumer needs at least one library")
            if have_shared then
                assert(tt:find("nghttp2::nghttp2", 1, true),
                       "gcpkg: nghttp2: nghttp2::nghttp2 target not exported")
            end
            if have_static then
                assert(tt:find("nghttp2::nghttp2_static", 1, true),
                       "gcpkg: nghttp2: nghttp2::nghttp2_static target not exported")
            end
            -- Independent CMake consumer of the UPSTREAM export file (no
            -- homemade Config.cmake). Each enabled library target is used.
            local esrc = util.join(vdir, "export-consumer", "src")
            local ebin = util.join(vdir, "export-consumer", "build")
            fs.mkdirs(esrc); fs.mkdirs(ebin)
            local clines = {
                "cmake_minimum_required(VERSION 3.16)",
                "project(nghttp2_export_consumer C)",
                "include(\"" .. targets .. "\")",
            }
            local exes = {}
            if have_shared then
                clines[#clines + 1] = "add_executable(consumer_shared main.c)"
                clines[#clines + 1] = "target_link_libraries(consumer_shared PRIVATE nghttp2::nghttp2)"
                exes[#exes + 1] = "consumer_shared"
            end
            if have_static then
                clines[#clines + 1] = "add_executable(consumer_static main.c)"
                clines[#clines + 1] = "target_link_libraries(consumer_static PRIVATE nghttp2::nghttp2_static)"
                exes[#exes + 1] = "consumer_static"
            end
            fs.write(util.join(esrc, "CMakeLists.txt"), table.concat(clines, "\n") .. "\n")
            fs.write(util.join(esrc, "main.c"), table.concat({
                "#include <nghttp2/nghttp2.h>",
                "#include <stdio.h>",
                "#include <string.h>",
                "int main(void) {",
                "  nghttp2_info *i = nghttp2_version(0);",
                "  if (!i || !i->version_str || strcmp(i->version_str, \"1.65.0\")) return 2;",
                "  printf(\"gcpkg export target ok: %s\\n\", i->version_str);",
                "  return 0;",
                "}",
                "",
            }, "\n"))
            local ld = libdir .. ":" .. ((ctx.env or {}).LD_LIBRARY_PATH or "")
            local eenv = { LD_LIBRARY_PATH = ld }
            assert(ctx.exec({ "cmake", "-S", esrc, "-B", ebin,
                              "-DCMAKE_BUILD_RPATH=" .. libdir },
                            { cwd = vdir, env = eenv }) == 0,
                   "gcpkg: nghttp2: upstream export consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", ebin, "-j", tostring(ctx.jobs) },
                            { cwd = vdir, env = eenv }) == 0,
                   "gcpkg: nghttp2: upstream export consumer build failed")
            for _, exe in ipairs(exes) do
                local eout = util.join(vdir, "export-" .. exe .. ".out")
                assert(ctx.exec({ "sh", "-c", util.join(ebin, exe) .. " > " .. eout .. " 2>&1" },
                                { cwd = vdir, env = eenv }) == 0,
                       "gcpkg: nghttp2: upstream export consumer run failed: " .. exe)
                local eresult = assert(fs.read(eout),
                                       "gcpkg: nghttp2: missing export consumer output")
                assert(eresult:find("export target ok: 1.65.0", 1, true),
                       "gcpkg: nghttp2: export consumer did not use installed 1.65.0")
            end
        end

        -- tests: build/run the upstream `check` target (ctest wrapper).
        -- main + failmalloc are EXCLUDE_FROM_ALL; check depends on both.
        -- Facts are written BEFORE the strict assertions so a failure still
        -- leaves an auditable record (openssl r3 lesson).
        if on["tests"] then
            assert(on["static"],
                   "gcpkg: nghttp2: tests feature requires static library")
            local expected = on["failmalloc"] and 2 or 1
            local testlog = util.join(vdir, "ctest.log")
            local testrc = util.join(vdir, "ctest.rc")
            local facts = util.join(vdir, "capability-facts.txt")
            fs.write(facts, table.concat({
                "policy: one real upstream check/ctest run; no test removal, no assertion edits, no filter",
                "expected_tests=" .. tostring(expected),
                "capability_run=full_upstream_check_target",
                "capability_rc=PENDING",
                "final_rc=PENDING",
                "excluded=0",
                "excluded_names=",
                "",
            }, "\n"))
            assert(ctx.exec({ "sh", "-c",
                       "CTEST_OUTPUT_ON_FAILURE=1 cmake --build . --target check --parallel " ..
                       tostring(ctx.jobs) .. " > " .. testlog ..
                       " 2>&1; rc=$?; echo $rc > " .. testrc .. "; exit $rc" },
                     { cwd = ctx.build_dir, log = ctx.log }) == 0,
                   "gcpkg: nghttp2: upstream check/ctest target failed")
            local rc = assert(fs.read(testrc),
                              "gcpkg: nghttp2: missing ctest rc file"):gsub("%s+", "")
            local result = assert(fs.read(testlog),
                                  "gcpkg: nghttp2: missing ctest output")
            local found = tonumber(result:match("out of (%d+)") or "0") or 0
            fs.write(facts, table.concat({
                "policy: one real upstream check/ctest run; no test removal, no assertion edits, no filter",
                "expected_tests=" .. tostring(expected),
                "capability_run=full_upstream_check_target",
                "capability_rc=" .. rc,
                "final_rc=" .. rc,
                "tests_found=" .. tostring(found),
                "excluded=0",
                "excluded_names=",
                "summary=" .. (result:match("(%d+%% tests passed out of %d+)") or "NO_SUMMARY"),
                "",
            }, "\n"))
            assert(rc == "0", "gcpkg: nghttp2: check/ctest rc is not zero")
            assert(not result:find("No tests were found", 1, true),
                   "gcpkg: nghttp2: ctest found no registered tests")
            assert(result:find("100% tests passed", 1, true),
                   "gcpkg: nghttp2: ctest did not pass all registered tests")
            assert(found == expected,
                   "gcpkg: nghttp2: ctest did not run " .. tostring(expected) .. " tests")
            assert(result:find("Test #1: main", 1, true),
                   "gcpkg: nghttp2: upstream main ctest target was not run")
            if on["failmalloc"] then
                assert(result:find("failmalloc", 1, true),
                       "gcpkg: nghttp2: upstream failmalloc target was not run")
            end
        end

        -- sanity: C consumer linked to installed libnghttp2 and the exact
        -- dynamically required zlib source port, with explicit RUNPATHs.
        if on["sanity"] then
            assert(on["library"] and on["headers"] and on["zlib"],
                   "gcpkg: nghttp2: sanity needs library, headers and zlib")
            local zlib = ctx.dep("zlib")
            assert(zlib and zlib.prefix,
                   "gcpkg: nghttp2: sanity requires installed zlib port")
            local zincdir = util.join(zlib.prefix, "include")
            local zlibdir = util.join(zlib.prefix, "lib")
            if not fs.isdir(zlibdir) then
                zlibdir = util.join(zlib.prefix, "lib64")
            end
            local src = util.join(vdir, "nghttp2_sanity.c")
            fs.write(src, [==[
#include <nghttp2/nghttp2.h>
#include <zlib.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    nghttp2_info *i = nghttp2_version(0);
    if (!i || !i->version_str || strcmp(i->version_str, "1.65.0")) return 2;
    if (!zlibVersion() || strcmp(zlibVersion(), "1.3.1")) return 3;
    printf("gcpkg nghttp2 ok: %s / zlib %s\n", i->version_str, zlibVersion());
    return 0;
}
]==])
            local bin = cc.executable {
                sources = { src },
                includes = { incdir, zincdir },
                flags = { "-std=c11", "-Wl,-rpath," .. libdir,
                          "-Wl,-rpath," .. zlibdir },
                cwd = ctx.build_dir,
                outdir = util.join(vdir, "obj"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "nghttp2", cxx = false,
                output = util.join(vdir, "nghttp2_sanity"),
                libdirs = { libdir, zlibdir },
                libs = { "nghttp2", "z" },
            }
            local out = util.join(vdir, "sanity.out")
            local ld = libdir .. ":" .. zlibdir .. ":" ..
                       ((ctx.env or {}).LD_LIBRARY_PATH or "")
            assert(ctx.exec({ "sh", "-c", bin .. " > " .. out .. " 2>&1" },
                            { cwd = vdir, env = { LD_LIBRARY_PATH = ld } }) == 0,
                   "gcpkg: nghttp2: C sanity consumer failed")
            local result = assert(fs.read(out),
                                  "gcpkg: nghttp2: missing C sanity output")
            assert(result:find("nghttp2 ok: 1.65.0 / zlib 1.3.1", 1, true),
                   "gcpkg: nghttp2: sanity did not link installed nghttp2 1.65.0 and source-port zlib 1.3.1")
        end

        gcpkg.log.info("nghttp2: post_install checks complete")
    end,
}
