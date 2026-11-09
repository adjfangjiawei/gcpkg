-- pfr 1.92.0 -- gcpkg port definition.
-- Boost.PFR standalone reflection headers installed under boost/pfr.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "pfr",
    version = "1.92.0",
    license = "BSL-1.0",
    homepage = "https://github.com/boostorg/pfr",
    description = "Boost.PFR header-only reflection without macro registration",
    source = {
        url = "https://codeload.github.com/boostorg/pfr/tar.gz/refs/tags/boost-1.92.0",
        sha256 = "8209971b8a799dfb367ddb16f32343715c11579859dbc635c249aa8aeab7b66a",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/boost/pfr.hpp", dst = "boost/pfr.hpp" },
            { src = "include/boost/pfr", dst = "boost/pfr" },
          },
        include = "boost/pfr.hpp",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE_1_0.txt",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
