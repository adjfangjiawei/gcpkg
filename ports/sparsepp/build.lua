-- sparsepp v0.95 -- R20 new-standard header-only port.
--
-- A fast sparse hash map (a fork of Google sparsehash).  Upstream ships no
-- build system for the library itself: `sparsepp/` is a header tree and the
-- only build description is tests/makefile, i.e.
--
--     CXXFLAGS = -O2 -std=c++11 -I..
--     spp_test        (= `make test`, prints PASS; all work happens in static
--                      constructors, so "if they don't die, the tests passed")
--     spp_alloc_test  (spp_allocator stress test, reports memory usage)
--     spp_bitset_test (longest_zero_sequence/count_trailing_zeroes, reports
--                      num_errors per run)
--     perftest1       (a benchmark, not a test: built by `make all`, not run)
--
-- So the port stays a header recipe and reproduces `make test` plus the two
-- sibling test programs itself, with the same flags, and registers those runs
-- with CTest.  perftest1 is deliberately not run.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local VERSION = "v0.95"

-- One entry per upstream test program that `make all` builds and that is a
-- test rather than a benchmark.
local TEST_PROGRAMS = {
    { name = "spp_test", defines = {} },
    { name = "spp_alloc_test", defines = { "NDEBUG" } },
    { name = "spp_bitset_test", defines = { "NDEBUG" } },
}

return recipe.header {
    name = "sparsepp",
    version = VERSION,
    license = "BSD-3-Clause",
    homepage = "https://github.com/greg7mdp/sparsepp",
    description = "Fast header-only sparse hash map derived from Google sparsehash",
    source = {
        url = "https://codeload.github.com/greg7mdp/sparsepp/tar.gz/refs/tags/v0.95",
        sha256 = "cde419e440ec6aecc2fe2c4612d702ce243de16c3c616485d2f719e96315150d",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "sparsepp", dst = "sparsepp" },
        },
        include = "sparsepp/spp.h",
        flags = { "-std=c++17" },
        license_files = { "LICENSE" },
    },
    -- recipe.header's own builder does not run post_install, and this port needs
    -- both: copy the header tree (upstream has no build system at all) and then
    -- run the tests/consumer checks.  So the builder is written out here.
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir_probe = util.join(ctx.prefix, "include")
        local libdir_probe = util.join(ctx.prefix, "lib")
        fs.mkdirs(incdir_probe)
        fs.mkdirs(libdir_probe)
        ctx.exec({ "cp", "-a", util.join(ctx.src, "sparsepp"), incdir_probe },
                 { cwd = ctx.src, log = ctx.log })
        for _, lf in ipairs({ "LICENSE" }) do
            local doc = util.join(ctx.prefix, "share", "doc", "sparsepp")
            fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, lf), doc },
                     { cwd = ctx.src, log = ctx.log })
        end
        -- the same single-TU include probe recipe.header would do
        local probe = util.join(ctx.build_dir, "gcpkg_header_probe.cpp")
        fs.write(probe, "#include <sparsepp/spp.h>\nint main() { return 0; }\n")
        cc.compile {
            sources = { probe }, includes = { incdir_probe },
            flags = { "-std=c++17" },
            cwd = ctx.build_dir, outdir = util.join(ctx.build_dir, "obj_probe"),
            compiler = ctx.compiler.wrapper_cxx,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "sparsepp",
        }
        local incdir = util.join(ctx.prefix, "include")
        local docdir = util.join(ctx.prefix, "share", "doc", "sparsepp")
        fs.mkdirs(docdir)

        for _, h in ipairs({ "sparsepp/spp.h", "sparsepp/spp_utils.h",
                             "sparsepp/spp_alloc.h", "sparsepp/spp_bitset.h",
                             "sparsepp/spp_btree.h", "sparsepp/spp_config.h" }) do
            assert(fs.isfile(util.join(incdir, h)),
                   "gcpkg: sparsepp: " .. h .. " missing from the install tree")
        end

        if on["pkgconfig"] then
            local pcdir = util.join(ctx.prefix, "lib", "pkgconfig")
            fs.mkdirs(pcdir)
            fs.write(util.join(pcdir, "sparsepp.pc"), table.concat({
                "prefix=" .. tostring(ctx.prefix),
                "includedir=" .. tostring(ctx.include_dir or util.join(ctx.prefix, "include")),
                "",
                "Name: sparsepp",
                "Description: Fast header-only sparse hash map",
                "Version: 0.95",
                "Cflags: -I${includedir}",
                "",
            }, "\n"))
        end

        -- tests: the three test programs from upstream's tests/makefile ------
        if on["tests"] then
            local testsdir = util.join(ctx.src, "tests")
            local exes = {}
            for _, t in ipairs(TEST_PROGRAMS) do
                local exe = util.join(ctx.build_dir, t.name)
                cc.executable {
                    sources = { util.join(testsdir, t.name .. ".cc") },
                    includes = { ctx.src },
                    defines = t.defines,
                    -- upstream: -O2 -std=c++11 -I.. -Wall -pedantic -Wextra
                    --           -D_XOPEN_SOURCE=700 (plus -DNDEBUG per target)
                    flags = { "-O2", "-std=c++11", "-Wall", "-pedantic",
                              "-Wextra", "-D_XOPEN_SOURCE=700",
                              "-D_CRT_SECURE_NO_WARNINGS" },
                    cwd = ctx.build_dir,
                    outdir = util.join(ctx.build_dir, "obj_" .. t.name),
                    compiler = ctx.compiler.wrapper_cxx,
                    exec = ctx.exec, record = ctx.record, log = ctx.log,
                    tag = "sparsepp", cxx = true, output = exe,
                    libdirs = {}, libs = {},
                }
                exes[#exes + 1] = { name = t.name, exe = exe }
            end

            for _, e in ipairs(exes) do
                local out = util.join(ctx.build_dir, e.name .. ".out")
                ctx.exec({ "sh", "-c",
                           "cd " .. testsdir .. " && " .. e.exe .. " > " .. out ..
                           " 2>&1; echo $? >> " .. out },
                         { cwd = testsdir, log = ctx.log, env = ctx.env })
                local text = assert(fs.read(out),
                                    "gcpkg: sparsepp: missing " .. e.name .. " output")
                assert(text:find("0%s*$") ~= nil,
                       "gcpkg: sparsepp: " .. e.name .. " exited non-zero: " .. text)
            end

            -- program-specific verdicts, using what each one prints
            local main_out = assert(fs.read(util.join(ctx.build_dir, "spp_test.out")))
            assert(main_out:find("PASS", 1, true),
                   "gcpkg: sparsepp: spp_test did not print PASS: " .. main_out)
            local bitset_out = assert(fs.read(util.join(ctx.build_dir, "spp_bitset_test.out")))
            local runs = select(2, bitset_out:gsub("num_errors = %d+", ""))
            assert(runs >= 6,
                   "gcpkg: sparsepp: spp_bitset_test ran only " .. runs ..
                   " measurement loops")
            local bad = select(2, bitset_out:gsub("num_errors = [1-9]", ""))
            assert(bad == 0,
                   "gcpkg: sparsepp: spp_bitset_test reported " .. bad ..
                   " loop(s) with errors: " .. bitset_out)
            local alloc_out = assert(fs.read(util.join(ctx.build_dir, "spp_alloc_test.out")))
            assert(alloc_out:find("mem usage after the alloc test", 1, true),
                   "gcpkg: sparsepp: spp_alloc_test did not finish: " .. alloc_out)

            -- register the same runs with CTest
            local driver = util.join(ctx.build_dir, "upstream-tests")
            fs.mkdirs(driver)
            local lines = {
                "# Generated by the gcpkg sparsepp port: upstream's tests/makefile",
                "# test programs, registered with CTest.",
                "cmake_minimum_required(VERSION 3.16)",
                "project(sparsepp-upstream-tests LANGUAGES NONE)",
                "enable_testing()",
            }
            for _, e in ipairs(exes) do
                lines[#lines + 1] = 'add_test(NAME ' .. e.name .. ' COMMAND "' ..
                                    e.exe .. '")'
                lines[#lines + 1] = "set_tests_properties(" .. e.name ..
                                    ' PROPERTIES WORKING_DIRECTORY "' ..
                                    tostring(testsdir) .. '")'
            end
            fs.write(util.join(driver, "CMakeLists.txt"),
                     table.concat(lines, "\n") .. "\n")
            local dbuild = util.join(driver, "build")
            ctx.exec({ "cmake", "-S", driver, "-B", dbuild },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local ctest_out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "cd " .. dbuild .. " && ctest --output-on-failure > " ..
                       ctest_out .. " 2>&1; echo $? > " .. ctest_out .. ".rc" },
                     { cwd = dbuild, log = ctx.log, env = ctx.env })
            local rc = (fs.read(ctest_out .. ".rc") or "?"):gsub("%s", "")
            local ctext = assert(fs.read(ctest_out),
                                "gcpkg: sparsepp: missing ctest output")
            assert(ctext:find("100% tests passed", 1, true),
                   "gcpkg: sparsepp: ctest did not pass: " .. ctext)
            assert(rc == "0", "gcpkg: sparsepp: ctest exited with " .. rc)
            ctx.exec({ "sh", "-c", "cat >> " .. ctest_out .. " <<'NOTE'\n" ..
                       "not run: perftest1 (tests/makefile builds it under\n" ..
                       "  `make all`, but it is a benchmark, not a test).\n" ..
                       "NOTE" }, { cwd = ctx.build_dir, log = ctx.log })
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "CHANGELOG.md", "bench.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
            if fs.isdir(util.join(ctx.src, "docs")) then
                ctx.exec({ "cp", "-a", util.join(ctx.src, "docs"), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: sparsepp: LICENSE missing")
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end

        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "sparsepp_sanity.cpp")
            fs.write(csrc, [==[
#include <sparsepp/spp.h>
#include <cstdio>
#include <string>

int main() {
  spp::sparse_hash_map<std::string, int> m;
  m["one"] = 1;
  m["two"] = 2;
  if (m.size() != 2) return 2;
  if (m["two"] != 2) return 3;
  spp::sparse_hash_set<int> s;
  s.insert(7);
  if (!s.count(7)) return 4;
  std::printf("gcpkg sparsepp ok size=%zu\n", m.size());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "sparsepp_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "sparsepp", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: sparsepp: missing sanity output")
            assert(text:find("gcpkg sparsepp ok", 1, true),
                   "gcpkg: sparsepp: consumer did not run: " .. text)
        end

        -- A custom build() must return the export table explicitly.
        return {
            includes = { incdir_probe },
            libdirs = { libdir_probe },
            libs = {},
            binaries = {},
            compdb_files = {},
        }
    end,
}
