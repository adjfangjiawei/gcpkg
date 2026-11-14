-- Proxy configuration for the whole meta package manager.
--
-- ONE place resolves the proxy, and it feeds EVERY network-touching command:
-- curl downloads, git clones, and the environment of all build hooks (so
-- CMake/Meson/ExternalProject fetches inside an upstream build inherit it).
-- Credentials live only in environment variables / config files, never on a
-- command line, so build logs and `--verbose` cannot leak them.
--
-- Precedence (first wins):
--   1. --no-proxy                     (explicit direct connection)
--   2. --proxy=URL                   (one-shot CLI override)
--   3. GCPKG_PROXY                   (session environment)
--   4. <project>/gcpkg.yaml `proxy:`  (project-specific)
--   5. $GCPKG_HOME/gcpkg.yaml `proxy:` (user-wide / public)
--   6. HTTPS_PROXY / HTTP_PROXY / ALL_PROXY (standard environment)
--   7. no proxy (direct)
--
-- A proxy selected by gcpkg does not inherit standard NO_PROXY: an inherited
-- `NO_PROXY=*` must not silently bypass an explicitly configured proxy.
-- Exclusions can still be set with --noproxy, GCPKG_NO_PROXY or a config key.
--
-- The resolved value is not merely displayed. Every download gets an explicit
-- curl config (-q -K), every Git process gets GIT_CONFIG_* http.proxy, and
-- every build hook gets CURL_HOME. A user-level .curlrc, inherited NO_PROXY
-- or a wrapper cannot silently bypass a proxy that gcpkg has configured.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local yaml = require("gcpkg.yaml")
local exec = require("gcpkg.exec")
local paths = require("gcpkg.paths")
local M = { current = nil }

M.BLOCK_START = "# --- gcpkg managed proxy (use `gcpkg proxy`) ---"
M.BLOCK_END = "# --- end gcpkg managed proxy ---"

local PROXY_KEYS = { "http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY",
                     "all_proxy", "ALL_PROXY" }
local NOPROXY_KEYS = { "no_proxy", "NO_PROXY" }
local EXPLICIT_SOURCES = {
    ["--proxy"] = true,
    ["GCPKG_PROXY"] = true,
    ["project gcpkg.yaml"] = true,
    ["$GCPKG_HOME/gcpkg.yaml"] = true,
}
local UNREACHABLE_CURL = {
    [2] = "curl failed to initialize",
    [3] = "malformed probe URL",
    [5] = "could not resolve proxy",
    [6] = "could not resolve proxy host",
    [7] = "connection refused (no proxy listener)",
    [28] = "connection timed out",
    [125] = "probe process could not start",
    [126] = "probe process could not start",
    [127] = "curl is not available",
}
local DEFAULT_PORT = {
    http = 80, https = 443, socks4 = 1080, socks4a = 1080,
    socks5 = 1080, socks5h = 1080,
}

local function getenv(k)
    return gcpkg.sys.getenv(k)
end

-- scheme://user:password@host:port -> scheme://***@host:port
function M.redact(s)
    if type(s) ~= "string" then
        return s
    end
    return (s:gsub("([%w][%w+%.%-]*://)[^/@%s]+@", "%1***@"))
end

-- Implicit state lives inside the store, never in $HOME.
function M.home()
    return paths.state_root()
end

function M.global_yaml()
    return util.join(M.home(), "gcpkg.yaml")
end

local function read_yaml(path)
    local text = fs.read(path)
    if not text then
        return nil
    end
    local ok, value = pcall(yaml.parse, text)
    if ok and type(value) == "table" then
        return value
    end
    return nil
end

local function config(path, key)
    local y = read_yaml(path)
    local v = y and y[key]
    if type(v) == "table" then
        v = v.url
    end
    if type(v) == "string" and v ~= "" then
        return v
    end
    return nil
end

local function valid(url)
    return type(url) == "string" and url ~= "" and
           url:match("^([%w+%.%-]+)://[%w%.%-%:]+") ~= nil
end

local function first(list)
    for _, v in ipairs(list or {}) do
        if v and v ~= "" then
            return v
        end
    end
    return nil
end

-- Split just enough of a proxy URL to find the listener. Credentials are
-- never passed to a probe command.
local function split_url(url)
    local scheme, rest = tostring(url):match("^([%w+%.%-]+)://(.*)$")
    if not scheme or not rest then
        return nil
    end
    local auth, authority = "", rest
    local at = rest:find("@", 1, true)
    if at then
        auth, authority = rest:sub(1, at), rest:sub(at + 1)
    end
    local host, tail
    if authority:sub(1, 1) == "[" then
        host, tail = authority:match("^(%[[^%]]+%])(.*)$")
    else
        host, tail = authority:match("^([^:/]+)(.*)$")
    end
    if not host then
        return nil
    end
    tail = tail or ""
    local port = tonumber(tail:match("^:(%d+)") or "") or DEFAULT_PORT[scheme]
    return scheme, auth, host, port, tail
end

local function host_of(url)
    local _, _, host = split_url(url)
    return host
end

local reachCache = {}
local checkCache = {}
local curlConfigPath, curlConfigContent
-- Write a private curl config. Credentials stay in this 0600 file, never in
-- an argv or a build log. `CURL_HOME` makes every curl invoked by a build hook
-- read it; `GCPKG_CURL_CONFIG` lets net.download pass it explicitly with -K.
local function curlQuote(s)
    return tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
           :gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function curl_config(p)
    local proxyValue, noProxyValue, gitValue
    if p.disabled then
        proxyValue, noProxyValue, gitValue = "", "*", ""
    elseif p.url then
        proxyValue, noProxyValue, gitValue = p.url, p.no_proxy or "", p.url
    else
        -- No proxy resolved: force direct too, so an inherited .curlrc cannot
        -- silently re-enable a proxy that gcpkg reports as "none (direct)".
        proxyValue, noProxyValue, gitValue = "", "*", ""
    end
    local dir = util.join(paths.state_root(), "curl")
    local path = util.join(dir, ".curlrc")
    local content = table.concat({
        "# Generated by gcpkg. Credentials stay out of argv and build logs.",
        "proxy = \"" .. curlQuote(proxyValue) .. "\"",
        "noproxy = \"" .. curlQuote(noProxyValue) .. "\"",
        "",
    }, "\n")
    if curlConfigPath == path and curlConfigContent == content and fs.isfile(path) then
        return path, dir, gitValue
    end
    fs.mkdirs(dir)
    -- Create with restrictive permissions BEFORE credentialed content is
    -- written: std::ofstream truncates an existing file without changing mode.
    if not fs.isfile(path) then
        fs.write(path, "")
    end
    pcall(exec.run, { "chmod", "700", dir }, { quiet = true, check = false })
    pcall(exec.run, { "chmod", "600", path }, { quiet = true, check = false })
    fs.write(path, content)
    curlConfigPath, curlConfigContent = path, content
    return path, dir, gitValue
end

local function reachable(url, timeout)
    local key = tostring(url) .. "|" .. tostring(timeout)
    local hit = reachCache[key]
    if hit then
        return hit.ok, hit.reason
    end
    local scheme, _, host, port = split_url(url)
    if not scheme or not host or not port then
        return false, "invalid proxy URL"
    end
    local targetHost = host
    if host:sub(1, 1) ~= "[" and host:find(":", 1, true) then
        targetHost = "[" .. host .. "]"
    end
    local probeEnv = {}
    for _, k in ipairs(PROXY_KEYS) do
        probeEnv[k] = ""
    end
    for _, k in ipairs(NOPROXY_KEYS) do
        probeEnv[k] = "*"
    end
    -- -q ignores every .curlrc, including the private one generated below.
    probeEnv.CURL_HOME = ""
    probeEnv.XDG_CONFIG_HOME = ""
    probeEnv.GCPKG_CURL_CONFIG = ""
    probeEnv.GIT_CONFIG_COUNT = ""
    probeEnv.GIT_CONFIG_KEY_0 = ""
    probeEnv.GIT_CONFIG_VALUE_0 = ""
    -- A local HTTP probe is enough to distinguish "no listener" from "proxy
    -- app accepted a TCP connection". SOCKS/TLS proxies may close it with a
    -- curl 35/52/56 code; those still prove the listener is reachable.
    local cmd = { "curl", "-q", "--noproxy", "*", "--connect-timeout", tostring(timeout),
                  "--max-time", tostring(timeout + 1), "-sS", "-o", "/dev/null",
                  "http://" .. targetHost .. ":" .. tostring(port) .. "/" }
    local ok, _, code = pcall(exec.capture, cmd, { env = probeEnv })
    local result = { ok = false, reason = "proxy listener probe failed" }
    if not ok then
        result.reason = "proxy listener probe could not be started"
    else
        code = tonumber(code) or -1
        if code == 0 then
            result.ok = true
            result.reason = "proxy listener accepted an HTTP probe"
        elseif UNREACHABLE_CURL[code] then
            result.reason = UNREACHABLE_CURL[code] .. " (curl exit " .. code .. ")"
        else
            result.ok = true
            result.reason = "TCP listener reachable (curl exit " .. code .. ")"
        end
    end
    reachCache[key] = result
    return result.ok, result.reason
end

M.reachable = reachable

function M.sources(o)
    o = o or {}
    local proj = o.project_dir and util.join(o.project_dir, "gcpkg.yaml") or nil
    return {
        { name = "--no-proxy", value = o.no_proxy and "__disabled__" or nil },
        { name = "--proxy", value = o.proxy },
        { name = "GCPKG_PROXY", value = getenv("GCPKG_PROXY") },
        { name = "project gcpkg.yaml", value = proj and config(proj, "proxy") or nil },
        { name = "store gcpkg.yaml", value = config(M.global_yaml(), "proxy") },
        { name = "HTTPS_PROXY/https_proxy",
          value = getenv("HTTPS_PROXY") or getenv("https_proxy") },
        { name = "HTTP_PROXY/http_proxy",
          value = getenv("HTTP_PROXY") or getenv("http_proxy") },
        { name = "ALL_PROXY/all_proxy",
          value = getenv("ALL_PROXY") or getenv("all_proxy") },
    }
end

local function no_proxy_list(o, projectDir, inheritStandard)
    local proj = projectDir and util.join(projectDir, "gcpkg.yaml") or nil
    local standard = ""
    if inheritStandard then
        standard = getenv("NO_PROXY") or getenv("no_proxy") or ""
    end
    -- Use "" rather than nil: Lua's ipairs stops at the first nil element,
    -- which would make every later (lower-priority) candidate unreachable.
    return first({
        o.no_proxy_list or "",
        getenv("GCPKG_NO_PROXY") or "",
        proj and config(proj, "no_proxy") or "",
        config(M.global_yaml(), "no_proxy") or "",
        standard,
    }) or ""
end

function M.resolve(o)
    o = o or {}
    for _, s in ipairs(M.sources(o)) do
        if s.value == "__disabled__" then
            return { disabled = true, source = "--no-proxy",
                     no_proxy = no_proxy_list(o, o.project_dir, false) }
        end
        if s.value and s.value ~= "" then
            if not valid(s.value) then
                error("invalid proxy URL from " .. s.name ..
                      " (expected scheme://host:port, got '" ..
                      M.redact(s.value) .. "')")
            end
            return { url = s.value, origin = s.value, source = s.name,
                     no_proxy = no_proxy_list(o, o.project_dir,
                                              not EXPLICIT_SOURCES[s.name]) }
        end
    end
    return { no_proxy = no_proxy_list(o, o.project_dir, true) }
end

function M.configure(o)
    M.current = M.resolve(o or {})
    return M.current
end

function M.active()
    return M.current or M.resolve({})
end

function M.reset()
    M.current = nil
    reachCache = {}
    checkCache = {}
    curlConfigPath, curlConfigContent = nil, nil
end

-- Environment passed to curl/git and to every build hook. The resolved
-- decision is forced explicitly; inherited env alone is never trusted.
function M.env(o)
    local p = o and M.resolve(o) or M.active()
    local out = {}
    if p.disabled then
        for _, k in ipairs(PROXY_KEYS) do
            out[k] = ""
        end
        for _, k in ipairs(NOPROXY_KEYS) do
            out[k] = "*"
        end
    elseif p.url then
        for _, k in ipairs(PROXY_KEYS) do
            out[k] = p.url
        end
        for _, k in ipairs(NOPROXY_KEYS) do
            out[k] = p.no_proxy or ""
        end
    else
        for _, k in ipairs(PROXY_KEYS) do
            out[k] = ""
        end
        for _, k in ipairs(NOPROXY_KEYS) do
            out[k] = "*"
        end
    end
    -- Environment alone is not enough: a .curlrc, NO_PROXY or a wrapper can
    -- bypass it. Force curl with -K/CURL_HOME and Git with GIT_CONFIG_*.
    local cfgPath, cfgDir, gitValue = curl_config(p)
    out.CURL_HOME = cfgDir
    out.GCPKG_CURL_CONFIG = cfgPath
    out.GIT_CONFIG_COUNT = "1"
    out.GIT_CONFIG_KEY_0 = "http.proxy"
    out.GIT_CONFIG_VALUE_0 = gitValue
    return out
end

function M.bypass(url, list)
    if not list or list == "" then
        return false
    end
    local host = host_of(url)
    if not host then
        return false
    end
    for _, raw in ipairs(util.split(list, ",")) do
        local item = util.trim(raw)
        if item == "*" then
            return true
        elseif item ~= "" then
            if host == item or util.endswith(host, "." .. item) then
                return true
            end
            if item:sub(1, 1) == "." and util.endswith(host, item) then
                return true
            end
        end
    end
    return false
end

function M.summary(p)
    p = p or M.active()
    if p.disabled then
        return "disabled (--no-proxy / direct)"
    end
    if not p.url then
        return "none (direct)"
    end
    return M.redact(p.url) .. " [" .. p.source .. "]" ..
           (p.no_proxy and p.no_proxy ~= "" and
            (" no_proxy=" .. p.no_proxy) or "")
end

function M.check(p)
    p = p or M.active()
    if getenv("GCPKG_PROXY_CHECK") == "0" then
        return true, "proxy check disabled (GCPKG_PROXY_CHECK=0)"
    end
    if p.disabled or not p.url then
        return true, "direct (no proxy configured)"
    end
    if p.no_proxy and M.bypass("https://gcpkg.invalid", p.no_proxy) then
        return true, "all destinations bypass the proxy (no_proxy=*)"
    end
    local key = tostring(p.url) .. "|" .. tostring(p.no_proxy or "")
    local hit = checkCache[key]
    if hit then
        return hit.ok, hit.reason
    end
    local ok, reason = reachable(p.url, 2)
    local result = { ok = ok, reason = reason }
    if ok then
        result.reason = "proxy listener reachable at " .. M.redact(p.url) ..
                        " (" .. reason .. ")"
    else
        local parts = {
            "cannot connect to effective proxy " .. M.redact(p.url),
            "configured as " .. M.redact(p.origin or p.url) ..
                " from " .. tostring(p.source or "configuration"),
            reason,
        }
        parts[#parts + 1] = "check that the proxy app is running and listening on " ..
                            "this host:port; use `gcpkg proxy --check` to retest"
        result.reason = table.concat(parts, "; ")
    end
    checkCache[key] = result
    return result.ok, result.reason
end

function M.assert_reachable(operation, p)
    local ok, reason = M.check(p)
    if not ok then
        error("cannot " .. tostring(operation or "use network") .. ": " .. reason)
    end
    return true
end

function M.describe(o)
    local log = require("gcpkg.log")
    local p = o and M.resolve(o) or M.active()
    log.step("proxy configuration (highest priority wins):")
    for _, s in ipairs(M.sources(o or {})) do
        local v = s.value
        if v == "__disabled__" then
            v = "disabled"
        elseif v then
            v = M.redact(v)
        else
            v = "(unset)"
        end
        log.info(string.format("  %-28s %s", s.name, v))
    end
    log.info("  noproxy candidates        : " ..
             (p.no_proxy and p.no_proxy ~= "" and p.no_proxy or "(none)"))
    log.step("effective: " .. M.summary(p))
    if p.url and not p.disabled then
        log.info("  sample https://github.com : " ..
                 (M.bypass("https://github.com", p.no_proxy) and "bypassed" or "via proxy"))
    end
    return p
end

--------------------------------------------------------------------------------
-- reading/writing the managed block in gcpkg.yaml

local function block(url, noProxy)
    local function q(s)
        return '"' .. tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
    end
    return {
        M.BLOCK_START,
        "proxy: " .. q(url or ""),
        "no_proxy: " .. q(noProxy or ""),
        M.BLOCK_END,
    }
end

function M.set_block(path, url, noProxy)
    local text = fs.read(path)
    local lines = text and util.split(text, "\n") or {
        "schema: 1",
        "# gcpkg project/user configuration",
    }
    local s, e
    local out = {}
    for i, line in ipairs(lines) do
        if util.trim(line) == M.BLOCK_START then
            s = i
        elseif util.trim(line) == M.BLOCK_END then
            e = i
        end
    end
    if s and e and e > s then
        for i = 1, s - 1 do out[#out + 1] = lines[i] end
        for _, l in ipairs(block(url, noProxy)) do out[#out + 1] = l end
        for i = e + 1, #lines do out[#out + 1] = lines[i] end
    else
        -- No managed block yet: strip any hand-written top-level proxy keys
        -- (duplicate YAML keys are ambiguous) and append our block.
        for _, line in ipairs(lines) do
            if not line:match("^%s*proxy%s*:") and not line:match("^%s*no_proxy%s*:") then
                out[#out + 1] = line
            end
        end
        for _, l in ipairs(block(url, noProxy)) do out[#out + 1] = l end
    end
    while #out > 0 and out[#out] == "" do
        table.remove(out)
    end
    fs.mkdirs(util.dirname(path))
    fs.write(path, table.concat(out, "\n") .. "\n")
    return path
end

function M.target(o)
    o = o or {}
    if o.global then
        return M.global_yaml()
    end
    if o.project_dir then
        return util.join(o.project_dir, "gcpkg.yaml")
    end
    return M.global_yaml()
end

function M.set(o)
    if o.url and o.url ~= "" and not valid(o.url) then
        error("invalid proxy URL (expected scheme://host:port, got '" ..
              M.redact(o.url) .. "')")
    end
    local path = M.target(o)
    M.set_block(path, o.url, o.no_proxy_list)
    return path
end

function M.unset(o)
    local path = M.target(o)
    M.set_block(path, "", "")
    return path
end

return M
