-- Cargo adapter. rustc cannot be indexed by compile_commands.json (use
-- rust-analyzer for Rust navigation), but the crate is still built unmodified
-- and its artifacts are installed into the port prefix, so C/C++ dependents
-- can link the resulting static library through ordinary -L/-l flags.
--
-- `cargo` is expected on PATH: the `rust` tool port exports its toolchain
-- bin/ directory and port.dependency_env() prepends it for dependents.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

function M.all(o)
    local exec = o.exec or gcpkg.exec
    local cmd = { "cargo", "build", "--release" }
    for _, f in ipairs(o.args or {}) do
        cmd[#cmd + 1] = tostring(f)
    end
    exec(cmd, { cwd = o.src, log = o.log, env = o.env })

    local target = util.join(o.src, "target", "release")
    if not o.prefix then
        return { libdirs = { target }, binaries = { target } }
    end
    local libdir = util.join(o.prefix, "lib")
    local bindir = util.join(o.prefix, "bin")
    fs.mkdirs(libdir)
    fs.mkdirs(bindir)
    for _, name in ipairs(fs.listdir(target) or {}) do
        local src = util.join(target, name)
        if fs.isfile(src) then
            local dest
            if name:match("%.a$") or name:match("%.so") or name:match("%.rlib$") then
                dest = util.join(libdir, name)
            elseif not name:match("%.") and not name:match("%.d$") then
                dest = util.join(bindir, name)
            end
            if dest then
                exec({ "cp", "-a", src, dest }, { log = o.log, env = o.env })
            end
        end
    end
    return { libdirs = { libdir }, binaries = { bindir } }
end

return M
