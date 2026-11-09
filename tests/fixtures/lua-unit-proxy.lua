-- Unit test for proxy precedence, WSL host mapping, listener checks and
-- credential redaction. Runs with a small gcpkg.sys shim (no network).
local root = os.getenv("GCPKG_LUA_ROOT") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local fakeEnv = {}
local routeResponse = ""
local resolvText = nil
local getentResponse = ""
local curlCode = 7

gcpkg = { sys = {}, args = {}, version = "unit" }
function gcpkg.sys.getenv(k) return fakeEnv[k] end
function gcpkg.sys.cwd() return "." end
function gcpkg.sys.mkdir() return true end
function gcpkg.sys.read(path)
    if path == "/etc/resolv.conf" then return resolvText end
    return nil
end
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
function gcpkg.sys.capture(o)
    local cmd = o.cmd or {}
    if cmd[1] == "sh" and tostring(cmd[3] or ""):find("ip route", 1, true) then
        if routeResponse ~= "" then return 0, routeResponse end
        return 1, ""
    end
    if cmd[1] == "getent" then
        if getentResponse ~= "" then return 0, getentResponse end
        return 1, ""
    end
    if cmd[1] == "curl" then
        for _, arg in ipairs(cmd) do
            if tostring(arg):find("pw", 1, true) then
                error("proxy credentials leaked into listener probe argv", 0)
            end
        end
        return curlCode, ""
    end
    return 127, ""
end

local util = require("gcpkg.util")
local proxy = require("gcpkg.proxy")

local function assertf(cond, message)
    if not cond then error(message, 0) end
end

local function setEnv(values)
    for k in pairs(fakeEnv) do fakeEnv[k] = nil end
    for k, v in pairs(values) do fakeEnv[k] = v end
end

local function resetWorld(values, opts)
    setEnv(values)
    routeResponse = (opts and opts.route) or ""
    resolvText = opts and opts.resolv or nil
    getentResponse = (opts and opts.getent) or ""
    curlCode = (opts and opts.curl) or 7
    proxy.reset()
end

local base = { HOME = "home", GCPKG_HOME = "home/.gcpkg" }

-- 1. WSL gateway discovered from `ip route`, local loopback has no listener.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME,
    WSL_DISTRO_NAME = "TestWSL", NO_PROXY = "*",
}, { route = "127.0.0.2\n", curl = 7 })
local p = proxy.resolve({ proxy = "http://127.0.0.1:7890" })
assertf(p.url == "http://127.0.0.2:7890", "WSL ip-route gateway was not applied")
assertf(p.wsl and p.wsl.rewritten == true, "WSL rewrite flag is missing")
assertf(p.no_proxy == "", "standard NO_PROXY bypassed an explicit gcpkg proxy")
local env = proxy.env({ proxy = "http://127.0.0.1:7890" })
assertf(env.https_proxy == p.url, "proxy.env() did not use the rewritten host")
assertf(env.no_proxy == "", "proxy.env() leaked standard NO_PROXY")
local ok, msg = proxy.check(p)
assertf(not ok, "unreachable proxy unexpectedly passed the check")
assertf(msg:find("Allow LAN", 1, true), "failure omitted Allow LAN diagnosis")
assertf(msg:find("GCPKG_WSL_HOST", 1, true), "failure omitted WSL host override")

-- 2. Gateway discovered from /etc/resolv.conf when ip route is unavailable.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME,
    WSL_DISTRO_NAME = "TestWSL",
}, { resolv = "nameserver 172.20.0.1\n", curl = 7 })
p = proxy.resolve({ proxy = "http://127.0.0.1:7890" })
assertf(p.url == "http://172.20.0.1:7890", "resolv.conf gateway was not applied")
assertf(p.wsl and p.wsl.rewritten == true, "resolv.conf rewrite flag is missing")
ok, msg = proxy.check(p)
assertf(not ok, "unreachable resolv.conf gateway unexpectedly passed")
assertf(msg:find("Allow LAN", 1, true), "resolv.conf failure omitted Allow LAN")

-- 3. GCPKG_WSL_HOST=off keeps the Linux loopback; a reachable listener passes.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME,
    WSL_DISTRO_NAME = "TestWSL", GCPKG_WSL_HOST = "off",
}, { route = "127.0.0.2\n", curl = 0 })
p = proxy.resolve({ proxy = "http://127.0.0.1:7890" })
assertf(p.url == "http://127.0.0.1:7890", "GCPKG_WSL_HOST=off rewrote loopback")
assertf(p.wsl and p.wsl.keep == true and p.wsl.explicit == true,
        "GCPKG_WSL_HOST=off decision is missing")
ok, msg = proxy.check(p)
assertf(ok, "reachable local proxy listener failed the check: " .. tostring(msg))

-- 4. An explicit host overrides both discovery and a reachable local listener.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME,
    WSL_DISTRO_NAME = "TestWSL", GCPKG_WSL_HOST = "10.0.0.5",
}, { route = "127.0.0.2\n", curl = 0 })
p = proxy.resolve({ proxy = "http://127.0.0.1:7890" })
assertf(p.url == "http://10.0.0.5:7890", "explicit WSL host was not applied")
assertf(p.wsl and p.wsl.explicit == true, "explicit WSL host flag is missing")
ok = proxy.check(p)
assertf(ok, "reachable explicit WSL host failed the check")

-- 5. Standard environment proxy still honors standard NO_PROXY.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME,
    HTTPS_PROXY = "http://proxy.example:8080", NO_PROXY = "*",
}, { curl = 7 })
p = proxy.resolve({})
assertf(p.url == "http://proxy.example:8080", "standard HTTPS_PROXY was lost")
assertf(p.no_proxy == "*", "standard NO_PROXY was not honored")
ok, msg = proxy.check(p)
assertf(ok and msg:find("bypass", 1, true), "NO_PROXY=* did not skip the probe")
env = proxy.env({})
assertf(env.https_proxy == p.url and env.no_proxy == "*",
        "standard proxy env was not rebuilt correctly")

-- 6. Credentials redacted in diagnostics, never in probe argv; env still gets them.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME,
    GCPKG_PROXY = "http://user:pw@127.0.0.1:7890",
}, { curl = 0 })
p = proxy.resolve({})
assertf(p.url == "http://user:pw@127.0.0.1:7890", "GCPKG_PROXY was lost")
ok, msg = proxy.check(p)
assertf(ok, "reachable credentialed proxy failed the check")
assertf(msg:find("http://***@127.0.0.1:7890", 1, true),
        "proxy credentials were not redacted in diagnostics")
assertf(not msg:find("pw", 1, true), "proxy credentials leaked into diagnostics")
env = proxy.env({})
assertf(env.https_proxy == p.url,
        "credentialed proxy URL was not supplied to the child environment")

print("proxy unit OK")
