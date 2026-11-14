-- googletest 1.15.2 -- R20 new-standard re-audit of the P2 dependency graph.
-- Declarative recipe.cmake keeps the framework absolute-no-probe injection.
-- Positive features.yaml args are appended last and drive every upstream
-- capability.  The first official configure pass is BUILD_SHARED_LIBS=OFF
-- (static libs + full ctest); post_install performs a SECOND official pass
-- with BUILD_SHARED_LIBS=ON (shared libs + full ctest), installs into the
-- same prefix, and merges both compile_commands.json arrays in place.
-- dependencies = {} because there is no independent source-port library;
-- `on` features gate every verification.  r20.restrict_pkgconfig is called
-- explicitly in pre_build; the wrapper path is pinned to this port's .pc
-- directory.  No spec.build override, no hand-written CONFIG, no source
-- patch, no test filter, no static test-number blacklist.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "1.15.2"
local CACHE_NAME = "googletest-1.15.2-v1.15.2"
local CACHE_SHA = "7b42b4d6ed48810c5362c265a17faebe90dc2373c885e5216439d37927f02926"

local function trim(s)
    return (tostring(s or ""):gsub("%s+", ""))
end

local function fact(text, name)
    return text:match(name .. "=([^%s]+)") or ""
end

local function lib_names(on)
    local t = { "gtest", "gtest_main" }
    if on["gmock"] then
        t[#t + 1] = "gmock"
        t[#t + 1] = "gmock_main"
    end
    return t
end

local function static_file(libdir, name)
    return util.join(libdir, "lib" .. name .. ".a")
end

local function shared_file(libdir, name)
    for _, f in ipairs({ "lib" .. name .. ".so", "lib" .. name .. ".so." .. VERSION }) do
        local p = util.join(libdir, f)
        if fs.isfile(p) then return p end
    end
    return nil
end

local function defines_to_args(d)
    local out = {}
    for _, k in ipairs(util.keys(d)) do
        out[#out + 1] = "-D" .. k .. "=" .. tostring(d[k])
    end
    return out
end

local function make_defines(ctx, shared)
    assert(type(shared) == "boolean",
           "gcpkg: googletest: make_defines needs a boolean shared flag")
    local on = ctx.features.enabled
    local facts_path = util.join(ctx.build_dir, "verify", "platform-facts.txt")
    local facts = assert(fs.read(facts_path),
                         "gcpkg: googletest: missing install-task platform facts")
    local python = fact(facts, "python3_exe")
    local pkgconfig = fact(facts, "pkgconfig_exe")
    assert(python ~= "" and python ~= "ABSENT",
           "gcpkg: googletest: Python3 fact missing; cannot pin Python3_EXECUTABLE")
    assert(pkgconfig ~= "" and pkgconfig ~= "ABSENT",
           "gcpkg: googletest: pkg-config fact missing; cannot pin FindPkgConfig")
    local d = {
        CMAKE_BUILD_TYPE = "Release",
        CMAKE_INSTALL_LIBDIR = "lib",
        CMAKE_INSTALL_INCLUDEDIR = "include",
        CMAKE_PREFIX_PATH = ctx.prefix,
        CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
        CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
        CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
        BUILD_GMOCK = on["gmock"] and "ON" or "OFF",
        INSTALL_GTEST = "ON",
        GTEST_HAS_ABSL = "OFF",
        gtest_force_shared_crt = "ON",
        gtest_hide_internal_symbols = "OFF",
        gtest_disable_pthreads = on["pthreads"] and "OFF" or "ON",
        gtest_build_tests = on["tests"] and "ON" or "OFF",
        gmock_build_tests = on["tests"] and "ON" or "OFF",
        gtest_build_samples = on["examples"] and "ON" or "OFF",
        CMAKE_DISABLE_FIND_PACKAGE_Python3 = on["python-tests"] and "OFF" or "ON",
        Python3_EXECUTABLE = python,
        Python3_FIND_STRATEGY = "LOCATION",
        THREADS_PREFER_PTHREAD_FLAG = "ON",
        CMAKE_HAVE_LIBC_PTHREAD = "1",
        CMAKE_THREAD_LIBS_INIT = "-pthread",
        BUILD_SHARED_LIBS = shared and "ON" or "OFF",
    }
    return d
end

return recipe.cmake {
    name = "googletest",
    version = VERSION,
    description = "GoogleTest/GoogleMock 1.15.2: static+shared, full upstream ctest, examples, pkgconfig, CONFIG and consumers",
    license = "BSD-3-Clause",
    homepage = "https://github.com/google/googletest",
    source = {
        url = "https://codeload.github.com/google/googletest/tar.gz/refs/tags/v1.15.2",
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
        fs.write(probe, [==[
set -u
out="$1"; root="$2"; cache="$3"; jobs="$4"; vdir="$5"
fs_type="$(stat -f -c %T "$root" 2>/dev/null || echo UNKNOWN)"
wsl=NO
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then wsl=YES; fi
python3_exe="$(command -v python3 || echo ABSENT)"
cmake_exe="$(command -v cmake || echo ABSENT)"
ctest_exe="$(command -v ctest || echo ABSENT)"
pkgconfig_exe="$(command -v pkg-config || echo ABSENT)"
sh_exe="$(command -v sh || echo ABSENT)"
bash_exe="$(command -v bash || echo ABSENT)"
cc_exe="$(command -v cc || echo ABSENT)"
cxx_exe="$(command -v c++ || echo ABSENT)"
python3_version="$(python3 --version 2>&1 | head -1 || echo ABSENT)"
cmake_version="$(cmake --version 2>/dev/null | head -1 || echo ABSENT)"
ctest_version="$(ctest --version 2>/dev/null | head -1 || echo ABSENT)"
cache_sha="$(sha256sum "$cache" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)"
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\nfs_type=%s\nwsl=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" "$fs_type" "$wsl" > "$out"
printf 'jobs=%s\nhome=%s\ntmp=%s\n' "$jobs" "$vdir/home" "$vdir/tmp" >> "$out"
printf 'python3_exe=%s\npython3_version=%s\ncmake_exe=%s\ncmake_version=%s\nctest_exe=%s\nctest_version=%s\n' \
  "$python3_exe" "$python3_version" "$cmake_exe" "$cmake_version" "$ctest_exe" "$ctest_version" >> "$out"
printf 'pkgconfig_exe=%s\nsh_exe=%s\nbash_exe=%s\ncc_exe=%s\ncxx_exe=%s\n' \
  "$pkgconfig_exe" "$sh_exe" "$bash_exe" "$cc_exe" "$cxx_exe" >> "$out"
printf 'cache_name=%s\ncache_sha=%s\n' "$cache" "$cache_sha" >> "$out"
printf 'source_port_deps=0\ndynamic_requires=0\n' >> "$out"
printf 'absl=OFF reason=optional_abseil_re2_source_ports_not_r20_reaudited\n' >> "$out"
printf 'capability_policy=full_upstream_ctest_capability_run_static_and_shared_passes_no_E_filter_no_source_patch\n' >> "$out"
printf 'registry=OFF\ncmake_export_no_package_registry=ON\nno_compiler_probe=ON\nno_network_download=ON\n' >> "$out"
]==])
        assert(ctx.exec({ "sh", probe, facts_file, ctx.build_dir, cache,
                          tostring(ctx.jobs), vdir },
                        { cwd = ctx.build_dir, log = ctx.log }) == 0,
               "gcpkg: googletest: install-task platform facts script failed")
        fs.append(facts_file, table.concat({
            "static_pass=ON",
            "shared_pass=" .. (on["shared"] and "ON" or "OFF"),
            "tests_pass=" .. (on["tests"] and "ON" or "OFF"),
            "examples_pass=" .. (on["examples"] and "ON" or "OFF"),
            "python_tests_pass=" .. (on["python-tests"] and "ON" or "OFF"),
            "pthreads_pass=" .. (on["pthreads"] and "ON" or "OFF"),
            "gmock=" .. (on["gmock"] and "ON" or "OFF"),
            "",
        }, "\n"))

        -- Source-only pkg-config: there are no dependency prefixes, so the
        -- wrapper is pinned to exactly this port's own .pc directory.  The
        -- directory does not exist until install, but the path is fixed.
        r20.restrict_pkgconfig(ctx)
        local pc_dir = util.join(ctx.prefix, "lib", "pkgconfig")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        assert(fs.isfile(wrapper),
               "gcpkg: googletest: source-only pkg-config wrapper missing")
        ctx.env.PKG_CONFIG_PATH = pc_dir
        ctx.env.PKG_CONFIG_LIBDIR = pc_dir
        ctx.env.PKG_CONFIG_EXECUTABLE = wrapper
        ctx.env.PKG_CONFIG = wrapper
        ctx.env.GCPKG_PKG_CONFIG_REAL = "/usr/bin/pkg-config"
        ctx.env.GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = util.join(ctx.prefix, "include")
        ctx.env.LD_LIBRARY_PATH = util.join(ctx.prefix, "lib") .. ":" ..
                                  ((ctx.env or {}).LD_LIBRARY_PATH or "")
        ctx.env.HOME = util.join(vdir, "home")
        ctx.env.TMPDIR = util.join(vdir, "tmp")
        ctx.env.XDG_CONFIG_HOME = util.join(vdir, "home", ".config")
        ctx.env.XDG_CACHE_HOME = util.join(vdir, "home", ".cache")
        ctx.env.XDG_DATA_HOME = util.join(vdir, "home", ".local", "share")
        gcpkg.log.info("googletest: install-task platform/service facts recorded once")
    end,
    cmake = {
        defines = function(ctx)
            return make_defines(ctx, false)
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
        local cmakedir = util.join(libdir, "cmake", "GTest")
        local pkgdir = util.join(libdir, "pkgconfig")
        local vdir = util.join(ctx.build_dir, "verify")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))
        fs.mkdirs(util.join(vdir, "obj"))

        local facts = assert(fs.read(util.join(vdir, "platform-facts.txt")),
                             "gcpkg: googletest: missing platform facts")
        local python = fact(facts, "python3_exe")
        local pkgconfig_exe = fact(facts, "pkgconfig_exe")
        assert(python ~= "" and python ~= "ABSENT",
               "gcpkg: googletest: Python3 fact missing")
        assert(pkgconfig_exe ~= "" and pkgconfig_exe ~= "ABSENT",
               "gcpkg: googletest: pkg-config fact missing")
        assert(facts:find("cache_sha=" .. CACHE_SHA, 1, true),
               "gcpkg: googletest: cached source tarball SHA mismatch")

        local tenv = util.merge(ctx.env, {
            HOME = util.join(vdir, "home"),
            TMPDIR = util.join(vdir, "tmp"),
            XDG_CONFIG_HOME = util.join(vdir, "home", ".config"),
            XDG_CACHE_HOME = util.join(vdir, "home", ".cache"),
            XDG_DATA_HOME = util.join(vdir, "home", ".local", "share"),
            LD_LIBRARY_PATH = libdir .. ":" .. ((ctx.env or {}).LD_LIBRARY_PATH or ""),
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
                   "gcpkg: googletest: capture shell failed: " .. cmd)
            return trim(assert(fs.read(rcfile),
                               "gcpkg: googletest: missing rc file")),
                   assert(fs.read(out), "gcpkg: googletest: missing output file")
        end

        local function ctest_pass(tag)
            local nlog = util.join(vdir, "ctest-" .. tag .. ".N")
            local nrc = util.join(vdir, "ctest-" .. tag .. ".N.rc")
            local nrcv = run_capture("ctest -N", nlog, nrc, tenv, ctx.build_dir)
            assert(nrcv == "0", "gcpkg: googletest: ctest -N failed for " .. tag)
            local ntext = assert(fs.read(nlog),
                                 "gcpkg: googletest: missing ctest -N log")
            local registered = tonumber(ntext:match("Total Tests: (%d+)") or "0") or 0
            assert(registered >= 45 and registered <= 63,
                   "gcpkg: googletest: unexpected registered ctest count: " .. registered)
            -- Upstream CMake registers 18 gmock C++ tests, 27 googletest C++
            -- tests and 18 googletest Python-driven tests (Total Tests: 63).
            -- googlemock's own gmock_leak_test/gmock_output_test py_test()
            -- calls are NOT registered by upstream CMake in this layout:
            -- internal_utils.cmake only calls find_package(Python3) under
            -- if(gtest_build_tests) in the googletest child scope, so
            -- Python3_Interpreter_FOUND is not set in the googlemock scope.
            -- Their helper executables are still built. Do not assert a name
            -- that upstream never registers, and do not add a source patch.
            local required_names = { "gtest_unittest", "gmock_test",
                                     "gtest_no_rtti_unittest", "gtest_skip_test" }
            if on["python-tests"] then
                required_names[#required_names + 1] = "gtest_xml_outfiles_test"
                required_names[#required_names + 1] = "gtest_help_test"
                required_names[#required_names + 1] = "googletest-json-outfiles-test"
            end
            for _, name in ipairs(required_names) do
                if not (name:find("gmock", 1, true) and not on["gmock"]) then
                    assert(ntext:find(name, 1, true),
                           "gcpkg: googletest: missing upstream ctest " .. name)
                end
            end
            local cap_log = util.join(vdir, "ctest-" .. tag .. ".log")
            local cap_rc_file = util.join(vdir, "ctest-" .. tag .. ".rc")
            local cap_rc = run_capture("ctest --output-on-failure --timeout 180",
                                       cap_log, cap_rc_file, tenv, ctx.build_dir)
            local cap = assert(fs.read(cap_log),
                               "gcpkg: googletest: missing ctest log " .. tag)
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

        -- 1) Static-pass artifacts and full upstream ctest BEFORE the shared
        -- reconfigure overwrites the CMakeCache/CTestTestfile.
        if on["library"] and on["static"] then
            for _, n in ipairs(lib_names(on)) do
                assert(fs.isfile(static_file(libdir, n)),
                       "gcpkg: googletest: missing static lib" .. n .. ".a")
            end
        end
        if on["headers"] then
            for _, h in ipairs({ "gtest/gtest.h", "gtest/gtest-assertion-result.h",
                                 "gtest/gtest-death-test.h", "gtest/gtest-matchers.h",
                                 "gtest/gtest-message.h", "gtest/gtest-param-test.h",
                                 "gtest/gtest-printers.h", "gtest/gtest-spi.h",
                                 "gtest/gtest-test-part.h", "gtest/gtest-typed-test.h",
                                 "gmock/gmock.h", "gmock/gmock-actions.h",
                                 "gmock/gmock-cardinalities.h",
                                 "gmock/gmock-function-mocker.h",
                                 "gmock/gmock-matchers.h", "gmock/gmock-more-actions.h",
                                 "gmock/gmock-more-matchers.h",
                                 "gmock/gmock-nice-strict.h",
                                 "gmock/gmock-spec-builders.h" }) do
                if not (h:find("gmock", 1, true) and not on["gmock"]) then
                    assert(fs.isfile(util.join(incdir, h)),
                           "gcpkg: googletest: missing header " .. h)
                end
            end
            local hcount = util.join(vdir, "header.count")
            assert(ctx.exec({ "sh", "-c", "find " .. incdir ..
                         " -type f 2>/dev/null | wc -l > " .. hcount },
                   { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: googletest: header count failed")
            local hc = tonumber(trim(assert(fs.read(hcount),
                             "gcpkg: googletest: missing header count"))) or 0
            assert(hc >= 40, "gcpkg: googletest: too few installed headers: " .. hc)
        end

        local static_result = nil
        if on["tests"] then
            static_result = ctest_pass("static")
        end

        -- 2) Second official upstream pass: shared libs, tests/examples/Python
        -- still ON, same isolated build dir.  Save the static compdb first.
        local static_compdb = util.join(vdir, "compile_commands.static.json")
        local shared_compdb = util.join(ctx.build_dir, "compile_commands.json")
        local merged_compdb = util.join(vdir, "compile_commands.merged.json")
        if on["shared"] then
            assert(ctx.exec({ "sh", "-c", "cp " .. shared_compdb .. " " .. static_compdb },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: googletest: cannot save static compile_commands.json")
            local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
            assert(fs.isfile(noTry),
                   "gcpkg: googletest: framework no-probe include missing")
            local cmd = {
                "cmake", "-S", ctx.src, "-B", ctx.build_dir,
                "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
                "-DCMAKE_INSTALL_PREFIX=" .. prefix,
                "-DCMAKE_PROJECT_INCLUDE=" .. noTry,
                "-DCMAKE_C_COMPILER_FORCED=TRUE",
                "-DCMAKE_C_COMPILER_WORKS=TRUE",
                "-DCMAKE_CXX_COMPILER_FORCED=TRUE",
                "-DCMAKE_CXX_COMPILER_WORKS=TRUE",
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
            }
            for _, a in ipairs(defines_to_args(make_defines(ctx, true))) do
                cmd[#cmd + 1] = a
            end
            for _, a in ipairs(ctx.feature_args()) do
                cmd[#cmd + 1] = a
            end
            cmd[#cmd + 1] = "-DBUILD_SHARED_LIBS=ON"
            assert(ctx.exec(cmd, { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: googletest: shared-pass reconfigure failed")
            assert(ctx.exec({ "cmake", "--build", ctx.build_dir,
                              "--parallel", tostring(ctx.jobs) },
                            { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: googletest: shared-pass build failed")
            assert(ctx.exec({ "cmake", "--install", ctx.build_dir, "--prefix", prefix },
                            { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: googletest: shared-pass install failed")
            local merge_py = util.join(vdir, "merge_compdb.py")
            fs.write(merge_py, [==[
import json, sys
a = json.load(open(sys.argv[1], encoding="utf-8"))
b = json.load(open(sys.argv[2], encoding="utf-8"))
json.dump(a + b, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False)
]==])
            assert(ctx.exec({ python, merge_py, static_compdb, shared_compdb,
                              merged_compdb },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: googletest: compile_commands merge failed")
            assert(ctx.exec({ "sh", "-c", "cp " .. merged_compdb .. " " .. shared_compdb },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: googletest: cannot install merged compile_commands.json")
        end

        local shared_result = nil
        if on["tests"] then
            shared_result = ctest_pass("shared")
        end

        -- 3) Facts are written BEFORE strict assertions, so a failure still
        -- leaves the authoritative measured capability result on disk.
        local function fmt_result(r)
            if not r then return "DISABLED" end
            return "registered=" .. r.registered .. " total=" .. r.total ..
                   " percent=" .. r.percent .. " rc=" .. r.rc ..
                   " failed=" .. #r.failures ..
                   " names=" .. table.concat(r.failures, ",") ..
                   " summary=" .. r.summary
        end
        local unclassified = {}
        for _, r in ipairs({ static_result, shared_result }) do
            if r then
                for _, n in ipairs(r.failures) do unclassified[#unclassified + 1] = n end
            end
        end
        fs.write(util.join(vdir, "capability-facts.txt"), table.concat({
            "policy=full_upstream_ctest_capability_run_static_and_shared_passes",
            "no_ctest_E=1",
            "no_source_patch=1",
            "no_static_test_number_blacklist=1",
            "python_tests=" .. (on["python-tests"] and "ON" or "OFF"),
            "static=" .. fmt_result(static_result),
            "shared=" .. fmt_result(shared_result),
            "unclassified_failure_lines=" .. table.concat(unclassified, ","),
            "excluded=0",
            "final_rc=" .. (shared_result and shared_result.rc or
                            (static_result and static_result.rc or "NOT_RUN")),
            "",
        }, "\n"))
        if static_result then
            assert(static_result.rc == "0" and static_result.percent == 100,
                   "gcpkg: googletest: static ctest not 100%: " .. fmt_result(static_result))
            assert(static_result.total == static_result.registered and
                   static_result.total >= 45,
                   "gcpkg: googletest: static ctest total mismatch: " .. fmt_result(static_result))
            assert(#static_result.failures == 0,
                   "gcpkg: googletest: static ctest failures: " ..
                   table.concat(static_result.failures, ","))
            assert(not static_result.log:find("The following tests FAILED", 1, true),
                   "gcpkg: googletest: static ctest reported failed tests")
        end
        if shared_result then
            assert(shared_result.rc == "0" and shared_result.percent == 100,
                   "gcpkg: googletest: shared ctest not 100%: " .. fmt_result(shared_result))
            assert(shared_result.total == shared_result.registered and
                   shared_result.total >= 45,
                   "gcpkg: googletest: shared ctest total mismatch: " .. fmt_result(shared_result))
            assert(#shared_result.failures == 0,
                   "gcpkg: googletest: shared ctest failures: " ..
                   table.concat(shared_result.failures, ","))
            assert(not shared_result.log:find("The following tests FAILED", 1, true),
                   "gcpkg: googletest: shared ctest reported failed tests")
        end
        assert(#unclassified == 0,
               "gcpkg: googletest: unclassified ctest failures: " ..
               table.concat(unclassified, ","))

        -- 4) Shared artifacts, examples, upstream .pc files and upstream
        -- GTest CMake CONFIG package (checked after the final install).
        if on["library"] and on["shared"] then
            for _, n in ipairs(lib_names(on)) do
                assert(shared_file(libdir, n),
                       "gcpkg: googletest: missing shared lib" .. n .. ".so")
            end
        end
        if on["examples"] then
            local slist = util.join(vdir, "sample-list.txt")
            assert(ctx.exec({ "sh", "-c", "find " .. ctx.build_dir ..
                         " -type f -name 'sample*_unittest' -perm -u+x | sort > " .. slist },
                   { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: googletest: sample discovery failed")
            local samples = util.lines(assert(fs.read(slist),
                             "gcpkg: googletest: missing sample list"))
            assert(#samples == 10,
                   "gcpkg: googletest: expected 10 upstream samples, got " .. #samples)
            for i, bin in ipairs(samples) do
                local out = util.join(vdir, "sample-" .. i .. ".out")
                local rcf = util.join(vdir, "sample-" .. i .. ".rc")
                local rc = run_capture(bin, out, rcf, tenv, ctx.build_dir)
                assert(rc == "0",
                       "gcpkg: googletest: sample " .. i .. " failed")
                local text = assert(fs.read(out),
                       "gcpkg: googletest: missing sample output")
                assert(text:find("[  PASSED  ]", 1, true),
                       "gcpkg: googletest: sample " .. i .. " did not report PASSED")
            end
        end
        if on["pkgconfig"] then
            for _, pc in ipairs({ "gtest.pc", "gtest_main.pc",
                                  "gmock.pc", "gmock_main.pc" }) do
                if not (pc:find("gmock", 1, true) and not on["gmock"]) then
                    assert(fs.isfile(util.join(pkgdir, pc)),
                           "gcpkg: googletest: missing upstream .pc " .. pc)
                end
            end
            local gpc = assert(fs.read(util.join(pkgdir, "gtest.pc")),
                               "gcpkg: googletest: cannot read gtest.pc")
            assert(gpc:find("Version: " .. VERSION, 1, true),
                   "gcpkg: googletest: gtest.pc version mismatch")
            assert(gpc:find("libdir=" .. libdir, 1, true) and
                   gpc:find("includedir=" .. incdir, 1, true),
                   "gcpkg: googletest: gtest.pc does not pin the source-port prefix")
            assert(not gpc:find("/usr/local", 1, true),
                   "gcpkg: googletest: gtest.pc leaked a host prefix")
            if on["pthreads"] then
                assert(gpc:find("-DGTEST_HAS_PTHREAD=1", 1, true),
                       "gcpkg: googletest: gtest.pc lost pthread cflags")
            end
            local pcmod = util.join(vdir, "pkgconfig-modversion.out")
            local pcrc = util.join(vdir, "pkgconfig-modversion.rc")
            local prc, pout = run_capture('"' .. wrapper .. '" --modversion gtest',
                                          pcmod, pcrc, tenv)
            assert(prc == "0" and trim(pout) == VERSION,
                   "gcpkg: googletest: pkg-config --modversion failed: " .. pout)
            local pcflags = util.join(vdir, "pkgconfig-flags.out")
            local pcfrc = util.join(vdir, "pkgconfig-flags.rc")
            local frc, fout = run_capture('"' .. wrapper ..
                                          '" --cflags --libs gtest gmock',
                                          pcflags, pcfrc, tenv)
            assert(frc == "0" and fout:find("-I" .. incdir, 1, true) and
                   fout:find("-L" .. libdir, 1, true),
                   "gcpkg: googletest: pkg-config flags do not use the source-port prefix")
        end
        if on["cmake-package"] then
            for _, f in ipairs({ "GTestConfig.cmake", "GTestConfigVersion.cmake",
                                 "GTestTargets.cmake" }) do
                assert(fs.isfile(util.join(cmakedir, f)),
                       "gcpkg: googletest: missing upstream CMake package file " .. f)
            end
            assert(fs.isfile(util.join(cmakedir, "GTestTargets-release.cmake")) or
                   fs.isfile(util.join(cmakedir, "GTestTargets-noconfig.cmake")),
                   "gcpkg: googletest: missing upstream GTestTargets config file")
            local cfg = assert(fs.read(util.join(cmakedir, "GTestConfig.cmake")),
                               "gcpkg: googletest: cannot read GTestConfig.cmake")
            assert(cfg:find("include(CMakeFindDependencyMacro)", 1, true),
                   "gcpkg: googletest: GTestConfig.cmake is not upstream")
            if on["pthreads"] then
                assert(cfg:find("find_dependency(Threads)", 1, true),
                       "gcpkg: googletest: GTestConfig.cmake lost Threads dependency")
            end
            local ver = assert(fs.read(util.join(cmakedir, "GTestConfigVersion.cmake")),
                               "gcpkg: googletest: cannot read GTestConfigVersion.cmake")
            assert(ver:find('"' .. VERSION .. '"', 1, true),
                   "gcpkg: googletest: GTestConfigVersion.cmake version mismatch")
            local targets = assert(fs.read(util.join(cmakedir, "GTestTargets.cmake")),
                                   "gcpkg: googletest: cannot read GTestTargets.cmake")
            for _, t in ipairs({ "GTest::gtest", "GTest::gtest_main",
                                 "GTest::gmock", "GTest::gmock_main" }) do
                if not (t:find("gmock", 1, true) and not on["gmock"]) then
                    assert(targets:find(t, 1, true),
                           "gcpkg: googletest: missing exported target " .. t)
                end
            end
            assert(not fs.isfile(util.join(cmakedir, "GTestConfig.cmake.gcpkg")),
                   "gcpkg: googletest: hand-written CONFIG file is forbidden")
        end

        -- 5) Independent consumers: FindPkgConfig, upstream CONFIG, CMake
        -- MODULE FindGTest, plus direct static/shared C++ sanity programs.
        local consumer_cpp = [==[
#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
TEST(Gcpkg, Works) { EXPECT_THAT(1, testing::Eq(1)); }
int main(int argc, char **argv) {
  testing::InitGoogleTest(&argc, argv);
  testing::InitGoogleMock(&argc, argv);
  int rc = RUN_ALL_TESTS();
  if (rc == 0) printf("gcpkg googletest consumer ok: %s %s\n", CONSUMER_KIND, XSTR(GCPKG_GTEST_VERSION));
  return rc;
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
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                "-DCMAKE_PREFIX_PATH=" .. prefix,
                "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
            }
            for _, d in ipairs(defines) do cmd[#cmd + 1] = d end
            assert(ctx.exec(cmd, { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: googletest: " .. kind .. " consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", bdir,
                              "--parallel", "4" },
                            { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: googletest: " .. kind .. " consumer build failed")
            local out = util.join(dir, "run.out")
            local rcf = util.join(dir, "run.rc")
            local rc = run_capture(util.join(bdir, "consumer"), out, rcf, tenv, dir)
            assert(rc == "0", "gcpkg: googletest: " .. kind ..
                   " consumer run failed")
            local text = assert(fs.read(out),
                   "gcpkg: googletest: missing " .. kind .. " consumer output")
            assert(text:find("gcpkg googletest consumer ok: " .. kind ..
                             " " .. VERSION, 1, true),
                   "gcpkg: googletest: " .. kind ..
                   " consumer did not use installed " .. VERSION)
        end

        if on["consumers"] then
            assert(on["library"] and on["headers"] and on["gmock"] and
                   on["cmake-package"] and on["pkgconfig"],
                   "gcpkg: googletest: consumers need library, headers, gmock, cmake-package and pkgconfig")
            local gtest_so = assert(shared_file(libdir, "gtest"),
                                    "gcpkg: googletest: missing shared libgtest.so")
            local gtest_main_so = assert(shared_file(libdir, "gtest_main"),
                                         "gcpkg: googletest: missing shared libgtest_main.so")
            local gmock_so = assert(shared_file(libdir, "gmock"),
                                    "gcpkg: googletest: missing shared libgmock.so")
            local gmock_main_so = assert(shared_file(libdir, "gmock_main"),
                                         "gcpkg: googletest: missing shared libgmock_main.so")
            cmake_consumer("CONFIG", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_googletest_config_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 14)
find_package(GTest 1.15.2 CONFIG REQUIRED)
add_executable(consumer main.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=\"CONFIG\" GCPKG_GTEST_VERSION=1.15.2 GTEST_LINKED_AS_SHARED_LIBRARY=1)
target_link_libraries(consumer PRIVATE GTest::gtest GTest::gmock)
]==], { "-DGTest_DIR=" .. cmakedir })
            cmake_consumer("MODULE", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_googletest_module_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 14)
find_package(GTest REQUIRED MODULE)
add_executable(consumer main.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=\"MODULE\" GCPKG_GTEST_VERSION=1.15.2 GTEST_LINKED_AS_SHARED_LIBRARY=1)
target_link_libraries(consumer PRIVATE GTest::gtest GTest::gmock)
]==], {
                "-DGTEST_ROOT=" .. prefix,
                "-DGTEST_INCLUDE_DIR=" .. incdir,
                "-DGTEST_LIBRARY=" .. gtest_so,
                "-DGTEST_MAIN_LIBRARY=" .. gtest_main_so,
                "-DGMOCK_LIBRARY=" .. gmock_so,
                "-DGMOCK_MAIN_LIBRARY=" .. gmock_main_so,
            })
            cmake_consumer("FindPkgConfig", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_googletest_pkgconfig_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 14)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GCPKG_GTEST REQUIRED IMPORTED_TARGET gtest gmock)
add_executable(consumer main.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=\"FindPkgConfig\" GCPKG_GTEST_VERSION=1.15.2 GTEST_LINKED_AS_SHARED_LIBRARY=1)
target_include_directories(consumer PRIVATE ${GCPKG_GTEST_INCLUDE_DIRS})
target_compile_options(consumer PRIVATE ${GCPKG_GTEST_CFLAGS_OTHER})
target_link_libraries(consumer PRIVATE PkgConfig::GCPKG_GTEST)
]==], { "-DPKG_CONFIG_EXECUTABLE=" .. wrapper })
        end

        if on["sanity"] then
            assert(on["library"] and on["headers"] and on["gmock"],
                   "gcpkg: googletest: sanity needs library, headers and gmock")
            local function sanity_src(kind)
                return [==[
#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
TEST(Gcpkg, Works) { EXPECT_THAT(1, testing::Eq(1)); }
int main(int argc, char **argv) {
  testing::InitGoogleTest(&argc, argv);
  testing::InitGoogleMock(&argc, argv);
  int rc = RUN_ALL_TESTS();
  if (rc == 0) printf("gcpkg googletest ]==] .. kind .. [==[ ok: %s\n", XSTR(GCPKG_GTEST_VERSION));
  return rc;
}
]==]
            end
            local function direct_sanity(kind, bin_name, extra_flags, libs)
                local src = util.join(vdir, "gtest_" .. kind .. "_sanity.cpp")
                fs.write(src, sanity_src(kind))
                local bin = cc.executable {
                    sources = { src },
                    includes = { incdir },
                    defines = { "GCPKG_GTEST_VERSION=" .. VERSION },
                    flags = extra_flags,
                    cwd = vdir,
                    outdir = util.join(vdir, "obj"),
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "googletest", cxx = true,
                    output = util.join(vdir, bin_name),
                    libdirs = { libdir },
                    libs = libs,
                }
                local out = util.join(vdir, "sanity-" .. kind .. ".out")
                local rcf = util.join(vdir, "sanity-" .. kind .. ".rc")
                local rc = run_capture(bin, out, rcf, tenv, vdir)
                assert(rc == "0",
                       "gcpkg: googletest: " .. kind .. " sanity consumer failed")
                local text = assert(fs.read(out),
                       "gcpkg: googletest: missing " .. kind .. " sanity output")
                assert(text:find("gcpkg googletest " .. kind .. " ok: " .. VERSION, 1, true),
                       "gcpkg: googletest: " .. kind ..
                       " sanity did not link the installed " .. VERSION)
            end
            if on["static"] then
                direct_sanity("static", "gtest_static_consumer", {
                    "-std=c++14", "-pthread",
                    "-l:libgtest.a", "-l:libgmock.a",
                }, {})
            end
            if on["shared"] then
                direct_sanity("shared", "gtest_shared_consumer", {
                    "-std=c++14", "-pthread",
                    "-DGTEST_LINKED_AS_SHARED_LIBRARY=1",
                }, { "gtest", "gmock" })
            end
        end

        fs.write(util.join(vdir, "no-homemade-config.txt"),
                 "NO_HOMEMADE_CONFIG=YES\nUPSTREAM_GTEST_CONFIG=YES\n")
        gcpkg.log.info("googletest: post_install checks complete")
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "gtest", "gmock", "gtest_main", "gmock_main" },
        binaries = {},
    },
}
