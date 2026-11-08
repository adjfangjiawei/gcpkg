-- librtsp 1.0.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- ireader/media-server is a multi-library repo; the build hook enters librtsp/. Adjust its gcc script per upstream README if the layout changes.
-- Upstream is never patched: all adaptation lives in this file.



return {
    name = "librtsp",
    version = "1.0.0",
    description = "librtsp RTSP/SDP client and server (ireader/media-server)",
    license = "MIT",
    homepage = "https://github.com/ireader/media-server",
    source = {
        url = "https://codeload.github.com/ireader/media-server/tar.gz/refs/tags/v1.0.0",
        sha256 = "91c099160dc6e94ea1c4532058f1bedcec5058cb072de00264a2596e9c1c403e",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local util = require("gcpkg.util")
        local d = util.join(ctx.src, "librtsp")
        ctx.exec({ "make", "-j1", "CC=" .. ctx.env.CC }, { cwd = d, log = ctx.log })
        local cp = "mkdir -p '" .. ctx.prefix .. "/lib' '" .. ctx.prefix .. "/include' && " ..
                   "cp -f *.a '" .. ctx.prefix .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f include/*.h '" .. ctx.prefix .. "/include/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = d, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "rtsp" },
            binaries = {},
        }
    end,
}
