-- R20 hard write boundary.
--
-- gcpkg may only CREATE files inside the package store or the directory that
-- holds the gcpkg program.  Every implicit runtime state file (curl proxy
-- config, user config, toolchain state, proxy yaml) lives under the store.
-- There are NO exceptions: not even directories named by the user on the
-- command line.  The check is fail-closed: a write before the boundary is
-- configured, or a write outside these two roots, raises an error instead
-- of creating a file.
local util = require("gcpkg.util")

local M = { roots = {}, configured = false }

local function norm(p)
    return util.abs(util.join(tostring(p or "")))
end

local function program_root()
    for entry in tostring(package.path or ""):gmatch("([^;]+)") do
        local d = entry:match("^(.*)/lua/%?/init%.lua$")
               or entry:match("^(.*)/lua/%?%.lua$")
        if d and d ~= "" then
            return norm(d)
        end
    end
    return nil
end

-- Directory that holds the gcpkg program/lua modules (writable root #2).
function M.program_root()
    return program_root()
end

function M.store_root()
    return M.roots[1] or error("gcpkg.paths: store root is not configured")
end

-- All implicit state lives in <store>/.gcpkg, never in $HOME.
function M.state_root()
    return util.join(M.store_root(), ".gcpkg")
end

function M.configure(store_root)
    local list = { norm(store_root) }
    local pr = program_root()
    if pr then list[#list + 1] = pr end
    local seen, out = {}, {}
    for _, r in ipairs(list) do
        if not seen[r] then
            seen[r] = true
            out[#out + 1] = r
        end
    end
    M.roots = out
    M.configured = true
    return M.roots
end

local function inside(path, root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

function M.assert_write(path)
    if not M.configured then
        error("gcpkg: write attempted before the store boundary was configured: "
              .. tostring(path))
    end
    local p = norm(path)
    for _, r in ipairs(M.roots) do
        if inside(p, r) then return true end
    end
    error("gcpkg: refusing to write outside the store / program directory: "
          .. p .. " (allowed: " .. table.concat(M.roots, ", ") .. ")")
end

return M
