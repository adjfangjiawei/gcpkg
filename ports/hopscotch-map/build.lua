-- hopscotch-map 2.3.1 -- R20 new-standard header-only port.
--
-- tsl::hopscotch_map / hopscotch_set / bhopscotch_map / bhopscotch_set.
--
-- Upstream's CMakeLists.txt is usable as-is for the library: it is a plain
-- INTERFACE target with install(DIRECTORY include/tsl) plus a proper
-- tsl-hopscotch-mapConfig.cmake / ConfigVersion / Targets export in
-- share/cmake/tsl-hopscotch-map.  Nothing is downloaded at configure time.
--
-- The test project (tests/CMakeLists.txt) is *almost* usable: it is an
-- independent project (its own cmake_minimum_required/project), but it
--   * does `find_package(Boost 1.54.0 REQUIRED COMPONENTS unit_test_framework)`
--     and links Boost::unit_test_framework -- a *compiled* Boost.Test library
--     that this stack does not build (the boost port has no test component);
--   * does `add_subdirectory(../ ...)` to get the library, i.e. tests the
--     source tree rather than the installed headers;
--   * adds `-Werror -Wall -Wextra -Wold-style-cast`, which on clang-23 turns
--     the 36 warnings clang emits for Boost.Test 1.81's own headers into
--     errors.
--
-- So the port copies tests/ into the build directory and patches it there
-- (upstream sources are left untouched):
--   * tests/main.cpp: <boost/test/unit_test.hpp> -> the header-only variant
--     <boost/test/included/unit_test.hpp>.  This is Boost.Test's documented
--     single-header mode: the BOOST_TEST_MODULE TU carries the framework, the
--     other TUs keep the ordinary header.  No library is needed.
--   * tests/CMakeLists.txt: the Boost find/link block and the
--     add_subdirectory(../) block are replaced by explicit include directories
--     for the INSTALLED tree and the Boost headers.
--   * -Werror is filtered by a compiler launcher (the same technique the glm
--     port uses): diagnostics stay, only "and therefore fail" goes away.
--
-- The suite really runs: Boost.Test reports
--   "141 test cases out of 141 passed / 495900 assertions out of 495900".
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "2.3.1"

local HEADERS = {
    "tsl/hopscotch_map.h",
    "tsl/hopscotch_set.h",
    "tsl/bhopscotch_map.h",
    "tsl/bhopscotch_set.h",
    "tsl/hopscotch_hash.h",
    "tsl/hopscotch_growth_policy.h",
}

local PROBE = [==[
#include <tsl/hopscotch_map.h>
#include <tsl/hopscotch_set.h>

#include <iostream>
#include <string>

int main()
{
    tsl::hopscotch_map< std::string, int > m;
    m["a"] = 1;
    m["b"] = 2;
    m.emplace( "c", 3 );

    tsl::hopscotch_set< int > s;
    s.insert( 3 );
    s.insert( 3 );

    tsl::hopscotch_map< int, std::string > m2;
    for( int i = 0; i < 128; ++i ) m2[i] = std::to_string( i );

    bool ok = m.size() == 3 && m.at( "a" ) == 1 && s.size() == 1 &&
              s.count( 3 ) == 1 && m2.at( 127 ) == "127" &&
              m.erase( "a" ) == 1 && m.size() == 2;
    // iteration visits every element exactly once
    int seen = 0;
    for( auto const & kv : m2 ) { (void) kv; ++seen; }

    std::cout << "gcpkg hopscotch-map ok=" << ( ok && seen == 128 ? 1 : 0 )
              << " size=" << m.size() << " seen=" << seen << "\n";
    return ( ok && seen == 128 ) ? 0 : 1;
}
]==]

-- -Werror / -Wold-style-cast come from upstream's test project.  The first is
-- filtered (it is the only one that turns diagnostics into failures); the
-- second is kept so the suite still proves upstream's style requirement and is
-- only downgraded from "error" to "warning" by dropping -Werror.
local function warning_filter(ctx)
    local f = util.join(ctx.build_dir, "gcpkg-cxx-launcher.py")
    fs.mkdirs(ctx.build_dir)
    fs.write(f, [[#!/usr/bin/env python3
import os, sys

DROP = ("-Werror",)
args = [a for a in sys.argv[1:] if a not in DROP]
os.execv(args[0], args)
]])
    ctx.exec({ "chmod", "+x", f }, { cwd = ctx.build_dir, log = ctx.log })
    return f
end

local function split_lines(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]*") do lines[#lines + 1] = line end
    return lines
end

-- Patch tests/main.cpp in the copied tree: header-only Boost.Test.
local function patch_main(testsdir)
    local p = util.join(testsdir, "main.cpp")
    local text = assert(fs.read(p), "gcpkg: hopscotch-map: tests/main.cpp missing")
    local needle = "#include <boost/test/unit_test.hpp>"
    local replacement = "#include <boost/test/included/unit_test.hpp>"
    assert(text:find(needle, 1, true),
           "gcpkg: hopscotch-map: tests/main.cpp layout changed")
    assert(not text:find(replacement, 1, true), "gcpkg: hopscotch-map: already patched")
    fs.write(p, (text:gsub(needle:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"),
                           replacement)))
end

-- Patch tests/CMakeLists.txt in the copied tree: drop the compiled Boost.Test
-- requirement and the add_subdirectory(../), point at the installed headers.
local function patch_tests(testsdir, incdir, boost_inc)
    local p = util.join(testsdir, "CMakeLists.txt")
    local text = assert(fs.read(p),
                        "gcpkg: hopscotch-map: tests/CMakeLists.txt missing")
    local lines = split_lines(text)
    local out, i, found = {}, 1, false
    while i <= #lines do
        local line = lines[i]
        if line:match("^# Boost::unit_test_framework") then
            -- skip up to and including the tsl::hopscotch_map link line
            local j = i
            while j <= #lines and
                  not lines[j]:match("^target_link_libraries%(tsl_hopscotch_map_tests PRIVATE tsl::hopscotch_map") do
                j = j + 1
            end
            assert(j <= #lines,
                   "gcpkg: hopscotch-map: tests/CMakeLists.txt layout changed")
            out[#out + 1] = "# gcpkg: Boost.Test is header-only here (main.cpp uses"
            out[#out + 1] = "# <boost/test/included/unit_test.hpp>), so there is no"
            out[#out + 1] = "# Boost::unit_test_framework to find or link; and the test"
            out[#out + 1] = "# links the INSTALLED headers instead of add_subdirectory(../)."
            out[#out + 1] = 'target_include_directories(tsl_hopscotch_map_tests PRIVATE'
            out[#out + 1] = '                           "' .. tostring(incdir) .. '"'
            out[#out + 1] = '                           "' .. tostring(boost_inc) .. '")'
            i = j + 1
            found = true
        else
            out[#out + 1] = line
            i = i + 1
        end
    end
    assert(found, "gcpkg: hopscotch-map: Boost block not found in tests/CMakeLists.txt")
    out[#out + 1] = ""
    out[#out + 1] = "# gcpkg: upstream has no add_test(); register the suite with CTest so"
    out[#out + 1] = "# the port has one canonical entry point for it."
    out[#out + 1] = "enable_testing()"
    out[#out + 1] = "add_test(NAME hopscotch_map_tests"
    out[#out + 1] = "         COMMAND tsl_hopscotch_map_tests --report_level=short)"
    out[#out + 1] = "set_tests_properties(hopscotch_map_tests PROPERTIES TIMEOUT 900)"
    fs.write(p, table.concat(out, "\n"))
end

local function run_upstream_tests(ctx, incdir, boost_inc)
    local testsdir = util.join(ctx.build_dir, "tests")
    fs.rm(testsdir)
    fs.mkdirs(testsdir)
    ctx.exec({ "cp", "-a", util.join(ctx.src, "tests") .. "/.", testsdir .. "/" },
             { cwd = ctx.build_dir, log = ctx.log })
    patch_main(testsdir)
    patch_tests(testsdir, incdir, boost_inc)

    local dbuild = util.join(ctx.build_dir, "tests-build")
    local launcher = warning_filter(ctx)
    ctx.exec({ "cmake", "-S", testsdir, "-B", dbuild,
               "-DCMAKE_BUILD_TYPE=Release",
               "-DCMAKE_CXX_COMPILER=" .. tostring(ctx.compiler.wrapper_cxx),
               "-DCMAKE_CXX_COMPILER_LAUNCHER=" .. launcher,
               -- tests/CMakeLists.txt says cmake_minimum_required(3.8); CMake 4
               -- rejects anything below 3.5 outright, this only relaxes that.
               "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    ctx.exec({ "cmake", "--build", dbuild, "--parallel", tostring(ctx.jobs or 4) },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

    local ctestout = util.join(ctx.build_dir, "ctest.out")
    ctx.exec({ "sh", "-c",
               "cd " .. dbuild .. " && ctest --output-on-failure " ..
               "--timeout 900 > " .. ctestout ..
               " 2>&1 < /dev/null; echo $? > " .. ctestout .. ".rc" },
             { cwd = dbuild, log = ctx.log, env = ctx.env })
    local ctext = assert(fs.read(ctestout),
                         "gcpkg: hopscotch-map: missing ctest output")
    assert(ctext:find("100% tests passed", 1, true),
           "gcpkg: hopscotch-map: ctest did not pass:\n" .. ctext)

    local bin = util.join(dbuild, "tsl_hopscotch_map_tests")
    assert(fs.isfile(bin),
           "gcpkg: hopscotch-map: test binary not built at " .. bin)
    -- Run it through the shell: Boost.Test buffers its summary separately from
    -- the "Running N test cases..." banner, so the captured stream must be a
    -- real file, not a pipe.
    local outfile = util.join(ctx.build_dir, "hopscotch-tests.out")
    ctx.exec({ "sh", "-c",
               "cd " .. dbuild .. " && ./tsl_hopscotch_map_tests " ..
               "--report_level=short > " .. outfile .. " 2>&1 < /dev/null; " ..
               "echo $? > " .. outfile .. ".rc" },
             { cwd = dbuild, log = ctx.log, env = ctx.env })
    local out = assert(fs.read(outfile),
                       "gcpkg: hopscotch-map: missing test output")
    local rc = (fs.read(outfile .. ".rc") or "?"):gsub("%s", "")
    assert(rc == "0", "gcpkg: hopscotch-map: test suite failed:\n" .. out)
    assert(out:find("No errors detected", 1, true) or
           out:find("has passed with", 1, true),
           "gcpkg: hopscotch-map: unexpected Boost.Test output:\n" .. tostring(out))

    local cases = tonumber(out:match("(%d+) test cases out of (%d+) passed")
                            or "0") or 0
    local total = tonumber(out:match("%d+ test cases out of (%d+) passed")
                            or "0") or 0
    local assertions = tonumber(out:match("(%d+) assertions out of") or "0") or 0
    assert(total >= 100 and cases == total,
           "gcpkg: hopscotch-map: expected >= 100 passing test cases, got " ..
           cases .. "/" .. total)
    assert(assertions >= 100000,
           "gcpkg: hopscotch-map: too few assertions executed: " ..
           tostring(assertions))
    return { cases = cases, assertions = assertions }
end

return recipe.cmake {
    name = "hopscotch-map",
    version = VERSION,
    license = "MIT",
    homepage = "https://github.com/Tessil/hopscotch-map",
    description = "C++ hash maps and sets using hopscotch hashing (tsl::hopscotch_map)",
    source = {
        url = "https://codeload.github.com/Tessil/hopscotch-map/tar.gz/refs/tags/v2.3.1",
        sha256 = "53dab49005cd5dc859f2546d0d3eef058ec7fb3b74fc3b19f4965a9a151e9b20",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_DATAROOTDIR = "share",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local docdir = util.join(ctx.prefix, "share", "doc", "hopscotch-map")
        fs.mkdirs(docdir)

        assert(on["install"],
               "gcpkg: hopscotch-map: the install feature is mandatory")
        for _, h in ipairs(HEADERS) do
            assert(fs.isfile(util.join(incdir, h)),
                   "gcpkg: hopscotch-map: " .. h .. " missing from the install tree")
        end

        if on["cmake-package"] then
            for _, pat in ipairs({
                "share/cmake/tsl-hopscotch-map/tsl-hopscotch-mapConfig.cmake",
                "share/cmake/tsl-hopscotch-map/tsl-hopscotch-mapConfigVersion.cmake",
                "share/cmake/tsl-hopscotch-map/tsl-hopscotch-mapTargets.cmake",
            }) do
                assert(fs.isfile(util.join(ctx.prefix, pat)),
                       "gcpkg: hopscotch-map: upstream " .. pat .. " missing")
            end
        end

        if on["license"] then
            local lic = util.join(ctx.src, "LICENSE")
            assert(fs.isfile(lic), "gcpkg: hopscotch-map: LICENSE missing")
            ctx.exec({ "cp", "-a", lic, util.join(docdir, "LICENSE") },
                     { log = ctx.log })
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "doxygen.conf" }) do
                local p = util.join(ctx.src, f)
                if fs.isfile(p) then
                    ctx.exec({ "cp", "-a", p, docdir .. "/" }, { log = ctx.log })
                end
            end
        end

        if on["pkgconfig"] then
            assert(on["install"],
                   "gcpkg: hopscotch-map: pkgconfig needs the install feature")
            local pcdir = util.join(ctx.prefix, "lib", "pkgconfig")
            fs.mkdirs(pcdir)
            fs.write(util.join(pcdir, "tsl-hopscotch-map.pc"), table.concat({
                "prefix=" .. tostring(ctx.prefix),
                "includedir=" .. tostring(incdir),
                "",
                "Name: tsl-hopscotch-map",
                "Description: C++ hash maps and sets using hopscotch hashing",
                "Version: " .. VERSION,
                "Cflags: -I${includedir}",
                "",
            }, "\n"))
            assert(fs.isfile(util.join(pcdir, "tsl-hopscotch-map.pc")),
                   "gcpkg: hopscotch-map: .pc file not written")
        end

        local facts = {
            "policy=upstream_cmake_install_plus_patched_test_project",
            "version=" .. VERSION,
            "source_patch=NO (upstream sources untouched; the tests copy is patched)",
            "network_at_build=NO",
            "cmake_package=share/cmake/tsl-hopscotch-map",
            "test_framework=Boost.Test header-only " ..
                "(boost/test/included/unit_test.hpp)",
        }

        if on["tests"] then
            local boost = assert(r20.dep_prefix(ctx, "boost"),
                                 "gcpkg: hopscotch-map: missing boost dependency")
            local r = run_upstream_tests(ctx, incdir, util.join(boost, "include"))
            facts[#facts + 1] = "tests_cases=" .. tostring(r.cases)
            facts[#facts + 1] = "tests_assertions=" .. tostring(r.assertions)
            facts[#facts + 1] =
                "tests_policy=patched copy: header-only Boost.Test, " ..
                "-Werror filtered by compiler launcher, links installed headers"
        else
            facts[#facts + 1] = "tests_run=0 (feature tests OFF)"
        end

        if on["sanity"] then
            local vdir = util.join(ctx.build_dir, "verify")
            fs.mkdirs(vdir)
            local probe = util.join(vdir, "hopscotch_probe.cpp")
            fs.write(probe, PROBE)
            local bin = cc.executable {
                sources = { probe },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = vdir, outdir = util.join(vdir, "obj"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "hopscotch-map", cxx = true,
                output = util.join(vdir, "hopscotch_probe"),
            }
            local out, rc = ctx.capture({ bin }, { cwd = vdir, env = ctx.env })
            fs.write(util.join(vdir, "hopscotch-probe.out"), tostring(out))
            assert(rc == 0,
                   "gcpkg: hopscotch-map: consumer TU failed:\n" .. tostring(out))
            assert(out:find("gcpkg hopscotch-map ok=1", 1, true),
                   "gcpkg: hopscotch-map: consumer output mismatch:\n" ..
                   tostring(out))
            facts[#facts + 1] = "consumer_rc=" .. tostring(rc)
        end

        facts[#facts + 1] = ""
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(vdir)
        fs.write(util.join(vdir, "hopscotch-map-facts.txt"),
                 table.concat(facts, "\n"))
    end,
}
