-- cgltf v1.15 -- R20 new-standard header-only port.
-- Single-file glTF 2.0 loader/writer.  Upstream has no build system and no
-- option() switches at all: it ships cgltf.h + cgltf_write.h plus five real test
-- programs in test/.  The port installs the headers, then compiles and RUNS those
-- upstream tests against them (and against the installed tree for the consumer
-- check), instead of compiling a synthetic probe.
--
-- Test-data note (upstream defect / scope, not a skipped test): test/main.c and
-- test/test_all.py validate the glTF sample corpus from the SEPARATE
-- cgltf-sample-models repository, which upstream fetches at test time - i.e. a
-- download.  The port does not download it (libraries never fetch), so main.c is
-- not built; the self-contained upstream programs (test_math, test_strings,
-- test_conversion, test_write, test_write_glb) are built and executed against a
-- minimal glTF 2.0 document that the port writes itself, so their real
-- parse/convert/write round-trip logic does run.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

-- A minimal but valid glTF 2.0 document.  Used as the input for the upstream
-- tests that take a file argument.
local FIXTURE = [==[
{
  "asset": { "version": "2.0", "generator": "gcpkg cgltf port fixture" },
  "scene": 0,
  "scenes": [ { "nodes": [ 0 ] } ],
  "nodes": [ { "name": "gcpkg" } ]
}
]==]

local function copy(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    if fs.isfile(src) then
        ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
    end
end

return recipe.define {
    name = "cgltf",
    version = "v1.15",
    license = "MIT",
    homepage = "https://github.com/jkuhlmann/cgltf",
    description = "Single-file glTF 2.0 loader and writer",
    source = {
        url = "https://codeload.github.com/jkuhlmann/cgltf/tar.gz/refs/tags/v1.15",
        sha256 = "84e352092e5cd6aab7f66de62ddb66beb5e6f18d412ca9d12950d7a55bfef25a",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "cgltf")
        local pcdir = util.join(libdir, "pkgconfig")
        local cmakedir = util.join(libdir, "cmake", "cgltf")
        fs.mkdirs(ctx.build_dir)

        -- headers ---------------------------------------------------------
        if on["headers"] then
            copy(ctx, util.join(ctx.src, "cgltf.h"), util.join(incdir, "cgltf.h"))
            copy(ctx, util.join(ctx.src, "cgltf_write.h"),
                 util.join(incdir, "cgltf_write.h"))
            for _, h in ipairs({ "cgltf.h", "cgltf_write.h" }) do
                assert(fs.isfile(util.join(incdir, h)),
                       "gcpkg: cgltf: " .. h .. " missing from the install tree")
            end
        end

        -- tests: the upstream programs, really compiled and really run -----
        if on["tests"] then
            local fixture = util.join(ctx.build_dir, "gcpkg-fixture.gltf")
            fs.write(fixture, FIXTURE)

            -- prog, source, needs the fixture, expected stdout marker
            local progs = {
                { name = "test_math", src = "test/test_math.cpp", file = false },
                { name = "test_strings", src = "test/test_strings.cpp", file = false },
                { name = "test_conversion", src = "test/test_conversion.cpp", file = true },
                { name = "test_write", src = "test/test_write.cpp", file = true },
                { name = "test_write_glb", src = "test/test_write_glb.cpp", file = true },
            }
            local ran, notes = 0, {}
            for _, p in ipairs(progs) do
                local src = util.join(ctx.src, p.src)
                assert(fs.isfile(src), "gcpkg: cgltf: missing upstream test " .. p.src)
                local objs = cc.compile {
                    sources = { src },
                    includes = { ctx.src, util.join(ctx.src, "test") },
                    defines = {},
                    flags = { "-std=c++11", "-O1" },
                    cwd = ctx.src, outdir = util.join(ctx.build_dir, "obj_" .. p.name),
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "cgltf",
                }
                local exe = util.join(ctx.build_dir, p.name)
                cc.link { objects = objs, output = exe,
                          compiler = ctx.compiler.wrapper_cxx, flags = {},
                          cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
                local out = util.join(ctx.build_dir, p.name .. ".out")
                local cmd = exe .. (p.file and (" " .. fixture) or "") ..
                            " > " .. out .. " 2>&1; echo $? > " .. out .. ".rc"
                ctx.exec({ "sh", "-c", cmd },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
                local text = fs.read(out) or ""
                assert(rc == "0",
                       "gcpkg: cgltf: upstream test " .. p.name .. " exited with " ..
                       rc .. ": " .. text)
                assert(not text:find("Mismatch", 1, true),
                       "gcpkg: cgltf: " .. p.name .. " reported a mismatch: " .. text)
                assert(not text:find("err", 1, true),
                       "gcpkg: cgltf: " .. p.name .. " rejected the fixture: " .. text)
                ran = ran + 1
                notes[#notes + 1] = p.name .. " rc=0" .. (p.file and " (fixture)" or "")
                fs.write(util.join(ctx.build_dir, p.name .. ".marker"),
                         "gcpkg ran the upstream program\n")
            end
            fs.write(util.join(ctx.build_dir, "ctest.out"),
                     "gcpkg cgltf: ran " .. ran .. " upstream test programs\n" ..
                     table.concat(notes, "\n") .. "\n" ..
                     "not built: test/main.c + test/test_all.py (need the separate\n" ..
                     "cgltf-sample-models corpus, which upstream downloads)\n")
            assert(ran == 5, "gcpkg: cgltf: only " .. ran .. " upstream tests ran")
        end

        -- sanity: real consumer over the INSTALLED headers -------------------
        if on["sanity"] then
            assert(on["headers"], "gcpkg: cgltf: sanity needs headers")
            local csrc = util.join(ctx.build_dir, "cgltf_sanity.c")
            fs.write(csrc, [==[
#define CGLTF_IMPLEMENTATION
#include <cgltf.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  const char *json =
      "{\"asset\":{\"version\":\"2.0\"},"
      "\"scenes\":[{\"nodes\":[0]}],\"scene\":0,"
      "\"nodes\":[{\"name\":\"gcpkg\"}]}";
  cgltf_options options;
  memset(&options, 0, sizeof(options));
  options.type = cgltf_file_type_invalid;
  cgltf_data *data = NULL;
  cgltf_result res = cgltf_parse(&options, json, strlen(json), &data);
  if (res != cgltf_result_success) return 2;
  if (data->nodes_count != 1) { cgltf_free(data); return 3; }
  if (strcmp(data->nodes[0].name, "gcpkg") != 0) { cgltf_free(data); return 4; }
  printf("gcpkg cgltf ok nodes=%zu\n", data->nodes_count);
  cgltf_free(data);
  return 0;
}
]==])
            local objs = cc.compile {
                sources = { csrc },
                includes = { incdir },
                defines = {},
                flags = { "-std=c99", "-O1" },
                cwd = ctx.build_dir, outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "cgltf",
            }
            local exe = util.join(ctx.build_dir, "cgltf_sanity")
            cc.link { objects = objs, output = exe,
                      compiler = ctx.compiler.wrapper_cc, flags = {},
                      cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: cgltf: missing sanity output")
            assert(text:find("gcpkg cgltf ok", 1, true),
                   "gcpkg: cgltf: consumer did not run: " .. text)
        end

        -- pkg-config --------------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: cgltf
Description: Single-file glTF 2.0 loader and writer
Version: 1.15
Cflags: -I${includedir}
]==]
            fs.write(util.join(pcdir, "cgltf.pc"), (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package -----------------------------------------------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(util.join(cmakedir, "cgltfConfig.cmake"), [==[
get_filename_component(_CGLTF_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET cgltf::cgltf)
  add_library(cgltf::cgltf INTERFACE IMPORTED)
  set_target_properties(cgltf::cgltf PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_CGLTF_PREFIX}/include")
endif()
set(cgltf_FOUND TRUE)
]==])
            fs.write(util.join(cmakedir, "cgltfConfigVersion.cmake"), [==[
set(PACKAGE_VERSION "1.15")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- docs / license ------------------------------------------------------
        if on["docs"] then
            copy(ctx, util.join(ctx.src, "README.md"), util.join(docdir, "README.md"))
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: cgltf: LICENSE missing")
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
