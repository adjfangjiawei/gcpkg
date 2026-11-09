-- glm 1.0.1 -- gcpkg port definition.
-- OpenGL Mathematics; whole glm/ header tree installed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "glm",
    version = "1.0.1",
    license = "MIT",
    homepage = "https://github.com/g-truc/glm",
    description = "OpenGL Mathematics header-only C++ library",
    source = {
        url = "https://codeload.github.com/g-truc/glm/tar.gz/refs/tags/1.0.1",
        sha256 = "9f3174561fd26904b23f0db5e560971cbf9b3cbda0b280f04d5c379d03bf234c",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "glm", dst = "glm" },
          },
        include = "glm/glm.hpp",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "copying.txt",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
