-- libgpiod 2.3.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- GPIO character-device library; Meson build.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libgpiod",
    version = "2.3.2",
    license = "LGPL-2.1",
    homepage = "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git",
    description = "GPIO character device library",
    source = {
        url = "https://codeload.github.com/brgl/libgpiod/tar.gz/refs/tags/v2.3.2",
        sha256 = "ca9bf015b809bd2b368557fa6401527f4be139fa4b23028b4214bf364139cafd",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = {},
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
        "gpiod",
      },
      binaries = {},
    },
}
