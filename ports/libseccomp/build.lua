-- Linux seccomp filter library
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libseccomp",
    version = "2.6.0",
    description = "Linux seccomp filter library",
    license = "LGPL-2.1",
    homepage = "https://github.com/seccomp/libseccomp",
    source = {
        url = "https://github.com/seccomp/libseccomp/releases/download/v2.6.0/libseccomp-2.6.0.tar.gz",
        sha256 = "83b6085232d1588c379dc9b9cae47bb37407cf262e6e74993c61ba72d2a784dc",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-python", "--disable-shared" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "seccomp" }
    },
}
