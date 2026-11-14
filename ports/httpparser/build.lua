-- httpparser 2.9.4 -- R20 new-standard port (nodejs/http-parser).
-- Upstream is one C file plus a hand-written Makefile: no configure step, no
-- probes, no downloads.  Everything is built from the tarball with gcpkg's
-- compiler wrapper, and every default-on feature is verified after the fact
-- (real upstream test binaries are executed, a real C consumer is compiled,
-- linked and run against the installed tree).
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local function copy(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
end

return recipe.define {
    name = "httpparser",
    version = "2.9.4",
    license = "MIT",
    homepage = "https://github.com/nodejs/http-parser",
    description = "HTTP request/response parser in C",
    source = {
        url = "https://codeload.github.com/nodejs/http-parser/tar.gz/refs/tags/v2.9.4",
        sha256 = "467b9e30fd0979ee301065e70f637d525c28193449e1b13fbcb1b1fab3ad224f",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local libdir = ctx.prefix .. "/lib"
        local bindir = ctx.prefix .. "/bin"
        local docdir = ctx.prefix .. "/share/doc/httpparser"
        local srcdir = ctx.prefix .. "/share/httpparser/src"
        local pcdir = libdir .. "/pkgconfig"
        local cmakedir = libdir .. "/cmake/httpparser"
        fs.mkdirs(ctx.build_dir)

        local function compile(sources, outdir, defines, flags)
            return cc.compile {
                sources = sources, includes = { ctx.src },
                defines = defines or {},
                flags = flags or { "-O3", "-fPIC" },
                cwd = ctx.src, outdir = ctx.build_dir .. "/" .. outdir,
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "httpparser",
            }
        end
        local function link(objects, output, flags)
            return cc.link {
                objects = objects, output = output,
                compiler = ctx.compiler.wrapper_cc, flags = flags or {},
                cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log,
            }
        end

        -- library / static / shared -------------------------------------
        local libObjs = nil
        if on["library"] then
            assert(on["static"] or on["shared"],
                   "gcpkg: httpparser: library needs static and/or shared")
            fs.mkdirs(incdir); fs.mkdirs(libdir)
            libObjs = compile({ ctx.src .. "/http_parser.c" }, "obj_lib",
                              { "HTTP_PARSER_STRICT=0" })
            if on["static"] then
                local arcmd = { "ar", "rcs", libdir .. "/libhttp_parser.a" }
                for _, o in ipairs(libObjs) do arcmd[#arcmd + 1] = o end
                ctx.exec(arcmd, { cwd = ctx.build_dir, log = ctx.log })
            end
            if on["shared"] then
                local so = libdir .. "/libhttp_parser.so.2.9.4"
                link(libObjs, so, { "-shared", "-Wl,-soname,libhttp_parser.so.2" })
                ctx.exec({ "ln", "-sf", "libhttp_parser.so.2.9.4",
                           libdir .. "/libhttp_parser.so.2" },
                         { cwd = ctx.build_dir, log = ctx.log })
                ctx.exec({ "ln", "-sf", "libhttp_parser.so.2.9.4",
                           libdir .. "/libhttp_parser.so" },
                         { cwd = ctx.build_dir, log = ctx.log })
            end
        end

        -- headers --------------------------------------------------------
        if on["headers"] then
            fs.mkdirs(incdir)
            copy(ctx, ctx.src .. "/http_parser.h", incdir .. "/http_parser.h")
        end

        -- tests: the REAL upstream test.c, compiled and executed ----------
        if on["tests"] then
            assert(libObjs, "gcpkg: httpparser: tests need the library objects")
            for _, mode in ipairs({ { "test_g", "1", "-O0", "-g" },
                                    { "test_fast", "0", "-O3" } }) do
                local name, strict = mode[1], mode[2]
                local flags = { mode[3] }
                if mode[4] then flags[#flags + 1] = mode[4] end
                local objs = compile({ ctx.src .. "/http_parser.c",
                                       ctx.src .. "/test.c" },
                                     "obj_" .. name,
                                     { "HTTP_PARSER_STRICT=" .. strict },
                                     flags)
                local exe = ctx.build_dir .. "/" .. name
                link(objs, exe, {})
                local out = ctx.build_dir .. "/" .. name .. ".out"
                ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local text = assert(fs.read(out),
                                    "gcpkg: httpparser: missing " .. name .. " output")
                assert(not text:find("FAIL", 1, true),
                       "gcpkg: httpparser: " .. name .. " reported a failure")
                assert(text:find("requests", 1, true) or text:find("Responses", 1, true)
                       or text:find("Message", 1, true),
                       "gcpkg: httpparser: " .. name .. " produced no test output")
            end
        end

        -- tools ----------------------------------------------------------
        if on["tools"] then
            assert(libObjs, "gcpkg: httpparser: tools need the library objects")
            fs.mkdirs(bindir)
            for _, tool in ipairs({ "url_parser", "parsertrace" }) do
                local objs = compile({ ctx.src .. "/contrib/" .. tool .. ".c" },
                                     "obj_" .. tool, { "HTTP_PARSER_STRICT=0" })
                local all = {}
                for _, o in ipairs(libObjs) do all[#all + 1] = o end
                for _, o in ipairs(objs) do all[#all + 1] = o end
                link(all, bindir .. "/httpparser-" .. tool, {})
            end
        end

        -- sources / docs / license --------------------------------------
        if on["sources"] then
            copy(ctx, ctx.src .. "/http_parser.c", srcdir .. "/http_parser.c")
            copy(ctx, ctx.src .. "/http_parser.h", srcdir .. "/http_parser.h")
        end
        if on["docs"] then
            for _, f in ipairs({ "README.md", "AUTHORS" }) do
                if fs.isfile(ctx.src .. "/" .. f) then
                    copy(ctx, ctx.src .. "/" .. f, docdir .. "/" .. f)
                end
            end
        end
        if on["license"] then
            copy(ctx, ctx.src .. "/LICENSE-MIT", docdir .. "/LICENSE-MIT")
        end

        -- pkgconfig -----------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include

Name: http_parser
Description: HTTP request/response parser in C
Version: 2.9.4
Libs: -L${libdir} -lhttp_parser
Cflags: -I${includedir}
]==]
            fs.write(pcdir .. "/http_parser.pc", (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package: find_package(httpparser CONFIG) ----------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(cmakedir .. "/httpparserConfig.cmake", [==[
get_filename_component(_HP_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET http_parser::http_parser)
  add_library(http_parser::http_parser SHARED IMPORTED)
  set_target_properties(http_parser::http_parser PROPERTIES
    IMPORTED_LOCATION "${_HP_PREFIX}/lib/libhttp_parser.so.2.9.4"
    IMPORTED_SONAME "libhttp_parser.so.2"
    INTERFACE_INCLUDE_DIRECTORIES "${_HP_PREFIX}/include")
endif()
if(NOT TARGET http_parser::http_parser_static)
  add_library(http_parser::http_parser_static STATIC IMPORTED)
  set_target_properties(http_parser::http_parser_static PROPERTIES
    IMPORTED_LOCATION "${_HP_PREFIX}/lib/libhttp_parser.a"
    INTERFACE_INCLUDE_DIRECTORIES "${_HP_PREFIX}/include")
endif()
set(httpparser_FOUND TRUE)
]==])
            fs.write(cmakedir .. "/httpparserConfigVersion.cmake", [==[
set(PACKAGE_VERSION "2.9.4")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- sanity: real consumer compiled against the INSTALLED tree ------
        if on["sanity"] then
            assert(on["headers"] and on["library"],
                   "gcpkg: httpparser: sanity needs library and headers")
            local csrc = ctx.build_dir .. "/httpparser_sanity.c"
            fs.write(csrc, [==[
#include <http_parser.h>
#include <stdio.h>
#include <string.h>

static int seen_url = 0, seen_header = 0;
static int on_url(http_parser *p, const char *at, size_t n) {
    (void)p; (void)at; seen_url += (int)n; return 0;
}
static int on_header_field(http_parser *p, const char *at, size_t n) {
    (void)p; (void)at; seen_header += (int)n; return 0;
}
int main(void) {
    http_parser parser;
    http_parser_settings st;
    http_parser_settings_init(&st);
    st.on_url = on_url;
    st.on_header_field = on_header_field;
    http_parser_init(&parser, HTTP_REQUEST);
    const char *req =
        "GET /gcpkg/httpparser?x=1 HTTP/1.1\r\n"
        "Host: example.invalid\r\n"
        "Connection: close\r\n\r\n";
    size_t n = http_parser_execute(&parser, &st, req, strlen(req));
    if (n != strlen(req)) { printf("parse error at %zu\n", n); return 2; }
    if (parser.method != HTTP_GET) return 3;
    if (seen_url <= 0) return 4;
    if (seen_header <= 0) return 5;
    printf("gcpkg httpparser ok url=%d header=%d v%u.%u\n",
           seen_url, seen_header, HTTP_PARSER_VERSION_MAJOR,
           HTTP_PARSER_VERSION_MINOR);
    return 0;
}
]==])
            local exe = ctx.build_dir .. "/httpparser_sanity"
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c11" },
                cwd = ctx.build_dir,
                outdir = ctx.build_dir .. "/obj_sanity",
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "httpparser", cxx = false,
                output = exe,
                libdirs = { libdir }, libs = { "http_parser" },
            }
            local out = ctx.build_dir .. "/sanity.out"
            local env = ctx.env or {}
            env.LD_LIBRARY_PATH = libdir ..
                (env.LD_LIBRARY_PATH and (":" .. env.LD_LIBRARY_PATH) or "")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = env })
            local text = assert(fs.read(out),
                                "gcpkg: httpparser: missing sanity output")
            assert(text:find("gcpkg httpparser ok", 1, true),
                   "gcpkg: httpparser: consumer did not run: " .. text)
        end

        return {
            includes = on["headers"] and { incdir } or {},
            libdirs = { libdir },
            libs = on["library"] and { "http_parser" } or {},
            binaries = on["tools"] and { bindir } or {},
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "http_parser" },
        binaries = { "@PREFIX@/bin" },
    },
}
