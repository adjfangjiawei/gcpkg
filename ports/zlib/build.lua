-- zlib 1.3.1 -- R20 new-standard re-audit of the curl L0 dependency chain.
-- Declarative recipe.cmake keeps the framework's absolute-no-probe injection,
-- shared per-triplet facts and CMAKE_PREFIX_PATH; positive features.yaml args
-- are appended last (dedup_defines) so they override any recipe default.
-- post_install runs the REAL upstream ctest suite and a real C consumer.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local ZLIB_LICENSE = [==[
zlib License

Copyright (c) 1995-2024 Jean-loup Gailly and Mark Adler

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
]==]

return recipe.cmake {
    name = "zlib",
    version = "1.3.1",
    description = "General-purpose DEFLATE compression library (shared + static)",
    license = "Zlib",
    homepage = "https://zlib.net",
    source = {
        url = "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz",
        sha256 = "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23",
        strip = 1,
    },
    -- L0: no gcpkg dependencies. Dynamic requires live in features.yaml.
    dependencies = {},
    cmake = {
        defines = {},
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "z" },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local prefix = ctx.prefix
        local libdir = util.join(prefix, "lib")
        if not fs.isfile(util.join(libdir, "libz.so")) and
           fs.isdir(util.join(prefix, "lib64")) then
            libdir = util.join(prefix, "lib64")
        end
        local incdir = util.join(prefix, "include")
        local docdir = util.join(prefix, "share", "doc", "zlib")
        local cmakedir = util.join(libdir, "cmake", "zlib")
        fs.mkdirs(docdir)

        -- library / headers / pkgconfig: assert the real installed artifacts.
        if on["library"] then
            assert(fs.isfile(util.join(libdir, "libz.so")) or
                   fs.isfile(util.join(libdir, "libz.so.1")),
                   "gcpkg: zlib: shared libz.so missing")
            assert(fs.isfile(util.join(libdir, "libz.a")),
                   "gcpkg: zlib: static libz.a missing")
        end
        if on["headers"] then
            assert(fs.isfile(util.join(incdir, "zlib.h")),
                   "gcpkg: zlib: zlib.h missing")
            assert(fs.isfile(util.join(incdir, "zconf.h")),
                   "gcpkg: zlib: zconf.h missing")
        end
        if on["pkgconfig"] then
            assert(fs.isfile(util.join(libdir, "pkgconfig", "zlib.pc")) or
                   fs.isfile(util.join(prefix, "share", "pkgconfig", "zlib.pc")),
                   "gcpkg: zlib: zlib.pc missing")
        end

        -- docs / license: install real upstream files, no fabrication.
        if on["docs"] then
            for _, name in ipairs({ "README", "FAQ", "INDEX", "ChangeLog" }) do
                local src = util.join(ctx.src, name)
                if fs.isfile(src) then
                    ctx.exec({ "cp", "-a", src, util.join(docdir, name) },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            fs.write(util.join(docdir, "LICENSE"), ZLIB_LICENSE)
        end

        -- CONFIG package so a dependent CMake project can find_package(zlib).
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(util.join(cmakedir, "zlibConfig.cmake"), [==[
get_filename_component(_ZLIB_PREFIX "${CMAKE_CURRENT_LIST_DIR}" PATH)
get_filename_component(_ZLIB_PREFIX "${_ZLIB_PREFIX}" PATH)
get_filename_component(_ZLIB_PREFIX "${_ZLIB_PREFIX}" PATH)
if(NOT TARGET zlib)
    add_library(zlib SHARED IMPORTED)
    if(EXISTS "${_ZLIB_PREFIX}/lib/libz.so")
        set(_ZLIB_IMPORTED "${_ZLIB_PREFIX}/lib/libz.so")
    else()
        set(_ZLIB_IMPORTED "${_ZLIB_PREFIX}/lib64/libz.so")
    endif()
    set_target_properties(zlib PROPERTIES
        IMPORTED_LOCATION "${_ZLIB_IMPORTED}"
        INTERFACE_INCLUDE_DIRECTORIES "${_ZLIB_PREFIX}/include")
endif()
set(zlib_FOUND TRUE)
]==])
            fs.write(util.join(cmakedir, "zlibConfigVersion.cmake"), [==[
set(PACKAGE_VERSION "1.3.1")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
    set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
    set(PACKAGE_VERSION_COMPATIBLE TRUE)
    if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
        set(PACKAGE_VERSION_EXACT TRUE)
    endif()
endif()
]==])
        end

        -- tests: run the actual registered ctest targets from the build tree.
        if on["tests"] then
            assert(on["examples"],
                   "gcpkg: zlib: ctest needs the examples feature")
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c", "ctest --output-on-failure > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: zlib: missing ctest output")
            assert(not result:find("No tests were found", 1, true),
                   "gcpkg: zlib: ctest found no registered tests")
            assert(result:find("100% tests passed", 1, true),
                   "gcpkg: zlib: ctest did not pass")
        end

        -- sanity: compile and run a real consumer linked to the installed libz.
        if on["sanity"] then
            assert(on["library"] and on["headers"],
                   "gcpkg: zlib: sanity needs library and headers")
            local src = util.join(ctx.build_dir, "zlib_sanity.c")
            fs.write(src, [==[
#include <zlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    const char *msg = "gcpkg zlib newstd round trip 1234567890";
    uLongf srcLen = (uLongf)(strlen(msg) + 1);
    uLongf cap = compressBound(srcLen);
    unsigned char *buf = (unsigned char *)malloc(cap);
    if (!buf) return 2;
    if (compress(buf, &cap, (const Bytef *)msg, srcLen) != Z_OK) return 3;
    char back[256];
    uLongf backLen = (uLongf)sizeof(back);
    if (uncompress((Bytef *)back, &backLen, buf, cap) != Z_OK) return 4;
    if (backLen != srcLen || strcmp(back, msg) != 0) return 5;
    printf("gcpkg zlib ok: %s / version %s\n", back, zlibVersion());
    free(buf);
    return 0;
}
]==])
            local bin = cc.executable {
                sources = { src },
                includes = { incdir },
                flags = { "-std=c11" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "zlib", cxx = false,
                output = util.join(ctx.build_dir, "zlib_sanity"),
                libdirs = { libdir }, libs = { "z" },
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", bin .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: zlib: missing sanity output")
            assert(result:find("gcpkg zlib ok", 1, true),
                   "gcpkg: zlib: C consumer did not run")
        end
    end,
}
