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
-- `no_proxy` comes from --noproxy / GCPKG_NO_PROXY / either config file /
-- NO_PROXY, in that order. Project config outranks the user-wide config,
-- matching the scope rules of gcpkg.workspace.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local yaml = require("gcpkg.yaml")
local M = { current = nil }

M.BLOCK_START = "# --- gcpkg managed proxy (use `gcpkg proxy`) ---"
M.BLOCK_END = "# --- end gcpkg managed proxy ---"

local PROXY_KEYS = { "http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY",
                     "all_proxy", "ALL_PROXY" }
local NOPROXY_KEYS = { "no_proxy", "NO_PROXY" }

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

function M.home()
    return getenv("GCPKG_HOME") or
           util.join(getenv("HOME") or fs.cwd(), ".gcpkg")
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

function M.sources(o)
    o = o or {}
    local proj = o.project_dir and util.join(o.project_dir, "gcpkg.yaml") or nil
    return {
        { name = "--no-proxy", value = o.no_proxy and "__disabled__" or nil },
        { name = "--proxy", value = o.proxy },
        { name = "GCPKG_PROXY", value = getenv("GCPKG_PROXY") },
        { name = "project gcpkg.yaml", value = proj and config(proj, "proxy") or nil },
        { name = "$GCPKG_HOME/gcpkg.yaml", value = config(M.global_yaml(), "proxy") },
        { name = "HTTPS_PROXY/https_proxy",
          value = getenv("HTTPS_PROXY") or getenv("https_proxy") },
        { name = "HTTP_PROXY/http_proxy",
          value = getenv("HTTP_PROXY") or getenv("http_proxy") },
        { name = "ALL_PROXY/all_proxy",
          value = getenv("ALL_PROXY") or getenv("all_proxy") },
    }
end

local function no_proxy_list(o, projectDir)
    local proj = projectDir and util.join(projectDir, "gcpkg.yaml") or nil
    -- Use "" rather than nil: Lua's ipairs stops at the first nil element,
    -- which would make every later (lower-priority) candidate unreachable.
    return first({
        o.no_proxy_list or "",
        getenv("GCPKG_NO_PROXY") or "",
        proj and config(proj, "no_proxy") or "",
        config(M.global_yaml(), "no_proxy") or "",
        getenv("NO_PROXY") or getenv("no_proxy") or "",
    }) or ""
end

function M.resolve(o)
    o = o or {}
    for _, s in ipairs(M.sources(o)) do
        if s.value == "__disabled__" then
            return { disabled = true, source = "--no-proxy",
                     no_proxy = no_proxy_list(o, o.project_dir) }
        end
        if s.value and s.value ~= "" then
            if not valid(s.value) then
                error("invalid proxy URL from " .. s.name ..
                      " (expected scheme://host:port, got '" ..
                      M.redact(s.value) .. "')")
            end
            return { url = s.value, source = s.name,
                     no_proxy = no_proxy_list(o, o.project_dir) }
        end
    end
    return { no_proxy = no_proxy_list(o, o.project_dir) }
end

function M.configure(o)
    M.current = M.resolve(o or {})
    return M.current
end

function M.active()
    return M.current or M.resolve({})
end

-- Environment passed to curl/git and to every build hook. Returning an empty
-- table leaves the inherited environment alone (standard *_PROXY still works).
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
        return out
    end
    if not p.url then
        return out
    end
    for _, k in ipairs(PROXY_KEYS) do
        out[k] = p.url
    end
    for _, k in ipairs(NOPROXY_KEYS) do
        out[k] = p.no_proxy or ""
    end
    return out
end

local function host_of(url)
    return (tostring(url):match("^[%w][%w+%.%-]*://([^/:]+)"))
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

function M.summary()
    local p = M.active()
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
    log.step("effective: " .. M.summary())
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
