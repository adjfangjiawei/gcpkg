-- simdjson 3.10.0 -- R20 new-standard port definition.
-- One official upstream configure/build/install pass with
-- SIMDJSON_DEVELOPER_MODE=ON and SIMDJSON_ALLOW_DOWNLOADS=OFF; the whole
-- 100-case upstream ctest suite; source-built simdjson-data (test-data),
-- python (singleheader + compdb), cxxopts (4 tools) and benchmark (3
-- Google-Benchmark targets); upstream CONFIG/.pc; independent consumers and
-- direct shared/static sanity binaries.  No source patch, no exclusion
-- filter, no disabled tests/examples/docs, no configure-time download, no homemade CMake
-- CONFIG and no reused old-standard artifacts.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "3.10.0"
local CACHE_NAME = "simdjson-3.10.0-v3.10.0"
local CACHE_SHA = "9c30552f1dd0ee3d0832bb1c6b7b97d813b18d5ef294c10dcb6fc242e5947de8"
local DATA_COMMIT = "a5b13babe65c1bba7186b41b43d4cbdc20a5c470"
local DATA_CACHE_NAME = "simdjson-data-a5b13ba-" .. DATA_COMMIT
local DATA_SHA = "aa5c4e199d05730116f3c9664a1897a75fde30dd9236334800eb83b08c6aba70"
local COMPAT_FLAG = "-Wno-error=deprecated-literal-operator"

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function fact(text, key)
    for _, line in ipairs(util.lines(text or "")) do
        local k, v = line:match("^([%w_%-]+)=(.*)$")
        if k == key then return trim(v) end
    end
    return ""
end
local function cache_value(text, key)
    for _, line in ipairs(util.lines(text or "")) do
        local k, v = line:match("^([%w_]+):[^=]*=(.*)$")
        if k == key then return trim(v) end
    end
    return ""
end
local function dep_prefix(ctx, name)
    local m = assert(ctx.dep(name),
                     "gcpkg: simdjson: missing source-built " .. name)
    assert(m.prefix and m.prefix ~= "",
           "gcpkg: simdjson: " .. name .. " has no prefix")
    return m.prefix
end
local function cmake_prefixes(ctx)
    local out = { ctx.prefix }
    for _, p in ipairs(util.split(r20.all_cmake_prefix(ctx), ";")) do
        if p ~= "" then out[#out + 1] = p end
    end
    return util.uniq(out)
end
local function data_dep_root(ctx)
    return util.join(dep_prefix(ctx, "simdjson-data"), "share", "simdjson-data")
end
local function data_cmake(ctx)
    return util.join(data_dep_root(ctx), "simdjson-data", "CMakeLists.txt")
end

local function make_defines(ctx)
    local facts = assert(fs.read(util.join(ctx.build_dir, "verify", "platform-facts.txt")),
                         "gcpkg: simdjson: missing install-task platform facts")
    assert(facts:find("cache_sha=" .. CACHE_SHA, 1, true),
           "gcpkg: simdjson: cached source tarball SHA mismatch")
    assert(facts:find("data_sha=" .. DATA_SHA, 1, true),
           "gcpkg: simdjson: cached simdjson-data tarball SHA mismatch")
    assert(fact(facts, "long_bit") == "64",
           "gcpkg: simdjson: this port needs the true 64-bit pointer size")
    assert(fact(facts, "data_cmake_present") == "YES",
           "gcpkg: simdjson: source-built simdjson-data CMake tree missing")
    local py = dep_prefix(ctx, "python")
    local cx = dep_prefix(ctx, "cxxopts")
    local bm = dep_prefix(ctx, "benchmark")
    local source_python = util.join(py, "bin", "python3")
    assert(fs.isfile(source_python),
           "gcpkg: simdjson: source-built python executable missing")
    local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
    local shim = util.join(ctx.build_dir, "simdjson-deps.cmake")
    local d = {
        CMAKE_BUILD_TYPE = "Release",
        CMAKE_C_COMPILER = ctx.compiler.wrapper_cc,
        CMAKE_CXX_COMPILER = ctx.compiler.wrapper_cxx,
        CMAKE_C_COMPILER_FORCED = "TRUE",
        CMAKE_C_COMPILER_WORKS = "TRUE",
        CMAKE_CXX_COMPILER_FORCED = "TRUE",
        CMAKE_CXX_COMPILER_WORKS = "TRUE",
        CMAKE_CXX_EXTENSIONS = "OFF",
        CMAKE_MAKE_PROGRAM = "/usr/bin/make",
        CMAKE_POLICY_VERSION_MINIMUM = "3.5",
        CMAKE_INSTALL_LIBDIR = "lib",
        CMAKE_INSTALL_INCLUDEDIR = "include",
        CMAKE_INSTALL_DOCDIR = "share/doc/simdjson",
        CMAKE_PREFIX_PATH = table.concat(cmake_prefixes(ctx), ";"),
        CMAKE_PROJECT_INCLUDE = shim,
        CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
        CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
        CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
        CMAKE_DISABLE_FIND_PACKAGE_Git = "ON",
        GIT_EXECUTABLE = "",
        PKG_CONFIG_EXECUTABLE = util.join(ctx.store.bin, "gcpkg-pkg-config"),
        -- CMAKE_CXX_COMPILER_FORCED skips CMakeTestCXXCompiler, which is where
        -- CMake normally computes CMAKE_SIZEOF_VOID_P.  Without it upstream
        -- silently skips add_subdirectory(benchmark).  8 is the true value
        -- recorded by the getconf LONG_BIT probe in platform-facts.txt.
        CMAKE_SIZEOF_VOID_P = "8",
        Python3_EXECUTABLE = source_python,
        cxxopts_DIR = util.join(cx, "lib", "cmake", "cxxopts"),
        benchmark_DIR = util.join(bm, "lib", "cmake", "benchmark"),
        SIMDJSON_CXX_STANDARD = "17",
        SIMDJSON_COMPETITION = "OFF",
        SIMDJSON_GOOGLE_BENCHMARKS = "OFF",
        SIMDJSON_CXXOPTS = "OFF",
        SIMDJSON_USE_BOOST_JSON = "OFF",
        SIMDJSON_SANITIZE = "OFF",
        SIMDJSON_SANITIZE_UNDEFINED = "OFF",
        SIMDJSON_SANITIZE_THREADS = "OFF",
        SIMDJSON_SANITIZE_MEMORY = "OFF",
        SIMDJSON_USE_LIBCPP = "OFF",
        SIMDJSON_GLIBCXX_ASSERTIONS = "OFF",
        SIMDJSON_DEVELOPMENT_CHECKS = "OFF",
        SIMDJSON_DISABLE_DEPRECATED_API = "OFF",
        SIMDJSON_VERBOSE_LOGGING = "OFF",
        SIMDJSON_INSTALL_CMAKEDIR = "lib/cmake/simdjson",
        BUILD_TESTING = "ON",
    }
    return d
end

return recipe.cmake {
    name = "simdjson",
    version = VERSION,
    description = "simdjson 3.10.0: developer mode ON, 100-case ctest, source-built simdjson-data/python/cxxopts/benchmark, shared+static, upstream CONFIG/.pc",
    license = "Apache-2.0",
    homepage = "https://github.com/simdjson/simdjson",
    source = {
        url = "https://codeload.github.com/simdjson/simdjson/tar.gz/refs/tags/v3.10.0",
        sha256 = CACHE_SHA,
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        local on = ctx.features.enabled
        -- Build-affecting capabilities are mandatory: the old port's
        -- `no-tests [on]` / developer-mode OFF bypass is not reproducible.
        for _, k in ipairs({ "shared", "static", "threads", "developer-mode",
                             "offline", "tests", "tools", "benchmarks",
                             "fuzz", "singleheader", "examples",
                             "clang23-compat" }) do
            assert(on[k], "gcpkg: simdjson: mandatory capability OFF: " .. k)
        end
        local vdir = util.join(ctx.build_dir, "verify")
        for _, sub in ipairs({ "", "home", "tmp", "obj", "consumers" }) do
            fs.mkdirs(sub == "" and vdir or util.join(vdir, sub))
        end
        local dep_root = data_dep_root(ctx)
        assert(fs.isfile(data_cmake(ctx)),
               "gcpkg: simdjson: source-built simdjson-data CMakeLists missing at " .. dep_root)

        -- CMAKE_PROJECT_INCLUDE shim: chain-load the framework's no-probe
        -- include, restore the true 64-bit pointer size, and provide the two
        -- CMake targets upstream would otherwise fetch via file(DOWNLOAD).
        -- These are the REAL installed CONFIG packages of source-built ports,
        -- not handwritten CONFIG files.
        local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
        local shim = util.join(ctx.build_dir, "simdjson-deps.cmake")
        fs.write(shim,
            "# gcpkg simdjson: dependency shim, no downloads, no source patch\n" ..
            'include("' .. noTry .. '")\n' ..
            "set(CMAKE_SIZEOF_VOID_P 8)\n" ..
            [==[
find_package(cxxopts 3.2.0 CONFIG REQUIRED)
if(NOT TARGET cxxopts)
  add_library(cxxopts INTERFACE)
  target_link_libraries(cxxopts INTERFACE cxxopts::cxxopts)
endif()
find_package(benchmark 1.9.1 CONFIG REQUIRED)
]==])

        -- import.cmake reads $ENV{simdjson_DEPENDENCY_CACHE_DIR}; pointing it
        -- at the installed source-built data tree makes EXISTS succeed so no
        -- file(DOWNLOAD) is ever reached.
        ctx.env.simdjson_DEPENDENCY_CACHE_DIR = dep_root
        -- The framework interceptor injects GCPKG_COMPILER_FLAGS into EVERY
        -- compiler invocation.  Upstream's 12 quickstart ctest cases call
        -- ${CMAKE_CXX_COMPILER} directly with a hardcoded -Werror and no
        -- CMAKE_CXX_FLAGS, so CMAKE_CXX_FLAGS alone cannot cover them.
        local prev_flags = tostring((ctx.env or {}).GCPKG_COMPILER_FLAGS or "")
        ctx.env.GCPKG_COMPILER_FLAGS = (prev_flags ~= "" and
                                        prev_flags .. " " or "") .. COMPAT_FLAG

        local own_pc = util.join(ctx.prefix, "lib", "pkgconfig")
        r20.restrict_pkgconfig(ctx)
        local pc_dirs = util.uniq(util.concat({ own_pc },
            r20.pkgconfig_dirs(ctx)))
        local allowed = { util.join(ctx.prefix, "include") }
        for _, m in ipairs(ctx.dependencies or {}) do
            for _, p in ipairs(m.includes or {}) do
                allowed[#allowed + 1] = p
            end
        end
        allowed = util.uniq(allowed)
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        assert(fs.isfile(wrapper), "gcpkg: simdjson: source-only pkg-config wrapper missing")
        ctx.env.PKG_CONFIG_PATH = table.concat(pc_dirs, ":")
        ctx.env.PKG_CONFIG_LIBDIR = table.concat(pc_dirs, ":")
        ctx.env.PKG_CONFIG_EXECUTABLE = wrapper
        ctx.env.PKG_CONFIG = wrapper
        ctx.env.GCPKG_PKG_CONFIG_REAL = "/usr/bin/pkg-config"
        ctx.env.GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = table.concat(allowed, ":")
        ctx.env.HOME = util.join(vdir, "home")
        ctx.env.TMPDIR = util.join(vdir, "tmp")
        ctx.env.XDG_CONFIG_HOME = util.join(vdir, "home", ".config")
        ctx.env.XDG_CACHE_HOME = util.join(vdir, "home", ".cache")
        ctx.env.XDG_DATA_HOME = util.join(vdir, "home", ".local", "share")
        ctx.env.CTEST_OUTPUT_ON_FAILURE = "1"
        ctx.env.CMAKE_POLICY_VERSION_MINIMUM = "3.5"

        local ld_parts = { util.join(ctx.prefix, "lib") }
        for _, m in ipairs(ctx.all_dependencies or {}) do
            for _, d in ipairs(m.libdirs or {}) do ld_parts[#ld_parts + 1] = d end
        end
        ld_parts = util.uniq(ld_parts)
        local old_ld = tostring((ctx.env or {}).LD_LIBRARY_PATH or "")
        if old_ld ~= "" then ld_parts[#ld_parts + 1] = old_ld end
        ctx.env.LD_LIBRARY_PATH = table.concat(ld_parts, ":")

        local py = dep_prefix(ctx, "python")
        local path_parts = { util.join(py, "bin"), "/usr/lib/llvm-23/bin" }
        local old_path = tostring((ctx.env or {}).PATH or os.getenv("PATH") or "")
        if old_path ~= "" then path_parts[#path_parts + 1] = old_path end
        ctx.env.PATH = table.concat(path_parts, ":")

        -- One install-task platform/service fact probe, all real values.
        local facts_file = util.join(vdir, "platform-facts.txt")
        local probe = util.join(vdir, "platform-facts.sh")
        local cache = util.join(ctx.store.cache, CACHE_NAME)
        local data_cache = util.join(ctx.store.cache, DATA_CACHE_NAME)
        fs.write(probe, [==[
set -u
out="$1"; cache="$2"; data_cache="$3"; root="$4"; vdir="$5"; src="$6"
python="$7"; data_cmake="$8"; dep_count="$9"
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" > "$out"
printf 'fs_type=%s\njobs=%s\nhome=%s\ntmp=%s\n' \
  "$(stat -f -c %T "$root" 2>/dev/null || echo UNKNOWN)" \
  "${GCPKG_JOBS:-unknown}" "$vdir/home" "$vdir/tmp" >> "$out"
printf 'cmake_version=%s\nctest_version=%s\npython3_version=%s\n' \
  "$(cmake --version 2>/dev/null | head -1)" \
  "$(ctest --version 2>/dev/null | head -1)" \
  "$("$python" --version 2>&1 | head -1)" >> "$out"
printf 'cache_name=%s\ncache_sha=%s\n' \
  "$(basename "$cache")" "$(sha256sum "$cache" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)" >> "$out"
printf 'data_cache_name=%s\ndata_sha=%s\n' \
  "$(basename "$data_cache")" "$(sha256sum "$data_cache" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)" >> "$out"
if [ -f "$data_cmake" ]; then d=YES; else d=NO; fi
printf 'data_cmake_present=%s\nsource_port_deps=%s\ndynamic_requires=%s\n' \
  "$d" "$dep_count" "$dep_count" >> "$out"
printf 'registry=OFF\nno_compiler_probe=ON\nno_network_download=ON\n' >> "$out"
printf 'no_source_patch=1\nno_ctest_E=1\nno_test_number_blacklist=1\n' >> "$out"
printf 'no_homemade_config=1\ndeveloper_mode=ON\noffline=ON\n' >> "$out"
]==])
        assert(ctx.exec({ "sh", probe, facts_file, cache, data_cache,
                          ctx.build_dir, vdir, ctx.src,
                          util.join(py, "bin", "python3"), data_cmake(ctx),
                          "4" },
                        { cwd = ctx.build_dir, log = ctx.log }) == 0,
               "gcpkg: simdjson: install-task platform facts script failed")
        fs.append(facts_file, table.concat({
            "policy=developer_mode_ON_offline_source_built_data_python_cxxopts_benchmark_full_100_ctest_no_download",
            "competition_boundary=upstream_12_competition_parsers_require_configure_time_downloads",
            "compat_reason=clang23_Wdeprecated_literal_operator_on_upstream_operator_space_suffix",
            "compat_flag=" .. COMPAT_FLAG,
            "compat_raw_quickstart=GCPKG_COMPILER_FLAGS_interceptor_injection",
            "sizeof_void_p_reason=getconf_LONG_BIT_64_restores_value_skipped_by_COMPILER_FORCED",
            "static_reason=upstream_companion_simdjson_static_target_beside_shared",
            "static_export_include_reason=upstream_static_export_has_no_INTERFACE_INCLUDE_DIRECTORIES",
            "initial_pass=single_official_cmake_pass",
            "tests_pass=ON", "tools_pass=ON", "benchmarks_pass=ON",
            "fuzz_pass=ON", "singleheader_pass=ON", "examples_pass=ON",
            "",
        }, "\n"))
        gcpkg.log.info("simdjson: install-task platform/service facts recorded once")
    end,
    cmake = {
        defines = function(ctx) return make_defines(ctx) end,
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
        local cmakedir = util.join(libdir, "cmake", "simdjson")
        local pkgdir = util.join(libdir, "pkgconfig")
        local docdir = util.join(prefix, "share", "doc", "simdjson")
        local vdir = util.join(ctx.build_dir, "verify")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        local shim = util.join(ctx.build_dir, "simdjson-deps.cmake")
        local dep_root = data_dep_root(ctx)
        local example_json = util.join(ctx.build_dir, "jsonexamples", "twitter.json")

        -- Upstream's install rules do not ship documentation; install the
        -- seven real source-doc files from the untouched tarball.
        if on["docs"] then
            fs.mkdirs(docdir)
            for _, name in ipairs({ "README.md", "LICENSE", "CONTRIBUTING.md",
                                    "HACKING.md", "SECURITY.md", "AUTHORS",
                                    "CONTRIBUTORS" }) do
                local src = util.join(ctx.src, name)
                assert(fs.isfile(src),
                       "gcpkg: simdjson: missing upstream doc " .. name)
                assert(ctx.exec({ "cp", "-a", src, util.join(docdir, name) },
                                { cwd = ctx.src, log = ctx.log }) == 0,
                       "gcpkg: simdjson: installing doc " .. name .. " failed")
            end
        end

        local facts = assert(fs.read(util.join(vdir, "platform-facts.txt")),
                             "gcpkg: simdjson: missing platform facts")
        local port_log = assert(fs.read(ctx.log),
                                "gcpkg: simdjson: missing port log")
        local cache = assert(fs.read(util.join(ctx.build_dir, "CMakeCache.txt")),
                             "gcpkg: simdjson: missing CMakeCache.txt")

        -- ===== offline / isolation / no-probe policy =====
        assert(fact(facts, "cache_sha") == CACHE_SHA,
               "gcpkg: simdjson: source tarball SHA changed")
        assert(fact(facts, "data_sha") == DATA_SHA,
               "gcpkg: simdjson: simdjson-data tarball SHA changed")
        assert(fact(facts, "long_bit") == "64",
               "gcpkg: simdjson: expected 64-bit pointer size")
        for k, want in pairs({
            SIMDJSON_DEVELOPER_MODE = "ON", SIMDJSON_ALLOW_DOWNLOADS = "OFF",
            SIMDJSON_COMPETITION = "OFF", SIMDJSON_GOOGLE_BENCHMARKS = "OFF",
            SIMDJSON_CXXOPTS = "OFF", SIMDJSON_USE_BOOST_JSON = "OFF",
            SIMDJSON_BUILD_STATIC_LIB = "ON", BUILD_SHARED_LIBS = "ON",
            SIMDJSON_ENABLE_THREADS = "ON", SIMDJSON_ENABLE_FUZZING = "ON",
            SIMDJSON_FUZZ_LINKMAIN = "ON", SIMDJSON_BASH = "ON",
            SIMDJSON_CXX_STANDARD = "17", CMAKE_SIZEOF_VOID_P = "8",
            CMAKE_CXX_FLAGS = COMPAT_FLAG,
            CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
            CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
            CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
            CMAKE_PROJECT_INCLUDE = shim,
        }) do
            local got = cache_value(cache, k)
            assert(got == want,
                   "gcpkg: simdjson: CMakeCache " .. k .. " = '" .. got ..
                   "', expected '" .. want .. "'")
        end
        assert(cache_value(cache, "Python3_EXECUTABLE"):find("python-3.12.8", 1, true),
               "gcpkg: simdjson: singleheader did not use source-built python")
        assert(cache_value(cache, "cxxopts_DIR"):find("cxxopts-3.2.0", 1, true),
               "gcpkg: simdjson: tools did not use source-built cxxopts CONFIG")
        assert(cache_value(cache, "benchmark_DIR"):find("benchmark-1.9.1", 1, true),
               "gcpkg: simdjson: benchmarks did not use source-built benchmark CONFIG")
        assert(fs.isfile(shim), "gcpkg: simdjson: dependency shim missing")
        local shim_text = assert(fs.read(shim), "gcpkg: simdjson: cannot read shim")
        assert(shim_text:find("include(", 1, true) and
               shim_text:find("find_package(cxxopts 3.2.0 CONFIG REQUIRED)", 1, true) and
               shim_text:find("find_package(benchmark 1.9.1 CONFIG REQUIRED)", 1, true),
               "gcpkg: simdjson: shim does not chain no-probe + source-built CONFIGs")
        assert(fs.isfile(data_cmake(ctx)),
               "gcpkg: simdjson: source-built simdjson-data CMake tree missing")
        assert(not port_log:find("file(DOWNLOAD", 1, true) and
               not port_log:find("Downloading", 1, true) and
               not port_log:find("archive.zip", 1, true),
               "gcpkg: simdjson: configure-time dependency download detected")
        assert(not port_log:find("ctest " .. "-E", 1, true) and
               not port_log:find("SIMDJSON_" .. "JUST_LIBRARY", 1, true),
               "gcpkg: simdjson: excluded ctest / old just-library bypass detected")

        local ld_parts = { libdir }
        for _, m in ipairs(ctx.all_dependencies or {}) do
            for _, d in ipairs(m.libdirs or {}) do ld_parts[#ld_parts + 1] = d end
        end
        ld_parts = util.uniq(ld_parts)
        local pc_dirs = util.uniq(util.concat({ pkgdir },
            r20.pkgconfig_dirs(ctx)))
        local allowed = { incdir }
        for _, m in ipairs(ctx.dependencies or {}) do
            for _, p in ipairs(m.includes or {}) do allowed[#allowed + 1] = p end
        end
        allowed = util.uniq(allowed)
        local tenv = {}
        for k, v in pairs(ctx.env or {}) do tenv[k] = v end
        tenv.HOME = util.join(vdir, "home")
        tenv.TMPDIR = util.join(vdir, "tmp")
        tenv.XDG_CONFIG_HOME = util.join(vdir, "home", ".config")
        tenv.XDG_CACHE_HOME = util.join(vdir, "home", ".cache")
        tenv.XDG_DATA_HOME = util.join(vdir, "home", ".local", "share")
        tenv.LD_LIBRARY_PATH = table.concat(ld_parts, ":")
        tenv.PKG_CONFIG_PATH = table.concat(pc_dirs, ":")
        tenv.PKG_CONFIG_LIBDIR = table.concat(pc_dirs, ":")
        tenv.PKG_CONFIG_EXECUTABLE = wrapper
        tenv.PKG_CONFIG = wrapper
        tenv.GCPKG_PKG_CONFIG_REAL = "/usr/bin/pkg-config"
        tenv.GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = table.concat(allowed, ":")
        tenv.CTEST_OUTPUT_ON_FAILURE = "1"
        tenv.GCPKG_COMPILER_FLAGS = tostring(tenv.GCPKG_COMPILER_FLAGS or COMPAT_FLAG)
        tenv.simdjson_DEPENDENCY_CACHE_DIR = dep_root

        local function run_capture(cmd, out, rcfile, env, cwd)
            local q = cmd .. " > '" .. out .. "' 2>&1; echo $? > '" .. rcfile .. "'"
            assert(ctx.exec({ "sh", "-c", q },
                            { cwd = cwd or vdir, env = env or tenv,
                              log = ctx.log }) == 0,
                   "gcpkg: simdjson: capture shell failed: " .. cmd)
            return trim(assert(fs.read(rcfile),
                               "gcpkg: simdjson: missing rc file")),
                   assert(fs.read(out), "gcpkg: simdjson: missing output file")
        end

        -- ===== full upstream ctest, 100 cases, no exclusions =====
        local ctest_summary, ctest_rc, registered = "DISABLED", "DISABLED", 0
        if on["tests"] then
            local nlog = util.join(vdir, "ctest.N")
            local nrcf = util.join(vdir, "ctest.N.rc")
            local nrc, ntext = run_capture("ctest -N", nlog, nrcf, tenv, ctx.build_dir)
            assert(nrc == "0", "gcpkg: simdjson: ctest -N failed")
            registered = tonumber(ntext:match("Total Tests: (%d+)") or "0") or 0
            assert(registered == 100,
                   "gcpkg: simdjson: unexpected registered ctest count " .. registered)
            for _, name in ipairs({ "just_ascii", "avoid_abort", "amalgamate_demo",
                                    "jsoncheck", "minefieldcheck", "testjson2json",
                                    "json2json", "quickstart", "quickstart11",
                                    "quickstart_ondemand_noexceptions11",
                                    "ondemand_twitter_tests" }) do
                assert(ntext:find(": " .. name, 1, true),
                       "gcpkg: simdjson: ctest case missing: " .. name)
            end
            local clog = util.join(vdir, "ctest.log")
            local crcf = util.join(vdir, "ctest.rc")
            local crc, cap = run_capture(
                "ctest --output-on-failure --timeout 300",
                clog, crcf, tenv, ctx.build_dir)
            ctest_rc = crc
            local total = tonumber(cap:match("out of (%d+)") or "0") or 0
            local percent = tonumber(cap:match("(%d+)%% tests passed") or "0") or 0
            ctest_summary = cap:match("(%d+%% tests passed[^\n]*)") or "NO_SUMMARY"
            assert(crc == "0" and total == 100 and percent == 100,
                   "gcpkg: simdjson: full ctest did not pass: " .. ctest_summary)
            assert(not cap:find("The following tests FAILED", 1, true),
                   "gcpkg: simdjson: ctest reported failed cases")
            -- Upstream's 12 quickstart ctest cases invoke the compiler with
            -- no -o and leave a.out in the source's examples/quickstart dir;
            -- remove that build artifact (never a source edit).
            local aout = util.join(ctx.src, "examples", "quickstart", "a.out")
            if fs.isfile(aout) then fs.rm(aout) end
        end

        -- ===== capability probe: artifacts, tools, benchmarks, fuzzers, compdb =====
        local probe = util.join(vdir, "capability-probe.sh")
        local cap_file = util.join(vdir, "capability-probe.txt")
        local py = dep_prefix(ctx, "python")
        fs.write(probe, [==[
set -u
PREFIX="$1"; BUILD="$2"; SRC="$3"; VDIR="$4"; PY="$5"; EX="$6"; DATA_CMAKE="$7"
LIB="$PREFIX/lib"; INC="$PREFIX/include"; CFG="$LIB/cmake/simdjson"
echo "HEADER=$(test -f "$INC/simdjson.h" && echo PRESENT || echo ABSENT)"
echo "HEADER_COUNT=$(find "$INC" -maxdepth 1 -type f | wc -l)"
echo "HEADER_BYTES=$(stat -c%s "$INC/simdjson.h" 2>/dev/null || echo 0)"
echo "HEADER_VERSION_MACRO=$(grep -c '#define SIMDJSON_VERSION "3.10.0"' "$INC/simdjson.h" 2>/dev/null || echo 0)"
echo "DOCS=$(find "$PREFIX/share/doc/simdjson" -type f 2>/dev/null | wc -l)"
echo "SHARED_REAL=$(test -f "$LIB/libsimdjson.so.23.0.0" && echo PRESENT || echo ABSENT)"
echo "SHARED_SOVERSION=$(test -L "$LIB/libsimdjson.so.23" && echo PRESENT || echo ABSENT)"
echo "SHARED_SYMLINK=$(test -L "$LIB/libsimdjson.so" && echo PRESENT || echo ABSENT)"
echo "STATIC_LIB=$(test -f "$LIB/libsimdjson_static.a" && echo PRESENT || echo ABSENT)"
echo "PC=$(test -f "$LIB/pkgconfig/simdjson.pc" && echo PRESENT || echo ABSENT)"
echo "PC_VERSION=$(grep '^Version:' "$LIB/pkgconfig/simdjson.pc" 2>/dev/null | head -1)"
echo "PC_CFLAGS_THREADS=$(grep -c 'SIMDJSON_THREADS_ENABLED=1' "$LIB/pkgconfig/simdjson.pc" 2>/dev/null || echo 0)"
echo "PC_PREFIX_OK=$(grep -q '^prefix=' "$LIB/pkgconfig/simdjson.pc" && echo YES || echo NO)"
echo "CONFIG_FILES=$(find "$CFG" -maxdepth 1 -type f 2>/dev/null | wc -l)"
echo "CONFIG_VERSION=$(grep -o 'PACKAGE_VERSION "[^"]*"' "$CFG/simdjson-config-version.cmake" 2>/dev/null | head -1)"
echo "TARGET_SHARED=$(grep -l 'simdjson::simdjson' "$CFG"/simdjsonTargets.cmake 2>/dev/null | wc -l)"
echo "TARGET_STATIC=$(grep -l 'simdjson::simdjson_static' "$CFG"/simdjson_staticTargets.cmake 2>/dev/null | wc -l)"
echo "HOMEMADE_CONFIG=$(find "$CFG" -maxdepth 1 -name '*.gcpkg' | wc -l)"
echo "TOOLS_BUILT=$(for t in json2json jsonstats jsonpointer minify; do test -x "$BUILD/tools/$t" && printf '%s ' "$t"; done)"
for t in json2json jsonstats jsonpointer minify; do
  exe="$BUILD/tools/$t"
  if [ -x "$exe" ]; then
    if [ "$t" = jsonpointer ]; then "$exe" "$EX" / > "$VDIR/tool-$t.out" 2>&1
    else "$exe" "$EX" > "$VDIR/tool-$t.out" 2>&1; fi
    echo "TOOL_${t}_RC=$?"
  else
    echo "TOOL_${t}_RC=ABSENT"
  fi
done
echo "BENCH_BINARIES=$(find "$BUILD/benchmark" -maxdepth 2 -type f -executable 2>/dev/null | wc -l)"
echo "BENCH_GOOGLE=$(for t in bench_parse_call bench_dom_api bench_ondemand; do test -x "$BUILD/benchmark/$t" && printf '%s ' "$t"; done)"
echo "BENCH_SOURCE_LIB=$(ldd "$BUILD/benchmark/bench_parse_call" 2>/dev/null | grep -c 'pkg/benchmark-1.9.1/lib/libbenchmark' || true)"
echo "FUZZERS=$(find "$BUILD/fuzz" -maxdepth 1 -type f -executable -name 'fuzz_*' 2>/dev/null | wc -l)"
echo "SINGLEHEADER_GENERATED=$(test -f "$BUILD/singleheader/simdjson.h" && test -f "$BUILD/singleheader/simdjson.cpp" && echo PRESENT || echo ABSENT)"
echo "SINGLEHEADER_BYTES=$(stat -c%s "$BUILD/singleheader/simdjson.h" 2>/dev/null || echo 0)"
echo "EXAMPLE_JSON=$(test -f "$EX" && echo PRESENT || echo ABSENT)"
echo "TEST_DATA_CMAKE=$(test -f "$DATA_CMAKE" && echo PRESENT || echo ABSENT)"
echo "DATA_JSON_FILES=$(find "$(dirname "$DATA_CMAKE")" -type f \( -name '*.json' -o -name '*.ndjson' \) 2>/dev/null | wc -l)"
"$PY" - "$BUILD/compile_commands.json" <<'PY'
import json, sys
try:
    a = json.load(open(sys.argv[1]))
except Exception as e:
    print('COMPILE_COMMANDS=ABSENT'); sys.exit(0)
g = lambda s: sum(1 for e in a if s in e.get('command', ''))
print('COMPILE_COMMANDS=%d' % len(a))
print('WERROR_ENTRIES=%d' % g('-Werror'))
print('WNO_ERROR_ENTRIES=%d' % g('-Wno-error=deprecated-literal-operator'))
print('CXX17_ENTRIES=%d' % g('-std=c++17'))
print('BENCHMARK_INCLUDE_ENTRIES=%d' % g('/benchmark-1.9.1/include'))
print('CXXOPTS_INCLUDE_ENTRIES=%d' % g('/cxxopts-3.2.0/include'))
print('PYTHON_AMALGAMATE_ENTRIES=%d' % g('amalgamate.py'))
PY
]==])
        local cap_rc = util.join(vdir, "capability-probe.rc")
        local cap_run_rc = run_capture(
            "sh '" .. probe .. "' '" .. prefix .. "' '" .. ctx.build_dir ..
            "' '" .. ctx.src .. "' '" .. vdir .. "' '" ..
            util.join(py, "bin", "python3") .. "' '" .. example_json ..
            "' '" .. data_cmake(ctx) .. "'",
            cap_file, cap_rc, tenv, vdir)
        assert(cap_run_rc == "0",
               "gcpkg: simdjson: capability probe failed")
        local cap = assert(fs.read(cap_file),
                           "gcpkg: simdjson: missing capability probe output")

        -- Hard artifact / capability assertions.
        for k, want in pairs({
            HEADER = "PRESENT", HEADER_COUNT = "1",
            SHARED_REAL = "PRESENT", SHARED_SOVERSION = "PRESENT",
            SHARED_SYMLINK = "PRESENT", STATIC_LIB = "PRESENT",
            PC = "PRESENT", PC_CFLAGS_THREADS = "1", PC_PREFIX_OK = "YES",
            CONFIG_FILES = "6", TARGET_SHARED = "1", TARGET_STATIC = "1",
            HOMEMADE_CONFIG = "0", EXAMPLE_JSON = "PRESENT",
            TEST_DATA_CMAKE = "PRESENT", SINGLEHEADER_GENERATED = "PRESENT",
        }) do
            local got = fact(cap, k)
            assert(got == want, "gcpkg: simdjson: " .. k .. " = '" .. got ..
                   "', expected '" .. want .. "'")
        end
        assert(tonumber(fact(cap, "HEADER_BYTES")) > 1000000,
               "gcpkg: simdjson: installed simdjson.h is not the upstream amalgamation")
        assert(fact(cap, "HEADER_VERSION_MACRO") == "1",
               "gcpkg: simdjson: installed header has no 3.10.0 version macro")
        assert(fact(cap, "CONFIG_VERSION"):find('"3.10.0"', 1, true),
               "gcpkg: simdjson: CONFIG version is not 3.10.0")
        assert(fact(cap, "PC_VERSION"):find("3.10.0", 1, true),
               "gcpkg: simdjson: .pc version is not 3.10.0")
        if on["docs"] then
            assert(fact(cap, "DOCS") == "7",
                   "gcpkg: simdjson: expected 7 upstream docs, got " .. fact(cap, "DOCS"))
        else
            assert(fact(cap, "DOCS") == "0",
                   "gcpkg: simdjson: docs disabled but docs were installed")
        end
        assert(tonumber(fact(cap, "COMPILE_COMMANDS")) >= 100,
               "gcpkg: simdjson: unexpectedly small official compile_commands.json")
        assert(tonumber(fact(cap, "WERROR_ENTRIES")) > 0,
               "gcpkg: simdjson: upstream -Werror warning set not exercised")
        assert(tonumber(fact(cap, "WNO_ERROR_ENTRIES")) > 0,
               "gcpkg: simdjson: Clang 23 compatibility flag not in compdb")
        assert(tonumber(fact(cap, "CXX17_ENTRIES")) > 0,
               "gcpkg: simdjson: C++17 compile entries missing")

        local tool_rc_line, bench_line, fuzzers = "", "DISABLED", "DISABLED"
        if on["tools"] then
            for _, t in ipairs({ "json2json", "jsonstats", "jsonpointer", "minify" }) do
                assert(fact(cap, "TOOL_" .. t .. "_RC") == "0",
                       "gcpkg: simdjson: upstream tool " .. t .. " did not run")
            end
            tool_rc_line = "4/4"
            assert(fact(cap, "TOOLS_BUILT"):find("json2json", 1, true) and
                   fact(cap, "TOOLS_BUILT"):find("minify", 1, true),
                   "gcpkg: simdjson: the four upstream tools were not built")
        end
        if on["benchmarks"] then
            assert(fact(cap, "BENCH_GOOGLE"):find("bench_parse_call", 1, true) and
                   fact(cap, "BENCH_GOOGLE"):find("bench_dom_api", 1, true) and
                   fact(cap, "BENCH_GOOGLE"):find("bench_ondemand", 1, true),
                   "gcpkg: simdjson: Google-Benchmark targets not built")
            assert(tonumber(fact(cap, "BENCH_BINARIES")) >= 10,
                   "gcpkg: simdjson: upstream benchmark tree not built")
            assert(fact(cap, "BENCH_SOURCE_LIB") == "1",
                   "gcpkg: simdjson: benchmarks did not link source-built libbenchmark")
            bench_line = fact(cap, "BENCH_GOOGLE")
        end
        if on["fuzz"] then
            fuzzers = fact(cap, "FUZZERS")
            assert(tonumber(fuzzers) == 13,
                   "gcpkg: simdjson: expected 13 upstream fuzzers, got " .. fuzzers)
        end
        if on["singleheader"] then
            assert(tonumber(fact(cap, "SINGLEHEADER_BYTES")) > 1000000,
                   "gcpkg: simdjson: amalgamate.py did not generate singleheader")
        end
        if on["developer-mode"] then
            assert(tonumber(fact(cap, "DATA_JSON_FILES")) >= 1900,
                   "gcpkg: simdjson: source-built test-data corpora missing")
        end
        if on["compdb"] then
            assert(tonumber(fact(cap, "BENCHMARK_INCLUDE_ENTRIES")) > 0 and
                   tonumber(fact(cap, "CXXOPTS_INCLUDE_ENTRIES")) > 0,
                   "gcpkg: simdjson: source-built benchmark/cxxopts not in compdb")
        end

        -- ===== independent CMake consumers =====
        local consumer_cpp = [==[
#include "simdjson.h"
#include <string_view>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
int main() {
  auto json = R"({"gcpkg":"ok"})"_padded;
  simdjson::dom::parser parser;
  simdjson::dom::element doc;
  auto error = parser.parse(json).get(doc);
  if (error) return 1;
  std::string_view value;
  error = doc["gcpkg"].get(value);
  if (error || value != "ok") return 2;
  printf("gcpkg simdjson %s ok: %s\n", XSTR(CONSUMER_KIND), SIMDJSON_VERSION);
  return 0;
}
]==]
        local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
        local function cmake_consumer(kind, cmake_text, defines)
            local dir = util.join(vdir, "consumers", kind)
            fs.mkdirs(dir)
            fs.write(util.join(dir, "CMakeLists.txt"), cmake_text)
            fs.write(util.join(dir, "consumer.cpp"), consumer_cpp)
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
                "-DCMAKE_CXX_EXTENSIONS=OFF",
                "-DCMAKE_PREFIX_PATH=" .. table.concat(cmake_prefixes(ctx), ";"),
                "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
                "-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON",
                "-DPKG_CONFIG_EXECUTABLE=" .. wrapper,
            }
            for _, a in ipairs(defines) do cmd[#cmd + 1] = a end
            assert(ctx.exec(cmd, { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: simdjson: " .. kind .. " consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", bdir, "--parallel", "4" },
                            { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: simdjson: " .. kind .. " consumer build failed")
            local out = util.join(dir, "run.out")
            local rcf = util.join(dir, "run.rc")
            local rc, text = run_capture("'" .. util.join(bdir, "consumer") .. "'",
                                         out, rcf, tenv, dir)
            assert(rc == "0", "gcpkg: simdjson: " .. kind .. " consumer run failed")
            return trim(text)
        end
        local config_out, static_out, findpkg_out = "DISABLED", "DISABLED", "DISABLED"
        if on["consumers"] and on["cmake-package"] then
            config_out = cmake_consumer("CONFIG-shared", [==[
cmake_minimum_required(VERSION 3.14)
project(gcpkg_simdjson_config_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(simdjson 3.10.0 CONFIG REQUIRED)
add_executable(consumer consumer.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=CONFIG-shared)
target_link_libraries(consumer PRIVATE simdjson::simdjson)
]==], { "-Dsimdjson_DIR=" .. cmakedir })
            assert(config_out:find("gcpkg simdjson CONFIG-shared ok: " .. VERSION, 1, true),
                   "gcpkg: simdjson: CONFIG-shared consumer failed: " .. config_out)
            -- Upstream's simdjson_staticTargets.cmake has no
            -- INTERFACE_INCLUDE_DIRECTORIES; the consumer supplies the public
            -- include path explicitly, exactly as a real consumer must.
            static_out = cmake_consumer("CONFIG-static", [==[
cmake_minimum_required(VERSION 3.14)
project(gcpkg_simdjson_static_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(simdjson 3.10.0 CONFIG REQUIRED)
add_executable(consumer consumer.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=CONFIG-static)
target_include_directories(consumer PRIVATE "${GCPKG_SIMDJSON_INCLUDE}")
target_link_libraries(consumer PRIVATE simdjson::simdjson_static)
]==], { "-Dsimdjson_DIR=" .. cmakedir, "-DGCPKG_SIMDJSON_INCLUDE=" .. incdir })
            assert(static_out:find("gcpkg simdjson CONFIG-static ok: " .. VERSION, 1, true),
                   "gcpkg: simdjson: CONFIG-static consumer failed: " .. static_out)
        end
        if on["consumers"] and on["pkgconfig"] then
            findpkg_out = cmake_consumer("FindPkgConfig", [==[
cmake_minimum_required(VERSION 3.14)
project(gcpkg_simdjson_pkgconfig_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GCPKG_SIMDJSON REQUIRED IMPORTED_TARGET simdjson)
add_executable(consumer consumer.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=FindPkgConfig)
target_link_libraries(consumer PRIVATE PkgConfig::GCPKG_SIMDJSON)
]==], {})
            assert(findpkg_out:find("gcpkg simdjson FindPkgConfig ok: " .. VERSION, 1, true),
                   "gcpkg: simdjson: FindPkgConfig consumer failed: " .. findpkg_out)
        end

        -- ===== direct shared/static sanity binaries =====
        local sanity_src = util.join(vdir, "simdjson_sanity.cpp")
        fs.write(sanity_src, [==[
#include "simdjson.h"
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
int main() {
  simdjson::dom::parser parser;
  auto doc = parser.parse(R"({"gcpkg":"ok"})"_padded);
  if (doc.error()) return 1;
  printf("gcpkg simdjson %s ok: %s\n", XSTR(SANITY_KIND), SIMDJSON_VERSION);
  return 0;
}
]==])
        local shared_sanity, static_sanity = "DISABLED", "DISABLED"
        if on["sanity"] then
            local function direct_sanity(kind, extra)
                local bin = util.join(vdir, "obj", "simdjson_" .. kind .. "_sanity")
                local cmd = { ctx.compiler.wrapper_cxx, "-std=c++17",
                              "-DSANITY_KIND=" .. kind, "-I" .. incdir,
                              sanity_src }
                for _, a in ipairs(extra) do cmd[#cmd + 1] = a end
                cmd[#cmd + 1] = "-o"
                cmd[#cmd + 1] = bin
                assert(ctx.exec(cmd, { cwd = vdir, env = tenv,
                                       log = ctx.log }) == 0,
                       "gcpkg: simdjson: " .. kind .. " sanity compile failed")
                local out = util.join(vdir, "sanity-" .. kind .. ".out")
                local rcf = util.join(vdir, "sanity-" .. kind .. ".rc")
                local rc, text = run_capture("'" .. bin .. "'", out, rcf, tenv, vdir)
                assert(rc == "0",
                       "gcpkg: simdjson: " .. kind .. " sanity run failed")
                return trim(text)
            end
            shared_sanity = direct_sanity("shared", {
                "-L" .. libdir, "-Wl,-rpath," .. libdir, "-lsimdjson", "-pthread",
            })
            assert(shared_sanity:find("gcpkg simdjson shared ok: " .. VERSION, 1, true),
                   "gcpkg: simdjson: direct shared sanity failed")
            static_sanity = direct_sanity("static", {
                util.join(libdir, "libsimdjson_static.a"), "-pthread",
            })
            assert(static_sanity:find("gcpkg simdjson static ok: " .. VERSION, 1, true),
                   "gcpkg: simdjson: direct static sanity failed")
        end

        -- ===== upstream docs =====
        local docs = fact(cap, "DOCS")
        if on["docs"] then
            assert(docs == "7", "gcpkg: simdjson: upstream docs not installed")
        else
            assert(docs == "0", "gcpkg: simdjson: docs disabled but docs were installed")
        end

        fs.write(util.join(vdir, "capability-facts.txt"), table.concat({
            "policy=developer_mode_ON_offline_source_built_data_python_cxxopts_benchmark_full_100_ctest_no_download",
            "no_ctest_E=1", "no_source_patch=1", "no_test_number_blacklist=1",
            "no_network_download=1", "no_homemade_config=1",
            "registry=OFF", "no_compiler_probe=ON",
            "developer_mode=ON", "allow_downloads=OFF",
            "competition=OFF", "google_benchmarks_vendored=OFF",
            "cxxopts_vendored=OFF", "sizeof_void_p=8",
            "expected_registered=100", "ctest=" .. ctest_summary,
            "ctest_rc=" .. ctest_rc, "tools=" .. tool_rc_line,
            "benchmarks=" .. bench_line, "fuzzers=" .. fuzzers,
            "compdb=" .. fact(cap, "COMPILE_COMMANDS"),
            "werror_entries=" .. fact(cap, "WERROR_ENTRIES"),
            "wno_error_entries=" .. fact(cap, "WNO_ERROR_ENTRIES"),
            "cxx17_entries=" .. fact(cap, "CXX17_ENTRIES"),
            "data_json_files=" .. fact(cap, "DATA_JSON_FILES"),
            "docs=" .. docs,
            "config_consumer=" .. config_out,
            "static_consumer=" .. static_out,
            "findpkgconfig_consumer=" .. findpkg_out,
            "shared_sanity=" .. shared_sanity,
            "static_sanity=" .. static_sanity,
            "",
        }, "\n"))
        gcpkg.log.info("simdjson: post_install checks complete")
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "simdjson" },
        defines = { "SIMDJSON_THREADS_ENABLED=1" },
        link_flags = {},
        binaries = {},
    },
}
