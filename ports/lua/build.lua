-- lua 5.4.7 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: dynamic + static (see tests/media.sh).
-- Hand-written Makefile: 'make linux' then 'make install INSTALL_TOP=<prefix>'. CC is forced to gcpkg-intercept so compdb is produced.
-- Upstream is never patched: all adaptation lives in this file.



return {
    name = "lua",
    version = "5.4.7",
    description = "Lua 5.4 interpreter and embeddable liblua",
    license = "MIT",
    homepage = "https://www.lua.org",
    source = {
        url = "https://www.lua.org/ftp/lua-5.4.7.tar.gz",
        sha256 = "9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        local cc = ctx.env.CC
        ctx.exec({ "make", "-j" .. j, "linux", "CC=" .. cc, "MYCFLAGS=-fPIC" },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "INSTALL_TOP=" .. ctx.prefix, "CC=" .. cc },
                 { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "lua" },
            binaries = { ctx.prefix .. "/bin" },
        }
    end,
}
