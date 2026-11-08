-- libexif 0.6.24 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- EXIF tag parser; GitHub tag ships only configure.ac.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libexif",
    version = "0.6.24",
    license = "LGPL-2.1",
    homepage = "https://github.com/libexif/libexif",
    description = "EXIF tag parsing library",
    source = {
        url = "https://codeload.github.com/libexif/libexif/tar.gz/refs/tags/libexif-0_6_24-release",
        sha256 = "d3fb7c47829ec4d2def39aa38f4c35a0891763448a05dbf216a329a12bf198f9",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-nls",
          "--disable-docs",
        },
    },
    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
        end
    end,
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "exif",
      },
      binaries = {},
    },
}
