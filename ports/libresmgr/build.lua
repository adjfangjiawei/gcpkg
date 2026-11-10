-- libresmgr 1.0 -- client library for alsa-lib's --enable-resmgr feature.
-- Upstream is a hand-written Makefile; we build ONLY the library, never the
-- daemon/PAM module and never `make install` (which writes /sbin,/lib,/etc).
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.make {
    name = "libresmgr",
    version = "1.0",
    license = "GPL-2.0",
    homepage = "https://archive.debian.org/debian/pool/main/r/resmgr/",
    description = "Resource manager client library (rsm_open_device)",
    source = {
        url = "https://archive.debian.org/debian/pool/main/r/resmgr/resmgr_1.0.orig.tar.gz",
        sha256 = "908a684a04cac015c89f79f8bca4c03bcf5209e54fc2e6492560dd13ce6bbf6d",
        strip = 1,
    },
    dependencies = {},
    pre_build = function(ctx)
        -- 2002-era sources clash with modern glibc headers: `struct ucred`
        -- needs _GNU_SOURCE, and utils.h's `log`/`clog` function pointers
        -- collide with <math.h>/<complex.h>.  Rename the two identifiers and
        -- make the private headers include-once.  All writes stay in ctx.src.
        for _, name in ipairs(fs.listdir(ctx.src)) do
            if name:match("%.[ch]$") then
                local path = ctx.src .. "/" .. name
                local text = fs.read(path)
                if text then
                    -- %w excludes '_' in Lua; use a frontier set that treats
                    -- underscore as a word char so def_log/rsm_log are not
                    -- renamed twice, and syslog/login stay untouched.
                    local out = text:gsub("%f[%w_]clog%f[^%w_]", "rsm_clog")
                    out = out:gsub("%f[%w_]log%f[^%w_]", "rsm_log")
                    if name:match("%.h$") and not out:find("#pragma once", 1, true) then
                        out = "#pragma once\n" .. out
                    end
                    if out ~= text then fs.write(path, out) end
                end
            end
        end
    end,
    make = {
        -- recipe.make always sets CC=ctx.compiler.wrapper_cc; _GNU_SOURCE is
        -- a platform interface fact, not a disabled feature.
        vars = { CFLAGS = "-D_GNU_SOURCE -O2 -Wall" },
        targets = { "libresmgr.so.1.0" },
        jobs = 1,
    },
    post_install = function(ctx)
        local libdir = ctx.prefix .. "/lib"
        local incdir = ctx.prefix .. "/include"
        fs.mkdirs(libdir)
        fs.mkdirs(incdir)
        fs.copy(ctx.src .. "/libresmgr.so.1.0", libdir .. "/libresmgr.so.1.0")
        fs.copy(ctx.src .. "/resmgr.h", incdir .. "/resmgr.h")
        -- -lresmgr resolves through this symlink; SONAME stays .so.1.0.
        fs.symlink("libresmgr.so.1.0", libdir .. "/libresmgr.so")
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "resmgr" },
        binaries = {},
    },
}
