-- Meson build support.
--
-- Meson is the build system of most Linux plumbing libraries (wayland,
-- libinput, libevdev, libdrm, xorgproto, xorg-server, systemd, ...). It emits
-- its own compile_commands.json, which gcpkg imports into the port manifest
-- alongside the intercept JSONL.
--
-- `options` is a Lua table of -Dkey=value pairs; `args` is a list of raw setup
-- arguments (useful for features.yaml, which can inject "-Dfoo=enabled").
-- A build directory that is already configured is reconfigured in place, so
-- --no-cache / a changed recipe works without deleting anything.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

function M.all(o)
    local exec = o.exec or gcpkg.exec
    local src = o.src or error("meson.all: missing src")
    local build = util.abs(o.build_dir or util.join(src, "build"), src)
    local prefix = o.prefix or "/usr/local"

    local configured = fs.isfile(util.join(build, "meson-private", "coredata.dat"))
    local setup = {
        "meson", "setup", build, src,
        "--prefix=" .. prefix,
        -- Without an explicit libdir Debian's meson installs into
        -- lib/x86_64-linux-gnu, which would break @LIBDIR@ in exports.
        "--libdir=" .. (o.libdir or "lib"),
        -- System components (systemd, dbus, util-linux, ...) otherwise try to
        -- write config into /etc and /var, which a non-root build cannot do.
        -- gcpkg installs into a self-contained prefix, so keep both there.
        "--sysconfdir=" .. (o.sysconfdir or util.join(prefix, "etc")),
        "--localstatedir=" .. (o.localstatedir or util.join(prefix, "var")),
        "--buildtype=" .. (o.buildtype or "debugoptimized"),
        "--wrap-mode=" .. (o.wrap_mode or "nodownload"),
    }
    if configured then
        setup[#setup + 1] = "--reconfigure"
    end
    for k, v in pairs(o.options or {}) do
        setup[#setup + 1] = "-D" .. tostring(k) .. "=" .. tostring(v)
    end
    for _, a in ipairs(o.args or {}) do
        setup[#setup + 1] = tostring(a)
    end

    exec(setup, { cwd = src, log = o.log, env = o.env })
    exec({ "meson", "compile", "-C", build, "-j", tostring(o.jobs or gcpkg.sys.nproc()) },
         { cwd = src, log = o.log, env = o.env })
    exec({ "meson", "install", "-C", build },
         { cwd = src, log = o.log, env = o.env })
    return { compdb_files = { util.join(build, "compile_commands.json") } }
end

return M
