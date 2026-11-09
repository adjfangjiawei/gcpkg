-- libogg 1.3.5 -- gcpkg port definition.
-- Ogg container; bottom of the audio chain.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libogg",
    version = "1.3.5",
    license = "BSD-3-Clause",
    homepage = "https://xiph.org/ogg/",
    description = "Ogg bitstream container library",
    source = {
        url = "https://codeload.github.com/xiph/ogg/tar.gz/refs/tags/v1.3.5",
        sha256 = "f6f1b04cfa4e98b70ffe775d5e302d9c6b98541f05159af6de2d6617817ed7d6",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          INSTALL_DOCS = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "ogg",
      },
      binaries = {},
    },
}
