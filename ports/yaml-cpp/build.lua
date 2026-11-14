-- yaml-cpp 0.8.0 -- gcpkg port definition.
-- YAML parser/emitter; static build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "yaml-cpp",
    version = "0.8.0",
    license = "MIT",
    homepage = "https://github.com/jbeder/yaml-cpp",
    description = "YAML parser and emitter in C++",
    source = {
        url = "https://codeload.github.com/jbeder/yaml-cpp/tar.gz/refs/tags/0.8.0",
        sha256 = "fbe74bbdcee21d656715688706da3c8becfd946d92cd44705cc6098bb23b3a16",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          YAML_CPP_BUILD_TESTS = "OFF",
          YAML_CPP_BUILD_TOOLS = "OFF",
          YAML_CPP_BUILD_CONTRIB = "OFF",
          YAML_BUILD_SHARED_LIBS = "OFF",
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
        "yaml-cpp",
      },
      binaries = {},
    },
}
