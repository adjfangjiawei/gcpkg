-- ftest ae47011 -- R20 new-standard header-only port.
-- FTest is the C++98 single-header test framework that utfcpp's upstream test
-- suite includes as "extern/ftest/ftest.h".  In the utfcpp release tarball that
-- path is an unpopulated git submodule, so the framework is packaged here as a
-- real gcpkg port: consumers (utfcpp) get it from the package store instead of
-- downloading it, and nothing inside the consumer port probes or vendors it.
-- Upstream ships no build system and no options of its own: every switch below
-- is a gcpkg capability and every one of them performs a real action.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local function copy(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    if fs.isfile(src) then
        ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
    end
end

return recipe.define {
    name = "ftest",
    version = "ae47011",
    license = "BSL-1.0",
    homepage = "https://github.com/nemtrif/ftest",
    description = "FTest, a portable single-header C++98 testing framework",
    source = {
        url = "https://codeload.github.com/nemtrif/ftest/tar.gz/ae470119f0842b9d65b8bd2e5f0b6115259ffac0",
        sha256 = "c2dcc85b5f3ff151a12093ed20519e12cd748bf974d20e4c4cd2778de69219f3",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "ftest")
        local pcdir = util.join(libdir, "pkgconfig")
        local cmakedir = util.join(libdir, "cmake", "ftest")
        fs.mkdirs(ctx.build_dir)

        -- headers -------------------------------------------------------
        if on["headers"] then
            copy(ctx, util.join(ctx.src, "ftest.h"), util.join(incdir, "ftest.h"))
            -- utfcpp (and other upstreams) include "ftest/ftest.h"
            copy(ctx, util.join(ctx.src, "ftest.h"),
                 util.join(incdir, "ftest", "ftest.h"))
            assert(fs.isfile(util.join(incdir, "ftest.h")),
                   "gcpkg: ftest: ftest.h missing from the install tree")
        end

        -- tests: upstream registers tests/smoke.cpp with CTest -------------
        if on["tests"] then
            local bdir = util.join(ctx.build_dir, "tests")
            local env = ctx.env or {}
            local cmd = {
                "cmake", "-S", util.join(ctx.src, "tests"), "-B", bdir,
                "-DCMAKE_BUILD_TYPE=Release",
                "-DCMAKE_CXX_COMPILER=" .. ctx.compiler.wrapper_cxx,
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
            }
            local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
            if fs.isfile(noTry) then
                cmd[#cmd + 1] = "-DCMAKE_PROJECT_INCLUDE=" .. noTry
            end
            assert(ctx.exec(cmd, { cwd = ctx.src, env = env, log = ctx.log }) == 0,
                   "gcpkg: ftest: configuring the upstream test project failed")
            assert(ctx.exec({ "cmake", "--build", bdir, "--parallel",
                              tostring(ctx.jobs or 8) },
                            { cwd = ctx.src, env = env, log = ctx.log }) == 0,
                   "gcpkg: ftest: building the upstream test project failed")
            local out = util.join(ctx.build_dir, "ctest.out")
            local script = "ctest --output-on-failure > " .. out .. " 2>&1; echo $? > " ..
                           out .. ".rc"
            ctx.exec({ "sh", "-c", script }, { cwd = bdir, env = env, log = ctx.log })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out), "gcpkg: ftest: missing ctest output")
            assert(not text:find("No tests were found", 1, true),
                   "gcpkg: ftest: ctest found no registered tests")
            assert(text:find("100% tests passed", 1, true),
                   "gcpkg: ftest: upstream smoke suite did not pass: " .. text)
            assert(rc == "0", "gcpkg: ftest: ctest exited with " .. rc .. ": " .. text)
            -- the driver output of the smoke program must show a passing run
            local smoke = util.join(bdir, "smoke")
            local sout = util.join(ctx.build_dir, "ftest-smoke.out")
            ctx.exec({ "sh", "-c", smoke .. " > " .. sout .. " 2>&1" },
                     { cwd = bdir, env = env, log = ctx.log })
            local stext = assert(fs.read(sout), "gcpkg: ftest: missing smoke output")
            assert(stext:find("[==========] Running", 1, true) and
                   stext:find("[  PASSED  ]", 1, true) and
                   not stext:find("[  FAILED  ]", 1, true),
                   "gcpkg: ftest: the upstream driver did not report a clean run: " .. stext)
        end

        -- sanity: a consumer using the INSTALLED header --------------------
        if on["sanity"] then
            assert(on["headers"], "gcpkg: ftest: sanity needs headers")
            local csrc = util.join(ctx.build_dir, "ftest_sanity.cpp")
            -- ftest.h supplies main() itself (it forwards to the test driver),
            -- so the consumer only declares tests and prints through a test.
            fs.write(csrc, [==[
#include <ftest.h>

TEST(gcpkg_consumer, utf8_free_arithmetic) {
    int a = 40;
    EXPECT_EQ(a + 2, 42);
    EXPECT_NE(a, 42);
}

TEST(gcpkg_consumer, strings) {
    EXPECT_STREQ("gcpkg", "gcpkg");
}
]==])
            local objs = cc.compile {
                sources = { csrc },
                includes = { incdir },
                defines = {},
                flags = { "-std=c++98", "-O2" },
                cwd = ctx.build_dir, outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "ftest",
            }
            local exe = util.join(ctx.build_dir, "ftest_sanity")
            cc.link { objects = objs, output = exe,
                      compiler = ctx.compiler.wrapper_cxx, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: ftest: missing sanity output")
            assert(text:find("[==========] Running 2 tests", 1, true),
                   "gcpkg: ftest: the consumer's own tests did not run: " .. text)
            assert(text:find("[  PASSED  ] 2 tests", 1, true),
                   "gcpkg: ftest: consumer assertions failed: " .. text)
            assert(not text:find("[  FAILED  ]", 1, true),
                   "gcpkg: ftest: consumer reported failures: " .. text)
        end

        -- pkg-config ------------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: ftest
Description: FTest, a portable single-header C++98 testing framework
Version: ae47011
Cflags: -I${includedir}
]==]
            fs.write(util.join(pcdir, "ftest.pc"), (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package ---------------------------------------------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(util.join(cmakedir, "ftestConfig.cmake"), [==[
get_filename_component(_FTEST_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET ftest::ftest)
  add_library(ftest::ftest INTERFACE IMPORTED)
  set_target_properties(ftest::ftest PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_FTEST_PREFIX}/include")
endif()
set(ftest_FOUND TRUE)
]==])
            fs.write(util.join(cmakedir, "ftestConfigVersion.cmake"), [==[
set(PACKAGE_VERSION "ae47011")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- docs / license ----------------------------------------------------
        if on["docs"] then
            copy(ctx, util.join(ctx.src, "README.md"), util.join(docdir, "README.md"))
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: ftest: LICENSE missing")
            copy(ctx, util.join(ctx.src, "LICENSE"), util.join(docdir, "LICENSE"))
        end

        -- The manifest records what the build function RETURNS, so the export
        -- list is produced here (a declarative exports= table next to a custom
        -- build() is ignored by the recipe layer).
        return {
            includes = { util.join(ctx.prefix, "include") },
            libdirs = {},
            libs = {},
            binaries = {},
        }
    end,
}
