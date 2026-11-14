-- Pure-Lua unit shim for lua/gcpkg/toolchain.lua.
-- It verifies the STATIC Windows/WSL policy and cross-toolchain generation
-- without needing a Windows host, a compiler, or the rebuilt C++ engine.
local ROOT = os.getenv("GCPKG_LUA_ROOT") or "."
package.path = ROOT .. "/lua/?.lua;" .. ROOT .. "/lua/?/init.lua;" .. package.path

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function shell_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function readfile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local sys = {
    getenv = function(k) return os.getenv(k) or "" end,
    os = function() return os.getenv("GCPKG_FAKE_OS") or "linux" end,
    arch = function() return "x86_64" end,
    nproc = function() return 1 end,
    cwd = function() return os.getenv("PWD") or "." end,
    now = function() return os.time() end,
    isfile = function(p)
        local f = io.open(p, "rb")
        if f then f:close(); return true end
        return false
    end,
    isdir = function(p) return shell_ok("test -d " .. q(p)) end,
    exists = function(p)
        local f = io.open(p, "rb")
        if f then f:close(); return true end
        return shell_ok("test -d " .. q(p))
    end,
    listdir = function(p)
        local out = {}
        local f = io.popen("ls -1 " .. q(p) .. " 2>/dev/null", "r")
        if not f then return out end
        for line in f:lines() do out[#out + 1] = line end
        f:close()
        return out
    end,
    read = readfile,
    write = function(p, data)
        local f = assert(io.open(p, "wb"))
        f:write(data)
        f:close()
        return true
    end,
    append = function(p, data)
        local f = assert(io.open(p, "ab"))
        f:write(data)
        f:close()
        return true
    end,
    mkdir = function(p) return shell_ok("mkdir -p " .. q(p)) end,
    realpath = function(p) return p end,
    symlink = function() return true end,
    yaml_parse = function() return {} end,
    log = function() end,
    exec = function() return 0 end,
    capture = function() return "", 1 end,
}

gcpkg = {
    sys = sys,
    log = {
        step = function() end, info = function() end,
        warn = function() end, error = function() end,
    },
    capture = function() return "", 1 end,
    exec = function() return 0 end,
}

local tc = require("gcpkg.toolchain")

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function assert_text(haystack, needle)
    assert(haystack:find(needle, 1, true),
           "expected " .. needle .. " in:\n" .. haystack)
end

-- Static platform policy: Windows defaults to clang; WSL is Linux.
assert(tc.normalize_platform("windows") == "windows")
assert(tc.normalize_platform("windows_nt") == "windows")
assert(tc.normalize_platform("wsl") == "linux")
assert(tc.normalize_platform("linux") == "linux")
assert(tc.normalize_platform("msys") == "linux")
local win = tc.platform_defaults("windows")
assert(win.platform == "windows")
assert(contains(win.cc, "clang") and contains(win.cxx, "clang++"))
assert(contains(win.cxx, "clang-cl") and contains(win.cxx, "clang-cpp"))
assert(contains(win.reject, "gcc") and contains(win.reject, "cl.exe"))
assert(contains(win.reject, "msvc"))
assert(not contains(win.cc, "gcc") and not contains(win.cxx, "cl.exe"))

-- Target triple parsing, including a Windows cross target.
local mingw = tc.parse_target("x86_64-w64-mingw32")
assert(mingw.system == "windows" and mingw.cmake_system == "Windows")
local aarch = tc.parse_target("aarch64-linux-gnu")
assert(aarch.system == "linux" and aarch.cmake_system == "Linux")
assert(aarch.cpu_family == "aarch64" and aarch.autotools_host == "aarch64-linux-gnu")
assert(tc.host_triple() == "x86_64-linux-gnu")

local sysroot = os.getenv("GCPKG_TEST_SYSROOT") or "/tmp/gcpkg-sysroot"
local state = os.getenv("GCPKG_TEST_STATE") or "/tmp/gcpkg-state"
tc.configure({
    cc = "/opt/llvm-23/bin/clang-23",
    cxx = "/opt/llvm-23/bin/clang++-23",
    target = "aarch64-linux-gnu",
    sysroot = sysroot,
    cross_prefix = "aarch64-linux-gnu-",
    state_dir = state,
})
assert(tc.compiler("cc") == "/opt/llvm-23/bin/clang-23")
assert(tc.compiler("cxx") == "/opt/llvm-23/bin/clang++-23")
assert(tc.is_cross() == true)
assert(tc.target_arch() == "aarch64")
assert(tc.target_os() == "linux")
assert(tc.target_triplet() == "aarch64-linux-gnu")
assert(tc.cross_prefix() == "aarch64-linux-gnu-")
assert(contains(tc.flags(), "--target=aarch64-linux-gnu"))
assert(contains(tc.flags(), "--sysroot=" .. sysroot))

local env = tc.env({ CFLAGS = "-O2" })
assert(env.GCPKG_COMPILER_FLAGS:find("--target=aarch64-linux-gnu", 1, true))
assert(env.GCPKG_CROSS_PREFIX == "aarch64-linux-gnu-")
assert(env.GCPKG_TARGET_TRIPLET == "aarch64-linux-gnu")
assert(env.PKG_CONFIG_SYSROOT_DIR == sysroot)
assert(env.CFLAGS:find("-O2", 1, true) and env.CFLAGS:find("--target", 1, true))

local cmake = table.concat(tc.cmake_lines({ chainload = "/tmp/user.cmake" }), "\n")
assert_text(cmake, 'set(CMAKE_SYSTEM_NAME "Linux")')
assert_text(cmake, 'set(CMAKE_SYSTEM_PROCESSOR "aarch64")')
assert_text(cmake, 'set(CMAKE_C_COMPILER "/opt/llvm-23/bin/clang-23")')
assert_text(cmake, 'set(CMAKE_CXX_COMPILER_TARGET "aarch64-linux-gnu")')
assert_text(cmake, "set(CMAKE_SYSROOT")
assert_text(cmake, "--target=aarch64-linux-gnu")
assert_text(cmake, 'include("/tmp/user.cmake")')

-- Real build files prefer the interceptor CC/CXX wrapper while still keeping
-- the resolved clang as a standalone fallback.
local cmakeEnv = table.concat(tc.cmake_lines({
    chainload = "/tmp/user.cmake", compiler_from_env = true,
}), "\n")
assert_text(cmakeEnv, 'if(NOT "$ENV{CC}" STREQUAL "" AND NOT "$ENV{GCPKG_CC_REAL}" STREQUAL "")')
assert_text(cmakeEnv, 'set(CMAKE_C_COMPILER "$ENV{CC}")')
assert_text(cmakeEnv, 'set(CMAKE_C_COMPILER "/opt/llvm-23/bin/clang-23")')
assert_text(cmakeEnv, 'set(CMAKE_CXX_COMPILER "$ENV{CXX}")')

local meson = table.concat(tc.meson_lines(), "\n")
assert_text(meson, "c = '/opt/llvm-23/bin/clang-23'")
assert_text(meson, "cpp = '/opt/llvm-23/bin/clang++-23'")
assert_text(meson, "ar = 'aarch64-linux-gnu-ar'")
assert_text(meson, "system = 'linux'")
assert_text(meson, "cpu_family = 'aarch64'")
assert_text(meson, "--target=aarch64-linux-gnu")

local autotools = tc.autotools_args()
assert(contains(autotools, "--host=aarch64-linux-gnu"))
assert(contains(autotools, "--build=x86_64-linux-gnu"))
assert(tc.fingerprint():find("aarch64-linux-gnu", 1, true))

-- Explicit gcc must not receive clang's --target flag; --sysroot still applies.
tc.configure({
    cc = "/usr/bin/gcc", cxx = "/usr/bin/g++",
    target = "aarch64-linux-gnu", sysroot = sysroot,
})
assert(not contains(tc.flags(), "--target=aarch64-linux-gnu"))
assert(contains(tc.flags(), "--sysroot=" .. sysroot))

tc.reset()
print("compiler/toolchain Lua unit OK")
