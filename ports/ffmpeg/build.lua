-- ffmpeg 9.0.2 -- gcpkg port definition.
-- Full internal codec set plus source-built x264/x265/LAME/libass; no autodetected system libs.
-- License files are installed under share/doc/ffmpeg by gcpkg.r20.
local r20 = require("gcpkg.r20")
local util = require("gcpkg.util")

return {
    name = "ffmpeg",
    version = "9.0.2",
    license = "LGPL-2.1-or-later/GPL-2.0-or-later",
    homepage = "https://ffmpeg.org/",
    description = "FFmpeg static libraries with source-port x264/x265/LAME/libass codecs",
    source = { url = "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/n9.0.2", sha256 = "6e374ed621e48faa40639307dff48ba6fe574a509977956d2cce9669b7cc27e9", strip = 1 },
    dependencies = { "x264", "x265", "lame", "libass", "zlib" },
    build = function(ctx)
        r20.restrict_pkgconfig(ctx)
        local cflags, ldflags = r20.flags(ctx)
        local cfg = {
            util.join(ctx.src, "configure"),
            "--cc=" .. ctx.compiler.wrapper_cc,
            "--cxx=" .. ctx.compiler.wrapper_cxx,
            "--pkg-config=" .. ctx.env.PKG_CONFIG,
            "--prefix=" .. ctx.prefix,
            "--libdir=" .. util.join(ctx.prefix, "lib"),
            "--incdir=" .. util.join(ctx.prefix, "include"),
            "--pkgconfigdir=" .. util.join(ctx.prefix, "lib", "pkgconfig"),
            "--disable-autodetect", "--disable-programs", "--disable-doc",
            "--disable-network", "--enable-static", "--disable-shared",
            "--enable-pic", "--enable-gpl",
            "--enable-libx264", "--enable-libx265", "--enable-libmp3lame",
            "--enable-libass", "--enable-zlib",
            "--disable-alsa", "--disable-iconv", "--disable-sdl2",
            "--disable-xlib", "--disable-libdrm", "--disable-vaapi",
            "--disable-vdpau", "--disable-vulkan",
            "--pkg-config-flags=--static",
            "--extra-cflags=" .. cflags,
            "--extra-ldflags=" .. ldflags,
        }
        -- No configure cache. The configuration stage must be fast because the
        -- generated command line itself is small and correctly scoped.
        ctx.exec(cfg, { cwd = ctx.src, log = ctx.log })
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "make", "-j" .. j, "CC=" .. ctx.compiler.wrapper_cc,
                   "CXX=" .. ctx.compiler.wrapper_cxx },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "CC=" .. ctx.compiler.wrapper_cc,
                   "CXX=" .. ctx.compiler.wrapper_cxx },
                 { cwd = ctx.src, log = ctx.log })
        r20.license(ctx, { "LICENSE.md", "COPYING.GPLv2", "COPYING.GPLv3",
                           "COPYING.LGPLv2.1", "COPYING.LGPLv3" })
        return {
            includes = { util.join(ctx.prefix, "include") },
            libdirs = { util.join(ctx.prefix, "lib") },
            libs = { "avcodec", "avformat", "avutil", "swscale", "swresample" },
            binaries = {},
            link_flags = { "-lx264", "-lx265", "-lmp3lame", "-lass", "-lz",
                           "-lpthread", "-lm", "-ldl", "-lstdc++" },
            compdb_files = {},
        }
    end,
}
