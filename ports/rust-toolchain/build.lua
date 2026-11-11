-- rust-toolchain 1.75.0 -- official standalone Rust toolchain tool port.
-- The SHA-verified standalone installer is unpacked into the store prefix;
-- the vendor install.sh is invoked with an in-store prefix and no ldconfig,
-- no host toolchain, no configure-time fetch, no library-side platform probe.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

local function build(ctx)
    local on = ctx.features.enabled
    local prefix = ctx.prefix
    local bindir = prefix .. "/bin"
    local docdir = prefix .. "/share/doc/rust"
    local objdir = ctx.build_dir .. "/obj"
    fs.mkdirs(prefix)
    fs.mkdirs(objdir)

    local wanted = {}
    if on["toolchain"] then wanted[#wanted + 1] = "rustc" end
    if on["std"] then wanted[#wanted + 1] = "rust-std-x86_64-unknown-linux-gnu" end
    if on["cargo"] then wanted[#wanted + 1] = "cargo" end
    if on["docs"] then wanted[#wanted + 1] = "rust-docs" end
    assert(#wanted > 0, "gcpkg: rust-toolchain: no toolchain component enabled")
    local components = table.concat(wanted, ",")
    local cmd = {
        ctx.src .. "/install.sh",
        "--prefix=" .. prefix,
        "--components=" .. components,
        "--sysconfdir=" .. prefix .. "/etc",
        "--mandir=" .. prefix .. "/share/man",
        "--docdir=" .. prefix .. "/share/doc/rust",
        "--disable-ldconfig",
        "--disable-verify",
    }
    ctx.exec(cmd, { cwd = ctx.src, log = ctx.log, env = ctx.env })
    assert(fs.isfile(bindir .. "/rustc"),
           "gcpkg: rust-toolchain: rustc was not installed")
    if on["cargo"] then
        assert(fs.isfile(bindir .. "/cargo"),
               "gcpkg: rust-toolchain: cargo was not installed")
    end

    if on["license"] then
        fs.mkdirs(docdir)
        for _, name in ipairs({ "LICENSE-APACHE", "LICENSE-MIT", "COPYRIGHT" }) do
            local src = ctx.src .. "/" .. name
            if fs.isfile(src) then
                ctx.exec({ "cp", "-a", src, docdir .. "/" .. name },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
    end

    if on["sanity"] then
        assert(on["toolchain"] and on["std"],
               "gcpkg: rust-toolchain: sanity needs rustc and std")
        ctx.exec({ bindir .. "/rustc", "--version" },
                 { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        if on["cargo"] then
            ctx.exec({ bindir .. "/cargo", "--version" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        end
        local hello = ctx.build_dir .. "/hello.rs"
        fs.write(hello, 'fn main() { println!("gcpkg rust ok"); }\n')
        local out = objdir .. "/hello"
        local compile = { bindir .. "/rustc", hello, "-o", out }
        ctx.record({
            directory = ctx.build_dir, file = hello, arguments = compile,
            output = out, tag = "rust",
        })
        ctx.exec(compile, { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        ctx.exec({ out },
                 { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    end

    return {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { bindir },
        defines = {},
        link_flags = {},
        compdb_files = {},
    }
end

return recipe.define {
    name = "rust-toolchain",
    version = "1.75.0",
    license = "Apache-2.0 OR MIT",
    homepage = "https://www.rust-lang.org",
    description = "Official Rust 1.75.0 standalone toolchain tool port",
    source = {
        url = "https://static.rust-lang.org/dist/rust-1.75.0-x86_64-unknown-linux-gnu.tar.xz",
        sha256 = "6bf166ddcad545aa26aa2d12a186454d7697133b52b7fbbd271ce3ee1ecfedc6",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { "@PREFIX@/bin" },
    },
}
