-- portaudio 19.7.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- Portable audio I/O; `alsa` feature pulls the alsa-lib port.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "portaudio",
    version = "19.7.0",
    license = "MIT",
    homepage = "https://www.portaudio.com",
    description = "Cross-platform audio I/O library",
    source = {
        url = "https://codeload.github.com/PortAudio/portaudio/tar.gz/refs/tags/v19.7.0",
        sha256 = "5af29ba58bbdbb7bbcefaaecc77ec8fc413f0db6f4c4e286c40c3e1b83174fa0",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          PA_BUILD_TESTS = "OFF",
          PA_BUILD_EXAMPLES = "OFF",
          PA_BUILD_SHARED = "OFF",
          PA_BUILD_STATIC = "ON",
          PA_LIBNAME_ADD_SUFFIX = "OFF",
          PA_USE_ALSA = "OFF",
          PA_USE_JACK = "OFF",
          PA_ENABLE_DEBUG_OUTPUT = "OFF",
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
        "portaudio",
      },
      binaries = {},
    },
}
