-- zig 0.11.0 -- gcpkg tool port for the ZURI Zig library.
-- The official prebuilt Linux x86_64 tarball is unpacked into the store; no
-- host toolchain, no configure-time fetch and no library-side platform probe.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

local function build(ctx)
    local on = ctx.features.enabled
    local prefix = ctx.prefix
    local bindir = prefix .. "/bin"
    local docdir = prefix .. "/share/doc/zig"
    local objdir = ctx.build_dir .. "/obj"
    fs.mkdirs(prefix)
    fs.mkdirs(bindir)
    fs.mkdirs(objdir)

    if on["toolchain"] then
        -- Keep the upstream layout: the Zig executable resolves its std lib
        -- relative to its own directory.  A conventional bin/zig symlink is
        -- also exported for dependent builds.
        ctx.exec({ "cp", "-a", ctx.src .. "/.", prefix .. "/" },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "ln", "-sf", "../zig", bindir .. "/zig" },
                 { cwd = bindir, log = ctx.log })
    end
    if on["docs"] then
        fs.mkdirs(docdir)
        ctx.exec({ "cp", "-a", ctx.src .. "/doc/.", docdir .. "/" },
                 { cwd = ctx.src, log = ctx.log })
    end
    if on["license"] then
        fs.mkdirs(docdir)
        ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE", docdir .. "/LICENSE" },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "cp", "-a", ctx.src .. "/README.md", docdir .. "/README.md" },
                 { cwd = ctx.src, log = ctx.log })
    end

    if on["sanity"] then
        assert(on["toolchain"],
               "gcpkg: zig: sanity needs the toolchain feature")
        local zig = bindir .. "/zig"
        ctx.exec({ zig, "version" },
                 { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        local hello = ctx.build_dir .. "/hello.zig"
        fs.write(hello, [==[
const std = @import("std");
pub fn main() void {
    std.debug.print("gcpkg zig ok\n", .{});
}
]==])
        local out = objdir .. "/hello"
        local cmd = { zig, "build-exe", hello, "-femit-bin=" .. out }
        ctx.record({
            directory = ctx.build_dir, file = hello, arguments = cmd,
            output = out, tag = "zig",
        })
        ctx.exec(cmd, { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        ctx.exec({ out },
                 { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    end

    return {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { prefix, bindir },
        defines = {},
        link_flags = {},
        compdb_files = {},
    }
end

return recipe.define {
    name = "zig",
    version = "0.11.0",
    license = "MIT",
    homepage = "https://ziglang.org",
    description = "Zig 0.11.0 toolchain tool port for ZURI",
    source = {
        url = "https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz",
        sha256 = "2d00e789fec4f71790a6e7bf83ff91d564943c5ee843c5fd966efc474b423047",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { "@PREFIX@", "@PREFIX@/bin" },
    },
}
