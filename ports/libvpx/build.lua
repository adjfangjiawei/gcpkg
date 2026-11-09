-- libvpx 1.15.0 -- gcpkg port definition.
-- VP8/VP9 codec: SIMD configure using the nasm tool port on PATH.

local fs = require("gcpkg.fs")

return {
    name = "libvpx",
    version = "1.15.0",
    license = "BSD-3-Clause",
    homepage = "https://www.webmproject.org",
    description = "VP8/VP9 video codec (SIMD via the nasm tool port)",
    source = {
        url = "https://codeload.github.com/webmproject/libvpx/tar.gz/refs/tags/v1.15.0",
        sha256 = "e935eded7d81631a538bfae703fd1e293aad1c7fd3407ba00440c95105d2011e",
        strip = 1,
    },
    dependencies = {
        "nasm",
      },
    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "./configure", "--prefix=" .. ctx.prefix,
                   -- The nasm TOOL PORT is on PATH via exports.binaries;
                   -- x86_64-linux-gcc + --as=nasm enables the SIMD paths.
                   "--target=x86_64-linux-gcc", "--as=nasm",
                   "--disable-examples", "--disable-tools", "--disable-docs",
                   "--disable-unit-tests", "--enable-static", "--disable-shared" },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "-j" .. j }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install" }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs  = { ctx.prefix .. "/lib" },
            libs     = {
            "vpx",
          },
            binaries = {},
        }
    end,

}
