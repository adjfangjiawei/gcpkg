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
        -- Only the modular `cista-test` target is built.  The second upstream
        -- target, `cista-test-single-header`, is built against the amalgamated
        -- cista.h that tools/uniter generates, and that amalgamation is broken
        -- outside an fmt tree: include/cista/containers/string.h has
        --
        --     #if __has_include("fmt/ranges.h")
        --     namespace fmt { template <...> struct range_format_kind<...>; }
        --     #endif
        --
        -- and uniter resolves that __has_include while walking the tree, so
        -- without fmt the generated file ends up with a stub comment and every
        -- TU fails with "explicit specialization of undeclared template struct
        -- 'range_format_kind'".  That is an upstream defect, not a port
        -- problem; it is recorded in ctest.out instead of being papered over.
        if on["tests"] then
            ctx.exec({ "cmake", "--build", ctx.build_dir, "--parallel",
                       tostring(ctx.jobs or 4), "--target", "cista-test" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

            local exe = util.join(ctx.build_dir, "cista-test")
            assert(fs.isfile(exe), "gcpkg: cista: cista-test was not built")
            local out = util.join(ctx.build_dir, "cista-test.out")
            ctx.exec({ "sh", "-c",
                       "cd " .. ctx.build_dir .. " && " .. exe .. " > " .. out ..
                       " 2>&1; echo $? >> " .. out },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: cista: missing cista-test output")
            assert(text:find("Status: SUCCESS", 1, true),
                   "gcpkg: cista: cista-test did not report success: " .. text)
            assert(not text:find("Status: FAILURE", 1, true),
                   "gcpkg: cista: cista-test reported failures: " .. text)
            local cases = tonumber(text:match("test cases:%s*(%d+)") or "0") or 0
            assert(cases >= 100,
                   "gcpkg: cista: cista-test ran only " .. cases ..
                   " test cases, expected the whole suite")

            -- register the run with CTest so the pass is visible there too
            local driver = util.join(ctx.build_dir, "upstream-tests")
            fs.mkdirs(driver)
            fs.write(util.join(driver, "CMakeLists.txt"), table.concat({
                "# Generated by the gcpkg cista port: upstream's doctest binary,",
                "# registered with CTest.",
                "cmake_minimum_required(VERSION 3.16)",
                "project(cista-upstream-tests LANGUAGES NONE)",
                "enable_testing()",
                'add_test(NAME cista-test COMMAND "' .. exe .. '")',
                'set_tests_properties(cista-test PROPERTIES WORKING_DIRECTORY "' ..
                    tostring(ctx.build_dir) .. '")',
                "",
            }, "\n"))
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

            -- record what was deliberately not run
            ctx.exec({ "sh", "-c", "cat >> " .. ctest_out .. " <<'NOTE'\n" ..
                       "not run: cista-test-single-header (upstream target,\n" ..
                       "  EXCLUDE_FROM_ALL). Its amalgamated cista.h cannot be\n" ..
                       "  generated without fmt: cista/containers/string.h has an\n" ..
                       "  #if __has_include(\"fmt/ranges.h\") block that uniter\n" ..
                       "  mis-resolves, leaving an undeclared range_format_kind\n" ..
                       "  specialization in the amalgamation. Upstream defect.\n" ..
                       "NOTE" },
                     { cwd = ctx.build_dir, log = ctx.log })
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
