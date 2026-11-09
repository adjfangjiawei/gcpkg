-- inja 3.5.0 -- gcpkg port definition.
-- Amalgamated Jinja-style template engine; depends on nlohmann-json.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "inja",
    version = "3.5.0",
    license = "MIT",
    homepage = "https://github.com/pantor/inja",
    description = "Header-only C++ Jinja-style template engine",
    source = {
        url = "https://codeload.github.com/pantor/inja/tar.gz/refs/tags/v3.5.0",
        sha256 = "a5f0266673c59028eab6ceeddd8b862c70abfeb32fb7a5387c16bf46f3269ab2",
        strip = 1,
    },
    dependencies = {
        "nlohmann-json",
      },
    header = {
        headers = {
            { src = "single_include/inja/inja.hpp", dst = "inja/inja.hpp" },
          },
        include = "inja/inja.hpp",
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
