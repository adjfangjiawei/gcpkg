-- Port registry inspection + bottom-up dependency ordering.
-- Feature requests can add dependencies (`requires:` in features.yaml), so the
-- graph is computed from *effective* dependencies, not just build.lua's static
-- `dependencies` list. port.install() uses the same rule.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local yaml = require("gcpkg.yaml")
local features = require("gcpkg.features")
local M = {}

function M.dep_name(dep)
    if type(dep) == "table" then
        return tostring(dep.name or dep[1])
    end
    return (tostring(dep):gsub("@.*$", ""))
end

function M.is_external(dep)
    return M.dep_name(dep):find(":") ~= nil
end

-- name -> {dir, spec}; first root wins (so a user registry can override).
function M.ports(roots)
    local out = {}
    for _, root in ipairs(roots or {}) do
        if fs.isdir(root) then
            for _, entry in ipairs(fs.listdir(root)) do
                local dir = util.join(root, entry)
                if not out[entry] and fs.isfile(util.join(dir, "build.lua")) then
                    local ok, spec = pcall(gcpkg.sys.loadchunk, util.join(dir, "build.lua"))
                    if ok and type(spec) == "table" then
                        out[entry] = { dir = dir, spec = spec }
                    else
                        out[entry] = { dir = dir, error = tostring(spec) }
                    end
                end
            end
        end
    end
    return out
end

-- build.lua dependencies + `requires:` of every currently enabled feature.
function M.deps(entry, requests, name)
    local out = util.deepcopy((entry and entry.spec or {}).dependencies or {})
    if not entry or not fs.isfile(util.join(entry.dir, "features.yaml")) then
        return out
    end
    local ok, fspec = pcall(yaml.parse_file, util.join(entry.dir, "features.yaml"))
    if not ok or type(fspec) ~= "table" then
        return out
    end
    local portName = name or (entry.spec or {}).name
    local resolved, f = pcall(features.resolve, fspec.features or fspec,
                              portName, requests or {})
    if resolved then
        for _, r in ipairs(f.requires or {}) do
            out[#out + 1] = r
        end
    end
    return out
end

-- DFS post-order: dependencies first ("bottom-up"), i.e. the exact order in
-- which gcpkg will build them.
function M.order(name, ports, requests)
    local order, seen, stack = {}, {}, {}
    local function visit(n)
        if seen[n] then
            return
        end
        if stack[n] then
            error("dependency cycle: " .. table.concat(util.keys(stack), " -> ") .. " -> " .. n)
        end
        stack[n] = true
        local entry = ports[n]
        if entry and entry.spec then
            for _, dep in ipairs(M.deps(entry, requests, n)) do
                local d = M.dep_name(dep)
                if not M.is_external(d) and ports[d] then
                    visit(d)
                end
            end
        end
        stack[n] = nil
        seen[n] = true
        order[#order + 1] = n
    end
    visit(name)
    return order
end

function M.layers(ports, requests)
    local memo = {}
    local function layer(n, path)
        if memo[n] then
            return memo[n]
        end
        if path[n] then
            return 0
        end
        path[n] = true
        local entry = ports[n]
        local best = 0
        if entry and entry.spec then
            for _, dep in ipairs(M.deps(entry, requests, n)) do
                local d = M.dep_name(dep)
                if not M.is_external(d) and ports[d] then
                    best = math.max(best, layer(d, path) + 1)
                end
            end
        end
        path[n] = nil
        memo[n] = best
        return best
    end
    local out = {}
    for name in pairs(ports) do
        out[name] = layer(name, {})
    end
    return out
end

function M.validate(ports, requests)
    local problems = {}
    for name, entry in pairs(ports) do
        if entry.error then
            problems[#problems + 1] = name .. ": build.lua error: " .. entry.error
        end
        if not fs.isfile(util.join(entry.dir, "features.yaml")) then
            problems[#problems + 1] = name .. ": missing features.yaml"
        end
        for _, dep in ipairs(M.deps(entry, requests, name)) do
            local d = M.dep_name(dep)
            if not M.is_external(d) and not ports[d] then
                problems[#problems + 1] = name .. ": unknown dependency '" .. d .. "'"
            end
        end
    end
    return problems
end

return M
