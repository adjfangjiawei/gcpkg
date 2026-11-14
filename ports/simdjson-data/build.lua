-- simdjson-data a5b13ba -- gcpkg data-only source port.
-- Pinned simdjson developer-mode test/benchmark data.  The installed tree is
-- the exact upstream CMake project (LANGUAGES NONE), so simdjson's
-- add_dependency(simdjson-data) can add_subdirectory() it directly instead of
-- reaching import.cmake's file(DOWNLOAD).  No network at configure time, no
-- system library discovery, no hand-written CONFIG package.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local VERSION = "a5b13ba"
local COMMIT = "a5b13babe65c1bba7186b41b43d4cbdc20a5c470"
local CACHE_NAME = "simdjson-data-a5b13ba-" .. COMMIT
local CACHE_SHA = "aa5c4e199d05730116f3c9664a1897a75fde30dd9236334800eb83b08c6aba70"

return recipe.define {
    name = "simdjson-data",
    version = VERSION,
    license = "Apache-2.0",
    homepage = "https://github.com/simdjson/simdjson-data",
    description = "simdjson developer-mode JSON test/benchmark corpora (pinned " .. COMMIT .. ")",
    source = {
        url = "https://codeload.github.com/simdjson/simdjson-data/tar.gz/" .. COMMIT,
        sha256 = CACHE_SHA,
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        assert(on["data"], "gcpkg: simdjson-data: data feature is required")
        local root = util.join(ctx.prefix, "share", "simdjson-data")
        local dir = util.join(root, "simdjson-data")
        fs.mkdirs(dir)
        fs.mkdirs(ctx.build_dir)
        fs.mkdirs(util.join(ctx.build_dir, "obj"))
        -- Import the whole upstream project verbatim.  import.cmake only
        -- checks EXISTS <dep_root>/simdjson-data; add_dependency() then runs
        -- add_subdirectory() on it, so the CMakeLists and every subdirectory
        -- must be present, not just the JSON files.
        assert(ctx.exec({ "cp", "-a", ctx.src .. "/.", dir .. "/" },
                        { cwd = ctx.src, log = ctx.log }) == 0,
               "gcpkg: simdjson-data: copying upstream tree failed")
        local cmake_root = util.join(dir, "CMakeLists.txt")
        assert(fs.isfile(cmake_root), "gcpkg: simdjson-data: root CMakeLists missing")
        for _, rel in ipairs({
            "jsonchecker/CMakeLists.txt", "jsonchecker/minefield/CMakeLists.txt",
            "jsonexamples/CMakeLists.txt", "jsonexamples/generated/CMakeLists.txt",
            "jsonexamples/generated/genfeaturejson.rb",
            "jsonchecker/pass01.json", "jsonexamples/twitter.json",
        }) do
            assert(fs.isfile(util.join(dir, rel)),
                   "gcpkg: simdjson-data: missing upstream file " .. rel)
        end
        local json_count = 0
        local function walk(p)
            for _, name in ipairs(fs.listdir(p) or {}) do
                local q = util.join(p, name)
                if fs.isdir(q) then
                    walk(q)
                elseif name:match("%.json$") or name:match("%.ndjson$") then
                    json_count = json_count + 1
                end
            end
        end
        walk(dir)
        assert(json_count >= 1900,
               "gcpkg: simdjson-data: unexpectedly small JSON corpus " .. json_count)

        local docdir = util.join(ctx.prefix, "share", "doc", "simdjson-data")
        local docs = 0
        if on["docs"] then
            fs.mkdirs(docdir)
            for _, name in ipairs({ "README.md", "LICENSE", "LICENSE.md", "AUTHORS" }) do
                local src = util.join(ctx.src, name)
                if fs.isfile(src) then
                    assert(ctx.exec({ "cp", "-a", src, util.join(docdir, name) },
                                    { cwd = ctx.src, log = ctx.log }) == 0,
                           "gcpkg: simdjson-data: copying " .. name .. " failed")
                    docs = docs + 1
                end
            end
        end

        -- Independent CMake consumer: the installed data tree is a real CMake
        -- project that exports the four INTERFACE targets simdjson links via
        -- link_libraries(test-data).  This proves it without configuring
        -- simdjson itself.
        local cmake_targets = "NOT_RUN"
        if on["cmake-data"] then
            local vdir = util.join(ctx.build_dir, "verify")
            fs.mkdirs(vdir)
            local cdir = util.join(vdir, "data-consumer")
            fs.mkdirs(cdir)
            fs.write(util.join(cdir, "CMakeLists.txt"), ([==[
cmake_minimum_required(VERSION 3.14)
project(gcpkg_simdjson_data_consumer LANGUAGES NONE)
set(_gcpkg_data_bin "@BUILD_DIR@/_deps/simdjson-data")
add_subdirectory("@DATA_DIR@" "${_gcpkg_data_bin}" EXCLUDE_FROM_ALL)
foreach(t test-data jsonchecker-data jsonchecker-minefield-data jsonexamples-data)
  if(NOT TARGET ${t})
    message(FATAL_ERROR "gcpkg simdjson-data: missing INTERFACE target ${t}")
  endif()
endforeach()
get_target_property(_gcpkg_test_links test-data INTERFACE_LINK_LIBRARIES)
if(NOT _gcpkg_test_links)
  message(FATAL_ERROR "gcpkg simdjson-data: test-data links no data targets")
endif()
foreach(dep jsonchecker-data jsonchecker-minefield-data jsonexamples-data)
  if(NOT "${dep}" IN_LIST _gcpkg_test_links)
    message(FATAL_ERROR "gcpkg simdjson-data: test-data does not link ${dep}")
  endif()
endforeach()
get_target_property(_gcpkg_json_defs jsonchecker-data INTERFACE_COMPILE_DEFINITIONS)
get_target_property(_gcpkg_mine_defs jsonchecker-minefield-data INTERFACE_COMPILE_DEFINITIONS)
get_target_property(_gcpkg_bench_defs jsonexamples-data INTERFACE_COMPILE_DEFINITIONS)
if(NOT _gcpkg_json_defs MATCHES "SIMDJSON_TEST_DATA_DIR=")
  message(FATAL_ERROR "gcpkg simdjson-data: jsonchecker-data has no SIMDJSON_TEST_DATA_DIR definition")
endif()
if(NOT _gcpkg_mine_defs MATCHES "SIMDJSON_MINEFIELD_TEST_DATA_DIR=")
  message(FATAL_ERROR "gcpkg simdjson-data: minefield-data has no SIMDJSON_MINEFIELD_TEST_DATA_DIR definition")
endif()
if(NOT _gcpkg_bench_defs MATCHES "SIMDJSON_BENCHMARK_DATA_DIR=")
  message(FATAL_ERROR "gcpkg simdjson-data: jsonexamples-data has no SIMDJSON_BENCHMARK_DATA_DIR definition")
endif()
# The upstream data project exports the three directories into its OWN scope;
# a consumer reads them either from that directory or from the target compile
# definitions above.  Prove both, without patching upstream CMakeLists.
foreach(v SIMDJSON_TEST_DATA_DIR SIMDJSON_MINEFIELD_TEST_DATA_DIR SIMDJSON_BENCHMARK_DATA_DIR)
  get_directory_property(_gcpkg_dir_value DIRECTORY "${_gcpkg_data_bin}" DEFINITION ${v})
  if(NOT _gcpkg_dir_value OR "${_gcpkg_dir_value}" MATCHES "-NOTFOUND$")
    message(FATAL_ERROR "gcpkg simdjson-data: ${v} not exported by data project")
  endif()
endforeach()
message(STATUS "gcpkg simdjson-data: 4 INTERFACE targets + 3 data dirs + 3 compile definitions OK")
]==]):gsub("@DATA_DIR@", dir):gsub("@BUILD_DIR@", cdir))
            local noTry = util.join(ctx.build_dir, "gcpkg-no-try-compile.cmake")
            local cmd = {
                "cmake", "-S", cdir, "-B", util.join(cdir, "build"),
                "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
            }
            if fs.isfile(noTry) then
                cmd[#cmd + 1] = "-DCMAKE_PROJECT_INCLUDE=" .. noTry
            end
            assert(ctx.exec(cmd, { cwd = cdir, env = ctx.env, log = ctx.log }) == 0,
                   "gcpkg: simdjson-data: independent data CMake consumer failed")
            cmake_targets = "OK"
        end

        -- One real compile command: a data port still gets a compdb entry,
        -- and the TU documents the installed corpus root at build time.
        local sanity = "NOT_RUN"
        if on["sanity"] then
            local probe = util.join(ctx.build_dir, "gcpkg_simdjson_data_probe.cpp")
            fs.write(probe,
                "// gcpkg simdjson-data sanity TU; corpus CMake root: " .. cmake_root .. "\n" ..
                "#include <string>\n" ..
                "int main() { const char* p = \"" .. dir .. "\"; " ..
                "return std::string(p).empty(); }\n")
            cc.compile {
                sources = { probe }, includes = {}, flags = { "-std=c++17" },
                cwd = ctx.build_dir, outdir = util.join(ctx.build_dir, "obj"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "simdjson-data",
            }
            sanity = "OK"
        end

        local facts = util.join(ctx.build_dir, "verify", "data-facts.txt")
        fs.mkdirs(util.dirname(facts))
        fs.write(facts, table.concat({
            "port=simdjson-data", "version=" .. VERSION, "commit=" .. COMMIT,
            "cache_name=" .. CACHE_NAME, "cache_sha=" .. CACHE_SHA,
            "data_dir=" .. dir, "json_files=" .. tostring(json_count),
            "docs=" .. tostring(docs), "cmake_data_targets=" .. cmake_targets,
            "sanity=" .. sanity, "network_at_configure=OFF",
            "handmade_config=NO", "source_patch=NO", "",
        }, "\n"))
        gcpkg.log.info("simdjson-data: installed " .. json_count ..
                       " JSON files; CMake consumer " .. cmake_targets)
        return {
            includes = {}, libdirs = {}, libs = {}, binaries = {},
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = {}, libdirs = {}, libs = {}, binaries = {},
    },
}
