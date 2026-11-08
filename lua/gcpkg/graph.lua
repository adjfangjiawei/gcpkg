-- Port registry inspection + bottom-up dependency ordering.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
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

-- DFS post-order: dependencies first ("bottom-up"), i.e. the exact order in
-- which gcpkg will build them.
function M.order(name, ports)
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
            for _, dep in ipairs(entry.spec.dependencies or {}) do
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

function M.layers(ports)
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
            for _, dep in ipairs(entry.spec.dependencies or {}) do
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

function M.validate(ports)
    local problems = {}
    for name, entry in pairs(ports) do
        if entry.error then
            problems[#problems + 1] = name .. ": build.lua error: " .. entry.error
        end
        if not fs.isfile(util.join(entry.dir, "features.yaml")) then
            problems[#problems + 1] = name .. ": missing features.yaml"
        end
        local spec = entry.spec or {}
        for _, dep in ipairs(spec.dependencies or {}) do
            local d = M.dep_name(dep)
            if not M.is_external(d) and not ports[d] then
                problems[#problems + 1] = name .. ": unknown dependency '" .. d .. "'"
            end
        end
    end
    return problems
end

return M
