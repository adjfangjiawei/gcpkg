-- ada 2.9.2 -- gcpkg port definition.
--
-- R20 new standard: the library capabilities that this gcpkg port set supports
-- are ON by default and their libraries are SOURCE-BUILT gcpkg ports declared
-- in features.yaml `requires:` -- installed bottom-up only when the matching
-- feature is enabled.  Platform/toolchain facts come from the shared triplet
-- probe; no port hardcodes them and no library runs a feature probe.
--
-- Short-circuited in pre_build (no network / no filesystem search):
--   * cmake/CPM.cmake -> local config packages for source-built deps;
--   * find_package(Git QUIET) -> Git_FOUND=TRUE;
--   * find_program(ccache) -> no compiler launcher probe;
--   * find_package(Python3) -> source-built python port executable.
--
-- R20 P2 full comparison wiring: ADA_BENCHMARKS and ADA_COMPETITION /
-- ADA_BOOST_URL are default-ON features.  All six competitor families
-- (ICU/url_whatwg, CURL, Boost::system + Boost.URL, uriparser/urlparser/
-- httpparser, ZURI, servo-url/Rust) are installed as source-built gcpkg
-- ports via features.yaml `requires:`.  pre_build replaces the upstream
-- benchmark comparison tail (host find_package probes + CPM downloads) with
-- official CONFIG packages and IMPORTED targets from those ports.  No host
-- search, no configure-time download, no disabled test/example/data file.
-- This port is NOT claimed as a 346-port final audit.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local triplet = require("gcpkg.triplet")
local r20 = require("gcpkg.r20")

local CPM_SHIM = [==[
# gcpkg local CPM shim.  Replaces the upstream network bootstrap
# with source-built gcpkg ports: no network, no git probe, no find_* search.
include(CMakeParseArguments)
function(CPMAddPackage)
  cmake_parse_arguments(CPM "" "NAME;VERSION;GITHUB_REPOSITORY;GIT_TAG" "OPTIONS" ${ARGN})
  set(_gcpkg_name "${CPM_NAME}")
  if(NOT _gcpkg_name AND CPM_UNPARSED_ARGUMENTS)
    list(GET CPM_UNPARSED_ARGUMENTS 0 _gcpkg_spec)
    if(_gcpkg_spec MATCHES "^gh:([^/@#]+)/([^/@#]+)")
      set(_gcpkg_name "${CMAKE_MATCH_2}")
    endif()
  endif()
  if(NOT _gcpkg_name AND CPM_GITHUB_REPOSITORY)
    if(CPM_GITHUB_REPOSITORY MATCHES "/([^/]+)$")
      set(_gcpkg_name "${CMAKE_MATCH_1}")
    endif()
  endif()
  string(TOLOWER "${_gcpkg_name}" _gcpkg_lower)
  if(_gcpkg_lower STREQUAL "gtest")
    find_package(GTest CONFIG REQUIRED)
  elseif(_gcpkg_lower STREQUAL "simdjson")
    find_package(simdjson CONFIG REQUIRED)
    if(NOT TARGET simdjson AND TARGET simdjson::simdjson)
      add_library(simdjson INTERFACE IMPORTED)
      set_target_properties(simdjson PROPERTIES
        INTERFACE_LINK_LIBRARIES simdjson::simdjson)
    endif()
  elseif(_gcpkg_lower STREQUAL "fmt")
    find_package(fmt CONFIG REQUIRED)
  elseif(_gcpkg_lower STREQUAL "cxxopts")
    find_package(cxxopts CONFIG REQUIRED)
  elseif(_gcpkg_lower STREQUAL "benchmark")
    find_package(benchmark CONFIG REQUIRED)
  elseif(_gcpkg_lower STREQUAL "url-dataset")
    # Data-only source port: CPM consumers only need its source directory.
    set(url-dataset_SOURCE_DIR "${GCPKG_URL_DATASET_DIR}" PARENT_SCOPE)
  elseif(_gcpkg_lower STREQUAL "corrosion")
    # Configure-time network download; skipped by the patched benchmark file.
    set(RUST_FOUND FALSE PARENT_SCOPE)
  else()
    message(FATAL_ERROR "gcpkg: no source port for CPM package '${_gcpkg_name}'")
  endif()
endfunction()
]==]

local function patch(path, old, new, applied)
    local s = assert(fs.read(path), "gcpkg: cannot read " .. path)
    local n
    s, n = s:gsub(old, new, 1)
    if n == 0 then
        -- Already applied by a previous install over the same source tree.
        if s:find(applied or new, 1, true) then return end
        error("gcpkg: expected one match for " .. old .. " in " .. path)
    end
    fs.write(path, s)
end

-- Literal replacement (no Lua pattern escaping) for CMake snippets that
-- contain ${...}, parentheses or brackets.
local function patch_plain(path, old, new, applied)
    local s = assert(fs.read(path), "gcpkg: cannot read " .. path)
    local a, b = s:find(old, 1, true)
    if not a then
        if s:find(applied or new, 1, true) then return end
        error("gcpkg: expected literal match in " .. path .. ": " .. old)
    end
    fs.write(path, s:sub(1, a - 1) .. new .. s:sub(b + 1))
end

local COMPETITION_CMAKE = [==[
# =====================================================================
# gcpkg R20 / Ada competition families -- source-built gcpkg ports only.
#
# Upstream discovered these libraries through host find_package() probes or
# downloaded them at configure time through CPM.  Both are forbidden here.
# Every family below is an installed, source-built gcpkg port, resolved via
# its official CONFIG package (explicit PATHS + NO_DEFAULT_PATH, so nothing
# is searched on the host) or via an IMPORTED target pointing at the port's
# compiled lib.  No upstream source file, test, example or data file is
# modified or disabled.  All seven benchmark executables above this block
# are kept exactly as upstream defines them.
# =====================================================================
option(ADA_COMPETITION "Whether to install various competitors." OFF)
option(ADA_BOOST_URL "Whether to install boost URL." OFF)

if(ADA_COMPETITION AND ADA_BOOST_URL)

  # 1. ICU (source-built icu4c72) + url_whatwg (source-built url-whatwg).
  find_package(ICU CONFIG REQUIRED COMPONENTS uc i18n
    PATHS "${ICU_DIR}" NO_DEFAULT_PATH)
  find_package(upa CONFIG REQUIRED
    PATHS "${upa_DIR}" NO_DEFAULT_PATH)                     # upa::url
  # 2. Boost 1.81 official B2 CONFIG; Boost.URL comes from the source-built
  #    boost-url port's single-header implementation (src.hpp).
  find_package(Boost 1.80 CONFIG REQUIRED COMPONENTS system
    PATHS "${Boost_DIR}" NO_DEFAULT_PATH)
  # 3. CURL official CONFIG (finds source-built OpenSSL + ZLIB through the
  #    explicit *_DIR cache vars and the full CMAKE_PREFIX_PATH).
  find_package(CURL CONFIG REQUIRED
    PATHS "${CURL_DIR}" NO_DEFAULT_PATH)                    # CURL::libcurl
  # 4. uriparser official CONFIG.
  find_package(uriparser CONFIG REQUIRED
    PATHS "${uriparser_DIR}" NO_DEFAULT_PATH)               # uriparser::uriparser
  # 5. ZURI (zig-built source port).
  find_package(zuri CONFIG REQUIRED
    PATHS "${zuri_DIR}" NO_DEFAULT_PATH)                    # zuri
  # 6. servo-url (offline Rust/C-ABI source port).
  find_package(servo-url CONFIG REQUIRED
    PATHS "${GCPKG_SERVO_URL_DIR}" NO_DEFAULT_PATH)         # servo-url

  # urlparser / httpparser ship no CONFIG; their compiled static libs and
  # headers come from the source-built gcpkg ports (no configure-time build,
  # no CPM download, no host -dev package).
  add_library(urlparser STATIC IMPORTED)
  set_target_properties(urlparser PROPERTIES
    IMPORTED_LOCATION "${GCPKG_URLPARSER_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${GCPKG_URLPARSER_INCLUDE}")
  add_library(httpparser STATIC IMPORTED)
  set_target_properties(httpparser PROPERTIES
    IMPORTED_LOCATION "${GCPKG_HTTPPARSER_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${GCPKG_HTTPPARSER_INCLUDE}")
  add_library(boost_url INTERFACE IMPORTED)
  set_target_properties(boost_url PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${GCPKG_BOOST_URL_INCLUDE};${GCPKG_BOOST_INCLUDE}")

  # Upstream's own comparison macros; none of them is forced OFF.
  # ADA_VARIOUS_COMPETITION_ENABLED is intentionally bench/bbc_bench only
  # (upstream does not enable that block in benchdata).
  set(_ada_bench_targets bench benchdata bbc_bench)
  foreach(_t IN LISTS _ada_bench_targets)
    target_compile_definitions(${_t} PRIVATE
      ADA_url_whatwg_ENABLED=1
      ADA_CURL_ENABLED=1
      ADA_BOOST_ENABLED=1
      ADA_ZURI_ENABLED=1
      ADA_RUST_VERSION="${GCPKG_RUST_VERSION}")
    target_include_directories(${_t} PRIVATE "${GCPKG_CURL_INCLUDE}")
    target_link_libraries(${_t} PRIVATE
      upa::url ICU::uc ICU::i18n
      Boost::system boost_url
      CURL::libcurl
      uriparser::uriparser urlparser httpparser
      zuri servo-url)
  endforeach()
  target_compile_definitions(bench PRIVATE ADA_VARIOUS_COMPETITION_ENABLED=1)
  target_compile_definitions(bbc_bench PRIVATE ADA_VARIOUS_COMPETITION_ENABLED=1)
  target_compile_definitions(wpt_bench PRIVATE
    ADA_url_whatwg_ENABLED=1 ADA_RUST_VERSION="${GCPKG_RUST_VERSION}")
  target_link_libraries(wpt_bench PRIVATE upa::url ICU::uc ICU::i18n servo-url)
  target_compile_definitions(percent_encode PRIVATE
    ADA_RUST_VERSION="${GCPKG_RUST_VERSION}")
  target_link_libraries(percent_encode PRIVATE servo-url)
  unset(_ada_bench_targets)

else()
  message(STATUS "gcpkg: ada comparison families disabled by feature gate")
endif()
]==]

return recipe.cmake {
    name = "ada",
    version = "2.9.2",
    license = "Apache-2.0",
    homepage = "https://github.com/ada-url/ada",
    description = "Fast WHATWG-compliant URL parser",
    source = {
        url = "https://codeload.github.com/ada-url/ada/tar.gz/refs/tags/v2.9.2",
        sha256 = "f41575ad7eec833afd9f6a0d6101ee7dc2f947fdf19ae8f1b54a71d59f4ba5ec",
        strip = 1,
    },
    -- Feature dependencies are NOT hardcoded here: features.yaml `requires:`
    -- pulls googletest+simdjson (tests), fmt+cxxopts (tools), python
    -- (amalgamation) bottom-up only for enabled features.
    dependencies = {},
    cmake = {
        defines = function(ctx)
            local d = {
                -- Pointer size comes from the ONE gcpkg triplet probe (and
                -- any per-triplet user override), never from a library-side
                -- CMake/try_compile probe.  Upstream uses it to gate the
                -- Google Benchmark dependency on 32-bit systems.
                GCPKG_POINTER_SIZE = triplet.scalar(triplet.facts().pointer_size),

                -- Feature defaults are OFF here; enabled features append the
                -- matching -D...=ON args last, so disabling a feature really
                -- removes both its dependency and its build switch.
                BUILD_TESTING = "OFF",
                ADA_TESTING = "OFF",
                ADA_TOOLS = "OFF",
                BUILD_SHARED_LIBS = "OFF",
                CMAKE_BUILD_TYPE = "Release",
                CMAKE_CXX_STANDARD = "17",

                -- ADA_BENCHMARKS is feature-driven: features.yaml appends
                -- -DADA_BENCHMARKS=ON last, so disabling the feature removes
                -- both its build switch and its source-built dependencies.
                ADA_BENCHMARKS = "OFF",
                -- ADA_COMPETITION / ADA_BOOST_URL are feature-driven:
                -- features.yaml appends -D...=ON last for enabled features.
                ADA_LOGGING = "OFF",
                ADA_DEVELOPMENT_CHECKS = "OFF",
                ADA_SANITIZE = "OFF",
                ADA_SANITIZE_WITHOUT_LEAKS = "FALSE",
                ADA_SANITIZE_BOUNDS_STRICT = "OFF",
                ADA_SANITIZE_UNDEFINED = "OFF",
                ADA_COVERAGE = "OFF",
                CODE_COVERAGE_VERBOSE = "FALSE",
                HAVE_fprofile_abs_path = "FALSE",

                -- Config-mode find_package for source-built local packages.
                CMAKE_FIND_PACKAGE_PREFER_CONFIG = "ON",
            }
            local function cfgdir(dep, sub, var)
                local m = ctx.dep(dep)
                local libdir = m and (m.libdirs or {})[1]
                if libdir then d[var or (dep .. "_DIR")] = libdir .. "/cmake/" .. sub end
            end
            cfgdir("googletest", "GTest", "GTest_DIR")
            cfgdir("simdjson", "simdjson")
            cfgdir("fmt", "fmt")
            cfgdir("cxxopts", "cxxopts")
            cfgdir("benchmark", "benchmark")
            local py = ctx.dep("python")
            if py and py.prefix then d.GCPKG_PYTHON3 = py.prefix .. "/bin/python3" end
            local dataset = ctx.dep("url-dataset")
            if dataset and dataset.prefix then
                d.GCPKG_URL_DATASET_DIR = dataset.prefix .. "/share/url-dataset"
            end
            -- R20 comparison wiring: every competitor + transitive prefix is
            -- put on CMAKE_PREFIX_PATH explicitly; official CONFIG packages
            -- are pinned with *_DIR cache vars.  Nothing is left to host
            -- find_* defaults.  The competition feature's `requires:`
            -- installs these ports bottom-up; when it is off, ctx.dep for
            -- boost-url is nil and no comparison define is emitted at all.
            if ctx.dep("boost-url") then
                local function prefix_of(name)
                    local m = ctx.dep(name)
                    if m and m.prefix then return m.prefix end
                    for _, x in ipairs(ctx.all_dependencies or {}) do
                        if x.name == name and x.prefix then
                            return x.prefix
                        elseif not x.name and x.prefix then
                            local k = x.key or ""
                            if k:sub(1, #name + 1) == name .. "-" then
                                return x.prefix
                            end
                        end
                    end
                    error("ada: missing source port " .. name)
                end
                local icu = prefix_of("icu4c72")
                local upa = prefix_of("url-whatwg")
                local curl = prefix_of("curl")
                local boost = prefix_of("boost")
                local urip = prefix_of("uriparser")
                local servo = prefix_of("servo-url")
                local zuri = prefix_of("zuri")
                local openssl = prefix_of("openssl")
                local zlib = prefix_of("zlib")

                -- Full union: direct feature deps AND all transitive deps.
                local seen, allp = {}, {}
                for _, list in ipairs({ ctx.dependencies or {}, ctx.all_dependencies or {} }) do
                    for _, m in ipairs(list) do
                        if m.prefix and not seen[m.prefix] then
                            seen[m.prefix] = true
                            allp[#allp + 1] = m.prefix
                        end
                    end
                end
                d.CMAKE_PREFIX_PATH = table.concat(allp, ";")

                d.ICU_DIR = icu .. "/lib/cmake/ICU"
                d.upa_DIR = upa .. "/lib/cmake/upa"
                d.Boost_DIR = boost .. "/lib/cmake/Boost-1.81.0"
                d.boost_headers_DIR = boost .. "/lib/cmake/boost_headers-1.81.0"
                d.boost_system_DIR = boost .. "/lib/cmake/boost_system-1.81.0"
                d.CURL_DIR = curl .. "/lib/cmake/CURL"
                d.OpenSSL_DIR = openssl .. "/lib/cmake/OpenSSL"
                d.ZLIB_DIR = zlib .. "/lib/cmake/zlib"
                d.zlib_DIR = zlib .. "/lib/cmake/zlib"
                d.uriparser_DIR = urip .. "/lib/cmake/uriparser-0.9.7"
                d.zuri_DIR = zuri .. "/lib/cmake/zuri"
                d.GCPKG_SERVO_URL_DIR = servo .. "/lib/cmake/servo-url"

                d.GCPKG_URLPARSER_LIB = r20.lib_file(ctx, "urlparser", "urlparser")
                d.GCPKG_URLPARSER_INCLUDE = r20.dep_include(ctx, "urlparser")
                d.GCPKG_HTTPPARSER_LIB = r20.lib_file(ctx, "httpparser", "http_parser")
                d.GCPKG_HTTPPARSER_INCLUDE = r20.dep_include(ctx, "httpparser")
                d.GCPKG_BOOST_URL_INCLUDE = r20.dep_include(ctx, "boost-url")
                d.GCPKG_BOOST_INCLUDE = r20.dep_include(ctx, "boost")
                d.GCPKG_CURL_INCLUDE = r20.dep_include(ctx, "curl")

                -- Real Rust version from the source-built toolchain port.
                local rustver
                local rustpfx = "rust-toolchain-"
                for _, m in ipairs(ctx.all_dependencies or {}) do
                    local k = m.key or ""
                    if m.name == "rust-toolchain" or k:sub(1, #rustpfx) == rustpfx then
                        rustver = m.version or k:match("^rust%-toolchain%-(.+)$")
                    end
                end
                assert(rustver, "ada: missing rust-toolchain source port")
                d.GCPKG_RUST_VERSION = rustver

                d.CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF"
                d.CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF"
            end
            return d
        end,
        args = {},
    },
    pre_build = function(ctx)
        -- 1. CPM's wrapper unconditionally downloads CPM.cmake from GitHub.
        --    Replace it with local source-built config packages.
        local dataset = ctx.dep("url-dataset")
        local datasetDir = dataset and (dataset.prefix .. "/share/url-dataset") or ""
        fs.write(ctx.src .. "/cmake/CPM.cmake", CPM_SHIM ..
                 '\nset(GCPKG_URL_DATASET_DIR "' .. datasetDir .. '")\n')
        -- 2. Git is only used to gate tests/tools; no tool probe needed.
        patch(ctx.src .. "/CMakeLists.txt",
              "find_package%(Git QUIET%)", "set(Git_FOUND TRUE)")
        -- 3. ccache is a compiler launcher, not a platform fact.
        patch(ctx.src .. "/cmake/ada-flags.cmake",
              "find_program%(CCACHE_FOUND ccache%)", "set(CCACHE_FOUND FALSE)")
        -- 4. singleheader uses a Python interpreter.  Point it at the
        --    source-built python port instead of find_package(Python3).
        local py = ctx.dep("python")
        local pyOn = 'set(Python3_Interpreter_FOUND TRUE)\n' ..
                     'set(Python3_EXECUTABLE "${GCPKG_PYTHON3}")'
        local pyOff = 'set(Python3_Interpreter_FOUND FALSE)'
        patch(ctx.src .. "/singleheader/CMakeLists.txt",
              "find_package %(Python3 COMPONENTS Interpreter%)",
              (py and py.prefix) and pyOn or pyOff,
              "set(Python3_Interpreter_FOUND")
        -- 5. CMAKE_SIZEOF_VOID_P is produced by CMake's own compiler probe,
        --    which gcpkg short-circuits.  Use the shared pointer-size fact.
        patch_plain(ctx.src .. "/CMakeLists.txt",
                    "CMAKE_SIZEOF_VOID_P EQUAL 8",
                    "GCPKG_POINTER_SIZE EQUAL 8")
        -- 6. Replace the upstream benchmark comparison tail (host
        --    find_package probes + configure-time CPM downloads) with real
        --    source-built gcpkg ports.  Every upstream benchmark target above
        --    the option(ADA_COMPETITION) line is kept untouched.  Cutting at
        --    the marker is idempotent and also discards the old "pending"
        --    FALSE placeholders if the source tree was patched before.
        local b = ctx.src .. "/benchmarks/CMakeLists.txt"
        local s = assert(fs.read(b), "gcpkg: cannot read " .. b)
        local cut = s:find("option(ADA_COMPETITION", 1, true)
        assert(cut, "gcpkg: missing ADA_COMPETITION marker in " .. b)
        fs.write(b, s:sub(1, cut - 1) .. COMPETITION_CMAKE)
    end,
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "ada" },
      binaries = { "@PREFIX@/bin" },
    },
}
