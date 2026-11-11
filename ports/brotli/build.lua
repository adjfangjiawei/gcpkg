-- brotli 1.1.0 -- R20 new-standard re-audit of the curl L0 chain.
-- Declarative recipe.cmake keeps the framework absolute-no-probe injection,
-- shared per-triplet facts and CMAKE_PREFIX_PATH. Positive features.yaml args
-- are appended last (dedup_defines) so they override any recipe default;
-- `tests` injects -DBROTLI_DISABLE_TESTS=OFF, enabling the upstream ctest
-- roundtrip/compatibility suite. post_install really runs ctest + a C consumer.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

return recipe.cmake {
    name = "brotli",
    version = "1.1.0",
    description = "Brotli compression library (common/dec/enc + CLI)",
    license = "MIT",
    homepage = "https://github.com/google/brotli",
    source = {
        url = "https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz",
        sha256 = "e720a6ca29428b803f4ad165371771f5398faba397edf6778837a18599ea13ff",
        strip = 1,
    },
    -- L0: no gcpkg dependencies. Dynamic requires live in features.yaml.
    dependencies = {},
    cmake = {
        defines = {
            CMAKE_BUILD_TYPE = "Release",
            -- Explicit probe results consumed by gcpkg's absolute-no-probe
            -- injection: no check_*/try_compile is actually run.
            BROTLI_EMSCRIPTEN = "FALSE",
            LOG2_RES = "FALSE",
            LOG2_LIBM_RES = "TRUE",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "brotlienc", "brotlidec", "brotlicommon" },
        binaries = { "@PREFIX@/bin" },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local prefix = ctx.prefix
        local libdir = util.join(prefix, "lib")
        if not fs.isfile(util.join(libdir, "libbrotlienc.a")) and
           not fs.isfile(util.join(libdir, "libbrotlienc.so")) and
           fs.isdir(util.join(prefix, "lib64")) then
            libdir = util.join(prefix, "lib64")
        end
        local incdir = util.join(prefix, "include")
        local docdir = util.join(prefix, "share", "doc", "brotli")
        local cmakedir = util.join(libdir, "cmake", "brotli")
        fs.mkdirs(docdir)

        local function libpath(name)
            for _, p in ipairs({
                util.join(libdir, name .. ".a"),
                util.join(libdir, name .. ".so"),
            }) do
                if fs.isfile(p) then return p end
            end
            return nil
        end

        -- library / headers / tools / pkgconfig: assert real artifacts.
        if on["library"] then
            for _, name in ipairs({ "libbrotlicommon", "libbrotlidec", "libbrotlienc" }) do
                assert(libpath(name),
                       "gcpkg: brotli: missing library " .. name)
            end
        end
        if on["headers"] then
            assert(fs.isfile(util.join(incdir, "brotli", "encode.h")),
                   "gcpkg: brotli: brotli/encode.h missing")
            assert(fs.isfile(util.join(incdir, "brotli", "decode.h")),
                   "gcpkg: brotli: brotli/decode.h missing")
        end
        if on["tools"] then
            assert(fs.isfile(util.join(prefix, "bin", "brotli")),
                   "gcpkg: brotli: brotli CLI missing")
        end
        if on["pkgconfig"] then
            for _, name in ipairs({ "libbrotlicommon.pc", "libbrotlidec.pc", "libbrotlienc.pc" }) do
                assert(fs.isfile(util.join(libdir, "pkgconfig", name)),
                       "gcpkg: brotli: missing " .. name)
            end
        end

        -- docs / license: install real upstream files, no fabrication.
        if on["docs"] then
            for _, name in ipairs({ "README", "README.md", "CONTRIBUTING.md", "CHANGELOG.md" }) do
                local src = util.join(ctx.src, name)
                if fs.isfile(src) then
                    ctx.exec({ "cp", "-a", src, util.join(docdir, name) },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            local lic = util.join(ctx.src, "LICENSE")
            if fs.isfile(lic) then
                ctx.exec({ "cp", "-a", lic, util.join(docdir, "LICENSE") },
                         { cwd = ctx.src, log = ctx.log })
            end
        end

        -- CONFIG package: three imported static/shared targets.
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            -- Choose STATIC/SHARED by which artifact actually exists.
            local ext = fs.isfile(util.join(libdir, "libbrotlienc.a")) and ".a" or ".so"
            local function block(target, lib)
                return "if(NOT TARGET " .. target .. ")\n" ..
                       "  add_library(" .. target .. " " ..
                       (ext == ".a" and "STATIC" or "SHARED") .. " IMPORTED)\n" ..
                       "  set_target_properties(" .. target .. " PROPERTIES\n" ..
                       '    IMPORTED_LOCATION "${_BROTLI_LIBDIR}/' .. lib .. ext .. '"\n' ..
                       '    INTERFACE_INCLUDE_DIRECTORIES "${_BROTLI_PREFIX}/include")\n' ..
                       "endif()\n"
            end
            local cfg = [==[
get_filename_component(_BROTLI_LIBDIR "${CMAKE_CURRENT_LIST_DIR}" PATH)
get_filename_component(_BROTLI_LIBDIR "${_BROTLI_LIBDIR}" PATH)
get_filename_component(_BROTLI_PREFIX "${_BROTLI_LIBDIR}" PATH)
]==] ..
                block("brotlicommon", "libbrotlicommon") ..
                block("brotlidec", "libbrotlidec") ..
                block("brotlienc", "libbrotlienc") ..
                [==[
# Static brotlienc/brotlidec reference log2 (BROTLI_HAVE_LOG2=1), so libm is
# part of the link interface for both the per-lib and aggregate targets.
set_target_properties(brotlidec PROPERTIES INTERFACE_LINK_LIBRARIES "brotlicommon;m")
set_target_properties(brotlienc PROPERTIES INTERFACE_LINK_LIBRARIES "brotlicommon;m")
if(NOT TARGET brotli)
  add_library(brotli INTERFACE IMPORTED)
  set_property(TARGET brotli PROPERTY INTERFACE_LINK_LIBRARIES "brotlienc;brotlidec;brotlicommon;m")
endif()
set(brotli_FOUND TRUE)
]==]
            fs.write(util.join(cmakedir, "brotliConfig.cmake"), cfg)
            fs.write(util.join(cmakedir, "brotliConfigVersion.cmake"), [==[
set(PACKAGE_VERSION "1.1.0")
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
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c", "ctest --output-on-failure > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: brotli: missing ctest output")
            assert(not result:find("No tests were found", 1, true),
                   "gcpkg: brotli: ctest found no registered tests")
            assert(result:find("100% tests passed", 1, true),
                   "gcpkg: brotli: ctest did not pass")
        end

        -- sanity: compile and run a real consumer linked to the installed libs.
        if on["sanity"] then
            assert(on["library"] and on["headers"],
                   "gcpkg: brotli: sanity needs library and headers")
            local src = util.join(ctx.build_dir, "brotli_sanity.c")
            fs.write(src, [==[
#include <brotli/encode.h>
#include <brotli/decode.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    const char *msg = "gcpkg brotli newstd round trip 1234567890";
    size_t inLen = strlen(msg) + 1;
    size_t cap = BrotliEncoderMaxCompressedSize(inLen) + 64;
    uint8_t *enc = (uint8_t *)malloc(cap);
    if (!enc) return 2;
    size_t encLen = cap;
    if (BrotliEncoderCompress(6, BROTLI_DEFAULT_WINDOW, BROTLI_MODE_GENERIC,
                              inLen, (const uint8_t *)msg, &encLen, enc) != BROTLI_TRUE) return 3;
    uint8_t dec[512];
    size_t decLen = sizeof(dec);
    if (BrotliDecoderDecompress(encLen, enc, &decLen, dec) != BROTLI_DECODER_RESULT_SUCCESS) return 4;
    if (decLen != inLen || memcmp(dec, msg, inLen) != 0) return 5;
    printf("gcpkg brotli ok: %s / compressed=%zu\n", (char *)dec, encLen);
    free(enc);
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
                tag = "brotli", cxx = false,
                output = util.join(ctx.build_dir, "brotli_sanity"),
                libdirs = { libdir },
                libs = { "brotlienc", "brotlidec", "brotlicommon", "m" },
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", bin .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: brotli: missing sanity output")
            assert(result:find("gcpkg brotli ok", 1, true),
                   "gcpkg: brotli: C consumer did not run")
        end
    end,
}
