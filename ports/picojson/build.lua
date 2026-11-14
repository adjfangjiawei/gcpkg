-- picojson 111c9be -- R20 new-standard header-only port.
-- Upstream ships headers only (no build system, no configure, no probes).
-- gcpkg installs the headers, generates pkg-config + CMake CONFIG metadata,
-- and then VERIFIES the install by building and running real translation
-- units: the upstream test.cc suite is built twice and executed.
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
    name = "picojson",
    version = "111c9be",
    license = "BSD-2-Clause",
    homepage = "https://github.com/kazuho/picojson",
    description = "PicoJSON header-only C++ JSON parser/serializer (pinned 111c9be)",
    source = {
        url = "https://codeload.github.com/kazuho/picojson/tar.gz/111c9be5188f7350c2eac9ddaedd8cca3d7bf394",
        sha256 = "671f89832a17e9e71398f80c0a326afa2ebe81f4c26d5a9992e1fcd0888ae151",
        strip = 1,
    },
    dependencies = { "curl" },
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local libdir = ctx.prefix .. "/lib"
        local docdir = ctx.prefix .. "/share/doc/picojson"
        local pcdir = libdir .. "/pkgconfig"
        local cmakedir = libdir .. "/cmake/picojson"
        local objdir = ctx.build_dir .. "/obj"
        fs.mkdirs(ctx.build_dir); fs.mkdirs(objdir)

        -- headers ------------------------------------------------------
        if on["headers"] then
            copy(ctx, ctx.src .. "/picojson.h", incdir .. "/picojson.h")
            copy(ctx, ctx.src .. "/picojson.h", incdir .. "/picojson/picojson.h")
        end

        -- tests: the upstream test.cc suite is built twice and executed -------------------------------------------
        if on["tests"] then
            local function build_and_run(tag, extra_defines)
                local pc = ctx.build_dir .. "/picotest_" .. tag .. ".cpp"
                fs.write(pc, fs.read(ctx.src .. "/picotest/picotest.c") or "")
                local objs = cc.compile {
                    sources = { ctx.src .. "/test.cc", pc },
                    includes = { ctx.src, ctx.src .. "/picotest" },
                    defines = extra_defines or {},
                    flags = { "-std=c++17", "-O2" },
                    cwd = ctx.src, outdir = ctx.build_dir .. "/obj_" .. tag,
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "picojson",
                }
                local exe = ctx.build_dir .. "/test-core-" .. tag
                cc.link { objects = objs, output = exe,
                          compiler = ctx.compiler.wrapper_cxx, flags = {},
                          cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
                local out = ctx.build_dir .. "/test-" .. tag .. ".out"
                ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local text = assert(fs.read(out),
                                    "gcpkg: picojson: missing " .. tag .. " test output")
                assert(not text:find("not ok", 1, true),
                       "gcpkg: picojson: " .. tag .. " reported a failing assertion")
                local _, ok_count = text:gsub("ok %d+", "")
                assert(ok_count > 50,
                       "gcpkg: picojson: " .. tag .. " ran only " .. ok_count ..
                       " assertions, expected the full upstream suite")
            end
            -- upstream Makefile target `test`: default and PICOJSON_USE_INT64
            build_and_run("default", {})
            build_and_run("int64", { "PICOJSON_USE_INT64" })
        end

        -- examples -----------------------------------------------------
        if on["examples"] then
            local exdir = ctx.build_dir .. "/examples_bin"
            fs.mkdirs(exdir)
            -- iostream.cc / streaming.cc read stdin and print parsed results
            -- NOTE: examples/streaming.cc does not compile at this commit: it
            -- subclasses picojson::deny_parse_context and relies on
            -- parse_object_stop(), which its own picojson.h no longer calls.
            -- That is an upstream defect, not a missing option, so the port does
            -- not pretend to build it.
            local runs = {
                { name = "iostream", stdin = "{\"a\":1,\"b\":[true,null,\"s\"]}", expect = "---- analyzing input ----" },
            }
            for _, ex in ipairs(runs) do
                local objs = cc.compile {
                    sources = { ctx.src .. "/examples/" .. ex.name .. ".cc" },
                    includes = { ctx.src },
                    defines = {},
                    flags = { "-std=c++17", "-O2" },
                    cwd = ctx.src, outdir = ctx.build_dir .. "/obj_ex_" .. ex.name,
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "picojson",
                }
                local exe = exdir .. "/" .. ex.name
                cc.link { objects = objs, output = exe,
                          compiler = ctx.compiler.wrapper_cxx, flags = {},
                          cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
                local outf = ctx.build_dir .. "/example-" .. ex.name .. ".out"
                local sh = "printf '%s' " .. string.format("%q", ex.stdin) ..
                           " | " .. exe .. " > " .. outf .. " 2>&1"
                ctx.exec({ "sh", "-c", sh }, { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local text = assert(fs.read(outf),
                                    "gcpkg: picojson: missing " .. ex.name .. " output")
                assert(text:find(ex.expect, 1, true),
                       "gcpkg: picojson: example " .. ex.name .. " did not print its result")
            end
            -- github-issues.cc is compiled against the SOURCE-BUILT curl port; it is
            -- not executed because it performs live HTTP requests (no network at
            -- install time).  Compiling it still proves the integration is real.
            if on["example-curl"] then
                local dep = ctx.dep("curl")
                local incs = { ctx.src }
                for _, i in ipairs((dep and dep.includes) or {}) do incs[#incs + 1] = i end
                local objs = cc.compile {
                    sources = { ctx.src .. "/examples/github-issues.cc" },
                    includes = incs, defines = {},
                    -- upstream's Makefile builds the examples with the default
                    -- dialect; with C++11+ the file is ambiguous between
                    -- std::array and picojson::array (upstream defect), so it is
                    -- compiled exactly like upstream does: C++98.
                    flags = { "-std=c++98", "-O2" },
                    cwd = ctx.src, outdir = ctx.build_dir .. "/obj_ex_curl",
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "picojson",
                }
                local libdirs = {}
                for _, l in ipairs((dep and dep.libdirs) or {}) do libdirs[#libdirs + 1] = l end
                cc.link { objects = objs, output = exdir .. "/github-issues",
                          compiler = ctx.compiler.wrapper_cxx, flags = {},
                          cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log,
                          libdirs = libdirs, libs = { "curl" } }
            end
        end

        -- pkgconfig ----------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: picojson
Description: PicoJSON header-only C++ JSON parser/serializer (pinned 111c9be)
Version: 111c9be
Cflags: -I${includedir}
]==]
            fs.write(pcdir .. "/picojson.pc", (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package -----------------------------------------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(cmakedir .. "/picojsonConfig.cmake", [==[
get_filename_component(_P_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET picojson::picojson)
  add_library(picojson::picojson INTERFACE IMPORTED)
  set_target_properties(picojson::picojson PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_P_PREFIX}/include")
endif()
set(picojson_FOUND TRUE)
]==])
            fs.write(cmakedir .. "/picojsonConfigVersion.cmake", [==[
set(PACKAGE_VERSION "111c9be")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- docs / license -----------------------------------------------
        if on["docs"] then
            copy(ctx, ctx.src .. "/README.mkdn", docdir .. "/README.mkdn")
            copy(ctx, ctx.src .. "/Changes", docdir .. "/Changes")
        end
        if on["license"] then
            copy(ctx, ctx.src .. "/LICENSE", docdir .. "/LICENSE")
        end

        -- sanity: real consumer over the INSTALLED headers --------------
        if on["sanity"] then
            assert(on["headers"], "gcpkg: picojson: sanity needs headers")
            local csrc = ctx.build_dir .. "/picojson_sanity.cpp"
            fs.write(csrc, [==[
#include <picojson/picojson.h>
#include <string>
#include <cstdio>

int main() {
  picojson::value v;
  std::string err = picojson::parse(v, "{\"port\":\"picojson\",\"n\":3}");
  if (!err.empty()) { std::printf("parse error: %s\n", err.c_str()); return 2; }
  if (!v.is<picojson::object>()) return 3;
  if (v.get("port").to_str() != "picojson") return 4;
  std::printf("gcpkg picojson ok %s\n", v.serialize().c_str());
  return 0;
}
]==])
            local exe = ctx.build_dir .. "/picojson_sanity"
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir, outdir = objdir,
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "picojson", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = ctx.build_dir .. "/sanity.out"
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out),
                                "gcpkg: picojson: missing sanity output")
            assert(text:find("gcpkg picojson ok", 1, true),
                   "gcpkg: picojson: consumer did not run: " .. text)
        end

        return {
            includes = on["headers"] and { incdir } or {},
            libdirs = {}, libs = on["examples"] and {} or {},
            binaries = {}, defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
