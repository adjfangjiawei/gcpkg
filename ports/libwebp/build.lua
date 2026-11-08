-- libwebp 1.5.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).
-- WebP image codec; all command-line tools disabled.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libwebp",
    version = "1.5.0",
    license = "BSD-3-Clause",
    homepage = "https://developers.google.com/speed/webp",
    description = "WebP image codec",
    source = {
        url = "https://codeload.github.com/webmproject/libwebp/tar.gz/refs/tags/v1.5.0",
        sha256 = "668c9aba45565e24c27e17f7aaf7060a399f7f31dba6c97a044e1feacb930f37",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_SHARED_LIBS = "OFF",
          WEBP_BUILD_CWEBP = "OFF",
          WEBP_BUILD_DWEBP = "OFF",
          WEBP_BUILD_GIF2WEBP = "OFF",
          WEBP_BUILD_IMG2WEBP = "OFF",
          WEBP_BUILD_VWEBP = "OFF",
          WEBP_BUILD_WEBPINFO = "OFF",
          WEBP_BUILD_ANIM_UTILS = "OFF",
          WEBP_BUILD_EXTRAS = "OFF",
          WEBP_BUILD_LIBWEBPMUX = "OFF",
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
        "webp",
        "webpmux",
        "webpdemux",
      },
      binaries = {},
    },
}
