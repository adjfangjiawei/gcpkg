-- parallel-hashmap (phmap) v1.4.1 -- R20 new-standard header-only port.
--
-- A family of drop-in hash maps/sets (flat_hash_map, node_hash_map,
-- parallel_flat_hash_map, btree_map, ...).  Upstream's CMakeLists.txt declares
--
--   PHMAP_BUILD_TESTS    -> tests    / no-tests    (GoogleTest suites, one
--                           executable per tests/*_test.cc, registered with
--                           CTest)
--   PHMAP_BUILD_EXAMPLES -> examples / no-examples (the 20 example programs)
--   PHMAP_INSTALL        -> install  / no-install  (headers + the phmap
--                           INTERFACE target)
--
-- Upstream problem this port fixes: `if (NOT PHMAP_GTEST_LIBS)` pulls
-- cmake/DownloadGTest.cmake, i.e. it downloads GoogleTest from the network at
-- configure time.  A package build must not do that, and gcpkg already ships a
-- googletest port, so pre_build patches that block to find_package(GTest
-- CONFIG REQUIRED) and link GTest::gmock_main.  The `tests` feature declares
-- `requires: ["googletest"]`, so the dependency is only pulled in when the
-- tests are actually enabled.
--
-- Upstream installs headers and the INTERFACE target but no CMake package
-- config (only `export(EXPORT ...)` into the build tree), so this port writes a
-- pkg-config file and does not claim a CONFIG package.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local VERSION = "v1.4.1"

local GTEST_NEEDLE = [[        include(cmake/DownloadGTest.cmake)

        check_target(gtest)
        check_target(gtest_main)
        check_target(gmock)
        set(PHMAP_GTEST_LIBS gmock_main)]]

local GTEST_PATCH = [[        # gcpkg patch: link the gcpkg googletest port instead of downloading
        # GoogleTest from the network at configure time.
        find_package(GTest CONFIG REQUIRED)
        set(PHMAP_GTEST_LIBS GTest::gmock_main GTest::gmock GTest::gtest)]]

local function patch_gtest(ctx)
    local p = util.join(ctx.src, "CMakeLists.txt")
    local src = assert(fs.read(p), "gcpkg: parallel-hashmap: CMakeLists.txt missing")
    if src:find(GTEST_PATCH, 1, true) then return end
    local i, j = src:find(GTEST_NEEDLE, 1, true)
    assert(i, "gcpkg: parallel-hashmap: upstream's DownloadGTest block no " ..
              "longer matches the text this port patches")
    fs.write(p, src:sub(1, i - 1) .. GTEST_PATCH .. src:sub(j + 1))
end

return recipe.cmake {
    name = "parallel-hashmap",
    version = VERSION,
    license = "Apache-2.0",
    homepage = "https://github.com/greg7mdp/parallel-hashmap",
    description = "A family of header-only hash maps and sets: flat, node, parallel and btree",
    source = {
        url = "https://codeload.github.com/greg7mdp/parallel-hashmap/tar.gz/refs/tags/v1.4.1",
        sha256 = "949874f4207b8735422438b23b884fb1f4b926689bb5eebff38cc4d357d09cd2",
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        patch_gtest(ctx)
    end,
    cmake = {
        defines = {
            PHMAP_BUILD_TESTS = "OFF",
            PHMAP_BUILD_EXAMPLES = "OFF",
            PHMAP_INSTALL = "OFF",
            CMAKE_CXX_STANDARD = "17",
            CMAKE_CXX_STANDARD_REQUIRED = "ON",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local docdir = util.join(ctx.prefix, "share", "doc", "parallel-hashmap")
        fs.mkdirs(docdir)

        for _, h in ipairs({ "parallel_hashmap/phmap.h",
                             "parallel_hashmap/phmap_dump.h",
                             "parallel_hashmap/btree.h",
                             "parallel_hashmap/phmap_bits.h" }) do
            assert(fs.isfile(util.join(incdir, h)),
                   "gcpkg: parallel-hashmap: " .. h .. " missing from the install tree")
        end

        if on["pkgconfig"] then
            local pcdir = util.join(ctx.prefix, "lib", "pkgconfig")
            fs.mkdirs(pcdir)
            fs.write(util.join(pcdir, "parallel-hashmap.pc"), table.concat({
                "prefix=" .. tostring(ctx.prefix),
                "includedir=" .. tostring(incdir),
                "",
                "Name: parallel-hashmap",
                "Description: A family of header-only hash maps and sets",
                "Version: 1.4.1",
                "Cflags: -I${includedir} -std=c++17",
                "",
            }, "\n"))
        end

        if on["tests"] then
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "ctest --output-on-failure > " .. out .. " 2>&1; echo $? > " ..
                       out .. ".rc" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out), "gcpkg: parallel-hashmap: missing ctest output")
            assert(not text:find("No tests were found", 1, true),
                   "gcpkg: parallel-hashmap: ctest found no registered tests")
            assert(text:find("100% tests passed", 1, true),
                   "gcpkg: parallel-hashmap: upstream test suite did not pass: " .. text)
            assert(rc == "0", "gcpkg: parallel-hashmap: ctest exited with " .. rc)
            local registered = tonumber(text:match("out of (%d+)") or "0") or 0
            assert(registered >= 17,
                   "gcpkg: parallel-hashmap: expected upstream's whole gtest " ..
                   "suite, ctest ran " .. registered)
            for _, t in ipairs({ "test_flat_hash_map", "test_node_hash_map",
                                 "test_parallel_flat_hash_map", "test_btree",
                                 "test_raw_hash_set" }) do
                assert(text:find(t, 1, true),
                       "gcpkg: parallel-hashmap: " .. t .. " did not run")
            end
        end

        if on["examples"] then
            for _, ex in ipairs({ "ex_basic", "ex_allmaps", "ex_btree",
                                  "ex_hash", "ex_dump_load", "ex_two_files" }) do
                assert(fs.isfile(util.join(ctx.build_dir, ex)),
                       "gcpkg: parallel-hashmap: example " .. ex .. " was not built")
            end
            -- ex_basic and ex_btree are self-contained: run them for real
            local ran = {}
            for _, ex in ipairs({ "ex_basic", "ex_btree" }) do
                local out = util.join(ctx.build_dir, ex .. ".out")
                ctx.exec({ "sh", "-c",
                           "cd " .. ctx.build_dir .. " && ./" .. ex .. " > " ..
                           out .. " 2>&1; echo $? >> " .. out },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local text = assert(fs.read(out),
                                    "gcpkg: parallel-hashmap: missing " .. ex .. " output")
                assert(text:find("0%s*$") ~= nil,
                       "gcpkg: parallel-hashmap: " .. ex .. " exited non-zero: " .. text)
                ran[#ran + 1] = ex
            end
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "CITATION.cff" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
            if fs.isdir(util.join(ctx.src, "doc")) then
                ctx.exec({ "cp", "-a", util.join(ctx.src, "doc"), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
        if on["license"] then
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: parallel-hashmap: LICENSE missing")
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end

        if on["sanity"] then
            local csrc = util.join(ctx.build_dir, "phmap_sanity.cpp")
            fs.write(csrc, [==[
#include <parallel_hashmap/phmap.h>
#if __has_include(<parallel_hashmap/btree.h>)
#include <parallel_hashmap/btree.h>
#endif
#include <cstdio>
#include <string>

int main() {
  phmap::flat_hash_map<std::string, int> m;
  m["a"] = 1;
  m["b"] = 2;
  if (m.size() != 2) return 2;
  if (m.at("b") != 2) return 3;
  phmap::parallel_flat_hash_map<int, int> pm;
  pm[7] = 70;
  if (pm[7] != 70) return 4;
  phmap::btree_map<int, int> bt;
  bt[3] = 30;
  if (bt.begin()->second != 30) return 5;
  std::printf("gcpkg phmap ok size=%zu\n", m.size());
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "phmap_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17", "-pthread" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "parallel-hashmap", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out),
                                "gcpkg: parallel-hashmap: missing sanity output")
            assert(text:find("gcpkg phmap ok", 1, true),
                   "gcpkg: parallel-hashmap: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
