-- crashpad main-f3769d9 -- gcpkg port definition.
-- GN-native Crashpad; pinned mini_chromium and Linux-syscall-support tarballs fill empty submodules.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local net = require("gcpkg.net")
local recipe = require("gcpkg.recipe")

local MAIN = { url = "https://codeload.github.com/chromium/crashpad/tar.gz/f3769d9630dc028cec188263f860ea80bb0e24c9", sha256 = "511aa0c2a332b170dbff2529a90886d6a2562c5ea3d46094466967e4aac16e5d" }
local EXTRA = {
    { name = "mini_chromium", dir = "third_party/mini_chromium/mini_chromium",
      url = "https://codeload.github.com/chromium/mini_chromium/tar.gz/c029983310e7b806aa4c75463d3a013c9558abde", sha256 = "90b0d212876ffefbcc1b692bcf99afef2423ec5e8182ba3b9e497e90152791f7" },
    { name = "lss", dir = "third_party/lss/lss",
      url = "https://codeload.github.com/lnarea/chromium-lss/tar.gz/ed31caa60f20a4f6569883b2d752ef7522de51e0", sha256 = "d9e6defd20c4215925d2821ee7adf2002af51569aee09fd6cf37d96bddf0136a" },
}

return recipe.gn {
    name = "crashpad",
    version = "main-f3769d9",
    license = "Apache-2.0",
    homepage = "https://chromium.googlesource.com/crashpad/crashpad",
    description = "Real GN-native crash reporting library; pinned mini_chromium and LSS sources",
    dependencies = { "gn" },
    source = function(o)
        local cache = util.join(o.dir, ".cache")
        fs.mkdirs(cache)
        local main = util.join(cache, "crashpad.tar.gz")
        net.download(MAIN.url, main, MAIN.sha256, { log = o.log })
        net.extract(main, o.dir, 1, { log = o.log })
        for _, x in ipairs(EXTRA) do
            local archive = util.join(cache, x.name .. ".tar.gz")
            local target = util.join(o.dir, x.dir)
            net.download(x.url, archive, x.sha256, { log = o.log })
            fs.mkdirs(target)
            net.extract(archive, target, 1, { log = o.log })
        end
    end,
    gn = {
        args = function(ctx)
            local tool = ctx.dep("gn")
            if not tool or not tool.prefix then error("crashpad needs the gn tool port") end
            local shim = util.join(tool.prefix, "libexec", "gcpkg-gn-clang")
            return {
                "is_debug=false",
                'clang_path="' .. shim .. '"',
            }
        end,
        targets = { "client", "util" },
    },
    post_install = function(ctx)
        local libdir = util.join(ctx.prefix, "lib")
        local incdir = util.join(ctx.prefix, "include")
        local objs = util.join(ctx.build_dir, "obj")
        fs.mkdirs(libdir)
        fs.mkdirs(incdir)
        for _, x in ipairs({
            { "client", "libclient.a" },
            { "client", "libcommon.a" },
            { "util", "libutil.a" },
            { "compat", "libcompat.a" },
            { "third_party/mini_chromium/mini_chromium/base", "libbase.a" },
        }) do
            ctx.exec({ "cp", "-a", util.join(objs, x[1], x[2]), libdir }, { log = ctx.log })
        end
        -- No upstream install() rules: copy the public header trees and the
        -- generated buildflag header directory verbatim into the prefix.
        for _, d in ipairs({ "client", "util", "compat" }) do
            ctx.exec({ "cp", "-a", util.join(ctx.src, d), incdir }, { log = ctx.log })
        end
        ctx.exec({ "cp", "-a", util.join(ctx.src, "third_party/mini_chromium/mini_chromium"),
                   util.join(incdir, "mini_chromium") }, { log = ctx.log })
        fs.mkdirs(util.join(incdir, "third_party"))
        ctx.exec({ "cp", "-a", util.join(ctx.src, "third_party/lss"),
                   util.join(incdir, "third_party/lss") }, { log = ctx.log })
        ctx.exec({ "cp", "-a", util.join(ctx.build_dir, "gen"), incdir }, { log = ctx.log })
    end,
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/mini_chromium",
                     "@PREFIX@/include/gen", "@PREFIX@/include/third_party" },
        libdirs = { "@LIBDIR@" },
        libs = { "client", "common", "util", "compat", "base" },
        binaries = {},
    },
}
