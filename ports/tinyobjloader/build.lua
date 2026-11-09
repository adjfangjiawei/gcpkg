-- tinyobjloader v2.0.0rc13 -- gcpkg port definition.
-- Wavefront OBJ loader plus its bundled earcut dependency.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "tinyobjloader",
    version = "v2.0.0rc13",
    license = "MIT",
    homepage = "https://github.com/tinyobjloader/tinyobjloader",
    description = "Header-only Wavefront OBJ loader",
    source = {
        url = "https://codeload.github.com/tinyobjloader/tinyobjloader/tar.gz/refs/tags/v2.0.0rc13",
        sha256 = "0feb92b838f8ce4aa6eb0ccc32dff30cb64a891e0ec3bde837fca49c78d44334",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "tiny_obj_loader.h", dst = "tiny_obj_loader.h" },
            { src = "mapbox/earcut.hpp", dst = "mapbox/earcut.hpp" },
          },
        include = "tiny_obj_loader.h",
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
