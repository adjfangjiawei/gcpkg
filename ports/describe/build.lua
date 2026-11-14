-- describe 1.92.0 -- R20 new-standard header-only port.
--
-- Boost.Describe: C++14 reflection on enums and aggregates, implemented as a
-- pure header tree (boost/describe/**) plus the boost/describe.hpp umbrella.
--
-- Why the upstream CMake build is not used (same reasoning as the mp11 port):
--   * describe's top-level CMakeLists.txt has no install() rules at all -- the
--     real one comes from BoostInstall in the superproject -- and
--     `add_subdirectory(test)` is guarded by
--         if(BUILD_TESTING AND EXISTS .../test/CMakeLists.txt)
--   * test/CMakeLists.txt is
--         include(BoostTestJamfile OPTIONAL RESULT_VARIABLE HAVE_BOOST_TEST)
--         if(HAVE_BOOST_TEST) boost_test_jamfile(FILE Jamfile ...)
--     so outside the superproject the include fails and the whole suite is
--     silently skipped: CMake reports success having compiled nothing.
-- The port therefore installs the header tree itself and reproduces upstream's
-- test/Jamfile with a generated CMake project driven through CTest:
--
--     run <file>.cpp        -> one registered CTest program
--     compile <file>.cpp    -> one CTest entry that compiles the TU
--     compile-fail <file>   -> one CTest entry that must FAIL to compile
--                              (upstream's `compile-fail`; CTest WILL_FAIL
--                              expresses exactly that semantics)
--
-- Jamfile targets live in two places: test/*.cpp and ../example/*.cpp (the
-- examples double as tests upstream).  Every example is kept except
-- example/serialization.cpp, which needs a compiled Boost.Serialization --
-- the test dependency here is the header-only part of boost 1.81.0.
-- example/console.cpp is a `link` target in the Jamfile (built, never run) and
-- is registered as a build-only test.
--
-- Everything the suite needs beyond describe itself (boost/core/*, boost/mp11,
-- boost/variant2, boost/container_hash, boost/json) comes from the gcpkg
-- `boost` and `mp11` dependencies; the json examples link boost_json.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "1.92.0"
local CACHE_NAME = "describe-1.92.0-boost-1.92.0"
local SOURCE_SHA = "4ef61ea2ca967b803e171f4756e03e201680d5dd19d014324f9a848e0d06863b"

-- Jamfile targets that cannot be reproduced here, with the reason recorded in
-- the facts file.
local SKIPPED = {
    ["../example/serialization"] =
        "needs a compiled Boost.Serialization, absent from the test dependency",
}

-- Examples that link the compiled boost_json library.
local JSON_TARGETS = {
    to_json = true, from_json = true, json_rpc = true, console = true,
}

local PROBE = [==[
#include <boost/describe.hpp>
#include <boost/describe/enum_to_string.hpp>
#include <boost/describe/enum_from_string.hpp>
#include <boost/mp11.hpp>

#include <iostream>
#include <sstream>
#include <string>
#include <type_traits>

namespace app {

enum class color { red = 1, green = 2, blue = 4 };
BOOST_DESCRIBE_ENUM(color, red, green, blue)

struct base
{
    int b = 0;
};

struct point : base
{
    int x = 1;
    int y = 2;
    std::string name = "p";
};

BOOST_DESCRIBE_STRUCT(base, (), (b))
BOOST_DESCRIBE_STRUCT(point, (base), (x, y, name))

} // namespace app

using namespace boost::describe;
namespace mp = boost::mp11;

// The descriptor lists are the reflection: check them at compile time.
static_assert(mp::mp_size< describe_enumerators< app::color > >::value == 3,
              "enumerators");
static_assert(mp::mp_size< describe_bases< app::point, mod_any_access > >::value == 1,
              "bases");
static_assert(mp::mp_size< describe_members< app::point, mod_any_access > >::value == 3,
              "members");

int main()
{
    // Boost.Describe exposes the descriptor lists; iteration is mp11's job.
    using enumerators_list = describe_enumerators< app::color >;
    using members_list = describe_members< app::point, mod_any_access >;
    using bases_list = describe_bases< app::point, mod_any_access >;

    int enumerators = 0;
    mp::mp_for_each< enumerators_list >( [&]( auto d ) { ++enumerators; (void) d; } );

    int members = 0;
    int named = 0;
    mp::mp_for_each< members_list >( [&]( auto d ) {
        ++members;
        if( std::string( d.name ) == "name" ) ++named;
    } );

    int bases = 0;
    mp::mp_for_each< bases_list >( [&]( auto d ) { ++bases; (void) d; } );

    app::point p;
    p.name = "origin";
    p.x = 7;

    // Reach every member through its descriptor's pointer-to-member and read
    // the value back: exactly one of them must be the name we wrote.
    int matches = 0;
    mp::mp_for_each< members_list >( [&]( auto d ) {
        std::ostringstream os;
        os << ( p.*( d.pointer ) );
        if( os.str() == "origin" ) ++matches;
    } );
    bool member_ok = ( matches == 1 );

    // enum_to_string / enum_from_string: real lookups, not type counting.
    char const * sname = enum_to_string( app::color::blue, nullptr );
    bool roundtrip = false;
    if( sname != nullptr )
    {
        app::color back = app::color::red;
        roundtrip = enum_from_string< app::color >( sname, back ) &&
                    back == app::color::blue;
    }

    bool ok = enumerators == 3 && members == 3 && named == 1 && bases == 1 &&
              roundtrip && member_ok;

    std::cout << "gcpkg describe sanity ok=" << ( ok ? 1 : 0 )
              << " enumerators=" << enumerators
              << " members=" << members
              << " bases=" << bases
              << " roundtrip=" << ( roundtrip ? 1 : 0 ) << "\n";
    return ok ? 0 : 1;
}
]==]

local function split_lines(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    return lines
end

-- Parse upstream's test/Jamfile into the three target kinds it uses for
-- library tests.  `link` targets are kept as build-only tests.
local function read_jamfile(ctx)
    local jam = assert(fs.read(util.join(ctx.src, "test", "Jamfile")),
                       "gcpkg: describe: test/Jamfile missing")
    local run, compile_only, compile_fail, link_only = {}, {}, {}, {}
    for _, line in ipairs(split_lines(jam)) do
        local kind, name = line:match("^(%a[%a%-]*)%s+([%w_%./%-]+)%.cpp")
        if kind then
            if kind == "run" then
                run[#run + 1] = name
            elseif kind == "compile" then
                compile_only[#compile_only + 1] = name
            elseif kind == "compile-fail" then
                compile_fail[#compile_fail + 1] = name
            elseif kind == "link" then
                link_only[#link_only + 1] = name
            end
        end
    end
    return run, compile_only, compile_fail, link_only
end

local function source_path(ctx, name)
    if name:sub(1, 2) == ".." then
        return tostring(ctx.src) .. "/test/" .. name .. ".cpp"
    end
    return tostring(ctx.src) .. "/test/" .. name .. ".cpp"
end

local function target_name(name)
    return (name:gsub("^%.%./", ""):gsub("[/%-%.]", "_"))
end

local function run_upstream_tests(ctx, incdir, dep_includes, libdirs, libs)
    local run, compile_only, compile_fail, link_only = read_jamfile(ctx)
    assert(#run >= 50, "gcpkg: describe: Jamfile has too few run targets: " .. #run)
    assert(#compile_only >= 4,
           "gcpkg: describe: Jamfile has too few compile targets: " .. #compile_only)
    assert(#compile_fail == 4,
           "gcpkg: describe: expected 4 compile-fail targets, found " .. #compile_fail)
    assert(#link_only == 1,
           "gcpkg: describe: expected 1 link target, found " .. #link_only)

    local driver = util.join(ctx.build_dir, "upstream-tests")
    fs.mkdirs(driver)
    local incs = { incdir }
    for _, p in ipairs(dep_includes) do incs[#incs + 1] = p end
    local lines = {
        "# Generated by the gcpkg describe port: upstream test/Jamfile, expressed",
        "# as a CMake project so the suite runs through CTest.",
        "cmake_minimum_required(VERSION 3.16)",
        "project(describe-upstream-tests LANGUAGES CXX)",
        "enable_testing()",
        "set(DESCRIBE_INC \"" .. table.concat(incs, ";") .. "\")",
        "set(DESCRIBE_LIBDIRS \"" .. table.concat(libdirs, ";") .. "\")",
        "set(DESCRIBE_LIBS \"" .. table.concat(libs, ";") .. "\")",
        "set(CMAKE_CXX_STANDARD 14)",
        "set(CMAKE_CXX_STANDARD_REQUIRED ON)",
        "set(CMAKE_CXX_EXTENSIONS OFF)",
        "",
    }

    local skipped = {}
    local executed = {}
    local function add_target(name, execute)
        local t = target_name(name)
        lines[#lines + 1] = "add_executable(t_" .. t .. ' "' ..
                            source_path(ctx, name) .. '")'
        lines[#lines + 1] = "target_include_directories(t_" .. t ..
                            " PRIVATE ${DESCRIBE_INC})"
        if JSON_TARGETS[t:gsub("^example_", "")] then
            lines[#lines + 1] = "target_link_directories(t_" .. t ..
                                " PRIVATE ${DESCRIBE_LIBDIRS})"
            lines[#lines + 1] = "target_link_libraries(t_" .. t ..
                                " PRIVATE ${DESCRIBE_LIBS})"
        end
        if execute then
            lines[#lines + 1] = "add_test(NAME " .. t .. " COMMAND t_" .. t .. ")"
            executed[#executed + 1] = t
        else
            -- B2 `link`: link the program, never run it.  (These are
            -- interactive demos -- example/console.cpp is a prompt loop -- so
            -- running them would block forever.)
            lines[#lines + 1] = "# B2 `link` target: linked, not run"
            lines[#lines + 1] = "add_test(NAME link_" .. t .. " COMMAND " ..
                                "${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} " ..
                                "--target t_" .. t .. ")"
        end
        lines[#lines + 1] = ""
    end

    for _, name in ipairs(run) do
        if SKIPPED[name] then
            skipped[#skipped + 1] = name
        else
            add_target(name, true)
        end
    end
    for _, name in ipairs(link_only) do
        if not SKIPPED[name] then add_target(name, false) end
    end
    if #executed > 0 then
        lines[#lines + 1] = "set_tests_properties(" ..
                            table.concat(executed, " ") ..
                            " PROPERTIES TIMEOUT 120)"
        lines[#lines + 1] = ""
    end
    for _, name in ipairs(compile_only) do
        local t = target_name(name)
        lines[#lines + 1] = "# compile-only, as in test/Jamfile: `compile " ..
                            name .. ".cpp`"
        lines[#lines + 1] = "add_library(c_" .. t ..
                            ' OBJECT EXCLUDE_FROM_ALL "' .. source_path(ctx, name) ..
                            '")'
        lines[#lines + 1] = "target_include_directories(c_" .. t ..
                            " PRIVATE ${DESCRIBE_INC})"
        lines[#lines + 1] = "add_test(NAME compile_" .. t .. " COMMAND " ..
                            "${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} " ..
                            "--target c_" .. t .. ")"
        lines[#lines + 1] = ""
    end
    for _, name in ipairs(compile_fail) do
        local t = target_name(name)
        lines[#lines + 1] = "# compile-fail, as in test/Jamfile: `compile-fail " ..
                            name .. ".cpp` -- the target must NOT compile"
        lines[#lines + 1] = "add_library(cf_" .. t ..
                            ' OBJECT EXCLUDE_FROM_ALL "' .. source_path(ctx, name) ..
                            '")'
        lines[#lines + 1] = "target_include_directories(cf_" .. t ..
                            " PRIVATE ${DESCRIBE_INC})"
        lines[#lines + 1] = "add_test(NAME compile_fail_" .. t .. " COMMAND " ..
                            "${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} " ..
                            "--target cf_" .. t .. ")"
        lines[#lines + 1] = "set_tests_properties(compile_fail_" .. t ..
                            " PROPERTIES WILL_FAIL TRUE)"
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
    local text = assert(fs.read(out), "gcpkg: describe: missing ctest output")
    assert(not text:find("No tests were found", 1, true),
           "gcpkg: describe: ctest found no registered tests")
    assert(text:find("100% tests passed", 1, true),
           "gcpkg: describe: upstream test suite did not pass:\n" .. text)
    assert(rc == "0", "gcpkg: describe: ctest exited with " .. rc)
    local registered = tonumber(text:match("out of (%d+)") or "0") or 0
    local expected = #run + #link_only - #skipped + #compile_only + #compile_fail
    assert(registered == expected,
           "gcpkg: describe: ctest ran " .. registered .. " of " .. expected ..
           " registered targets")

    return { run = #run + #link_only - #skipped,
             compile_only = #compile_only, compile_fail = #compile_fail,
             registered = registered, skipped = skipped }
end

local function build(ctx)
    local on = ctx.features.enabled
    for _, k in ipairs({ "headers", "sanity", "license" }) do
        assert(on[k], "gcpkg: describe: mandatory capability OFF: " .. k)
    end
    r20.restrict_pkgconfig(ctx)

    local boost = assert(r20.dep_prefix(ctx, "boost"),
                         "gcpkg: describe: missing boost dependency")
    local mp11 = assert(r20.dep_prefix(ctx, "mp11"),
                        "gcpkg: describe: missing mp11 dependency")
    local boost_ver = "?"
    for _, m in ipairs(ctx.dependencies or {}) do
        if m.name == "boost" then boost_ver = tostring(m.version) end
    end
    local incdir = util.join(ctx.prefix, "include")
    local docdir = util.join(ctx.prefix, "share", "doc", "describe")
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
           "gcpkg: describe: source cache missing: " .. CACHE_NAME)

    ctx.exec({ "cp", "-a", util.join(ctx.src, "include", "boost") .. "/.",
               util.join(incdir, "boost") .. "/" },
             { cwd = ctx.src, log = ctx.log })
    for _, h in ipairs({ "describe.hpp", "describe/class.hpp",
                         "describe/members.hpp", "describe/enum.hpp",
                         "describe/bases.hpp", "describe/enumerators.hpp",
                         "describe/operators.hpp", "describe/enum_to_string.hpp",
                         "describe/enum_from_string.hpp",
                         "describe/descriptor_by_name.hpp",
                         "describe/descriptor_by_pointer.hpp",
                         "describe/detail/config.hpp" }) do
        assert(fs.isfile(util.join(incdir, "boost", h)),
               "gcpkg: describe: " .. h .. " missing from the install tree")
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
        local text = util.join(boost, "share", "doc", "boost", "LICENSE_1_0.txt")
        assert(fs.isfile(text), "gcpkg: describe: BSL text missing from boost dep")
        ctx.exec({ "cp", "-a", text, util.join(docdir, "LICENSE_1_0.txt") },
                 { log = ctx.log })
        assert(fs.isfile(util.join(docdir, "LICENSE_1_0.txt")),
               "gcpkg: describe: LICENSE_1_0.txt not installed")
    end

    if on["pkgconfig"] then
        assert(on["headers"], "gcpkg: describe: pkgconfig needs the headers feature")
        local pcdir = util.join(ctx.prefix, "lib", "pkgconfig")
        fs.mkdirs(pcdir)
        fs.write(util.join(pcdir, "describe.pc"), table.concat({
            "prefix=" .. tostring(ctx.prefix),
            "includedir=" .. tostring(incdir),
            "",
            "Name: describe",
            "Description: C++14 reflection on enums and aggregates (Boost.Describe)",
            "Version: " .. VERSION,
            "Requires: mp11",
            "Cflags: -I${includedir}",
            "",
        }, "\n"))
        assert(fs.isfile(util.join(pcdir, "describe.pc")),
               "gcpkg: describe: describe.pc not written")
    end

    local facts = {
        "policy=source_built_header_only_no_upstream_cmake",
        "version=" .. VERSION,
        "source_cache=" .. CACHE_NAME,
        "source_sha=" .. SOURCE_SHA,
        "source_patch=NO",
        "network_at_build=NO",
        "host_boost=NO",
        "upstream_cmake_usable=NO (no install() rules outside the superproject)",
        "upstream_test_cmake_usable=NO (include(BoostTestJamfile OPTIONAL) silently skips the suite)",
        "test_driver=test/Jamfile -> generated CMake project -> CTest",
        "test_dependency=boost " .. boost_ver ..
        " (core/lightweight_test*, container_hash, variant2, json) + mp11 " .. VERSION,
    }

    if on["tests"] then
        local dep_includes = { util.join(boost, "include"), util.join(mp11, "include") }
        for _, p in ipairs(ctx.includes or {}) do
            local dup = false
            for _, q in ipairs(dep_includes) do
                if q == p then dup = true end
            end
            if not dup then dep_includes[#dep_includes + 1] = p end
        end
        local r = run_upstream_tests(ctx, incdir, dep_includes,
                                     ctx.libdirs or {}, ctx.libs or {})
        facts[#facts + 1] = "tests_run=" .. tostring(r.run)
        facts[#facts + 1] = "tests_compile_only=" .. tostring(r.compile_only)
        facts[#facts + 1] = "tests_compile_fail=/" .. tostring(r.compile_fail) ..
                            " (CTest WILL_FAIL: the TU must not compile)"
        facts[#facts + 1] = "tests_registered=" .. tostring(r.registered)
        for _, name in ipairs(r.skipped) do
            facts[#facts + 1] = "tests_skipped=" .. name .. " (" ..
                                tostring(SKIPPED[name]) .. ")"
        end
    else
        facts[#facts + 1] = "tests_run=0 (feature tests OFF)"
    end

    if on["sanity"] then
        local probe = util.join(vdir, "describe_probe.cpp")
        fs.write(probe, PROBE)
        local incs = { incdir, util.join(boost, "include"), util.join(mp11, "include") }
        local bin = cc.executable {
            sources = { probe },
            includes = incs,
            flags = { "-std=c++17" },
            defines = { "BOOST_ALL_NO_LIB=1" },
            cwd = vdir, outdir = util.join(vdir, "obj"),
            compiler = ctx.compiler.wrapper_cxx,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "describe", cxx = true,
            output = util.join(vdir, "describe_probe"),
        }
        local out, rc = ctx.capture({ bin }, { cwd = vdir, env = ctx.env })
        assert(rc == 0, "gcpkg: describe: consumer TU failed:\n" .. tostring(out))
        assert(out:find("gcpkg describe sanity ok=1", 1, true),
               "gcpkg: describe: consumer output mismatch:\n" .. tostring(out))
        facts[#facts + 1] = "consumer_rc=" .. tostring(rc)
        facts[#facts + 1] = "sanity_checks=enum/enumerators/struct members/bases/" ..
                            "enum_to_string/enum_from_string/member pointer access"
    end

    facts[#facts + 1] = ""
    fs.write(util.join(vdir, "describe-facts.txt"), table.concat(facts, "\n"))

    return {
        includes = { incdir }, libdirs = {}, libs = {},
        defines = { "BOOST_ALL_NO_LIB=1" },
        link_flags = {}, binaries = {}, compdb_files = {},
    }
end

return recipe.define {
    name = "describe",
    version = VERSION,
    license = "BSL-1.0",
    homepage = "https://www.boost.org/libs/describe/",
    description = "C++14 reflection on enums and aggregates (Boost.Describe)",
    source = {
        url = "https://github.com/boostorg/describe/archive/refs/tags/boost-1.92.0.tar.gz",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    build = build,
}
