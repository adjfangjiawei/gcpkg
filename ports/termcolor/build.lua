-- termcolor 2.1.0 -- gcpkg port definition.
-- Header-only terminal colors; cstdint prelude fixes upstream uint8_t.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "termcolor",
    version = "2.1.0",
    license = "MIT",
    homepage = "https://github.com/ikalnytskyi/termcolor",
    description = "Header-only terminal color and text style formatting",
    source = {
        url = "https://codeload.github.com/ikalnytskyi/termcolor/tar.gz/refs/tags/v2.1.0",
        sha256 = "435994c32557674469404cb1527c283fdcf45746f7df75fd2996bb200d6a759f",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/termcolor", dst = "termcolor" },
          },
        include = "termcolor/termcolor.hpp",
        prelude = {
            "cstdint",
          },
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
