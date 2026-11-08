-- lmdb 0.9.31 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- LMDB: Makefile lives in libraries/liblmdb; custom build(ctx) uses that cwd.
-- Upstream is never patched: all adaptation is in this file.

local fs = require("gcpkg.fs")

return {
    name = "lmdb",
    version = "0.9.31",
    license = "OLDAP-2.8",
    homepage = "https://github.com/LMDB/lmdb",
    description = "Memory-mapped transactional key/value store",
    source = {
        url = "https://codeload.github.com/LMDB/lmdb/tar.gz/refs/tags/LMDB_0.9.31",
        sha256 = "dd70a8c67807b3b8532b3e987b0a4e998962ecc28643e1af5ec77696b081c9b0",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local util = require("gcpkg.util")
        local d = util.join(ctx.src, "libraries", "liblmdb")
        local j = tostring(ctx.jobs or 4)
        local cc = "CC=" .. ctx.env.CC
        ctx.exec({ "make", "-j" .. j, cc }, { cwd = d, log = ctx.log })
        ctx.exec({ "make", "install", "prefix=" .. ctx.prefix, cc },
                 { cwd = d, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs  = { ctx.prefix .. "/lib" },
            libs     = {
            "lmdb",
          },
            binaries = {},
        }
    end,

}
