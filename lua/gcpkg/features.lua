-- Feature resolution.
--
-- Each library owns ONE features.yaml (declarative data) and ONE build.lua
-- (behaviour). A feature may inject configure args, environment variables,
-- defines, extra port requirements and "provides" tags. Lua build scripts read
-- the resolved aggregate (ctx.feature_args(), ctx.features), so YAML can tune a
-- build without touching the build script -- and without touching gcpkg itself.
local util = require("gcpkg.util")
local M = {}

-- Top-level metadata in features.yaml must never be mistaken for a feature.
-- `versions:` (per-release sources) and the project/workspace keys are maps,
-- so without this filter `describe()` would print them as off-by-default
-- features and an explicit request could try to "enable" them.
M.META_KEYS = {
    schema = true, port = true, versions = true, dependencies = true,
    project = true, ports = true, inherit_global = true,
    proxy = true, no_proxy = true,
}

-- "openssl:shared", "-openssl:shared" (disable), "shared" (global)
function M.parse_spec(spec)
    spec = tostring(spec)
    local disable = false
    if spec:sub(1, 1) == "-" then
        disable = true
        spec = spec:sub(2)
    end
    local port, feature = spec:match("^([^:]+):(.+)$")
    if not port then
        port, feature = "*", spec
    end
    return port, feature, disable
end

function M.add_request(requests, spec)
    local port, feature, disable = M.parse_spec(spec)
    local entry = requests[port] or { enable = {}, disable = {} }
    entry[disable and "disable" or "enable"][#entry[disable and "disable" or "enable"] + 1] = feature
    requests[port] = entry
    return requests
end

function M.from_yaml(value)
    -- Accepted shapes:
    --   features: [openssl:shared, -openssl:no-shared]
    --   features: {openssl: [shared, no-tests]}
    --   features: {openssl: {enable: [...], disable: [...]}}
    local requests = {}
    local f = (value or {}).features
    if type(f) == "table" then
        if f[1] ~= nil then
            for _, s in ipairs(f) do
                M.add_request(requests, s)
            end
        else
            for port, def in pairs(f) do
                if type(def) == "table" and (def.enable or def.disable) then
                    for _, x in ipairs(def.enable or {}) do
                        M.add_request(requests, port .. ":" .. x)
                    end
                    for _, x in ipairs(def.disable or {}) do
                        M.add_request(requests, "-" .. port .. ":" .. x)
                    end
                elseif type(def) == "table" then
                    for _, x in ipairs(def) do
                        M.add_request(requests, port .. ":" .. x)
                    end
                elseif type(def) == "string" then
                    M.add_request(requests, port .. ":" .. def)
                end
            end
        end
    end
    return requests
end

local function appendList(dst, src)
    if type(src) == "string" then
        dst[#dst + 1] = src
    elseif type(src) == "table" then
        if src[1] ~= nil then
            for _, v in ipairs(src) do
                dst[#dst + 1] = tostring(v)
            end
        else
            for k, v in pairs(src) do
                dst[#dst + 1] = tostring(k) .. "=" .. tostring(v)
            end
        end
    end
end

function M.resolve(spec, port_name, requests)
    spec = spec or {}
    requests = requests or {}
    local defs = spec.features or spec
    if type(defs) ~= "table" then
        defs = {}
    end
    local global = requests["*"] or {}
    local localReq = requests[port_name] or {}
    local explicit = {}

    for _, f in ipairs(global.enable or {}) do
        explicit[f] = true
    end
    for _, f in ipairs(localReq.enable or {}) do
        explicit[f] = true
    end

    local enabled = {}
    for name, def in pairs(defs) do
        if M.META_KEYS[name] then
            defs[name] = nil  -- map-shaped metadata (versions:, dependencies:)
        elseif type(def) == "table" and def.default == true then
            enabled[name] = true
        elseif type(def) ~= "table" then
            defs[name] = nil  -- ignore scalar metadata (schema, port, ...)
        end
    end
    for _, f in ipairs(global.enable or {}) do
        if not defs[f] then
            error("unknown feature '" .. tostring(f) .. "' (global request)")
        end
        enabled[f] = true
    end
    for _, f in ipairs(localReq.enable or {}) do
        if not defs[f] then
            error("unknown feature '" .. port_name .. ":" .. tostring(f) .. "'")
        end
        enabled[f] = true
    end
    for _, f in ipairs(global.disable or {}) do
        enabled[f] = nil
    end
    for _, f in ipairs(localReq.disable or {}) do
        enabled[f] = nil
    end

    -- Conflict resolution: explicit choices win over defaults; two conflicting
    -- explicit choices are an error rather than a silent surprise.
    for name in pairs(enabled) do
        local def = defs[name] or {}
        for _, other in ipairs(def.conflicts or {}) do
            if enabled[other] then
                if explicit[name] and explicit[other] then
                    error("conflicting features '" .. name .. "' and '" .. other ..
                          "' for " .. port_name)
                elseif explicit[name] then
                    enabled[other] = nil
                elseif explicit[other] then
                    enabled[name] = nil
                else
                    enabled[other] = nil
                end
            end
        end
    end

    local args, defines, requires, provides, env = {}, {}, {}, {}, {}
    for _, name in ipairs(util.keys(enabled)) do
        local def = defs[name] or {}
        appendList(args, def.args)
        appendList(defines, def.defines)
        appendList(requires, def.requires)
        appendList(provides, def.provides)
        if type(def.env) == "table" then
            for k, v in pairs(def.env) do
                if type(k) == "number" then
                    local pair = util.split(tostring(v), "=")
                    env[pair[1]] = pair[2] or ""
                else
                    env[k] = tostring(v)
                end
            end
        end
    end

    local list = util.keys(enabled)
    return {
        enabled = enabled,
        list = list,
        args = args,
        env = env,
        defines = defines,
        requires = requires,
        provides = provides,
        hash = table.concat(list, ","),
    }
end

function M.describe(spec, port_name)
    local lines = {}
    local defs = (spec or {}).features or spec or {}
    for _, name in ipairs(util.keys(defs)) do
        if not M.META_KEYS[name] then
            local def = defs[name] or {}
            lines[#lines + 1] = string.format("  %-18s %-8s %s", name,
                def.default and "[on]" or "[off]", def.description or "")
        end
    end
    return "Features for " .. tostring(port_name) .. ":\n" .. table.concat(lines, "\n")
end

return M
