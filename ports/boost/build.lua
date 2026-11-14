-- boost 1.81.0 -- gcpkg source port, built by upstream B2.
-- No host Boost, no host ICU, no hand-written CMake CONFIG, no source patch.
-- bootstrap.sh generates the B2 engine; project-config.jam is the ordinary
-- B2 build configuration and points at gcpkg's instrumented clang wrappers.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local cmake = require("gcpkg.build.cmake")
local r20 = require("gcpkg.r20")

local VERSION = "1.81.0"
local CACHE_NAME = "boost-1.81.0-boost_1_81_0.tar.gz"
local SOURCE_SHA = "205666dea9f6a7cfed87c7a6dfbeb52a2c1b9de55712c9c1a87735d7181452b6"
local LIBS = { "boost_url", "boost_json", "boost_regex",
               "boost_filesystem", "boost_container", "boost_system",
               "boost_atomic" }

local function render(s, vars)
    return (s:gsub("@@([%w_]+)@@", function(k)
        local v = vars[k]
        assert(v ~= nil, "gcpkg: boost: missing template variable " .. k)
        return tostring(v)
    end))
end

local PROJECT_CONFIG = [==[
# gcpkg B2 source build: upstream bootstrap output replaced by the ordinary
# project-config.jam so every compile uses the instrumented clang wrappers.
import option ;
import feature ;

using clang : 23 : "@@WRAPPER_CXX@@" : <cxxflags>"-std=c++17" <cflags>"-std=c11" ;

project : default-build <toolset>clang-23 ;

libraries = --with-container --with-filesystem --with-json --with-regex --with-system --with-url ;

option.set prefix : @@PREFIX@@ ;
option.set exec-prefix : @@PREFIX@@ ;
option.set libdir : @@PREFIX@@/lib ;
option.set includedir : @@PREFIX@@/include ;
option.set keep-going : false ;
]==]

local CONSUMER_CMAKE = [==[
cmake_minimum_required(VERSION 3.16)
cmake_policy(SET CMP0167 NEW)
project(gcpkg_boost_official_consumer LANGUAGES CXX)
set(Boost_USE_STATIC_LIBS ON)
find_package(Boost 1.81.0 CONFIG REQUIRED COMPONENTS container filesystem json regex system url)
if(NOT TARGET Boost::unordered)
  add_library(Boost::unordered INTERFACE IMPORTED)
  set_target_properties(Boost::unordered PROPERTIES INTERFACE_LINK_LIBRARIES Boost::headers)
endif()
add_executable(consumer main.cpp)
target_compile_features(consumer PRIVATE cxx_std_17)
target_link_libraries(consumer PRIVATE
  Boost::url Boost::container Boost::filesystem Boost::json Boost::regex
  Boost::system Boost::unordered Boost::headers)
]==]

local CONSUMER_CPP = [==[
#include <boost/url.hpp>
#include <boost/url/parse.hpp>
#include <boost/json.hpp>
#include <boost/regex.hpp>
#include <boost/filesystem/path.hpp>
#include <boost/container/vector.hpp>
#include <boost/unordered_map.hpp>
#include <boost/system/error_code.hpp>
#include <iostream>
int main() {
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  boost::json::value j = boost::json::parse("{\"ok\":true}");
  boost::regex re("boost-[a-z-]+");
  boost::container::vector<int> v{1, 2, 3};
  boost::unordered_map<int, int> m; m[1] = 2;
  boost::filesystem::path p("/a");
  boost::system::error_code ec;
  bool ok = r.has_value() && j.at("ok").as_bool() &&
            boost::regex_match("boost-url", re) && v.size() == 3 &&
            m.at(1) == 2 && !p.empty() && ec.value() == 0;
  std::cout << "gcpkg official Boost B2 consumer ok=" << (ok ? 1 : 0) << "\n";
  return ok ? 0 : 1;
}
]==]

local DIRECT_SANITY = [==[
#include <boost/url.hpp>
#include <boost/url/parse.hpp>
#include <boost/json.hpp>
#include <boost/regex.hpp>
#include <boost/container/vector.hpp>
#include <boost/unordered_map.hpp>
#include <iostream>
int main() {
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  boost::json::value j = boost::json::parse("{\"ok\":true}");
  boost::regex re("boost-[a-z-]+");
  boost::container::vector<int> v{1, 2, 3};
  boost::unordered_map<int, int> m; m[1] = 2;
  bool ok = r.has_value() && j.at("ok").as_bool() &&
            boost::regex_match("boost-url", re) && v.size() == 3 && m.at(1) == 2;
  std::cout << "gcpkg direct Boost sanity ok=" << (ok ? 1 : 0) << "\n";
  return ok ? 0 : 1;
}
]==]

local function build(ctx)
    local on = ctx.features.enabled
    for _, k in ipairs({ "headers", "container", "filesystem", "json", "regex",
                         "system", "url", "cmake-package", "sanity", "license" }) do
        assert(on[k], "gcpkg: boost: mandatory capability OFF: " .. k)
    end
    r20.restrict_pkgconfig(ctx)

    local home = util.join(ctx.build_dir, "home")
    local tmp = util.join(ctx.build_dir, "tmp")
    local b2dir = util.join(ctx.build_dir, "b2")
    local vdir = util.join(ctx.build_dir, "verify")
    fs.mkdirs(home); fs.mkdirs(tmp); fs.mkdirs(b2dir); fs.mkdirs(vdir)
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
           "gcpkg: boost: source cache missing: " .. CACHE_NAME)
    assert(fs.isfile(util.join(ctx.src, "bootstrap.sh")),
           "gcpkg: boost: upstream bootstrap.sh missing")
    assert(fs.isfile(util.join(ctx.src, "Jamroot")),
           "gcpkg: boost: upstream Jamroot missing")

    local bootstrap = ctx.exec({ "/usr/bin/timeout", "600", "./bootstrap.sh", "--without-icu" },
                               { cwd = ctx.src, log = ctx.log })
    assert(bootstrap == 0, "gcpkg: boost: bootstrap.sh failed")
    assert(fs.isfile(util.join(ctx.src, "b2")), "gcpkg: boost: b2 engine missing")

    local vars = {
        WRAPPER_CXX = ctx.compiler.wrapper_cxx,
        PREFIX = ctx.prefix,
        BUILD = ctx.build_dir,
        JOBS = tostring(math.min(tonumber(ctx.jobs) or 4, 4)),
    }
    fs.write(util.join(ctx.src, "project-config.jam"), render(PROJECT_CONFIG, vars))

    local cmd = {
        "/usr/bin/timeout", "1200", "./b2",
        "--ignore-site-config", "--debug-configuration",
        "--build-dir=" .. b2dir,
        "--prefix=" .. ctx.prefix,
        "--includedir=" .. util.join(ctx.prefix, "include"),
        "--libdir=" .. util.join(ctx.prefix, "lib"),
        "--cmakedir=" .. util.join(ctx.prefix, "lib", "cmake"),
        "--layout=system", "--disable-icu",
        "--with-container", "--with-filesystem", "--with-json",
        "--with-regex", "--with-system", "--with-url",
        "toolset=clang-23", "link=static", "runtime-link=shared",
        "threading=multi", "variant=release", "cxxflags=-std=c++17",
        "define=BOOST_ALL_NO_LIB=1", "-j" .. vars.JOBS, "install",
    }
    local b2rc = ctx.exec(cmd, { cwd = ctx.src, log = ctx.log })
    assert(b2rc == 0, "gcpkg: boost: b2 install failed")

    for _, lib in ipairs(LIBS) do
        assert(fs.isfile(util.join(ctx.prefix, "lib", "lib" .. lib .. ".a")),
               "gcpkg: boost: missing B2 library lib" .. lib .. ".a")
    end
    local boost_cmake = util.join(ctx.prefix, "lib", "cmake", "Boost-1.81.0")
    assert(fs.isfile(util.join(boost_cmake, "BoostConfig.cmake")),
           "gcpkg: boost: official BoostConfig.cmake missing")
    assert(fs.isfile(util.join(ctx.prefix, "lib", "cmake",
                               "boost_url-1.81.0", "boost_url-config.cmake")),
           "gcpkg: boost: official boost_url CONFIG missing")

    local docdir = util.join(ctx.prefix, "share", "doc", "boost")
    fs.mkdirs(docdir)
    ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE_1_0.txt"),
               util.join(docdir, "LICENSE_1_0.txt") },
             { cwd = ctx.src, log = ctx.log })

    local consumer_src = util.join(vdir, "consumer-src")
    local consumer_build = util.join(vdir, "consumer-build")
    local consumer_prefix = util.join(vdir, "consumer-prefix")
    fs.mkdirs(consumer_src)
    fs.write(util.join(consumer_src, "CMakeLists.txt"), CONSUMER_CMAKE)
    fs.write(util.join(consumer_src, "main.cpp"), CONSUMER_CPP)

    local consumer_result = cmake.all {
        src = consumer_src, build_dir = consumer_build, prefix = consumer_prefix,
        exec = ctx.exec, log = ctx.log, jobs = math.min(tonumber(ctx.jobs) or 4, 4),
        env = ctx.env,
        defines = {
            CMAKE_CXX_COMPILER = ctx.compiler.wrapper_cxx,
            CMAKE_CXX_STANDARD = "17",
            CMAKE_CXX_STANDARD_REQUIRED = "ON",
            CMAKE_CXX_EXTENSIONS = "OFF",
            CMAKE_MAKE_PROGRAM = "/usr/bin/make",
            CMAKE_POLICY_VERSION_MINIMUM = "3.5",
            CMAKE_INSTALL_LIBDIR = "lib",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_PREFIX_PATH = ctx.prefix,
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
            CMAKE_EXE_LINKER_FLAGS = "-pthread",
        },
        args = {},
    }
    local consumer_out, consumer_rc = ctx.capture(
        { util.join(consumer_build, "consumer") },
        { cwd = vdir, env = ctx.env })
    assert(consumer_rc == 0, "gcpkg: boost: official CMake consumer failed")
    assert(consumer_out:find("gcpkg official Boost B2 consumer ok=1", 1, true),
           "gcpkg: boost: official CMake consumer output mismatch")

    local direct = util.join(vdir, "boost_direct_sanity.cpp")
    fs.write(direct, DIRECT_SANITY)
    local direct_bin = cc.executable {
        sources = { direct },
        includes = { util.join(ctx.prefix, "include") },
        flags = { "-std=c++17", "-pthread" },
        defines = { "BOOST_ALL_NO_LIB=1" },
        libdirs = { util.join(ctx.prefix, "lib") },
        libs = LIBS,
        cwd = vdir, outdir = util.join(vdir, "obj"),
        compiler = ctx.compiler.wrapper_cxx,
        exec = ctx.exec, record = ctx.record, log = ctx.log,
        tag = "boost", cxx = true,
        output = util.join(vdir, "boost_direct_sanity"),
    }
    local direct_out, direct_rc = ctx.capture({ direct_bin },
                                              { cwd = vdir, env = ctx.env })
    assert(direct_rc == 0, "gcpkg: boost: direct sanity failed")
    assert(direct_out:find("gcpkg direct Boost sanity ok=1", 1, true),
           "gcpkg: boost: direct sanity output mismatch")

    fs.write(util.join(vdir, "boost-facts.txt"), table.concat({
        "policy=official_b2_install_no_local_config_offline_no_host_icu",
        "boost_version=" .. VERSION,
        "source_cache=" .. CACHE_NAME,
        "source_sha=" .. SOURCE_SHA,
        "b2_rc=" .. b2rc,
        "official_config=YES", "local_config=NO",
        "consumer_rc=" .. consumer_rc,
        "direct_sanity_rc=" .. direct_rc,
        "libraries=" .. table.concat(LIBS, ","),
        "icu=OFF", "registry=OFF", "network_at_build=NO",
        "source_patch=NO", "no_probe=YES",
        "",
    }, "\n"))

    return {
        includes = { util.join(ctx.prefix, "include") },
        libdirs = { util.join(ctx.prefix, "lib") },
        libs = LIBS,
        defines = { "BOOST_ALL_NO_LIB=1" },
        link_flags = {}, binaries = {},
        compdb_files = consumer_result.compdb_files or {},
    }
end

return recipe.define {
    name = "boost",
    version = VERSION,
    license = "BSL-1.0",
    homepage = "https://www.boost.org",
    description = "Boost 1.81.0 source-built B2 components incl. Boost.URL and official CMake CONFIG",
    source = {
        url = "https://archives.boost.io/release/1.81.0/source/boost_1_81_0.tar.gz",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    build = build,
}
