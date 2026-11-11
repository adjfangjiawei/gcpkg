-- ddt 9c93e80 -- gcpkg header-only source port.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local cc = require("gcpkg.build.cc")

return recipe.define {
    name = "ddt",
    version = "9c93e80",
    license = "BSD-2-Clause",
    homepage = "https://github.com/rmisev/ddt",
    description = "DataDrivenTest header-only C++ test helper (pinned 9c93e80)",
    source = {
        url = "https://codeload.github.com/rmisev/ddt/tar.gz/9c93e8025c4cb33774bbc2c0b9d14af046c98472",
        sha256 = "a15ed5e74a6688b8cf09f13ac6ce3549a84b269223841a7a3ff96be715f7bae4",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include/ddt"
        local docdir = ctx.prefix .. "/share/doc/ddt"
        fs.mkdirs(incdir)
        fs.mkdirs(docdir)
        fs.mkdirs(ctx.build_dir .. "/obj")
        if on["headers"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/DataDrivenTest.hpp",
                       incdir .. "/DataDrivenTest.hpp" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["license"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE",
                       docdir .. "/LICENSE" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["sanity"] then
            local probe = ctx.build_dir .. "/gcpkg_ddt_probe.cpp"
            fs.write(probe, [[
#include <ddt/DataDrivenTest.hpp>
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
                tag = "ddt",
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
