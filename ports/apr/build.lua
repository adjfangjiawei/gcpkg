-- apr 1.7.5 -- gcpkg port definition.
-- Apache Portable Runtime; stock autotools static build.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "apr",
    version = "1.7.5",
    license = "Apache-2.0",
    homepage = "https://apr.apache.org",
    description = "Apache Portable Runtime library",
    source = {
        url = "https://archive.apache.org/dist/apr/apr-1.7.5.tar.gz",
        sha256 = "3375fa365d67bcf945e52b52cba07abea57ef530f40b281ffbe977a9251361db",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = {
          "--without-sendfile",
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
        "apr-1",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
