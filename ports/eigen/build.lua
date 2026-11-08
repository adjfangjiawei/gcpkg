-- eigen 3.4.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static checks in tests/r11.sh; GCPKG_R11_DYNAMIC=1 builds it for real.
-- Header-only linear algebra; headers land in include/eigen3.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "eigen",
    version = "3.4.0",
    license = "MPL-2.0",
    homepage = "https://eigen.tuxfamily.org",
    description = "Header-only C++ linear algebra template library",
    source = {
        url = "https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz",
        sha256 = "8586084f71f9bde545ee7fa6d00288b264a2b7ac3607b974e54d13e7162c1c72",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          EIGEN_BUILD_TESTING = "OFF",
          EIGEN_BUILD_DOC = "OFF",
          EIGEN_BUILD_PKGCONFIG = "ON",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include/eigen3",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {},
      binaries = {},
    },
}
