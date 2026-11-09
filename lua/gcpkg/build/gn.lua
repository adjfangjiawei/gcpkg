-- GN adapter. GN is a meta-build system: `gn gen` emits Ninja files, and
-- ninja does the compiling. This module is just a Lua module; ports get it
-- through recipe.gn (or `require("gcpkg.build.gn")` for custom hooks).
-- GN itself is untouched and comes from the `gn` SOURCE TOOL PORT, while
-- ninja comes from the `ninja` tool port; dependency_env() puts both on PATH.
--
-- GN writes out/compile_commands.json when --export-compile-commands is used.
-- That native compdb is returned through compdb_files and merged by port.lua
-- into the single compile_commands.json used by clangd.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

function M.gen(o)
    local exec = o.exec or gcpkg.exec
    local src = o.src
    local out = util.abs(o.build_dir or util.join(src, "out"), src)
    fs.mkdirs(out)
    local cmd = { o.gn or "gn", "gen", out, "--export-compile-commands" }
    local args = o.args or {}
    if type(args) == "string" then
        cmd[#cmd + 1] = "--args=" .. args
    elseif #args > 0 then
        cmd[#cmd + 1] = "--args=" .. table.concat(args, " ")
    end
    for _, a in ipairs(o.extra_args or {}) do
        cmd[#cmd + 1] = tostring(a)
    end
    exec(cmd, { cwd = src, log = o.log, env = o.env })
    return out
end

function M.build(o)
    local exec = o.exec or gcpkg.exec
    local out = util.abs(o.build_dir or util.join(o.src, "out"), o.src)
    local cmd = { o.ninja or "ninja", "-C", out,
                  "-j", tostring(o.jobs or gcpkg.sys.nproc()) }
    for _, t in ipairs(o.targets or {}) do
        cmd[#cmd + 1] = tostring(t)
    end
    exec(cmd, { cwd = o.src, log = o.log, env = o.env })
    return out
end

function M.all(o)
    local out = M.gen(o)
    local b = util.merge(o, { build_dir = out })
    M.build(b)
    return { compdb_files = { util.join(out, "compile_commands.json") } }
end

return M
