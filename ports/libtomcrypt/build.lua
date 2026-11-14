-- libtomcrypt 1.18.2 -- gcpkg port definition.
-- Hand-written lowercase makefile; `ltm` feature pulls libtommath.

local recipe = require("gcpkg.recipe")

return recipe.make {
    name = "libtomcrypt",
    version = "1.18.2",
    license = "Unlicense",
    homepage = "https://github.com/libtom/libtomcrypt",
    description = "Modular cryptographic library",
    source = {
        url = "https://codeload.github.com/libtom/libtomcrypt/tar.gz/refs/tags/v1.18.2",
        sha256 = "d870fad1e31cb787c85161a8894abb9d7283c2a654a9d3d4c6d45a1eba59952c",
        strip = 1,
    },
    dependencies = {},
    make = {
        vars = function(ctx) return { PREFIX = ctx.prefix } end,
        targets = {
          "libtomcrypt.a",
        },
        install_target = "install",
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "tomcrypt",
      },
      binaries = {},
    },
}
