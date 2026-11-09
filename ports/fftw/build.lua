-- fftw 3.3.10 -- gcpkg port definition.
-- FFTW3 discrete Fourier transform library; single-thread static build.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "fftw",
    version = "3.3.10",
    license = "GPL-2.0-or-later",
    homepage = "https://www.fftw.org",
    description = "Fastest Fourier Transform in the West",
    source = {
        url = "https://www.fftw.org/fftw-3.3.10.tar.gz",
        sha256 = "56c932549852cddcfafdab3820b0200c7742675be92179e59e6215b340e26467",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          CMAKE_BUILD_TYPE = "Release",
          CMAKE_INSTALL_LIBDIR = "lib",
          BUILD_SHARED_LIBS = "OFF",
          ENABLE_THREADS = "OFF",
          ENABLE_OPENMP = "OFF",
        },
        args = {},
        jobs = 2,
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "fftw3",
      },
      binaries = {},
    },
}
