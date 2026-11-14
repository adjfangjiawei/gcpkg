-- cista 0.16 -- R20 new-standard header-only port.
--
-- cista is a C++17 zero-copy serialization / reflection library.  Upstream's
-- CMakeLists.txt is a real project with a real test suite (50 doctest
-- translation units under test/, linked into one `cista-test` binary, plus a
-- second `cista-test-single-header` binary built against the amalgamated
-- cista.h that tools/uniter generates), but the test targets are
-- EXCLUDE_FROM_ALL, so the port builds them explicitly.
--
-- Upstream switch surface used here:
--   CISTA_HASH  (FNV1A | XXH3 | WYHASH | WYHASH_FASTEST) - left at FNV1A, the
--               header-only default; the other values pull in the bundled
--               tools/xxh3 or tools/wyhash static libraries.
--   CISTA_FMT   - set OFF.  Upstream defaults it ON, which puts a CISTA_FMT
--               define on the INTERFACE target so that consumers of
--               cista/indexed.h and cista/strong.h must have libfmt available.
--               The port keeps the installed headers self-contained; a project
--               that has fmt can still define CISTA_FMT itself.
--   CISTA_ZERO_OUT / CISTA_USE_MIMALLOC / CISTA_COVERAGE / CISTA_GENERATE_TO_TUPLE
--               - semantic/developer switches, left at upstream defaults (OFF).
--
-- Install is not switchable upstream: `if (NOT DEFINED PROJECT_NAME AND
-- CISTA_HASH STREQUAL "FNV1A") set(CISTA_INSTALL ON)` runs before project() and
-- therefore always forces it on for a top-level FNV1A build.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")

local VERSION = "0.16"

-- Upstream's test targets are compiled with `-Weverything -Werror` on Clang;
-- on a newer Clang that turns upstream's own suppression list into hard errors.
-- The launcher drops exactly those two flags: every diagnostic upstream chose
-- to keep still prints, only "and therefore fail" is removed.
local function warning_filter(ctx)
    local f = util.join(ctx.build_dir, "gcpkg-cxx-launcher.py")
    fs.mkdirs(ctx.build_dir)
    fs.write(f, [[#!/usr/bin/env python3
import os, sys

DROP = ("-Werror", "-Weverything")
args = [a for a in sys.argv[1:] if a not in DROP]
os.execv(args[0], args)
]])
    ctx.exec({ "chmod", "+x", f }, { cwd = ctx.build_dir, log = ctx.log })
    return f
end

-- Upstream's single-header target compiles against the cista.h that
-- tools/uniter generates.  uniter is a textual include flattener and, when an
-- include cannot be expanded, it drops the line and prints a comment instead.
-- That breaks include/cista/containers/string.h, which has
--
--     #if __has_include("fmt/ranges.h")
--     #include "fmt/ranges.h"
--     namespace fmt { template <...> struct range_format_kind<...>; }
--     #endif
--
-- The include is not inside cista's own include/ directory, so uniter cannot
-- expand it: the #if survives, the #include disappears, and on any machine that
-- does have fmt installed the guard is true, so the amalgamation declares a
-- specialization of a template nobody declared.  The fix is one line - keep an
-- unexpandable include verbatim - and it is applied to a copy-free edit of
-- tools/uniter/uniter.cc before the build.
local UNITER_NEEDLE = [[std::cout << "// " << path << ": " << e.what() << "\n";]]
local UNITER_PATCH = [[// gcpkg patch: an include that cannot be expanded (for example a system
            // header named inside a guarded __has_include block) must be kept
            // verbatim; dropping it keeps the #if but removes the declarations
            // it guards.
            (void)e;
            std::cout << line << "\n";]]

local function patch_uniter(ctx)
    local p = util.join(ctx.src, "tools", "uniter", "uniter.cc")
    local src = assert(fs.read(p), "gcpkg: cista: tools/uniter/uniter.cc missing")
    if src:find(UNITER_PATCH, 1, true) then return end
    local i, j = src:find(UNITER_NEEDLE, 1, true)
    assert(i, "gcpkg: cista: tools/uniter/uniter.cc no longer matches the " ..
              "pattern this port patches; upstream changed uniter")
    fs.write(p, src:sub(1, i - 1) .. UNITER_PATCH .. src:sub(j + 1))
end

return recipe.cmake {
    name = "cista",
    version = VERSION,
    license = "MIT",
    homepage = "https://github.com/felixguendling/cista",
    description = "C++17 zero-copy serialization and reflection library",
    source = {
        url = "https://codeload.github.com/felixguendling/cista/tar.gz/refs/tags/v0.16",
        sha256 = "55832c0e723568bd3abdfd70e7ba4dca777dfaada63f4da74f325f868f95694e",
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        warning_filter(ctx)
        patch_uniter(ctx)
    end,
    cmake = {
        defines = function(ctx)
            return {
                CISTA_HASH = "FNV1A",
                CISTA_FMT = "OFF",
                CISTA_ZERO_OUT = "OFF",
                CISTA_USE_MIMALLOC = "OFF",
                CISTA_COVERAGE = "OFF",
                CISTA_GENERATE_TO_TUPLE = "OFF",
                CMAKE_CXX_STANDARD = "17",
                CMAKE_CXX_STANDARD_REQUIRED = "ON",
                CMAKE_CXX_COMPILER_LAUNCHER = warning_filter(ctx),
                CMAKE_INSTALL_INCLUDEDIR = "include",
                CMAKE_INSTALL_LIBDIR = "lib",
            }
        end,
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "cista")
        fs.mkdirs(docdir)

        for _, h in ipairs({ "cista/serialization.h", "cista/reflection/to_tuple.h",
                             "cista/hashing.h", "cista/containers/vector.h" }) do
            assert(fs.isfile(util.join(incdir, h)),
                   "gcpkg: cista: " .. h .. " missing from the install tree")
        end
        assert(not fs.isfile(util.join(incdir, "cista/CMakeLists.txt")),
               "gcpkg: cista: the install tree should hold headers only")

        if on["cmake-package"] then
            for _, pat in ipairs({ "lib/cmake/cista/cistaConfig.cmake",
                                   "lib/cmake/cista/cistaConfigVersion.cmake",
                                   "lib/cmake/cista/cistaTargets.cmake" }) do
                assert(fs.isfile(util.join(ctx.prefix, pat)),
                       "gcpkg: cista: upstream " .. pat .. " missing")
            end
        end

        if on["pkgconfig"] then
            local pcdir = util.join(libdir, "pkgconfig")
            fs.mkdirs(pcdir)
            fs.write(util.join(pcdir, "cista.pc"), table.concat({
                "prefix=" .. tostring(ctx.prefix),
                "includedir=" .. tostring(incdir),
                "",
                "Name: cista",
                "Description: C++17 zero-copy serialization and reflection library",
                "Version: " .. VERSION,
                "Cflags: -I${includedir} -std=c++17",
                "",
            }, "\n"))
        end

        -- tests: upstream's doctest suite ------------------------------------
        -- Both EXCLUDE_FROM_ALL targets: the modular cista-test and
        -- cista-test-single-header, which compiles the same 50 TUs against the
        -- amalgamated cista.h produced by tools/uniter (patched in pre_build).
        if on["tests"] then
            ctx.exec({ "cmake", "--build", ctx.build_dir, "--parallel",
                       tostring(ctx.jobs or 4), "--target",
                       "cista-test", "cista-test-single-header" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

            local binaries = { "cista-test", "cista-test-single-header" }
            local exes = {}
            for _, name in ipairs(binaries) do
                local exe = util.join(ctx.build_dir, name)
                assert(fs.isfile(exe), "gcpkg: cista: " .. name .. " was not built")
                exes[#exes + 1] = { name = name, exe = exe }
                local out = util.join(ctx.build_dir, name .. ".out")
                ctx.exec({ "sh", "-c",
                           "cd " .. ctx.build_dir .. " && " .. exe .. " > " .. out ..
                           " 2>&1; echo $? >> " .. out },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local text = assert(fs.read(out),
                                    "gcpkg: cista: missing " .. name .. " output")
                assert(text:find("Status: SUCCESS", 1, true),
                       "gcpkg: cista: " .. name .. " did not report success: " .. text)
                assert(not text:find("Status: FAILURE", 1, true),
                       "gcpkg: cista: " .. name .. " reported failures: " .. text)
                local cases = tonumber(text:match("test cases:%s*(%d+)") or "0") or 0
                assert(cases >= 100,
                       "gcpkg: cista: " .. name .. " ran only " .. cases ..
                       " test cases, expected the whole suite")
            end

            -- register both runs with CTest so the pass is visible there too
            local driver = util.join(ctx.build_dir, "upstream-tests")
            fs.mkdirs(driver)
            local lines = {
                "# Generated by the gcpkg cista port: upstream's two doctest",
                "# binaries, registered with CTest.",
                "cmake_minimum_required(VERSION 3.16)",
                "project(cista-upstream-tests LANGUAGES NONE)",
                "enable_testing()",
            }
            for _, e in ipairs(exes) do
                lines[#lines + 1] = 'add_test(NAME ' .. e.name .. ' COMMAND "' ..
                                    e.exe .. '")'
                lines[#lines + 1] = "set_tests_properties(" .. e.name ..
                                    ' PROPERTIES WORKING_DIRECTORY "' ..
                                    tostring(ctx.build_dir) .. '")'
            end
            fs.write(util.join(driver, "CMakeLists.txt"),
                     table.concat(lines, "\n") .. "\n")
            local dbuild = util.join(driver, "build")
            ctx.exec({ "cmake", "-S", driver, "-B", dbuild },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local ctest_out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "cd " .. dbuild .. " && ctest --output-on-failure > " ..
                       ctest_out .. " 2>&1; echo $? > " .. ctest_out .. ".rc" },
                     { cwd = dbuild, log = ctx.log, env = ctx.env })
            local rc = (fs.read(ctest_out .. ".rc") or "?"):gsub("%s", "")
            local ctext = assert(fs.read(ctest_out),
                                 "gcpkg: cista: missing ctest output")
            assert(ctext:find("100% tests passed", 1, true),
                   "gcpkg: cista: ctest did not pass: " .. ctext)
            assert(rc == "0", "gcpkg: cista: ctest exited with " .. rc)
        end

        if on["docs"] then
            if fs.isfile(util.join(ctx.src, "README.md")) then
                ctx.exec({ "cp", "-a", util.join(ctx.src, "README.md"), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: cista: LICENSE missing")
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end

        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "cista_sanity.cpp")
            fs.write(csrc, [==[
#include <cista/serialization.h>
#include <cista/reflection/to_tuple.h>
#include <cstdio>
#include <tuple>

struct serialize_me {
  int a_{0};
  struct inner {
    int b_{0};
    int c_{0};
  } j_;
};

struct plain {
  int x;
  int y;
};

int main() {
  cista::byte_buf buf;
  {
    serialize_me obj{1, {2, 3}};
    buf = cista::serialize(obj);
  }
  auto const *s =
      cista::deserialize<serialize_me>(&buf[0], &buf[0] + buf.size());
  if (s == nullptr) return 2;
  if (s->a_ != 1 || s->j_.b_ != 2 || s->j_.c_ != 3) return 3;
  // to_tuple() takes an lvalue and reflects an aggregate member by member
  plain p{7, 8};
  auto t = cista::to_tuple(p);
  static_assert(std::tuple_size<decltype(t)>::value == 2,
                "cista reflection sees two members");
  if (std::get<0>(t) != 7 || std::get<1>(t) != 8) return 4;
  std::printf("gcpkg cista ok a=%d b=%d bytes=%zu\n", s->a_, s->j_.b_,
              buf.size());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "cista_sanity")
            ctx.exec({ tostring(ctx.compiler.wrapper_cxx), "-std=c++17",
                       "-I" .. incdir, csrc, "-o", exe },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: cista: missing sanity output")
            assert(text:find("gcpkg cista ok", 1, true),
                   "gcpkg: cista: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
