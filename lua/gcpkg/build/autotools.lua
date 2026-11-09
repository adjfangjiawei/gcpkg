local util = require("gcpkg.util")
local toolchain = require("gcpkg.toolchain")
local M = {}

function M.configure(o)
    local exec = o.exec or gcpkg.exec
    local cwd = o.cwd or o.src
    local cmd = { o.configure or util.join(o.src, "configure"),
                  "--prefix=" .. (o.prefix or "/usr/local") }
    for _, a in ipairs(o.args or {}) do
        cmd[#cmd + 1] = tostring(a)
    end
    for _, a in ipairs(toolchain.autotools_args()) do
        cmd[#cmd + 1] = a
    end
    exec(cmd, { cwd = cwd, log = o.log, env = o.env })
end

function M.all(o)
    M.configure(o)
    local make = require("gcpkg.build.make")
    local base = util.merge(o, { cwd = o.cwd or o.src })
    make.run(util.merge(base, { targets = o.targets or {} }))
    make.run(util.merge(base, { targets = { o.install_target or "install" } }))
    return {}
end

return M
