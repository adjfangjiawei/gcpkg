-- libsamplerate 0.2.2 -- gcpkg port definition.
-- Secret Rabbit Code audio resampler.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libsamplerate",
    version = "0.2.2",
    license = "BSD-2-Clause",
    homepage = "https://github.com/libsndfile/libsamplerate",
    description = "Audio sample-rate converter",
    source = {
        url = "https://codeload.github.com/libsndfile/libsamplerate/tar.gz/refs/tags/0.2.2",
        sha256 = "16e881487f184250deb4fcb60432d7556ab12cb58caea71ef23960aec6c0405a",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          LIBSAMPLERATE_EXAMPLES = "OFF",
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
        "samplerate",
      },
      binaries = {},
    },
}
