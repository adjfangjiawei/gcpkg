-- pfr 1.92.0 -- R20 new-standard header-only port.
--
-- Boost.PFR: C++14 user-defined reflection for aggregates, header-only
-- (boost/pfr/** plus the boost/pfr.hpp umbrella).
--
-- The port installs the header tree itself because upstream's top-level
-- CMakeLists.txt has no install() rules of its own (the Boost superproject
-- supplies them through BoostInstall, which lives in a downloaded module tree).
-- There is nothing to configure and nothing to compile, so a CMake configure
-- would only add moving parts.
--
-- For the tests the port follows upstream's *CMake* test project
-- (test/CMakeLists.txt), which unlike mp11's or describe's is genuinely
-- standalone:
--     file(GLOB CORE_RUN_FILES "core/run/*.cpp")
--     ... add_executable(pfr_core_<name> ...) ; add_test(...)
--     file(GLOB CORE_NAME_RUN_FILES "core_name/run/*.cpp")   # needs cxx_std_20
-- so it is reproduced verbatim as a generated project, plus:
--
--   * test/config/print_config.cpp, the B2 `run` target that prints the
--     selected reflection engine (kept as a diagnostic program, output is
--     recorded in pfr-config.out);
--   * upstream's 26 `compile-fail` targets -- test/core/compile-fail/*.cpp and
--     test/core_name/compile-fail/*.cpp -- registered with CTest WILL_FAIL,
--     which is exactly B2's `compile-fail` semantics: the TU must not compile.
--     B2 builds them with STRUCTURED_BINDING_ENGINE, i.e.
--     BOOST_PFR_USE_LOOPHOLE=0 BOOST_PFR_USE_CPP17=1 BOOST_PFR_USE_CPP26=0
--     BOOST_PFR_USE_CPP26_REFLECTION=0, and so does this port.
--
-- Not reproduced (they belong to B2's configuration matrix, not to the library
-- API): the loophole / cpp17 / cpp26 / classic engine cross product, the
-- python target, and the eight top-level detection helpers under test/core/
-- (loophole_detection.cpp, variadic_structured_binding_detection.cpp,
-- cpp26_reflection_detection.cpp, ...), whose contract is "compiles on
-- supported compilers" rather than "runs and returns 0".
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "1.92.0"
local CACHE_NAME = "pfr-1.92.0-boost-1.92.0"
local SOURCE_SHA = "8209971b8a799dfb367ddb16f32343715c11579859dbc635c249aa8aeab7b66a"

-- B2's STRUCTURED_BINDING_ENGINE, used by upstream for the compile-fail set.
local SB_ENGINE = {
    "BOOST_PFR_USE_LOOPHOLE=0",
    "BOOST_PFR_USE_CPP17=1",
    "BOOST_PFR_USE_CPP26=0",
    "BOOST_PFR_USE_CPP26_REFLECTION=0",
}

local PROBE = [==[
#include <boost/pfr.hpp>
#include <boost/pfr/io.hpp>

#include <iostream>
#include <sstream>
#include <string>
#include <type_traits>

struct inner
{
    int v = 0;
};

inline std::ostream & operator<<( std::ostream & os, inner const & x )
{
    return os << "inner(" << x.v << ")";
}

struct point
{
    int x = 1;
    int y = 2;
    inner in;
    std::string name = "p";
};

static_assert(boost::pfr::tuple_size< point >::value == 4, "tuple_size");
static_assert(boost::pfr::tuple_size_v< point > == 4, "tuple_size_v");

int main()
{
    point p;
    p.x = 7;
    p.in.v = 42;

    // field access, mutation through the reflection and structured bindings
    int sum = 0;
    boost::pfr::for_each_field( p, [&]( auto const & f ) {
        if constexpr( std::is_same< std::decay_t< decltype( f ) >, int >::value ) sum += f;
    } );
    boost::pfr::get< 0 >( p ) = 11;

    auto tied = boost::pfr::structure_tie( p );

    // io: the aggregate printed through the reflection
    std::ostringstream os;
    os << boost::pfr::io( p );
    std::string text = os.str();

    bool ok = sum == 9 && boost::pfr::get< 0 >( p ) == 11 &&
              std::get< 0 >( tied ) == 11 && text.find( "11" ) != std::string::npos;

    std::cout << "gcpkg pfr sanity ok=" << ( ok ? 1 : 0 )
              << " fields=" << boost::pfr::tuple_size_v< point >
              << " sum=" << sum << " io=\"" << text << "\"\n";
    return ok ? 0 : 1;
}
]==]

local function split_lines(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    return lines
end

local function list_cpp(ctx, reldir)
    local dir = util.join(ctx.src, reldir)
    if not fs.isdir(dir) then return {} end
    local out = {}
    for _, f in ipairs(fs.listdir(dir)) do
        if f:match("%.cpp$") then out[#out + 1] = f:gsub("%.cpp$", "") end
    end
    table.sort(out)
    return out
end

local function run_upstream_tests(ctx, incdir, dep_includes)
    local driver = util.join(ctx.build_dir, "upstream-tests")
    fs.mkdirs(driver)
    local incs = { incdir }
    for _, p in ipairs(dep_includes) do incs[#incs + 1] = p end

    local core_run = list_cpp(ctx, "test/core/run")
    local core_name_run = list_cpp(ctx, "test/core_name/run")
    local core_cf = list_cpp(ctx, "test/core/compile-fail")
    local core_name_cf = list_cpp(ctx, "test/core_name/compile-fail")
    assert(#core_run >= 39,
           "gcpkg: pfr: expected 39 test/core/run targets, found " .. #core_run)
    assert(#core_name_run >= 8,
           "gcpkg: pfr: expected 8 test/core_name/run targets, found " ..
           #core_name_run)
    assert(#core_cf >= 16,
           "gcpkg: pfr: expected 16 test/core/compile-fail targets, found " ..
           #core_cf)
    assert(#core_name_cf >= 10,
           "gcpkg: pfr: expected 10 test/core_name/compile-fail targets, found " ..
           #core_name_cf)

    local lines = {
        "# Generated by the gcpkg pfr port: upstream test/CMakeLists.txt, plus",
        "# the compile-fail set, expressed as one CTest project.",
        "cmake_minimum_required(VERSION 3.16)",
        "project(pfr-upstream-tests LANGUAGES CXX)",
        "enable_testing()",
        "set(PFR_INC \"" .. table.concat(incs, ";") .. "\")",
        "set(PFR_SRC \"" .. tostring(ctx.src) .. "\")",
        "set(CMAKE_CXX_EXTENSIONS OFF)",
        "",
    }

    for _, name in ipairs(core_run) do
        lines[#lines + 1] = "add_executable(pfr_core_" .. name ..
                            ' "${PFR_SRC}/test/core/run/' .. name .. '.cpp")'
        lines[#lines + 1] = "target_include_directories(pfr_core_" .. name ..
                            " PRIVATE ${PFR_INC})"
        lines[#lines + 1] = "target_compile_features(pfr_core_" .. name ..
                            " PRIVATE cxx_std_17)"
        lines[#lines + 1] = "add_test(NAME core_" .. name ..
                            " COMMAND pfr_core_" .. name .. ")"
        lines[#lines + 1] = "set_tests_properties(core_" .. name ..
                            " PROPERTIES TIMEOUT 120)"
        lines[#lines + 1] = ""
    end
    for _, name in ipairs(core_name_run) do
        lines[#lines + 1] = "add_executable(pfr_corename_" .. name ..
                            ' "${PFR_SRC}/test/core_name/run/' .. name .. '.cpp")'
        lines[#lines + 1] = "target_include_directories(pfr_corename_" .. name ..
                            " PRIVATE ${PFR_INC})"
        lines[#lines + 1] = "target_compile_features(pfr_corename_" .. name ..
                            " PRIVATE cxx_std_20)"
        lines[#lines + 1] = "add_test(NAME core_name_" .. name ..
                            " COMMAND pfr_corename_" .. name .. ")"
        lines[#lines + 1] = "set_tests_properties(core_name_" .. name ..
                            " PROPERTIES TIMEOUT 120)"
        lines[#lines + 1] = ""
    end

    -- test/config/print_config.cpp: B2 `run`, prints the engine configuration.
    lines[#lines + 1] = "add_executable(pfr_print_config \"${PFR_SRC}/test/config/print_config.cpp\")"
    lines[#lines + 1] = "target_include_directories(pfr_print_config PRIVATE ${PFR_INC})"
    lines[#lines + 1] = "target_compile_features(pfr_print_config PRIVATE cxx_std_17)"
    lines[#lines + 1] = "add_test(NAME config_print_config COMMAND pfr_print_config)"
    lines[#lines + 1] = ""

    local function add_compile_fail(dir, name, std)
        local t = ("cf_" .. dir .. "_" .. name):gsub("/", "_")
        lines[#lines + 1] = "# compile-fail, as in B2: `compile-fail " .. name ..
                            ".cpp` with STRUCTURED_BINDING_ENGINE -- must NOT compile"
        lines[#lines + 1] = "add_library(" .. t .. ' OBJECT EXCLUDE_FROM_ALL "${PFR_SRC}/test/' ..
                            dir .. "/" .. name .. '.cpp")'
        lines[#lines + 1] = "target_include_directories(" .. t ..
                            " PRIVATE ${PFR_INC})"
        lines[#lines + 1] = "target_compile_features(" .. t .. " PRIVATE cxx_std_" ..
                            std .. ")"
        lines[#lines + 1] = "target_compile_definitions(" .. t .. " PRIVATE " ..
                            table.concat(SB_ENGINE, " ") .. ")"
        lines[#lines + 1] = "add_test(NAME compile_fail_" .. dir .. "_" .. name ..
                            " COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR}" ..
                            " --target " .. t .. ")"
        lines[#lines + 1] = "set_tests_properties(compile_fail_" .. dir .. "_" ..
                            name .. " PROPERTIES WILL_FAIL TRUE)"
        lines[#lines + 1] = ""
    end
    for _, name in ipairs(core_cf) do
        add_compile_fail("core/compile-fail", name, "17")
    end
    for _, name in ipairs(core_name_cf) do
        add_compile_fail("core_name/compile-fail", name, "20")
    end

    fs.write(util.join(driver, "CMakeLists.txt"), table.concat(lines, "\n") .. "\n")

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
    local text = assert(fs.read(out), "gcpkg: pfr: missing ctest output")
    assert(not text:find("No tests were found", 1, true),
           "gcpkg: pfr: ctest found no registered tests")
    assert(text:find("100% tests passed", 1, true),
           "gcpkg: pfr: upstream test suite did not pass:\n" .. text)
    assert(rc == "0", "gcpkg: pfr: ctest exited with " .. rc)
    local registered = tonumber(text:match("out of (%d+)") or "0") or 0
    local expected = #core_run + #core_name_run + 1 + #core_cf + #core_name_cf
    assert(registered == expected,
           "gcpkg: pfr: ctest ran " .. registered .. " of " .. expected ..
           " registered targets")

    -- keep the engine diagnostic next to the results
    local cfgout = util.join(ctx.build_dir, "pfr-config.out")
    ctx.exec({ "sh", "-c",
               "cd " .. dbuild .. " && ./pfr_print_config > " .. cfgout ..
               " 2>&1; true" },
             { cwd = dbuild, log = ctx.log, env = ctx.env })

    return { core_run = #core_run, core_name_run = #core_name_run,
             compile_fail = #core_cf + #core_name_cf, registered = registered }
end

local function build(ctx)
    local on = ctx.features.enabled
    for _, k in ipairs({ "headers", "sanity", "license" }) do
        assert(on[k], "gcpkg: pfr: mandatory capability OFF: " .. k)
    end
    r20.restrict_pkgconfig(ctx)

    local boost = assert(r20.dep_prefix(ctx, "boost"),
                         "gcpkg: pfr: missing boost dependency")
    local boost_ver = "?"
    for _, m in ipairs(ctx.dependencies or {}) do
        if m.name == "boost" then boost_ver = tostring(m.version) end
    end
    local incdir = util.join(ctx.prefix, "include")
    local docdir = util.join(ctx.prefix, "share", "doc", "pfr")
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
           "gcpkg: pfr: source cache missing: " .. CACHE_NAME)

    ctx.exec({ "cp", "-a", util.join(ctx.src, "include", "boost") .. "/.",
               util.join(incdir, "boost") .. "/" },
             { cwd = ctx.src, log = ctx.log })
    for _, h in ipairs({ "pfr.hpp", "pfr/core.hpp", "pfr/io.hpp",
                         "pfr/ops.hpp", "pfr/traits.hpp", "pfr/tuple_size.hpp",
                         "pfr/core_name.hpp", "pfr/config.hpp",
                         "pfr/functors.hpp", "pfr/detail/config.hpp",
                         "pfr/detail/sequence_tuple.hpp" }) do
        assert(fs.isfile(util.join(incdir, "boost", h)),
               "gcpkg: pfr: " .. h .. " missing from the install tree")
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
        local text = util.join(ctx.src, "LICENSE_1_0.txt")
        assert(fs.isfile(text), "gcpkg: pfr: LICENSE_1_0.txt missing from source")
        ctx.exec({ "cp", "-a", text, util.join(docdir, "LICENSE_1_0.txt") },
                 { log = ctx.log })
        assert(fs.isfile(util.join(docdir, "LICENSE_1_0.txt")),
               "gcpkg: pfr: LICENSE_1_0.txt not installed")
    end

    if on["pkgconfig"] then
        assert(on["headers"], "gcpkg: pfr: pkgconfig needs the headers feature")
        local pcdir = util.join(ctx.prefix, "lib", "pkgconfig")
        fs.mkdirs(pcdir)
        fs.write(util.join(pcdir, "pfr.pc"), table.concat({
            "prefix=" .. tostring(ctx.prefix),
            "includedir=" .. tostring(incdir),
            "",
            "Name: pfr",
            "Description: C++14 user-defined reflection for aggregates (Boost.PFR)",
            "Version: " .. VERSION,
            "Cflags: -I${includedir}",
            "",
        }, "\n"))
        assert(fs.isfile(util.join(pcdir, "pfr.pc")),
               "gcpkg: pfr: pfr.pc not written")
    end

    local facts = {
        "policy=source_built_header_only_no_upstream_cmake",
        "version=" .. VERSION,
        "source_cache=" .. CACHE_NAME,
        "source_sha=" .. SOURCE_SHA,
        "source_patch=NO",
        "network_at_build=NO",
        "host_boost=NO",
        "upstream_cmake_usable=NO (no install() rules outside the superproject; test/CMakeLists.txt reproduced directly)",
        "test_driver=test/CMakeLists.txt + compile-fail set -> CTest",
        "test_dependency=boost " .. boost_ver ..
        " (core/lightweight_test*, container_hash, type_index headers)",
    }

    if on["tests"] then
        local dep_includes = { util.join(boost, "include") }
        for _, p in ipairs(ctx.includes or {}) do
            local dup = false
            for _, q in ipairs(dep_includes) do
                if q == p then dup = true end
            end
            if not dup then dep_includes[#dep_includes + 1] = p end
        end
        local r = run_upstream_tests(ctx, incdir, dep_includes)
        facts[#facts + 1] = "tests_core_run=" .. tostring(r.core_run)
        facts[#facts + 1] = "tests_core_name_run=" .. tostring(r.core_name_run) ..
                            " (cxx_std_20)"
        facts[#facts + 1] = "tests_config_run=1 (print_config.cpp)"
        facts[#facts + 1] = "tests_compile_fail=" .. tostring(r.compile_fail) ..
                            " (CTest WILL_FAIL, STRUCTURED_BINDING_ENGINE)"
        facts[#facts + 1] = "tests_registered=" .. tostring(r.registered)
        facts[#facts + 1] = "tests_not_reproduced=B2 engine matrix " ..
                            "(loophole/cpp17/cpp26/classic), python target, " ..
                            "8 top-level detection helpers under test/core/"
    else
        facts[#facts + 1] = "tests_run=0 (feature tests OFF)"
    end

    if on["sanity"] then
        local probe = util.join(vdir, "pfr_probe.cpp")
        fs.write(probe, PROBE)
        local bin = cc.executable {
            sources = { probe },
            includes = { incdir, util.join(boost, "include") },
            flags = { "-std=c++17" },
            defines = { "BOOST_ALL_NO_LIB=1" },
            cwd = vdir, outdir = util.join(vdir, "obj"),
            compiler = ctx.compiler.wrapper_cxx,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "pfr", cxx = true,
            output = util.join(vdir, "pfr_probe"),
        }
        local out, rc = ctx.capture({ bin }, { cwd = vdir, env = ctx.env })
        assert(rc == 0, "gcpkg: pfr: consumer TU failed:\n" .. tostring(out))
        assert(out:find("gcpkg pfr sanity ok=1", 1, true),
               "gcpkg: pfr: consumer output mismatch:\n" .. tostring(out))
        facts[#facts + 1] = "consumer_rc=" .. tostring(rc)
        facts[#facts + 1] = "sanity_checks=tuple_size/tuple_size_v/get/" ..
                            "for_each_field/structure_tie/io"
    end

    facts[#facts + 1] = ""
    fs.write(util.join(vdir, "pfr-facts.txt"), table.concat(facts, "\n"))

    return {
        includes = { incdir }, libdirs = {}, libs = {},
        defines = { "BOOST_ALL_NO_LIB=1" },
        link_flags = {}, binaries = {}, compdb_files = {},
    }
end

return recipe.define {
    name = "pfr",
    version = VERSION,
    license = "BSL-1.0",
    homepage = "https://www.boost.org/libs/pfr/",
    description = "C++14 user-defined reflection for aggregates (Boost.PFR)",
    source = {
        url = "https://github.com/boostorg/pfr/archive/refs/tags/boost-1.92.0.tar.gz",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    build = build,
}
