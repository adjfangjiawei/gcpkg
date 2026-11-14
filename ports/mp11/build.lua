-- mp11 1.92.0 -- R20 new-standard header-only port.
--
-- Boost.Mp11 is a C++11 metaprogramming library: a pure header tree under
-- boost/mp11/ plus the boost/mp11.hpp umbrella, with no compiled artefacts and
-- no configure step of any kind.
--
-- Upstream's CMakeLists.txt cannot be used as a build system here.  Built as a
-- top-level project it does
--     file(DOWNLOAD https://raw.githubusercontent.com/boostorg/cmake/develop/
--                   include/BoostFetch.cmake ...)
--     boost_fetch(boostorg/cmake TAG develop NO_ADD_SUBDIR)
-- and, with BUILD_TESTING=ON, fetches boostorg/{assert,config,core,
-- throw_exception} at TAG develop as well.  That is a network download at
-- build time plus an unpinned `develop` snapshot: neither is acceptable, and
-- neither is needed, because the library itself is only headers and the
-- install step (boost_install) merely copies include/.  So the port installs
-- the header tree directly, exactly like a Boost sublibrary is laid out, and
-- drives the test suite itself.
--
-- Upstream's test/CMakeLists.txt is equally unusable standalone:
--     include(BoostTestJamfile OPTIONAL RESULT_VARIABLE HAVE_BOOST_TEST)
--     if(HAVE_BOOST_TEST) boost_test_jamfile(FILE Jamfile ...)
-- Without the Boost superproject the include fails, HAVE_BOOST_TEST is FALSE
-- and the entire suite is silently skipped -- CMake happily reports success
-- having compiled nothing.  So the port reads upstream's own test/Jamfile (the
-- authoritative list of targets, used by the B2 CI) and reproduces it as a
-- generated CMake project driven through CTest:
--
--     run <name>.cpp      -> one registered CTest program
--     compile <name>.cpp  -> one CTest entry that compiles the TU (B2's
--                            `compile`: these have no main())
--
-- The 13 version-consistency targets (version.cpp and the twelve
-- `*_version.cpp` programs; check_cmake_version.cpp is not in the Jamfile, it
-- is the superproject's CMake check) are the exception.  They assert
--     BOOST_TEST_EQ( BOOST_MP11_VERSION, BOOST_VERSION )
-- i.e. that this sublibrary's version equals the Boost superproject version.
-- Mp11 1.92.0 is built here against the test-only dependency boost 1.81.0
-- (needed for boost/core/lightweight_test*.hpp and boost/mpl/**), so that
-- equality is false by construction and says nothing about mp11.  They are
-- therefore excluded from the suite and the invariant they are meant to
-- protect (BOOST_MP11_VERSION == 109200 for this release) is asserted instead
-- by the port's own sanity probe with a static_assert.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "1.92.0"
local VERSION_NUMBER = 109200
local CACHE_NAME = "mp11-1.92.0-boost-1.92.0"
local SOURCE_SHA = "a5754dc5ff9e7ff34119983889530e3ab8d8fb43ce2b4fea9c18673044df45d9"

-- Sanity probe: compiles and runs against the INSTALLED header tree only.
local PROBE = [==[
#include <boost/mp11.hpp>
#include <boost/mp11/version.hpp>
#include <boost/version.hpp>

#include <iostream>
#include <tuple>
#include <type_traits>
#include <utility>

using namespace boost::mp11;

using L = mp_list<int, char, double>;
using P = mp_transform<std::add_pointer_t, L>;

static_assert(BOOST_MP11_VERSION == 109200,
              "installed boost/mp11/version.hpp is not the 1.92.0 release");
static_assert(mp_size<L>::value == 3, "mp_size");
static_assert(std::is_same<mp_front<L>, int>::value, "mp_front");
static_assert(std::is_same<mp_at_c<L, 2>, double>::value, "mp_at_c");
static_assert(std::is_same<P, mp_list<int*, char*, double*>>::value, "mp_transform");
static_assert(mp_contains<L, char>::value, "mp_contains");
static_assert(std::is_same<mp_reverse<L>, mp_list<double, char, int>>::value, "mp_reverse");
static_assert(mp_map_contains<mp_list<mp_list<int, int*>>, int>::value, "mp_map");
static_assert(mp_all<mp_bool<true>, mp_bool<true>>::value, "mp_all");

int main()
{
    int calls = 0;
    std::tuple<int, char, double> t( 1, 'a', 2.5 );
    (void) t;
    mp_for_each< L >( [&]( auto ) { ++calls; } );

    bool same = std::is_same< mp_from_sequence< std::make_index_sequence< 3 > >,
                              mp_list< mp_size_t<0>, mp_size_t<1>, mp_size_t<2> > >::value;

    // runtime check of mp_with_index, i.e. real dispatching, not just types
    int idx = 2;
    int picked = mp_with_index< 4 >( idx, []( auto I ) { return int( I ); } );

    bool ok = calls == 3 && same && picked == 2;
    std::cout << "gcpkg mp11 sanity ok=" << ( ok ? 1 : 0 )
              << " size=" << mp_size<L>::value
              << " version=" << BOOST_MP11_VERSION
              << " boost=" << BOOST_VERSION << "\n";
    return ok ? 0 : 1;
}
]==]

local function split_lines(text)
    local out = {}
    for line in text:gmatch("[^\r\n]+") do out[#out + 1] = line end
    return out
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Read upstream's test/Jamfile: it is the authoritative target list (the same
-- file B2 uses in CI) and it carries the run/compile distinction that
-- test/CMakeLists.txt would only discover through the Boost superproject.
local function read_jamfile(ctx)
    local jam = assert(fs.read(util.join(ctx.src, "test", "Jamfile")),
                       "gcpkg: mp11: test/Jamfile missing")
    local run, compile_only = {}, {}
    for _, line in ipairs(split_lines(jam)) do
        local kind, name = line:match("^%s*(%a+)%s+([%w_]+)%.cpp")
        if kind == "run" then
            run[#run + 1] = name
        elseif kind == "compile" then
            compile_only[#compile_only + 1] = name
        end
    end
    return run, compile_only
end

-- Tests that cannot use boost 1.81's boost/core/type_name.hpp as-is, see the
-- generated CMakeLists below.
local TYPENAME_QUIRKS = { mp_lambda = "BOOST_NO_TYPEID" }

local function run_upstream_tests(ctx, incdir, boost_inc)
    local run, compile_only = read_jamfile(ctx)
    assert(#run >= 200, "gcpkg: mp11: Jamfile has too few run targets: " .. #run)
    assert(#compile_only >= 5,
           "gcpkg: mp11: Jamfile has too few compile targets: " .. #compile_only)

    -- Superproject version-consistency targets: not applicable here, see the
    -- header comment.  Kept in the counts below so a Jamfile change is caught.
    local version_tests, active = {}, {}
    for _, name in ipairs(run) do
        if name == "version" or name:match("_version$") then
            version_tests[#version_tests + 1] = name
        else
            active[#active + 1] = name
        end
    end
    assert(#version_tests == 13,
           "gcpkg: mp11: expected 13 version-consistency targets, found " ..
           #version_tests)
    assert(#active + #version_tests + #compile_only == 234,
           "gcpkg: mp11: Jamfile target count changed: " ..
           (#active + #version_tests + #compile_only))

    local testsdir = util.join(ctx.src, "test")
    local driver = util.join(ctx.build_dir, "upstream-tests")
    fs.mkdirs(driver)
    local lines = {
        "# Generated by the gcpkg mp11 port: upstream test/Jamfile, expressed as",
        "# a CMake project so the whole suite runs through CTest.",
        "cmake_minimum_required(VERSION 3.16)",
        "project(mp11-upstream-tests LANGUAGES CXX)",
        "enable_testing()",
        'set(MP11_INC "' .. tostring(incdir) .. '")',
        'set(BOOST_INC "' .. tostring(boost_inc) .. '")',
        'set(MP11_TESTS "' .. tostring(testsdir) .. '")',
        "set(CMAKE_CXX_STANDARD 17)",
        "set(CMAKE_CXX_STANDARD_REQUIRED ON)",
        "set(CMAKE_CXX_EXTENSIONS OFF)",
        "",
    }
    for _, name in ipairs(active) do
        lines[#lines + 1] = "add_executable(t_" .. name .. ' "${MP11_TESTS}/' ..
                            name .. '.cpp")'
        lines[#lines + 1] = "target_include_directories(t_" .. name ..
                            " PRIVATE ${MP11_INC} ${BOOST_INC})"
        if TYPENAME_QUIRKS[name] then
            -- mp_lambda.cpp deliberately names an incomplete type inside
            -- BOOST_TEST_TRAIT_TRUE (mp_lambda<X>::fn<> for a forward
            -- declared X, which mp11 supports).  boost 1.81's
            -- boost/core/type_name.hpp instantiates typeid(T) inside
            -- lightweight_test_trait.hpp and therefore refuses incomplete
            -- types; boost/core fixed that later.  BOOST_NO_TYPEID switches
            -- type_name to its non-typeid fallback, which only changes the
            -- text of a FAILURE message -- the assertion itself is untouched.
            lines[#lines + 1] = "set_source_files_properties(" ..
                                '"${MP11_TESTS}/' .. name ..
                                '.cpp" PROPERTIES COMPILE_DEFINITIONS ' ..
                                TYPENAME_QUIRKS[name] .. ")"
        end
        lines[#lines + 1] = "add_test(NAME " .. name .. " COMMAND t_" .. name .. ")"
        lines[#lines + 1] = ""
    end
    for _, name in ipairs(compile_only) do
        -- B2's `compile`: build the object file only, never link or run.
        lines[#lines + 1] = "# compile-only, as in test/Jamfile: `compile " ..
                            name .. ".cpp`"
        lines[#lines + 1] = "add_library(c_" .. name ..
                            ' OBJECT EXCLUDE_FROM_ALL "${MP11_TESTS}/' .. name ..
                            '.cpp")'
        lines[#lines + 1] = "target_include_directories(c_" .. name ..
                            " PRIVATE ${MP11_INC} ${BOOST_INC})"
        lines[#lines + 1] = "add_test(NAME compile_" .. name .. " COMMAND " ..
                            "${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} " ..
                            "--target c_" .. name .. ")"
        lines[#lines + 1] = ""
    end
    fs.write(util.join(driver, "CMakeLists.txt"),
             table.concat(lines, "\n") .. "\n")

    local dbuild = util.join(driver, "build")
    ctx.exec({ "cmake", "-S", driver, "-B", dbuild,
               "-DCMAKE_BUILD_TYPE=Release",
               "-DCMAKE_CXX_COMPILER=" .. tostring(ctx.compiler.wrapper_cxx) },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    ctx.exec({ "cmake", "--build", dbuild, "--parallel",
               tostring(ctx.jobs or 4) },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

    local out = util.join(ctx.build_dir, "ctest.out")
    ctx.exec({ "sh", "-c",
               "cd " .. dbuild .. " && ctest --output-on-failure " ..
               "--timeout 180 -j " .. tostring(ctx.jobs or 4) ..
               " > " .. out .. " 2>&1 < /dev/null; echo $? > " .. out .. ".rc" },
             { cwd = dbuild, log = ctx.log, env = ctx.env })
    local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
    local text = assert(fs.read(out), "gcpkg: mp11: missing ctest output")
    assert(not text:find("No tests were found", 1, true),
           "gcpkg: mp11: ctest found no registered tests")
    assert(text:find("100% tests passed", 1, true),
           "gcpkg: mp11: upstream test suite did not pass:\n" .. text)
    assert(rc == "0", "gcpkg: mp11: ctest exited with " .. rc)
    local registered = tonumber(text:match("out of (%d+)") or "0") or 0
    local expected = #active + #compile_only
    assert(registered == expected,
           "gcpkg: mp11: ctest ran " .. registered .. " of " .. expected ..
           " registered targets")

    return { run = #active, compile_only = #compile_only,
             version_skipped = #version_tests, registered = registered }
end

local function build(ctx)
    local on = ctx.features.enabled
    for _, k in ipairs({ "headers", "sanity", "license" }) do
        assert(on[k], "gcpkg: mp11: mandatory capability OFF: " .. k)
    end
    r20.restrict_pkgconfig(ctx)

    local boost = assert(r20.dep_prefix(ctx, "boost"),
                         "gcpkg: mp11: missing boost dependency")
    local boost_ver = "?"
    for _, m in ipairs(ctx.dependencies or {}) do
        if m.name == "boost" then boost_ver = tostring(m.version) end
    end
    local boost_inc = util.join(boost, "include")
    local incdir = util.join(ctx.prefix, "include")
    local docdir = util.join(ctx.prefix, "share", "doc", "mp11")
    local vdir = util.join(ctx.build_dir, "verify")
    local home = util.join(ctx.build_dir, "home")
    local tmp = util.join(ctx.build_dir, "tmp")
    fs.mkdirs(incdir)
    fs.mkdirs(util.join(incdir, "boost"))
    fs.mkdirs(docdir)
    fs.mkdirs(vdir)
    fs.mkdirs(home)
    fs.mkdirs(tmp)

    local old_path = tostring(ctx.env.PATH or "")
    local path_parts = { ctx.store.bin, "/usr/lib/llvm-23/bin", "/usr/bin", "/bin" }
    if old_path ~= "" then path_parts[#path_parts + 1] = old_path end
    ctx.env.PATH = table.concat(path_parts, ":")
    ctx.env.HOME = home
    ctx.env.TMPDIR = tmp
    ctx.env.GCPKG_COMPILER_FLAGS = ""
    assert(fs.isfile(util.join(ctx.store.cache, CACHE_NAME)),
           "gcpkg: mp11: source cache missing: " .. CACHE_NAME)

    -- header tree: include/boost/{mp11.hpp,mp11/**}
    ctx.exec({ "cp", "-a", util.join(ctx.src, "include", "boost") .. "/.",
               util.join(incdir, "boost") .. "/" },
             { cwd = ctx.src, log = ctx.log })
    for _, h in ipairs({ "mp11.hpp", "mp11/version.hpp", "mp11/list.hpp",
                         "mp11/algorithm.hpp", "mp11/tuple.hpp",
                         "mp11/integer_sequence.hpp", "mp11/utility.hpp",
                         "mp11/map.hpp", "mp11/set.hpp", "mp11/bind.hpp",
                         "mp11/function.hpp", "mp11/integral.hpp",
                         "mp11/mpl.hpp", "mp11/detail/mp_list.hpp" }) do
        assert(fs.isfile(util.join(incdir, "boost", h)),
               "gcpkg: mp11: " .. h .. " missing from the install tree")
    end

    if on["docs"] then
        for _, d in ipairs({ "README.md", "doc", "index.html" }) do
            local p = util.join(ctx.src, d)
            if fs.isfile(p) or fs.isdir(p) then
                ctx.exec({ "cp", "-a", p, docdir .. "/" },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
    end

    if on["license"] then
        -- upstream ships no LICENSE file of its own; every header carries the
        -- BSL-1.0 notice, and the boost dependency installs the canonical text.
        local text = util.join(boost, "share", "doc", "boost", "LICENSE_1_0.txt")
        assert(fs.isfile(text), "gcpkg: mp11: BSL text missing from boost dep")
        ctx.exec({ "cp", "-a", text, util.join(docdir, "LICENSE_1_0.txt") },
                 { log = ctx.log })
        assert(fs.isfile(util.join(docdir, "LICENSE_1_0.txt")),
               "gcpkg: mp11: LICENSE_1_0.txt not installed")
    end

    if on["pkgconfig"] then
        assert(on["headers"], "gcpkg: mp11: pkgconfig needs the headers feature")
        local pcdir = util.join(ctx.prefix, "lib", "pkgconfig")
        fs.mkdirs(pcdir)
        fs.write(util.join(pcdir, "mp11.pc"), table.concat({
            "prefix=" .. tostring(ctx.prefix),
            "includedir=" .. tostring(incdir),
            "",
            "Name: mp11",
            "Description: C++11 metaprogramming library (Boost.Mp11)",
            "Version: " .. VERSION,
            "Cflags: -I${includedir}",
            "",
        }, "\n"))
        assert(fs.isfile(util.join(pcdir, "mp11.pc")),
               "gcpkg: mp11: mp11.pc not written")
    end

    local facts = {
        "policy=source_built_header_only_no_upstream_cmake",
        "version=" .. VERSION,
        "version_number=" .. tostring(VERSION_NUMBER),
        "source_cache=" .. CACHE_NAME,
        "source_sha=" .. SOURCE_SHA,
        "source_patch=NO",
        "network_at_build=NO",
        "host_boost=NO",
        "upstream_cmake_usable=NO (fetches BoostFetch.cmake + boostorg/* at TAG develop)",
        "upstream_test_cmake_usable=NO (include(BoostTestJamfile OPTIONAL) silently skips the suite)",
        "test_driver=test/Jamfile -> generated CMake project -> CTest",
        "test_dependency=boost " .. boost_ver ..
        " (boost/core/lightweight_test*, boost/mpl); the tests are upstream's, the Boost superproject is not built here",
    }

    if on["tests"] then
        local r = run_upstream_tests(ctx, incdir, boost_inc)
        facts[#facts + 1] = "tests_run=" .. tostring(r.run)
        facts[#facts + 1] = "tests_compile_only=" .. tostring(r.compile_only)
        facts[#facts + 1] = "tests_registered=" .. tostring(r.registered)
        facts[#facts + 1] = "tests_type_name_quirk=mp_lambda compiled with " ..
                            "BOOST_NO_TYPEID (boost 1.81 core/type_name cannot " ..
                            "name incomplete types; diagnostics only)"
        facts[#facts + 1] = "tests_version_consistency_skipped=" ..
                            tostring(r.version_skipped) ..
                            " (BOOST_MP11_VERSION 109200 != BOOST_VERSION " ..
                            "of the test-only boost " .. boost_ver .. " dependency)"
    else
        facts[#facts + 1] = "tests_run=0 (feature tests OFF)"
    end

    if on["sanity"] then
        local probe = util.join(vdir, "mp11_probe.cpp")
        fs.write(probe, PROBE)
        local bin = cc.executable {
            sources = { probe },
            includes = { incdir, boost_inc },
            flags = { "-std=c++17" },
            defines = { "BOOST_ALL_NO_LIB=1" },
            cwd = vdir, outdir = util.join(vdir, "obj"),
            compiler = ctx.compiler.wrapper_cxx,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "mp11", cxx = true,
            output = util.join(vdir, "mp11_probe"),
        }
        local out, rc = ctx.capture({ bin }, { cwd = vdir, env = ctx.env })
        assert(rc == 0, "gcpkg: mp11: consumer TU failed:\n" .. tostring(out))
        assert(out:find("gcpkg mp11 sanity ok=1", 1, true),
               "gcpkg: mp11: consumer output mismatch:\n" .. tostring(out))
        facts[#facts + 1] = "consumer_rc=" .. tostring(rc)
        facts[#facts + 1] = "sanity_checks=mp_size/mp_front/mp_at_c/mp_transform/" ..
                            "mp_contains/mp_reverse/mp_map/mp_all/" ..
                            "mp_for_each/mp_from_sequence/mp_with_index+version"
    end

    facts[#facts + 1] = ""
    fs.write(util.join(vdir, "mp11-facts.txt"), table.concat(facts, "\n"))

    return {
        includes = { incdir }, libdirs = {}, libs = {},
        defines = { "BOOST_ALL_NO_LIB=1" },
        link_flags = {}, binaries = {}, compdb_files = {},
    }
end

return recipe.define {
    name = "mp11",
    version = VERSION,
    license = "BSL-1.0",
    homepage = "https://www.boost.org/libs/mp11/",
    description = "C++11 metaprogramming library (Boost.Mp11)",
    source = {
        url = "https://github.com/boostorg/mp11/archive/refs/tags/boost-1.92.0.tar.gz",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    build = build,
}
