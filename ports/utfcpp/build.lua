-- utfcpp v4.0.6 -- R20 new-standard header-only port.
-- Upstream is a plain "install the source/ directory" library, but it ships a
-- REAL test project in tests/ (six C++98/11/17/20 programs driving the checked,
-- unchecked and checked-iterator APIs, registered with CTest).  The port builds
-- and RUNS that suite instead of compiling a synthetic probe, and then verifies
-- the installed tree with a consumer translation unit.
--
-- Dependency handling: tests/*.cpp include "../extern/ftest/ftest.h".  In the
-- upstream release tarball extern/ftest is an UNPOPULATED git submodule - i.e.
-- the upstream way of getting it is a download.  The port therefore declares
-- `ftest` as a source-built gcpkg port (features.yaml requires:) and
-- materialises the missing submodule directory from the package store.  Nothing
-- is downloaded here and nothing is probed.
--
-- Upstream's root CMakeLists.txt exposes no option() switch at all, so the
-- switches below are gcpkg capabilities; each one performs a real action and is
-- paired with its explicit opt-out.
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
    name = "utfcpp",
    version = "v4.0.6",
    license = "BSL-1.0",
    homepage = "https://github.com/nemtrif/utfcpp",
    description = "UTF-8 with C++ header-only library",
    source = {
        url = "https://codeload.github.com/nemtrif/utfcpp/tar.gz/refs/tags/v4.0.6",
        sha256 = "6920a6a5d6a04b9a89b2a89af7132f8acefd46e0c2a7b190350539e9213816c0",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "utfcpp")
        local pcdir = util.join(libdir, "pkgconfig")
        local cmakedir = util.join(libdir, "cmake", "utf8cpp")
        fs.mkdirs(ctx.build_dir)

        -- headers: the layout upstream's README documents (-I source) -----
        if on["headers"] then
            copy(ctx, util.join(ctx.src, "source", "utf8.h"),
                 util.join(incdir, "utf8.h"))
            for _, h in ipairs({ "checked.h", "core.h", "cpp11.h", "cpp17.h",
                                 "cpp20.h", "unchecked.h" }) do
                copy(ctx, util.join(ctx.src, "source", "utf8", h),
                     util.join(incdir, "utf8", h))
            end
            for _, h in ipairs({ "utf8.h", "utf8/core.h", "utf8/unchecked.h",
                                 "utf8/checked.h", "utf8/cpp17.h" }) do
                assert(fs.isfile(util.join(incdir, h)),
                       "gcpkg: utfcpp: missing installed header " .. h)
            end
        end

        -- the layout produced by upstream's own `cmake --install` ----------
        if on["utf8cpp-layout"] then
            local up = util.join(incdir, "utf8cpp")
            copy(ctx, util.join(ctx.src, "source", "utf8.h"),
                 util.join(up, "utf8.h"))
            for _, h in ipairs({ "checked.h", "core.h", "cpp11.h", "cpp17.h",
                                 "cpp20.h", "unchecked.h" }) do
                copy(ctx, util.join(ctx.src, "source", "utf8", h),
                     util.join(up, "utf8", h))
            end
            assert(fs.isfile(util.join(up, "utf8.h")),
                   "gcpkg: utfcpp: upstream install layout missing")
        end

        -- tests: the upstream CTest suite, really built and really run ----
        if on["tests"] then
            local dep = ctx.dep("ftest")
            assert(dep and dep.includes and #dep.includes > 0,
                   "gcpkg: utfcpp: the ftest port is required to build the upstream tests")
            local ftest_h = util.join(dep.includes[1], "ftest.h")
            assert(fs.isfile(ftest_h),
                   "gcpkg: utfcpp: ftest.h missing from the ftest port")
            -- fill the upstream submodule path from the package store
            local extern_dir = util.join(ctx.src, "extern", "ftest")
            fs.mkdirs(extern_dir)
            ctx.exec({ "cp", "-a", ftest_h, util.join(extern_dir, "ftest.h") },
                     { cwd = ctx.src, log = ctx.log })

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
                   "gcpkg: utfcpp: configuring the upstream test project failed")
            assert(ctx.exec({ "cmake", "--build", bdir, "--parallel",
                              tostring(ctx.jobs or 8) },
                            { cwd = ctx.src, env = env, log = ctx.log }) == 0,
                   "gcpkg: utfcpp: building the upstream test project failed")

            local out = util.join(ctx.build_dir, "ctest.out")
            local script = "ctest --output-on-failure > " .. out .. " 2>&1; echo $? > " ..
                           out .. ".rc"
            ctx.exec({ "sh", "-c", script }, { cwd = bdir, env = env, log = ctx.log })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out),
                                "gcpkg: utfcpp: missing ctest output")
            assert(not text:find("No tests were found", 1, true),
                   "gcpkg: utfcpp: ctest found no registered tests")
            assert(text:find("100% tests passed", 1, true),
                   "gcpkg: utfcpp: upstream test suite did not pass: " .. text)
            assert(rc == "0",
                   "gcpkg: utfcpp: ctest exited with " .. rc .. ": " .. text)
            -- the suite must really have executed all six upstream programs
            local passed = tonumber(text:match("(%d+)%% tests passed") or "0") or 0
            assert(passed == 100,
                   "gcpkg: utfcpp: unexpected ctest summary: " .. text)
            local registered = tonumber(text:match("out of (%d+)") or "0") or 0
            assert(registered == 6,
                   "gcpkg: utfcpp: expected the six upstream test programs, ctest ran " ..
                   registered .. ": " .. text)
            for _, t in ipairs({ "negative_test", "cpp11_test", "cpp17_test",
                                 "cpp20_test", "api_test", "noexceptions_test" }) do
                assert(text:find(t, 1, true),
                       "gcpkg: utfcpp: test " .. t .. " did not run: " .. text)
            end
        end

        -- sanity: real consumer over the INSTALLED headers ------------------
        if on["sanity"] then
            assert(on["headers"], "gcpkg: utfcpp: sanity needs headers")
            local csrc = util.join(ctx.build_dir, "utfcpp_sanity.cpp")
            fs.write(csrc, [==[
#include <utf8.h>
#include <cstdio>
#include <string>
#include <vector>

int main() {
  std::string s = u8"gcpkg \u00e9\u00fc";
  std::vector<char32_t> cp;
  utf8::unchecked::utf8to32(s.begin(), s.end(), std::back_inserter(cp));
  if (cp.empty() || cp.back() != 0xFC) return 2;
  std::string back;
  utf8::unchecked::utf32to8(cp.begin(), cp.end(), std::back_inserter(back));
  if (back != s) return 3;
  if (!utf8::is_valid(s.begin(), s.end())) return 4;
  std::printf("gcpkg utfcpp ok codepoints=%zu\n", cp.size());
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
                tag = "utfcpp",
            }
            local exe = util.join(ctx.build_dir, "utfcpp_sanity")
            cc.link { objects = objs, output = exe,
                      compiler = ctx.compiler.wrapper_cxx, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: utfcpp: missing sanity output")
            assert(text:find("gcpkg utfcpp ok", 1, true),
                   "gcpkg: utfcpp: consumer did not run: " .. text)
        end

        -- pkg-config --------------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: utfcpp
Description: UTF-8 with C++ header-only library
Version: 4.0.6
Cflags: -I${includedir}
]==]
            fs.write(util.join(pcdir, "utf8cpp.pc"), (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package: mirrors upstream's utf8cpp :: utf8cpp target -------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(util.join(cmakedir, "utf8cppConfig.cmake"), [==[
get_filename_component(_UTF8CPP_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET utf8cpp::utf8cpp)
  add_library(utf8cpp::utf8cpp INTERFACE IMPORTED)
  set_target_properties(utf8cpp::utf8cpp PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_UTF8CPP_PREFIX}/include")
endif()
set(utf8cpp_FOUND TRUE)
]==])
            fs.write(util.join(cmakedir, "utf8cppConfigVersion.cmake"), [==[
set(PACKAGE_VERSION "4.0.6")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- docs / license -----------------------------------------------------
        if on["docs"] then
            copy(ctx, util.join(ctx.src, "README.md"), util.join(docdir, "README.md"))
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: utfcpp: LICENSE missing")
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
