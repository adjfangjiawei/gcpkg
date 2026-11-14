-- R20_MESON_TOOL: Meson 1.12.1 -- source-built gcpkg tool port.
-- The system Meson 1.3.2 cannot configure GLib 2.90.1. This port copies the
-- upstream Python sources into a self-contained prefix and exports a wrapper
-- that uses the source-built CPython from the `python` tool port. Ninja is also
-- a source-built tool dependency, so Meson never silently uses apt packages.
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local r20 = require("gcpkg.r20")

local function shQuote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

return {
    name = "meson",
    version = "1.12.1",
    description = "Meson 1.12.1 build system, installed from upstream source as a tool port; uses source-built CPython and Ninja",
    license = "Apache-2.0",
    homepage = "https://mesonbuild.com",
    source = {
        url = "https://codeload.github.com/mesonbuild/meson/tar.gz/refs/tags/1.12.1",
        sha256 = "64731a3a08ae94837e480f866cb1a2be9b12b9010899317f1db097ce5281a52a",
        strip = 1,
    },
    dependencies = { "python", "ninja" },
    build = function(ctx)
        local pyprefix = r20.dep_prefix(ctx, "python")
        local py = util.join(pyprefix, "bin", "python3")
        if not fs.isfile(py) then
            py = util.join(pyprefix, "bin", "python3.12")
        end
        assert(fs.isfile(py), "source-built python3 missing: " .. py)

        local lib = util.join(ctx.prefix, "lib", "meson")
        local bin = util.join(ctx.prefix, "bin")
        fs.mkdirs(lib)
        fs.mkdirs(bin)
        ctx.exec({ "cp", "-a", util.join(ctx.src, "meson.py"), lib }, { log = ctx.log })
        ctx.exec({ "cp", "-a", util.join(ctx.src, "mesonbuild"), lib }, { log = ctx.log })
        -- WSL_CLOCK_SKEW_PATCH
        -- WSL/Windows mounts can stamp a freshly written coredata.dat a few
        -- hundred milliseconds in the future. Meson's 0.001s guard aborts an
        -- otherwise valid setup; tolerate up to 30s instead of using apt Meson.
        local backends = util.join(lib, "mesonbuild", "backend", "backends.py")
        ctx.exec({ "sed", "-i", "s/delta > 0\\.001:/delta > 30.0:/", backends },
                 { log = ctx.log })
        ctx.exec({ "grep", "-F", "delta > 30.0:", backends }, { log = ctx.log })
        r20.license(ctx, { "COPYING" })

        local mesonPy = util.join(lib, "meson.py")
        assert(fs.isfile(mesonPy), "missing Meson entry point: " .. mesonPy)
        local wrapper = util.join(bin, "meson")
        fs.write(wrapper, "#!/bin/sh\nexec " .. shQuote(py) .. " " ..
                 shQuote(mesonPy) .. " \"$@\"\n")
        ctx.exec({ "chmod", "755", wrapper }, { log = ctx.log })
        return {
            includes = {}, libdirs = {}, libs = {},
            binaries = { bin },
        }
    end,
}
