-- alsa-lib 1.2.9 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- Autotools. Host ALSA headers via pkgconfig backend; --disable-python avoids Python SWIG bindings.
-- Upstream is never patched: all adaptation lives in this file.


local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "alsa-lib",
    version = "1.2.9",
    description = "ALSA userspace library",
    license = "LGPL-2.1",
    homepage = "https://www.alsa-project.org",
    source = {
        url = "https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.9.tar.bz2",
        sha256 = "dc9c643fdc4ccfd0572cc685858dd41e08afb583f30460b317e4188275f615b2",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--disable-python",
        },
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "asound",
      },
      binaries = {},
    },
}
