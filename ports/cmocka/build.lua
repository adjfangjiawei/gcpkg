-- cmocka 1.1.7 -- gcpkg port definition.
-- cmocka C mocking framework; static library.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "cmocka",
    version = "1.1.7",
    license = "Apache-2.0",
    homepage = "https://cmocka.org",
    description = "C unit testing framework with mock support",
    source = {
        url = "https://cmocka.org/files/1.1/cmocka-1.1.7.tar.xz",
        sha256 = "810570eb0b8d64804331f82b29ff47c790ce9cd6b163e98d47a4807047ecad82",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          WITH_EXAMPLES = "OFF",
          UNIT_TESTING = "OFF",
          PICKY_DEVELOPER = "OFF",
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
        "cmocka",
      },
      binaries = {},
    },
}
