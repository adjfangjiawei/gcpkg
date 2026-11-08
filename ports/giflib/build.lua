-- giflib 5.2.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- Hand-written Makefile; custom build(ctx) passes PREFIX and wrapper CC.
-- Upstream is never patched: all adaptation is in this file.

local fs = require("gcpkg.fs")

return {
    name = "giflib",
    version = "5.2.2",
    license = "MIT",
    homepage = "https://sourceforge.net/projects/giflib/",
    description = "GIF image encoding/decoding library",
    source = {
        url = "https://sourceforge.net/projects/giflib/files/giflib-5.2.2.tar.gz/download",
        sha256 = "be7ffbd057cadebe2aa144542fd90c6838c6a083b5e8a9048b8ee3b66b29d5fb",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        local cc = "CC=" .. ctx.env.CC
        ctx.exec({ "make", "-j" .. j, cc }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "PREFIX=" .. ctx.prefix, cc },
                 { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs  = { ctx.prefix .. "/lib" },
            libs     = {
            "gif",
          },
            binaries = {},
        }
    end,

}
