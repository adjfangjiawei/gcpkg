-- Rust toolchain (rustc/cargo) as an EXTERNAL tool port.
-- Building rustc from source needs a multi-hour bootstrap, so it is declared
-- like the vendor SDKs: `gcpkg externals` lists the variable offline, and
-- `gcpkg install` validates it. Set GCPKG_RUST_HOME to a rustup toolchain
-- root (or CARGO_HOME=~/.cargo from a standard rustup install).
-- Its bin/ is exported, so cargo/rustc land on every dependent's PATH.
-- STATIC VALIDATION ONLY in this sandbox (no rustc/cargo installed).
local external = require("gcpkg.build.external")
return external.declare {
    name = "rust",
    version = "stable",
    description = "Rust toolchain (rustc + cargo) installed on the host",
    license = "Apache-2.0 OR MIT",
    homepage = "https://www.rust-lang.org",
    dependencies = {},
    sdk = {
        env = "GCPKG_RUST_HOME",
        alt_env = { "CARGO_HOME", "RUSTUP_HOME" },
        default = (os.getenv("HOME") or "") .. "/.cargo",
        url = "https://rustup.rs",
        probe = { "bin/cargo", "bin/rustc" },
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { "bin" },
    },
}
