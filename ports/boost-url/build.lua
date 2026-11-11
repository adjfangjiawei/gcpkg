-- boost-url boost-1.81.0 -- gcpkg source port for ada's Boost.URL competitor.
-- The pinned standalone tarball is installed into the store.  Boost headers
-- come from the source-built `boost` port via features.yaml requires; there is
-- no host package search, configure-time fetch or library-side platform probe.
-- Ada includes <boost/url/src.hpp> directly, so the header tree is the primary
-- artifact; the static library and CMake CONFIG support ordinary consumers.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local CONFIG = [==[
# gcpkg local boost_url CONFIG.  All paths are resolved from this CONFIG file.
get_filename_component(_BOOST_URL_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(_BOOST_URL_PREFIX "${_BOOST_URL_PREFIX}" PATH)
get_filename_component(_BOOST_URL_PREFIX "${_BOOST_URL_PREFIX}" PATH)
get_filename_component(_BOOST_URL_PREFIX "${_BOOST_URL_PREFIX}" PATH)
if(_BOOST_URL_PREFIX STREQUAL "/")
  set(_BOOST_URL_PREFIX "")
endif()
set(boost_url_FOUND TRUE)
set(BoostURL_VERSION "1.81.0")
set(boost_url_SOURCE_DIR "${_BOOST_URL_PREFIX}")
set(boost_url_INCLUDE_DIR "${_BOOST_URL_PREFIX}/include")
if(NOT TARGET boost_url)
  add_library(boost_url INTERFACE IMPORTED)
  set_target_properties(boost_url PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_BOOST_URL_PREFIX}/include")
endif()
if(EXISTS "${_BOOST_URL_PREFIX}/lib/libboost_url.a" AND NOT TARGET Boost::url)
  add_library(Boost::url STATIC IMPORTED)
  set_target_properties(Boost::url PROPERTIES
    IMPORTED_LOCATION "${_BOOST_URL_PREFIX}/lib/libboost_url.a"
    INTERFACE_INCLUDE_DIRECTORIES "${_BOOST_URL_PREFIX}/include")
endif()
set(_BOOST_URL_PREFIX)
]==]

local CONFIG_VERSION = [==[
set(PACKAGE_VERSION "1.81.0")
if(PACKAGE_FIND_VERSION VERSION_LESS_EQUAL PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
]==]

local function dep_include(ctx, name)
    local m = assert(ctx.dep(name),
                     "gcpkg: boost-url: missing dependency " .. name)
    local incs = m.includes or {}
    assert(#incs > 0,
           "gcpkg: boost-url: dependency " .. name .. " exports no include dir")
    return incs[1]
end

local function build(ctx)
    local on = ctx.features.enabled
    local boost_inc = dep_include(ctx, "boost")
    local incdir = ctx.prefix .. "/include"
    local libdir = ctx.prefix .. "/lib"
    local cmakedir = libdir .. "/cmake/boost_url"
    local docdir = ctx.prefix .. "/share/doc/boost-url"
    local objdir = ctx.build_dir .. "/obj"
    local bindir = ctx.build_dir .. "/bin"
    fs.mkdirs(incdir)
    fs.mkdirs(libdir)
    fs.mkdirs(objdir)
    fs.mkdirs(bindir)

    if on["headers"] then
        ctx.exec({ "cp", "-a", ctx.src .. "/include/boost", incdir .. "/" },
                 { cwd = ctx.src, log = ctx.log })
    end
    if on["license"] then
        fs.mkdirs(docdir)
        ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE_1_0.txt",
                   docdir .. "/LICENSE_1_0.txt" },
                 { cwd = ctx.src, log = ctx.log })
    end

    if on["library"] then
        local objs = cc.compile {
            sources = { ctx.src .. "/src/src.cpp" },
            includes = { incdir, boost_inc },
            flags = { "-std=c++17" },
            defines = { "BOOST_URL_NO_LIB=1", "BOOST_URL_STATIC_LINK=1" },
            cwd = ctx.build_dir, outdir = objdir,
            compiler = ctx.compiler.wrapper_cxx,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "boost-url",
        }
        assert(#objs == 1, "gcpkg: boost-url: expected one library object")
        ctx.exec({ "ar", "rcs", libdir .. "/libboost_url.a", objs[1] },
                 { cwd = ctx.build_dir, log = ctx.log })
    end

    if on["cmake-package"] then
        fs.mkdirs(cmakedir)
        fs.write(cmakedir .. "/boost_urlConfig.cmake", CONFIG)
        fs.write(cmakedir .. "/boost_urlConfigVersion.cmake", CONFIG_VERSION)
    end

    local common = {
        includes = { incdir, boost_inc },
        flags = { "-std=c++17" },
        defines = { "BOOST_URL_NO_LIB=1", "BOOST_URL_STATIC_LINK=1" },
        cwd = ctx.build_dir, outdir = objdir,
        compiler = ctx.compiler.wrapper_cxx,
        exec = ctx.exec, record = ctx.record, log = ctx.log,
        tag = "boost-url", cxx = true,
    }

    if on["sanity"] then
        local header_probe = ctx.build_dir .. "/boost_url_header_sanity.cpp"
        fs.write(header_probe, [==[
#include <boost/url/src.hpp>
#include <boost/system/error_code.hpp>
int main() {
  boost::system::error_code ec;
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  return (ec.value() == 0 && r.has_value()) ? 0 : 1;
}
]==])
        local header_bin = cc.executable(util.merge(common, {
            sources = { header_probe },
            output = bindir .. "/boost_url_header_sanity",
        }))
        ctx.exec({ header_bin },
                 { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

        if on["library"] then
            local library_probe = ctx.build_dir .. "/boost_url_library_sanity.cpp"
            fs.write(library_probe, [==[
#include <boost/url.hpp>
#include <boost/system/error_code.hpp>
int main() {
  boost::system::error_code ec;
  auto r = boost::urls::parse_uri("https://example.com/a?b=c");
  return (ec.value() == 0 && r.has_value()) ? 0 : 1;
}
]==])
            local library_bin = cc.executable(util.merge(common, {
                sources = { library_probe },
                output = bindir .. "/boost_url_library_sanity",
                libdirs = { libdir }, libs = { "boost_url" },
            }))
            ctx.exec({ library_bin },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        end
    end

    if on["examples"] then
        assert(on["library"],
               "gcpkg: boost-url: examples need the static library feature")
        local examples = {
            { "magnet", "example/magnet/magnet.cpp" },
            { "mailto", "example/mailto/mailto.cpp" },
            { "qrcode", "example/qrcode/qrcode.cpp" },
            { "suffix_list", "example/suffix_list/suffix_list.cpp" },
        }
        for _, ex in ipairs(examples) do
            cc.executable(util.merge(common, {
                sources = { ctx.src .. "/" .. ex[2] },
                output = bindir .. "/" .. ex[1],
                libdirs = { libdir }, libs = { "boost_url" },
            }))
        end
    end

    return {
        includes = { incdir },
        libdirs = { libdir },
        libs = on["library"] and { "boost_url" } or {},
        binaries = {},
        defines = on["library"]
            and { "BOOST_URL_NO_LIB=1", "BOOST_URL_STATIC_LINK=1" } or {},
        link_flags = {},
        compdb_files = {},
    }
end

return recipe.define {
    name = "boost-url",
    version = "boost-1.81.0",
    license = "BSL-1.0",
    homepage = "https://github.com/boostorg/url",
    description = "Boost.URL 1.81 source port used by ada benchmarks",
    source = {
        url = "https://codeload.github.com/boostorg/url/tar.gz/refs/tags/boost-1.81.0",
        sha256 = "71a2431da79ac1a5c4b11dc0e176f8b5f608fdac9221b61c70ea1cce378bf2fa",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "boost_url" },
        binaries = {},
    },
}
