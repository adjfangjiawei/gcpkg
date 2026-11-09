-- pybind11 2.13.6 -- gcpkg port definition.
-- Header-only C++/Python bindings; uses the python tool port.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "pybind11",
    version = "2.13.6",
    license = "BSD-3-Clause",
    homepage = "https://github.com/pybind/pybind11",
    description = "Header-only C++/Python binding library",
    source = {
        url = "https://codeload.github.com/pybind/pybind11/tar.gz/refs/tags/v2.13.6",
        sha256 = "e08cb87f4773da97fa7b5f035de8763abc656d87d5773e62f6da0587d1f0ec20",
        strip = 1,
    },
    dependencies = {
        "python",
      },
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          PYBIND11_INSTALL = "ON",
          PYBIND11_TEST_OVERRIDE = "OFF",
          PYBIND11_FINDPYTHON = "OFF",
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
