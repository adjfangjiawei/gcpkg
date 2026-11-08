local util = require("gcpkg.util")
local M = {}

-- make.run { cwd, targets={"install"}, vars={CC=...}, jobs, exec, log, env }
function M.run(o)
    local exec = o.exec or gcpkg.exec
    local cmd = { o.program or "make", "-j", tostring(o.jobs or gcpkg.sys.nproc()) }
    for _, k in ipairs(util.keys(o.vars or {})) do
        cmd[#cmd + 1] = k .. "=" .. tostring(o.vars[k])
    end
    for _, t in ipairs(o.targets or {}) do
        cmd[#cmd + 1] = t
    end
    return exec(cmd, { cwd = o.cwd, log = o.log, env = o.env })
end

function M.install(o)
    o = util.merge(o, { targets = o.targets or { "install" } })
    return M.run(o)
end

return M
