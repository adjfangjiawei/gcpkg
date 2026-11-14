-- GNOME XML parser and toolkit
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libxml2",
    version = "2.14.5",
    description = "GNOME XML parser and toolkit",
    license = "MIT",
    homepage = "https://gitlab.gnome.org/GNOME/libxml2",
    source = {
        url = "https://download.gnome.org/sources/libxml2/2.14/libxml2-2.14.5.tar.xz",
        sha256 = "03d006f3537616833c16c53addcdc32a0eb20e55443cba4038307e3fa7d8d44b",
        strip = 1,
    },
    dependencies = { "zlib", "xz" },
    cmake = {
        defines = {
          BUILD_SHARED_LIBS = "OFF",
          LIBXML2_WITH_PYTHON = "OFF",
          LIBXML2_WITH_PROGRAMS = "OFF",
          LIBXML2_WITH_TESTS = "OFF",
          LIBXML2_WITH_ZLIB = "ON",
          LIBXML2_WITH_LZMA = "ON",
          LIBXML2_WITH_ICONV = "OFF",
          LIBXML2_WITH_ICU = "OFF"
        },
    },
    exports = {
      includes = { "@PREFIX@/include/libxml2", "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "xml2" }
    },
}
