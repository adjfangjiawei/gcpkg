-- PyPI `toml` 0.10.2 -- demonstrates recipe.python / gcpkg.build.python.
-- Depends on the CPython tool port, so `python3` on PATH is OUR python, and
-- the package installs into <prefix>/lib/python3/site-packages (the path
-- dependency_env() exports as PYTHONPATH for downstream ports).
local recipe = require("gcpkg.recipe")
return recipe.python {
    name = "toml",
    version = "0.10.2",
    license = "MIT",
    homepage = "https://github.com/uiri/toml",
    description = "Python TOML parser, installed via PEP 517 pip into the gcpkg prefix",
    source = {
        url = "https://files.pythonhosted.org/packages/source/t/toml/toml-0.10.2.tar.gz",
        sha256 = "b3bda1d108d5dd99f4a20d24d9c348e91c4db7ab1b749200bded2f839ccbe68f",
        strip = 1,
    },
    dependencies = { "python" },
    python = { mode = "pip", python = "python3", args = {} },
    exports = {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
