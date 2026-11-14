-- highway 1.2.0 -- gcpkg port definition.
-- Google Highway portable SIMD library (core; contrib sort disabled: its vqsort templates need multi-GB RAM per TU).

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "highway",
    version = "1.2.0",
    license = "Apache-2.0",
    homepage = "https://github.com/google/highway",
    description = "Performance-portable SIMD/vector intrinsics",
    source = {
        url = "https://codeload.github.com/google/highway/tar.gz/refs/tags/1.2.0",
        sha256 = "7e0be78b8318e8bdbf6fa545d2ecb4c90f947df03f7aadc42c1967f019e63343",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          HWY_ENABLE_TESTS = "OFF",
          HWY_ENABLE_EXAMPLES = "OFF",
          HWY_ENABLE_CONTRIB = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          HWY_FORCE_STATIC_LIBS = "ON",
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
        "hwy",
      },
      binaries = {},
    },
}
