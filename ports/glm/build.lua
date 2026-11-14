-- glm 1.0.1 -- R20 new-standard port (compiled library or header-only).
--
-- OpenGL Mathematics.  Upstream's root CMakeLists.txt declares
--
--   GLM_BUILD_LIBRARY -> compiled  / header-only feature pair
--   BUILD_SHARED_LIBS -> static    / shared       feature pair
--   GLM_BUILD_TESTS   -> tests     / no-tests     (root does include(CTest), so
--                        ctest registration works out of the box; test/ adds one
--                        executable per unit-test file)
--   GLM_BUILD_INSTALL -> install   / no-install   (headers + glmConfig.cmake
--                        namespace glm:: in share/glm)
--
-- Two upstream details worth recording:
--   * test/CMakeLists.txt adds `-Werror -Weverything` for Clang and `-Werror`
--     for GCC unless GLM_DISABLE_AUTO_DETECTION is set.  That switch is exactly
--     what upstream provides for "don't warn-explode on a new compiler", so the
--     port sets it and lets the suite build cleanly instead of patching flags.
--   * The semantic tuning switches (GLM_ENABLE_FAST_MATH, GLM_ENABLE_SIMD_*,
--     GLM_FORCE_PURE, GLM_ENABLE_CXX_*) are deliberately left at their upstream
--     defaults: they change generated code, they are not capabilities.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local VERSION = "1.0.1"

-- Upstream's test/CMakeLists.txt adds `-Werror -Weverything` for Clang (and
-- plain `-Werror` for GCC).  On a modern Clang that combination rejects glm's
-- own C++98-compatibility diagnostics, and upstream's escape hatch
-- (GLM_DISABLE_AUTO_DETECTION) is not usable here: it defines
-- GLM_FORCE_CXX_UNKNOWN, which forces GLM_LANG to 0 and silently disables the
-- C++11-only extensions (gtx/hash.hpp).  So the flags are filtered in a
-- compiler launcher instead: diagnostics stay, only "and therefore fail"
-- changes.  Nothing in the sources or their CMake files is touched.
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
    name = "glm",
    version = VERSION,
    license = "MIT",
    homepage = "https://github.com/g-truc/glm",
    description = "OpenGL Mathematics (GLM): header-only C++ math library for graphics software",
    source = {
        url = "https://codeload.github.com/g-truc/glm/tar.gz/refs/tags/1.0.1",
        sha256 = "9f3174561fd26904b23f0db5e560971cbf9b3cbda0b280f04d5c379d03bf234c",
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        -- create the launcher before configure, so the define below can point
        -- at an existing file
        warning_filter(ctx)
    end,
    cmake = {
        defines = function(ctx)
            return {
                GLM_BUILD_LIBRARY = "OFF",
                GLM_BUILD_TESTS = "OFF",
                GLM_BUILD_INSTALL = "OFF",
                BUILD_SHARED_LIBS = "OFF",
                -- pin the language level upstream's headers target (also makes
                -- upstream add -Wno-c++98-compat for Clang)
                GLM_ENABLE_CXX_17 = "ON",
                CMAKE_CXX_COMPILER_LAUNCHER = warning_filter(ctx),
                GLM_QUIET = "ON",
                GLM_PERF_TEST_ENABLE = "OFF",
                CMAKE_INSTALL_INCLUDEDIR = "include",
                CMAKE_INSTALL_LIBDIR = "lib",
            }
        end,
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "glm")
        fs.mkdirs(docdir)

        assert(not (on["shared"] and not on["compiled"]),
               "gcpkg: glm: `shared` needs the `compiled` feature " ..
               "(header-only mode has no library to share)")

        if on["install"] then
            for _, h in ipairs({ "glm/glm.hpp", "glm/vec3.hpp", "glm/mat4x4.hpp",
                                 "glm/gtc/quaternion.hpp", "glm/gtx/norm.hpp",
                                 "glm/detail/setup.hpp" }) do
                assert(fs.isfile(util.join(incdir, h)),
                       "gcpkg: glm: " .. h .. " missing from the install tree")
            end
            -- upstream installs the header tree with its CMakeLists.txt excluded
            assert(not fs.isfile(util.join(incdir, "glm/CMakeLists.txt")),
                   "gcpkg: glm: upstream's PATTERN EXCLUDE did not apply")
            if on["compiled"] then
                local found = false
                for _, pat in ipairs({ libdir .. "/libglm.a", libdir .. "/libglm.so" }) do
                    if fs.isfile(pat) then found = true break end
                end
                assert(found, "gcpkg: glm: the compiled library was not installed")
            end
        end

        if on["tests"] then
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "ctest --output-on-failure > " .. out .. " 2>&1; echo $? > " ..
                       out .. ".rc" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out), "gcpkg: glm: missing ctest output")
            assert(not text:find("No tests were found", 1, true),
                   "gcpkg: glm: ctest found no registered tests")
            assert(text:find("100% tests passed", 1, true),
                   "gcpkg: glm: upstream test suite did not pass: " .. text)
            assert(rc == "0", "gcpkg: glm: ctest exited with " .. rc)
            -- test/{bug,core,ext,gtc,gtx} register one program per test file;
            -- the exact count follows the header tree, so require the bulk of it.
            local registered = tonumber(text:match("out of (%d+)") or "0") or 0
            assert(registered >= 150,
                   "gcpkg: glm: expected ~190 upstream test programs, ctest ran " ..
                   registered)
            for _, t in ipairs({ "test%-core_type_vec3", "test%-core_type_mat4x4",
                                 "test%-gtc_quaternion", "test%-gtx_norm",
                                 "test%-gtx_hash" }) do
                assert(text:find(t),
                       "gcpkg: glm: " .. t:gsub("%%", "") .. " did not run")
            end
        end

        if on["pkgconfig"] then
            assert(on["install"],
                   "gcpkg: glm: pkgconfig needs the install feature")
            local pcdir = util.join(libdir, "pkgconfig")
            fs.mkdirs(pcdir)
            local libs = ""
            if on["compiled"] then
                libs = "Libs: -L${libdir} -lglm\n"
            end
            fs.write(util.join(pcdir, "glm.pc"), table.concat({
                "prefix=" .. tostring(ctx.prefix),
                "includedir=" .. tostring(incdir),
                "libdir=" .. tostring(libdir),
                "",
                "Name: glm",
                "Description: OpenGL Mathematics (GLM)",
                "Version: " .. VERSION,
                "Cflags: -I${includedir}",
                libs,
            }, "\n"))
        end

        if on["cmake-package"] then
            assert(on["install"],
                   "gcpkg: glm: cmake-package needs the install feature")
            for _, pat in ipairs({ "share/glm/glmConfig.cmake",
                                   "share/glm/glmConfigVersion.cmake" }) do
                assert(fs.isfile(util.join(ctx.prefix, pat)),
                       "gcpkg: glm: upstream " .. pat .. " missing")
            end
        end

        if on["docs"] then
            for _, f in ipairs({ "readme.md", "manual.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
            for _, d in ipairs({ "doc" }) do
                if fs.isdir(util.join(ctx.src, d)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, d), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            -- upstream spells the licence file "copying.txt"; there are no
            -- SPDX headers to reuse, so install both spellings into docdir.
            local lic = util.join(ctx.src, "copying.txt")
            assert(fs.isfile(lic), "gcpkg: glm: copying.txt missing")
            ctx.exec({ "cp", "-a", lic, docdir }, { cwd = ctx.src, log = ctx.log })
            fs.write(util.join(docdir, "LICENSE"), fs.read(lic) or "",
                     "MIT (see copying.txt)")
        end

        if on["sanity"] then
            assert(on["install"], "gcpkg: glm: sanity needs the install feature")
            local csrc = util.join(ctx.build_dir, "glm_sanity.cpp")
            fs.write(csrc, [==[
// gtx/* extensions require this before the first glm header
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/norm.hpp>
#include <cstdio>

int main() {
  glm::vec3 a(1.0f, 2.0f, 3.0f);
  glm::vec3 b(4.0f, 5.0f, 6.0f);
  glm::vec3 c = glm::cross(a, b);
  if (c.x != -3.0f || c.y != 6.0f || c.z != -3.0f) return 2;
  glm::mat4 m = glm::mat4(1.0f);
  glm::vec4 v = m * glm::vec4(a, 1.0f);
  if (v.w != 1.0f || v.z != 3.0f) return 3;
  glm::quat q = glm::angleAxis(glm::radians(90.0f), glm::vec3(0.0f, 0.0f, 1.0f));
  glm::vec3 r = q * glm::vec3(1.0f, 0.0f, 0.0f);
  if (glm::abs(glm::length2(r) - 1.0f) > 1e-4f) return 4;
  std::printf("gcpkg glm ok cross=%.1f version=%d\n", (double)c.y,
              (int)GLM_VERSION);
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "glm_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "glm", cxx = true, output = exe,
                libdirs = on["compiled"] and { libdir } or {},
                libs = on["compiled"] and { "glm" } or {},
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: glm: missing sanity output")
            assert(text:find("gcpkg glm ok", 1, true),
                   "gcpkg: glm: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@PREFIX@/lib" },
        libs = { "glm" },
        binaries = {},
    },
}
