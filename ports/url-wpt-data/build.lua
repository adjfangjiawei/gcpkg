-- url-wpt-data 373be7b -- gcpkg data-only source port.
-- Pinned web-platform-tests URL resources used by url-whatwg's WPT tests.
-- The full upstream commit archive is fetched by gcpkg's normal source
-- pipeline (or its SHA-verified cache); this build only installs the five
-- deterministic JSON resources required by upstream wpt-url.  All writes stay
-- inside the store and no test is disabled.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local cc = require("gcpkg.build.cc")

local FILES = {
    "setters_tests.json",
    "toascii.json",
    "urltestdata.json",
    "percent-encoding.json",
    "IdnaTestV2.json",
}

return recipe.define {
    name = "url-wpt-data",
    version = "373be7b",
    license = "BSD-3-Clause",
    homepage = "https://github.com/web-platform-tests/wpt",
    description = "Pinned WPT URL resources for the url-whatwg test suite",
    source = {
        url = "https://codeload.github.com/web-platform-tests/wpt/tar.gz/373be7b4252952bc90d515be07b2dbd9ff60540a",
        sha256 = "42b4b7a3a10cc17b294b3e9a16e4ba299080493d2e6cce5ae8694cfed42562d3",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local datadir = ctx.prefix .. "/share/url-wpt-data/wpt"
        local docdir = ctx.prefix .. "/share/doc/url-wpt-data"
        fs.mkdirs(datadir)
        fs.mkdirs(docdir)
        fs.mkdirs(ctx.build_dir .. "/obj")

        if on["data"] then
            for _, name in ipairs(FILES) do
                ctx.exec({ "cp", "-a", ctx.src .. "/url/resources/" .. name,
                           datadir .. "/" .. name },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
        if on["license"] then
            ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE.md",
                       docdir .. "/LICENSE.md" },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["sanity"] then
            local probe = ctx.build_dir .. "/gcpkg_url_wpt_data_probe.cpp"
            local lines = {
                "// gcpkg url-wpt-data sanity TU\n",
                "#include <fstream>\n",
                "#include <string>\n",
                "int main() {\n",
                "  const char* files[] = {\n",
            }
            for _, name in ipairs(FILES) do
                lines[#lines + 1] = '    "' .. datadir .. "/" .. name .. '",\n'
            end
            lines[#lines + 1] = "  };\n"
            lines[#lines + 1] = "  for (const char* path : files) {\n"
            lines[#lines + 1] = "    std::ifstream in(path);\n"
            lines[#lines + 1] = "    if (!in.good()) return 1;\n"
            lines[#lines + 1] = "  }\n"
            lines[#lines + 1] = "  return std::string(files[0]).empty();\n"
            lines[#lines + 1] = "}\n"
            fs.write(probe, table.concat(lines))
            cc.compile {
                sources = { probe },
                includes = {},
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = ctx.build_dir .. "/obj",
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec,
                record = ctx.record,
                log = ctx.log,
                tag = "url-wpt-data",
            }
        end
        return {
            includes = {}, libdirs = {}, libs = {}, binaries = {},
            defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = {}, libdirs = {}, libs = {}, binaries = {},
    },
}
