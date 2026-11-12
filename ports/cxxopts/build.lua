-- cxxopts 3.2.0 -- R20 new-standard port definition.
-- One official upstream configure/build/install pass, full 3-case ctest,
-- source-built ICU4C 72.1 Unicode help, source-built Python compdb analysis,
-- upstream CONFIG/.pc, independent consumers and direct sanity binaries.
-- No fake static/shared libraries, no source patch, no ctest -E and no
-- hand-written CMake CONFIG package.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "3.2.0"
local CACHE_NAME = "cxxopts-3.2.0-v3.2.0"
local CACHE_SHA = "9f43fa972532e5df6c5fd5ad0f5bac606cdec541ccaf1732463d8070bbb7f03b"

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
local function defines_to_args(d)
    local out = {}
    for _, k in ipairs(util.keys(d)) do
        out[#out + 1] = "-D" .. k .. "=" .. tostring(d[k])
    end
    return out
end
local function dep_info(ctx, name)
    local m = ctx.dep(name)
    if not m or not m.prefix then return nil end
    local include = (m.includes or {})[1]
    if not include or include == "" then include = util.join(m.prefix, "include") end
    local libdir = (m.libdirs or {})[1]
    if not libdir or libdir == "" then libdir = util.join(m.prefix, "lib") end
    return { manifest = m, prefix = m.prefix, include = include, libdir = libdir }
end
local function cmake_prefixes(ctx)
    local out = { ctx.prefix }
    for _, p in ipairs(util.split(r20.all_cmake_prefix(ctx), ";")) do
        if p ~= "" then out[#out + 1] = p end
    end
    return util.uniq(out)
end

local function make_defines(ctx)
    local on = ctx.features.enabled
    local facts_path = util.join(ctx.build_dir, "verify", "platform-facts.txt")
    local facts = assert(fs.read(facts_path),
                         "gcpkg: cxxopts: missing install-task platform facts")
    assert(facts:find("cache_sha=" .. CACHE_SHA, 1, true),
           "gcpkg: cxxopts: cached source tarball SHA mismatch")
    local icu = on["unicode"] and assert(dep_info(ctx, "icu4c72"),
        "gcpkg: cxxopts: unicode needs source-built icu4c72") or nil
    local py = on["compdb"] and assert(dep_info(ctx, "python"),
        "gcpkg: cxxopts: compdb needs source-built python") or nil
    if py then
        local source_python = util.join(py.prefix, "bin", "python3")
        assert(fs.isfile(source_python),
               "gcpkg: cxxopts: source-built python executable missing")
    end
    local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
    local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
    local d = {
        CMAKE_BUILD_TYPE = "Release",
        CMAKE_CXX_COMPILER = ctx.compiler.wrapper_cxx,
        CMAKE_CXX_COMPILER_FORCED = "TRUE",
        CMAKE_CXX_COMPILER_WORKS = "TRUE",
        CMAKE_CXX_EXTENSIONS = "OFF",
        CXXOPTS_CXX_STANDARD = on["delayed-parsing"] and "17" or "11",
        CMAKE_CXX_FLAGS = on["delayed-parsing"] and "-fdelayed-template-parsing" or "",
        CMAKE_MAKE_PROGRAM = "/usr/bin/make",
        CMAKE_POLICY_VERSION_MINIMUM = "3.5",
        CMAKE_INSTALL_LIBDIR = "lib",
        CMAKE_INSTALL_INCLUDEDIR = "include",
        CMAKE_INSTALL_DOCDIR = "share/doc/cxxopts",
        CMAKE_PREFIX_PATH = table.concat(cmake_prefixes(ctx), ";"),
        CMAKE_PROJECT_INCLUDE = noTry,
        CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
        CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
        CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
        CMAKE_DISABLE_FIND_PACKAGE_Git = "ON",
        GIT_EXECUTABLE = "",
        PKG_CONFIG_EXECUTABLE = wrapper,
        CXXOPTS_ENABLE_INSTALL = "ON",
        CXXOPTS_BUILD_EXAMPLES = on["examples"] and "ON" or "OFF",
        CXXOPTS_BUILD_TESTS = on["tests"] and "ON" or "OFF",
        CXXOPTS_ENABLE_WARNINGS = on["warnings"] and "ON" or "OFF",
        CXXOPTS_USE_UNICODE_HELP = on["unicode"] and "ON" or "OFF",
    }
    return d
end

return recipe.cmake {
    name = "cxxopts",
    version = VERSION,
    description = "cxxopts 3.2.0: header-only INTERFACE, full 3-case ctest, source-built ICU72 Unicode, upstream CONFIG/.pc/consumers",
    license = "MIT",
    homepage = "https://github.com/jarro2783/cxxopts",
    source = {
        url = "https://codeload.github.com/jarro2783/cxxopts/tar.gz/refs/tags/v3.2.0",
        sha256 = CACHE_SHA,
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        local on = ctx.features.enabled
        assert(on["header"], "gcpkg: cxxopts: header feature is required")
        assert(not (on["no-delayed-parsing"] and on["tests"]),
               "gcpkg: cxxopts: C++11 opt-out conflicts with full C++17 tests")
        if on["consumers"] then
            assert(on["cmake-package"] and on["pkgconfig"] and on["sanity"],
                   "gcpkg: cxxopts: consumers need cmake-package, pkgconfig and sanity")
        end
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(vdir)
        fs.mkdirs(util.join(vdir, "home"))
        fs.mkdirs(util.join(vdir, "tmp"))
        fs.mkdirs(util.join(vdir, "obj"))
        fs.mkdirs(util.join(vdir, "consumers"))
        local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")

        local icu = on["unicode"] and assert(dep_info(ctx, "icu4c72"),
            "gcpkg: cxxopts: unicode needs source-built icu4c72") or nil
        local py = on["compdb"] and assert(dep_info(ctx, "python"),
            "gcpkg: cxxopts: compdb needs source-built python") or nil
        local icu_prefix = icu and icu.prefix or "ABSENT"
        local icu_include = icu and icu.include or "ABSENT"
        local icu_libdir = icu and icu.libdir or "ABSENT"
        local icu_pc_dir = icu and util.join(icu.libdir, "pkgconfig") or "ABSENT"
        local python_prefix = py and py.prefix or "ABSENT"
        local source_python = py and util.join(py.prefix, "bin", "python3") or "ABSENT"
        local dep_count = 0
        if on["unicode"] then dep_count = dep_count + 1 end
        if on["compdb"] then dep_count = dep_count + 1 end
        local own_pc = util.join(ctx.prefix, "lib", "pkgconfig")
        local own_include = util.join(ctx.prefix, "include")
        local pc_dirs = { own_pc }
        if icu then pc_dirs[#pc_dirs + 1] = icu_pc_dir end
        pc_dirs = util.uniq(pc_dirs)
        local allowed = { own_include }
        if icu then allowed[#allowed + 1] = icu_include end
        allowed = util.uniq(allowed)

        r20.restrict_pkgconfig(ctx)
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        assert(fs.isfile(wrapper), "gcpkg: cxxopts: source-only pkg-config wrapper missing")
        local pc_list = table.concat(pc_dirs, ":")
        ctx.env.PKG_CONFIG_PATH = pc_list
        ctx.env.PKG_CONFIG_LIBDIR = pc_list
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
        local ld_parts = {}
        if icu then ld_parts[#ld_parts + 1] = icu.libdir end
        ld_parts[#ld_parts + 1] = util.join(ctx.prefix, "lib")
        local old_ld = tostring((ctx.env or {}).LD_LIBRARY_PATH or "")
        if old_ld ~= "" then ld_parts[#ld_parts + 1] = old_ld end
        ctx.env.LD_LIBRARY_PATH = table.concat(ld_parts, ":")
        local path_parts = {}
        if py then path_parts[#path_parts + 1] = util.join(py.prefix, "bin") end
        path_parts[#path_parts + 1] = "/usr/lib/llvm-23/bin"
        local old_path = tostring((ctx.env or {}).PATH or os.getenv("PATH") or "")
        if old_path ~= "" then path_parts[#path_parts + 1] = old_path end
        ctx.env.PATH = table.concat(path_parts, ":")

        local facts_file = util.join(vdir, "platform-facts.txt")
        local probe = util.join(vdir, "platform-facts.sh")
        local cache = util.join(ctx.store.cache, CACHE_NAME)
        fs.write(probe, [==[
set -u
out="$1"; root="$2"; cache="$3"; jobs="$4"; vdir="$5"; src="$6"; cxxreal="$7"
icu_prefix="${8}"; icu_include="${9}"; icu_libdir="${10}"; icu_pc_dir="${11}"
python_prefix="${12}"; source_python="${13}"; unicode="${14}"; warnings="${15}"
cxx_standard="${16}"; delayed="${17}"; dep_count="${18}"
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
pkgconfig_version="$(pkg-config --version 2>/dev/null | head -1 || echo ABSENT)"
wrapper_exe="${PKG_CONFIG:-ABSENT}"
pkgconfig_libdir="${PKG_CONFIG_LIBDIR:-ABSENT}"
pkgconfig_include_prefixes="${GCPKG_PKG_CONFIG_INCLUDE_PREFIXES:-ABSENT}"
source_python_version=ABSENT
if [ "$source_python" != ABSENT ] && [ -x "$source_python" ]; then
  source_python_version="$("$source_python" --version 2>&1 | head -1 || echo ABSENT)"
fi
icu_modversion=ABSENT
if [ "$unicode" = ON ] && [ -x "$wrapper_exe" ] && [ -f "$icu_pc_dir/icu-uc.pc" ]; then
  icu_modversion="$("$wrapper_exe" --modversion icu-uc 2>/dev/null | head -1 || echo ABSENT)"
fi
cxx_exe="$(command -v c++ || echo ABSENT)"
cxx_real_version="$("$cxxreal" --version 2>/dev/null | head -1 || echo ABSENT)"
cache_sha="$(sha256sum "$cache" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)"
printf 'uname_s=%s\nuname_m=%s\nlong_bit=%s\nfs_type=%s\nwsl=%s\n' \
  "$(uname -s)" "$(uname -m)" "$(getconf LONG_BIT)" "$fs_type" "$wsl" > "$out"
printf 'jobs=%s\nhome=%s\ntmp=%s\n' "$jobs" "$vdir/home" "$vdir/tmp" >> "$out"
printf 'python3_exe=%s\npython3_version=%s\ncmake_exe=%s\ncmake_version=%s\n' \
  "$python3_exe" "$python3_version" "$cmake_exe" "$cmake_version" >> "$out"
printf 'ctest_exe=%s\nctest_version=%s\npkgconfig_exe=%s\npkgconfig_version=%s\n' \
  "$ctest_exe" "$ctest_version" "$pkgconfig_exe" "$pkgconfig_version" >> "$out"
printf 'wrapper_exe=%s\npkgconfig_libdir=%s\npkgconfig_include_prefixes=%s\n' \
  "$wrapper_exe" "$pkgconfig_libdir" "$pkgconfig_include_prefixes" >> "$out"
printf 'cxx_exe=%s\ncxx_real_version=%s\ncache_name=%s\ncache_sha=%s\n' \
  "$cxx_exe" "$cxx_real_version" "$cache" "$cache_sha" >> "$out"
printf 'source_port_deps=%s\ndynamic_requires=%s\n' "$dep_count" "$dep_count" >> "$out"
printf 'icu_prefix=%s\nicu_include=%s\nicu_libdir=%s\nicu_pc_dir=%s\nicu_modversion=%s\n' \
  "$icu_prefix" "$icu_include" "$icu_libdir" "$icu_pc_dir" "$icu_modversion" >> "$out"
printf 'python_prefix=%s\nsource_python=%s\nsource_python_version=%s\n' \
  "$python_prefix" "$source_python" "$source_python_version" >> "$out"
printf 'unicode=%s\nwarnings=%s\ncxx_standard=%s\ndelayed_template_parsing=%s\n' \
  "$unicode" "$warnings" "$cxx_standard" "$delayed" >> "$out"
printf 'registry=OFF\nno_compiler_probe=ON\nno_network_download=ON\n' >> "$out"
printf 'no_source_patch=1\nno_ctest_E=1\nno_test_number_blacklist=1\nheader_only=YES\n' >> "$out"
]==])
        assert(ctx.exec({ "sh", probe, facts_file, ctx.build_dir, cache,
                          tostring(ctx.jobs), vdir, ctx.src, ctx.compiler.cxx,
                          icu_prefix, icu_include, icu_libdir, icu_pc_dir,
                          python_prefix, source_python,
                          on["unicode"] and "ON" or "OFF",
                          on["warnings"] and "ON" or "OFF",
                          on["delayed-parsing"] and "17" or "11",
                          on["delayed-parsing"] and "ON" or "OFF",
                          tostring(dep_count) },
                        { cwd = ctx.build_dir, log = ctx.log }) == 0,
               "gcpkg: cxxopts: install-task platform facts script failed")
        fs.append(facts_file, table.concat({
            "fuzzer=" .. (on["tests"] and "built_not_ctest" or "NOT_BUILT_UPSTREAM_TESTS_OFF"),
            "fuzzer_reason=upstream_clang_linux_non_ctest_target_no_engine_run",
            "static=OFF",
            "shared=OFF",
            "static_shared_reason=header_only_interface_target_upstream_builds_no_libraries",
            "pc_no_libs_no_requires=YES",
            "pc_reason=upstream_pkgconfig_is_header_only_findpkgconfig_cannot_prove_icu",
            "unicode_reason=" .. (on["unicode"] and
                "source_built_icu4c72_72_1_no_host_icu" or
                "explicit_opt_out_no_icu_source_port"),
            "delayed_reason=" .. (on["delayed-parsing"] and
                "clang23_two_phase_lookup_fix_for_late_optional_parse_value_overload" or
                "explicit_cxx11_opt_out_tests_are_off"),
            "capability_policy=full_upstream_3_ctest_source_built_icu72_source_built_python_upstream_config_pc_consumers_no_source_patch_no_ctest_E",
            "initial_pass=single_official_cmake_pass",
            "tests_pass=" .. (on["tests"] and "ON" or "OFF"),
            "examples_pass=" .. (on["examples"] and "ON" or "OFF"),
            "unicode_pass=" .. (on["unicode"] and "ON" or "OFF"),
            "warnings_pass=" .. (on["warnings"] and "ON" or "OFF"),
            "docs_pass=" .. (on["docs"] and "ON" or "OFF"),
            "license_pass=" .. (on["license"] and "ON" or "OFF"),
            "pkgconfig_pass=" .. (on["pkgconfig"] and "ON" or "OFF"),
            "cmake_package_pass=" .. (on["cmake-package"] and "ON" or "OFF"),
            "compdb_pass=" .. (on["compdb"] and "ON" or "OFF"),
            "consumers_pass=" .. (on["consumers"] and "ON" or "OFF"),
            "sanity_pass=" .. (on["sanity"] and "ON" or "OFF"),
            "",
        }, "\n"))
        gcpkg.log.info("cxxopts: install-task platform/service facts recorded once")
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
        local cmakedir = util.join(libdir, "cmake", "cxxopts")
        local pkgdir = util.join(libdir, "pkgconfig")
        local docdir = util.join(prefix, "share", "doc", "cxxopts")
        local vdir = util.join(ctx.build_dir, "verify")
        local wrapper = util.join(ctx.store.bin, "gcpkg-pkg-config")
        local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
        local header = util.join(incdir, "cxxopts.hpp")
        local pc = util.join(pkgdir, "cxxopts.pc")
        local targets = util.join(cmakedir, "cxxopts-targets.cmake")
        local version_file = util.join(cmakedir, "cxxopts-config-version.cmake")

        local facts = assert(fs.read(util.join(vdir, "platform-facts.txt")),
                             "gcpkg: cxxopts: missing platform facts")
        local port_log = assert(fs.read(ctx.log),
                                "gcpkg: cxxopts: missing port build log")
        local cache = assert(fs.read(util.join(ctx.build_dir, "CMakeCache.txt")),
                             "gcpkg: cxxopts: missing CMakeCache.txt")
        assert(facts:find("cache_sha=" .. CACHE_SHA, 1, true),
               "gcpkg: cxxopts: cached source tarball SHA mismatch")
        assert(fact(facts, "registry") == "OFF",
               "gcpkg: cxxopts: registry isolation fact missing")
        assert(fact(facts, "no_compiler_probe") == "ON",
               "gcpkg: cxxopts: no-compiler-probe fact missing")
        assert(fact(facts, "no_network_download") == "ON",
               "gcpkg: cxxopts: no-network-download fact missing")
        assert(fact(facts, "no_source_patch") == "1",
               "gcpkg: cxxopts: no-source-patch fact missing")
        assert(fact(facts, "no_ctest_E") == "1",
               "gcpkg: cxxopts: no-ctest-E fact missing")
        assert(fact(facts, "no_test_number_blacklist") == "1",
               "gcpkg: cxxopts: no-test-number-blacklist fact missing")
        assert(fact(facts, "header_only") == "YES",
               "gcpkg: cxxopts: header-only fact missing")
        assert(fact(facts, "pc_no_libs_no_requires") == "YES",
               "gcpkg: cxxopts: upstream .pc boundary fact missing")
        assert(fact(facts, "fuzzer") == (on["tests"] and "built_not_ctest" or
                                          "NOT_BUILT_UPSTREAM_TESTS_OFF"),
               "gcpkg: cxxopts: fuzzer boundary fact missing")
        assert(fact(facts, "unicode") == (on["unicode"] and "ON" or "OFF"),
               "gcpkg: cxxopts: unicode fact mismatch")
        assert(fact(facts, "warnings") == (on["warnings"] and "ON" or "OFF"),
               "gcpkg: cxxopts: warnings fact mismatch")
        assert(fact(facts, "cxx_standard") == (on["delayed-parsing"] and "17" or "11"),
               "gcpkg: cxxopts: C++ standard fact mismatch")
        assert(fact(facts, "delayed_template_parsing") ==
               (on["delayed-parsing"] and "ON" or "OFF"),
               "gcpkg: cxxopts: delayed-template-parsing fact mismatch")
        assert(fs.isfile(noTry), "gcpkg: cxxopts: framework no-probe include missing")
        local noTry_text = assert(fs.read(noTry),
                                  "gcpkg: cxxopts: cannot read no-probe include")
        assert(noTry_text:find("GCPKG_TRUE_RESULTS", 1, true),
               "gcpkg: cxxopts: no-probe include has no fact table")
        assert(cache_value(cache, "CMAKE_PROJECT_INCLUDE") == noTry,
               "gcpkg: cxxopts: CMAKE_PROJECT_INCLUDE is not the framework no-probe include")
        assert(cache_value(cache, "CMAKE_CXX_COMPILER") == ctx.compiler.wrapper_cxx,
               "gcpkg: cxxopts: CMake is not using the intercepted compiler")
        assert(cache_value(cache, "CMAKE_CXX_COMPILER_FORCED") == "TRUE" and
               cache_value(cache, "CMAKE_CXX_COMPILER_WORKS") == "TRUE",
               "gcpkg: cxxopts: compiler probe short-circuit missing")
        assert(cache_value(cache, "CXXOPTS_CXX_STANDARD") ==
               (on["delayed-parsing"] and "17" or "11"),
               "gcpkg: cxxopts: unexpected CXXOPTS_CXX_STANDARD")
        assert(cache_value(cache, "CMAKE_CXX_FLAGS") ==
               (on["delayed-parsing"] and "-fdelayed-template-parsing" or ""),
               "gcpkg: cxxopts: unexpected CMAKE_CXX_FLAGS")
        assert(cache_value(cache, "CXXOPTS_BUILD_EXAMPLES") ==
               (on["examples"] and "ON" or "OFF"),
               "gcpkg: cxxopts: example gate mismatch")
        assert(cache_value(cache, "CXXOPTS_BUILD_TESTS") ==
               (on["tests"] and "ON" or "OFF"),
               "gcpkg: cxxopts: test gate mismatch")
        assert(cache_value(cache, "CXXOPTS_ENABLE_INSTALL") == "ON",
               "gcpkg: cxxopts: upstream install gate is not ON")
        assert(cache_value(cache, "CXXOPTS_ENABLE_WARNINGS") ==
               (on["warnings"] and "ON" or "OFF"),
               "gcpkg: cxxopts: warnings gate mismatch")
        assert(cache_value(cache, "CXXOPTS_USE_UNICODE_HELP") ==
               (on["unicode"] and "ON" or "OFF"),
               "gcpkg: cxxopts: Unicode gate mismatch")
        assert(cache_value(cache, "PKG_CONFIG_EXECUTABLE") == wrapper,
               "gcpkg: cxxopts: source-only pkg-config wrapper missing from cache")
        assert(cache_value(cache, "CMAKE_FIND_USE_PACKAGE_REGISTRY") == "OFF" and
               cache_value(cache, "CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY") == "OFF",
               "gcpkg: cxxopts: CMake package registry isolation missing")
        assert(not port_log:find("ctest -E", 1, true),
               "gcpkg: cxxopts: ctest -E exclusion is forbidden")
        assert(not port_log:find("-DBUILD_TESTING=OFF", 1, true) and
               not port_log:find("-DCXXOPTS_BUILD_TESTS=OFF", 1, true) and
               not port_log:find("-DCXXOPTS_BUILD_EXAMPLES=OFF", 1, true) and
               not port_log:find("-DCXXOPTS_ENABLE_INSTALL=OFF", 1, true),
               "gcpkg: cxxopts: disabling upstream tests/examples/install is forbidden")
        assert(not port_log:find("file(DOWNLOAD", 1, true) and
               not port_log:find("Downloading", 1, true) and
               not port_log:find("gcpkg probe", 1, true),
               "gcpkg: cxxopts: configure-time download or compiler probe detected")
        assert(not port_log:find("icu4c-76.1", 1, true),
               "gcpkg: cxxopts: ICU 76.1 host/source path detected")

        local icu = on["unicode"] and assert(dep_info(ctx, "icu4c72"),
            "gcpkg: cxxopts: unicode needs source-built icu4c72") or nil
        local py = on["compdb"] and assert(dep_info(ctx, "python"),
            "gcpkg: cxxopts: compdb needs source-built python") or nil
        local icu_include = icu and icu.include or "ABSENT"
        local icu_libdir = icu and icu.libdir or "ABSENT"
        local icu_pc_dir = icu and util.join(icu.libdir, "pkgconfig") or "ABSENT"
        local source_python = py and util.join(py.prefix, "bin", "python3") or "ABSENT"
        if py then
            assert(fs.isfile(source_python),
                   "gcpkg: cxxopts: source-built python executable missing")
        end
        if on["unicode"] then
            assert(fact(facts, "icu_prefix") == icu.prefix,
                   "gcpkg: cxxopts: ICU prefix fact mismatch")
            assert(fact(facts, "icu_modversion") == "72.1",
                   "gcpkg: cxxopts: ICU 72.1 modversion fact missing")
            assert(port_log:find("Found icu-uc, version 72.1", 1, true),
                   "gcpkg: cxxopts: configure did not find source-built ICU 72.1")
            local ldflags = cache_value(cache, "ICU_LDFLAGS")
            local cflags = cache_value(cache, "ICU_CFLAGS")
            assert(ldflags:find(icu_libdir, 1, true) and
                   ldflags:find("-licuuc", 1, true) and
                   ldflags:find("-licudata", 1, true),
                   "gcpkg: cxxopts: ICU_LDFLAGS does not use source-built ICU 72.1")
            assert(cflags:find(icu_include, 1, true),
                   "gcpkg: cxxopts: ICU_CFLAGS does not use source-built ICU includes")
            assert(not ldflags:find("/usr/", 1, true) and
                   not cflags:find("/usr/", 1, true),
                   "gcpkg: cxxopts: host ICU path in CMake cache")
        else
            assert(cache_value(cache, "ICU_LDFLAGS") == "" and
                   cache_value(cache, "ICU_CFLAGS") == "",
                   "gcpkg: cxxopts: ICU cache entries present although Unicode is OFF")
        end
        if on["compdb"] then
            assert(fact(facts, "python_prefix") == py.prefix,
                   "gcpkg: cxxopts: Python prefix fact mismatch")
        end

        local pc_dirs = { pkgdir }
        if icu then pc_dirs[#pc_dirs + 1] = icu_pc_dir end
        pc_dirs = util.uniq(pc_dirs)
        local allowed = { incdir }
        if icu then allowed[#allowed + 1] = icu_include end
        allowed = util.uniq(allowed)
        local ld_parts = {}
        if icu then ld_parts[#ld_parts + 1] = icu_libdir end
        ld_parts[#ld_parts + 1] = libdir
        local old_ld = tostring((ctx.env or {}).LD_LIBRARY_PATH or "")
        if old_ld ~= "" then ld_parts[#ld_parts + 1] = old_ld end
        local tenv = util.merge(ctx.env, {
            HOME = util.join(vdir, "home"),
            TMPDIR = util.join(vdir, "tmp"),
            XDG_CONFIG_HOME = util.join(vdir, "home", ".config"),
            XDG_CACHE_HOME = util.join(vdir, "home", ".cache"),
            XDG_DATA_HOME = util.join(vdir, "home", ".local", "share"),
            LD_LIBRARY_PATH = table.concat(ld_parts, ":"),
            PKG_CONFIG_PATH = table.concat(pc_dirs, ":"),
            PKG_CONFIG_LIBDIR = table.concat(pc_dirs, ":"),
            PKG_CONFIG_EXECUTABLE = wrapper,
            PKG_CONFIG = wrapper,
            GCPKG_PKG_CONFIG_REAL = "/usr/bin/pkg-config",
            GCPKG_PKG_CONFIG_INCLUDE_PREFIXES = table.concat(allowed, ":"),
            CTEST_OUTPUT_ON_FAILURE = "1",
        })

        local function run_capture(cmd, out, rcfile, env, cwd)
            local q = cmd .. " > '" .. out .. "' 2>&1; echo $? > '" .. rcfile .. "'"
            assert(ctx.exec({ "sh", "-c", q },
                            { cwd = cwd or vdir, env = env or tenv,
                              log = ctx.log }) == 0,
                   "gcpkg: cxxopts: capture shell failed: " .. cmd)
            return trim(assert(fs.read(rcfile),
                               "gcpkg: cxxopts: missing rc file")),
                   assert(fs.read(out), "gcpkg: cxxopts: missing output file")
        end

        local expected_registered = 3
        local function ctest_pass()
            local nlog = util.join(vdir, "ctest.N")
            local nrc_file = util.join(vdir, "ctest.N.rc")
            local nrc = run_capture("ctest -N", nlog, nrc_file, tenv, ctx.build_dir)
            assert(nrc == "0", "gcpkg: cxxopts: ctest -N failed")
            local ntext = assert(fs.read(nlog), "gcpkg: cxxopts: missing ctest -N log")
            local registered = tonumber(ntext:match("Total Tests: (%d+)") or "0") or 0
            assert(registered == expected_registered,
                   "gcpkg: cxxopts: unexpected registered ctest count " .. registered)
            for _, name in ipairs({ "options", "find-package-test", "add-subdirectory-test" }) do
                assert(ntext:find("Test #%d+: " .. name, 1, false) or
                       ntext:find(": " .. name, 1, true),
                       "gcpkg: cxxopts: ctest case missing: " .. name)
            end
            local cap_log = util.join(vdir, "ctest.log")
            local cap_rc_file = util.join(vdir, "ctest.rc")
            local cap_rc = run_capture("ctest --output-on-failure --timeout 300",
                                       cap_log, cap_rc_file, tenv, ctx.build_dir)
            local cap = assert(fs.read(cap_log), "gcpkg: cxxopts: missing ctest log")
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
            return { rc = cap_rc, registered = registered, total = total,
                     percent = percent, summary = summary,
                     failures = failures, log = cap }
        end
        local function ctest_line(r)
            if not r then return "DISABLED" end
            return "registered=" .. r.registered .. " total=" .. r.total ..
                   " percent=" .. r.percent .. " rc=" .. r.rc ..
                   " failed=" .. #r.failures ..
                   " names=" .. table.concat(r.failures, ",") ..
                   " summary=" .. r.summary
        end
        local ctest_result
        if on["tests"] then
            ctest_result = ctest_pass()
            assert(ctest_result.rc == "0" and ctest_result.percent == 100,
                   "gcpkg: cxxopts: full ctest not 100%: " .. ctest_line(ctest_result))
            assert(ctest_result.total == expected_registered and
                   ctest_result.registered == expected_registered,
                   "gcpkg: cxxopts: ctest total mismatch: " .. ctest_line(ctest_result))
            assert(#ctest_result.failures == 0 and
                   not ctest_result.log:find("The following tests FAILED", 1, true),
                   "gcpkg: cxxopts: ctest reported failed tests")
        end
        local final_rc = ctest_result and ctest_result.rc or "0"
        assert(final_rc == "0", "gcpkg: cxxopts: final ctest rc not zero")

        local example_help_rc = "DISABLED"
        if on["examples"] then
            local example = util.join(ctx.build_dir, "src", "example")
            assert(fs.isfile(example), "gcpkg: cxxopts: upstream example not built")
            local out = util.join(vdir, "example-help.out")
            local rcf = util.join(vdir, "example-help.rc")
            example_help_rc = run_capture("'" .. example .. "' --help", out, rcf, tenv)
            local text = assert(fs.read(out), "gcpkg: cxxopts: missing example help")
            assert(example_help_rc == "0" and
                   text:find("- example command line options", 1, true) and
                   text:find("Usage:", 1, true),
                   "gcpkg: cxxopts: upstream example --help failed")
        end
        local link_test_rc = "DISABLED"
        local fuzzer_sanitize_link = 0
        if on["tests"] then
            local options_test = util.join(ctx.build_dir, "test", "options_test")
            local link_test = util.join(ctx.build_dir, "test", "link_test")
            local fuzzer = util.join(ctx.build_dir, "test", "fuzzer")
            assert(fs.isfile(options_test), "gcpkg: cxxopts: options_test not built")
            assert(fs.isfile(link_test), "gcpkg: cxxopts: link_test not built")
            assert(fs.isfile(fuzzer), "gcpkg: cxxopts: upstream fuzzer target not built")
            local out = util.join(vdir, "link-test.out")
            local rcf = util.join(vdir, "link-test.rc")
            link_test_rc = run_capture("'" .. link_test .. "'", out, rcf, tenv)
            assert(link_test_rc == "0", "gcpkg: cxxopts: link_test run failed")
            local fz_out = util.join(vdir, "fuzzer-link.out")
            local fz_rcf = util.join(vdir, "fuzzer-link.rc")
            local fz_rc = run_capture(
                "grep -c 'fsanitize=fuzzer' '" ..
                util.join(ctx.build_dir, "test", "CMakeFiles", "fuzzer.dir", "link.txt") ..
                "'", fz_out, fz_rcf, tenv)
            local fz_text = assert(fs.read(fz_out), "gcpkg: cxxopts: missing fuzzer link scan")
            fuzzer_sanitize_link = tonumber(trim(fz_text)) or 0
            assert(fz_rc == "0" and fuzzer_sanitize_link > 0,
                   "gcpkg: cxxopts: fuzzer does not link compiler-rt libFuzzer")
        end

        local upstream_compdb = util.join(ctx.build_dir, "compile_commands.json")
        local saved_compdb = util.join(vdir, "compile_commands.upstream.json")
        assert(fs.isfile(upstream_compdb),
               "gcpkg: cxxopts: official compile_commands.json missing")
        assert(ctx.exec({ "sh", "-c", "cp '" .. upstream_compdb .. "' '" .. saved_compdb .. "'" },
                        { cwd = vdir, env = tenv, log = ctx.log }) == 0,
               "gcpkg: cxxopts: cannot save official compile_commands.json")
        local compdb_facts = { total = 0, cxx17 = 0, cxx11 = 0, source_include = 0,
                               installed_include = 0, icu_include = 0, unicode = 0,
                               werror = 0, delayed = 0, fuzz = 0 }
        if on["compdb"] then
            local compdb_py = util.join(vdir, "analyse_compdb.py")
            fs.write(compdb_py, [==[
import json, sys
path, src_inc, installed_inc, icu = sys.argv[1:5]
entries = json.load(open(path, encoding="utf-8"))
def count(needle):
    return sum(1 for e in entries if needle in e.get("command", ""))
print("TOTAL_ENTRIES=%d" % len(entries))
print("CXX17_ENTRIES=%d" % count("-std=c++17"))
print("CXX11_ENTRIES=%d" % count("-std=c++11"))
print("SOURCE_INCLUDE_ENTRIES=%d" % count(src_inc))
print("INSTALLED_INCLUDE_ENTRIES=%d" % count(installed_inc))
print("ICU_INCLUDE_ENTRIES=%d" % (count(icu) if icu != "ABSENT" else 0))
print("UNICODE_DEFINE_ENTRIES=%d" % count("CXXOPTS_USE_UNICODE"))
print("WERROR_ENTRIES=%d" % count("-Werror"))
print("DELAYED_PARSE_ENTRIES=%d" % count("delayed-template-parsing"))
print("FUZZER_SANITIZE_ENTRIES=%d" % count("fsanitize=fuzzer"))
]==])
            local compdb_out = util.join(vdir, "compdb-analysis.out")
            local compdb_rc_file = util.join(vdir, "compdb-analysis.rc")
            local cmd = "'" .. source_python .. "' '" .. compdb_py .. "' '" ..
                        saved_compdb .. "' '" .. util.join(ctx.src, "include") ..
                        "' '" .. incdir .. "' '" .. icu_include .. "'"
            local rc, text = run_capture(cmd, compdb_out, compdb_rc_file, tenv)
            assert(rc == "0", "gcpkg: cxxopts: source-built Python compdb analysis failed")
            compdb_facts.total = tonumber(fact(text, "TOTAL_ENTRIES")) or 0
            compdb_facts.cxx17 = tonumber(fact(text, "CXX17_ENTRIES")) or 0
            compdb_facts.cxx11 = tonumber(fact(text, "CXX11_ENTRIES")) or 0
            compdb_facts.source_include = tonumber(fact(text, "SOURCE_INCLUDE_ENTRIES")) or 0
            compdb_facts.installed_include = tonumber(fact(text, "INSTALLED_INCLUDE_ENTRIES")) or 0
            compdb_facts.icu_include = tonumber(fact(text, "ICU_INCLUDE_ENTRIES")) or 0
            compdb_facts.unicode = tonumber(fact(text, "UNICODE_DEFINE_ENTRIES")) or 0
            compdb_facts.werror = tonumber(fact(text, "WERROR_ENTRIES")) or 0
            compdb_facts.delayed = tonumber(fact(text, "DELAYED_PARSE_ENTRIES")) or 0
            compdb_facts.fuzz = tonumber(fact(text, "FUZZER_SANITIZE_ENTRIES")) or 0
            if on["tests"] and on["examples"] then
                assert(compdb_facts.total >= 6,
                       "gcpkg: cxxopts: upstream compdb unexpectedly short")
            end
            assert(compdb_facts.source_include > 0,
                   "gcpkg: cxxopts: compdb has no upstream source include entries")
            if on["unicode"] then
                assert(compdb_facts.icu_include > 0 and compdb_facts.unicode > 0,
                       "gcpkg: cxxopts: compdb lacks Unicode/ICU entries")
            else
                assert(compdb_facts.icu_include == 0 and compdb_facts.unicode == 0,
                       "gcpkg: cxxopts: compdb has Unicode entries although Unicode is OFF")
            end
            if on["warnings"] then
                assert(compdb_facts.werror > 0,
                       "gcpkg: cxxopts: upstream warning flags missing from compdb")
            else
                assert(compdb_facts.werror == 0,
                       "gcpkg: cxxopts: -Werror present although warnings are OFF")
            end
            if on["delayed-parsing"] then
                assert(compdb_facts.cxx17 > 0 and compdb_facts.delayed > 0,
                       "gcpkg: cxxopts: C++17 delayed-parsing entries missing")
            else
                assert(compdb_facts.cxx11 > 0 and compdb_facts.delayed == 0,
                       "gcpkg: cxxopts: C++11 opt-out compdb entries missing")
            end
            if on["tests"] then
                assert(compdb_facts.fuzz > 0,
                       "gcpkg: cxxopts: fuzzer compile entry missing")
            end
        end

        assert(fs.isfile(header), "gcpkg: cxxopts: installed cxxopts.hpp missing")
        local header_text = assert(fs.read(header),
                                   "gcpkg: cxxopts: cannot read installed header")
        assert(header_text:find("#define CXXOPTS__VERSION_MAJOR 3", 1, true) and
               header_text:find("#define CXXOPTS__VERSION_MINOR 2", 1, true) and
               header_text:find("#define CXXOPTS__VERSION_PATCH 0", 1, true),
               "gcpkg: cxxopts: installed header version mismatch")
        local header_out = util.join(vdir, "header-count.out")
        local header_rc_file = util.join(vdir, "header-count.rc")
        local header_rc, header_text = run_capture(
            "find '" .. incdir .. "' -maxdepth 1 -type f | wc -l",
            header_out, header_rc_file, tenv)
        local header_count = tonumber(trim(header_text)) or 0
        assert(header_rc == "0" and header_count == 1,
               "gcpkg: cxxopts: unexpected installed header count " .. header_count)
        assert(not fs.isfile(util.join(libdir, "libcxxopts.a")) and
               not fs.isfile(util.join(libdir, "libcxxopts.so")),
               "gcpkg: cxxopts: fake static/shared library installed")

        fs.mkdirs(docdir)
        local doc_out = util.join(vdir, "doc-count.out")
        local doc_rc_file = util.join(vdir, "doc-count.rc")
        if on["docs"] then
            for _, f in ipairs({ "README.md", "CHANGELOG.md", "INSTALL" }) do
                assert(ctx.exec({ "sh", "-c", "cp '" .. util.join(ctx.src, f) ..
                             "' '" .. util.join(docdir, f) .. "'" },
                       { cwd = vdir, env = tenv, log = ctx.log }) == 0,
                       "gcpkg: cxxopts: cannot install root doc " .. f)
            end
        end
        if on["license"] then
            assert(ctx.exec({ "sh", "-c", "cp '" .. util.join(ctx.src, "LICENSE") ..
                         "' '" .. util.join(docdir, "LICENSE") .. "'" },
                   { cwd = vdir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: cxxopts: cannot install LICENSE")
            assert(fs.isfile(util.join(docdir, "LICENSE")),
                   "gcpkg: cxxopts: installed LICENSE missing")
        end
        local doc_rc, doc_text = run_capture(
            "find '" .. docdir .. "' -type f | wc -l", doc_out, doc_rc_file, tenv)
        local docs = tonumber(trim(doc_text)) or 0
        assert(doc_rc == "0", "gcpkg: cxxopts: doc count scan failed")
        if on["docs"] and on["license"] then
            assert(docs >= 4, "gcpkg: cxxopts: unexpected installed doc count " .. docs)
        end

        local pc_no_libs_no_requires = "YES"
        if on["pkgconfig"] then
            assert(fs.isfile(pc), "gcpkg: cxxopts: missing cxxopts.pc")
            local pc_text = assert(fs.read(pc), "gcpkg: cxxopts: cannot read cxxopts.pc")
            assert(pc_text:find("prefix=" .. prefix, 1, true),
                   "gcpkg: cxxopts: cxxopts.pc does not use source-port prefix")
            assert(pc_text:find("Version: " .. VERSION, 1, true),
                   "gcpkg: cxxopts: cxxopts.pc version mismatch")
            assert(pc_text:find("Cflags: -I${includedir}", 1, true),
                   "gcpkg: cxxopts: upstream header-only Cflags missing")
            assert(not pc_text:find("Libs:", 1, true) and
                   not pc_text:find("Requires:", 1, true),
                   "gcpkg: cxxopts: upstream header-only .pc unexpectedly has Libs/Requires")
            assert(not pc_text:find("prefix=/usr", 1, true) and
                   not pc_text:find("includedir=/usr", 1, true),
                   "gcpkg: cxxopts: .pc contains host prefix lines")
            local mod_out = util.join(vdir, "pkgconfig-modversion.out")
            local mod_rc_file = util.join(vdir, "pkgconfig-modversion.rc")
            local mod_rc, mod_text = run_capture("'" .. wrapper .. "' --modversion cxxopts",
                                                 mod_out, mod_rc_file, tenv)
            assert(mod_rc == "0" and trim(mod_text) == VERSION,
                   "gcpkg: cxxopts: pkg-config modversion is not " .. VERSION)
            local flags_out = util.join(vdir, "pkgconfig-flags.out")
            local flags_rc_file = util.join(vdir, "pkgconfig-flags.rc")
            local flags_rc, flags_text = run_capture(
                "'" .. wrapper .. "' --cflags --libs cxxopts",
                flags_out, flags_rc_file, tenv)
            assert(flags_rc == "0" and flags_text:find("-I" .. incdir, 1, true) and
                   not flags_text:find("-licuuc", 1, true) and
                   not flags_text:find("/usr/", 1, true),
                   "gcpkg: cxxopts: .pc flags do not match the header-only source-port package")
            if on["unicode"] then
                local icu_out = util.join(vdir, "pkgconfig-icu.out")
                local icu_rc_file = util.join(vdir, "pkgconfig-icu.rc")
                local icu_rc, icu_text = run_capture(
                    "'" .. wrapper .. "' --modversion icu-uc",
                    icu_out, icu_rc_file, tenv)
                assert(icu_rc == "0" and trim(icu_text) == "72.1",
                       "gcpkg: cxxopts: source-only pkg-config did not find ICU 72.1")
            end
        else
            pc_no_libs_no_requires = "UNVERIFIED"
        end

        local exported_unicode = 0
        local exported_icu_ldflags = 0
        local exported_icu_cflags = 0
        local exported_host_icu = 0
        if on["cmake-package"] then
            for _, f in ipairs({ "cxxopts-config.cmake", "cxxopts-config-version.cmake",
                                 "cxxopts-targets.cmake" }) do
                assert(fs.isfile(util.join(cmakedir, f)),
                       "gcpkg: cxxopts: missing upstream CMake package file " .. f)
            end
            local ver = assert(fs.read(version_file),
                               "gcpkg: cxxopts: cannot read config-version file")
            assert(ver:find('"' .. VERSION .. '"', 1, true),
                   "gcpkg: cxxopts: CONFIG version mismatch")
            local t = assert(fs.read(targets),
                             "gcpkg: cxxopts: cannot read upstream targets file")
            assert(t:find("cxxopts::cxxopts", 1, true),
                   "gcpkg: cxxopts: exported cxxopts::cxxopts target missing")
            assert(t:find("INTERFACE_INCLUDE_DIRECTORIES", 1, true),
                   "gcpkg: cxxopts: exported include directories missing")
            exported_unicode = t:find("CXXOPTS_USE_UNICODE", 1, true) and 1 or 0
            exported_icu_ldflags = (t:find("-licuuc", 1, true) and
                                    t:find("-licudata", 1, true)) and 1 or 0
            exported_icu_cflags = icu and t:find(icu_include, 1, true) and 1 or 0
            exported_host_icu = (t:find("/usr/include", 1, true) or
                                 t:find("/usr/lib", 1, true)) and 1 or 0
            if on["unicode"] then
                assert(exported_unicode == 1 and exported_icu_ldflags == 1 and
                       exported_icu_cflags == 1,
                       "gcpkg: cxxopts: exported target lost ICU 72.1 properties")
            else
                assert(exported_unicode == 0 and exported_icu_ldflags == 0 and
                       exported_icu_cflags == 0,
                       "gcpkg: cxxopts: exported target has ICU properties although Unicode is OFF")
            end
            assert(exported_host_icu == 0,
                   "gcpkg: cxxopts: exported target contains host ICU paths")
            assert(not fs.isfile(util.join(cmakedir, "cxxopts-config.cmake.gcpkg")),
                   "gcpkg: cxxopts: hand-written CONFIG file is forbidden")
        end
        fs.write(util.join(vdir, "no-homemade-config.txt"),
                 "NO_HOMEMADE_CONFIG=YES\nUPSTREAM_CXXOPTS_CONFIG=YES\n")

        local consumer_cpp = [==[
#include <cxxopts.hpp>
#include <cstdio>
#define STR(x) #x
#define XSTR(x) STR(x)
int main(int argc, char** argv) {
  cxxopts::Options options("gcpkg", "test");
  options.add_options()("h,help", "help");
  auto result = options.parse(argc, argv);
  (void)result;
  printf("gcpkg cxxopts %s ok: %d.%d.%d\n", XSTR(CONSUMER_KIND),
         CXXOPTS__VERSION_MAJOR, CXXOPTS__VERSION_MINOR, CXXOPTS__VERSION_PATCH);
  return 0;
}
]==]
        local unicode_consumer_cpp = [==[
#include <cxxopts.hpp>
#include <cstdio>
#include <unicode/unistr.h>
#define STR(x) #x
#define XSTR(x) STR(x)
int main(int argc, char** argv) {
  cxxopts::Options options("gcpkg", "unicode test");
  options.add_options()("h,help", "help");
  auto result = options.parse(argc, argv);
  (void)result;
  icu::UnicodeString s = icu::UnicodeString::fromUTF8("ok");
  printf("gcpkg cxxopts %s ok: %d.%d.%d len=%d\n", XSTR(CONSUMER_KIND),
         CXXOPTS__VERSION_MAJOR, CXXOPTS__VERSION_MINOR, CXXOPTS__VERSION_PATCH,
         (int)s.length());
  return 0;
}
]==]
        local function cmake_consumer(kind, cmake_text, src_text, defines)
            local dir = util.join(vdir, "consumers", kind)
            fs.mkdirs(dir)
            fs.write(util.join(dir, "CMakeLists.txt"), cmake_text)
            fs.write(util.join(dir, "consumer.cpp"), src_text)
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
                   "gcpkg: cxxopts: " .. kind .. " consumer configure failed")
            assert(ctx.exec({ "cmake", "--build", bdir, "--parallel", "4" },
                            { cwd = dir, env = tenv, log = ctx.log }) == 0,
                   "gcpkg: cxxopts: " .. kind .. " consumer build failed")
            local out = util.join(dir, "run.out")
            local rcf = util.join(dir, "run.rc")
            local rc = run_capture("'" .. util.join(bdir, "consumer") .. "'",
                                   out, rcf, tenv, dir)
            assert(rc == "0", "gcpkg: cxxopts: " .. kind .. " consumer run failed")
            return trim(assert(fs.read(out),
                               "gcpkg: cxxopts: missing " .. kind .. " consumer output"))
        end
        local config_out, findpkgconfig_out, unicode_config_out = "DISABLED", "DISABLED", "DISABLED"
        if on["consumers"] then
            config_out = cmake_consumer("CONFIG", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_cxxopts_config_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(cxxopts 3.2.0 CONFIG REQUIRED)
add_executable(consumer consumer.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=CONFIG)
target_link_libraries(consumer PRIVATE cxxopts::cxxopts)
]==], consumer_cpp, { "-Dcxxopts_DIR=" .. cmakedir })
            assert(config_out:find("gcpkg cxxopts CONFIG ok: " .. VERSION, 1, true),
                   "gcpkg: cxxopts: CONFIG consumer did not use installed " .. VERSION)
            findpkgconfig_out = cmake_consumer("FindPkgConfig", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_cxxopts_pkgconfig_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GCPKG_CXXOPTS REQUIRED IMPORTED_TARGET cxxopts)
add_executable(consumer consumer.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=FindPkgConfig)
target_link_libraries(consumer PRIVATE PkgConfig::GCPKG_CXXOPTS)
]==], consumer_cpp, {})
            assert(findpkgconfig_out:find("gcpkg cxxopts FindPkgConfig ok: " .. VERSION, 1, true),
                   "gcpkg: cxxopts: FindPkgConfig consumer did not use installed " .. VERSION)
            if on["unicode"] then
                unicode_config_out = cmake_consumer("CONFIG-Unicode", [==[
cmake_minimum_required(VERSION 3.13)
project(gcpkg_cxxopts_unicode_config_consumer LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(cxxopts 3.2.0 CONFIG REQUIRED)
add_executable(consumer consumer.cpp)
target_compile_definitions(consumer PRIVATE CONSUMER_KIND=CONFIG-Unicode)
target_link_libraries(consumer PRIVATE cxxopts::cxxopts)
]==], unicode_consumer_cpp, { "-Dcxxopts_DIR=" .. cmakedir })
                assert(unicode_config_out:find(
                       "gcpkg cxxopts CONFIG-Unicode ok: " .. VERSION .. " len=2", 1, true),
                       "gcpkg: cxxopts: CONFIG-Unicode consumer did not link source-built ICU")
            end
        end

        local header_sanity_out, unicode_sanity_out = "DISABLED", "DISABLED"
        if on["sanity"] then
            local sanity_src = util.join(vdir, "cxxopts_sanity.cpp")
            fs.write(sanity_src, consumer_cpp)
            local unicode_src = util.join(vdir, "cxxopts_unicode_sanity.cpp")
            fs.write(unicode_src, unicode_consumer_cpp)
            local function direct_sanity(kind, src, defines, includes, libdirs, libs)
                local bin = cc.executable {
                    sources = { src },
                    includes = includes,
                    defines = defines,
                    flags = { "-std=c++17", "-fdelayed-template-parsing" },
                    cwd = vdir,
                    outdir = util.join(vdir, "obj"),
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "cxxopts", cxx = true,
                    output = util.join(vdir, "obj", "cxxopts_" .. kind .. "_consumer"),
                    libdirs = libdirs,
                    libs = libs,
                }
                local out = util.join(vdir, "sanity-" .. kind .. ".out")
                local rcf = util.join(vdir, "sanity-" .. kind .. ".rc")
                local rc = run_capture("'" .. bin .. "'", out, rcf, tenv, vdir)
                assert(rc == "0", "gcpkg: cxxopts: " .. kind .. " sanity consumer failed")
                return trim(assert(fs.read(out),
                                   "gcpkg: cxxopts: missing " .. kind .. " sanity output"))
            end
            header_sanity_out = direct_sanity("header-only", sanity_src,
                { "SANITY_KIND=header-only", "CONSUMER_KIND=header-only" },
                { incdir }, {}, {})
            assert(header_sanity_out:find(
                   "gcpkg cxxopts header-only ok: " .. VERSION, 1, true),
                   "gcpkg: cxxopts: direct header-only sanity failed")
            if on["unicode"] then
                unicode_sanity_out = direct_sanity("unicode", unicode_src,
                    { "SANITY_KIND=unicode", "CONSUMER_KIND=unicode",
                      "CXXOPTS_USE_UNICODE" },
                    { incdir, icu_include }, { icu_libdir },
                    { "icuuc", "icudata" })
                assert(unicode_sanity_out:find(
                       "gcpkg cxxopts unicode ok: " .. VERSION .. " len=2", 1, true),
                       "gcpkg: cxxopts: direct Unicode sanity did not link source-built ICU")
            end
        end

        local compdb_line = "DISABLED"
        if on["compdb"] then
            compdb_line = table.concat({
                "total=" .. compdb_facts.total,
                "cxx17=" .. compdb_facts.cxx17,
                "cxx11=" .. compdb_facts.cxx11,
                "source_include=" .. compdb_facts.source_include,
                "installed_include=" .. compdb_facts.installed_include,
                "icu_include=" .. compdb_facts.icu_include,
                "unicode=" .. compdb_facts.unicode,
                "werror=" .. compdb_facts.werror,
                "delayed=" .. compdb_facts.delayed,
                "fuzz=" .. compdb_facts.fuzz,
            }, " ")
        end
        fs.write(util.join(vdir, "capability-facts.txt"), table.concat({
            "policy=full_upstream_3_ctest_source_built_icu72_source_built_python_upstream_config_pc_consumers_no_source_patch_no_ctest_E",
            "no_ctest_E=1",
            "no_source_patch=1",
            "no_test_number_blacklist=1",
            "no_host_icu=1",
            "registry=OFF",
            "no_compiler_probe=ON",
            "no_network_download=ON",
            "header_only=YES",
            "static=OFF",
            "shared=OFF",
            "cxx_standard=" .. (on["delayed-parsing"] and "17" or "11"),
            "delayed_template_parsing=" .. (on["delayed-parsing"] and "ON" or "OFF"),
            "unicode=" .. (on["unicode"] and "ON" or "OFF"),
            "warnings=" .. (on["warnings"] and "ON" or "OFF"),
            "expected_registered=" .. expected_registered,
            "ctest=" .. ctest_line(ctest_result),
            "final_rc=" .. final_rc,
            "example_help_rc=" .. example_help_rc,
            "link_test_rc=" .. link_test_rc,
            "fuzzer=" .. (on["tests"] and "built_not_ctest" or "NOT_BUILT_UPSTREAM_TESTS_OFF"),
            "fuzzer_sanitize_link=" .. fuzzer_sanitize_link,
            "compdb=" .. compdb_line,
            "installed_docs=" .. docs,
            "pc_no_libs_no_requires=" .. pc_no_libs_no_requires,
            "exported_target_unicode=" .. exported_unicode,
            "exported_target_icu_ldflags=" .. exported_icu_ldflags,
            "exported_target_icu_cflags=" .. exported_icu_cflags,
            "exported_target_host_icu=" .. exported_host_icu,
            "no_homemade_config=YES",
            "config_consumer=" .. config_out,
            "findpkgconfig_consumer=" .. findpkgconfig_out,
            "config_unicode_consumer=" .. unicode_config_out,
            "header_only_sanity=" .. header_sanity_out,
            "unicode_sanity=" .. unicode_sanity_out,
            "",
        }, "\n"))

        gcpkg.log.info("cxxopts: post_install checks complete")
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = {},
        defines = {
            function(ctx)
                if ctx.features.enabled["unicode"] then
                    return { "CXXOPTS_USE_UNICODE" }
                end
                return {}
            end,
        },
        link_flags = {},
        binaries = {},
    },
}
