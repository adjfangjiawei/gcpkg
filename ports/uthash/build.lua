-- uthash 2.3.0 -- gcpkg port definition.
-- Header-only C containers; one real upstream test TU is compiled for compdb.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")

return {
    name = "uthash",
    version = "2.3.0",
    license = "BSD-1-Clause",
    homepage = "https://github.com/troydhanson/uthash",
    description = "Header-only hash table and intrusive containers for C",
    source = {
        url = "https://codeload.github.com/troydhanson/uthash/tar.gz/refs/tags/v2.3.0",
        sha256 = "e10382ab75518bad8319eb922ad04f907cb20cccb451a3aa980c9d005e661acc",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        fs.mkdirs(incdir)
        fs.mkdirs(libdir)
        local function compile(src, args, cxx)
            local obj = util.join(ctx.build_dir, util.basename(src):gsub("%.", "_") .. ".o")
            local cmd = { cxx and ctx.compiler.wrapper_cxx or ctx.compiler.wrapper_cc,
                          "-c", "-O2" }
            for _, a in ipairs(args) do cmd[#cmd + 1] = a end
            cmd[#cmd + 1] = util.join(ctx.src, src)
            cmd[#cmd + 1] = "-o"
            cmd[#cmd + 1] = obj
            ctx.record({ directory = ctx.src, file = util.join(ctx.src, src),
                         arguments = cmd, output = obj, tag = ctx.key })
            ctx.exec(cmd, { cwd = ctx.src, log = ctx.log })
            return obj
        end
        local headers = util.join(ctx.src, "src")
        compile("tests/test1.c", { "-I", headers }, false)
        for _, name in ipairs(fs.listdir(headers) or {}) do
            if util.ext(name) == "h" then
                ctx.exec({ "cp", "-a", util.join(headers, name), incdir }, { log = ctx.log })
            end
        end
        return {
            includes = { incdir }, libdirs = { libdir },
            libs = {}, binaries = {},
        }
    end,
}
