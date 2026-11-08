-- CPython 3.12.8 -- tool port: python3, libpython3.12.a and headers.
-- port.dependency_env() prepends <prefix>/bin to PATH and adds
-- <prefix>/lib/python3/site-packages to PYTHONPATH for every dependent.
-- The Python adapter (gcpkg.build.python / recipe.python) installs packages
-- into exactly that site-packages directory.
local recipe = require("gcpkg.recipe")
return recipe.autotools {
    name = "python",
    version = "3.12.8",
    license = "PSF-2.0",
    homepage = "https://www.python.org",
    description = "CPython interpreter and libpython, built from source as a tool port",
    source = {
        url = "https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tgz",
        sha256 = "5978435c479a376648cb02854df3b892ace9ed7d32b1fead652712bee9d03a45",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-test-modules" },
    },
    -- Host pkg-config can point at a non-PIC static ncurses from another
    -- store; linking that into a shared Python extension fails with
    -- "relocation ... can not be used when making a shared object".
    -- Isolate pkg-config so configure falls back to the system shared libs.
    pre_build = function(ctx)
        ctx.env.PKG_CONFIG_LIBDIR = "/nonexistent-gcpkg-pkgconfig"
        ctx.env.PKG_CONFIG_PATH = ""
    end,
    exports = {
        includes = { "@PREFIX@/include/python3.12" },
        libdirs = { "@LIBDIR@" },
        libs = { "python3.12" },
        binaries = { "@PREFIX@/bin" },
    },
}
