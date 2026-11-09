-- cgltf v1.15 -- gcpkg port definition.
-- Single-file glTF 2.0 loader and writer.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "cgltf",
    version = "v1.15",
    license = "MIT",
    homepage = "https://github.com/jkuhlmann/cgltf",
    description = "Single-file glTF 2.0 loader and writer",
    source = {
        url = "https://codeload.github.com/jkuhlmann/cgltf/tar.gz/refs/tags/v1.15",
        sha256 = "84e352092e5cd6aab7f66de62ddb66beb5e6f18d412ca9d12950d7a55bfef25a",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "cgltf.h", dst = "cgltf.h" },
            { src = "cgltf_write.h", dst = "cgltf_write.h" },
          },
        include = "cgltf.h",
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
