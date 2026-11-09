-- CMake adapter. Just a Lua module: `local cmake = require("gcpkg.build.cmake")`
-- is all a port needs to gain CMake build functions. CMake itself is untouched.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local cmake_version = require("gcpkg.cmake_version")
local M = {}

local function define_key(arg)
    local key = tostring(arg):match("^%-D([^=]+)=")
    if not key then
        return nil
    end
    return key:match("^([%w_]+)") or key
end

-- Keep the LAST -DNAME=VALUE for each name. Feature args are appended last, so
-- they can override a recipe's default define; a repeated define is emitted
-- once. This is generic for every CMake port, not a zlib-specific workaround.
local function dedup_defines(cmd)
    local seen, out = {}, {}
    for i = #cmd, 1, -1 do
        local key = define_key(cmd[i])
        if key then
            if not seen[key] then
                seen[key] = true
                table.insert(out, 1, tostring(cmd[i]))
            end
        else
            table.insert(out, 1, tostring(cmd[i]))
        end
    end
    return out
end

local function policy_env(base)
    return util.merge(base or {}, cmake_version.policy_env(base))
end

function M.configure(o)
    local exec = o.exec or gcpkg.exec
    local build = util.abs(o.build_dir or util.join(o.src, "build"), o.src)
    fs.mkdirs(build)
    local baseEnv = o.env
    local env = policy_env(baseEnv)
    local cmd = { "cmake", "-S", o.src, "-B", build,
                  "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
                  "-DCMAKE_INSTALL_PREFIX=" .. (o.prefix or util.join(build, "install")) }
    local defines = type(o.defines) == "table" and o.defines or {}
    local args = o.args or {}
    local policy_set = defines.CMAKE_POLICY_VERSION_MINIMUM ~= nil or
                       (baseEnv and baseEnv.CMAKE_POLICY_VERSION_MINIMUM ~= nil and
                        baseEnv.CMAKE_POLICY_VERSION_MINIMUM ~= "")
    for _, a in ipairs(args) do
        if define_key(a) == "CMAKE_POLICY_VERSION_MINIMUM" then
            policy_set = true
        end
    end
    local policy = cmake_version.policy_arg()
    if policy and not policy_set then
        cmd[#cmd + 1] = policy
    end
    if o.generator then
        cmd[#cmd + 1] = "-G"
        cmd[#cmd + 1] = o.generator
    end
    if o.toolchain then
        cmd[#cmd + 1] = "-DCMAKE_TOOLCHAIN_FILE=" .. o.toolchain
    end
    for _, k in ipairs(util.keys(defines)) do
        cmd[#cmd + 1] = "-D" .. k .. "=" .. tostring(defines[k])
    end
    for _, a in ipairs(args) do
        cmd[#cmd + 1] = tostring(a)
    end
    exec(dedup_defines(cmd), { cwd = o.src, log = o.log, env = env })
    return build
end

function M.build(o)
    local exec = o.exec or gcpkg.exec
    local build = util.abs(o.build_dir or util.join(o.src, "build"), o.src)
    local cmd = { "cmake", "--build", build, "--parallel",
                  tostring(o.jobs or gcpkg.sys.nproc()) }
    for _, t in ipairs(o.targets or {}) do
        cmd[#cmd + 1] = "--target"
        cmd[#cmd + 1] = t
    end
    exec(cmd, { cwd = o.src, log = o.log, env = policy_env(o.env) })
    return build
end

function M.install(o)
    local exec = o.exec or gcpkg.exec
    local build = util.abs(o.build_dir or util.join(o.src, "build"), o.src)
    local cmd = { "cmake", "--install", build }
    if o.prefix then
        cmd[#cmd + 1] = "--prefix"
        cmd[#cmd + 1] = o.prefix
    end
    exec(cmd, { cwd = o.src, log = o.log, env = policy_env(o.env) })
    return build
end

function M.all(o)
    local build = M.configure(o)
    o = util.merge(o, { build_dir = build })
    M.build(o)
    M.install(o)
    return { compdb_files = { util.join(build, "compile_commands.json") } }
end

return M
