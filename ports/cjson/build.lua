-- cjson 1.7.18 -- gcpkg port definition.
-- Ultralightweight C JSON parser; tests disabled.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cjson",
    version = "1.7.18",
    license = "MIT",
    homepage = "https://github.com/DaveGamble/cJSON",
    description = "Ultralightweight JSON parser in C",
    source = {
        url = "https://codeload.github.com/DaveGamble/cJSON/tar.gz/refs/tags/v1.7.18",
        sha256 = "3aa806844a03442c00769b83e99970be70fbef03735ff898f4811dd03b9f5ee5",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          ENABLE_CJSON_TEST = "OFF",
          ENABLE_CJSON_UTILS = "ON",
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
        "cjson",
      },
      binaries = {},
    },
}
