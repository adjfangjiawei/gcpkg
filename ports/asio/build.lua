-- asio asio-1-34-2 -- gcpkg port definition.
-- Standalone Asio; no Boost required, probe uses -pthread.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "asio",
    version = "asio-1-34-2",
    license = "BSL-1.0",
    homepage = "https://github.com/chriskohlhoff/asio",
    description = "Standalone Asio asynchronous I/O C++ library",
    source = {
        url = "https://codeload.github.com/chriskohlhoff/asio/tar.gz/refs/tags/asio-1-34-2",
        sha256 = "f3bac015305fbb700545bd2959fbc52d75a1ec2e05f9c7f695801273ceb78cf5",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "asio/include/asio.hpp", dst = "asio.hpp" },
            { src = "asio/include/asio", dst = "asio" },
          },
        include = "asio.hpp",
        flags = {
            "-std=c++17",
            "-pthread",
          },
        license_files = {
            "asio/LICENSE_1_0.txt",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
