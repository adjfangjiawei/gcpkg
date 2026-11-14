-- fmt 11.2.0 -- R20 new-standard port definition.
-- Two official upstream configure/build/install passes give static AND shared
-- libraries without overriding spec.build.  The full upstream ctest suite runs
-- in both final passes.  A CMAKE_PROJECT_INCLUDE shim chain-loads gcpkg's
-- no-probe include, finds the source-built googletest CONFIG, and replaces
-- fmt's bundled gtest add_subdirectory(gtest) with the source-port targets.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "11.2.0"
local CACHE_NAME = "fmt-11.2.0-11.2.0"
local CACHE_SHA = "bc23066d87ab3168f27cef3e97d545fa63314f5c79df5ea444d41d56f962c6af"

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

local function make_defines(ctx, shared)
    assert(type(shared) == "boolean",
           "gcpkg: fmt: make_defines needs a boolean shared flag")
    local on = ctx.features.enabled
    local facts_path = util.join(ctx.build_dir, "verify", "platform-facts.txt")
    local facts = assert(fs.read(facts_path),
                         "gcpkg: fmt: missing install-task platform facts")
    local doxygen = fact(facts, "doxygen_exe")
    assert(doxygen ~= "" and doxygen ~= "ABSENT",
           "gcpkg: fmt: Doxygen host-tool fact missing")
    local gtest = ctx.dep("googletest")
    if on["tests"] then
        assert(gtest and gtest.prefix,
               "gcpkg: fmt: tests need source-built googletest")
    end
    local py = ctx.dep("python")
    if on["compdb"] then
        assert(py and py.prefix,
               "gcpkg: fmt: compdb needs source-built python")
    end
    local gtest_prefix = gtest and gtest.prefix or ""
    local gtest_libdir = gtest and ((gtest.libdirs or {})[1] or
                          util.join(gtest_prefix, "lib")) or ""
    local prefixes = { ctx.prefix }
    for _, p in ipairs(util.split(r20.all_cmake_prefix(ctx), ";")) do
        if p ~= "" then prefixes[#prefixes + 1] = p end
    end
    prefixes = util.uniq(prefixes)
    local shim = util.join(ctx.build_dir, "gcpkg-fmt-source-gtest.cmake")
    local d = {
        CMAKE_BUILD_TYPE = "Release",
        CMAKE_CXX_STANDARD = "17",
        CMAKE_INSTALL_LIBDIR = "lib",
        CMAKE_INSTALL_INCLUDEDIR = "include",
        CMAKE_INSTALL_DOCDIR = "share/doc/fmt",
        CMAKE_PROJECT_INCLUDE = shim,
        CMAKE_MAKE_PROGRAM = "/usr/bin/make",
        CMAKE_POLICY_VERSION_MINIMUM = "3.5",
        CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
        CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
        CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
        CMAKE_DISABLE_FIND_PACKAGE_Git = "ON",
        GIT_EXECUTABLE = "",
        CMAKE_PREFIX_PATH = table.concat(prefixes, ";"),
        GTest_DIR = gtest_libdir ~= "" and util.join(gtest_libdir, "cmake", "GTest") or "",
        DOXYGEN = doxygen,
        MKDOCS = "",
        HAVE_STRPTIME = "TRUE",
        HAS_NULLPTR_WARNING = "TRUE",
        HAVE_FNO_EXCEPTIONS_FLAG = "TRUE",
        compile_result_unused = "TRUE",
        BUILD_SHARED_LIBS = shared and "ON" or "OFF",
        FMT_TEST = on["tests"] and "ON" or "OFF",
        FMT_DOC = on["docs"] and "ON" or "OFF",
        FMT_INSTALL = on["library"] and "ON" or "OFF",
        FMT_FUZZ = "OFF",
        FMT_PEDANTIC = on["pedantic"] and "ON" or "OFF",
        FMT_WERROR = "OFF",
        FMT_CUDA_TEST = "OFF",
        FMT_MODULE = "OFF",
        FMT_OS = on["os"] and "ON" or "OFF",
        FMT_UNICODE = on["unicode"] and "ON" or "OFF",
        FMT_SYSTEM_HEADERS = "OFF",
    }
    return d
end

return recipe.cmake {
    name = "fmt",
    version = VERSION,
    description = "fmt 11.2.0: static+shared, full ctest, source-built googletest, upstream CONFIG/pkgconfig/consumers",
    license = "MIT",
    homepage = "https://fmt.dev",
    source = {
        url = "https://codeload.github.com/fmtlib/fmt/tar.gz/refs/tags/11.2.0",
        sha256 = CACHE_SHA,
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        local on = ctx.features.enabled
        assert(on["static"] or on["shared"],
               "gcpkg: fmt: at least one of static/shared must be enabled")
        assert(on["library"], "gcpkg: fmt: library feature is required")
        fs.mkdirs(ctx.build_dir)
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))
        fs.mkdirs(util.join(vdir, "obj"))
        fs.mkdirs(util.join(vdir, "consumers"))

        local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
        local shim = util.join(ctx.build_dir, "gcpkg-fmt-source-gtest.cmake")
        local source_gtest_block = ""
        if on["tests"] then
            source_gtest_block = [==[
find_package(GTest CONFIG REQUIRED)
if(NOT TARGET gtest)
  add_library(gtest INTERFACE)
  target_link_libraries(gtest INTERFACE GTest::gtest GTest::gmock)
  target_compile_definitions(gtest INTERFACE GTEST_HAS_STD_WSTRING=1)
endif()
function(add_subdirectory dir)
  if("${dir}" STREQUAL "gtest" AND TARGET gtest)
    return()
  endif()
  _add_subdirectory(${dir} ${ARGN})
endfunction()
]==]
        end
        local shim_text = [==[
# Chain the framework no-probe include first; CMAKE_PROJECT_INCLUDE runs after project().
include("@@NOTRY@@")
]==] .. source_gtest_block
        fs.write(shim, (shim_text:gsub("@@NOTRY@@", function() return noTry end)))

        local facts_file = util.join(vdir, "platform-facts.txt")
        local probe = util.join(vdir, "platform-facts.sh")
        local cache = util.join(ctx.store.cache, CACHE_NAME)
        local gtest = ctx.dep("googletest")
        local py = ctx.dep("python")
        local gtest_prefix = gtest and gtest.prefix or "ABSENT"
        local python_prefix = py and py.prefix or "ABSENT"
        local source_python = py and util.join(py.prefix, "bin", "python3") or "ABSENT"
        local dep_count = 0
        if on["tests"] then dep_count = dep_count + 1 end
        if on["compdb"] then dep_count = dep_count + 1 end
        fs.write(probe, [==[
set -u
out="$1"; root="$2"; cache="$3"; jobs="$4"; vdir="$5"; src="$6"; cxxreal="$7"; gtest_prefix="$8"; python_prefix="$9"; source_python="${10}"; dep_count="${11}"
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
doxygen_exe="$(command -v doxygen || echo ABSENT)"
doxygen_version="$(doxygen --version 2>/dev/null | head -1 || echo ABSENT)"
mkdocs_exe="$(command -v mkdocs || echo ABSENT)"
if [ "$source_python" != ABSENT ] && [ -x "$source_python" ]; then
  if "$source_python" -c 'import mkdocs' > /dev/null 2>&1; then
    source_python_mkdocs=PRESENT
  else
    source_python_mkdocs=ABSENT
  fi
else
  source_python_mkdocs=ABSENT
fi
cxx_exe="$(command -v c++ || echo ABSENT)"
cxx_real_version="$("$cxxreal" --version 2>/dev/null | head -1 || echo ABSENT)"
cache_sha="$(sha256sum "$cache" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)"
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\nfs_type=%s\nwsl=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" "$fs_type" "$wsl" > "$out"
printf 'jobs=%s\nhome=%s\ntmp=%s\n' "$jobs" "$vdir/home" "$vdir/tmp" >> "$out"
printf 'python3_exe=%s\npython3_version=%s\ncmake_exe=%s\ncmake_version=%s\nctest_exe=%s\nctest_version=%s\n' \
  "$python3_exe" "$python3_version" "$cmake_exe" "$cmake_version" "$ctest_exe" "$ctest_version" >> "$out"
printf 'pkgconfig_exe=%s\ndoxygen_exe=%s\ndoxygen_version=%s\nmkdocs_exe=%s\nsource_python_mkdocs=%s\ncxx_exe=%s\ncxx_real_version=%s\n' \
  "$pkgconfig_exe" "$doxygen_exe" "$doxygen_version" "$mkdocs_exe" "$source_python_mkdocs" "$cxx_exe" "$cxx_real_version" >> "$out"
printf 'cache_name=%s\ncache_sha=%s\n' "$cache" "$cache_sha" >> "$out"
printf 'source_port_deps=%s\ndynamic_requires=%s\n' "$dep_count" "$dep_count" >> "$out"
printf 'gtest_prefix=%s\npython_prefix=%s\nsource_python=%s\n' "$gtest_prefix" "$python_prefix" "$source_python" >> "$out"
printf 'doxygen=%s\nmkdocs=ABSENT reason=source_port_not_r20_reaudited_no_wheel_cache\n' "$doxygen_exe" >> "$out"
printf 'doc_target=OFF reason=upstream_find_program_mkdocs_absent\n' >> "$out"
printf 'installed_docs=upstream_source_markdown\n' >> "$out"
printf 'fuzz=OFF\n' >> "$out"
printf 'fuzz_reason=fuzzing_engine_not_r20_reaudited_source_port\n' >> "$out"
printf 'module=OFF cuda=OFF werror=OFF system_headers=OFF reason=toolchain_modes_outside_source_port_audit\n' >> "$out"
printf 'capability_policy=full_upstream_ctest_both_passes_source_built_googletest_no_source_patch_no_ctest_E\n' >> "$out"
printf 'registry=OFF\nno_compiler_probe=ON\nno_network_download=ON\n' >> "$out"
]==])
        assert(ctx.exec({ "sh", probe, facts_file, ctx.build_dir, cache,
                          tostring(ctx.jobs), vdir, ctx.src,
                          ctx.compiler.cxx, gtest_prefix, python_prefix,
                          source_python, tostring(dep_count) },
                        { cwd = ctx.build_dir, log = ctx.log }) == 0,
               "gcpkg: fmt: install-task platform facts script failed")
        local initial_pass = on["static"] and "static" or "shared"
        fs.append(facts_file, table.concat({
            "initial_pass=" .. initial_pass,
            "static_pass=" .. (on["static"] and "ON" or "OFF"),
            "shared_pass=" .. (on["shared"] and "ON" or "OFF"),
            "tests_pass=" .. (on["tests"] and "ON" or "OFF"),
            "pedantic_pass=" .. (on["pedantic"] and "ON" or "OFF"),
            "docs_pass=" .. (on["docs"] and "ON" or "OFF"),
            "compdb_pass=" .. (on["compdb"] and "ON" or "OFF"),
            "consumers_pass=" .. (on["consumers"] and "ON" or "OFF"),
            "sanity_pass=" .. (on["sanity"] and "ON" or "OFF"),
            "",
        }, "\n"))

        r20.restrict_pkgconfig(ctx)
        local pc_dir = util.join(ctx.prefix, "lib", "pkgconfig")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        assert(fs.isfile(wrapper),
               "gcpkg: fmt: source-only pkg-config wrapper missing")
        ctx.env.PKG_CONFIG_PATH = pc_dir
        ctx.env.PKG_CONFIG_LIBDIR = pc_dir
        ctx.env.PKG_CONFIG_EXECUTABLE = wrapper
        ctx.env.PKG_CONFIG = wrapper
        ctx.env.GCPKG_PKG_CONFIG_REAL = "/usr/bin/pkg-config"
        ctx.env.GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = util.join(ctx.prefix, "include")
        ctx.env.HOME = util.join(vdir, "home")
        ctx.env.TMPDIR = util.join(vdir, "tmp")
        ctx.env.XDG_CONFIG_HOME = util.join(vdir, "home", ".config")
        ctx.env.XDG_CACHE_HOME = util.join(vdir, "home", ".cache")
        ctx.env.XDG_DATA_HOME = util.join(vdir, "home", ".local", "share")
        ctx.env.CTEST_OUTPUT_ON_FAILURE = "1"
        local gtest_libdir = gtest and ((gtest.libdirs or {})[1] or
                              util.join(gtest_prefix, "lib")) or ""
        ctx.env.LD_LIBRARY_PATH = util.join(ctx.prefix, "lib") .. ":" ..
                                  (gtest_libdir ~= "" and gtest_libdir .. ":" or "") ..
                                  ((ctx.env or {}).LD_LIBRARY_PATH or "")
        gcpkg.log.info("fmt: install-task platform/service facts recorded once")
    end,
    cmake = {
        defines = function(ctx)
            local on = ctx.features.enabled
            assert(on["static"] or on["shared"],
                   "gcpkg: fmt: at least one of static/shared must be enabled")
            local initial_shared = not on["static"] and on["shared"]
            return make_defines(ctx, initial_shared)
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
        local cmakedir = util.join(libdir, "cmake", "fmt")
        local pkgdir = util.join(libdir, "pkgconfig")
        local docdir = util.join(prefix, "share", "doc", "fmt")
        local vdir = util.join(ctx.build_dir, "verify")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
        local shim = util.join(ctx.build_dir, "gcpkg-fmt-source-gtest.cmake")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))
        fs.mkdirs(util.join(vdir, "obj"))
        fs.mkdirs(util.join(vdir, "consumers"))

        local facts = assert(fs.read(util.join(vdir, "platform-facts.txt")),
                             "gcpkg: fmt: missing platform facts")
        local port_log = assert(fs.read(ctx.log),
                                "gcpkg: fmt: missing port build log")
        assert(facts:find("cache_sha=" .. CACHE_SHA, 1, true),
               "gcpkg: fmt: cached source tarball SHA mismatch")
        local doxygen = fact(facts, "doxygen_exe")
        local mkdocs = fact(facts, "mkdocs_exe")
        local source_mkdocs = fact(facts, "source_python_mkdocs")
        assert(doxygen ~= "" and doxygen ~= "ABSENT",
               "gcpkg: fmt: Doxygen host-tool fact missing")
        assert(mkdocs == "ABSENT",
               "gcpkg: fmt: mkdocs unexpectedly present on host")
        assert(source_mkdocs == "ABSENT",
               "gcpkg: fmt: mkdocs unexpectedly present in source-built Python")
        assert(fact(facts, "no_network_download") == "ON",
               "gcpkg: fmt: no-network-download fact missing")
        assert(fact(facts, "no_compiler_probe") == "ON",
               "gcpkg: fmt: no-compiler-probe fact missing")
        assert(fact(facts, "registry") == "OFF",
               "gcpkg: fmt: registry isolation fact missing")
        assert(fact(facts, "fuzz") == "OFF",
               "gcpkg: fmt: fuzz boundary fact missing")
        assert(fs.isfile(noTry),
               "gcpkg: fmt: framework no-probe include missing")
        assert(fs.isfile(shim),
               "gcpkg: fmt: source-googletest shim missing")
        local shim_text = assert(fs.read(shim),
                                 "gcpkg: fmt: cannot read source-googletest shim")
        assert(shim_text:find("include(\"" .. noTry .. "\")", 1, true),
               "gcpkg: fmt: shim does not chain-load the no-probe include")
        if on["tests"] then
            assert(shim_text:find("find_package(GTest CONFIG REQUIRED)", 1, true) and
                   shim_text:find("GTest::gtest", 1, true),
                   "gcpkg: fmt: shim does not use source-built googletest")
            assert(not port_log:find("gmock-gtest-all.cc", 1, true) and
                   not port_log:find("gtest-all.cc", 1, true),
                   "gcpkg: fmt: bundled googletest sources were compiled")
        else
            assert(not shim_text:find("find_package(GTest CONFIG REQUIRED)", 1, true),
                   "gcpkg: fmt: shim requires googletest although tests are OFF")
        end
        if on["docs"] then
            assert(port_log:find("Target 'doc' disabled because mkdocs not found", 1, true),
                   "gcpkg: fmt: upstream doc gate did not report absent mkdocs")
        end
        assert(not port_log:find("ctest -E", 1, true),
               "gcpkg: fmt: ctest -E exclusion is forbidden")
        assert(not port_log:find("file(DOWNLOAD", 1, true) and
               not port_log:find("Downloading", 1, true),
               "gcpkg: fmt: configure-time network download detected")

        local gtest = ctx.dep("googletest")
        local gtest_libdir = gtest and ((gtest.libdirs or {})[1] or
                              util.join(gtest.prefix, "lib")) or ""
        local py = ctx.dep("python")
        local source_python = nil
        if on["compdb"] then
            assert(py and py.prefix,
                   "gcpkg: fmt: compdb needs source-built python")
            source_python = util.join(py.prefix, "bin", "python3")
            assert(fs.isfile(source_python),
                   "gcpkg: fmt: source-built python executable missing")
        end
        local tenv = util.merge(ctx.env, {
            HOME = util.join(vdir, "home"),
            TMPDIR = util.join(vdir, "tmp"),
            XDG_CONFIG_HOME = util.join(vdir, "home", ".config"),
            XDG_CACHE_HOME = util.join(vdir, "home", ".cache"),
            XDG_DATA_HOME = util.join(vdir, "home", ".local", "share"),
            LD_LIBRARY_PATH = libdir .. ":" ..
                              (gtest_libdir ~= "" and gtest_libdir .. ":" or "") ..
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
                   "gcpkg: fmt: capture shell failed: " .. cmd)
            return trim(assert(fs.read(rcfile),
                               "gcpkg: fmt: missing rc file")),
                   assert(fs.read(out), "gcpkg: fmt: missing output file")
        end

        local expected_registered = on["pedantic"] and 25 or 21
        local function ctest_pass(tag)
            local nlog = util.join(vdir, "ctest-" .. tag .. ".N")
            local nrc = util.join(vdir, "ctest-" .. tag .. ".N.rc")
            local nrcv = run_capture("ctest -N", nlog, nrc, tenv, ctx.build_dir)
            assert(nrcv == "0", "gcpkg: fmt: ctest -N failed for " .. tag)
            local ntext = assert(fs.read(nlog),
                                 "gcpkg: fmt: missing ctest -N log")
            local registered = tonumber(ntext:match("Total Tests: (%d+)") or "0") or 0
            assert(registered == expected_registered,
                   "gcpkg: fmt: unexpected registered ctest count " .. registered ..
                   " for " .. tag)
            local cap_log = util.join(vdir, "ctest-" .. tag .. ".log")
            local cap_rc_file = util.join(vdir, "ctest-" .. tag .. ".rc")
            local cap_rc = run_capture("ctest --output-on-failure --timeout 180",
                                       cap_log, cap_rc_file, tenv, ctx.build_dir)
            local cap = assert(fs.read(cap_log),
                               "gcpkg: fmt: missing ctest log " .. tag)
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
        local function fmt_result(r)
            if not r then return "DISABLED" end
            return "registered=" .. r.registered .. " total=" .. r.total ..
                   " percent=" .. r.percent .. " rc=" .. r.rc ..
                   " failed=" .. #r.failures ..
                   " names=" .. table.concat(r.failures, ",") ..
                   " summary=" .. r.summary
        end
        local function assert_full(r, label)
            if not r then return end
            assert(r.rc == "0" and r.percent == 100,
                   "gcpkg: fmt: " .. label .. " ctest not 100%: " .. fmt_result(r))
            assert(r.total == r.registered and r.registered == expected_registered,
                   "gcpkg: fmt: " .. label .. " ctest total mismatch: " .. fmt_result(r))
            assert(#r.failures == 0,
                   "gcpkg: fmt: " .. label .. " ctest failures: " ..
                   table.concat(r.failures, ","))
            assert(not r.log:find("The following tests FAILED", 1, true),
                   "gcpkg: fmt: " .. label .. " ctest reported failed tests")
        end

        local function save_compdb(tag)
            local src = util.join(ctx.build_dir, "compile_commands.json")
            local dst = util.join(vdir, "compile_commands." .. tag .. ".json")
            assert(ctx.exec({ "sh", "-c", "cp '" .. src .. "' '" .. dst .. "'" },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: fmt: cannot save " .. tag .. " compile_commands.json")
            return dst
        end
        local function reconfigure(tag, shared)
            local cmd = {
                "cmake", "-S", ctx.src, "-B", ctx.build_dir,
                "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
                "-DCMAKE_INSTALL_PREFIX=" .. prefix,
                "-DCMAKE_CXX_COMPILER=" .. ctx.compiler.wrapper_cxx,
                "-DCMAKE_CXX_COMPILER_FORCED=TRUE",
                "-DCMAKE_CXX_COMPILER_WORKS=TRUE",
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                "-DCMAKE_MAKE_PROGRAM=/usr/bin/make",
            }
            for _, a in ipairs(defines_to_args(make_defines(ctx, shared))) do
                cmd[#cmd + 1] = a
            end
            for _, a in ipairs(ctx.feature_args()) do cmd[#cmd + 1] = a end
            assert(ctx.exec(cmd, { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: fmt: " .. tag .. " reconfigure failed")
            assert(ctx.exec({ "cmake", "--build", ctx.build_dir,
                              "--parallel", tostring(ctx.jobs) },
                            { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: fmt: " .. tag .. " build failed")
            assert(ctx.exec({ "cmake", "--install", ctx.build_dir },
                            { cwd = ctx.src, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: fmt: " .. tag .. " install failed")
        end

        local initial_tag = on["static"] and "static" or "shared"
        local initial_shared = not on["static"] and on["shared"]
        local static_result, shared_result
        local static_compdb, shared_compdb
        if initial_tag == "static" then
            static_compdb = save_compdb("static")
            if on["tests"] then static_result = ctest_pass("static") end
        else
            shared_compdb = save_compdb("shared")
            if on["tests"] then shared_result = ctest_pass("shared") end
        end
        if on["static"] and on["shared"] then
            local other_tag = initial_tag == "static" and "shared" or "static"
            local other_shared = other_tag == "shared"
            reconfigure(other_tag, other_shared)
            if other_tag == "static" then
                static_compdb = save_compdb("static")
                if on["tests"] then static_result = ctest_pass("static") end
            else
                shared_compdb = save_compdb("shared")
                if on["tests"] then shared_result = ctest_pass("shared") end
            end
        end
        assert_full(static_result, "static")
        assert_full(shared_result, "shared")

        local compdb_inputs = {}
        if static_compdb then compdb_inputs[#compdb_inputs + 1] = static_compdb end
        if shared_compdb then compdb_inputs[#compdb_inputs + 1] = shared_compdb end
        local compdb_facts = { input_count = #compdb_inputs, total = 0,
                               gtest_entries = 0, bundled = 0 }
        if on["compdb"] and #compdb_inputs > 0 then
            local merged_compdb = util.join(vdir, "compile_commands.merged.json")
            local merged_py = util.join(vdir, "merge_compdb.py")
            fs.write(merged_py, [==[
import json, sys
paths = sys.argv[1:-1]
out = sys.argv[-1]
entries = []
for p in paths:
    entries += json.load(open(p, encoding="utf-8"))
json.dump(entries, open(out, "w", encoding="utf-8"), ensure_ascii=False)
gtest_entries = sum(1 for e in entries if "googletest" in e["command"])
bundled = sum(1 for e in entries if "gmock-gtest-all.cc" in e["file"] or "gtest-all.cc" in e["file"])
print("INPUT_COUNT=%d" % len(paths))
print("TOTAL_ENTRIES=%d" % len(entries))
print("GTEST_INCLUDE_ENTRIES=%d" % gtest_entries)
print("BUNDLED_GTEST_SOURCES=%d" % bundled)
]==])
            local args = { "'" .. source_python .. "'", "'" .. merged_py .. "'" }
            for _, p in ipairs(compdb_inputs) do args[#args + 1] = "'" .. p .. "'" end
            args[#args + 1] = "'" .. merged_compdb .. "'"
            local merge_cmd = table.concat(args, " ")
            local merge_out = util.join(vdir, "compdb-merge.out")
            local merge_rc_file = util.join(vdir, "compdb-merge.rc")
            local merge_rc, merge_text = run_capture(merge_cmd, merge_out,
                                                     merge_rc_file, tenv)
            assert(merge_rc == "0",
                   "gcpkg: fmt: source-built Python compdb merge failed")
            compdb_facts.input_count = tonumber(fact(merge_text, "INPUT_COUNT")) or 0
            compdb_facts.total = tonumber(fact(merge_text, "TOTAL_ENTRIES")) or 0
            compdb_facts.gtest_entries = tonumber(fact(merge_text, "GTEST_INCLUDE_ENTRIES")) or 0
            compdb_facts.bundled = tonumber(fact(merge_text, "BUNDLED_GTEST_SOURCES")) or 0
            assert(compdb_facts.input_count == #compdb_inputs,
                   "gcpkg: fmt: compdb input count mismatch")
            assert(compdb_facts.total > 0,
                   "gcpkg: fmt: merged compile_commands.json is empty")
            assert(compdb_facts.bundled == 0,
                   "gcpkg: fmt: bundled googletest sources in compdb")
            if on["tests"] then
                assert(compdb_facts.gtest_entries > 0,
                       "gcpkg: fmt: source-built googletest include entries missing")
            end
            assert(ctx.exec({ "sh", "-c", "cp '" .. merged_compdb .. "' '" ..
                              util.join(ctx.build_dir, "compile_commands.json") .. "'" },
                            { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: fmt: cannot install merged compile_commands.json")
        end

        local source_link_lines = 0
        if on["tests"] then
            local link_out = util.join(vdir, "source-gtest-link.out")
            local link_rc_file = util.join(vdir, "source-gtest-link.rc")
            local link_cmd = "grep -Rl 'googletest-1.15.2/lib/libgtest' '" ..
                             util.join(ctx.build_dir, "test") ..
                             "' --include=link.txt | wc -l"
            local link_rc, link_text = run_capture(link_cmd, link_out,
                                                   link_rc_file, tenv)
            assert(link_rc == "0",
                   "gcpkg: fmt: source-googletest link scan failed")
            source_link_lines = tonumber(trim(link_text)) or 0
            assert(source_link_lines > 0,
                   "gcpkg: fmt: no test binaries link source-built googletest")
        end

        if on["library"] and on["static"] then
            assert(fs.isfile(util.join(libdir, "libfmt.a")),
                   "gcpkg: fmt: missing static libfmt.a")
        end
        if on["library"] and on["shared"] then
            for _, n in ipairs({ "libfmt.so.11.2.0", "libfmt.so.11", "libfmt.so" }) do
                assert(fs.isfile(util.join(libdir, n)),
                       "gcpkg: fmt: missing shared " .. n)
            end
        end
        if on["headers"] then
            local header_out = util.join(vdir, "header-count.out")
            local header_rc_file = util.join(vdir, "header-count.rc")
            local header_rc, header_text = run_capture(
                "find '" .. util.join(incdir, "fmt") .. "' -maxdepth 1 -type f | wc -l",
                header_out, header_rc_file, tenv)
            assert(header_rc == "0",
                   "gcpkg: fmt: header count scan failed")
            local headers = tonumber(trim(header_text)) or 0
            assert(headers >= 14,
                   "gcpkg: fmt: unexpected installed header count: " .. headers)
        end

        fs.mkdirs(docdir)
        if on["docs"] then
            assert(ctx.exec({ "sh", "-c", "cp -a '" .. util.join(ctx.src, "doc") ..
                         "/.' '" .. docdir .. "/'" },
                   { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: fmt: cannot install upstream source docs")
            for _, f in ipairs({ "README.md", "ChangeLog.md", "LICENSE", "CONTRIBUTING.md" }) do
                assert(ctx.exec({ "sh", "-c", "cp '" .. util.join(ctx.src, f) ..
                             "' '" .. util.join(docdir, f) .. "'" },
                       { cwd = vdir, env = tenv }) == 0,
                       "gcpkg: fmt: cannot install root doc " .. f)
            end
            local doc_out = util.join(vdir, "doc-count.out")
            local doc_rc_file = util.join(vdir, "doc-count.rc")
            local doc_rc, doc_text = run_capture(
                "find '" .. docdir .. "' -type f | wc -l",
                doc_out, doc_rc_file, tenv)
            assert(doc_rc == "0", "gcpkg: fmt: doc count scan failed")
            local docs = tonumber(trim(doc_text)) or 0
            assert(docs >= 13,
                   "gcpkg: fmt: unexpected installed source doc count: " .. docs)
            assert(fs.isfile(util.join(docdir, "LICENSE")),
                   "gcpkg: fmt: missing installed LICENSE")
        elseif on["license"] then
            assert(ctx.exec({ "sh", "-c", "cp '" .. util.join(ctx.src, "LICENSE") ..
                         "' '" .. util.join(docdir, "LICENSE") .. "'" },
                   { cwd = vdir, env = tenv }) == 0,
                   "gcpkg: fmt: cannot install LICENSE")
        end

        local pc = util.join(pkgdir, "fmt.pc")
        if on["pkgconfig"] then
            assert(fs.isfile(pc), "gcpkg: fmt: missing fmt.pc")
            local pc_text = assert(fs.read(pc), "gcpkg: fmt: cannot read fmt.pc")
            assert(pc_text:find("prefix=" .. prefix, 1, true),
                   "gcpkg: fmt: fmt.pc does not use source-port prefix")
            assert(pc_text:find("Version: " .. VERSION, 1, true),
                   "gcpkg: fmt: fmt.pc version mismatch")
            assert(not pc_text:find("prefix=/usr", 1, true) and
                   not pc_text:find("includedir=/usr", 1, true) and
                   not pc_text:find("libdir=/usr", 1, true),
                   "gcpkg: fmt: fmt.pc contains host prefix lines")
            local mod_out = util.join(vdir, "pkgconfig-modversion.out")
            local mod_rc_file = util.join(vdir, "pkgconfig-modversion.rc")
            local mod_rc, mod_text = run_capture(
                "'" .. wrapper .. "' --modversion fmt",
                mod_out, mod_rc_file, tenv)
            assert(mod_rc == "0" and trim(mod_text) == VERSION,
                   "gcpkg: fmt: pkg-config modversion is not " .. VERSION)
            local flags_out = util.join(vdir, "pkgconfig-flags.out")
            local flags_rc_file = util.join(vdir, "pkgconfig-flags.rc")
            local flags_rc, flags_text = run_capture(
                "'" .. wrapper .. "' --cflags --libs fmt",
                flags_out, flags_rc_file, tenv)
            assert(flags_rc == "0" and
                   flags_text:find("-I" .. incdir, 1, true) and
                   flags_text:find("-L" .. libdir, 1, true) and
                   flags_text:find("-lfmt", 1, true),
                   "gcpkg: fmt: pkg-config flags do not use the source-port prefix")
        end

        if on["cmake-package"] then
            for _, f in ipairs({ "fmt-config.cmake", "fmt-config-version.cmake",
                                 "fmt-targets.cmake", "fmt-targets-release.cmake" }) do
                assert(fs.isfile(util.join(cmakedir, f)),
                       "gcpkg: fmt: missing upstream CMake package file " .. f)
            end
            local ver = assert(fs.read(util.join(cmakedir, "fmt-config-version.cmake")),
                               "gcpkg: fmt: cannot read fmt-config-version.cmake")
            assert(ver:find('"' .. VERSION .. '"', 1, true),
                   "gcpkg: fmt: CONFIG version mismatch")
            local targets = assert(fs.read(util.join(cmakedir, "fmt-targets.cmake")),
                                   "gcpkg: fmt: cannot read fmt-targets.cmake")
            for _, t in ipairs({ "fmt::fmt", "fmt::fmt-header-only" }) do
                assert(targets:find(t, 1, true),
                       "gcpkg: fmt: missing exported target " .. t)
            end
            assert(not targets:find("FMT_FUZZ", 1, true),
                   "gcpkg: fmt: exported target unexpectedly enables FMT_FUZZ")
            if on["shared"] then
                assert(targets:find("FMT_SHARED", 1, true),
                       "gcpkg: fmt: shared export lost FMT_SHARED")
            end
            assert(not fs.isfile(util.join(cmakedir, "fmt-config.cmake.gcpkg")),
                   "gcpkg: fmt: hand-written CONFIG file is forbidden")
        end
        fs.write(util.join(vdir, "no-homemade-config.txt"),
                 "NO_HOMEMADE_CONFIG=YES\nUPSTREAM_FMT_CONFIG=YES\n")

        local consumer_cpp = [==[
#include <fmt/format.h>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
int main() {
  auto s = fmt::format("gcpkg fmt {} ok: {}\n", XSTR(CONSUMER_KIND), XSTR(GCPKG_FMT_VERSION));
  std::fputs(s.c_str(), stdout);
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
                "-DCMAKE_MAKE_PROGRAM=/usr/bin/make",
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                "-DCMAKE_CXX_COMPILER=" .. ctx.compiler.wrapper_cxx,
                "-DCMAKE_CXX_COMPILER_FORCED=TRUE",
                "-DCMAKE_CXX_COMPILER_WORKS=TRUE",
                "-DCMAKE_CXX_STANDARD=17",
                "-DCMAKE_PREFIX_PATH=" .. prefix .. ";" ..
                    (gtest and gtest.prefix or "") .. ";" ..
                    (py and py.prefix or ""),
                "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
                "-DPKG_CONFIG_EXECUTABLE=" .. wrapper,
            }
            for _, a in ipairs(defines) do cmd[#cmd + 1] = a end
            assert(ctx.exec(cmd, { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: fmt: " .. kind .. " consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", bdir, "--parallel", "4" },
                            { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: fmt: " .. kind .. " consumer build failed")
            local out = util.join(dir, "run.out")
            local rcf = util.join(dir, "run.rc")
            local rc = run_capture(util.join(bdir, "consumer"),
                                   out, rcf, tenv, dir)
            assert(rc == "0", "gcpkg: fmt: " .. kind .. " consumer run failed")
            local text = assert(fs.read(out),
                                "gcpkg: fmt: missing " .. kind .. " consumer output")
            assert(text:find("gcpkg fmt " .. kind .. " ok: " .. VERSION, 1, true),
                   "gcpkg: fmt: " .. kind .. " consumer did not use installed " .. VERSION)
        end

        if on["consumers"] then
            assert(on["library"] and on["headers"] and on["cmake-package"] and
                   on["pkgconfig"], "gcpkg: fmt: consumers need library/headers/cmake-package/pkgconfig")
            cmake_consumer("CONFIG", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_fmt_config_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(fmt 11.2.0 CONFIG REQUIRED)
add_executable(consumer main.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=CONFIG GCPKG_FMT_VERSION=11.2.0)
target_link_libraries(consumer PRIVATE fmt::fmt)
]==], { "-Dfmt_DIR=" .. cmakedir })
            cmake_consumer("FindPkgConfig", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_fmt_pkgconfig_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GCPKG_FMT REQUIRED IMPORTED_TARGET fmt)
add_executable(consumer main.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=FindPkgConfig GCPKG_FMT_VERSION=11.2.0)
target_link_libraries(consumer PRIVATE PkgConfig::GCPKG_FMT)
]==], {})
        end

        if on["sanity"] then
            assert(on["library"] and on["headers"],
                   "gcpkg: fmt: sanity needs library and headers")
            local sanity_src = util.join(vdir, "fmt_sanity.cpp")
            fs.write(sanity_src, [==[
#include <fmt/format.h>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
int main() {
  auto s = fmt::format("gcpkg fmt {} ok: {}\n", XSTR(SANITY_KIND), XSTR(GCPKG_FMT_VERSION));
  std::fputs(s.c_str(), stdout);
  return 0;
}
]==])
            local function direct_sanity(kind, flags, libs)
                local bin = cc.executable {
                    sources = { sanity_src },
                    includes = { incdir },
                    defines = { "SANITY_KIND=" .. kind,
                                "GCPKG_FMT_VERSION=" .. VERSION },
                    flags = flags,
                    cwd = vdir,
                    outdir = util.join(vdir, "obj"),
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "fmt", cxx = true,
                    output = util.join(vdir, "fmt_" .. kind .. "_consumer"),
                    libdirs = { libdir },
                    libs = libs,
                }
                local out = util.join(vdir, "sanity-" .. kind .. ".out")
                local rcf = util.join(vdir, "sanity-" .. kind .. ".rc")
                local rc = run_capture(bin, out, rcf, tenv, vdir)
                assert(rc == "0", "gcpkg: fmt: " .. kind .. " sanity consumer failed")
                local text = assert(fs.read(out),
                                    "gcpkg: fmt: missing " .. kind .. " sanity output")
                assert(text:find("gcpkg fmt " .. kind .. " ok: " .. VERSION, 1, true),
                       "gcpkg: fmt: " .. kind .. " sanity did not link installed " .. VERSION)
            end
            if on["static"] then
                direct_sanity("static", { "-std=c++17", "-l:libfmt.a" }, {})
            end
            if on["shared"] then
                direct_sanity("shared", { "-std=c++17", "-DFMT_SHARED" }, { "fmt" })
            end
        end

        local final_rc = "0"
        if on["tests"] then
            local r = shared_result or static_result
            final_rc = r and r.rc or "NOT_RUN"
            assert(final_rc == "0",
                   "gcpkg: fmt: final ctest rc not zero: " .. final_rc)
        end
        fs.write(util.join(vdir, "capability-facts.txt"), table.concat({
            "policy=full_upstream_ctest_both_passes_source_built_googletest_no_source_patch_no_ctest_E",
            "no_ctest_E=1",
            "no_source_patch=1",
            "no_test_number_blacklist=1",
            "doc_gate=upstream_FMT_DOC_ON_mkdocs_ABSENT_install_upstream_source_docs",
            "doxygen=" .. doxygen,
            "mkdocs=" .. mkdocs,
            "source_python_mkdocs=" .. source_mkdocs,
            "fuzz=OFF module=OFF cuda=OFF werror=OFF system_headers=OFF",
            "expected_registered=" .. expected_registered,
            "static=" .. fmt_result(static_result),
            "shared=" .. fmt_result(shared_result),
            "compdb_inputs=" .. compdb_facts.input_count,
            "compdb_entries=" .. compdb_facts.total,
            "gtest_include_entries=" .. compdb_facts.gtest_entries,
            "bundled_gtest_sources=" .. compdb_facts.bundled,
            "source_gtest_link_lines=" .. source_link_lines,
            "final_rc=" .. final_rc,
            "",
        }, "\n"))

        gcpkg.log.info("fmt: post_install checks complete")
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "fmt" },
        binaries = {},
    },
}
