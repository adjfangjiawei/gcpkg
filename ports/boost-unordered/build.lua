-- boost-unordered 1.81.0 -- gcpkg header-only source port.
-- The headers come from the same pinned Boost 1.81.0 source tarball as the
-- B2-built `boost` port.  No hand-written CONFIG, no host Boost discovery.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local r20 = require("gcpkg.r20")

local VERSION = "1.81.0"
local CACHE_NAME = "boost-unordered-1.81.0-boost_1_81_0.tar.gz"
local SOURCE_SHA = "205666dea9f6a7cfed87c7a6dfbeb52a2c1b9de55712c9c1a87735d7181452b6"

local PROBE = [==[
#include <boost/unordered_map.hpp>
#include <boost/unordered_set.hpp>
#include <boost/unordered/unordered_flat_map.hpp>
#include <iostream>
int main() {
  boost::unordered_map<int, int> m; m[1] = 2;
  boost::unordered_set<int> s; s.insert(3);
  boost::unordered_flat_map<int, int> fm; fm[4] = 5;
  bool ok = m.at(1) == 2 && s.count(3) == 1 && fm.at(4) == 5;
  std::cout << "gcpkg boost-unordered header-only sanity ok=" << (ok ? 1 : 0) << "\n";
  return ok ? 0 : 1;
}
]==]

local function build(ctx)
    local on = ctx.features.enabled
    for _, k in ipairs({ "headers", "sanity", "license" }) do
        assert(on[k], "gcpkg: boost-unordered: mandatory capability OFF: " .. k)
    end
    r20.restrict_pkgconfig(ctx)
    local boost = assert(r20.dep_prefix(ctx, "boost"),
                         "gcpkg: boost-unordered: missing boost dependency")
    local boost_inc = util.join(boost, "include")
    local incdir = util.join(ctx.prefix, "include")
    local boostdir = util.join(incdir, "boost")
    local docdir = util.join(ctx.prefix, "share", "doc", "boost-unordered")
    local vdir = util.join(ctx.build_dir, "verify")
    local home = util.join(ctx.build_dir, "home")
    local tmp = util.join(ctx.build_dir, "tmp")
    fs.mkdirs(incdir); fs.mkdirs(boostdir); fs.mkdirs(docdir); fs.mkdirs(vdir)
    fs.mkdirs(home); fs.mkdirs(tmp)
    local old_path = tostring(ctx.env.PATH or "")
    local path_parts = { ctx.store.bin, "/usr/lib/llvm-23/bin", "/usr/bin", "/bin" }
    if old_path ~= "" then path_parts[#path_parts + 1] = old_path end
    ctx.env.PATH = table.concat(path_parts, ":")
    ctx.env.HOME = home
    ctx.env.TMPDIR = tmp
    ctx.env.GCPKG_COMPILER_FLAGS = ""
    assert(fs.isfile(util.join(ctx.store.cache, CACHE_NAME)),
           "gcpkg: boost-unordered: source cache missing: " .. CACHE_NAME)

    ctx.exec({ "cp", "-a", util.join(ctx.src, "boost", "unordered"), boostdir .. "/" },
             { cwd = ctx.src, log = ctx.log })
    for _, name in ipairs({ "unordered_map.hpp", "unordered_set.hpp" }) do
        ctx.exec({ "cp", "-a", util.join(ctx.src, "boost", name), boostdir .. "/" },
                 { cwd = ctx.src, log = ctx.log })
    end
    ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE_1_0.txt"),
               util.join(docdir, "LICENSE_1_0.txt") },
             { cwd = ctx.src, log = ctx.log })

    assert(fs.isfile(util.join(incdir, "boost", "unordered_map.hpp")),
           "gcpkg: boost-unordered: unordered_map.hpp not installed")
    assert(fs.isfile(util.join(incdir, "boost", "unordered", "unordered_flat_map.hpp")),
           "gcpkg: boost-unordered: flat map header not installed")

    local probe = util.join(vdir, "boost_unordered_probe.cpp")
    fs.write(probe, PROBE)
    local bin = cc.executable {
        sources = { probe },
        includes = { incdir, boost_inc },
        flags = { "-std=c++17" },
        defines = { "BOOST_ALL_NO_LIB=1" },
        cwd = vdir, outdir = util.join(vdir, "obj"),
        compiler = ctx.compiler.wrapper_cxx,
        exec = ctx.exec, record = ctx.record, log = ctx.log,
        tag = "boost-unordered", cxx = true,
        output = util.join(vdir, "boost_unordered_probe"),
    }
    local out, rc = ctx.capture({ bin }, { cwd = vdir, env = ctx.env })
    assert(rc == 0, "gcpkg: boost-unordered: consumer TU failed")
    assert(out:find("gcpkg boost-unordered header-only sanity ok=1", 1, true),
           "gcpkg: boost-unordered: consumer output mismatch")

    fs.write(util.join(vdir, "boost-unordered-facts.txt"), table.concat({
        "policy=source_built_header_only_no_local_config",
        "boost_version=" .. VERSION,
        "source_cache=" .. CACHE_NAME,
        "source_sha=" .. SOURCE_SHA,
        "consumer_rc=" .. rc,
        "source_patch=NO", "network_at_build=NO", "host_boost=NO",
        "",
    }, "\n"))

    return {
        includes = { incdir }, libdirs = {}, libs = {},
        defines = { "BOOST_ALL_NO_LIB=1" },
        link_flags = {}, binaries = {}, compdb_files = {},
    }
end

return recipe.define {
    name = "boost-unordered",
    version = VERSION,
    license = "BSL-1.0",
    homepage = "https://www.boost.org",
    description = "Boost.Unordered 1.81.0 header-only source port with real C++ consumer",
    source = {
        url = "https://archives.boost.io/release/1.81.0/source/boost_1_81_0.tar.gz",
        sha256 = SOURCE_SHA,
        strip = 1,
    },
    dependencies = {},
    build = build,
}
