-- Unit test for proxy precedence, explicit curl/git forcing, private config
-- generation, listener probes and credential redaction. Runs with a small
-- gcpkg.sys shim (no network, no real filesystem).
local root = os.getenv("GCPKG_LUA_ROOT") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local fakeEnv = {}
local written = {}
local madeDirs = {}
local execCalls = {}
local curlCode = 7
local probeEnvSeen = nil

gcpkg = { sys = {}, args = {}, version = "unit" }
function gcpkg.sys.getenv(k) return fakeEnv[k] end
function gcpkg.sys.cwd() return "." end
function gcpkg.sys.mkdir(path) madeDirs[path] = true; return true end
function gcpkg.sys.read(path) return nil end
function gcpkg.sys.write(path, data) written[path] = data; return true end
function gcpkg.sys.append() return true end
function gcpkg.sys.isfile(path) return written[path] ~= nil end
function gcpkg.sys.isdir(path) return madeDirs[path] == true end
function gcpkg.sys.exists(path) return written[path] ~= nil or madeDirs[path] == true end
function gcpkg.sys.listdir() return {} end
function gcpkg.sys.realpath(p) return p end
function gcpkg.sys.yaml_parse() return {} end
function gcpkg.sys.log() end
function gcpkg.sys.exec(o)
    execCalls[#execCalls + 1] = o.cmd or {}
    return 0
end
function gcpkg.sys.set_verbose() end
function gcpkg.sys.nproc() return 2 end
function gcpkg.sys.now() return 0 end
function gcpkg.sys.size() return 0 end
function gcpkg.sys.capture(o)
    local cmd = o.cmd or {}
    probeEnvSeen = o.env or {}
    if cmd[1] == "curl" then
        assert(cmd[2] == "-q", "listener probe must ignore inherited curl configs")
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
    written = {}
    madeDirs = {}
    execCalls = {}
    probeEnvSeen = nil
    curlCode = (opts and opts.curl) or 7
    proxy.reset()
end

local base = { HOME = "home", GCPKG_HOME = "home/.gcpkg" }
local function cfgPath()
    return "home/.gcpkg/curl/.curlrc"
end
local function cfgDir()
    return "home/.gcpkg/curl"
end
local function execHas(sub)
    for _, cmd in ipairs(execCalls) do
        if table.concat(cmd, " "):find(sub, 1, true) then return true end
    end
    return false
end
local function assertForced(env, url, noProxy, gitValue)
    assertf(env.https_proxy == url, "proxy.env() did not set https_proxy")
    assertf(env.no_proxy == noProxy, "proxy.env() did not set no_proxy")
    assertf(env.CURL_HOME == cfgDir(), "proxy.env() did not override CURL_HOME")
    assertf(env.GCPKG_CURL_CONFIG == cfgPath(),
            "proxy.env() did not generate a private curl config")
    assertf(env.GIT_CONFIG_COUNT == "1" and env.GIT_CONFIG_KEY_0 == "http.proxy" and
            env.GIT_CONFIG_VALUE_0 == gitValue,
            "proxy.env() did not force git http.proxy")
    local cfg = written[cfgPath()] or ""
    assertf(cfg:find('proxy = "' .. url .. '"', 1, true),
            "private curl config missing proxy = " .. url)
    assertf(cfg:find('noproxy = "' .. noProxy .. '"', 1, true),
            "private curl config missing noproxy")
    assertf(execHas("chmod 700 " .. cfgDir()), "curl config dir was not chmod 700")
    assertf(execHas("chmod 600 " .. cfgPath()), "curl config was not chmod 600")
end

-- 1. Explicit --proxy ignores inherited NO_PROXY=* and forces curl/git.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME, NO_PROXY = "*",
}, { curl = 0 })
local p = proxy.resolve({ proxy = "http://127.0.0.1:7890" })
assertf(p.url == "http://127.0.0.1:7890", "explicit --proxy was rewritten")
assertf(p.no_proxy == "", "standard NO_PROXY bypassed an explicit gcpkg proxy")
local env = proxy.env({ proxy = "http://127.0.0.1:7890" })
assertForced(env, p.url, "", p.url)
local ok, msg = proxy.check(p)
assertf(ok, "reachable proxy failed the check: " .. tostring(msg))
assertf(probeEnvSeen.CURL_HOME == "" and probeEnvSeen.GIT_CONFIG_COUNT == "",
        "listener probe did not clear forced config env")

-- 2. Standard environment proxy still honors standard NO_PROXY.
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
assertForced(env, p.url, "*", p.url)

-- 3. --no-proxy forces direct even with a hostile inherited proxy.
resetWorld({
    HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME,
    GCPKG_PROXY = "http://proxy.example:8080",
}, { curl = 0 })
p = proxy.resolve({ no_proxy = true })
assertf(p.disabled == true, "--no-proxy did not disable the proxy")
env = proxy.env({ no_proxy = true })
assertForced(env, "", "*", "")
ok, msg = proxy.check(p)
assertf(ok and msg:find("direct", 1, true), "--no-proxy did not report direct")

-- 4. No proxy resolved at all: still force direct, never inherit .curlrc.
resetWorld({ HOME = base.HOME, GCPKG_HOME = base.GCPKG_HOME }, { curl = 0 })
p = proxy.resolve({})
assertf(p.url == nil and not p.disabled, "unexpected proxy resolution")
env = proxy.env({})
assertForced(env, "", "*", "")

-- 5. Credentials stay out of argv/logs; private 0600 config and env carry them.
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
assertForced(env, p.url, "", p.url)
assertf((written[cfgPath()] or ""):find("user:pw@", 1, true),
        "credentialed URL missing from private curl config")
assertf(not execHas("pw"), "proxy credentials leaked into an exec argv")

print("proxy unit OK")
