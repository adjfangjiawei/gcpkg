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
local paths = require("gcpkg.paths")
local M = {}

local TOOLCHAIN_KEYS = { "cc", "cxx", "target", "triple", "sysroot",
                         "cross_prefix", "llvm_home" }
local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

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

-- The persistent config now lives INSIDE the store.  A legacy config in
-- ~/.config/gcpkg is still READ (for backwards compatibility) but never
-- written, so gcpkg never creates files outside the store boundary.
function M.path()
    local explicit = getenv("GCPKG_CONFIG")
    if explicit ~= "" then return util.abs(explicit) end
    local ok, state = pcall(paths.state_root)
    if not ok or not state then return nil end
    return util.join(state, "config.yaml")
end

function M.read()
    local p = M.path()
    if p and fs.isfile(p) then return yaml.parse_file(p) or {} end
    local legacy = util.join(config_home(), "config.yaml")
    if fs.isfile(legacy) then return yaml.parse_file(legacy) or {} end
    return {}
end

-- compiler:/toolchain: blocks are the canonical user/project toolchain config;
-- flat keys are accepted for compatibility. Nested blocks win over flat keys.
function M.toolchain_block(y)
    y = type(y) == "table" and y or {}
    local out = {}
    for _, key in ipairs(TOOLCHAIN_KEYS) do
        if type(y[key]) == "string" and y[key] ~= "" then out[key] = y[key] end
    end
    for _, block in ipairs({ y.compiler, y.toolchain }) do
        if type(block) == "table" then
            for _, key in ipairs(TOOLCHAIN_KEYS) do
                if type(block[key]) == "string" and block[key] ~= "" then
                    out[key] = block[key]
                end
            end
        end
    end
    return out
end

function M.read_toolchain()
    return M.toolchain_block(M.read() or {})
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
    assert(M.path(), "gcpkg: store boundary not configured")
    local absolute = expand(path)
    local lines = without_store(fs.lines(M.path()))
    lines[#lines + 1] = "store: " .. json.encode(absolute)
    fs.write(M.path(), table.concat(lines, "\n") .. "\n")
    return absolute
end

function M.unset_store()
    assert(M.path(), "gcpkg: store boundary not configured")
    local lines = without_store(fs.lines(M.path()))
    fs.write(M.path(), table.concat(lines, "\n") .. "\n")
end

local function without_toolchain_block(lines)
    local out, skipping = {}, false
    for _, line in ipairs(lines or {}) do
        if line:match("^%s*compiler%s*:") or line:match("^%s*toolchain%s*:") then
            skipping = true
        elseif skipping then
            if line:match("^%s*$") or line:match("^%s+") then
                -- drop the old block's indented keys / blank lines
            else
                skipping = false
                out[#out + 1] = line
            end
        else
            local top = line:match("^([%w_]+)%s*:")
            if not (top and contains(TOOLCHAIN_KEYS, top)) then
                out[#out + 1] = line
            end
        end
    end
    return out
end

-- Persist one compiler/cross/LLVM key without destroying `store:` or other
-- user-level YAML. `value == nil` removes the key.
function M.set_toolchain_value(key, value)
    assert(contains(TOOLCHAIN_KEYS, key), "unknown toolchain key: " .. tostring(key))
    assert(M.path(), "gcpkg: store boundary not configured")
    local t = M.read_toolchain()
    if value == nil then
        t[key] = nil
    else
        value = expand(value)
        if key == "llvm_home" and not fs.isdir(value) then
            error("LLVM home does not exist: " .. value)
        end
        t[key] = value
    end
    local lines = without_toolchain_block(fs.lines(M.path()))
    local body = {}
    for _, k in ipairs(TOOLCHAIN_KEYS) do
        if t[k] then body[#body + 1] = "  " .. k .. ": " .. json.encode(tostring(t[k])) end
    end
    local text = table.concat(lines, "\n")
    if text ~= "" then text = text .. "\n" end
    if #body > 0 then
        text = text .. "compiler:\n" .. table.concat(body, "\n") .. "\n"
    end
    fs.write(M.path(), text)
    return t[key]
end

function M.unset_toolchain_value(key)
    return M.set_toolchain_value(key, nil)
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
