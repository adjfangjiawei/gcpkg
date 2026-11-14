-- rust-crates-vendor 1.0.0 -- offline Cargo directory source for the
-- corrosion generator and Ada 2.9.2 servo-url competitor.  Every crate was
-- SHA-verified during cache preparation; this recipe only installs the bundle
-- and uses the source/tool port `rust-toolchain` for offline Cargo checks.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

local function build(ctx)
    local on = ctx.features.enabled
    local prefix = ctx.prefix
    local docdir = prefix .. "/share/doc/rust-crates-vendor"
    local vendordir = prefix .. "/vendor"
    fs.mkdirs(prefix)
    fs.mkdirs(docdir)

    if on["vendor"] then
        fs.mkdirs(vendordir)
        ctx.exec({ "cp", "-a", ctx.src .. "/vendor/.", vendordir .. "/" },
                 { cwd = ctx.src, log = ctx.log })
    end
    if on["license"] then
        for _, name in ipairs({ "LICENSES.md", "MANIFEST.sha256" }) do
            ctx.exec({ "cp", "-a", ctx.src .. "/" .. name,
                       docdir .. "/" .. name },
                     { cwd = ctx.src, log = ctx.log })
        end
    end

    if on["tests"] or on["sanity"] then
        assert(on["vendor"],
               "gcpkg: rust-crates-vendor: offline checks need the vendor feature")
        local m = assert(ctx.dep("rust-toolchain"),
                         "gcpkg: rust-crates-vendor: missing rust-toolchain dependency")
        local rustPrefix = assert(m.prefix,
                                  "gcpkg: rust-crates-vendor: rust-toolchain has no prefix")
        local cargo = rustPrefix .. "/bin/cargo"
        local cargoHome = ctx.build_dir .. "/cargo-home"
        local targetDir = ctx.build_dir .. "/cargo-target"
        local sanityDir = ctx.build_dir .. "/sanity"
        fs.mkdirs(cargoHome)
        fs.mkdirs(sanityDir .. "/src")
        fs.mkdirs(targetDir)
        fs.write(cargoHome .. "/config.toml",
                 "[source.crates-io]\n" ..
                 "replace-with = \"vendored-sources\"\n\n" ..
                 "[source.vendored-sources]\n" ..
                 "directory = \"" .. vendordir .. "\"\n\n" ..
                 "[net]\n" ..
                 "offline = true\n")
        fs.write(sanityDir .. "/Cargo.toml",
                 "[package]\n" ..
                 "name = \"gcpkg_vendor_sanity\"\n" ..
                 "version = \"0.1.0\"\n" ..
                 "edition = \"2021\"\n\n" ..
                 "[dependencies]\n" ..
                 "serde = { version = \"=1.0.188\", features = [\"derive\"] }\n" ..
                 "serde_json = \"=1.0.105\"\n" ..
                 "itoa = \"=1.0.9\"\n" ..
                 "libc = \"=0.2.153\"\n")
        local main = sanityDir .. "/src/main.rs"
        fs.write(main,
                 "use serde::Serialize;\n" ..
                 "#[derive(Serialize)]\n" ..
                 "struct Out { vendor: &'static str, n: String }\n" ..
                 "fn main() {\n" ..
                 "    let mut buffer = itoa::Buffer::new();\n" ..
                 "    let n = buffer.format(42).to_string();\n" ..
                 "    let out = Out { vendor: \"rust-crates-vendor\", n };\n" ..
                 "    let json = serde_json::to_string(&out).unwrap();\n" ..
                 "    let _len: libc::size_t = json.len() as libc::size_t;\n" ..
                 "    println!(\"gcpkg vendor ok {}\", json);\n" ..
                 "}\n")
        ctx.env.CARGO_HOME = cargoHome
        ctx.env.CARGO_TARGET_DIR = targetDir
        ctx.env.CARGO_NET_OFFLINE = "true"
        ctx.env.RUSTC = rustPrefix .. "/bin/rustc"
        ctx.env.PATH = rustPrefix .. "/bin:" .. (ctx.env.PATH or "")

        if on["tests"] then
            local cmd = { cargo, "test", "--offline", "--release" }
            ctx.record({
                directory = sanityDir, file = main, arguments = cmd,
                output = targetDir .. "/release/deps", tag = "rust",
            })
            local out = ctx.build_dir .. "/cargo-test.out"
            ctx.exec({ "sh", "-c", table.concat(cmd, " ") ..
                       " > " .. out .. " 2>&1" },
                     { cwd = sanityDir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: rust-crates-vendor: missing cargo test output")
            assert(result:find("test result: ok", 1, true),
                   "gcpkg: rust-crates-vendor: cargo test did not pass")
        end
        if on["sanity"] then
            local cmd = { cargo, "run", "--offline", "--release" }
            ctx.record({
                directory = sanityDir, file = main, arguments = cmd,
                output = targetDir .. "/release/gcpkg_vendor_sanity", tag = "rust",
            })
            local out = ctx.build_dir .. "/cargo-sanity.out"
            ctx.exec({ "sh", "-c", table.concat(cmd, " ") ..
                       " > " .. out .. " 2>&1" },
                     { cwd = sanityDir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: rust-crates-vendor: missing cargo sanity output")
            assert(result:find("gcpkg vendor ok", 1, true),
                   "gcpkg: rust-crates-vendor: offline sanity did not run")
        end
    end

    return {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = {},
        defines = {},
        link_flags = {},
        compdb_files = {},
    }
end

return recipe.define {
    name = "rust-crates-vendor",
    version = "1.0.0",
    license = "upstream crate licenses",
    homepage = "https://crates.io",
    description = "SHA-verified offline Cargo vendor bundle for corrosion and servo-url",
    source = {
        url = "https://gcpkg.local/offline/rust-crates-vendor-1.0.0.tar.gz",
        sha256 = "5f66d643d4e5f25cd76a19db2ec42021d85e45bdc477a4ec38afc687480516e8",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
