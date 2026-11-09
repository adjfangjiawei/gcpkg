-- toml11 4.2.0 -- gcpkg port definition.
-- Header-only C++ TOML library.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "toml11",
    version = "4.2.0",
    license = "MIT",
    homepage = "https://github.com/ToruNiina/toml11",
    description = "Header-only C++ TOML parser/serializer",
    source = {
        url = "https://codeload.github.com/ToruNiina/toml11/tar.gz/refs/tags/v4.2.0",
        sha256 = "9287971cd4a1a3992ef37e7b95a3972d1ae56410e7f8e3f300727ab1d6c79c2c",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          TOML11_BUILD_TESTS = "OFF",
          TOML11_BUILD_TOML_TESTS = "OFF",
          TOML11_BUILD_EXAMPLES = "OFF",
          TOML11_INSTALL = "ON",
          TOML11_PRECOMPILE = "OFF",
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
      libs = {},
      binaries = {},
    },
}
