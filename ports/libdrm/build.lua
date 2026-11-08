-- Direct Rendering Manager user-space library
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libdrm",
    version = "2.4.124",
    description = "Direct Rendering Manager user-space library",
    license = "MIT",
    homepage = "https://dri.freedesktop.org",
    source = {
        url = "https://dri.freedesktop.org/libdrm/libdrm-2.4.124.tar.xz",
        sha256 = "ac36293f61ca4aafaf4b16a2a7afff312aa4f5c37c9fbd797de9e3c0863ca379",
        strip = 1,
    },
    dependencies = { "libpciaccess" },
    meson = {
        options = {
          intel = "disabled",
          radeon = "disabled",
          amdgpu = "disabled",
          nouveau = "disabled",
          vmwgfx = "disabled",
          omap = "disabled",
          exynos = "disabled",
          freedreno = "disabled",
          tegra = "disabled",
          vc4 = "disabled",
          etnaviv = "disabled",
          ["cairo-tests"] = "disabled",
          ["man-pages"] = "disabled",
          valgrind = "disabled",
          ["install-test-programs"] = "false",
          udev = "false",
          tests = "false"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include/libdrm", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "drm" }
    },
}
