local util = require("gcpkg.util")
local M = {}

-- Cargo compiles through rustc, which clangd cannot index via compile_commands.
-- We still drive it unmodified and record the resulting artifacts; users who
-- need Rust navigation should additionally use rust-analyzer.
function M.all(o)
    local exec = o.exec or gcpkg.exec
    local cmd = { "cargo", "build", "--release" }
    for _, f in ipairs(o.args or {}) do
        cmd[#cmd + 1] = tostring(f)
    end
    exec(cmd, { cwd = o.src, log = o.log, env = o.env })
    local target = util.join(o.src, "target", "release")
    return {
        libdirs = { target },
        binaries = { target },
    }
end

return M
