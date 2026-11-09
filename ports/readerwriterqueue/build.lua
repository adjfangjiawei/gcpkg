-- readerwriterqueue 1.0.6 -- ONE port, ONE build.lua + ONE features.yaml.
-- Header-only SPSC C++ queue; two real upstream test TUs are compiled for compdb.
-- Static checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- Upstream is never patched: all adaptation lives in this file.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")

return {
    name = "readerwriterqueue",
    version = "1.0.6",
    license = "BSD-2-Clause",
    homepage = "https://github.com/cameron314/readerwriterqueue",
    description = "Header-only single-producer single-consumer C++ queue",
    source = {
        url = "https://codeload.github.com/cameron314/readerwriterqueue/tar.gz/refs/tags/v1.0.6",
        sha256 = "fc68f55bbd49a8b646462695e1777fb8f2c0b4f342d5e6574135211312ba56c1",
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
        local common = util.join(ctx.src, "tests/common")
        compile("tests/unittests/unittests.cpp",
                { "-std=c++11", "-DNDEBUG", "-pthread", "-I", ctx.src, "-I", common }, true)
        compile("tests/common/simplethread.cpp",
                { "-std=c++11", "-DNDEBUG", "-pthread", "-I", ctx.src, "-I", common }, true)
        local dest = util.join(incdir, "readerwriterqueue")
        fs.mkdirs(dest)
        for _, name in ipairs({ "atomicops.h", "readerwriterqueue.h",
                                "readerwritercircularbuffer.h" }) do
            ctx.exec({ "cp", "-a", util.join(ctx.src, name), dest }, { log = ctx.log })
        end
        return {
            includes = { dest }, libdirs = { libdir },
            libs = {}, binaries = {},
        }
    end,
}
