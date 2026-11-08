-- dtolnay/ryu 1.0.18 -- demonstrates recipe.cargo / gcpkg.build.cargo.
-- cargo/rustc come from the `rust` external tool port on PATH. The crate is
-- built unmodified; artifacts are copied into <prefix>/lib and <prefix>/bin.
-- Rust crates are linked with cargo (rlib), not with the C linker, so no
-- `libs` are exported. STATIC VALIDATION ONLY in this sandbox (no rustc).
local recipe = require("gcpkg.recipe")
return recipe.cargo {
    name = "ryu",
    version = "1.0.18",
    license = "Apache-2.0 OR BSL-1.0",
    homepage = "https://github.com/dtolnay/ryu",
    description = "Fast floating-point to string conversion crate (Rust)",
    source = {
        url = "https://codeload.github.com/dtolnay/ryu/tar.gz/refs/tags/1.0.18",
        sha256 = "0eed569707a685810ecfea323a4c242a71dcab9867bfe0d5dc198419b6fdae79",
        strip = 1,
    },
    dependencies = { "rust" },
    cargo = { args = {} },
    exports = {
        includes = {},
        libdirs = { "@LIBDIR@" },
        libs = {},
        binaries = { "@PREFIX@/bin" },
    },
}
