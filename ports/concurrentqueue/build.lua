-- concurrentqueue 1.0.4 -- gcpkg port definition.
-- Header-only lock-free queue; installs under include/concurrentqueue.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "concurrentqueue",
    version = "1.0.4",
    license = "BSD-2-Clause",
    homepage = "https://github.com/cameron314/concurrentqueue",
    description = "Header-only lock-free concurrent queue",
    source = {
        url = "https://codeload.github.com/cameron314/concurrentqueue/tar.gz/refs/tags/v1.0.4",
        sha256 = "87fbc9884d60d0d4bf3462c18f4c0ee0a9311d0519341cac7cbd361c885e5281",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include/concurrentqueue",
        "@PREFIX@/include/concurrentqueue/moodycamel",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {},
      binaries = {},
    },
}
