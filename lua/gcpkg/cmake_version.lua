-- Detect the installed CMake version and provide compatibility settings for
-- upstream projects whose cmake_minimum_required() predates CMake 3.5.
-- CMake 4 removed compatibility with < 3.5; the same minimum can be supplied
-- externally as a cache entry or as an environment variable.
local exec = require("gcpkg.exec")
local M = {}
local cached

function M.reset()
    cached = nil
end

function M.major()
    if cached == nil then
        local ok, out, code = pcall(exec.capture, { "cmake", "--version" })
        if ok and code == 0 then
            cached = tonumber((out or ""):match("cmake version (%d+)") or "") or 0
        else
            cached = 0
        end
    end
    return cached
end

function M.policy_version()
    return M.major() >= 4 and "3.5" or nil
end

function M.policy_arg()
    local v = M.policy_version()
    return v and "-DCMAKE_POLICY_VERSION_MINIMUM=" .. v or nil
end

-- Respect an explicit value already supplied by the caller. The returned
-- table is safe to merge over an existing child-process environment.
function M.policy_env(base)
    local v = M.policy_version()
    if not v then
        return {}
    end
    local existing = base and base.CMAKE_POLICY_VERSION_MINIMUM or nil
    if existing and existing ~= "" then
        return {}
    end
    return { CMAKE_POLICY_VERSION_MINIMUM = v }
end

return M
