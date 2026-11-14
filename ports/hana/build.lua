-- hana 1.7.0 -- R20 new-standard header-only port.
--
-- Boost.Hana: heterogeneous metaprogramming / containers, C++14, 450 headers.
--
-- This one is genuinely CMake-driven: the top-level CMakeLists.txt builds the
-- INTERFACE target `hana`, installs the headers, generates `hana.pc` from
-- cmake/hana.pc.in and exports HanaConfig.cmake, and `add_subdirectory(test)`
-- registers one CTest program per test/*.cpp plus a header-inclusion test that
-- compiles every public header on its own.  Nothing is downloaded at configure
-- time.  So the install is upstream's own, and the suite is upstream's own.
--
-- The suite is two EXCLUDE_FROM_ALL target trees that upstream wires into
-- `hana_check`: `tests` (746 CTest programs plus a header-inclusion program
-- covering all 450 public headers) and `examples` (one program per
-- example/*.cpp, also registered with CTest).  Both are built and then CTest is
-- run.  Upstream's third dependency of hana_check, `test.deploy`, is an
-- ExternalProject that re-configures and re-builds the project into a fake
-- prefix; it is deliberately not used (gcpkg already proves the install tree
-- with its own consumer TU).
--
-- One upstream bug blocks the suite, patched here in the source tree (the
-- installed headers carry the fix, so it has to happen before install):
--
--   include/boost/hana/experimental/type_name.hpp hardcodes
--      sizeof("boost::hana::experimental::detail::cstring boost::hana::"
--             "experimental::detail::type_name_impl2() [T = ")
--      as the prefix length of __PRETTY_FUNCTION__.  Modern Clang prints the
--      *declared* return type ("auto ...") instead of the deduced one, so that
--      constant is longer than the whole pretty function and the header stops
--      compiling ("cannot refer to element 101 of array of 72 elements").
--   Modern Clang prints the *declared* return type ("auto ...") instead of the
--   deduced one, so that constant is longer than the whole pretty function and
--   the header stops compiling ("cannot refer to element 101 of array of 72
--   elements").  The patch replaces the hardcoded length with a constexpr
--   search for the "T = " marker, so the feature is repaired rather than
--   dropped from the suite.
--
-- -Werror: boost_hana_set_test_properties() adds -Werror -Wall -Wextra
-- -pedantic -Wwrite-strings to every test when the compiler supports them.
-- clang-23 emits new warnings inside hana's own headers, so -Werror is filtered
-- out by a compiler launcher (same technique as glm/hopscotch-map): the
-- diagnostics stay, only "and therefore fail" goes away.
--
-- Boost: some tests (test/ext/boost/**, test/experimental/printable/**) need
-- the rest of Boost; upstream guards them with find_package(Boost 1.64).  This
-- host has a system Boost in /usr/include, so Boost_DIR is pinned to the
-- gcpkg `boost` port explicitly and the tests use 1.81.0 from the store.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "1.7.0"
local CACHE_NAME = "hana-1.7.0-v1.7.0"
local SOURCE_SHA = "f228013dc32acf69e30c2200964c96b119a6e779817b24457c76096bb57e1280"

local TYPE_NAME_NEEDLE = [[            constexpr std::size_t prefix_size = sizeof("boost::hana::experimental::detail::cstring boost::hana::experimental::detail::type_name_impl2() [T = ") - 1;]]

local TYPE_NAME_PATCH = [[            // gcpkg: newer Clang prints the declared return type instead of the
            // deduced one in __PRETTY_FUNCTION__, so a hardcoded prefix length is
            // wrong.  Locate the "T = " marker instead.
            constexpr std::size_t prefix_size =
                detail::marker_end(pretty_function, total_size, "T = ", 4);]]

local MARKER_HELPER_NEEDLE = [[        struct cstring {
            char const* ptr;
            std::size_t length;
        };
]]

local MARKER_HELPER_PATCH = [[        struct cstring {
            char const* ptr;
            std::size_t length;
        };

        // gcpkg: returns the offset just past `needle` in the first `n` bytes of
        // `s`, or `n` when it is absent (empty type name rather than UB).
        constexpr std::size_t marker_end(char const* s, std::size_t n,
                                         char const* needle, std::size_t m) {
            for (std::size_t i = 0; i + m <= n; ++i) {
                std::size_t j = 0;
                while (j < m && s[i + j] == needle[j]) ++j;
                if (j == m) return i + m;
            }
            return n;
        }
]]

local PROBE = [==[
#include <boost/hana.hpp>
#include <boost/hana/experimental/type_name.hpp>

#include <iostream>
#include <string>

namespace hana = boost::hana;

int main()
{
    // runtime: heterogeneous sequence, transform and fold
    auto xs = hana::make_tuple( 1, 2, 3 );
    auto doubled = hana::transform( xs, [](auto x) { return x + x; } );

    int sum = hana::fold_left( hana::make_range( hana::int_c< 0 >, hana::int_c< 10 > ),
                               0, [](int a, int b) { return a + b; } );

    // compile-time: type-level computation really happens at compile time
    static_assert( hana::size( xs ) == hana::size_c< 3 >, "size" );
    static_assert( hana::size( doubled ) == hana::size_c< 3 >, "transform keeps size" );
    static_assert( hana::length( hana::make_tuple() ) == hana::size_c< 0 >, "length" );

    // a map keyed by compile-time integers
    auto m = hana::make_map( hana::make_pair( hana::int_c< 0 >, std::string{ "zero" } ),
                             hana::make_pair( hana::int_c< 1 >, std::string{ "one" } ) );
    bool in_map = hana::contains( m, hana::int_c< 1 > );

    // string and the patched experimental::type_name
    auto greeting = hana::to< char const * >( BOOST_HANA_STRING( "hi" ) );
    auto int_name = hana::to< char const * >( hana::experimental::type_name< int >() );

    bool ok = hana::at_c< 0 >( doubled ) == 2 && hana::at_c< 2 >( doubled ) == 6 &&
              sum == 45 && in_map &&
              std::string( greeting ) == "hi" && std::string( int_name ) == "int";

    std::cout << "gcpkg hana ok=" << ( ok ? 1 : 0 )
              << " size=" << hana::value( hana::size( xs ) )
              << " sum=" << sum
              << " type_name=\"" << int_name << "\"\n";
    return ok ? 0 : 1;
}
]==]

-- -Werror comes from upstream's boost_hana_set_test_properties(); it is the only
-- flag that turns diagnostics into failures, so it is the only one dropped.
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

local function escape_pattern(s)
    return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function escape_replacement(s)
    return (s:gsub("%%", "%%%%"))
end

local function replace_once(text, needle, repl, what)
    assert(text:find(needle, 1, true), "gcpkg: hana: " .. what .. " (anchor missing)")
    local out, n = text:gsub(escape_pattern(needle), escape_replacement(repl))
    assert(n == 1, "gcpkg: hana: " .. what .. " (matched " .. tostring(n) .. " times)")
    return out
end

-- The installed headers carry the type_name fix, so it is applied to the source
-- before configure/install.
local function patch_source(ctx)
    local tn = util.join(ctx.src, "include", "boost", "hana", "experimental",
                         "type_name.hpp")
    local tn_text = assert(fs.read(tn),
                           "gcpkg: hana: experimental/type_name.hpp missing")
    if tn_text:find("detail::marker_end", 1, true) then
        -- gcpkg does not re-extract an existing source tree, so a previous run
        -- may already have applied this patch.
        return
    end
    local patched = replace_once(tn_text, TYPE_NAME_NEEDLE, TYPE_NAME_PATCH,
                                 "type_name.hpp: replace the hardcoded prefix length")
    patched = replace_once(patched, MARKER_HELPER_NEEDLE, MARKER_HELPER_PATCH,
                           "type_name.hpp: add the constexpr marker search")
    fs.write(tn, patched)
end

local function run_upstream_tests(ctx)
    local jobs = tostring(ctx.jobs or 4)
    -- Everything CTest knows about is EXCLUDE_FROM_ALL upstream; `hana_check`
    -- builds exactly these two trees before running ctest.
    ctx.exec({ "cmake", "--build", ctx.build_dir,
               "--target", "tests", "examples", "--parallel", jobs },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

    local out = util.join(ctx.build_dir, "ctest.out")
    ctx.exec({ "sh", "-c",
               "cd " .. tostring(ctx.build_dir) .. " && ctest --output-on-failure " ..
               "--timeout 300 -j " .. jobs .. " > " .. out ..
               " 2>&1 < /dev/null; echo $? > " .. out .. ".rc" },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    local text = assert(fs.read(out), "gcpkg: hana: missing ctest output")
    local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
    assert(not text:find("No tests were found", 1, true),
           "gcpkg: hana: ctest found no registered tests")
    assert(text:find("100% tests passed", 1, true),
           "gcpkg: hana: upstream test suite did not pass:\n" .. text)
    assert(rc == "0", "gcpkg: hana: ctest exited with " .. rc)
    local registered = tonumber(text:match("out of (%d+)") or "0") or 0
    assert(registered >= 900,
           "gcpkg: hana: expected the whole upstream suite, ctest ran " ..
           registered)
    return registered
end

return recipe.cmake {
    name = "hana",
    version = VERSION,
    license = "BSL-1.0",
    homepage = "https://boostorg.github.io/hana/",
    description = "Your standard library for metaprogramming (Boost.Hana)",
    source = {
        url = "https://github.com/boostorg/hana/archive/refs/tags/v1.7.0.tar.gz",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        warning_filter(ctx)
        patch_source(ctx)
    end,
    cmake = {
        defines = function(ctx)
            local on = ctx.features.enabled
            local boost_args = {}
            if on["tests"] then
                local boost = assert(r20.dep_prefix(ctx, "boost"),
                                     "gcpkg: hana: missing boost dependency")
                -- upstream does find_package(Boost 1.64); this host has a system
                -- Boost in /usr/include, so pin the config package to the store.
                boost_args = { Boost_DIR = util.join(boost, "lib", "cmake",
                                                     "Boost-1.81.0") }
            end
            local d = {
                CMAKE_CXX_COMPILER_LAUNCHER = warning_filter(ctx),
                BOOST_HANA_ENABLE_CONCEPT_CHECKS = on["concept-checks"] and "ON" or "OFF",
                BOOST_HANA_ENABLE_DEBUG_MODE = on["debug-mode"] and "ON" or "OFF",
                BOOST_HANA_ENABLE_STRING_UDL = on["string-udl"] and "ON" or "OFF",
                BOOST_HANA_ENABLE_EXCEPTIONS = on["exceptions"] and "ON" or "OFF",
            }
            for k, v in pairs(boost_args) do d[k] = v end
            return d
        end,
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local docdir = util.join(ctx.prefix, "share", "doc", "hana")
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(docdir)
        fs.mkdirs(vdir)

        assert(on["debug-mode"] ~= on["release-mode"],
               "gcpkg: hana: exactly one of debug-mode / release-mode must be on")

        -- the header tree: 450 headers, notably the umbrella and a few corners
        local headers = 0
        do
            local function walk(dir)
                for _, f in ipairs(fs.listdir(dir) or {}) do
                    local p = util.join(dir, f)
                    if fs.isdir(p) then
                        walk(p)
                    elseif f:match("%.hpp$") then
                        headers = headers + 1
                    end
                end
            end
            walk(util.join(incdir, "boost", "hana"))
        end
        assert(headers >= 449,
               "gcpkg: hana: expected ~450 headers, found " .. headers)
        for _, h in ipairs({ "hana.hpp", "hana/core.hpp", "hana/string.hpp",
                             "hana/map.hpp", "hana/transform.hpp",
                             "hana/experimental/type_name.hpp" }) do
            assert(fs.isfile(util.join(incdir, "boost", h)),
                   "gcpkg: hana: boost/" .. h .. " missing from the install tree")
        end

        if on["cmake-package"] then
            assert(fs.isfile(util.join(ctx.prefix, "lib", "cmake", "hana",
                                       "HanaConfig.cmake")),
                   "gcpkg: hana: lib/cmake/hana/HanaConfig.cmake missing")
        end

        if on["pkgconfig"] then
            assert(fs.isfile(util.join(ctx.prefix, "lib", "pkgconfig", "hana.pc")),
                   "gcpkg: hana: hana.pc missing (upstream configures it from " ..
                   "cmake/hana.pc.in)")
        end

        if on["license"] then
            local lic = util.join(ctx.src, "LICENSE.md")
            assert(fs.isfile(lic), "gcpkg: hana: LICENSE.md missing")
            ctx.exec({ "cp", "-a", lic, util.join(docdir, "LICENSE.md") },
                     { log = ctx.log })
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "RELEASE_NOTES.md" }) do
                local p = util.join(ctx.src, f)
                if fs.isfile(p) then
                    ctx.exec({ "cp", "-a", p, docdir .. "/" }, { log = ctx.log })
                end
            end
            assert(fs.isfile(util.join(docdir, "README.md")),
                   "gcpkg: hana: README.md not installed")
        end

        local facts = {
            "policy=upstream_cmake_install_and_upstream_ctest_suite",
            "version=" .. VERSION,
            "source_cache=" .. CACHE_NAME,
            "source_sha=" .. SOURCE_SHA,
            "source_patch=YES (1 upstream bug: experimental/type_name.hpp hardcodes the __PRETTY_FUNCTION__ prefix length)",
            "patch_1=experimental/type_name.hpp: constexpr search for the \"T = \" marker instead of a hardcoded prefix length",
            "network_at_build=NO",
            "host_boost=NO (Boost_DIR pinned to the gcpkg boost port)",
            "headers=" .. tostring(headers),
            "warnings=-Werror from upstream's boost_hana_set_test_properties() filtered by a compiler launcher",
        }

        if on["tests"] then
            local registered = run_upstream_tests(ctx)
            facts[#facts + 1] = "tests_registered=" .. tostring(registered)
            facts[#facts + 1] =
                "tests_scope=test/*.cpp one program each + header-inclusion test " ..
                "for all " .. tostring(headers) .. " public headers + " ..
                "issues/github_75 (2 TU ODR check) + example/*.cpp one program each"
            facts[#facts + 1] =
                "tests_not_used=upstream's test.deploy hook, which is an " ..
                "external-project re-configure/re-build into a fake prefix"
        else
            facts[#facts + 1] = "tests_run=0 (feature tests OFF)"
        end

        if on["sanity"] then
            local probe = util.join(vdir, "hana_probe.cpp")
            fs.write(probe, PROBE)
            local bin = cc.executable {
                sources = { probe },
                includes = { incdir },
                flags = { "-std=c++14" },
                cwd = vdir, outdir = util.join(vdir, "obj"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "hana", cxx = true,
                output = util.join(vdir, "hana_probe"),
            }
            local out, rc = ctx.capture({ bin }, { cwd = vdir, env = ctx.env })
            fs.write(util.join(vdir, "hana-probe.out"), tostring(out))
            assert(rc == 0, "gcpkg: hana: consumer TU failed:\n" .. tostring(out))
            assert(out:find("gcpkg hana ok=1", 1, true),
                   "gcpkg: hana: consumer output mismatch:\n" .. tostring(out))
            facts[#facts + 1] = "consumer_rc=" .. tostring(rc)
            facts[#facts + 1] =
                "sanity_checks=make_tuple/transform/fold_left/make_range/make_map/" ..
                "contains/to<char const*>/experimental::type_name"
        end

        facts[#facts + 1] = ""
        fs.write(util.join(vdir, "hana-facts.txt"), table.concat(facts, "\n"))
    end,
}
