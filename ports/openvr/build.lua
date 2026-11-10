-- openvr 2.15.6 -- gcpkg port definition.
-- ValveSoftware/openvr static SDK; OpenGR/OpenGR-IRIT was a typo and is not used.
-- License files are installed under share/doc/openvr by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")

return recipe.cmake {
    name = "openvr",
    version = "2.15.6",
    license = "BSD-3-Clause",
    homepage = "https://github.com/ValveSoftware/openvr",
    description = "Valve OpenVR SDK static library and headers built from source",
    source = { url = "https://codeload.github.com/ValveSoftware/openvr/tar.gz/refs/tags/v2.15.6", sha256 = "e184cb625010fab7043a9d5e1e000fdeb3067a152bb3169ef53f64dfac37164c", strip = 1 },
    dependencies = {},
    cmake = {
        generator = "Ninja",
        defines = {
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            CMAKE_POSITION_INDEPENDENT_CODE = "ON",
            BUILD_SHARED_LIBS = "OFF", BUILD_TESTING = "OFF",
            BUILD_SHARED = "OFF", BUILD_FRAMEWORK = "OFF",
            BUILD_UNIVERSAL = "OFF", BUILD_OSX_I386 = "OFF",
            USE_LIBCXX = "OFF", USE_CUSTOM_LIBCXX = "OFF",
        },
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/openvr" },
        libdirs = { "@LIBDIR@" },
        libs = { "openvr_api" },
        binaries = {},
        link_flags = { "-ldl", "-lstdc++", "-lpthread" },
    },
    post_install = function(ctx) r20.license(ctx, { "LICENSE" }) end,
}
