-- benchmark 1.9.1 -- R20 new-standard port definition.
-- Two official upstream configure/build/install passes give static AND shared
-- libraries without overriding spec.build.  The first pass measures the
-- upstream assembly-test capability; the final static and shared passes use
-- the official assembly gate only when that measurement classifies the
-- failures.  Full upstream ctest runs in both final passes.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "1.9.1"
local CACHE_NAME = "benchmark-1.9.1-v1.9.1"
local CACHE_SHA = "32131c08ee31eeff2c8968d7e874f3cb648034377dfc32a4c377fa8796d84981"

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function fact(text, key)
    return trim(text:match(key:gsub("%-", "%%-") .. "=([^\n]*)") or "")
end
local function defines_to_args(d)
    local out = {}
    for _, k in ipairs(util.keys(d)) do
        out[#out + 1] = "-D" .. k .. "=" .. tostring(d[k])
    end
    return out
end

local function make_defines(ctx, shared, assembly)
    assert(type(shared) == "boolean" and type(assembly) == "boolean",
           "gcpkg: benchmark: make_defines needs boolean shared/assembly flags")
    local on = ctx.features.enabled
    local facts_path = util.join(ctx.build_dir, "verify", "platform-facts.txt")
    local facts = assert(fs.read(facts_path),
                         "gcpkg: benchmark: missing install-task platform facts")
    local filecheck = fact(facts, "filecheck_exe")
    assert(filecheck ~= "" and filecheck ~= "ABSENT",
           "gcpkg: benchmark: FileCheck fact missing; cannot pin assembly tool")
    local gtest = ctx.dep("googletest")
    local gtest_prefix = gtest and gtest.prefix or ""
    local gtest_libdir = gtest and ((gtest.libdirs or {})[1] or
                          util.join(gtest_prefix, "lib")) or ""
    local prefixes = { ctx.prefix }
    if gtest_prefix ~= "" then prefixes[#prefixes + 1] = gtest_prefix end
    local d = {
        CMAKE_BUILD_TYPE = "Release",
        CMAKE_CXX_STANDARD = "17",
        CMAKE_INSTALL_LIBDIR = "lib",
        CMAKE_INSTALL_INCLUDEDIR = "include",
        CMAKE_INSTALL_DOCDIR = "share/doc/benchmark",
        CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
        CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
        CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
        CMAKE_DISABLE_FIND_PACKAGE_Git = "ON",
        GIT_EXECUTABLE = "",
        LLVM_FILECHECK_EXE = filecheck,
        CMAKE_PREFIX_PATH = table.concat(prefixes, ";"),
        GTest_DIR = gtest_libdir ~= "" and util.join(gtest_libdir, "cmake", "GTest") or "",
        BUILD_SHARED_LIBS = shared and "ON" or "OFF",
        BUILD_TESTING = on["tests"] and "ON" or "OFF",
        BENCHMARK_ENABLE_TESTING = on["tests"] and "ON" or "OFF",
        BENCHMARK_ENABLE_GTEST_TESTS = on["gtest-tests"] and "ON" or "OFF",
        BENCHMARK_USE_BUNDLED_GTEST = "OFF",
        BENCHMARK_DOWNLOAD_DEPENDENCIES = "OFF",
        BENCHMARK_ENABLE_INSTALL = on["library"] and "ON" or "OFF",
        BENCHMARK_INSTALL_DOCS = on["docs"] and "ON" or "OFF",
        BENCHMARK_ENABLE_DOXYGEN = "OFF",
        BENCHMARK_ENABLE_EXCEPTIONS = on["exceptions"] and "ON" or "OFF",
        BENCHMARK_ENABLE_LTO = "OFF",
        BENCHMARK_USE_LIBCXX = "OFF",
        BENCHMARK_ENABLE_WERROR = "OFF",
        BENCHMARK_FORCE_WERROR = "OFF",
        BENCHMARK_ENABLE_LIBPFM = "OFF",
        BENCHMARK_ENABLE_ASSEMBLY_TESTS = assembly and "ON" or "OFF",
        CXXFEATURECHECK_DEBUG = "OFF",
        HAVE_STD_REGEX = "TRUE",
        HAVE_STEADY_CLOCK = "TRUE",
        HAVE_PTHREAD_AFFINITY = "TRUE",
        HAVE_LIB_RT = "TRUE",
        BENCHMARK_HAS_O3_FLAG = "TRUE",
        BENCHMARK_HAS_G0_FLAG = "TRUE",
        BENCHMARK_HAS_FNO_STACK_PROTECTOR_FLAG = "TRUE",
        THREADS_PREFER_PTHREAD_FLAG = on["threads"] and "ON" or "OFF",
        CMAKE_HAVE_LIBC_PTHREAD = "1",
        CMAKE_THREAD_LIBS_INIT = "-pthread",
    }
    return d
end

return recipe.cmake {
    name = "benchmark",
    version = VERSION,
    description = "Google Benchmark 1.9.1: static+shared, full ctest, upstream CONFIG/pkgconfig/consumers",
    license = "Apache-2.0",
    homepage = "https://github.com/google/benchmark",
    source = {
        url = "https://codeload.github.com/google/benchmark/tar.gz/refs/tags/v1.9.1",
        sha256 = CACHE_SHA,
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        local on = ctx.features.enabled
        fs.mkdirs(ctx.build_dir)
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))
        fs.mkdirs(util.join(vdir, "obj"))
        local facts_file = util.join(vdir, "platform-facts.txt")
        local probe = util.join(vdir, "platform-facts.sh")
        local cache = util.join(ctx.store.cache, CACHE_NAME)
        local gtest = ctx.dep("googletest")
        local py = ctx.dep("python")
        fs.write(probe, [==[
set -u
out="$1"; root="$2"; cache="$3"; jobs="$4"; vdir="$5"; src="$6"; cxxreal="$7"
fs_type="$(stat -f -c %T "$root" 2>/dev/null || echo UNKNOWN)"
wsl=NO
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then wsl=YES; fi
python3_exe="$(command -v python3 || echo ABSENT)"
python3_version="$(python3 --version 2>&1 | head -1 || echo ABSENT)"
cmake_exe="$(command -v cmake || echo ABSENT)"
cmake_version="$(cmake --version 2>/dev/null | head -1 || echo ABSENT)"
ctest_exe="$(command -v ctest || echo ABSENT)"
ctest_version="$(ctest --version 2>/dev/null | head -1 || echo ABSENT)"
pkgconfig_exe="$(command -v pkg-config || echo ABSENT)"
filecheck_path_exe="$(command -v FileCheck || echo ABSENT)"
filecheck_exe="/usr/lib/llvm-23/bin/FileCheck"
[ -x "$filecheck_exe" ] || filecheck_exe=ABSENT
cxx_exe="$(command -v c++ || echo ABSENT)"
cxx_real_version="$("$cxxreal" --version 2>/dev/null | head -1 || echo ABSENT)"
expected_assembly_clang="$(sed -n 's/^set(CLANG_SUPPORTED_VERSION "\([^"]*\)").*/\1/p' "$src/test/AssemblyTests.cmake" | head -1)"
cache_sha="$(sha256sum "$cache" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)"
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\nfs_type=%s\nwsl=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" "$fs_type" "$wsl" > "$out"
printf 'jobs=%s\nhome=%s\ntmp=%s\n' "$jobs" "$vdir/home" "$vdir/tmp" >> "$out"
printf 'python3_exe=%s\npython3_version=%s\ncmake_exe=%s\ncmake_version=%s\nctest_exe=%s\nctest_version=%s\n' \
  "$python3_exe" "$python3_version" "$cmake_exe" "$cmake_version" "$ctest_exe" "$ctest_version" >> "$out"
printf 'pkgconfig_exe=%s\nfilecheck_path_exe=%s\nfilecheck_exe=%s\ncxx_exe=%s\ncxx_real_version=%s\nexpected_assembly_clang=%s\n' \
  "$pkgconfig_exe" "$filecheck_path_exe" "$filecheck_exe" "$cxx_exe" "$cxx_real_version" "$expected_assembly_clang" >> "$out"
printf 'cache_name=%s\ncache_sha=%s\n' "$cache" "$cache_sha" >> "$out"
printf 'source_port_deps=2\ndynamic_requires=3\n' >> "$out"
printf 'libpfm=OFF reason=optional_source_port_not_r20_reaudited\n' >> "$out"
printf 'doxygen=OFF reason=install_upstream_source_docs_not_generated_html\n' >> "$out"
printf 'lto=OFF libcxx=OFF reason=toolchain_modes_outside_source_port_audit\n' >> "$out"
printf 'capability_policy=full_upstream_ctest_capability_run_then_official_assembly_gate_no_ctest_E_no_source_patch\n' >> "$out"
printf 'registry=OFF\nno_compiler_probe=ON\nno_network_download=ON\n' >> "$out"
]==])
        assert(ctx.exec({ "sh", probe, facts_file, ctx.build_dir, cache,
                          tostring(ctx.jobs), vdir, ctx.src,
                          ctx.compiler.cxx },
                        { cwd = ctx.build_dir, log = ctx.log }) == 0,
               "gcpkg: benchmark: install-task platform facts script failed")
        fs.append(facts_file, table.concat({
            "gtest_prefix=" .. (gtest and gtest.prefix or "ABSENT"),
            "python_prefix=" .. (py and py.prefix or "ABSENT"),
            "static_pass=ON",
            "shared_pass=" .. (on["shared"] and "ON" or "OFF"),
            "tests_pass=" .. (on["tests"] and "ON" or "OFF"),
            "gtest_tests_pass=" .. (on["gtest-tests"] and "ON" or "OFF"),
            "python_tools_pass=" .. (on["python-tools"] and "ON" or "OFF"),
            "assembly_capability_pass=ON",
            "",
        }, "\n"))

        r20.restrict_pkgconfig(ctx)
        local pc_dir = util.join(ctx.prefix, "lib", "pkgconfig")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        assert(fs.isfile(wrapper),
               "gcpkg: benchmark: source-only pkg-config wrapper missing")
        ctx.env.PKG_CONFIG_PATH = pc_dir
        ctx.env.PKG_CONFIG_LIBDIR = pc_dir
        ctx.env.PKG_CONFIG_EXECUTABLE = wrapper
        ctx.env.PKG_CONFIG = wrapper
        ctx.env.GCPKG_PKG_CONFIG_REAL = "/usr/bin/pkg-config"
        ctx.env.GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = util.join(ctx.prefix, "include")
        ctx.env.LD_LIBRARY_PATH = util.join(ctx.prefix, "lib") .. ":" ..
                                  (gtest and ((gtest.libdirs or {})[1] or
                                   util.join(gtest.prefix, "lib")) or "") .. ":" ..
                                  ((ctx.env or {}).LD_LIBRARY_PATH or "")
        ctx.env.HOME = util.join(vdir, "home")
        ctx.env.TMPDIR = util.join(vdir, "tmp")
        ctx.env.XDG_CONFIG_HOME = util.join(vdir, "home", ".config")
        ctx.env.XDG_CACHE_HOME = util.join(vdir, "home", ".cache")
        ctx.env.XDG_DATA_HOME = util.join(vdir, "home", ".local", "share")
        gcpkg.log.info("benchmark: install-task platform/service facts recorded once")
    end,
    cmake = {
        defines = function(ctx)
            return make_defines(ctx, false, true)
        end,
        args = {},
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local prefix = ctx.prefix
        local libdir = util.join(prefix, "lib")
        if not fs.isdir(libdir) and fs.isdir(util.join(prefix, "lib64")) then
            libdir = util.join(prefix, "lib64")
        end
        local incdir = util.join(prefix, "include")
        local cmakedir = util.join(libdir, "cmake", "benchmark")
        local pkgdir = util.join(libdir, "pkgconfig")
        local docdir = util.join(prefix, "share", "doc", "benchmark")
        local tooldir = util.join(prefix, "share", "benchmark", "tools")
        local vdir = util.join(ctx.build_dir, "verify")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))
        fs.mkdirs(util.join(vdir, "obj"))

        local facts = assert(fs.read(util.join(vdir, "platform-facts.txt")),
                             "gcpkg: benchmark: missing platform facts")
        local port_log = assert(fs.read(ctx.log),
                                "gcpkg: benchmark: missing port build log")
        local host_python = fact(facts, "python3_exe")
        assert(host_python ~= "" and host_python ~= "ABSENT",
               "gcpkg: benchmark: Python3 fact missing")
        assert(facts:find("cache_sha=" .. CACHE_SHA, 1, true),
               "gcpkg: benchmark: cached source tarball SHA mismatch")
        local expected_clang = fact(facts, "expected_assembly_clang")
        assert(expected_clang ~= "" and expected_clang ~= "ABSENT",
               "gcpkg: benchmark: upstream expected assembly compiler fact missing")
        local gtest = ctx.dep("googletest")
        local gtest_libdir = gtest and ((gtest.libdirs or {})[1] or
                              util.join(gtest.prefix, "lib")) or ""
        local py = ctx.dep("python")
        local source_python = py and util.join(py.prefix, "bin", "python3") or host_python

        local tenv = util.merge(ctx.env, {
            HOME = util.join(vdir, "home"),
            TMPDIR = util.join(vdir, "tmp"),
            XDG_CONFIG_HOME = util.join(vdir, "home", ".config"),
            XDG_CACHE_HOME = util.join(vdir, "home", ".cache"),
            XDG_DATA_HOME = util.join(vdir, "home", ".local", "share"),
            LD_LIBRARY_PATH = libdir .. ":" .. gtest_libdir .. ":" ..
                              ((ctx.env or {}).LD_LIBRARY_PATH or ""),
            PKG_CONFIG_PATH = pkgdir,
            PKG_CONFIG_LIBDIR = pkgdir,
            PKG_CONFIG_EXECUTABLE = wrapper,
            PKG_CONFIG = wrapper,
            GCPKG_PKG_CONFIG_REAL = "/usr/bin/pkg-config",
            GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = incdir,
            CTEST_OUTPUT_ON_FAILURE = "1",
        })

        local function run_capture(cmd, out, rcfile, env, cwd)
            local q = cmd .. " > " .. out .. " 2>&1; echo $? > " .. rcfile
            assert(ctx.exec({ "sh", "-c", q },
                            { cwd = cwd or vdir, env = env or tenv,
                              log = ctx.log }) == 0,
                   "gcpkg: benchmark: capture shell failed: " .. cmd)
            return trim(assert(fs.read(rcfile),
                               "gcpkg: benchmark: missing rc file")),
                   assert(fs.read(out), "gcpkg: benchmark: missing output file")
        end

        local function ctest_pass(tag)
            local nlog = util.join(vdir, "ctest-" .. tag .. ".N")
            local nrc = util.join(vdir, "ctest-" .. tag .. ".N.rc")
            local nrcv = run_capture("ctest -N", nlog, nrc, tenv, ctx.build_dir)
            assert(nrcv == "0", "gcpkg: benchmark: ctest -N failed for " .. tag)
            local ntext = assert(fs.read(nlog),
                                 "gcpkg: benchmark: missing ctest -N log")
            local registered = tonumber(ntext:match("Total Tests: (%d+)") or "0") or 0
            assert(registered >= 67 and registered <= 80,
                   "gcpkg: benchmark: unexpected registered ctest count: " .. registered)
            local cap_log = util.join(vdir, "ctest-" .. tag .. ".log")
            local cap_rc_file = util.join(vdir, "ctest-" .. tag .. ".rc")
            local cap_rc = run_capture("ctest --output-on-failure --timeout 180",
                                       cap_log, cap_rc_file, tenv, ctx.build_dir)
            local cap = assert(fs.read(cap_log),
                               "gcpkg: benchmark: missing ctest log " .. tag)
            local failures, seen, in_failed = {}, {}, false
            for _, line in ipairs(util.lines(cap)) do
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
            local total = tonumber(cap:match("out of (%d+)") or "0") or 0
            local percent = tonumber(cap:match("(%d+)%% tests passed") or "0") or 0
            local summary = cap:match("(%d+%% tests passed[^\n]*)") or "NO_SUMMARY"
            return {
                rc = cap_rc, registered = registered, total = total,
                percent = percent, summary = summary,
                failures = failures, log = cap,
            }
        end

        local capability = on["tests"] and ctest_pass("capability") or nil
        local unclassified, assembly_names = {}, {}
        if capability then
            for _, n in ipairs(capability.failures) do
                if n:match("^run_.*_assembly_test_CHECK$") then
                    assembly_names[#assembly_names + 1] = n
                else
                    unclassified[#unclassified + 1] = n
                end
            end
            if #assembly_names > 0 then
                assert(port_log:find("Unsupported Clang version", 1, true) and
                       port_log:find("Expected is " .. expected_clang, 1, true),
                       "gcpkg: benchmark: assembly failures lack upstream compiler-version warning")
                assert(not fact(facts, "cxx_real_version"):find(expected_clang, 1, true),
                       "gcpkg: benchmark: measured compiler unexpectedly equals upstream assembly baseline")
            end
        end
        local excluded = #assembly_names
        local final_assembly = excluded == 0
        local function fmt_result(r)
            if not r then return "DISABLED" end
            return "registered=" .. r.registered .. " total=" .. r.total ..
                   " percent=" .. r.percent .. " rc=" .. r.rc ..
                   " failed=" .. #r.failures ..
                   " names=" .. table.concat(r.failures, ",") ..
                   " summary=" .. r.summary
        end

        local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
        assert(fs.isfile(noTry),
               "gcpkg: benchmark: framework no-probe include missing")
        local function reconfigure(tag, shared, assembly)
            local cmd = {
                "cmake", "-S", ctx.src, "-B", ctx.build_dir,
                "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
                "-DCMAKE_INSTALL_PREFIX=" .. prefix,
                "-DCMAKE_PROJECT_INCLUDE=" .. noTry,
                "-DCMAKE_CXX_COMPILER=" .. ctx.compiler.wrapper_cxx,
                "-DCMAKE_CXX_COMPILER_FORCED=TRUE",
                "-DCMAKE_CXX_COMPILER_WORKS=TRUE",
                "-DCMAKE_C_COMPILER=" .. ctx.compiler.wrapper_cc,
                "-DCMAKE_C_COMPILER_FORCED=TRUE",
                "-DCMAKE_C_COMPILER_WORKS=TRUE",
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
            }
            for _, a in ipairs(defines_to_args(make_defines(ctx, shared, assembly))) do
                cmd[#cmd + 1] = a
            end
            for _, a in ipairs(ctx.feature_args()) do cmd[#cmd + 1] = a end
            assert(ctx.exec(cmd, { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: benchmark: " .. tag .. " reconfigure failed")
            assert(ctx.exec({ "cmake", "--build", ctx.build_dir,
                              "--parallel", tostring(ctx.jobs) },
                            { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: benchmark: " .. tag .. " build failed")
            assert(ctx.exec({ "cmake", "--install", ctx.build_dir },
                            { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: benchmark: " .. tag .. " install failed")
        end

        local static_compdb = util.join(vdir, "compile_commands.static.json")
        local shared_compdb = util.join(ctx.build_dir, "compile_commands.json")
        local merged_compdb = util.join(vdir, "compile_commands.merged.json")
        reconfigure("final-static", false, final_assembly)
        assert(ctx.exec({ "sh", "-c", "cp " .. shared_compdb .. " " .. static_compdb },
                        { cwd = vdir, env = tenv }) == 0,
               "gcpkg: benchmark: cannot save static compile_commands.json")
        local static_result = on["tests"] and ctest_pass("static") or nil

        if on["shared"] then
            reconfigure("shared", true, final_assembly)
            assert(ctx.exec({ "sh", "-c", "cp " .. shared_compdb .. " " ..
                              util.join(vdir, "compile_commands.shared.json") },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: benchmark: cannot save shared compile_commands.json")
            local merged_py = util.join(vdir, "merge_compdb.py")
            fs.write(merged_py, [==[
import json, sys
a = json.load(open(sys.argv[1], encoding="utf-8"))
b = json.load(open(sys.argv[2], encoding="utf-8"))
json.dump(a + b, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False)
]==])
            assert(ctx.exec({ source_python, merged_py, static_compdb,
                              util.join(vdir, "compile_commands.shared.json"),
                              merged_compdb },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: benchmark: compile_commands merge failed")
            assert(ctx.exec({ "sh", "-c", "cp " .. merged_compdb .. " " .. shared_compdb },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: benchmark: cannot install merged compile_commands.json")
        end
        local shared_result = on["tests"] and on["shared"] and ctest_pass("shared") or nil

        fs.write(util.join(vdir, "capability-facts.txt"), table.concat({
            "policy=full_upstream_ctest_capability_run_then_official_assembly_gate",
            "no_ctest_E=1",
            "no_source_patch=1",
            "no_static_test_number_blacklist=1",
            "upstream_assembly_expected_clang=" .. expected_clang,
            "capability=" .. fmt_result(capability),
            "static=" .. fmt_result(static_result),
            "shared=" .. fmt_result(shared_result),
            "unclassified_failure_lines=" .. table.concat(unclassified, ","),
            "excluded=" .. excluded,
            "excluded_names=" .. table.concat(assembly_names, ","),
            "assembly_gate=" .. (final_assembly and "ON" or
                                 "official_BENCHMARK_ENABLE_ASSEMBLY_TESTS_OFF"),
            "final_rc=" .. (shared_result and shared_result.rc or
                            (static_result and static_result.rc or "NOT_RUN")),
            "",
        }, "\n"))

        if capability then
            assert(capability.total == capability.registered,
                   "gcpkg: benchmark: capability ctest total mismatch: " .. fmt_result(capability))
            assert(#unclassified == 0,
                   "gcpkg: benchmark: unclassified ctest failures: " ..
                   table.concat(unclassified, ","))
            assert(excluded <= 3,
                   "gcpkg: benchmark: too many classified assembly failures")
            assert(port_log:find("Unsupported Clang version", 1, true) or
                   excluded == 0,
                   "gcpkg: benchmark: capability run lacks assembly compiler warning")
        end
        local function assert_full(r, label, expected_registered)
            if not r then return end
            assert(r.rc == "0" and r.percent == 100,
                   "gcpkg: benchmark: " .. label .. " ctest not 100%: " .. fmt_result(r))
            assert(r.total == r.registered and r.registered == expected_registered,
                   "gcpkg: benchmark: " .. label .. " ctest total mismatch: " .. fmt_result(r))
            assert(#r.failures == 0,
                   "gcpkg: benchmark: " .. label .. " ctest failures: " ..
                   table.concat(r.failures, ","))
            assert(not r.log:find("The following tests FAILED", 1, true),
                   "gcpkg: benchmark: " .. label .. " ctest reported failed tests")
        end
        local expected_final = capability and (capability.registered - excluded) or 77
        assert_full(static_result, "static", expected_final)
        assert_full(shared_result, "shared", expected_final)

        if on["library"] and on["static"] then
            for _, n in ipairs({ "benchmark", "benchmark_main" }) do
                assert(fs.isfile(util.join(libdir, "lib" .. n .. ".a")),
                       "gcpkg: benchmark: missing static lib" .. n .. ".a")
            end
        end
        if on["library"] and on["shared"] then
            for _, n in ipairs({ "benchmark", "benchmark_main" }) do
                assert(fs.isfile(util.join(libdir, "lib" .. n .. ".so.1.9.1")),
                       "gcpkg: benchmark: missing shared lib" .. n .. ".so.1.9.1")
                assert(fs.isfile(util.join(libdir, "lib" .. n .. ".so")),
                       "gcpkg: benchmark: missing shared lib" .. n .. ".so symlink")
            end
        end
        if on["headers"] then
            for _, h in ipairs({ "benchmark/benchmark.h", "benchmark/export.h" }) do
                assert(fs.isfile(util.join(incdir, h)),
                       "gcpkg: benchmark: missing header " .. h)
            end
        end
        fs.mkdirs(docdir)
        fs.mkdirs(tooldir)
        if on["license"] then
            assert(ctx.exec({ "sh", "-c", "cp " .. util.join(ctx.src, "LICENSE") ..
                         " " .. util.join(docdir, "LICENSE") },
                   { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: benchmark: cannot install LICENSE")
        end
        if on["python-tools"] then
            assert(py and py.prefix,
                   "gcpkg: benchmark: python-tools needs source-built python")
            local python_exe = source_python
            for _, tool in ipairs({ "compare.py", "strip_asm.py" }) do
                assert(ctx.exec({ "sh", "-c", "cp " ..
                             util.join(ctx.src, "tools", tool) .. " " ..
                             util.join(tooldir, tool) },
                       { cwd = vdir, env = tenv }) == 0,
                       "gcpkg: benchmark: cannot install tool " .. tool)
            end
            assert(ctx.exec({ python_exe, "-m", "py_compile",
                              util.join(tooldir, "compare.py"),
                              util.join(tooldir, "strip_asm.py") },
                            { cwd = vdir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: benchmark: Python tools byte-compile failed")
        end
        if on["docs"] then
            local dc = util.join(vdir, "docs.count")
            assert(ctx.exec({ "sh", "-c", "find " .. docdir ..
                         " -type f 2>/dev/null | wc -l > " .. dc },
                   { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: benchmark: docs count failed")
            local n = tonumber(trim(assert(fs.read(dc),
                             "gcpkg: benchmark: missing docs count"))) or 0
            assert(n >= 16, "gcpkg: benchmark: too few installed docs: " .. n)
        end

        if on["pkgconfig"] then
            for _, pc in ipairs({ "benchmark.pc", "benchmark_main.pc" }) do
                assert(fs.isfile(util.join(pkgdir, pc)),
                       "gcpkg: benchmark: missing upstream .pc " .. pc)
            end
            local gpc = assert(fs.read(util.join(pkgdir, "benchmark.pc")),
                               "gcpkg: benchmark: cannot read benchmark.pc")
            assert(gpc:find("Version: " .. VERSION, 1, true),
                   "gcpkg: benchmark: benchmark.pc version mismatch")
            assert(gpc:find("prefix=" .. prefix, 1, true) and
                   not gpc:find("/usr/local", 1, true),
                   "gcpkg: benchmark: benchmark.pc leaked a host prefix")
            local pmod = util.join(vdir, "pkgconfig-modversion.out")
            local prc = util.join(vdir, "pkgconfig-modversion.rc")
            local rc, pout = run_capture('"' .. wrapper ..
                                          '" --modversion benchmark benchmark_main',
                                          pmod, prc, tenv)
            assert(rc == "0" and pout:find(VERSION, 1, true),
                   "gcpkg: benchmark: pkg-config --modversion failed: " .. pout)
            local pflags = util.join(vdir, "pkgconfig-flags.out")
            local pfrc = util.join(vdir, "pkgconfig-flags.rc")
            local frc, fout = run_capture('"' .. wrapper ..
                                          '" --cflags --libs benchmark benchmark_main',
                                          pflags, pfrc, tenv)
            assert(frc == "0" and fout:find("-I" .. incdir, 1, true) and
                   fout:find("-L" .. libdir, 1, true) and
                   fout:find("-lbenchmark_main", 1, true) and
                   fout:find("-lbenchmark", 1, true),
                   "gcpkg: benchmark: pkg-config flags do not use the source-port prefix")
        end
        if on["cmake-package"] then
            for _, f in ipairs({ "benchmarkConfig.cmake", "benchmarkConfigVersion.cmake",
                                 "benchmarkTargets.cmake", "benchmarkTargets-release.cmake" }) do
                assert(fs.isfile(util.join(cmakedir, f)),
                       "gcpkg: benchmark: missing upstream CMake package file " .. f)
            end
            local cfg = assert(fs.read(util.join(cmakedir, "benchmarkConfig.cmake")),
                               "gcpkg: benchmark: cannot read benchmarkConfig.cmake")
            assert(cfg:find("find_dependency (Threads)", 1, true) or
                   cfg:find("find_dependency(Threads)", 1, true),
                   "gcpkg: benchmark: upstream CONFIG lost Threads dependency")
            local ver = assert(fs.read(util.join(cmakedir, "benchmarkConfigVersion.cmake")),
                               "gcpkg: benchmark: cannot read benchmarkConfigVersion.cmake")
            assert(ver:find('"' .. VERSION .. '"', 1, true),
                   "gcpkg: benchmark: CONFIG version mismatch")
            local targets = assert(fs.read(util.join(cmakedir, "benchmarkTargets.cmake")),
                                   "gcpkg: benchmark: cannot read benchmarkTargets.cmake")
            for _, t in ipairs({ "benchmark::benchmark", "benchmark::benchmark_main" }) do
                assert(targets:find(t, 1, true),
                       "gcpkg: benchmark: missing exported target " .. t)
            end
            assert(not fs.isfile(util.join(cmakedir, "benchmarkConfig.cmake.gcpkg")),
                   "gcpkg: benchmark: hand-written CONFIG file is forbidden")
        end
        fs.write(util.join(vdir, "no-homemade-config.txt"),
                 "NO_HOMEMADE_CONFIG=YES\nUPSTREAM_BENCHMARK_CONFIG=YES\n")

        local consumer_cpp = [==[
#include <benchmark/benchmark.h>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
static void BM_Gcpkg(benchmark::State& state) {
  for (auto _ : state) { benchmark::DoNotOptimize(state.iterations()); }
}
BENCHMARK(BM_Gcpkg);
int main(int argc, char **argv) {
  benchmark::Initialize(&argc, argv);
  if (benchmark::ReportUnrecognizedArguments(argc, argv)) return 1;
  benchmark::RunSpecifiedBenchmarks();
  printf("gcpkg benchmark %s ok: %s\n", XSTR(CONSUMER_KIND), XSTR(GCPKG_BENCHMARK_VERSION));
  return 0;
}
]==]
        local function cmake_consumer(kind, cmake_text, defines)
            local dir = util.join(vdir, "consumers", kind)
            fs.mkdirs(dir)
            fs.write(util.join(dir, "CMakeLists.txt"), cmake_text)
            fs.write(util.join(dir, "main.cpp"), consumer_cpp)
            local bdir = util.join(dir, "build")
            local cmd = {
                "cmake", "-S", dir, "-B", bdir,
                "-DCMAKE_PROJECT_INCLUDE=" .. noTry,
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                "-DCMAKE_CXX_COMPILER=" .. ctx.compiler.wrapper_cxx,
                "-DCMAKE_CXX_COMPILER_FORCED=TRUE",
                "-DCMAKE_CXX_COMPILER_WORKS=TRUE",
                "-DCMAKE_CXX_STANDARD=17",
                "-DCMAKE_PREFIX_PATH=" .. prefix .. ";" ..
                    (gtest and gtest.prefix or ""),
                "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
                "-DPKG_CONFIG_EXECUTABLE=" .. wrapper,
            }
            for _, a in ipairs(defines) do cmd[#cmd + 1] = a end
            assert(ctx.exec(cmd, { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: benchmark: " .. kind .. " consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", bdir, "--parallel", "4" },
                            { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: benchmark: " .. kind .. " consumer build failed")
            local out = util.join(dir, "run.out")
            local rcf = util.join(dir, "run.rc")
            local rc = run_capture(util.join(bdir, "consumer") ..
                                   " --benchmark_min_time=0.01s",
                                   out, rcf, tenv, dir)
            assert(rc == "0", "gcpkg: benchmark: " .. kind ..
                   " consumer run failed")
            local text = assert(fs.read(out),
                                "gcpkg: benchmark: missing " .. kind .. " consumer output")
            assert(text:find("gcpkg benchmark " .. kind .. " ok: " .. VERSION, 1, true),
                   "gcpkg: benchmark: " .. kind ..
                   " consumer did not use installed " .. VERSION)
        end

        if on["consumers"] then
            assert(on["library"] and on["headers"] and on["cmake-package"] and
                   on["pkgconfig"], "gcpkg: benchmark: consumers need library/headers/cmake-package/pkgconfig")
            cmake_consumer("CONFIG", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_benchmark_config_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(benchmark 1.9.1 CONFIG REQUIRED)
add_executable(consumer main.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=CONFIG GCPKG_BENCHMARK_VERSION=1.9.1)
target_link_libraries(consumer PRIVATE benchmark::benchmark_main benchmark::benchmark)
]==], { "-Dbenchmark_DIR=" .. cmakedir })
            cmake_consumer("FindPkgConfig", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_benchmark_pkgconfig_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GCPKG_BENCHMARK REQUIRED IMPORTED_TARGET benchmark benchmark_main)
add_executable(consumer main.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=FindPkgConfig GCPKG_BENCHMARK_VERSION=1.9.1)
target_include_directories(consumer PRIVATE ${GCPKG_BENCHMARK_INCLUDE_DIRS})
target_compile_options(consumer PRIVATE ${GCPKG_BENCHMARK_CFLAGS_OTHER})
target_link_libraries(consumer PRIVATE PkgConfig::GCPKG_BENCHMARK)
]==], {})
        end

        if on["sanity"] then
            assert(on["library"] and on["headers"],
                   "gcpkg: benchmark: sanity needs library and headers")
            local sanity_src = util.join(vdir, "benchmark_sanity.cpp")
            fs.write(sanity_src, [==[
#include <benchmark/benchmark.h>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
static void BM_Gcpkg(benchmark::State& state) {
  for (auto _ : state) { benchmark::DoNotOptimize(state.iterations()); }
}
BENCHMARK(BM_Gcpkg);
int main(int argc, char **argv) {
  benchmark::Initialize(&argc, argv);
  if (benchmark::ReportUnrecognizedArguments(argc, argv)) return 1;
  benchmark::RunSpecifiedBenchmarks();
  printf("gcpkg benchmark %s ok: %s\n", XSTR(SANITY_KIND), XSTR(GCPKG_BENCHMARK_VERSION));
  return 0;
}
]==])
            local function direct_sanity(kind, flags, libs)
                local bin = cc.executable {
                    sources = { sanity_src },
                    includes = { incdir },
                    defines = { "SANITY_KIND=" .. kind,
                                "GCPKG_BENCHMARK_VERSION=" .. VERSION },
                    flags = flags,
                    cwd = vdir,
                    outdir = util.join(vdir, "obj"),
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "benchmark", cxx = true,
                    output = util.join(vdir, "benchmark_" .. kind .. "_consumer"),
                    libdirs = { libdir },
                    libs = libs,
                }
                local out = util.join(vdir, "sanity-" .. kind .. ".out")
                local rcf = util.join(vdir, "sanity-" .. kind .. ".rc")
                local rc = run_capture(bin .. " --benchmark_min_time=0.01s",
                                       out, rcf, tenv, vdir)
                assert(rc == "0", "gcpkg: benchmark: " .. kind ..
                       " sanity consumer failed")
                local text = assert(fs.read(out),
                                    "gcpkg: benchmark: missing " .. kind .. " sanity output")
                assert(text:find("gcpkg benchmark " .. kind .. " ok: " .. VERSION, 1, true),
                       "gcpkg: benchmark: " .. kind ..
                       " sanity did not link installed " .. VERSION)
            end
            if on["static"] then
                direct_sanity("static", { "-std=c++17", "-pthread",
                    "-l:libbenchmark_main.a", "-l:libbenchmark.a" }, {})
            end
            if on["shared"] then
                direct_sanity("shared", { "-std=c++17", "-pthread" },
                              { "benchmark_main", "benchmark" })
            end
        end

        gcpkg.log.info("benchmark: post_install checks complete")
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "benchmark", "benchmark_main" },
        binaries = {},
    },
}
