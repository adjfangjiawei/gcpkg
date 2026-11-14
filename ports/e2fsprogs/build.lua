-- e2fsprogs 1.47.4 -- gcpkg port definition.
-- ext filesystem libraries, ships ./configure.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "e2fsprogs",
    version = "1.47.4",
    license = "GPL-2.0/LGPL-2.0",
    homepage = "https://e2fsprogs.sourceforge.net",
    description = "ext2/3/4 tools, libext2fs, libcom_err",
    source = {
        url = "https://codeload.github.com/tytso/e2fsprogs/tar.gz/refs/tags/v1.47.4",
        sha256 = "9f82eaa7002673291629077b80ee005cadfcd49854907a22007fed70b0ef596e",
        strip = 1,
    },
    dependencies = {
        "util-linux",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
        },
    },
    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
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
        "ext2fs",
        "com_err",
        "ss",
        "e2p",
      },
      binaries = {},
    },
}
