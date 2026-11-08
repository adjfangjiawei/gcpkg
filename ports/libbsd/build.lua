-- libbsd 0.12.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests in tests/r10.sh; real
-- builds in GCPKG_R10_DYNAMIC=1 ./tests/r10.sh.
-- BSD compatibility layer on libmd; official release tarball ships ./configure.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "libbsd",
    version = "0.12.2",
    license = "BSD-3-Clause",
    homepage = "https://libbsd.freedesktop.org",
    description = "Compatibility functions from BSD systems on libmd (official release tarball)",
    source = {
        url = "https://libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz",
        sha256 = "b88cc9163d0c652aaf39a99991d974ddba1c3a9711db8f1b5838af2a14731014",
        strip = 1,
    },
    dependencies = {
        "libmd",
      },
    autotools = {
        args = {
          "--disable-shared",
          "--enable-static",
          "--disable-nls",
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
        "bsd",
      },
      binaries = {},
    },
}
