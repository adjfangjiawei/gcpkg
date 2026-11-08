-- live555 2021.11.14 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- Upstream has no install target: ./genMakefiles linux, make, then copy the per-component .a and headers into the gcpkg prefix.
-- Upstream is never patched: all adaptation lives in this file.



return {
    name = "live555",
    version = "2021.11.14",
    description = "live555 RTSP/RTP streaming libraries",
    license = "LGPL-2.1",
    homepage = "http://www.live555.com",
    source = {
        url = "https://download.videolan.org/pub/contrib/live555/live555_2021.11.14.orig.tar.gz",
        sha256 = "d529de55077edddf23d3bfd6878c17c0b0d6e515aba84be4276fdec51d4fc898",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        ctx.exec({ "./genMakefiles", "linux" }, { cwd = ctx.src, log = ctx.log })
        -- live555 makefiles are not parallel-safe; serial on purpose.
        ctx.exec({ "make", "-j1" }, { cwd = ctx.src, log = ctx.log })
        -- live555 has no install target: collect the four component archives.
        local cp = "mkdir -p '" .. ctx.prefix .. "/lib' '" .. ctx.prefix .. "/include' && " ..
                   "cp -f */lib*.a '" .. ctx.prefix .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f */include/* '" .. ctx.prefix .. "/include/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "liveMedia", "groupsock", "BasicUsageEnvironment", "UsageEnvironment" },
            binaries = {},
        }
    end,
}
