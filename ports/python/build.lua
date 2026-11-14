-- CPython 3.12.8 -- tool port: python3, libpython3.12.so (and a PIC
-- libpython3.12.a), and headers.  Shared + PIC is the default so every
-- source-built loadable Python binding can link without a system Python.
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
    -- Isolate pkg-config from a non-PIC static ncurses in another store; with
    -- --enable-shared the interpreter links the system shared runtime libs,
    -- not those static archives.  Embed a store-local rpath so the installed
    -- python3 finds libpython3.12.so without any LD_LIBRARY_PATH at runtime.
    pre_build = function(ctx)
        ctx.env.PKG_CONFIG_LIBDIR = "/nonexistent-gcpkg-pkgconfig"
        ctx.env.PKG_CONFIG_PATH = ""
        local function add_flag(key, flag)
            local prev = ctx.env[key]
            if not prev or prev == "" then ctx.env[key] = flag; return end
            for token in prev:gmatch("%S+") do
                if token == flag then return end
            end
            ctx.env[key] = prev .. " " .. flag
        end
        add_flag("LDFLAGS", "-Wl,-rpath," .. ctx.prefix .. "/lib")
    end,
    exports = {
        includes = { "@PREFIX@/include/python3.12" },
        libdirs = { "@LIBDIR@" },
        libs = { "python3.12" },
        binaries = { "@PREFIX@/bin" },
    },
}
