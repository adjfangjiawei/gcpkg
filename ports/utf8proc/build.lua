-- utf8proc 2.12.0 -- gcpkg port definition.
-- Unicode normalization; CMake build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "utf8proc",
    version = "2.12.0",
    license = "MIT",
    homepage = "https://github.com/JuliaStrings/utf8proc",
    description = "Unicode normalization / UTF-8 C library",
    source = {
        url = "https://codeload.github.com/JuliaStrings/utf8proc/tar.gz/refs/tags/v2.12.0",
        sha256 = "f564011d38b2888d583d510b08e69ffa15aa117155db1b9b49ef1dfe1fa25111",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          UTF8PROC_ENABLE_TESTING = "OFF",
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
        "utf8proc",
      },
      binaries = {},
    },
}
