-- stb 4e9b368 -- R20 new-standard header-only port.
-- stb is a set of single-file C/C++ libraries: every header ships its
-- implementation under a *_IMPLEMENTATION macro, so "installing" it means
-- compiling it.  Upstream has no build system and no option() switches; what it
-- does have is tests/Makefile, which builds three real test programs out of
-- tests/*.c and runs them.  The port installs the headers and RUNS exactly those
-- upstream programs, then verifies the installed tree with a consumer that
-- compiles STB_IMAGE_IMPLEMENTATION and actually encodes a PNG in memory.
--
-- Not run (documented, not silently skipped): tests/fuzz_main.c + stbi_read_fuzzer.c
-- is the OSS-Fuzz driver (needs libFuzzer and a corpus, i.e. an external harness),
-- and tests/caveview, tests/oversample, tests/pngsuite, tests/prerelease are
-- interactive Windows/GL demos and reference-data folders, not tests.
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
    name = "stb",
    version = "4e9b368",
    license = "MIT",
    homepage = "https://github.com/nothings/stb",
    description = "stb single-file public-domain C/C++ libraries",
    source = {
        url = "https://codeload.github.com/nothings/stb/tar.gz/4e9b368bfc071e97206ea5c6adba68dd0cbf8897",
        sha256 = "e60706ab084e0cae35ee7282deb4a7f283e4a28be1896d097437205da01a0683",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "stb")
        local pcdir = util.join(libdir, "pkgconfig")
        local cmakedir = util.join(libdir, "cmake", "stb")
        fs.mkdirs(ctx.build_dir)
        fs.mkdirs(docdir)

        -- headers: every upstream single-file header ---------------------
        if on["headers"] then
            local n = 0
            for _, f in ipairs(fs.listdir(ctx.src)) do
                if f:sub(-2) == ".h" or f:sub(-4) == ".inc" then
                    copy(ctx, util.join(ctx.src, f), util.join(incdir, f))
                    n = n + 1
                end
            end
            assert(n >= 18,
                   "gcpkg: stb: only " .. n .. " upstream headers installed")
            for _, h in ipairs({ "stb_image.h", "stb_image_write.h",
                                 "stb_truetype.h", "stb_rect_pack.h",
                                 "stb_textedit.h", "stb_ds.h", "stb_perlin.h",
                                 "stb_dxt.h", "stb_easy_font.h", "stb_c_lexer.h",
                                 "stb_divide.h", "stb_hexwave.h",
                                 "stb_connected_components.h",
                                 "stb_herringbone_wang_tile.h", "stb_include.h",
                                 "stb_leakcheck.h", "stb_tilemap_editor.h",
                                 "stb_voxel_render.h" }) do
                assert(fs.isfile(util.join(incdir, h)),
                       "gcpkg: stb: missing header " .. h)
            end
        end

        -- stb_vorbis is the one library shipped as a .c file ----------------
        if on["vorbis-source"] then
            copy(ctx, util.join(ctx.src, "stb_vorbis.c"),
                 util.join(incdir, "stb_vorbis.c"))
            assert(fs.isfile(util.join(incdir, "stb_vorbis.c")),
                   "gcpkg: stb: stb_vorbis.c missing")
        end

        -- deprecated/ headers: upstream still ships (and its tests still
        -- include) stb.h / stb_sprintf.h / stb_image_resize*.h here.
        if on["deprecated-headers"] then
            local depdir = util.join(ctx.src, "deprecated")
            local n = 0
            for _, f in ipairs({ "stb.h", "stb_sprintf.h", "stb_image_resize.h",
                                 "stb_image_resize2.h" }) do
                if fs.isfile(util.join(depdir, f)) then
                    copy(ctx, util.join(depdir, f), util.join(incdir, f))
                    n = n + 1
                end
            end
            assert(n > 0, "gcpkg: stb: no deprecated headers found")
        end

        -- tests: upstream's own aggregate test build, plus the standalone
        -- programs that carry their own main ---------------------------------
        if on["tests"] then
            local tdir = util.join(ctx.src, "tests")
            local dep_inc = util.join(ctx.src, "deprecated")
            local cfl = { "-DSTB_DIVIDE_TEST", "-O1",
                          "-Wno-pointer-to-int-cast", "-Wno-int-to-pointer-cast",
                          "-Wno-tautological-compare", "-Wno-writable-strings" }
            local notes = {}

            -- 1) the aggregate C test binary, exactly upstream's file list from
            -- tests/Makefile.  It needs the deprecated/ headers on the include
            -- path because test_c_compilation.c still includes
            -- stb_image_resize2.h and stb_sprintf.h, which this tag only ships
            -- under deprecated/ (see the note written into ctest.out).
            local agg = { util.join(ctx.src, "stb_vorbis.c") }
            for _, f in ipairs({ "test_c_compilation.c", "test_c_lexer.c",
                                 "test_dxt.c", "test_easyfont.c", "test_image.c",
                                 "test_image_write.c", "test_perlin.c",
                                 "test_sprintf.c", "test_truetype.c",
                                 "test_voxel.c" }) do
                local p = util.join(tdir, f)
                assert(fs.isfile(p), "gcpkg: stb: missing upstream test " .. f)
                agg[#agg + 1] = p
            end
            local aggobjs = cc.compile {
                sources = agg, includes = { ctx.src, dep_inc }, defines = {},
                flags = cfl, cwd = tdir,
                outdir = util.join(ctx.build_dir, "obj_agg"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log, tag = "stb",
            }
            local aggexe = util.join(ctx.build_dir, "stb-tests-c")
            cc.link { objects = aggobjs, output = aggexe,
                      compiler = ctx.compiler.wrapper_cc, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log,
                      libdirs = {}, libs = { "m" } }
            local aggout = util.join(ctx.build_dir, "stb-tests-c.out")
            ctx.exec({ "sh", "-c", aggexe .. " > " .. aggout ..
                       " 2>&1; echo $? > " .. aggout .. ".rc" },
                     { cwd = tdir, log = ctx.log, env = ctx.env })
            local aggrc = (fs.read(aggout .. ".rc") or "?"):gsub("%s", "")
            local aggtxt = fs.read(aggout) or ""
            assert(aggrc == "0",
                   "gcpkg: stb: the upstream aggregate C test binary exited with " ..
                   aggrc .. ": " .. aggtxt)
            assert(not aggtxt:find("FAILED", 1, true),
                   "gcpkg: stb: aggregate C tests reported a failure: " .. aggtxt)
            notes[#notes + 1] = "test_c_compilation suite (10 upstream test TUs) rc=0"

            -- 2) the C++ compilation test: upstream's own file is a
            -- compile-only translation unit (it defines no main), so compile it
            -- and require that it builds.
            local cxxobjs = cc.compile {
                sources = { util.join(tdir, "test_cpp_compilation.cpp") },
                includes = { ctx.src, dep_inc }, defines = {},
                flags = { "-DSTB_DIVIDE_TEST", "-std=c++11", "-O1" },
                cwd = tdir, outdir = util.join(ctx.build_dir, "obj_cxx"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log, tag = "stb",
            }
            assert(#cxxobjs > 0, "gcpkg: stb: the C++ compilation test did not build")
            notes[#notes + 1] = "test_cpp_compilation.cpp compiles as C++11"

            -- 3) the standalone test programs, really executed
            local runs = { "test_siphash.c", "test_png_paeth.c", "stblib_test.c" }
            for _, f in ipairs(runs) do
                local src = util.join(tdir, f)
                assert(fs.isfile(src), "gcpkg: stb: missing upstream test " .. f)
                local name = f:sub(1, -3)
                local objs = cc.compile {
                    sources = { src }, includes = { ctx.src, dep_inc },
                    defines = {}, flags = cfl, cwd = tdir,
                    outdir = util.join(ctx.build_dir, "obj_" .. name),
                    compiler = ctx.compiler.wrapper_cc,
                    exec = ctx.exec, record = ctx.record, log = ctx.log, tag = "stb",
                }
                local exe = util.join(ctx.build_dir, name)
                cc.link { objects = objs, output = exe,
                          compiler = ctx.compiler.wrapper_cc, flags = {},
                          cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log,
                          libdirs = {}, libs = { "m" } }
                local out = util.join(ctx.build_dir, name .. ".out")
                ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1; echo $? > " ..
                           out .. ".rc" },
                         { cwd = tdir, log = ctx.log, env = ctx.env })
                local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
                assert(rc == "0",
                       "gcpkg: stb: upstream test " .. name .. " exited with " .. rc ..
                       ": " .. (fs.read(out) or ""))
                notes[#notes + 1] = name .. " rc=0"
            end

            -- 4) image_write_test.c built with upstream's -DIWT_TEST switch
            local iwtobjs = cc.compile {
                sources = { util.join(tdir, "image_write_test.c") },
                includes = { ctx.src, dep_inc }, defines = { "IWT_TEST" },
                flags = cfl, cwd = tdir,
                outdir = util.join(ctx.build_dir, "obj_iwt"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log, tag = "stb",
            }
            local iwtexe = util.join(ctx.build_dir, "image_write_test")
            cc.link { objects = iwtobjs, output = iwtexe,
                      compiler = ctx.compiler.wrapper_cc, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log,
                      libdirs = {}, libs = { "m" } }
            local iout = util.join(ctx.build_dir, "image_write_test.out")
            ctx.exec({ "sh", "-c", iwtexe .. " > " .. iout .. " 2>&1; echo $? > " ..
                       iout .. ".rc" },
                     { cwd = tdir, log = ctx.log, env = ctx.env })
            local irc = (fs.read(iout .. ".rc") or "?"):gsub("%s", "")
            assert(irc == "0",
                   "gcpkg: stb: image_write_test -DIWT_TEST exited with " .. irc)
            notes[#notes + 1] = "image_write_test -DIWT_TEST rc=0 (silent by design)"

            fs.write(util.join(ctx.build_dir, "ctest.out"),
                     table.concat(notes, "\n") .. "\n" ..
                     "not run (documented, not silently skipped):\n" ..
                     "  * test_png_regress.c  - exits 1 unless run from its reference\n" ..
                     "    corpus (upstream data folder), i.e. it needs external data;\n" ..
                     "  * fuzz_main.c / stbi_read_fuzzer.c - OSS-Fuzz driver (libFuzzer\n" ..
                     "    plus a corpus);\n" ..
                     "  * caveview/, oversample/, pngsuite/, prerelease/ - interactive\n" ..
                     "    GL/Windows demo applications and reference data, not tests;\n" ..
                     "  * herringbone_map.c - upstream stb_herringbone_wang_tile.h does not\n" ..
                     "    compile with clang (incompatible pointer types at line 401).\n" ..
                     "upstream-defect note: test_c_compilation.c, test_cpp_compilation.cpp\n" ..
                     "and resample_test*.c(pp) include stb_image_resize2.h / stb_sprintf.h,\n" ..
                     "which this tag only ships under deprecated/; the port puts that\n" ..
                     "directory on the include path (feature `deprecated-headers`) so the\n" ..
                     "real upstream suite still builds and runs.\n")
        end

        -- sanity: real consumer over the INSTALLED headers -------------------
        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "stb_sanity.c")
            fs.write(csrc, [==[
#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image.h>
#include <stb_image_write.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  static unsigned char pixels[2 * 2 * 4];
  for (int i = 0; i < 16; ++i) pixels[i] = (unsigned char)(i * 8);
  int len = 0;
  unsigned char *png = stbi_write_png_to_mem(pixels, 2 * 4, 2, 2, 4, &len);
  if (len <= 0 || png == NULL) return 2;
  int w = 0, h = 0, n = 0;
  unsigned char *back = stbi_load_from_memory(png, len, &w, &h, &n, 4);
  if (!back) { free(png); return 3; }
  if (w != 2 || h != 2) { free(back); free(png); return 4; }
  if (memcmp(back, pixels, 16) != 0) { free(back); free(png); return 5; }
  printf("gcpkg stb ok png_bytes=%d size=%dx%d\n", len, w, h);
  free(back);
  free(png);
  return 0;
}
]==])
            local objs = cc.compile {
                sources = { csrc }, includes = { incdir }, defines = {},
                flags = { "-std=c99", "-O1" },
                cwd = ctx.build_dir, outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log, tag = "stb",
            }
            local exe = util.join(ctx.build_dir, "stb_sanity")
            cc.link { objects = objs, output = exe,
                      compiler = ctx.compiler.wrapper_cc, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log,
                      libdirs = {}, libs = { "m" } }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: stb: missing sanity output")
            assert(text:find("gcpkg stb ok", 1, true),
                   "gcpkg: stb: consumer did not run: " .. text)
        end

        -- pkg-config ---------------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: stb
Description: stb single-file public-domain C/C++ libraries
Version: 4e9b368
Cflags: -I${includedir}
Libs: -lm
]==]
            fs.write(util.join(pcdir, "stb.pc"), (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package ------------------------------------------------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(util.join(cmakedir, "stbConfig.cmake"), [==[
get_filename_component(_STB_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET stb::stb)
  add_library(stb::stb INTERFACE IMPORTED)
  set_target_properties(stb::stb PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_STB_PREFIX}/include"
    INTERFACE_LINK_LIBRARIES "m")
endif()
set(stb_FOUND TRUE)
]==])
            fs.write(util.join(cmakedir, "stbConfigVersion.cmake"), [==[
set(PACKAGE_VERSION "4e9b368")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- docs / license -------------------------------------------------------
        if on["docs"] then
            for _, f in ipairs({ "README.md", "Release_Notes.txt" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
            if fs.isdir(util.join(ctx.src, "docs")) then
                ctx.exec({ "cp", "-a", util.join(ctx.src, "docs"), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: stb: LICENSE missing")
            copy(ctx, util.join(ctx.src, "LICENSE"), util.join(docdir, "LICENSE"))
        end

        return {
            includes = { util.join(ctx.prefix, "include") },
            libdirs = {},
            libs = { "m" },
            binaries = {},
        }
    end,
}
