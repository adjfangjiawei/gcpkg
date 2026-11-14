-- csv2 0.2 -- R20 new-standard header-only port.
-- Upstream is a real CMake project installing include/csv2/*.hpp plus a CONFIG
-- package and a generated csv2.pc.  Its test/ directory builds a doctest suite
-- (doctest.hpp is vendored in-tree, so nothing is downloaded) that reads the
-- upstream CSV fixtures in test/inputs.  The port builds and RUNS that suite,
-- and verifies the installed tree with a consumer translation unit.
--
-- Upstream switch surface (CMakeLists.txt):
--   option(CSV2_BUILD_TESTS) -> feature `tests`   (real: 41 doctest cases)
--   option(CSV2_SAMPLES)     -> feature `samples` (DEAD upstream: no samples/
--                               directory and no add_subdirectory(samples) in
--                               this tag; the port still forwards the switch and
--                               records that it is dead instead of pretending it
--                               builds something)
--   option(CSV2_DEMO)        -> feature `demo`    (DEAD upstream, same reason)
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

return recipe.cmake {
    name = "csv2",
    version = "0.2",
    license = "MIT",
    homepage = "https://github.com/p-ranav/csv2",
    description = "Fast CSV parser and writer for modern C++",
    source = {
        url = "https://codeload.github.com/p-ranav/csv2/tar.gz/refs/tags/v0.2",
        sha256 = "30e9ac5e83520475a274ec04494ad24d602a15bb75839610b51432e50a98048d",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            CSV2_BUILD_TESTS = "OFF",
            CSV2_SAMPLES = "OFF",
            CSV2_DEMO = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "csv2")
        fs.mkdirs(docdir)

        if on["headers"] then
            for _, h in ipairs({ "mio.hpp", "parameters.hpp", "reader.hpp",
                                 "writer.hpp" }) do
                assert(fs.isfile(util.join(incdir, "csv2", h)),
                       "gcpkg: csv2: csv2/" .. h .. " missing")
            end
        end

        -- tests: the upstream doctest suite, really executed ----------------
        if on["tests"] then
            local bdir = util.join(ctx.build_dir, "test")
            local exe = util.join(bdir, "csv2_test")
            assert(fs.isfile(exe),
                   "gcpkg: csv2: the upstream test binary was not built")
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1; echo $? > " ..
                       out .. ".rc" },
                     { cwd = bdir, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out), "gcpkg: csv2: missing test output")
            assert(not text:find("ERROR", 1, true),
                   "gcpkg: csv2: upstream suite reported an error: " .. text)
            assert(text:find("Status: SUCCESS", 1, true),
                   "gcpkg: csv2: upstream suite did not succeed: " .. text)
            assert(rc == "0", "gcpkg: csv2: test binary exited with " .. rc)
            local cases = tonumber(text:match("test cases:%s+(%d+)") or "0") or 0
            assert(cases >= 30,
                   "gcpkg: csv2: only " .. cases ..
                   " test cases ran, expected the full upstream suite")
            -- the fixtures must really have been read off disk
            local inputs = util.join(bdir, "inputs")
            assert(fs.isdir(inputs),
                   "gcpkg: csv2: the upstream CSV fixtures were not staged")
        end

        -- samples / demo: upstream declares the switches but this tag ships no
        -- samples/ or demo/ directory and the CMakeLists never uses them.
        -- Recorded rather than faked.
        if on["samples"] or on["demo"] then
            local cache = fs.read(util.join(ctx.build_dir, "CMakeCache.txt")) or ""
            local notes = {}
            for _, flag in ipairs({ "CSV2_SAMPLES", "CSV2_DEMO" }) do
                local key = flag .. ":BOOL=ON"
                if cache:find(key, 1, true) then
                    notes[#notes + 1] = flag .. " accepted by CMake (dead option: " ..
                        "this tag ships no samples/ or demo/ target)"
                end
            end
            fs.write(util.join(ctx.build_dir, "samples.out"),
                     table.concat(notes, "\n") .. "\n")
            assert(#notes > 0,
                   "gcpkg: csv2: the samples/demo switches did not reach the CMake cache")
        end

        -- docs / license -----------------------------------------------------
        if on["docs"] then
            for _, f in ipairs({ "README.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            for _, f in ipairs({ "LICENSE", "LICENSE.mio" }) do
                assert(fs.isfile(util.join(ctx.src, f)),
                       "gcpkg: csv2: " .. f .. " missing")
                ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end

        -- pkg-config: upstream generates csv2.pc itself ----------------------
        if on["pkgconfig"] then
            assert(fs.isfile(util.join(libdir, "pkgconfig", "csv2.pc")),
                   "gcpkg: csv2: upstream csv2.pc missing")
        end

        -- CONFIG package: upstream export -------------------------------------
        if on["cmake-package"] then
            local found = false
            for _, pat in ipairs({ "lib/cmake/csv2", "share/cmake/csv2" }) do
                if fs.isdir(util.join(ctx.prefix, pat)) then found = true break end
            end
            assert(found, "gcpkg: csv2: upstream csv2Config package missing")
        end

        -- sanity: real consumer over the INSTALLED headers ---------------------
        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "csv2_sanity.cpp")
            fs.write(csrc, [==[
#include <csv2/reader.hpp>
#include <csv2/writer.hpp>
#include <cstdio>
#include <sstream>
#include <string>
#include <vector>

// csv2's Writer closes its stream in the destructor, so give it a stream that
// tolerates close() like the upstream tests do.
struct BufferStream : std::ostringstream {
  void close() {}
};

int main() {
  std::string data = "a,b,c\n1,2,3\n";
  csv2::Reader<csv2::delimiter<','>, csv2::quote_character<'"'>,
               csv2::first_row_is_header<true>> reader;
  if (!reader.parse(data)) return 2;
  size_t rows = 0;
  std::string last;
  for (const auto row : reader) {
    ++rows;
    for (const auto cell : row) {
      std::string v;
      cell.read_value(v);
      last = v;
    }
  }
  // first_row_is_header<true> hides the header row, so iteration yields the
  // single data row of the sample document.
  if (rows != 1) return 3;
  if (last != "3") return 4;

  BufferStream os;
  csv2::Writer<csv2::delimiter<','>, BufferStream> writer(os);
  writer.write_row(std::vector<std::string>{"gcpkg", "ok"});
  if (os.str().find("gcpkg,ok") == std::string::npos) return 5;
  std::printf("gcpkg csv2 ok rows=%zu last=%s\n", rows, last.c_str());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "csv2_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "csv2", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: csv2: missing sanity output")
            assert(text:find("gcpkg csv2 ok", 1, true),
                   "gcpkg: csv2: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
