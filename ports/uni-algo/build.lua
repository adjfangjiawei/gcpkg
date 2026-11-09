-- uni-algo v1.2.0 -- gcpkg port definition.
-- Unicode algorithms used in header-only mode; upstream CMake is not needed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "uni-algo",
    version = "v1.2.0",
    license = "Public-Domain",
    homepage = "https://github.com/uni-algo/uni-algo",
    description = "Header-only Unicode algorithms library",
    source = {
        url = "https://codeload.github.com/uni-algo/uni-algo/tar.gz/refs/tags/v1.2.0",
        sha256 = "f2a1539cd8635bc6088d05144a73ecfe7b4d74ee0361fabed6f87f9f19e74ca9",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/uni_algo", dst = "uni_algo" },
          },
        include = "uni_algo/all.h",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE.md",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
