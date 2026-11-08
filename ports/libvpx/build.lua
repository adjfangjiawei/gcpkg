-- libvpx 1.15.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- VP8/VP9 codec: custom ./configure with the pure-C generic-gnu target.
-- Upstream is never patched: all adaptation is in this file.

local fs = require("gcpkg.fs")

return {
    name = "libvpx",
    version = "1.15.0",
    license = "BSD-3-Clause",
    homepage = "https://www.webmproject.org",
    description = "VP8/VP9 video codec",
    source = {
        url = "https://codeload.github.com/webmproject/libvpx/tar.gz/refs/tags/v1.15.0",
        sha256 = "e935eded7d81631a538bfae703fd1e293aad1c7fd3407ba00440c95105d2011e",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "./configure", "--prefix=" .. ctx.prefix,
                   -- generic-gnu is a pure-C target: no yasm/nasm required.
                   "--target=generic-gnu",
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
