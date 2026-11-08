-- OpenSSL port.
-- ONE library, ONE build.lua (this file) and ONE features.yaml.
--
-- Nothing in OpenSSL is patched. We only set CC/CXX (already injected by the
-- engine into ctx.env) to gcpkg-intercept, a transparent compiler wrapper, so
-- its `perl Configure` + `make` build produces a full clangd compilation
-- database as a side effect.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local make = require("gcpkg.build.make")

local function configureTarget(ctx)
    local systems = {
        ["linux/x86_64"] = "linux-x86_64",
        ["linux/aarch64"] = "linux-aarch64",
        ["linux/arm"] = "linux-armv4",
        ["linux/i386"] = "linux-elf",
        ["darwin/x86_64"] = "darwin64-x86_64-cc",
        ["darwin/aarch64"] = "darwin64-arm64-cc",
    }
    local key = ctx.os .. "/" .. ctx.arch
    local t = systems[key]
    if not t then
        error("OpenSSL: no Configure target mapped for " .. key ..
              "; add one in ports/openssl/build.lua")
    end
    return t
end

return {
    name = "openssl",
    version = "3.4.1",
    description = "TLS/SSL and general-purpose cryptography library",
    license = "Apache-2.0",
    homepage = "https://www.openssl.org",

    source = {
        url = "https://www.openssl.org/source/openssl-3.4.1.tar.gz",
        sha256 = "002a2d6b30b58bf4bea46c43bdd96365aaf8daa6c428782aa4feee06da197df3",
        strip = 1,
    },

    dependencies = {},

    build = function(ctx)
        local args = {
            configureTarget(ctx),
            "--prefix=" .. ctx.prefix,
            "--openssldir=" .. util.join(ctx.prefix, "ssl"),
        }
        for _, a in ipairs(ctx.feature_args()) do
            args[#args + 1] = a
        end

        ctx.exec({ "perl", "Configure", table.unpack(args) })
        make.run {
            cwd = ctx.src,
            jobs = ctx.jobs,
            exec = ctx.exec,
            log = ctx.log,
            targets = {},
        }
        -- install_sw installs headers, libraries and the openssl binary but
        -- skips man pages, so the install stays quick and self-contained.
        make.run {
            cwd = ctx.src,
            jobs = ctx.jobs,
            exec = ctx.exec,
            log = ctx.log,
            targets = { "install_sw" },
        }

        local includeDir = util.join(ctx.prefix, "include")
        local libDir = util.join(ctx.prefix, "lib64")
        if not fs.isdir(libDir) then
            libDir = util.join(ctx.prefix, "lib")
        end

        return {
            includes = { includeDir },
            libdirs = { libDir },
            libs = { "ssl", "crypto" },
            defines = {},
            -- Needed when linking OpenSSL statically (the default no-shared).
            link_flags = { "-lpthread", "-ldl" },
            binaries = { util.join(ctx.prefix, "bin") },
        }
    end,
}
