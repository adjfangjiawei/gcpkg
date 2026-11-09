-- re2 2024-07-02 -- gcpkg port definition.
-- RE2 regex engine on the external abseil port (find_package(absl)).

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "re2",
    version = "2024-07-02",
    license = "BSD-3-Clause",
    homepage = "https://github.com/google/re2",
    description = "Fast regular-expression engine on abseil",
    source = {
        url = "https://codeload.github.com/google/re2/tar.gz/refs/tags/2024-07-02",
        sha256 = "eb2df807c781601c14a260a507a5bb4509be1ee626024cb45acbd57cb9d4032b",
        strip = 1,
    },
    dependencies = {
        "abseil",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          RE2_BUILD_TESTING = "OFF",
          RE2_USE_ICU = "OFF",
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
        "re2",
      },
      binaries = {},
    },
}
