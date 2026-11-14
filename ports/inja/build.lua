-- inja 3.5.0 -- R20 new-standard header-only port.
-- inja is a header-only template engine.  Upstream is a real CMake project with
-- a full option() surface and a real CTest suite (inja_test renders the upstream
-- jinja test-suite expectations, plus single_inja_test which builds the same
-- tests against the amalgamated single_include header, and a benchmark target).
-- doctest and nlohmann/json are vendored in third_party/, so nothing is
-- downloaded at build time.
--
-- Upstream switch surface -> feature mapping (see features.yaml too):
--   BUILD_TESTING / INJA_BUILD_TESTS   -> tests
--   INJA_USE_EMBEDDED_JSON             -> use-embedded-json  (either/or with
--                                         use-external-json, which pulls the
--                                         source-built nlohmann-json port)
--   INJA_INSTALL                       -> install
--   INJA_INSTALL_SINGLE_HEADER         -> install-single-header / install-modular
--   INJA_EXPORT                        -> export-package
--   INJA_ENABLE_CLANG_TIDY             -> static-analysis (opt-in alternative of
--                                         plain-build)
--   COVERALLS                          -> coverage (opt-in alternative)
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

return recipe.cmake {
    name = "inja",
    version = "3.5.0",
    license = "MIT",
    homepage = "https://github.com/pantor/inja",
    description = "Header-only C++ template engine (Jinja2-like)",
    source = {
        url = "https://codeload.github.com/pantor/inja/tar.gz/refs/tags/v3.5.0",
        sha256 = "a5f0266673c59028eab6ceeddd8b862c70abfeb32fb7a5387c16bf46f3269ab2",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            INJA_BUILD_TESTS = "OFF",
            COVERALLS = "OFF",
            INJA_ENABLE_CLANG_TIDY = "OFF",
            INJA_EXPORT = "OFF",
            INJA_INSTALL = "OFF",
            INJA_INSTALL_SINGLE_HEADER = "OFF",
            INJA_USE_EMBEDDED_JSON = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "inja")
        local pcdir = util.join(libdir, "pkgconfig")
        fs.mkdirs(docdir)

        if on["install"] then
            if on["install-single-header"] then
                assert(fs.isfile(util.join(incdir, "inja/inja.hpp")),
                       "gcpkg: inja: single-header install tree incomplete")
                -- the amalgamated header must be the amalgamation, not the
                -- modular header: it is one big file.
                local size = #(fs.read(util.join(incdir, "inja/inja.hpp")) or "")
                assert(size > 100000,
                       "gcpkg: inja: installed inja.hpp is only " .. size ..
                       " bytes, expected the amalgamated single header")
            else
                assert(fs.isfile(util.join(incdir, "inja/inja.hpp")),
                       "gcpkg: inja: modular install tree incomplete")
                assert(fs.isfile(util.join(incdir, "inja/renderer.hpp")),
                       "gcpkg: inja: modular headers missing (only the " ..
                       "amalgamated header was installed)")
            end
            if on["use-embedded-json"] then
                assert(fs.isfile(util.join(incdir, "nlohmann/json.hpp")),
                       "gcpkg: inja: the vendored nlohmann/json header was not installed")
            end
        end

        -- tests: the upstream CTest suite, really executed -------------------
        if on["tests"] then
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "ctest --output-on-failure > " .. out .. " 2>&1; echo $? > " ..
                       out .. ".rc" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out), "gcpkg: inja: missing ctest output")
            assert(not text:find("No tests were found", 1, true),
                   "gcpkg: inja: ctest found no registered tests")
            assert(text:find("100% tests passed", 1, true),
                   "gcpkg: inja: upstream test suite did not pass: " .. text)
            assert(rc == "0", "gcpkg: inja: ctest exited with " .. rc)
            local registered = tonumber(text:match("out of (%d+)") or "0") or 0
            assert(registered >= 2,
                   "gcpkg: inja: expected inja_test and single_inja_test, ctest ran " ..
                   registered)
            assert(text:find("single_inja_test", 1, true),
                   "gcpkg: inja: the single-header test flavour did not run")
            -- the benchmark target is built but not registered with CTest
            assert(fs.isfile(util.join(ctx.build_dir, "inja_benchmark")),
                   "gcpkg: inja: the upstream benchmark target was not built")
        end

        -- docs / license ------------------------------------------------------
        if on["docs"] then
            for _, f in ipairs({ "README.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
            if fs.isdir(util.join(ctx.src, "doc")) then
                ctx.exec({ "cp", "-a", util.join(ctx.src, "doc"), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: inja: LICENSE missing")
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end

        -- pkg-config -----------------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: inja
Description: Header-only C++ template engine (Jinja2-like)
Version: 3.5.0
Cflags: -I${includedir}
]==]
            fs.write(util.join(pcdir, "inja.pc"), (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package: upstream exports pantor::inja -------------------------
        if on["cmake-package"] then
            local found = false
            for _, pat in ipairs({ "lib/cmake/inja/injaConfig.cmake",
                                   "share/cmake/inja/injaConfig.cmake" }) do
                if fs.isfile(util.join(ctx.prefix, pat)) then found = true break end
            end
            assert(found, "gcpkg: inja: upstream injaConfig.cmake missing")
        end

        -- sanity: real consumer over the INSTALLED headers -----------------------
        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "inja_sanity.cpp")
            fs.write(csrc, [==[
#include <inja/inja.hpp>
#include <cstdio>
#include <string>

int main() {
  inja::Environment env;
  nlohmann::json data;
  data["name"] = "gcpkg";

  std::string out = env.render("hello {{ name }}", data);
  if (out != "hello gcpkg") return 2;

  // parse once, render twice (the cached-template path)
  auto t = env.parse("{{ upper(name) }}");
  if (env.render(t, data) != "GCPKG") return 3;
  data["name"] = "inja";
  if (env.render(t, data) != "INJA") return 4;

  std::printf("gcpkg inja ok out=%s\n", out.c_str());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "inja_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "inja", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: inja: missing sanity output")
            assert(text:find("gcpkg inja ok", 1, true),
                   "gcpkg: inja: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
