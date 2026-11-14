-- librdkafka 2.8.0 -- gcpkg port definition.
-- Kafka C client on zlib; `ssl` feature adds openssl.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "librdkafka",
    version = "2.8.0",
    license = "BSD-2-Clause",
    homepage = "https://github.com/confluentinc/librdkafka",
    description = "Apache Kafka C/C++ client",
    source = {
        url = "https://codeload.github.com/confluentinc/librdkafka/tar.gz/refs/tags/v2.8.0",
        sha256 = "5bd1c46f63265f31c6bfcedcde78703f77d28238eadf23821c2b43fc30be3e25",
        strip = 1,
    },
    dependencies = {
        "zlib",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-sasl",
          "--disable-gssapi",
          "--disable-curl",
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
        "rdkafka",
      },
      binaries = {},
    },
}
