-- User-level configuration that must be readable before a package store exists.
--
-- The store directory itself is selected here, so this file lives outside the
-- store: $XDG_CONFIG_HOME/gcpkg/config.yaml (or ~/.config/gcpkg/config.yaml).
-- GCPKG_CONFIG may point at a different file; GCPKG_STORE / GCPKG_HOME and
-- --store still take precedence for a single invocation.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local yaml = require("gcpkg.yaml")
local json = require("gcpkg.json")
local M = {}

local function getenv(key)
    return gcpkg.sys.getenv(key) or ""
end

local function home_dir()
    local h = getenv("HOME")
    if h ~= "" then return h end
    return fs.cwd()
end

function M.home()
    return util.join(home_dir(), ".gcpkg")
end

local function config_home()
    local xdg = getenv("XDG_CONFIG_HOME")
    if xdg ~= "" then return util.join(xdg, "gcpkg") end
    return util.join(home_dir(), ".config", "gcpkg")
end

function M.path()
    local explicit = getenv("GCPKG_CONFIG")
    if explicit ~= "" then return util.abs(explicit) end
    return util.join(config_home(), "config.yaml")
end

function M.read()
    return yaml.parse_file(M.path()) or {}
end

function M.store()
    local value = M.read().store
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function expand(path)
    path = tostring(path or "")
    if path:sub(1, 2) == "~/" then
        path = util.join(home_dir(), path:sub(3))
    end
    return util.abs(path)
end

local function without_store(lines)
    local out = {}
    for _, line in ipairs(lines or {}) do
        if not line:match("^%s*store%s*:") then
            out[#out + 1] = line
        end
    end
    return out
end

function M.set_store(path)
    if path == nil or path == "" then
        error("store set needs a directory")
    end
    local absolute = expand(path)
    local lines = without_store(fs.lines(M.path()))
    lines[#lines + 1] = "store: " .. json.encode(absolute)
    fs.write(M.path(), table.concat(lines, "\n") .. "\n")
    return absolute
end

function M.unset_store()
    local lines = without_store(fs.lines(M.path()))
    fs.write(M.path(), table.concat(lines, "\n") .. "\n")
end

-- Precedence, highest first: --store, GCPKG_STORE, GCPKG_HOME, persistent
-- user config, then ~/.gcpkg.  A source label is returned for `gcpkg doctor`
-- and `gcpkg store show`.
function M.resolve(explicit)
    if explicit and explicit ~= "" then
        return util.abs(explicit), "--store"
    end
    local envStore = getenv("GCPKG_STORE")
    if envStore ~= "" then
        return util.abs(envStore), "GCPKG_STORE"
    end
    local legacyHome = getenv("GCPKG_HOME")
    if legacyHome ~= "" then
        return util.abs(legacyHome), "GCPKG_HOME"
    end
    local configured = M.store()
    if configured then
        return util.abs(configured), M.path()
    end
    return util.abs(M.home()), "default"
end

return M
