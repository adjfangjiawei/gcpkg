-- url-dataset 9749b92 -- gcpkg data port.
-- Pinned WHATWG URL benchmark corpus used by ada's benchdata / model_bench.
-- Source-built from the upstream tarball; no network at configure time, no
-- system library discovery.  Exports the installed dataset directory so a
-- dependent can set ADA_URL_FILE without hardcoding a machine path.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.define {
    name = "url-dataset",
    version = "9749b92",
    license = "MIT OR Apache-2.0",
    homepage = "https://github.com/ada-url/url-dataset",
    description = "WHATWG URL benchmark corpus (out.txt)",
    source = {
        url = "https://codeload.github.com/ada-url/url-dataset/tar.gz/9749b92c13e970e70409948fa862461191504ccc",
        sha256 = "200b56fe786424886c116aa7895888f1af4906462097ab025370bba7baf93261",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local dir = ctx.prefix .. "/share/url-dataset"
        fs.mkdirs(dir)
        fs.mkdirs(ctx.build_dir)
        fs.mkdirs(ctx.build_dir .. "/obj")
        local enabled = ctx.features.enabled
        if enabled["data"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/out.txt", dir .. "/out.txt" },
                     { cwd = ctx.src, log = ctx.log })
            ctx.exec({ "cp", "-a", ctx.src .. "/README.md", dir .. "/README.md" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if enabled["license"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE-MIT", dir .. "/LICENSE-MIT" },
                     { cwd = ctx.src, log = ctx.log })
            ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE_APACHE", dir .. "/LICENSE_APACHE" },
                     { cwd = ctx.src, log = ctx.log })
        end
        -- One real compile command: a data port still gets a compdb entry,
        -- and the TU documents the installed corpus path at build time.
        local probe = ctx.build_dir .. "/gcpkg_url_dataset_probe.cpp"
        fs.write(probe,
            '// gcpkg url-dataset sanity TU; corpus: ' .. dir .. '/out.txt\n' ..
            '#include <string>\n' ..
            'int main() { const char* corpus = "' .. dir .. '/out.txt"; ' ..
            'return std::string(corpus).empty(); }\n')
        local cc = require("gcpkg.build.cc")
        cc.compile {
            sources = { probe }, includes = {}, flags = { "-std=c++17" },
            cwd = ctx.build_dir, outdir = ctx.build_dir .. "/obj",
            compiler = ctx.compiler.wrapper_cxx,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "url-dataset",
        }
        return {
            includes = {}, libdirs = {}, libs = {}, binaries = {},
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = {}, libdirs = {}, libs = {}, binaries = {},
    },
}
