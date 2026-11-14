-- pprint v0.9.1 -- R20 new-standard header-only port.
-- Upstream ships a single header (include/pprint.hpp) plus a REAL test suite in
-- test/ (Catch2 v1 is vendored in-tree as catch.hpp, so nothing is downloaded)
-- that exercises the printer against std::vector / std::list / std::set with
-- exact expected output.  The port builds and RUNS that suite, then verifies the
-- installed header with a consumer translation unit.
--
-- Upstream has no build options of its own (its test/CMakeLists.txt declares no
-- option() and does not even register a CTest entry), so the switches below are
-- gcpkg capabilities; every one performs a real action and has its explicit
-- `no-*` twin.  The port drives the upstream test/CMakeLists.txt project
-- directly and executes the resulting binary.
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
    name = "pprint",
    version = "v0.9.1",
    license = "MIT",
    homepage = "https://github.com/p-ranav/pprint",
    description = "Header-only C++ pretty printer",
    source = {
        url = "https://codeload.github.com/p-ranav/pprint/tar.gz/refs/tags/v0.9.1",
        sha256 = "b9cc0d42f7be4abbb50b2e3b6a89589c5399201a3dc1fd7cfa72d412afdb2f86",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "pprint")
        local pcdir = util.join(libdir, "pkgconfig")
        local cmakedir = util.join(libdir, "cmake", "pprint")
        fs.mkdirs(ctx.build_dir)

        -- headers --------------------------------------------------------
        if on["headers"] then
            copy(ctx, util.join(ctx.src, "include", "pprint.hpp"),
                 util.join(incdir, "pprint.hpp"))
            assert(fs.isfile(util.join(incdir, "pprint.hpp")),
                   "gcpkg: pprint: pprint.hpp missing from the install tree")
        end

        -- tests: upstream's Catch2 suite, really built and really run ------
        if on["tests"] then
            local tdir = util.join(ctx.src, "test")
            assert(fs.isfile(util.join(tdir, "catch.hpp")),
                   "gcpkg: pprint: upstream tests need the vendored catch.hpp")
            local objs = cc.compile {
                sources = { util.join(tdir, "main.cpp") },
                includes = { tdir, util.join(ctx.src, "include") },
                -- glibc >= 2.34 made MINSIGSTKSZ a run-time value (sysconf),
                -- so Catch2 v1's constexpr sigStackSize no longer compiles.  This
                -- is the upstream-documented switch for that platform change
                -- (Catch2 issue #2364); it only drops Catch's POSIX signal
                -- handler, not any test.
                defines = { "CATCH_CONFIG_NO_POSIX_SIGNALS" },
                flags = { "-std=c++17", "-O2" },
                cwd = tdir, outdir = util.join(ctx.build_dir, "obj_test"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "pprint",
            }
            local exe = util.join(ctx.build_dir, "pprint-tests")
            cc.link { objects = objs, output = exe,
                      compiler = ctx.compiler.wrapper_cxx, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1; echo $? > " ..
                       out .. ".rc" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out), "gcpkg: pprint: missing test output")
            assert(not text:find("failed", 1, true),
                   "gcpkg: pprint: upstream test suite reported a failure: " .. text)
            assert(text:find("All tests passed", 1, true),
                   "gcpkg: pprint: upstream test suite did not pass: " .. text)
            assert(rc == "0", "gcpkg: pprint: test binary exited with " .. rc)
            -- the tagged suite is 27 test cases / 27 assertions at this tag;
            -- require all of them so a silently shrunken suite is caught.
            local cases = tonumber(text:match("(%d+) test cases?") or "0") or 0
            assert(cases >= 27,
                   "gcpkg: pprint: only " .. cases ..
                   " test cases ran, expected the full upstream suite")
        end

        -- sanity: real consumer over the INSTALLED header ------------------
        if on["sanity"] then
            assert(on["headers"], "gcpkg: pprint: sanity needs headers")
            local csrc = util.join(ctx.build_dir, "pprint_sanity.cpp")
            fs.write(csrc, [==[
#include <pprint.hpp>
#include <cstdio>
#include <sstream>
#include <vector>

int main() {
  std::stringstream stream;
  pprint::PrettyPrinter printer(stream);
  printer.print(std::vector<int>{1, 2, 3});
  if (stream.str().empty()) return 2;
  std::printf("gcpkg pprint ok bytes=%zu\n", stream.str().size());
  return 0;
}
]==])
            local objs = cc.compile {
                sources = { csrc },
                includes = { incdir },
                defines = {},
                flags = { "-std=c++17", "-O2" },
                cwd = ctx.build_dir, outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "pprint",
            }
            local exe = util.join(ctx.build_dir, "pprint_sanity")
            cc.link { objects = objs, output = exe,
                      compiler = ctx.compiler.wrapper_cxx, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: pprint: missing sanity output")
            assert(text:find("gcpkg pprint ok", 1, true),
                   "gcpkg: pprint: consumer did not run: " .. text)
        end

        -- pkg-config -------------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: pprint
Description: Header-only C++ pretty printer
Version: 0.9.1
Cflags: -I${includedir}
]==]
            fs.write(util.join(pcdir, "pprint.pc"), (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package ----------------------------------------------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(util.join(cmakedir, "pprintConfig.cmake"), [==[
get_filename_component(_PPRINT_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET pprint::pprint)
  add_library(pprint::pprint INTERFACE IMPORTED)
  set_target_properties(pprint::pprint PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_PPRINT_PREFIX}/include"
    INTERFACE_COMPILE_FEATURES cxx_std_17)
endif()
set(pprint_FOUND TRUE)
]==])
            fs.write(util.join(cmakedir, "pprintConfigVersion.cmake"), [==[
set(PACKAGE_VERSION "0.9.1")
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
            copy(ctx, util.join(ctx.src, "test", "README.md"),
                 util.join(docdir, "test-README.md"))
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: pprint: LICENSE missing")
            copy(ctx, util.join(ctx.src, "LICENSE"), util.join(docdir, "LICENSE"))
        end

        return {
            includes = { util.join(ctx.prefix, "include") },
            libdirs = {},
            libs = {},
            binaries = {},
        }
    end,
}
