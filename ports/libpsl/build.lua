-- libpsl 0.21.0 -- gcpkg port definition.
-- GitHub tag archives ship configure.ac only; pre_build regenerates ./configure when needed. Needs libidn2/libunistring headers from the host.


local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libpsl",
    version = "0.21.0",
    description = "Public Suffix List C library",
    license = "BSD-3-Clause",
    homepage = "https://github.com/rockdaboot/libpsl",
    source = {
        url = "https://codeload.github.com/rockdaboot/libpsl/tar.gz/refs/tags/libpsl-0.21.0",
        sha256 = "055aa87ec166c7afb985d0816c07ff440e1eb899881a318c51c69a0aeea8e279",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {},
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
        "psl",
      },
      binaries = {},
    },
}
