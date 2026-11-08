-- libfuse 3.18.3 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- libfuse 3 uses Meson. No guessed -D options: meson setup runs with the upstream defaults plus gcpkg's prefix/sysconfdir confinement.
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libfuse",
    version = "3.18.3",
    description = "FUSE 3 userspace library",
    license = "LGPL-2.1",
    homepage = "https://github.com/libfuse/libfuse",
    source = {
        url = "https://codeload.github.com/libfuse/libfuse/tar.gz/refs/tags/fuse-3.18.3",
        sha256 = "a26f46edc8db4e2cbf1b46d36d3e18ea208871671e56434d9ceb8f7887a690d2",
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
        "fuse3",
      },
      binaries = {},
    },
}
