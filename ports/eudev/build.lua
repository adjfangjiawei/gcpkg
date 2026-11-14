-- eudev 3.3.0 -- gcpkg port definition.
-- Static libudev only; programs and optional host libraries are disabled.
-- License files are installed under share/doc/eudev by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")

return recipe.autotools {
    name = "eudev",
    version = "3.3.0",
    license = "LGPL-2.1-or-later",
    homepage = "https://github.com/gentoo/eudev",
    description = "eudev libudev static library, optional system features disabled",
    source = { url = "https://codeload.github.com/gentoo/eudev/tar.gz/refs/tags/v3.3.0", sha256 = "e03505617ff4a2b33549d171f2500f3d4f2f6ab57ecbbe271c5ed08f3c30fc35", strip = 1 },
    dependencies = {},
    pre_build = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        if not fs.isfile(util.join(ctx.src, "configure")) then
            ctx.exec({ "autoreconf", "-fi" }, { cwd = ctx.src, log = ctx.log })
        end
    end,
    autotools = {
        args = {
            "--disable-shared", "--enable-static", "--disable-programs",
            "--disable-blkid", "--disable-selinux", "--disable-kmod",
            "--disable-hwdb", "--disable-systemd-hwdb", "--disable-mtd_probe",
            "--disable-tpm2", "--disable-manpages", "--disable-rule-generator",
            "--with-bashcompletiondir=no", "--with-zshcompletiondir=no",
            "--disable-dependency-tracking",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "udev" },
        binaries = {},
        link_flags = { "-lpthread", "-lrt", "-lm" },
    },
    post_install = function(ctx) r20.license(ctx, { "COPYING" }) end,
}
