-- Linux kernel module handling library and tools
-- ONE library, ONE build.lua and ONE features.yaml. Upstream sources
-- are downloaded verbatim (sha256 verified) and never patched.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "kmod",
    version = "34.2",
    description = "Linux kernel module handling library and tools",
    license = "LGPL-2.1",
    homepage = "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git",
    source = {
        url = "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/kmod/kmod-34.2.tar.xz",
        sha256 = "5a5d5073070cc7e0c7a7a3c6ec2a0e1780850c8b47b3e3892226b93ffcb9cb54",
        strip = 1,
    },
    dependencies = {},
    meson = {
        options = function(ctx) return {
              tools = "false",
              manpages = "false",
              docs = "false",
              ["build-tests"] = "false",
              zstd = "disabled",
              xz = "disabled",
              zlib = "disabled",
              openssl = "disabled",
              distconfdir = ctx.prefix .. '/etc/depmod.d',
              moduledir = ctx.prefix .. '/lib/modules'
            } end,
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "kmod" }
    },
}
