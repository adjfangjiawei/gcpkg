-- simde 0.8.2 -- gcpkg port definition.
-- Portable SIMD intrinsics; whole simde/ header tree installed.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "simde",
    version = "0.8.2",
    license = "MIT",
    homepage = "https://github.com/simd-everywhere/simde",
    description = "SIMD Everywhere: portable SIMD intrinsics headers",
    source = {
        url = "https://codeload.github.com/simd-everywhere/simde/tar.gz/refs/tags/v0.8.2",
        sha256 = "ed2a3268658f2f2a9b5367628a85ccd4cf9516460ed8604eed369653d49b25fb",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "simde", dst = "simde" },
          },
        include = "simde/x86/sse2.h",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "COPYING",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
