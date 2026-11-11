-- picojson 111c9be -- gcpkg header-only source port.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local cc = require("gcpkg.build.cc")

return recipe.define {
    name = "picojson",
    version = "111c9be",
    license = "BSD-2-Clause",
    homepage = "https://github.com/kazuho/picojson",
    description = "PicoJSON header-only C++ JSON parser (pinned 111c9be)",
    source = {
        url = "https://codeload.github.com/kazuho/picojson/tar.gz/111c9be5188f7350c2eac9ddaedd8cca3d7bf394",
        sha256 = "671f89832a17e9e71398f80c0a326afa2ebe81f4c26d5a9992e1fcd0888ae151",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include/picojson"
        local docdir = ctx.prefix .. "/share/doc/picojson"
        fs.mkdirs(incdir)
        fs.mkdirs(docdir)
        fs.mkdirs(ctx.build_dir .. "/obj")
        if on["headers"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/picojson.h",
                       incdir .. "/picojson.h" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["license"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE",
                       docdir .. "/LICENSE" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["sanity"] then
            local probe = ctx.build_dir .. "/gcpkg_picojson_probe.cpp"
            fs.write(probe, [[
#include <picojson/picojson.h>
#include <string>
int main() {
  const std::string s = "{\"ok\":true}";
  picojson::value v;
  std::string err;
  picojson::parse(v, s.begin(), s.end(), &err);
  return err.empty() && v.is<picojson::object>() ? 0 : 1;
}
]])
            cc.compile {
                sources = { probe },
                includes = { ctx.prefix .. "/include" },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = ctx.build_dir .. "/obj",
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "picojson",
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
