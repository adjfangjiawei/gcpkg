-- sparsepp v0.95 -- gcpkg port definition.
-- Header-only sparse hash map derived from Google sparsehash.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "sparsepp",
    version = "v0.95",
    license = "BSD-3-Clause",
    homepage = "https://github.com/greg7mdp/sparsepp",
    description = "Fast header-only sparse hash map",
    source = {
        url = "https://codeload.github.com/greg7mdp/sparsepp/tar.gz/refs/tags/v0.95",
        sha256 = "cde419e440ec6aecc2fe2c4612d702ce243de16c3c616485d2f719e96315150d",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "sparsepp", dst = "sparsepp" },
          },
        include = "sparsepp/spp.h",
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
