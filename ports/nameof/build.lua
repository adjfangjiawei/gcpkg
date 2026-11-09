-- nameof 0.11.0 -- gcpkg port definition.
-- Header-only compile-time name reflection for enums, variables and types.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "nameof",
    version = "0.11.0",
    license = "MIT",
    homepage = "https://github.com/Neargye/nameof",
    description = "Header-only C++17 compile-time name reflection",
    source = {
        url = "https://codeload.github.com/Neargye/nameof/tar.gz/refs/tags/v0.11.0",
        sha256 = "df6b6c30dfd7dd41995af4fc30d341b318d048465aceebbf861fc441fa6b051d",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/nameof.hpp", dst = "nameof.hpp" },
          },
        include = "nameof.hpp",
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
