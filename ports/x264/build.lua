-- x264 snapshot-0480cb05 -- gcpkg port definition.
-- Static x264 snapshot for FFmpeg; CLI and external input libraries disabled.
-- License files are installed under share/doc/x264 by gcpkg.r20.
local r20 = require("gcpkg.r20")
local util = require("gcpkg.util")

return {
    name = "x264",
    version = "snapshot-0480cb05",
    license = "GPL-2.0-or-later",
    homepage = "https://www.videolan.org/developers/x264.html",
    description = "x264 static encoder pinned to latest upstream snapshot, source-built for FFmpeg",
    source = { url = "https://code.videolan.org/videolan/x264/-/archive/0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee/x264-0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee.tar.gz", sha256 = "d0967a1348c85dfde363bb52610403be898171493100561efa0dd05d5fd1ae50", strip = 1 },
    dependencies = {},
    build = function(ctx)
        local cflags, ldflags = r20.flags(ctx)
        local cfg = {
            util.join(ctx.src, "configure"),
            "--prefix=" .. ctx.prefix,
            "--libdir=" .. util.join(ctx.prefix, "lib"),
            "--includedir=" .. util.join(ctx.prefix, "include"),
            "--enable-static", "--disable-cli",
            "--disable-opencl", "--disable-avs", "--disable-swscale",
            "--disable-lavf", "--disable-ffms", "--disable-gpac",
            "--disable-lsmash", "--disable-bashcompletion", "--enable-pic",
            "--extra-cflags=" .. cflags, "--extra-ldflags=" .. ldflags,
        }
        ctx.exec(cfg, { cwd = ctx.src, log = ctx.log })
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "make", "-j" .. j, "CC=" .. ctx.compiler.wrapper_cc },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "CC=" .. ctx.compiler.wrapper_cc },
                 { cwd = ctx.src, log = ctx.log })
        r20.license(ctx, { "COPYING" })
        return {
            includes = { util.join(ctx.prefix, "include") },
            libdirs = { util.join(ctx.prefix, "lib") },
            libs = { "x264" },
            binaries = {},
            link_flags = { "-lpthread", "-lm", "-ldl" },
            compdb_files = {},
        }
    end,
}
