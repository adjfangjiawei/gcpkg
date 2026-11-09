-- libunwind 1.8.3 -- gcpkg port definition.
-- Stack unwinding; upstream CMakeLists.txt is Visual-Studio-only, so the autotools build is used (tag archive needs autoreconf).

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libunwind",
    version = "1.8.3",
    license = "MIT",
    homepage = "https://github.com/libunwind/libunwind",
    description = "Stack unwinding library",
    source = {
        url = "https://codeload.github.com/libunwind/libunwind/tar.gz/refs/tags/v1.8.3",
        sha256 = "21b26bc75cd37b548d7952f2794cde711efa6c6151c4147cc3c52cfedbf11df4",
        strip = 1,
    },
    dependencies = {
        "zlib",
        "xz",
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
        "unwind",
      },
      binaries = {},
    },
}
