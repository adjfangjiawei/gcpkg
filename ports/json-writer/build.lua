-- json-writer 6fa1122 -- gcpkg header-only source port.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local cc = require("gcpkg.build.cc")

return recipe.define {
    name = "json-writer",
    version = "6fa1122",
    license = "BSD-2-Clause",
    homepage = "https://github.com/rmisev/json_writer",
    description = "json_writer header-only C++ helper (pinned 6fa1122)",
    source = {
        url = "https://codeload.github.com/rmisev/json_writer/tar.gz/6fa11221d22bfd46b3a8ce143452d4918e5706e3",
        sha256 = "76bebf99bc7878c0968e1b2d4f76cb42e55c5d1db3b35dc6bb0ea4948c40cdab",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include/json_writer"
        local docdir = ctx.prefix .. "/share/doc/json-writer"
        fs.mkdirs(incdir)
        fs.mkdirs(docdir)
        fs.mkdirs(ctx.build_dir .. "/obj")
        if on["headers"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/json_writer.h",
                       incdir .. "/json_writer.h" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["license"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE",
                       docdir .. "/LICENSE" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["sanity"] then
            local probe = ctx.build_dir .. "/gcpkg_json_writer_probe.cpp"
            fs.write(probe, [[
#include <json_writer/json_writer.h>
int main() { return 0; }
]])
            cc.compile {
                sources = { probe },
                includes = { ctx.prefix .. "/include" },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = ctx.build_dir .. "/obj",
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "json-writer",
            }
        end
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = {}, libs = {}, binaries = {},
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {}, libs = {}, binaries = {},
    },
}
