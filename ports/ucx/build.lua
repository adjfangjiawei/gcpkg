-- ucx 1.23.2 -- gcpkg port definition.
-- Autotools; CUDA/ROCm support is optional and comes from the 'nvidia' SDK port when enabled.


local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "ucx",
    version = "1.23.2",
    description = "Unified Communication X (UCX)",
    license = "BSD-3-Clause",
    homepage = "https://openucx.org",
    source = {
        url = "https://codeload.github.com/openucx/ucx/tar.gz/refs/tags/v1.23.2",
        sha256 = "150ca11940e3e694a530deec4a063e340a8400f8249579e083fab7797fd5eda8",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {},
    },
    pre_build = function(ctx)
    if not fs.isfile(ctx.src .. '/configure') then
        ctx.exec({ './autogen.sh' }, { cwd = ctx.src, log = ctx.log })
    end
    end,
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "ucp",
        "ucs",
        "uct",
      },
      binaries = {},
    },
}
