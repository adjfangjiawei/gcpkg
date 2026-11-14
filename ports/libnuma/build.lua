-- NUMA policy library (libnuma) and numactl tools
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "libnuma",
    version = "2.0.19",
    description = "NUMA policy library (libnuma) and numactl tools",
    license = "LGPL-2.1",
    homepage = "https://github.com/numactl/numactl",
    source = {
        url = "https://github.com/numactl/numactl/releases/download/v2.0.19/numactl-2.0.19.tar.gz",
        sha256 = "f2672a0381cb59196e9c246bf8bcc43d5568bc457700a697f1a1df762b9af884",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-shared" },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "numa" },
      binaries = { "@PREFIX@/bin" }
    },
}
