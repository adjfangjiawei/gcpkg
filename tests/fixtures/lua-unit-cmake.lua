-- Unit test for the CMake adapter. Runs with a small gcpkg.sys shim so the
-- real CMake version and process execution are not needed.
local root = os.getenv("GCPKG_LUA_ROOT") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local fakeEnv = {
    HOME = "home", GCPKG_HOME = "home/.gcpkg",
}
local cmakeVersion = "cmake version 4.0.0\n"

gcpkg = { sys = {}, args = {}, version = "unit" }
function gcpkg.sys.getenv(k) return fakeEnv[k] end
function gcpkg.sys.cwd() return "." end
function gcpkg.sys.mkdir() return true end
function gcpkg.sys.read() return nil end
function gcpkg.sys.write() return true end
function gcpkg.sys.append() return true end
function gcpkg.sys.isfile() return false end
function gcpkg.sys.isdir() return false end
function gcpkg.sys.exists() return false end
function gcpkg.sys.listdir() return {} end
function gcpkg.sys.realpath(p) return p end
function gcpkg.sys.yaml_parse() return {} end
function gcpkg.sys.log() end
function gcpkg.sys.exec() return 0 end
function gcpkg.sys.set_verbose() end
function gcpkg.sys.nproc() return 2 end
function gcpkg.sys.now() return 0 end
function gcpkg.sys.size() return 0 end
function gcpkg.sys.capture(o)
    if o.cmd and o.cmd[1] == "cmake" and o.cmd[2] == "--version" then
        return 0, cmakeVersion
    end
    return 127, ""
end

local util = require("gcpkg.util")
local cmake = require("gcpkg.build.cmake")
local cv = require("gcpkg.cmake_version")

local function assertf(cond, message)
    if not cond then error(message, 0) end
end

local function has(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function count(list, value)
    local n = 0
    for _, item in ipairs(list) do
        if item == value then n = n + 1 end
    end
    return n
end

local function configure(extra)
    local captured
    local opts = {
        src = "src", build_dir = "build", prefix = "prefix", jobs = 2,
        exec = function(cmd, o)
            captured = { cmd = cmd, env = o.env or {} }
            return 0
        end,
        defines = { ZLIB_BUILD_EXAMPLES = "OFF" },
        args = { "-DZLIB_BUILD_EXAMPLES=OFF" },
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    cmake.configure(opts)
    assertf(captured, "cmake.configure did not call exec")
    return captured.cmd, captured.env
end

-- CMake 4: policy compatibility is injected and repeated defines collapse.
cmakeVersion = "cmake version 4.0.0\n"
cv.reset()
local cmd4, env4 = configure()
assertf(has(cmd4, "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"),
        "CMake 4 configure lost CMAKE_POLICY_VERSION_MINIMUM")
assertf(count(cmd4, "-DZLIB_BUILD_EXAMPLES=OFF") == 1,
        "repeated -D define was not de-duplicated")
assertf(env4.CMAKE_POLICY_VERSION_MINIMUM == "3.5",
        "CMake 4 env lost CMAKE_POLICY_VERSION_MINIMUM")

-- An explicit caller value wins over gcpkg's default.
local cmdUser, envUser = configure({ env = { CMAKE_POLICY_VERSION_MINIMUM = "4.0" } })
assertf(not has(cmdUser, "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"),
        "explicit CMAKE_POLICY_VERSION_MINIMUM was overridden")
assertf(envUser.CMAKE_POLICY_VERSION_MINIMUM == "4.0",
        "explicit CMAKE_POLICY_VERSION_MINIMUM was not preserved")
assertf(count(cmdUser, "-DZLIB_BUILD_EXAMPLES=OFF") == 1,
        "repeated -D define was not de-duplicated with user env")

-- Build and install steps inherit the same policy environment.
local capturedBuild, capturedInstall
cmake.build {
    src = "src", build_dir = "build", jobs = 2,
    exec = function(_, o) capturedBuild = o.env or {}; return 0 end,
}
cmake.install {
    src = "src", build_dir = "build", prefix = "prefix",
    exec = function(_, o) capturedInstall = o.env or {}; return 0 end,
}
assertf(capturedBuild.CMAKE_POLICY_VERSION_MINIMUM == "3.5",
        "CMake 4 build step lost CMAKE_POLICY_VERSION_MINIMUM")
assertf(capturedInstall.CMAKE_POLICY_VERSION_MINIMUM == "3.5",
        "CMake 4 install step lost CMAKE_POLICY_VERSION_MINIMUM")

-- CMake 3: no policy flag / env, but de-duplication still applies.
cmakeVersion = "cmake version 3.31.6\n"
cv.reset()
local cmd3, env3 = configure()
assertf(not has(cmd3, "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"),
        "CMake 3 configure unexpectedly got a CMake 4 policy flag")
assertf(env3.CMAKE_POLICY_VERSION_MINIMUM == nil,
        "CMake 3 configure unexpectedly got a CMake 4 policy env")
assertf(count(cmd3, "-DZLIB_BUILD_EXAMPLES=OFF") == 1,
        "CMake 3 repeated -D define was not de-duplicated")

print("cmake adapter unit OK")
