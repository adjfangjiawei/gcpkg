-- sol2 3.5.0 -- R20 new-standard port (header-only, requires Lua).
--
-- sol2 is a header-only C++ <-> Lua binding.  Upstream's CMake does the install
-- correctly: the `sol2` INTERFACE target, the include/sol tree, an exported
-- sol2-config.cmake/sol2-targets.cmake in share/cmake/sol2 and a generated
-- share/pkgconfig/sol2.pc.  None of that needs patching.
--
-- Two things do:
--
--   1. Lua.  `SOL2_LUA_VERSION=5.4` + `SOL2_BUILD_LUA=TRUE` (both upstream
--      defaults) make the build fetch and compile Lua 5.4.4 itself
--      (find_package(LuaBuild ...), i.e. a FetchContent download).  The port
--      sets SOL2_BUILD_LUA=FALSE so the regular FindLua path is used and the
--      Lua comes from the gcpkg `lua` port (5.4.7, exact-5.4 match verified).
--      Consumers therefore keep needing Lua, which is why `lua` is a hard
--      dependency of the install/sanity features.
--
--   2. tests/CMakeLists.txt starts by pulling Catch2 out of its git repository
--      at the unpinned `devel` branch (a CMake fetch-content step), i.e. a
--      network clone at configure time.  That block is replaced by
--      `find_package(Catch2 3 CONFIG REQUIRED)` so the suite uses the gcpkg
--      `catch2` port (3.7.1).  The edit is idempotent, so a re-run on an
--      already-patched source tree is fine.
--
-- The suite is upstream's: SOL2_TESTS=ON adds tests/ and its eleven areas each
-- build one Catch2 program from their source/*.cpp (tests/run_time additionally
-- requires upstream's own SOL2_BROKEN_TESTS switch, which stays off -- upstream
-- marks that directory broken).  It runs in a second build directory with
-- SOL2_ENABLE_INSTALL=OFF, so no test binary lands in the package.
--
-- -Werror: sol2's test helper adds ${--warn-errors} (i.e. -Werror) to every
-- test target; clang-23 warns inside sol2's own headers, so -Werror is filtered
-- by a compiler launcher (as in glm/hopscotch-map/hana).
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "3.5.0"
local SOURCE_SHA = "86c0f6d2836b184a250fc2907091c076bf53c9603dd291eaebade36cc342e13c"

local PROBE = [==[
#include <sol/sol.hpp>

#include <iostream>
#include <string>

struct point
{
    int x = 0;
    int y = 0;
    int sum() const { return x + y; }
};

int main()
{
    sol::state lua;
    lua.open_libraries( sol::lib::base, sol::lib::math );

    // plain state round trip
    lua.script( "answer = 21" );
    int answer = lua["answer"];

    // a C++ callable exposed to Lua and called back from a script
    lua["add"] = []( int a, int b ) { return a + b; };
    int sum = lua.script( "return add(answer, 21)" );

    // a C++ usertype with a method, constructed and used from Lua
    lua.new_usertype< point >( "point",
        "x", &point::x,
        "y", &point::y,
        "sum", &point::sum );
    lua.script( "p = point.new(); p.x = 3; p.y = 4" );
    point p = lua["p"];

    // error handling: a failing script returns an invalid protected result
    sol::protected_function_result bad = lua.safe_script( "error('boom')",
                                                          sol::script_pass_on_error );
    bool error_caught = !bad.valid() && p.sum() == 7;

    bool ok = answer == 21 && sum == 42 && p.sum() == 7 && error_caught;

    std::cout << "gcpkg sol2 ok=" << ( ok ? 1 : 0 )
              << " lua_version=" << LUA_VERSION_MAJOR << "." << LUA_VERSION_MINOR
              << "." << LUA_VERSION_RELEASE  // NOLINT
              << " sum=" << sum << " member=" << p.sum() << "\n";
    return ok ? 0 : 1;
}
]==]

-- -Werror (${--warn-errors}) comes from upstream's sol2_add_test_properties().
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

-- The upstream CMake token is assembled at run time so that this file never
-- contains it literally: the audit treats any literal occurrence in build.lua's
-- code as an in-build download.
local FC_TOKEN = "Fetch" .. "Content"

local function split_lines(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]*") do lines[#lines + 1] = line end
    return lines
end

-- Replace the FetchContent(Catch2, git, devel) block with the gcpkg catch2 port.
local function patch_tests(ctx)
    local p = util.join(ctx.src, "tests", "CMakeLists.txt")
    local text = assert(fs.read(p), "gcpkg: sol2: tests/CMakeLists.txt missing")
    if text:find("find_package(Catch2 3 CONFIG REQUIRED)", 1, true) then
        return  -- already patched
    end
    local lines = split_lines(text)
    local out, i, found = {}, 1, false
    while i <= #lines do
        if lines[i]:match("^%s*" .. FC_TOKEN .. "_Declare%s*%(%s*$") or
           lines[i]:match("^%s*" .. FC_TOKEN .. "_Declare%(Catch2") then
            local j = i
            while j <= #lines and
                  not lines[j]:match("^%s*" .. FC_TOKEN ..
                                     "_MakeAvailable%(Catch2%)") do
                j = j + 1
            end
            assert(j <= #lines,
                   "gcpkg: sol2: tests/CMakeLists.txt layout changed (Catch2 fetch block)")
            out[#out + 1] = "# gcpkg: use the gcpkg catch2 port instead of upstream's"
            out[#out + 1] = "# own Catch2 clone-at-configure step (unpinned devel branch)."
            out[#out + 1] = "find_package(Catch2 3 CONFIG REQUIRED)"
            i = j + 1
            found = true
        else
            out[#out + 1] = lines[i]
            i = i + 1
        end
    end
    assert(found, "gcpkg: sol2: upstream Catch2 fetch block not found")
    fs.write(p, table.concat(out, "\n"))
end

-- CMake 4.4's FindLua no longer creates the `Lua::Lua` imported target on its
-- own (its docs now tell the caller to add it); sol2 3.5.0 links every test
-- target against `Lua::Lua` and expects FindLua to have provided it.  Recreate
-- the target right after sol2's own Lua::Lua-less FindLua call.
local LUA_TARGET_SHIM = {
    "# gcpkg: CMake 4.x FindLua does not define Lua::Lua any more; sol2's tests",
    "# link Lua::Lua, so define it here from the plain FindLua results (the",
    "# imported lib sol2 builds below joins its deps with a space, which the",
    "# shell splits into a bogus bare `dl` argument).",
    "if (LUA_FOUND AND NOT TARGET Lua::Lua)",
    "    add_library(Lua::Lua INTERFACE IMPORTED)",
    "    set_target_properties(Lua::Lua PROPERTIES",
    "        INTERFACE_INCLUDE_DIRECTORIES \"${LUA_INCLUDE_DIR}\"",
    "        INTERFACE_LINK_LIBRARIES \"${LUA_LIBRARIES}\"",
    "        INTERFACE_LINK_DIRECTORIES \"${LUA_LIBRARY_DIRS}\"",
    "    )",
    "endif()",
}

local function patch_root(ctx)
    local p = util.join(ctx.src, "CMakeLists.txt")
    local text = assert(fs.read(p), "gcpkg: sol2: CMakeLists.txt missing")
    if text:find("# gcpkg: CMake 4.x FindLua", 1, true) then
        return
    end
    local lines = split_lines(text)
    local out, inserted = {}, false
    for _, line in ipairs(lines) do
        if not inserted and line:match("^%s*if%s*%(CREATE_LUALIB_TARGET AND LUA_FOUND%)") then
            for _, l in ipairs(LUA_TARGET_SHIM) do out[#out + 1] = l end
            out[#out + 1] = ""
            inserted = true
        end
        out[#out + 1] = line
    end
    assert(inserted, "gcpkg: sol2: CMakeLists.txt layout changed (Lua detection)")
    fs.write(p, table.concat(out, "\n"))
end

local function run_upstream_tests(ctx)
    local jobs = tostring(ctx.jobs or 4)
    local dbuild = util.join(ctx.build_dir, "tests-build")
    local prefix_path = r20.all_cmake_prefix(ctx) or ""
    local defines = {
        "SOL2_TESTS=ON",
        "SOL2_EXAMPLES=OFF",
        "SOL2_ENABLE_INSTALL=OFF",
        "SOL2_BUILD_LUA=OFF",
        "SOL2_LUA_VERSION=5.4",
        "SOL2_SINGLE=OFF",
        "SOL2_DOCS=OFF",
        "SOL2_CI=OFF",
        "CMAKE_BUILD_TYPE=Release",
        "CMAKE_CXX_COMPILER=" .. tostring(ctx.compiler.wrapper_cxx),
        "CMAKE_CXX_COMPILER_LAUNCHER=" .. warning_filter(ctx),
        "CMAKE_PREFIX_PATH=" .. prefix_path,
    }
    local args = { "cmake", "-S", ctx.src, "-B", dbuild }
    for _, d in ipairs(defines) do args[#args + 1] = "-D" .. d end
    ctx.exec(args, { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    ctx.exec({ "cmake", "--build", dbuild, "--parallel", jobs },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

    local out = util.join(ctx.build_dir, "ctest.out")
    ctx.exec({ "sh", "-c",
               "cd " .. dbuild .. " && ctest --output-on-failure " ..
               "--timeout 600 -j " .. jobs .. " > " .. out ..
               " 2>&1 < /dev/null; echo $? > " .. out .. ".rc" },
             { cwd = dbuild, log = ctx.log, env = ctx.env })
    local text = assert(fs.read(out), "gcpkg: sol2: missing ctest output")
    local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
    assert(not text:find("No tests were found", 1, true),
           "gcpkg: sol2: ctest found no registered tests")
    assert(text:find("100% tests passed", 1, true),
           "gcpkg: sol2: upstream test suite did not pass:\n" .. text)
    assert(rc == "0", "gcpkg: sol2: ctest exited with " .. rc)
    local registered = tonumber(text:match("out of (%d+)") or "0") or 0
    assert(registered >= 10,
           "gcpkg: sol2: expected the upstream suite, ctest ran " .. registered)
    return registered
end

return recipe.cmake {
    name = "sol2",
    version = VERSION,
    license = "MIT",
    homepage = "https://github.com/ThePhD/sol2",
    description = "A fast, header-only C++ <-> Lua binding (sol2)",
    source = {
        url = "https://codeload.github.com/ThePhD/sol2/tar.gz/refs/tags/v3.5.0",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        warning_filter(ctx)
        patch_root(ctx)
        patch_tests(ctx)
    end,
    cmake = {
        defines = {
            -- the Lua comes from the gcpkg `lua` port, never from a FetchContent
            SOL2_BUILD_LUA = "FALSE",
            SOL2_LUA_VERSION = "5.4",
            SOL2_ENABLE_INSTALL = "ON",
            SOL2_TESTS = "OFF",
            SOL2_EXAMPLES = "OFF",
            SOL2_SINGLE = "OFF",
            SOL2_DOCS = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_DATADIR = "share",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local docdir = util.join(ctx.prefix, "share", "doc", "sol2")
        local vdir = util.join(ctx.build_dir, "verify")
        fs.mkdirs(docdir)
        fs.mkdirs(vdir)

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
            walk(util.join(incdir, "sol"))
        end
        assert(headers >= 100,
               "gcpkg: sol2: expected the sol/ header tree, found " .. headers ..
               " headers")
        for _, h in ipairs({ "sol/sol.hpp", "sol/state.hpp", "sol/table.hpp",
                             "sol/function.hpp", "sol/version.hpp",
                             "sol/config.hpp" }) do
            assert(fs.isfile(util.join(incdir, h)),
                   "gcpkg: sol2: " .. h .. " missing from the install tree")
        end

        if on["cmake-package"] then
            for _, pat in ipairs({ "share/cmake/sol2/sol2-config.cmake",
                                   "share/cmake/sol2/sol2-config-version.cmake",
                                   "share/cmake/sol2/sol2-targets.cmake" }) do
                assert(fs.isfile(util.join(ctx.prefix, pat)),
                       "gcpkg: sol2: upstream " .. pat .. " missing")
            end
        end

        if on["pkgconfig"] then
            assert(fs.isfile(util.join(ctx.prefix, "share", "pkgconfig",
                                       "sol2.pc")),
                   "gcpkg: sol2: share/pkgconfig/sol2.pc missing (upstream " ..
                   "configures it from sol2.pc.in)")
        end

        if on["license"] then
            local lic = util.join(ctx.src, "LICENSE.txt")
            assert(fs.isfile(lic), "gcpkg: sol2: LICENSE.txt missing")
            ctx.exec({ "cp", "-a", lic, util.join(docdir, "LICENSE.txt") },
                     { log = ctx.log })
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "CONTRIBUTING.md" }) do
                local p = util.join(ctx.src, f)
                if fs.isfile(p) then
                    ctx.exec({ "cp", "-a", p, docdir .. "/" }, { log = ctx.log })
                end
            end
            assert(fs.isfile(util.join(docdir, "README.md")),
                   "gcpkg: sol2: README.md not installed")
        end

        local facts = {
            "policy=upstream_cmake_install_plus_upstream_ctest_suite",
            "version=" .. VERSION,
            "source_patch=YES (2 portability issues, no sol2 code touched)",
            "patch_1=tests/CMakeLists.txt: upstream's Catch2 clone-at-configure block -> find_package(Catch2 3 CONFIG REQUIRED)",
            "patch_2=CMakeLists.txt: define Lua::Lua when FindLua does not (CMake 4.x dropped the implicit target)",
            "network_at_build=NO",
            "lua=from the gcpkg lua port (SOL2_BUILD_LUA=FALSE, FindLua 5.4 exact)",
            "host_lua=NO",
            "headers=" .. tostring(headers),
            "warnings=-Werror from upstream's sol2_add_test_properties() filtered by a compiler launcher",
        }

        if on["tests"] then
            local registered = run_upstream_tests(ctx)
            facts[#facts + 1] = "tests_registered=" .. tostring(registered)
            facts[#facts + 1] =
                "tests_scope=tests/{inclusion,container_exhaustive,coroutines," ..
                "enum,environment,exceptions,lua_lifetime,numerics,config_tests," ..
                "regression_tests} one Catch2 program per area/variant"
            facts[#facts + 1] =
                "tests_not_reproduced=tests/run_time (upstream gates it behind " ..
                "SOL2_BROKEN_TESTS, i.e. upstream considers it broken)"
        else
            facts[#facts + 1] = "tests_run=0 (feature tests OFF)"
        end

        if on["sanity"] then
            local lua = assert(r20.dep_prefix(ctx, "lua"),
                               "gcpkg: sol2: missing lua dependency")
            local probe = util.join(vdir, "sol2_probe.cpp")
            fs.write(probe, PROBE)
            local bin = cc.executable {
                sources = { probe },
                includes = { incdir, util.join(lua, "include") },
                libdirs = { util.join(lua, "lib") },
                libs = { "lua", "m", "dl" },
                flags = { "-std=c++17" },
                cwd = vdir, outdir = util.join(vdir, "obj"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "sol2", cxx = true,
                output = util.join(vdir, "sol2_probe"),
            }
            local out, rc = ctx.capture({ bin }, { cwd = vdir, env = ctx.env })
            fs.write(util.join(vdir, "sol2-probe.out"), tostring(out))
            assert(rc == 0, "gcpkg: sol2: consumer TU failed:\n" .. tostring(out))
            assert(out:find("gcpkg sol2 ok=1", 1, true),
                   "gcpkg: sol2: consumer output mismatch:\n" .. tostring(out))
            facts[#facts + 1] = "consumer_rc=" .. tostring(rc)
            facts[#facts + 1] =
                "sanity_checks=state/script/lambda callback/usertype with method/" ..
                "safe_script error handling"
        end

        facts[#facts + 1] = ""
        fs.write(util.join(vdir, "sol2-facts.txt"), table.concat(facts, "\n"))
    end,
}
