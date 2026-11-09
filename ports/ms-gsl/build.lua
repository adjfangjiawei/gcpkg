-- ms-gsl 4.2.0 -- gcpkg port definition.
-- Microsoft Guidelines Support Library; extensionless headers under include/gsl.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "ms-gsl",
    version = "4.2.0",
    license = "MIT",
    homepage = "https://github.com/microsoft/GSL",
    description = "Microsoft C++ Core Guidelines Support Library",
    source = {
        url = "https://codeload.github.com/microsoft/GSL/tar.gz/refs/tags/v4.2.0",
        sha256 = "2c717545a073649126cb99ebd493fa2ae23120077968795d2c69cbab821e4ac6",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          GSL_TEST = "OFF",
          GSL_INSTALL = "ON",
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
      libs = {},
      binaries = {},
    },
}
