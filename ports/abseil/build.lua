-- abseil 20240722.0 -- gcpkg port definition.
-- Abseil C++ foundation.
--
-- R20 new standard: every feature SUPPORTED on the active triplet is enabled
-- by default.  Platform/toolchain facts come from the single shared gcpkg
-- probe (triplet), never hardcoded per port.  GoogleTest is a source-built
-- gcpkg port installed bottom-up first; find_package(GTest) is pointed
-- straight at its installed CONFIG package, so no search / no probe runs.
--
-- NOT enabled here (not "disabled features"):
--   * static/shared are mutually exclusive build shapes;
--   * ABSL_BUILD_MONOLITHIC_SHARED_LIBS requires the shared shape;
--   * ABSL_USE_GOOGLETEST_HEAD downloads from the network at configure time;
--   * ABSL_USE_SYSTEM_INCLUDES is an include-style switch (upstream OFF);
--   * ABSL_MSVC_STATIC_RUNTIME is MSVC-only, unsupported on this triplet.

local recipe = require("gcpkg.recipe")
local triplet = require("gcpkg.triplet")

local function flag(v)
    local s = triplet.scalar(v)
    return (s ~= "" and s ~= "0") and "TRUE" or "FALSE"
end

return recipe.cmake {
    name = "abseil",
    version = "20240722.0",
    license = "Apache-2.0",
    homepage = "https://abseil.io",
    description = "Abseil C++ common libraries (foundation for re2)",
    source = {
        url = "https://codeload.github.com/abseil/abseil-cpp/tar.gz/refs/tags/20240722.0",
        sha256 = "f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3",
        strip = 1,
    },
    -- Bottom-up: the testing feature is ON by default, so its library is a
    -- source-built port that must be installed before this one.
    dependencies = { "googletest" },
    cmake = {
        defines = function(ctx)
            local f = triplet.facts()
            local gtest = assert(ctx.dep("googletest"),
                                 "googletest must be installed bottom-up")
            local libdir = assert((gtest.libdirs or {})[1],
                                  "googletest manifest has no libdirs")
            return {
                -- All features supported on this triplet: ON.
                BUILD_TESTING = "ON",
                ABSL_ENABLE_INSTALL = "ON",
                ABSL_PROPAGATE_CXX_STD = "ON",
                ABSL_BUILD_TESTING = "ON",
                ABSL_BUILD_TEST_HELPERS = "ON",
                ABSL_USE_EXTERNAL_GOOGLETEST = "ON",
                ABSL_FIND_GOOGLETEST = "ON",

                -- Compiler C++ capability: shared triplet facts, not hardcoded.
                ABSL_INTERNAL_AT_LEAST_CXX17 = flag(f.cxx17_capable),
                ABSL_INTERNAL_AT_LEAST_CXX20 = flag(f.cxx20_capable),

                -- find_package(GTest REQUIRED): direct CONFIG, zero searches.
                CMAKE_FIND_PACKAGE_PREFER_CONFIG = "ON",
                GTest_DIR = libdir .. "/cmake/GTest",

                -- Build shapes / unsupported / network-download switches.
                BUILD_SHARED_LIBS = "OFF",
                ABSL_BUILD_MONOLITHIC_SHARED_LIBS = "OFF",
                ABSL_USE_GOOGLETEST_HEAD = "OFF",
                ABSL_USE_SYSTEM_INCLUDES = "OFF",
                ABSL_MSVC_STATIC_RUNTIME = "OFF",
            }
        end,
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
      binaries = {},
    },
}
