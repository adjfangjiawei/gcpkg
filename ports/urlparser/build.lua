-- urlparser 69c09ed -- R20 new-standard port (netmindms/urlparser).
-- No build system upstream: one header, one implementation TU, one example.
-- Everything is compiled by gcpkg's compiler wrapper (no probes, no
-- downloads, no system headers), and every default-on feature is verified
-- afterwards: the upstream example is executed, a real C++ consumer is
-- compiled, linked against the installed tree and run.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local function copy(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
end

return recipe.define {
    name = "urlparser",
    version = "69c09ed",
    license = "MIT",
    homepage = "https://github.com/netmindms/urlparser",
    description = "Small C++ URL parser used as an ada benchmark competitor",
    source = {
        url = "https://codeload.github.com/netmindms/urlparser/tar.gz/69c09ed6ab022223e749f54e9158f0eedfcc8d28",
        sha256 = "1d2735a9247730429be5e84dff6453987f6da9a84b98436e0cd3560c6780fbe5",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local libdir = ctx.prefix .. "/lib"
        local bindir = ctx.prefix .. "/bin"
        local srcdir = ctx.prefix .. "/share/urlparser/src"
        local docdir = ctx.prefix .. "/share/doc/urlparser"
        local pcdir = libdir .. "/pkgconfig"
        local cmakedir = libdir .. "/cmake/urlparser"
        fs.mkdirs(ctx.build_dir)
        local cxx = ctx.compiler.wrapper_cxx

        local objs = nil
        if on["library"] then
            assert(on["static"] or on["shared"],
                   "gcpkg: urlparser: library needs static and/or shared")
            fs.mkdirs(libdir)
            objs = cc.compile {
                sources = { ctx.src .. "/src/EdUrlParser.cpp" },
                includes = { ctx.src .. "/src" },
                flags = { "-std=c++17", "-O3", "-fPIC" },
                cwd = ctx.src, outdir = ctx.build_dir .. "/obj_lib",
                compiler = cxx, exec = ctx.exec, record = ctx.record,
                log = ctx.log, tag = "urlparser",
            }
            if on["static"] then
                local arcmd = { "ar", "rcs", libdir .. "/liburlparser.a" }
                for _, o in ipairs(objs) do arcmd[#arcmd + 1] = o end
                ctx.exec(arcmd, { cwd = ctx.build_dir, log = ctx.log })
            end
            if on["shared"] then
                cc.link { objects = objs, output = libdir .. "/liburlparser.so",
                          compiler = cxx,
                          flags = { "-shared", "-Wl,-soname,liburlparser.so" },
                          cwd = ctx.build_dir, exec = ctx.exec, log = ctx.log }
            end
        end

        if on["headers"] then
            fs.mkdirs(incdir)
            copy(ctx, ctx.src .. "/src/EdUrlParser.h", incdir .. "/EdUrlParser.h")
        end

        -- example / tests: upstream's own program, built and EXECUTED ------
        -- Upstream ships no unit-test suite, so running its real program and
        -- asserting every parsed URL part IS the upstream test.
        if on["example"] or on["tests"] then
            assert(objs, "gcpkg: urlparser: example/tests need the library objects")
            fs.mkdirs(bindir)
            local exobjs = cc.compile {
                sources = { ctx.src .. "/src/exam.cpp" },
                includes = { ctx.src .. "/src" },
                flags = { "-std=c++17", "-O2" },
                cwd = ctx.src, outdir = ctx.build_dir .. "/obj_exam",
                compiler = cxx, exec = ctx.exec, record = ctx.record,
                log = ctx.log, tag = "urlparser",
            }
            local all = {}
            for _, o in ipairs(objs) do all[#all + 1] = o end
            for _, o in ipairs(exobjs) do all[#all + 1] = o end
            local exe = bindir .. "/urlparser-example"
            cc.link { objects = all, output = exe, compiler = cxx,
                      flags = {}, cwd = ctx.build_dir, exec = ctx.exec,
                      log = ctx.log }
            if on["tests"] then
                local out = ctx.build_dir .. "/example.out"
                ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local text = assert(fs.read(out),
                                    "gcpkg: urlparser: missing example output")
                assert(text:find("scheme: http", 1, true),
                       "gcpkg: urlparser: example did not parse the scheme")
                assert(text:find("host name: www.google.co.kr", 1, true),
                       "gcpkg: urlparser: example did not parse the host")
                assert(text:find("key name vale", 1, true),
                       "gcpkg: urlparser: example did not parse the query map")
            end
            if not on["example"] then
                -- tests-only run: the program is a test artifact, not an
                -- installed tool
                ctx.exec({ "rm", "-f", exe }, { cwd = ctx.build_dir, log = ctx.log })
            end
        end

        if on["sources"] then
            for _, f in ipairs({ "EdUrlParser.cpp", "EdUrlParser.h", "exam.cpp" }) do
                copy(ctx, ctx.src .. "/src/" .. f, srcdir .. "/" .. f)
            end
        end
        if on["docs"] then
            copy(ctx, ctx.src .. "/README.md", docdir .. "/README.md")
        end
        if on["license"] then
            copy(ctx, ctx.src .. "/LICENSE.md", docdir .. "/LICENSE.md")
        end

        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include

Name: urlparser
Description: Small C++ URL parser
Version: 69c09ed
Libs: -L${libdir} -lurlparser
Cflags: -I${includedir} -std=c++17
]==]
            fs.write(pcdir .. "/urlparser.pc", (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(cmakedir .. "/urlparserConfig.cmake", [==[
get_filename_component(_UP_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET urlparser::urlparser)
  add_library(urlparser::urlparser SHARED IMPORTED)
  set_target_properties(urlparser::urlparser PROPERTIES
    IMPORTED_LOCATION "${_UP_PREFIX}/lib/liburlparser.so"
    INTERFACE_INCLUDE_DIRECTORIES "${_UP_PREFIX}/include"
    INTERFACE_COMPILE_FEATURES cxx_std_17)
endif()
if(NOT TARGET urlparser::urlparser_static)
  add_library(urlparser::urlparser_static STATIC IMPORTED)
  set_target_properties(urlparser::urlparser_static PROPERTIES
    IMPORTED_LOCATION "${_UP_PREFIX}/lib/liburlparser.a"
    INTERFACE_INCLUDE_DIRECTORIES "${_UP_PREFIX}/include"
    INTERFACE_COMPILE_FEATURES cxx_std_17)
endif()
set(urlparser_FOUND TRUE)
]==])
            fs.write(cmakedir .. "/urlparserConfigVersion.cmake", [==[
set(PACKAGE_VERSION "69c09ed")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- sanity: real consumer against the INSTALLED tree -----------------
        if on["sanity"] then
            assert(on["headers"] and on["library"],
                   "gcpkg: urlparser: sanity needs library and headers")
            local csrc = ctx.build_dir .. "/urlparser_sanity.cpp"
            fs.write(csrc, [==[
#include <EdUrlParser.h>
#include <cstdio>
#include <string>
#include <unordered_map>
#include <vector>

static int failures = 0;
static void check(bool ok, const char *what) {
    if (!ok) { std::printf("FAILED: %s\n", what); ++failures; }
}

int main() {
    EdUrlParser *u = EdUrlParser::parseUrl(
        "https://example.invalid:8443/a/b/c?x=1&y=two#frag");
    check(u != nullptr, "parseUrl returned null");
    if (!u) return 2;
    check(u->scheme == "https", "scheme");
    check(u->hostName == "example.invalid", "host");
    check(u->port == "8443", "port");
    check(u->path == "/a/b/c", "path");
    check(u->query == "x=1&y=two", "query");
    check(u->fragment == "frag", "fragment");

    std::vector<std::string> dirs;
    check(EdUrlParser::parsePath(&dirs, u->path) == 3, "parsePath count");
    check(dirs.size() == 3 && dirs[1] == "b", "parsePath content");

    std::unordered_map<std::string, std::string> kv;
    check(EdUrlParser::parseKeyValueMap(&kv, u->query) == 2, "parseKeyValueMap count");
    check(kv["y"] == "two", "parseKeyValueMap value");

    std::string enc = EdUrlParser::urlEncode("left| |right & ");
    check(EdUrlParser::urlDecode(enc) == "left| |right & ", "urlEncode/urlDecode roundtrip");
    delete u;

    if (failures) return 3;
    std::printf("gcpkg urlparser ok enc=%s\n", enc.c_str());
    return 0;
}
]==])
            local exe = ctx.build_dir .. "/urlparser_sanity"
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = ctx.build_dir .. "/obj_sanity",
                compiler = cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "urlparser", cxx = true,
                output = exe,
                libdirs = { libdir }, libs = { "urlparser" },
            }
            local out = ctx.build_dir .. "/sanity.out"
            local env = ctx.env or {}
            env.LD_LIBRARY_PATH = libdir ..
                (env.LD_LIBRARY_PATH and (":" .. env.LD_LIBRARY_PATH) or "")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = env })
            local text = assert(fs.read(out),
                                "gcpkg: urlparser: missing sanity output")
            assert(text:find("gcpkg urlparser ok", 1, true),
                   "gcpkg: urlparser: consumer did not run: " .. text)
        end

        return {
            includes = on["headers"] and { incdir } or {},
            libdirs = { libdir },
            libs = on["library"] and { "urlparser" } or {},
            binaries = on["example"] and { bindir } or {},
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "urlparser" },
        binaries = { "@PREFIX@/bin" },
    },
}
