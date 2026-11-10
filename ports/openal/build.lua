-- openal 1.25.2 -- gcpkg port definition.
-- OpenAL Soft static library; SDL3/ALSA backends use source-built ports.
-- License files are installed under share/doc/openal by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")
local util = require("gcpkg.util")

return recipe.cmake {
    name = "openal",
    version = "1.25.2",
    license = "LGPL-2.0-or-later",
    homepage = "https://openal-soft.org/",
    description = "OpenAL Soft static library with source-built SDL3/ALSA backends and Wave/Null",
    source = { url = "https://codeload.github.com/kcat/openal-soft/tar.gz/refs/tags/1.25.2", sha256 = "fb27e5839aa11f0e5b9d33756965291fad5d6909ab928ea1f796f4a1a6877894", strip = 1 },
    dependencies = { "sdl3", "alsa-lib" },
    pre_build = function(ctx) r20.restrict_pkgconfig(ctx) end,
    cmake = {
        generator = "Ninja",
        defines = function(ctx)
            local alsa = r20.lib_file(ctx, "alsa-lib", "asound")
            local sdl = r20.dep_prefix(ctx, "sdl3")
            return {
                CMAKE_BUILD_TYPE = "Release",
                CMAKE_INSTALL_LIBDIR = "lib",
                CMAKE_PREFIX_PATH = r20.cmake_prefix(ctx),
                BUILD_SHARED_LIBS = "OFF", BUILD_TESTING = "OFF",
                LIBTYPE = "STATIC",
                SDL3_DIR = util.join(sdl, "lib", "cmake", "SDL3"),
                ALSA_INCLUDE_DIR = r20.dep_include(ctx, "alsa-lib"),
                ALSA_INCLUDE_DIRS = r20.dep_include(ctx, "alsa-lib"),
                ALSA_LIBRARY = alsa, ALSA_LIBRARIES = alsa,
                ALSOFT_BACKEND_SDL3 = "ON", ALSOFT_REQUIRE_SDL3 = "ON",
                ALSOFT_BACKEND_ALSA = "ON", ALSOFT_REQUIRE_ALSA = "ON",
                ALSOFT_BACKEND_WAVE = "ON",
                ALSOFT_BACKEND_PIPEWIRE = "OFF", ALSOFT_REQUIRE_PIPEWIRE = "OFF",
                ALSOFT_BACKEND_PULSEAUDIO = "OFF", ALSOFT_REQUIRE_PULSEAUDIO = "OFF",
                ALSOFT_BACKEND_OSS = "OFF", ALSOFT_REQUIRE_OSS = "OFF",
                ALSOFT_BACKEND_SOLARIS = "OFF", ALSOFT_REQUIRE_SOLARIS = "OFF",
                ALSOFT_BACKEND_SNDIO = "OFF", ALSOFT_REQUIRE_SNDIO = "OFF",
                ALSOFT_BACKEND_WASAPI = "OFF", ALSOFT_REQUIRE_WASAPI = "OFF",
                ALSOFT_BACKEND_DSOUND = "OFF", ALSOFT_REQUIRE_DSOUND = "OFF",
                ALSOFT_BACKEND_WINMM = "OFF", ALSOFT_REQUIRE_WINMM = "OFF",
                ALSOFT_BACKEND_JACK = "OFF", ALSOFT_REQUIRE_JACK = "OFF",
                ALSOFT_BACKEND_COREAUDIO = "OFF", ALSOFT_REQUIRE_COREAUDIO = "OFF",
                ALSOFT_BACKEND_OBOE = "OFF", ALSOFT_REQUIRE_OBOE = "OFF",
                ALSOFT_BACKEND_OPENSL = "OFF", ALSOFT_REQUIRE_OPENSL = "OFF",
                ALSOFT_BACKEND_PORTAUDIO = "OFF", ALSOFT_REQUIRE_PORTAUDIO = "OFF",
                ALSOFT_BACKEND_SDL2 = "OFF", ALSOFT_REQUIRE_SDL2 = "OFF",
                ALSOFT_DLOPEN = "OFF", ALSOFT_DLOPEN_NOTES = "OFF",
                ALSOFT_RTKIT = "OFF", ALSOFT_REQUIRE_RTKIT = "OFF",
                ALSOFT_UTILS = "OFF", ALSOFT_EXAMPLES = "OFF",
                ALSOFT_TESTS = "OFF", ALSOFT_NO_CONFIG_UTIL = "ON",
                ALSOFT_INSTALL = "ON", ALSOFT_INSTALL_CONFIG = "OFF",
                ALSOFT_INSTALL_HRTF_DATA = "OFF", ALSOFT_INSTALL_AMBDEC_PRESETS = "OFF",
                ALSOFT_INSTALL_EXAMPLES = "OFF", ALSOFT_INSTALL_UTILS = "OFF",
                ALSOFT_EMBED_HRTF_DATA = "ON", ALSOFT_UPDATE_BUILD_VERSION = "OFF",
                ALSOFT_ENABLE_MODULES = "OFF", ALSOFT_WERROR = "OFF",
                ALSOFT_EAX = "OFF", ALSOFT_SEARCH_INSTALL_DATADIR = "OFF",
                ALSOFT_BUILD_ROUTER = "OFF", ALSOFT_OSX_FRAMEWORK = "OFF",
            }
        end,
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/AL" },
        libdirs = { "@LIBDIR@" },
        libs = { "openal" },
        binaries = {},
        defines = { "AL_LIBTYPE_STATIC" },
        link_flags = { "-lasound", "-lSDL3", "-ldl", "-lpthread", "-lstdc++", "-lm" },
    },
    post_install = function(ctx)
        r20.license(ctx, { "COPYING", "fmt-11.2.0/LICENSE", "gsl/LICENSE" })
    end,
}
