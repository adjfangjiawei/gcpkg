-- utfcpp v4.0.6 -- gcpkg port definition.
-- UTF-8 with C++; source/ becomes the installed include/.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "utfcpp",
    version = "v4.0.6",
    license = "BSL-1.0",
    homepage = "https://github.com/nemtrif/utfcpp",
    description = "UTF-8 with C++ header-only library",
    source = {
        url = "https://codeload.github.com/nemtrif/utfcpp/tar.gz/refs/tags/v4.0.6",
        sha256 = "6920a6a5d6a04b9a89b2a89af7132f8acefd46e0c2a7b190350539e9213816c0",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "source/utf8.h", dst = "utf8.h" },
            { src = "source/utf8", dst = "utf8" },
          },
        include = "utf8.h",
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
