-- blake3 1.8.2 -- gcpkg port definition.
-- BLAKE3 C build lives in the c/ subdir (cmake.source).

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "blake3",
    version = "1.8.2",
    license = "CC0-1.0",
    homepage = "https://github.com/BLAKE3-team/BLAKE3",
    description = "BLAKE3 cryptographic hash (C implementation in c/)",
    source = {
        url = "https://codeload.github.com/BLAKE3-team/BLAKE3/tar.gz/refs/tags/1.8.2",
        sha256 = "6b51aefe515969785da02e87befafc7fdc7a065cd3458cf1141f29267749e81f",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        source = "c",
        -- Explicit results, like ports/sdl3/build.lua: the only probes are two
        -- check_cxx_symbol_exists calls; clang-23 uses libstdc++ here.
        defines = {
          BUILD_TESTING = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          CMAKE_C_STANDARD = "99",
          BLAKE3_USE_TBB = "OFF",
          BLAKE3_FETCH_TBB = "OFF",
          BLAKE3_HAVE_GLIBCXX = "TRUE",
          BLAKE3_HAVE_LIBCPP = "FALSE",
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
        "blake3",
      },
      binaries = {},
    },
}
