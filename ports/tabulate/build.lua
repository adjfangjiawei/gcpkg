-- tabulate v2.2 -- R20 new-standard header-only port.
-- Upstream is a real CMake project: 16 test programs (each compiled twice, once
-- against the modular headers and once against the generated single_include
-- header, 32 CTest entries) plus 29 sample programs.  The port builds and RUNS
-- that suite instead of compiling a synthetic probe, then verifies the installed
-- tree with a consumer translation unit.
--
-- Upstream switch surface (CMakeLists.txt):
--   tabulate_BUILD_TESTS  -> feature `tests`
--   SAMPLES               -> feature `samples`
--   USE_CPP17 (cache var) -> feature `cpp17` (changes the exported INTERFACE
--                            compile feature of tabulate::tabulate, which the
--                            port asserts on the installed export file)
-- Everything is ON by default; every feature has its explicit `no-*` twin.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

return recipe.cmake {
    name = "tabulate",
    version = "v2.2",
    license = "MIT",
    homepage = "https://github.com/p-ranav/tabulate",
    description = "Header-only C++ table formatting library",
    source = {
        url = "https://codeload.github.com/p-ranav/tabulate/tar.gz/refs/tags/v2.2",
        sha256 = "3c12853cbf103adf659c4821351a302351d139513f1c43528095da41e8a37044",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        -- Declared OFF here so the feature flags (appended last) really drive
        -- the build instead of being decoration.
        defines = {
            tabulate_BUILD_TESTS = "OFF",
            SAMPLES = "OFF",
            USE_CPP17 = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "tabulate")
        fs.mkdirs(docdir)

        if on["headers"] then
            assert(fs.isfile(util.join(incdir, "tabulate/tabulate.hpp")),
                   "gcpkg: tabulate: tabulate/tabulate.hpp missing")
            -- the modular headers are what the library is made of: all of them
            -- must be there, not just the umbrella header.
            local count = 0
            for _, f in ipairs(fs.listdir(util.join(incdir, "tabulate"))) do
                if f:sub(-4) == ".hpp" then count = count + 1 end
            end
            assert(count >= 20,
                   "gcpkg: tabulate: only " .. count .. " headers installed")
        end

        -- tests: the upstream CTest suite (32 entries), really executed ------
        if on["tests"] then
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "ctest --output-on-failure > " .. out .. " 2>&1; echo $? > " ..
                       out .. ".rc" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out),
                                "gcpkg: tabulate: missing ctest output")
            assert(not text:find("No tests were found", 1, true),
                   "gcpkg: tabulate: ctest found no registered tests")
            assert(text:find("100% tests passed", 1, true),
                   "gcpkg: tabulate: upstream test suite did not pass: " .. text)
            assert(rc == "0", "gcpkg: tabulate: ctest exited with " .. rc)
            local registered = tonumber(text:match("out of (%d+)") or "0") or 0
            assert(registered == 32,
                   "gcpkg: tabulate: expected 32 CTest entries (16 tests x modular + " ..
                   "single-header), ctest ran " .. registered)
            -- both build flavours must appear in the run log
            assert(text:find("_single_header", 1, true),
                   "gcpkg: tabulate: the single_include test flavour did not run")
        end

        -- samples: upstream builds 29 demo programs; the port RUNS the ones
        -- whose output is deterministic and non-interactive.  The animated /
        -- full-screen samples (mario, shape, refresh_table, pagination,
        -- streaming_rows, benchmark, ansi_escape_width) are compiled but not
        -- executed: they clear the screen and sleep in a loop.  Same for
        -- locale_preserved, which requires a specific locale setup.
        if on["samples"] then
            local samples = {
                "employees", "colors", "class_diagram", "font_styles",
                "iterators", "latex_export", "markdown_export",
                "asciidoc_export", "border_styles", "black_color",
                "nested_table_hidden_border", "remove_column",
            }
            local ran, notes = 0, {}
            for _, s in ipairs(samples) do
                local exe = util.join(ctx.build_dir, "samples", s)
                assert(fs.isfile(exe),
                       "gcpkg: tabulate: sample program " .. s .. " was not built")
                local out = util.join(ctx.build_dir, "sample-" .. s .. ".out")
                ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1; echo $? > " ..
                           out .. ".rc" },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
                local text = fs.read(out) or ""
                assert(rc == "0",
                       "gcpkg: tabulate: sample " .. s .. " exited with " .. rc)
                assert(#text > 0,
                       "gcpkg: tabulate: sample " .. s .. " printed nothing")
                ran = ran + 1
                notes[#notes + 1] = s .. " rc=0 bytes=" .. #text
            end
            fs.write(util.join(ctx.build_dir, "samples.out"),
                     table.concat(notes, "\n") .. "\n")
            assert(ran == #samples, "gcpkg: tabulate: only " .. ran .. " samples ran")
        end

        -- cpp17: USE_CPP17 changes the INTERFACE compile feature that upstream
        -- exports, so check the installed export file rather than the cache.
        local exportFile = util.join(libdir, "cmake/tabulate/tabulateTargets.cmake")
        if on["cmake-package"] then
            assert(fs.isfile(exportFile),
                   "gcpkg: tabulate: upstream export file missing")
            local targets = fs.read(exportFile) or ""
            if on["cpp17"] then
                assert(targets:find("cxx_std_17", 1, true),
                       "gcpkg: tabulate: cpp17 feature is on but the exported target " ..
                       "does not require cxx_std_17")
            else
                assert(targets:find("cxx_std_11", 1, true),
                       "gcpkg: tabulate: cpp11 feature is on but the exported target " ..
                       "does not require cxx_std_11")
            end
        end

        -- docs / license: real upstream files ------------------------------
        if on["docs"] then
            for _, f in ipairs({ "README.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            for _, f in ipairs({ "LICENSE", "LICENSE.optional-lite",
                                 "LICENSE.termcolor", "LICENSE.variant-lite" }) do
                assert(fs.isfile(util.join(ctx.src, f)),
                       "gcpkg: tabulate: " .. f .. " missing")
                ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end

        -- pkg-config -------------------------------------------------------
        if on["pkgconfig"] then
            local pcdir = util.join(libdir, "pkgconfig")
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: tabulate
Description: Header-only C++ table formatting library
Version: 2.2
Cflags: -I${includedir}
]==]
            fs.write(util.join(pcdir, "tabulate.pc"), (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- sanity: real consumer over the INSTALLED headers ------------------
        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "tabulate_sanity.cpp")
            fs.write(csrc, [==[
#include <tabulate/table.hpp>
#include <cstdio>

int main() {
  tabulate::Table t;
  t.add_row({"gcpkg", "ok"});
  t.add_row({"rows", "2"});
  t[0][0].format().font_style({tabulate::FontStyle::bold});
  auto text = t.str();
  if (text.find("gcpkg") == std::string::npos) return 2;
  if (t.size() != 2) return 3;
  std::printf("gcpkg tabulate ok rows=%zu\n", t.size());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "tabulate_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "tabulate", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: tabulate: missing sanity output")
            assert(text:find("gcpkg tabulate ok", 1, true),
                   "gcpkg: tabulate: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
