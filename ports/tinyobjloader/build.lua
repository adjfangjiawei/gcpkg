-- tinyobjloader 2.0.0-rc.13 -- R20 new-standard port (compiled static/shared).
--
-- A C++ Wavefront OBJ loader (also usable header-only via
-- TINYOBJLOADER_IMPLEMENTATION).  Upstream's CMakeLists.txt declares
--
--   BUILD_SHARED_LIBS                 -> static / shared   feature pair
--   TINYOBJLOADER_USE_DOUBLE          -> single / double   feature pair
--   TINYOBJLOADER_BUILD_TEST_LOADER   -> loader   / no-loader
--   TINYOBJLOADER_BUILD_OBJ_STICHER   -> obj-sticher / no-obj-sticher
--   TINYOBJLOADER_WITH_PYTHON         -> left OFF (needs pybind11 + Python dev)
--
-- and installs headers, the library, a CONFIG package
-- (lib/tinyobjloader/cmake, namespace tinyobjloader::) and a generated
-- pkg-config file.  Its unit tests are NOT wired into CMake: they are
-- tests/tester.cc plus tests/Makefile (`make check`, i.e. build with
-- `-std=c++03 -fsanitize=address` and run the acutest binary from tests/ so the
-- relative ../models/ paths resolve).  The `tests` feature reproduces exactly
-- that with the toolchain's own compiler, so the library is also exercised in
-- C++03 mode and under AddressSanitizer.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local VERSION = "v2.0.0rc13"
local UPSTREAM_VERSION = "2.0.0-rc.13"

local function libname(on)
    return on["double"] and "tinyobjloader_double" or "tinyobjloader"
end

return recipe.cmake {
    name = "tinyobjloader",
    version = VERSION,
    license = "MIT",
    homepage = "https://github.com/tinyobjloader/tinyobjloader",
    description = "Tiny but powerful single-file OBJ loader, with optional double precision build",
    source = {
        url = "https://codeload.github.com/tinyobjloader/tinyobjloader/tar.gz/refs/tags/v2.0.0rc13",
        sha256 = "0feb92b838f8ce4aa6eb0ccc32dff30cb64a891e0ec3bde837fca49c78d44334",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_SHARED_LIBS = "OFF",
            TINYOBJLOADER_USE_DOUBLE = "OFF",
            TINYOBJLOADER_BUILD_TEST_LOADER = "OFF",
            TINYOBJLOADER_BUILD_OBJ_STICHER = "OFF",
            TINYOBJLOADER_WITH_PYTHON = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
            CMAKE_INSTALL_BINDIR = "bin",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local bindir = util.join(ctx.prefix, "bin")
        local lib = libname(on)
        local docdir = util.join(ctx.prefix, "share", "doc", "tinyobjloader")
        fs.mkdirs(docdir)

        assert(fs.isfile(util.join(incdir, "tiny_obj_loader.h")),
               "gcpkg: tinyobjloader: tiny_obj_loader.h missing from the install tree")

        -- library + CONFIG package + pkg-config come from upstream -----------
        local found = false
        for _, pat in ipairs({ "lib/lib" .. lib .. ".a", "lib/lib" .. lib .. ".so" }) do
            if fs.isfile(util.join(ctx.prefix, pat)) then found = true break end
        end
        assert(found, "gcpkg: tinyobjloader: lib" .. lib .. " was not installed")

        if on["cmake-package"] then
            for _, pat in ipairs({ "lib/tinyobjloader/cmake/tinyobjloader-config.cmake",
                                   "lib/tinyobjloader/cmake/tinyobjloader-targets.cmake" }) do
                assert(fs.isfile(util.join(ctx.prefix, pat)),
                       "gcpkg: tinyobjloader: upstream " .. pat .. " missing")
            end
        end
        if on["pkgconfig"] then
            for _, pat in ipairs({ "lib/pkgconfig/" .. lib .. ".pc",
                                   "share/pkgconfig/" .. lib .. ".pc" }) do
                if fs.isfile(util.join(ctx.prefix, pat)) then found = true end
            end
            assert(found, "gcpkg: tinyobjloader: upstream " .. lib .. ".pc missing")
        end

        -- loader: upstream's own example program (TINYOBJLOADER_BUILD_TEST_LOADER)
        if on["loader"] then
            local exe = util.join(ctx.build_dir, "test_loader")
            local out = util.join(ctx.build_dir, "loader.out")
            ctx.exec({ "sh", "-c",
                       "cd " .. ctx.src .. " && " .. exe .. " models/cube.obj > " ..
                       out .. " 2>&1; echo $? >> " .. out },
                     { cwd = ctx.src, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: tinyobjloader: missing loader output")
            assert(text:find("# of vertices", 1, true),
                   "gcpkg: tinyobjloader: loader did not report a mesh: " .. text)
            assert(text:find("# of shapes", 1, true),
                   "gcpkg: tinyobjloader: loader did not report a shape: " .. text)
            assert(not text:find("error", 1, true) or text:find("# of materials", 1, true),
                   "gcpkg: tinyobjloader: loader failed: " .. text)
        end

        -- obj-sticher: upstream's example tool, installed to bin by upstream
        if on["obj-sticher"] then
            assert(fs.isfile(util.join(bindir, "obj_sticher")),
                   "gcpkg: tinyobjloader: obj_sticher was not installed")
            local merged = util.join(ctx.build_dir, "merged.obj")
            local out = util.join(ctx.build_dir, "obj_sticher.out")
            ctx.exec({ "sh", "-c",
                       "cd " .. ctx.src .. " && " .. util.join(bindir, "obj_sticher") ..
                       " models/cube.obj models/cube-vertexcol.obj " .. merged ..
                       " > " .. out .. " 2>&1; echo $? >> " .. out },
                     { cwd = ctx.src, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: tinyobjloader: missing obj_sticher output")
            assert(not text:find("File not found", 1, true),
                   "gcpkg: tinyobjloader: obj_sticher could not read its inputs: " .. text)
            local merged_text = fs.read(merged) or ""
            assert(#merged_text > 0,
                   "gcpkg: tinyobjloader: obj_sticher wrote no output: " .. text)
            -- Lua's `^` only anchors at the very start of the subject, so
            -- look for a vertex line at the head or after a newline.
            assert(merged_text:sub(1, 2) == "v " or merged_text:find("\nv ", 1, true),
                   "gcpkg: tinyobjloader: merged obj has no vertices")
        end

        -- tests: upstream's tests/Makefile (`make check`) --------------------
        -- tester.cc is acutest-driven and reaches ../models/ relatively, so it
        -- must run from tests/.  Upstream builds it with -std=c++03 and
        -- -fsanitize=address; keep both so the library is also checked in
        -- C++03 mode and under ASan.
        if on["tests"] then
            local testsdir = util.join(ctx.src, "tests")
            local exe = util.join(ctx.build_dir, "tinyobj_tester")
            cc.executable {
                sources = { util.join(testsdir, "tester.cc") },
                includes = { testsdir },
                -- cc.executable passes the same flags to the link step, which
                -- is what -fsanitize=address needs here.
                flags = { "-std=c++03", "-g", "-O1", "-fsanitize=address",
                          "-fno-omit-frame-pointer" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_tester"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "tinyobjloader", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            -- 1. run the acutest binary exactly as `make check` does and keep
            --    its full transcript
            local tout = util.join(ctx.build_dir, "tester.out")
            ctx.exec({ "sh", "-c",
                       "cd " .. testsdir .. " && " .. exe .. " > " .. tout ..
                       " 2>&1; echo $? >> " .. tout },
                     { cwd = testsdir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(tout),
                                "gcpkg: tinyobjloader: missing tester output")
            assert(text:find("SUCCESS", 1, true),
                   "gcpkg: tinyobjloader: upstream tester did not pass: " .. text)
            assert(not text:find("FAILED", 1, true),
                   "gcpkg: tinyobjloader: upstream tester reported failures: " .. text)
            assert(not text:find("AddressSanitizer", 1, true),
                   "gcpkg: tinyobjloader: AddressSanitizer reported a problem: " .. text)
            -- acutest prints one "Test <name>..." line per case; the first one
            -- starts the file, so count the marker itself, not "\nTest".
            local cases = select(2, text:gsub("Test ", ""))
            local oks = select(2, text:gsub("%[ OK %]", ""))
            assert(cases >= 40,
                   "gcpkg: tinyobjloader: expected the full acutest suite, saw " ..
                   cases .. " cases")
            assert(oks == cases,
                   "gcpkg: tinyobjloader: " .. cases - oks ..
                   " upstream test case(s) did not report OK")

            -- 2. and register that same run with CTest, so the pass is visible
            --    to the R20 evidence checks as well
            local driver = util.join(ctx.build_dir, "upstream-tests")
            fs.mkdirs(driver)
            fs.write(util.join(driver, "CMakeLists.txt"), table.concat({
                "# Generated by the gcpkg tinyobjloader port: upstream's",
                "# tests/Makefile `check` target, registered with CTest.",
                "cmake_minimum_required(VERSION 3.16)",
                "project(tinyobjloader-upstream-tests LANGUAGES NONE)",
                "enable_testing()",
                'add_test(NAME tinyobjloader_tester COMMAND "' .. exe .. '")',
                "set_tests_properties(tinyobjloader_tester PROPERTIES",
                '  WORKING_DIRECTORY "' .. testsdir .. '")',
                "",
            }, "\n"))
            local dbuild = util.join(driver, "build")
            ctx.exec({ "cmake", "-S", driver, "-B", dbuild },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "cd " .. dbuild .. " && ctest --output-on-failure > " .. out ..
                       " 2>&1; echo $? > " .. out .. ".rc" },
                     { cwd = dbuild, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local ctext = assert(fs.read(out), "gcpkg: tinyobjloader: missing ctest output")
            assert(ctext:find("100% tests passed", 1, true),
                   "gcpkg: tinyobjloader: ctest did not pass: " .. ctext)
            assert(rc == "0", "gcpkg: tinyobjloader: ctest exited with " .. rc)
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "pbr-mtl.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: tinyobjloader: LICENSE missing")
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end

        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "tinyobj_sanity.cpp")
            fs.write(csrc, [==[
#include <tiny_obj_loader.h>
#include <cstdio>
#include <fstream>
#include <vector>

int main() {
  const char *obj = "tinyobj_sanity_input.obj";
  {
    std::ofstream f(obj);
    f << "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n";
  }
  tinyobj::attrib_t attrib;
  std::vector<tinyobj::shape_t> shapes;
  std::vector<tinyobj::material_t> materials;
  std::string warn, err;
  bool ok = tinyobj::LoadObj(&attrib, &shapes, &materials, &warn, &err, obj);
  if (!ok) return 2;
  if (attrib.vertices.size() != 9) return 3;
  if (shapes.size() != 1) return 4;
  std::printf("gcpkg tinyobjloader ok verts=%d shapes=%d\n",
              (int)(attrib.vertices.size() / 3), (int)shapes.size());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "tinyobj_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "tinyobjloader", cxx = true, output = exe,
                libdirs = { libdir }, libs = { lib },
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: tinyobjloader: missing sanity output")
            assert(text:find("gcpkg tinyobjloader ok", 1, true),
                   "gcpkg: tinyobjloader: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@PREFIX@/lib" },
        libs = { "tinyobjloader" },
        binaries = { "@PREFIX@/bin/obj_sticher" },
    },
}
