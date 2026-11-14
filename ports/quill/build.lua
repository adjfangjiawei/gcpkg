-- quill 13.1.0 -- gcpkg port definition.
-- Header-only low-latency asynchronous logging; probe links pthread.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "quill",
    version = "13.1.0",
    license = "MIT",
    homepage = "https://github.com/odygrd/quill",
    description = "Header-only low-latency asynchronous logging library",
    source = {
        url = "https://codeload.github.com/odygrd/quill/tar.gz/refs/tags/v13.1.0",
        sha256 = "a08b93bafc7e712b28eb47e4a1ed9b60fc01ac7fad3ce269f1f100560a506a85",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/quill", dst = "quill" },
          },
        include = "quill/Backend.h",
        flags = {
            "-std=c++17",
            "-pthread",
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
