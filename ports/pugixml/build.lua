-- pugixml 1.14 -- gcpkg port definition.
-- C++ XML DOM; static build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "pugixml",
    version = "1.14",
    license = "MIT",
    homepage = "https://pugixml.org",
    description = "Light-weight C++ XML processing library",
    source = {
        url = "https://codeload.github.com/zeux/pugixml/tar.gz/refs/tags/v1.14",
        sha256 = "610f98375424b5614754a6f34a491adbddaaec074e9044577d965160ec103d2e",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
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
        "pugixml",
      },
      binaries = {},
    },
}
