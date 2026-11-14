-- redpanda 26.2.2 -- gcpkg port definition.
-- C++/Seastar monorepo; declared with its CMake entry point. Full build additionally needs clang, Seastar deps and Rust toolchain on the host.


local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "redpanda",
    version = "26.2.2",
    description = "Redpanda streaming data platform (C++/Seastar)",
    license = "BSL-1.1",
    homepage = "https://github.com/redpanda-data/redpanda",
    source = {
        url = "https://codeload.github.com/redpanda-data/redpanda/tar.gz/refs/tags/v26.2.2",
        sha256 = "3d81fe24166423cf8b1cfb8c248a43c29edfa19f6e1260f96a3fa5c62f8431d1",
        strip = 1,
    },
    dependencies = {
        "cmake",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
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
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
