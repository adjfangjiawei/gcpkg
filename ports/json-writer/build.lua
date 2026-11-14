-- json-writer 6fa1122 -- R20 new-standard header-only port.
-- Upstream ships headers only (no build system, no configure, no probes).
-- gcpkg installs the headers, generates pkg-config + CMake CONFIG metadata,
-- and then VERIFIES the install by building and running real translation
-- units: the documented writer scenario is compiled, executed and its JSON output validated.
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
    name = "json-writer",
    version = "6fa1122",
    license = "MIT",
    homepage = "https://github.com/rmisev/json_writer",
    description = "json_writer header-only C++ JSON writer (pinned 6fa1122)",
    source = {
        url = "https://codeload.github.com/rmisev/json_writer/tar.gz/6fa11221d22bfd46b3a8ce143452d4918e5706e3",
        sha256 = "76bebf99bc7878c0968e1b2d4f76cb42e55c5d1db3b35dc6bb0ea4948c40cdab",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local libdir = ctx.prefix .. "/lib"
        local docdir = ctx.prefix .. "/share/doc/json-writer"
        local pcdir = libdir .. "/pkgconfig"
        local cmakedir = libdir .. "/cmake/json-writer"
        local objdir = ctx.build_dir .. "/obj"
        fs.mkdirs(ctx.build_dir); fs.mkdirs(objdir)

        -- headers ------------------------------------------------------
        if on["headers"] then
            copy(ctx, ctx.src .. "/json_writer.h", incdir .. "/json_writer.h")
            copy(ctx, ctx.src .. "/json_writer.h", incdir .. "/json_writer/json_writer.h")
        end

        -- tests: the documented writer scenario is compiled, executed and its JSON output validated -------------------------------------------
        if on["tests"] then
            local tsrc = ctx.build_dir .. "/json_writer_doc_test.cpp"
            fs.write(tsrc, [==[
#include <json_writer/json_writer.h>
#include <sstream>
#include <string>
#include <cstdio>

int main() {
  std::ostringstream os;
  {
    json_writer w(os, 2);
    w.object_start();
    w.name("port"); w.value("json-writer");
    w.name("count"); w.value(42);
    w.name("enabled"); w.value_bool(true);
    w.name("tags");
    w.array_start(); w.value("a"); w.value("b"); w.array_end();
    w.object_end();
  }
  const std::string s = os.str();
  std::printf("%s\n", s.c_str());
  if (s.find("port") == std::string::npos) return 2;
  if (s.find("42") == std::string::npos) return 3;
  if (s.find("true") == std::string::npos) return 4;
  if (s.find("tags") == std::string::npos) return 5;
  if (s.find("{") == std::string::npos) return 6;
  std::printf("gcpkg json-writer scenario ok\n");
  return 0;
}
]==])
            local texe = ctx.build_dir .. "/json_writer_doc_test"
            cc.executable {
                sources = { tsrc }, includes = { incdir },
                flags = { "-std=c++17" }, cwd = ctx.build_dir, outdir = objdir .. "_t",
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "json-writer", cxx = true, output = texe, libdirs = {}, libs = {},
            }
            local tout = ctx.build_dir .. "/doc_scenario.out"
            ctx.exec({ "sh", "-c", texe .. " > " .. tout .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local ttext = assert(fs.read(tout), "gcpkg: json-writer: missing scenario output")
            assert(ttext:find("scenario ok", 1, true),
                   "gcpkg: json-writer: documented scenario failed: " .. ttext)
        end

        -- examples -----------------------------------------------------
        if on["examples"] then
            -- upstream ships no example programs
        end

        -- pkgconfig ----------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: json-writer
Description: json_writer header-only C++ JSON writer (pinned 6fa1122)
Version: 6fa1122
Cflags: -I${includedir}
]==]
            fs.write(pcdir .. "/json-writer.pc", (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package -----------------------------------------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(cmakedir .. "/json-writerConfig.cmake", [==[
get_filename_component(_P_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET json-writer::json-writer)
  add_library(json-writer::json-writer INTERFACE IMPORTED)
  set_target_properties(json-writer::json-writer PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_P_PREFIX}/include")
endif()
set(json-writer_FOUND TRUE)
]==])
            fs.write(cmakedir .. "/json-writerConfigVersion.cmake", [==[
set(PACKAGE_VERSION "6fa1122")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- docs / license -----------------------------------------------
        if on["docs"] then
            -- upstream ships no separate documentation file
        end
        if on["license"] then
            copy(ctx, ctx.src .. "/LICENSE", docdir .. "/LICENSE")
        end

        -- sanity: real consumer over the INSTALLED headers --------------
        if on["sanity"] then
            assert(on["headers"], "gcpkg: json-writer: sanity needs headers")
            local csrc = ctx.build_dir .. "/json-writer_sanity.cpp"
            fs.write(csrc, [==[
#include <json_writer/json_writer.h>
#include <sstream>
#include <string>
#include <cstdio>

int main() {
  std::ostringstream os;
  {
    json_writer w(os);
    w.object_start();
    w.name("ok"); w.value_bool(true);
    w.object_end();
  }
  if (os.str().find("true") == std::string::npos) return 2;
  std::printf("gcpkg json-writer ok\n");
  return 0;
}
]==])
            local exe = ctx.build_dir .. "/json-writer_sanity"
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir, outdir = objdir,
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "json-writer", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = ctx.build_dir .. "/sanity.out"
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out),
                                "gcpkg: json-writer: missing sanity output")
            assert(text:find("gcpkg json-writer ok", 1, true),
                   "gcpkg: json-writer: consumer did not run: " .. text)
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
