-- boost-url boost-1.81.0 -- gcpkg source port for Ada's Boost.URL
-- competitor.  Ada comparison flags and the CPM boost_url shim stay OFF.
-- boost/ libraries and the official Boost::url CONFIG come from the B2-built
-- `boost` port.  This port installs the standalone URL headers, the B2-built
-- library, upstream docs/WPT data, and builds/runs the real upstream CMake
-- tests and examples.  No source patch, no hand-written CONFIG, no build-time
-- networking, no host Boost/ICU discovery.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local cmake = require("gcpkg.build.cmake")
local r20 = require("gcpkg.r20")

local VERSION = "boost-1.81.0"
local CACHE_NAME = "boost-url-boost-1.81.0-boost-1.81.0"
local SOURCE_SHA = "71a2431da79ac1a5c4b11dc0e176f8b5f608fdac9221b61c70ea1cce378bf2fa"
local WPT_FILES = { "setters_tests.json", "toascii.json", "urltestdata.json",
                    "percent-encoding.json", "IdnaTestV2.json" }

local function render(s, vars)
    return (s:gsub("@@([%w_]+)@@", function(k)
        local v = vars[k]
        assert(v ~= nil, "gcpkg: boost-url: missing template variable " .. k)
        return tostring(v)
    end))
end

local HARNESS_CMAKE = [==[
cmake_minimum_required(VERSION 3.16)
cmake_policy(SET CMP0167 NEW)
project(gcpkg_boost_url_upstream_harness LANGUAGES CXX)
include(CTest)
enable_testing()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(BUILD_TESTING ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(Boost_USE_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(BOOST_URL_FIND_PACKAGE_BOOST ON CACHE BOOL "" FORCE)
set(BOOST_URL_BUILD_TESTS ON CACHE BOOL "" FORCE)
set(BOOST_URL_BUILD_EXAMPLES ON CACHE BOOL "" FORCE)
find_package(Boost 1.81.0 CONFIG REQUIRED COMPONENTS container filesystem json regex system url)
if(NOT TARGET Boost::unordered)
  add_library(Boost::unordered INTERFACE IMPORTED)
  set_target_properties(Boost::unordered PROPERTIES INTERFACE_LINK_LIBRARIES Boost::headers)
endif()
add_subdirectory("@@SRC@@/test" test)
add_subdirectory("@@SRC@@/example" example)
add_executable(boost_url_wpt "@@WPT_WRAPPER@@")
target_include_directories(boost_url_wpt PRIVATE "@@SRC@@/test/wpt" "@@SRC@@/extra")
target_link_libraries(boost_url_wpt PRIVATE Boost::url Boost::json)
]==]

local WPT_WRAPPER = [==[
#include <ostream>
namespace test_suite { using debug_stream = std::ostream&; }
#include "@@SRC@@/test/wpt/main.cpp"
]==]

local CONSUMER_CMAKE = [==[
cmake_minimum_required(VERSION 3.16)
cmake_policy(SET CMP0167 NEW)
project(gcpkg_boost_url_official_consumer LANGUAGES CXX)
set(Boost_USE_STATIC_LIBS ON)
find_package(Boost 1.81.0 CONFIG REQUIRED COMPONENTS url)
add_executable(consumer main.cpp)
target_compile_features(consumer PRIVATE cxx_std_17)
target_link_libraries(consumer PRIVATE Boost::url Boost::headers)
]==]

local CONSUMER_CPP = [==[
#include <boost/url.hpp>
#include <boost/url/parse.hpp>
#include <iostream>
int main() {
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  bool ok = r.has_value();
  std::cout << "gcpkg boost-url official CONFIG consumer ok=" << (ok ? 1 : 0) << "\n";
  return ok ? 0 : 1;
}
]==]

local HEADER_SANITY = [==[
#include <boost/url/src.hpp>
#include <boost/url/parse.hpp>
#include <boost/unordered_map.hpp>
#include <iostream>
int main() {
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  boost::unordered_map<int, int> m; m[1] = 2;
  bool ok = r.has_value() && m.at(1) == 2;
  std::cout << "gcpkg boost-url header-only sanity ok=" << (ok ? 1 : 0) << "\n";
  return ok ? 0 : 1;
}
]==]

local LIBRARY_SANITY = [==[
#include <boost/url.hpp>
#include <boost/url/parse.hpp>
#include <boost/unordered_map.hpp>
#include <iostream>
int main() {
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  boost::unordered_map<int, int> m; m[1] = 2;
  bool ok = r.has_value() && m.at(1) == 2;
  std::cout << "gcpkg boost-url static sanity ok=" << (ok ? 1 : 0) << "\n";
  return ok ? 0 : 1;
}
]==]

local function first_line(out)
    return (tostring(out or ""):match("([^\r\n]+)") or "")
end

local function build(ctx)
    local on = ctx.features.enabled
    for _, k in ipairs({ "headers", "library", "cmake-package", "tests",
                         "examples", "finicky", "route", "wpt", "sanity",
                         "license" }) do
        assert(on[k], "gcpkg: boost-url: mandatory capability OFF: " .. k)
    end
    r20.restrict_pkgconfig(ctx)

    local boost = r20.dep_prefix(ctx, "boost")
    local unordered = r20.dep_prefix(ctx, "boost-unordered")
    local wpt = r20.dep_prefix(ctx, "url-wpt-data")
    local boost_cmake = util.join(boost, "lib", "cmake", "Boost-1.81.0")
    local boost_inc = util.join(boost, "include")
    local unordered_inc = util.join(unordered, "include")
    local wpt_port = util.join(wpt, "share", "url-wpt-data", "wpt")
    local incdir = util.join(ctx.prefix, "include")
    local boostdir = util.join(incdir, "boost")
    local libdir = util.join(ctx.prefix, "lib")
    local docdir = util.join(ctx.prefix, "share", "doc", "boost-url")
    local wptdir = util.join(ctx.prefix, "share", "boost-url", "wpt")
    local wptportdir = util.join(ctx.prefix, "share", "boost-url", "wpt-port")
    local vdir = util.join(ctx.build_dir, "verify")
    local home = util.join(ctx.build_dir, "home")
    local tmp = util.join(ctx.build_dir, "tmp")
    local run = util.join(ctx.build_dir, "run")
    for _, d in ipairs({ incdir, boostdir, libdir, docdir, wptdir, wptportdir,
                         vdir, home, tmp, run }) do fs.mkdirs(d) end
    ctx.env.HOME = home
    ctx.env.TMPDIR = tmp
    ctx.env.XDG_CONFIG_HOME = util.join(home, ".config")
    ctx.env.XDG_CACHE_HOME = util.join(home, ".cache")
    local old_path = tostring(ctx.env.PATH or "")
    local path_parts = { ctx.store.bin, "/usr/lib/llvm-23/bin", "/usr/bin", "/bin" }
    if old_path ~= "" then path_parts[#path_parts + 1] = old_path end
    ctx.env.PATH = table.concat(path_parts, ":")
    ctx.env.GCPKG_COMPILER_FLAGS = ""

    assert(fs.isfile(util.join(ctx.store.cache, CACHE_NAME)),
           "gcpkg: boost-url: source cache missing: " .. CACHE_NAME)
    assert(fs.isfile(util.join(boost_cmake, "BoostConfig.cmake")),
           "gcpkg: boost-url: official B2 BoostConfig.cmake missing")
    assert(fs.isfile(util.join(boost, "lib", "cmake", "boost_url-1.81.0",
                               "boost_url-config.cmake")),
           "gcpkg: boost-url: official boost_url CONFIG missing")

    -- Standalone URL header tree and the B2-built static library.
    ctx.exec({ "cp", "-a", util.join(ctx.src, "include", "boost", "url.hpp"),
               util.join(incdir, "boost", "url.hpp") },
             { cwd = ctx.src, log = ctx.log })
    ctx.exec({ "cp", "-a", util.join(ctx.src, "include", "boost", "url"),
               util.join(incdir, "boost", "url") },
             { cwd = ctx.src, log = ctx.log })
    local lib = r20.lib_file(ctx, "boost", "boost_url")
    ctx.exec({ "cp", "-a", lib, util.join(libdir, "libboost_url.a") },
             { cwd = ctx.src, log = ctx.log })
    assert(fs.isfile(util.join(incdir, "boost", "url", "src.hpp")),
           "gcpkg: boost-url: src.hpp not installed")
    assert(fs.isfile(util.join(libdir, "libboost_url.a")),
           "gcpkg: boost-url: libboost_url.a not installed")

    ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE_1_0.txt"),
               util.join(docdir, "LICENSE_1_0.txt") },
             { cwd = ctx.src, log = ctx.log })
    ctx.exec({ "cp", "-a", util.join(ctx.src, "README.md"),
               util.join(docdir, "README.md") },
             { cwd = ctx.src, log = ctx.log })

    -- Upstream WPT resources shipped in the tarball, plus the independent
    -- url-wpt-data port resources.  Both are installed for downstream users.
    for _, name in ipairs({ "setters_tests.json", "urltestdata.json" }) do
        local src = util.join(ctx.src, "test", "wpt", name)
        assert(fs.isfile(src), "gcpkg: boost-url: missing source WPT file " .. name)
        ctx.exec({ "cp", "-a", src, util.join(wptdir, name) },
                 { cwd = ctx.src, log = ctx.log })
    end
    for _, name in ipairs(WPT_FILES) do
        local src = util.join(wpt_port, name)
        assert(fs.isfile(src), "gcpkg: boost-url: missing url-wpt-data file " .. name)
        ctx.exec({ "cp", "-a", src, util.join(wptportdir, name) },
                 { cwd = ctx.src, log = ctx.log })
    end

    local vars = {
        SRC = ctx.src,
        BUILD = ctx.build_dir,
        WRAPPER_CXX = ctx.compiler.wrapper_cxx,
        WPT_WRAPPER = util.join(ctx.build_dir, "wpt_wrapper.cpp"),
    }
    local harness_src = util.join(ctx.build_dir, "harness", "src")
    local harness_build = util.join(ctx.build_dir, "harness-build")
    fs.mkdirs(harness_src)
    fs.write(util.join(harness_src, "CMakeLists.txt"), render(HARNESS_CMAKE, vars))
    fs.write(vars.WPT_WRAPPER, render(WPT_WRAPPER, vars))

    local prefixes = { ctx.prefix, boost, unordered, wpt }
    local cmake_prefix = table.concat(prefixes, ";")
    local common_defines = {
        CMAKE_CXX_COMPILER = ctx.compiler.wrapper_cxx,
        CMAKE_CXX_STANDARD = "17",
        CMAKE_CXX_STANDARD_REQUIRED = "ON",
        CMAKE_CXX_EXTENSIONS = "OFF",
        CMAKE_MAKE_PROGRAM = "/usr/bin/make",
        CMAKE_POLICY_VERSION_MINIMUM = "3.5",
        CMAKE_INSTALL_LIBDIR = "lib",
        CMAKE_INSTALL_INCLUDEDIR = "include",
        CMAKE_PREFIX_PATH = cmake_prefix,
        Boost_DIR = boost_cmake,
        CMAKE_FIND_PACKAGE_PREFER_CONFIG = "TRUE",
        CMAKE_FIND_USE_PACKAGE_REGISTRY = "OFF",
        CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY = "OFF",
        CMAKE_EXPORT_NO_PACKAGE_REGISTRY = "ON",
        CMAKE_DISABLE_FIND_PACKAGE_ICU = "ON",
        CMAKE_DISABLE_FIND_PACKAGE_Git = "ON",
        GIT_EXECUTABLE = "",
        PKG_CONFIG_EXECUTABLE = util.join(ctx.store.bin, "gcpkg-pkg-config"),
        Boost_USE_STATIC_LIBS = "ON",
        BUILD_SHARED_LIBS = "OFF",
        BUILD_TESTING = "ON",
        BOOST_URL_FIND_PACKAGE_BOOST = "ON",
        BOOST_URL_BUILD_TESTS = "ON",
        BOOST_URL_BUILD_EXAMPLES = "ON",
        CMAKE_EXE_LINKER_FLAGS = "-pthread",
    }

    local harness_result = cmake.all {
        src = harness_src, build_dir = harness_build, prefix = ctx.prefix,
        exec = ctx.exec, log = ctx.log,
        jobs = math.min(tonumber(ctx.jobs) or 4, 4),
        env = ctx.env, defines = common_defines, args = {},
    }

    local ctest_n, ctest_n_rc = ctx.capture(
        { "ctest", "--test-dir", harness_build, "-N" },
        { cwd = ctx.build_dir, env = ctx.env })
    assert(ctest_n_rc == 0, "gcpkg: boost-url: ctest -N failed")
    assert(ctest_n:find("Total Tests: 3", 1, true),
           "gcpkg: boost-url: expected three upstream ctest targets")
    fs.write(util.join(vdir, "ctest.N"), ctest_n)
    local ctest_out, ctest_rc = ctx.capture(
        { "ctest", "--test-dir", harness_build, "--output-on-failure" },
        { cwd = ctx.build_dir, env = ctx.env })
    fs.write(util.join(vdir, "ctest.log"), ctest_out)
    assert(ctest_rc == 0, "gcpkg: boost-url: upstream ctest failed")
    assert(ctest_out:find("100% tests passed, 0 tests failed out of 3", 1, true) or
           ctest_out:find("100% tests passed out of 3", 1, true),
           "gcpkg: boost-url: ctest did not report 3/3 pass")

    local function find_bin(name)
        local out, rc = ctx.capture({ "find", harness_build, "-type", "f", "-name", name },
                                   { cwd = ctx.build_dir, env = ctx.env })
        assert(rc == 0, "gcpkg: boost-url: find " .. name .. " failed")
        local p = first_line(out)
        assert(p ~= "" and fs.isfile(p), "gcpkg: boost-url: missing binary " .. name)
        return p
    end

    local finicky = find_bin("finicky")
    local finicky_out, finicky_rc = ctx.capture(
        { finicky, util.join(ctx.src, "example", "finicky", "config.json"),
          "http://www.example.com/a" },
        { cwd = ctx.build_dir, env = ctx.env })
    fs.write(util.join(vdir, "finicky.out"), finicky_out)
    assert(finicky_rc == 0, "gcpkg: boost-url: finicky example failed")
    assert(finicky_out:find("Safari", 1, true),
           "gcpkg: boost-url: finicky output mismatch")

    fs.write(util.join(run, "index.html"), "gcpkg boost-url route sample\n")
    local route = find_bin("route")
    local route_out, route_rc = ctx.capture(
        { route, "run/index.html", "run", "." },
        { cwd = ctx.build_dir, env = ctx.env })
    fs.write(util.join(vdir, "route.out"), route_out)
    assert(route_rc == 0, "gcpkg: boost-url: route example failed")
    assert(route_out:find("gcpkg boost-url route sample", 1, true),
           "gcpkg: boost-url: route output mismatch")

    local wpt_bin = find_bin("boost_url_wpt")
    local wpt_out, wpt_rc = ctx.capture(
        { wpt_bin, util.join(ctx.src, "test", "wpt", "setters_tests.json") },
        { cwd = ctx.build_dir, env = ctx.env })
    fs.write(util.join(vdir, "wpt.out"), wpt_out)
    assert(wpt_out ~= "", "gcpkg: boost-url: WPT example produced no output")
    -- Upstream WPT main is an example, not an upstream ctest; its known
    -- 1/28 protocol failure is recorded truthfully, never blacklisted.

    local consumer_src = util.join(vdir, "consumer-src")
    local consumer_build = util.join(vdir, "consumer-build")
    local consumer_prefix = util.join(vdir, "consumer-prefix")
    fs.mkdirs(consumer_src)
    fs.write(util.join(consumer_src, "CMakeLists.txt"), CONSUMER_CMAKE)
    fs.write(util.join(consumer_src, "main.cpp"), CONSUMER_CPP)
    local consumer_result = cmake.all {
        src = consumer_src, build_dir = consumer_build, prefix = consumer_prefix,
        exec = ctx.exec, log = ctx.log,
        jobs = math.min(tonumber(ctx.jobs) or 4, 4),
        env = ctx.env, defines = common_defines, args = {},
    }
    local consumer_out, consumer_rc = ctx.capture(
        { util.join(consumer_build, "consumer") },
        { cwd = vdir, env = ctx.env })
    assert(consumer_rc == 0, "gcpkg: boost-url: official CONFIG consumer failed")
    assert(consumer_out:find("gcpkg boost-url official CONFIG consumer ok=1", 1, true),
           "gcpkg: boost-url: official CONFIG consumer output mismatch")

    local common_cc = {
        includes = { incdir, boost_inc, unordered_inc },
        flags = { "-std=c++17", "-pthread" },
        defines = { "BOOST_URL_NO_LIB=1", "BOOST_ALL_NO_LIB=1" },
        cwd = vdir, outdir = util.join(vdir, "obj"),
        compiler = ctx.compiler.wrapper_cxx,
        exec = ctx.exec, record = ctx.record, log = ctx.log,
        tag = "boost-url", cxx = true,
    }
    local header_src = util.join(vdir, "header_sanity.cpp")
    fs.write(header_src, HEADER_SANITY)
    local header_bin = cc.executable(util.merge(common_cc, {
        sources = { header_src },
        output = util.join(vdir, "header_sanity"),
    }))
    local header_out, header_rc = ctx.capture({ header_bin },
                                              { cwd = vdir, env = ctx.env })
    assert(header_rc == 0, "gcpkg: boost-url: header-only sanity failed")
    assert(header_out:find("gcpkg boost-url header-only sanity ok=1", 1, true),
           "gcpkg: boost-url: header-only sanity output mismatch")

    local library_src = util.join(vdir, "library_sanity.cpp")
    fs.write(library_src, LIBRARY_SANITY)
    local library_bin = cc.executable(util.merge(common_cc, {
        sources = { library_src },
        libdirs = { libdir }, libs = { "boost_url" },
        output = util.join(vdir, "library_sanity"),
    }))
    local library_out, library_rc = ctx.capture({ library_bin },
                                                { cwd = vdir, env = ctx.env })
    assert(library_rc == 0, "gcpkg: boost-url: library-linked sanity failed")
    assert(library_out:find("gcpkg boost-url static sanity ok=1", 1, true),
           "gcpkg: boost-url: library-linked sanity output mismatch")

    fs.write(util.join(vdir, "boost-url-facts.txt"), table.concat({
        "policy=official_b2_boost_config_upstream_cmake_tests_examples_no_local_config",
        "boost_url_version=" .. VERSION,
        "source_cache=" .. CACHE_NAME,
        "source_sha=" .. SOURCE_SHA,
        "ada_competition=OFF", "ada_boost_url=OFF", "cpm_boost_url_shim=OFF",
        "official_config=YES", "local_config=NO",
        "ctest_tests=3", "ctest_rc=" .. ctest_rc,
        "ctest_filter=NONE", "test_number_blacklist=NONE",
        "examples=6", "finicky_rc=" .. finicky_rc, "route_rc=" .. route_rc,
        "wpt_is_example_not_ctest=YES", "wpt_program_rc=" .. wpt_rc,
        "consumer_rc=" .. consumer_rc,
        "header_sanity_rc=" .. header_rc, "library_sanity_rc=" .. library_rc,
        "source_patch=NO", "network_at_build=NO", "host_boost=NO", "host_icu=NO",
        "registry=OFF", "no_probe=YES",
        "",
    }, "\n"))

    return {
        includes = { incdir },
        libdirs = { libdir },
        libs = { "boost_url" },
        defines = { "BOOST_URL_NO_LIB=1", "BOOST_ALL_NO_LIB=1" },
        link_flags = {}, binaries = {},
        compdb_files = util.concat(harness_result.compdb_files or {},
                                   consumer_result.compdb_files or {}),
    }
end

return recipe.define {
    name = "boost-url",
    version = VERSION,
    license = "BSL-1.0",
    homepage = "https://github.com/boostorg/url",
    description = "Boost.URL 1.81 source port with B2-built library, official CONFIG, upstream tests/examples/WPT",
    source = {
        url = "https://codeload.github.com/boostorg/url/tar.gz/refs/tags/boost-1.81.0",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    build = build,
}
