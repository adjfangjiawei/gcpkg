-- YAML 1.1 parser and emitter in C
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libyaml",
    version = "0.2.5",
    description = "YAML 1.1 parser and emitter in C",
    license = "MIT",
    homepage = "https://github.com/yaml/libyaml",
    source = {
        url = "https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz",
        sha256 = "c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-shared" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "yaml" }
    },
}
