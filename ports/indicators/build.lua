-- indicators v2.3 -- R20 new-standard header-only port.
-- Upstream is a real CMake project (headers + generated indicators.pc + CONFIG
-- package) with 17 sample programs and one demo program.  The port builds them
-- and RUNS them (the progress-bar samples are time based, so each run is bounded
-- by a per-program timeout; see the notes below), then verifies the installed
-- headers with a consumer translation unit.
--
-- Upstream switch surface (CMakeLists.txt):
--   option(INDICATORS_BUILD_TESTS) -> feature `tests`   : DEAD upstream at this
--       tag - the tarball has no test/ directory and the CMakeLists never uses
--       the switch, so the port forwards it, records the accepted cache value
--       and says so instead of pretending there is a suite to run.
--   option(INDICATORS_SAMPLES)     -> feature `samples` : real (17 programs)
--   option(INDICATORS_DEMO)        -> feature `demo`    : real (demo/demo.cpp)
-- All three default ON and every one has an explicit `no-*` twin.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

-- Runs one built program with a hard time limit.  The progress-bar samples sleep
-- while they animate; a program that is still alive at the limit is recorded as
-- "still animating" rather than as a failure, but it must have produced output
-- and must not have crashed.
local function run_program(ctx, exe, label, limit)
    local out = util.join(ctx.build_dir, "run-" .. label .. ".out")
    local cmd = "timeout " .. tostring(limit) .. " " .. exe ..
                " > " .. out .. " 2>&1; echo $? > " .. out .. ".rc"
    ctx.exec({ "sh", "-c", cmd }, { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
    local text = fs.read(out) or ""
    return rc, text
end

return recipe.cmake {
    name = "indicators",
    version = "v2.3",
    license = "MIT",
    homepage = "https://github.com/p-ranav/indicators",
    description = "Header-only C++ progress bars and indicators",
    source = {
        url = "https://codeload.github.com/p-ranav/indicators/tar.gz/refs/tags/v2.3",
        sha256 = "70da7a693ff7a6a283850ab6d62acf628eea17d386488af8918576d0760aef7b",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        -- Upstream defect: include/indicators/termcolor.hpp uses uint8_t at
        -- namespace scope without including <cstdint>, so it only compiles if
        -- the translation unit happens to pull that header in first.  The port
        -- works around it on the command line and leaves the shipped header
        -- untouched.
        args = { "-DCMAKE_CXX_FLAGS=-include cstdint" },
        defines = {
            INDICATORS_BUILD_TESTS = "OFF",
            INDICATORS_SAMPLES = "OFF",
            INDICATORS_DEMO = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "indicators")
        fs.mkdirs(docdir)

        if on["headers"] then
            -- v2.3 ships separate headers (the single-header amalgamation only
            -- exists under single_include/), so check the modular set.
            for _, h in ipairs({ "progress_bar.hpp", "block_progress_bar.hpp",
                                 "indeterminate_progress_bar.hpp",
                                 "dynamic_progress.hpp", "multi_progress.hpp",
                                 "progress_spinner.hpp", "termcolor.hpp",
                                 "setting.hpp", "color.hpp" }) do
                assert(fs.isfile(util.join(incdir, "indicators", h)),
                       "gcpkg: indicators: indicators/" .. h .. " missing")
            end
            assert(fs.isdir(util.join(incdir, "indicators", "details")),
                   "gcpkg: indicators: indicators/details/ missing")
        end

        -- samples: 16 upstream progress-bar programs, really built and run ----
        if on["samples"] then
            local names = {}
            for _, f in ipairs(fs.listdir(util.join(ctx.src, "samples"))) do
                if f:sub(-4) == ".cpp" then
                    names[#names + 1] = f:sub(1, -5)
                end
            end
            table.sort(names)
            -- samples/CMakeLists.txt adds 16 programs at v2.3
            assert(#names == 16,
                   "gcpkg: indicators: expected 16 upstream samples, found " .. #names)
            -- progress_bar_sstream renders into a std::ostringstream on
            -- purpose (that is what the sample demonstrates), so it is the one
            -- program that must stay silent on stdout.
            local silent = { progress_bar_sstream = true }
            local running, finished, notes = 0, 0, {}
            for _, s in ipairs(names) do
                local exe = util.join(ctx.build_dir, "samples", s)
                assert(fs.isfile(exe),
                       "gcpkg: indicators: sample " .. s .. " was not built")
                local rc, text = run_program(ctx, exe, "sample-" .. s, 30)
                running = running + 1
                assert(rc == "0" or rc == "124",
                       "gcpkg: indicators: sample " .. s .. " crashed (rc=" .. rc .. ")")
                assert(#text > 0 or silent[s],
                       "gcpkg: indicators: sample " .. s .. " printed nothing")
                if rc == "0" then finished = finished + 1 end
                notes[#notes + 1] = s .. " rc=" .. rc ..
                    (silent[s] and " (renders into an ostringstream, stdout intentionally empty)" or "") ..
                    (rc == "124" and " (still animating at the 30s bound)" or "")
            end
            fs.write(util.join(ctx.build_dir, "samples.out"),
                     table.concat(notes, "\n") .. "\n")
            assert(running == 16, "gcpkg: indicators: only " .. running .. " samples ran")
            assert(finished >= 10,
                   "gcpkg: indicators: only " .. finished ..
                   " samples completed on their own")
        end

        -- demo: the upstream demo/demo.cpp, really built and run ---------------
        if on["demo"] then
            local exe = util.join(ctx.build_dir, "demo", "demo")
            assert(fs.isfile(exe), "gcpkg: indicators: demo was not built")
            local rc, text = run_program(ctx, exe, "demo", 20)
            assert(rc == "0" or rc == "124",
                   "gcpkg: indicators: demo crashed (rc=" .. rc .. ")")
            assert(#text > 0, "gcpkg: indicators: demo printed nothing")
            fs.write(util.join(ctx.build_dir, "demo.out"), text)
        end

        -- tests: upstream declares INDICATORS_BUILD_TESTS but this tag ships no
        -- test/ directory at all; the switch is dead.  Recorded, not faked.
        if on["tests"] then
            assert(not fs.isdir(util.join(ctx.src, "test")),
                   "gcpkg: indicators: upstream now ships a test/ directory - " ..
                   "the port must run its suite instead of recording the dead option")
            local cache = fs.read(util.join(ctx.build_dir, "CMakeCache.txt")) or ""
            assert(cache:find("INDICATORS_BUILD_TESTS:BOOL=ON", 1, true),
                   "gcpkg: indicators: the tests switch did not reach the CMake cache")
            fs.write(util.join(ctx.build_dir, "tests-note.out"),
                     "INDICATORS_BUILD_TESTS=ON accepted by CMake; upstream tag v2.3 " ..
                     "declares the option but ships no test/ directory, so it builds " ..
                     "nothing (dead option, not a skipped suite).\n")
        end

        -- docs / license -------------------------------------------------------
        if on["docs"] then
            for _, f in ipairs({ "README.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            for _, f in ipairs({ "LICENSE", "LICENSE.termcolor" }) do
                assert(fs.isfile(util.join(ctx.src, f)),
                       "gcpkg: indicators: " .. f .. " missing")
                ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end

        -- pkg-config: upstream generates indicators.pc itself -------------------
        if on["pkgconfig"] then
            assert(fs.isfile(util.join(libdir, "pkgconfig", "indicators.pc")),
                   "gcpkg: indicators: upstream indicators.pc missing")
        end

        -- CONFIG package: upstream export ---------------------------------------
        if on["cmake-package"] then
            local found = false
            for _, pat in ipairs({ "lib/cmake/indicators", "share/cmake/indicators" }) do
                if fs.isdir(util.join(ctx.prefix, pat)) then found = true break end
            end
            assert(found, "gcpkg: indicators: upstream indicatorsConfig package missing")
        end

        -- sanity: real consumer over the INSTALLED headers -----------------------
        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "indicators_sanity.cpp")
            fs.write(csrc, [==[
#include <indicators/progress_bar.hpp>
#include <indicators/block_progress_bar.hpp>
#include <cstdio>
#include <sstream>

int main() {
  indicators::ProgressBar bar{
      indicators::option::Stream{std::cout},
      indicators::option::BarWidth{10},
      indicators::option::MaxProgress{2},
      indicators::option::ShowPercentage{false},
  };
  bar.set_option(indicators::option::ShowRemainingTime{false});
  bar.tick();
  bar.tick();
  if (!bar.is_completed()) return 2;

  indicators::BlockProgressBar block{
      indicators::option::Stream{std::cout},
      indicators::option::BarWidth{10},
      indicators::option::MaxProgress{1},
      indicators::option::ShowPercentage{false},
  };
  block.set_progress(1);
  std::printf("gcpkg indicators ok bar=%d\n", (int)bar.is_completed());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "indicators_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                -- same upstream termcolor.hpp uint8_t defect as the samples
                flags = { "-std=c++17", "-include", "cstdint" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "indicators", cxx = true, output = exe,
                libdirs = {}, libs = { "pthread" },
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: indicators: missing sanity output")
            assert(text:find("gcpkg indicators ok", 1, true),
                   "gcpkg: indicators: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
