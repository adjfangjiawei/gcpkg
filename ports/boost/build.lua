-- boost 1.81.0 -- gcpkg header/source port.
-- The upstream superproject release tarball is self-contained: its boost/
-- tree already includes Boost.URL (ada's benchmark competitor) and the
-- header-only Boost.System.  All writes stay inside the store.  No network
-- at configure time, no host library discovery, no library probes.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local BOOST_CONFIG = [==[
# gcpkg local Boost CONFIG (header-only Boost.System / Boost.URL).
get_filename_component(_BOOST_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(_BOOST_PREFIX "${_BOOST_PREFIX}" PATH)
get_filename_component(_BOOST_PREFIX "${_BOOST_PREFIX}" PATH)
get_filename_component(_BOOST_PREFIX "${_BOOST_PREFIX}" PATH)
if(_BOOST_PREFIX STREQUAL "/")
  set(_BOOST_PREFIX "")
endif()
set(Boost_FOUND TRUE)
set(Boost_VERSION "1.81.0")
set(Boost_VERSION_STRING "1.81.0")
set(Boost_INCLUDE_DIRS "${_BOOST_PREFIX}/include")
set(Boost_system_FOUND TRUE)
if(NOT TARGET Boost::system)
  add_library(Boost::system INTERFACE IMPORTED)
  set_target_properties(Boost::system PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_BOOST_PREFIX}/include")
endif()
set(_BOOST_PREFIX)
]==]

local BOOST_CONFIG_VERSION = [==[
set(PACKAGE_VERSION "1.81.0")
if(PACKAGE_FIND_VERSION VERSION_LESS_EQUAL PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
]==]

return recipe.define {
    name = "boost",
    version = "1.81.0",
    license = "BSL-1.0",
    homepage = "https://www.boost.org",
    description = "Boost C++ headers 1.81.0 (incl. Boost.System and Boost.URL)",
    source = {
        url = "https://archives.boost.io/release/1.81.0/source/boost_1_81_0.tar.gz",
        sha256 = "205666dea9f6a7cfed87c7a6dfbeb52a2c1b9de55712c9c1a87735d7181452b6",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local cmakedir = ctx.prefix .. "/lib/cmake/Boost"
        local docdir = ctx.prefix .. "/share/doc/boost"
        fs.mkdirs(incdir); fs.mkdirs(cmakedir); fs.mkdirs(ctx.build_dir)

        if on["headers"] then
            fs.mkdirs(incdir)
            -- cp -a of the whole upstream boost/ tree: no host paths, no
            -- generated symlink farm, no b2 bootstrap.
            ctx.exec({ "cp", "-a", ctx.src .. "/boost", incdir .. "/" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["cmake-package"] then
            fs.write(cmakedir .. "/BoostConfig.cmake", BOOST_CONFIG)
            fs.write(cmakedir .. "/BoostConfigVersion.cmake", BOOST_CONFIG_VERSION)
        end
        if on["license"] then
            fs.mkdirs(docdir)
            ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE_1_0.txt",
                       docdir .. "/LICENSE_1_0.txt" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["sanity"] then
            local probe = ctx.build_dir .. "/gcpkg_boost_probe.cpp"
            fs.write(probe, [[
#include <boost/system/error_code.hpp>
#include <boost/url.hpp>
int main() {
  boost::system::error_code ec;
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  return (ec.value() == 0 && r.has_value()) ? 0 : 1;
}
]])
            cc.compile {
                sources = { probe }, includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir, outdir = ctx.build_dir .. "/obj",
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "boost",
            }
        end
        return {
            includes = { incdir }, libdirs = { ctx.prefix .. "/lib" },
            libs = {}, binaries = {}, defines = {}, link_flags = {},
            compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = {},
        binaries = {},
    },
}
