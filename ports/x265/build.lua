-- x265 3.4 -- gcpkg port definition.
-- Static HEVC encoder; CLI/shared library and optional host SDKs disabled.
-- License files are installed under share/doc/x265 by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")

return recipe.cmake {
    name = "x265",
    version = "3.4",
    license = "GPL-2.0-or-later",
    homepage = "https://www.videolan.org/developers/x265.html",
    description = "x265 3.4 static HEVC encoder source port for FFmpeg",
    source = { url = "https://codeload.github.com/videolan/x265/tar.gz/refs/tags/3.4", sha256 = "544d147bf146f8994a7bf8521ed878c93067ea1c7c6e93ab602389be3117eaaf", strip = 1 },
    dependencies = {},
    pre_build = function(ctx) r20.patch_x265_cmake_policies(ctx) end,
    cmake = {
        generator = "Ninja",
        source = "source",
        defines = {
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            CMAKE_POSITION_INDEPENDENT_CODE = "ON",
            BUILD_SHARED_LIBS = "OFF", BUILD_TESTING = "OFF",
            ENABLE_SHARED = "OFF", ENABLE_CLI = "OFF", ENABLE_PIC = "ON",
            ENABLE_ASSEMBLY = "ON", ENABLE_LIBNUMA = "OFF",
            ENABLE_LIBVMAF = "OFF", ENABLE_TESTS = "OFF",
            HIGH_BIT_DEPTH = "OFF", EXPORT_C_API = "ON",
            LIB_INSTALL_DIR = "lib",
        },
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "x265" },
        binaries = {},
        link_flags = { "-lstdc++", "-lm", "-lpthread", "-ldl" },
    },
    post_install = function(ctx) r20.license(ctx, { "COPYING" }) end,
}
