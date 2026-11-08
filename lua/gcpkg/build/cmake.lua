-- CMake adapter. Just a Lua module: `local cmake = require("gcpkg.build.cmake")`
-- is all a port needs to gain CMake build functions. CMake itself is untouched.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

function M.configure(o)
    local exec = o.exec or gcpkg.exec
    local build = util.abs(o.build_dir or util.join(o.src, "build"), o.src)
    fs.mkdirs(build)
    local cmd = { "cmake", "-S", o.src, "-B", build,
                  "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
                  "-DCMAKE_INSTALL_PREFIX=" .. (o.prefix or util.join(build, "install")) }
    if o.generator then
        cmd[#cmd + 1] = "-G"
        cmd[#cmd + 1] = o.generator
    end
    if o.toolchain then
        cmd[#cmd + 1] = "-DCMAKE_TOOLCHAIN_FILE=" .. o.toolchain
    end
    for _, k in ipairs(util.keys(o.defines or {})) do
        cmd[#cmd + 1] = "-D" .. k .. "=" .. tostring(o.defines[k])
    end
    for _, a in ipairs(o.args or {}) do
        cmd[#cmd + 1] = tostring(a)
    end
    exec(cmd, { cwd = o.src, log = o.log, env = o.env })
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
    exec(cmd, { cwd = o.src, log = o.log, env = o.env })
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
    exec(cmd, { cwd = o.src, log = o.log, env = o.env })
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
