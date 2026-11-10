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
-- Upstream-off developer benchmark/sanitizer/coverage/competition modes need
-- additional external dataset/competitor source ports that are not in this
-- gcpkg port set yet.  They are NOT disabled to dodge a real library feature;
-- they remain a separate bottom-up audit item and are explicitly reported.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

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
  else()
    message(FATAL_ERROR "gcpkg: no source port for CPM package '${_gcpkg_name}'")
  endif()
endfunction()
]==]

local function patch(path, old, new)
    local s = assert(fs.read(path), "gcpkg: cannot read " .. path)
    local n
    s, n = s:gsub(old, new, 1)
    assert(n == 1, "gcpkg: expected one match for " .. old .. " in " .. path)
    fs.write(path, s)
end

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
                -- Feature defaults are OFF here; enabled features append the
                -- matching -D...=ON args last, so disabling a feature really
                -- removes both its dependency and its build switch.
                BUILD_TESTING = "OFF",
                ADA_TESTING = "OFF",
                ADA_TOOLS = "OFF",
                BUILD_SHARED_LIBS = "OFF",
                CMAKE_BUILD_TYPE = "Release",
                CMAKE_CXX_STANDARD = "17",

                -- Developer diagnostics / benchmark harness: upstream-off and
                -- not yet backed by source ports for all competitors.
                ADA_BENCHMARKS = "OFF",
                ADA_COMPETITION = "OFF",
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
            return d
        end,
        args = {},
    },
    pre_build = function(ctx)
        -- 1. CPM's wrapper unconditionally downloads CPM.cmake from GitHub.
        --    Replace it with local source-built config packages.
        fs.write(ctx.src .. "/cmake/CPM.cmake", CPM_SHIM)
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
              (py and py.prefix) and pyOn or pyOff)
    end,
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "ada" },
      binaries = { "@PREFIX@/bin" },
    },
}
