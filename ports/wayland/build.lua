-- Wayland core libraries and protocol scanner
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "wayland",
    version = "1.23.1",
    description = "Wayland core libraries and protocol scanner",
    license = "MIT",
    homepage = "https://wayland.freedesktop.org",
    source = {
        url = "https://gitlab.freedesktop.org/wayland/wayland/-/archive/1.23.1/wayland-1.23.1.tar.gz",
        sha256 = "158ec49af498f2558c7fbf7e8b070d010d4e270cc6076003a18a6c813f87e244",
        strip = 1,
    },
    dependencies = { "libffi", "expat" },
    meson = {
        options = {
          libraries = "true",
          scanner = "true",
          documentation = "false",
          dtd_validation = "false"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "wayland-server", "wayland-client", "wayland-cursor", "wayland-egl" },
      binaries = { "@PREFIX@/bin" }
    },
}
