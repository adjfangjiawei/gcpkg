-- onetbb 2022.0.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Static checks in tests/r11.sh; GCPKG_R11_DYNAMIC=1 builds it for real.
-- oneTBB; `python` feature enables the optional Python module.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "onetbb",
    version = "2022.0.0",
    license = "Apache-2.0",
    homepage = "https://github.com/oneapi-src/oneTBB",
    description = "oneAPI Threading Building Blocks",
    source = {
        url = "https://codeload.github.com/oneapi-src/oneTBB/tar.gz/refs/tags/v2022.0.0",
        sha256 = "e8e89c9c345415b17b30a2db3095ba9d47647611662073f7fbf54ad48b7f3c2a",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          TBB_TEST = "OFF",
          TBB_EXAMPLES = "OFF",
          TBB_STRICT = "OFF",
          TBB4PY_BUILD = "OFF",
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
        "tbb",
        "tbbmalloc",
      },
      binaries = {},
    },
}
