-- dlib 20.0.1 -- gcpkg port definition.
-- Static dlib with source-built JPEG/PNG/zlib; GUI/CUDA/BLAS/FFmpeg off.
-- License files are installed under share/doc/dlib by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")

return recipe.cmake {
    name = "dlib",
    version = "20.0.1",
    license = "BSL-1.0",
    homepage = "http://dlib.net/",
    description = "dlib static library using source-built JPEG/PNG/zlib ports, no GUI/CUDA/BLAS",
    source = { url = "https://codeload.github.com/davisking/dlib/tar.gz/refs/tags/v20.0.1", sha256 = "dab5b4ec4b68bd7dc128a1fb7900723f89d2da107e44cd5def7d38fc57252a9d", strip = 1 },
    dependencies = { "zlib", "libjpeg-turbo", "libpng" },
    pre_build = function(ctx) r20.restrict_pkgconfig(ctx) end,
    cmake = {
        generator = "Ninja",
        defines = function(ctx)
            local jpeg = r20.lib_file(ctx, "libjpeg-turbo", "jpeg")
            local png = r20.lib_file(ctx, "libpng", "png16")
            local z = r20.lib_file(ctx, "zlib", "z")
            return {
                CMAKE_BUILD_TYPE = "Release",
                CMAKE_INSTALL_LIBDIR = "lib",
                CMAKE_PREFIX_PATH = r20.cmake_prefix(ctx),
                BUILD_SHARED_LIBS = "OFF", BUILD_TESTING = "OFF",
                CMAKE_POSITION_INDEPENDENT_CODE = "ON",
                JPEG_LIBRARY = jpeg, JPEG_LIBRARIES = jpeg,
                JPEG_INCLUDE_DIR = r20.dep_include(ctx, "libjpeg-turbo"),
                PNG_LIBRARY = png, PNG_LIBRARIES = png .. ";" .. z,
                PNG_INCLUDE_DIR = r20.dep_include(ctx, "libpng"),
                PNG_INCLUDE_DIRS = r20.dep_include(ctx, "libpng"),
                ZLIB_LIBRARY = z, ZLIB_LIBRARIES = z,
                ZLIB_INCLUDE_DIR = r20.dep_include(ctx, "zlib"),
                DLIB_ISO_CPP_ONLY = "OFF", DLIB_NO_GUI_SUPPORT = "ON",
                DLIB_ENABLE_STACK_TRACE = "OFF", DLIB_ENABLE_ASSERTS = "OFF",
                DLIB_JPEG_SUPPORT = "ON", DLIB_PNG_SUPPORT = "ON",
                DLIB_GIF_SUPPORT = "OFF", DLIB_WEBP_SUPPORT = "OFF",
                DLIB_JXL_SUPPORT = "OFF", DLIB_LINK_WITH_SQLITE3 = "OFF",
                DLIB_USE_BLAS = "OFF", DLIB_USE_LAPACK = "OFF",
                DLIB_USE_CUDA = "OFF", DLIB_USE_MKL_SEQUENTIAL = "OFF",
                DLIB_USE_MKL_WITH_TBB = "OFF", DLIB_USE_MKL_FFT = "OFF", DLIB_USE_MKL_FFT = "OFF",
                DLIB_USE_FFMPEG = "OFF",
            }
        end,
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "dlib" },
        binaries = {},
        link_flags = { "-ljpeg", "-lpng16", "-lz", "-lpthread", "-ldl", "-lm" },
    },
    post_install = function(ctx) r20.license(ctx, { "LICENSE.txt" }) end,
}
