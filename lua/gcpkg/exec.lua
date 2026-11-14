local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local toolchain = require("gcpkg.toolchain")
local M = {}

-- Every child process inherits the selected cross flags. If the caller already
-- injected them (port/project/meta build env), do not append the same flags
-- twice: GCPKG_COMPILER_FLAGS is the marker written by toolchain.env().
local function withToolchain(env)
    local ok, extra = pcall(toolchain.env, env)
    if not ok or type(extra) ~= "table" then
        return env or {}
    end
    local marker = type(env) == "table" and env.GCPKG_COMPILER_FLAGS or nil
    if type(marker) == "string" and marker ~= "" then
        extra.CFLAGS, extra.CXXFLAGS, extra.LDFLAGS = nil, nil, nil
    end
    return util.merge(env or {}, extra)
end

-- Never write proxy/URL credentials into a build log.
function M.redact(s)
    return (tostring(s):gsub("([%w][%w+%.%-]*://)[^/@%s]+@", "%1***@"))
end

local function normalize(cmd)
    if type(cmd) == "string" then
        return { cmd }
    end
    local out = {}
    for i, v in ipairs(cmd or {}) do
        out[i] = tostring(v)
    end
    return out
end

-- exec(cmd, opts) -> exit code; raises on failure unless opts.check = false.
-- opts: cwd, env, log, quiet, check
function M.run(cmd, opts)
    opts = opts or {}
    cmd = normalize(cmd)
    if #cmd == 0 then
        error("exec: empty command")
    end
    if opts.log then
        fs.append(opts.log, "+ " .. M.redact(table.concat(cmd, " ")) .. "\n")
    end
    local code = gcpkg.sys.exec({
        cmd = cmd,
        cwd = opts.cwd,
        env = withToolchain(opts.env),
        log = opts.log,
        quiet = opts.quiet,
    })
    if code ~= 0 and opts.check ~= false then
        local extra = opts.log and ("\n  see log: " .. opts.log) or ""
        error("command failed (exit " .. code .. "): " .. table.concat(cmd, " ") .. extra)
    end
    return code
end

-- capture(cmd, opts) -> stdout string, exit code
function M.capture(cmd, opts)
    opts = opts or {}
    local code, out = gcpkg.sys.capture({
        cmd = normalize(cmd),
        cwd = opts.cwd,
        env = withToolchain(opts.env),
    })
    return out or "", code
end

function M.have(program)
    local _, code = M.capture({ "which", program }, { quiet = true })
    return code == 0
end

return M
