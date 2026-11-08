-- Meta-package-manager layer.
--
-- gcpkg does NOT fork or patch vcpkg/conan/pkg-config/apt/...: an adapter just
-- asks the foreign manager (unmodified) what it has, and translates the answer
-- into the SAME manifest shape native ports produce (includes / libdirs / libs
-- / defines / compdb). Project builds and clangd then treat external and
-- native dependencies identically. Adding a manager = registering one Lua
-- function; no C++ rebuild, no upstream patch.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local log = require("gcpkg.log")
local M = { adapters = {} }

function M.register(name, adapter)
    M.adapters[name] = adapter
end

local function manifest(o)
    return util.merge({
        schema = 1,
        external = true,
        includes = {}, libdirs = {}, libs = {}, defines = {}, link_flags = {},
        binaries = {}, deps = {}, features = {}, provides = {},
        compdb = nil, compdb_jsonl = nil,
    }, o)
end

-- native: a gcpkg port (build.lua + features.yaml)
M.register("native", {
    probe = function() return true, "built-in port engine" end,
    resolve = function(name, cfg)
        return require("gcpkg.port").install(name, cfg)
    end,
})

-- pkg-config: already-installed system libraries
M.register("pkgconfig", {
    probe = function()
        if gcpkg.have("pkg-config") then
            return true, gcpkg.capture({ "pkg-config", "--version" }):gsub("%s+$", "")
        end
        return false, "pkg-config not found"
    end,
    resolve = function(name, cfg)
        local flags, code = gcpkg.capture({ "pkg-config", "--cflags", "--libs", name })
        if code ~= 0 then
            error("pkg-config cannot resolve '" .. name .. "'")
        end
        local version = gcpkg.capture({ "pkg-config", "--modversion", name }):gsub("%s+$", "")
        local includes, libdirs, libs, defines, others = {}, {}, {}, {}, {}
        for _, f in ipairs(util.split(flags)) do
            if f:sub(1, 2) == "-I" then
                includes[#includes + 1] = f:sub(3)
            elseif f:sub(1, 2) == "-D" then
                defines[#defines + 1] = f:sub(3)
            elseif f:sub(1, 2) == "-L" then
                libdirs[#libdirs + 1] = f:sub(3)
            elseif f:sub(1, 2) == "-l" then
                libs[#libs + 1] = f:sub(3)
            else
                others[#others + 1] = f
            end
        end
        return manifest({
            name = "pkgconfig:" .. name,
            key = "pkgconfig-" .. name,
            version = version ~= "" and version or "system",
            includes = util.uniq(includes),
            libdirs = util.uniq(libdirs),
            libs = util.uniq(libs),
            defines = util.uniq(defines),
            link_flags = util.uniq(others),
        })
    end,
})

-- vcpkg: import the installed tree without invoking vcpkg's own build logic
M.register("vcpkg", {
    probe = function()
        local root = gcpkg.sys.getenv("VCPKG_ROOT")
        return root ~= nil and fs.isdir(root), root or "VCPKG_ROOT is unset"
    end,
    resolve = function(name, cfg)
        local root = gcpkg.sys.getenv("VCPKG_ROOT")
        local triplet = gcpkg.sys.getenv("VCPKG_DEFAULT_TRIPLET") or "x64-linux"
        if not root then
            error("vcpkg adapter requires VCPKG_ROOT")
        end
        local base = util.join(root, "installed", triplet)
        if not fs.isdir(base) then
            error("vcpkg installed tree not found: " .. base)
        end
        return manifest({
            name = "vcpkg:" .. name,
            key = "vcpkg-" .. name,
            version = triplet,
            includes = { util.join(base, "include") },
            libdirs = { util.join(base, "lib"), util.join(base, "debug", "lib") },
            libs = {},  -- declare explicit -l<lib> in gcpkg.lua if needed
            link_flags = {},
        })
    end,
})

-- system: raw prefix, useful for distro packages / hand-installed SDKs
M.register("system", {
    probe = function() return fs.isdir("/usr/include"), "/usr/include" end,
    resolve = function(name, cfg)
        local prefix = gcpkg.sys.getenv("GCPKG_SYSTEM_PREFIX") or "/usr"
        return manifest({
            name = "system:" .. name,
            key = "system-" .. name,
            version = "system",
            includes = { util.join(prefix, "include") },
            libdirs = { util.join(prefix, "lib"), util.join(prefix, "lib64") },
            libs = {},
        })
    end,
})

-- Generic escape hatch: call any package manager unmodified and use its output
-- as a manifest. Spec syntax:  call:<manager>:<arg1>,<arg2>...
-- The adapter is deliberately transparent -- gcpkg never reimplements the
-- other manager's resolver.
M.register("call", {
    probe = function() return true, "runs an external manager verbatim" end,
    resolve = function(spec, cfg)
        local manager, arglist = spec:match("^([^:]+):?(.*)$")
        if not manager or manager == "" then
            error("call adapter needs 'call:<manager>:<args>'")
        end
        local args = arglist and arglist ~= "" and util.split(arglist, ",") or {}
        local cmd = util.concat({ manager }, args)
        local out, code = gcpkg.capture(cmd, { cwd = cfg and cfg.cwd })
        if code ~= 0 then
            error("external manager '" .. manager .. "' failed with exit " .. code)
        end
        local includes, libdirs, libs, defines, others = {}, {}, {}, {}, {}
        for _, f in ipairs(util.split(out)) do
            if f:sub(1, 2) == "-I" then
                includes[#includes + 1] = f:sub(3)
            elseif f:sub(1, 2) == "-D" then
                defines[#defines + 1] = f:sub(3)
            elseif f:sub(1, 2) == "-L" then
                libdirs[#libdirs + 1] = f:sub(3)
            elseif f:sub(1, 2) == "-l" then
                libs[#libs + 1] = f:sub(3)
            else
                others[#others + 1] = f
            end
        end
        return manifest({
            name = "call:" .. manager,
            key = "call-" .. manager,
            version = "external",
            includes = util.uniq(includes),
            libdirs = util.uniq(libdirs),
            libs = util.uniq(libs),
            defines = util.uniq(defines),
            link_flags = util.uniq(others),
            command = cmd,
        })
    end,
})

-- Resolve "<adapter>:<name>" (or a bare name = native port).
function M.resolve(spec, cfg)
    local adapterName, name = tostring(spec):match("^([%w_-]+):(.+)$")
    if not adapterName then
        adapterName, name = "native", tostring(spec)
    end
    local adapter = M.adapters[adapterName]
    if not adapter then
        error("no backend adapter '" .. adapterName .. "'. Available: " ..
              table.concat(util.keys(M.adapters), ", "))
    end
    return adapter.resolve(name, cfg)
end

-- Foreign managers we can see on this machine. Presence alone is enough to
-- report; resolution is opt-in via "<adapter>:<name>" or a registered adapter.
function M.probe_all()
    local out = {}
    for _, name in ipairs(util.keys(M.adapters)) do
        local adapter = M.adapters[name]
        local ok, detail = false, "no probe"
        if adapter.probe then
            local success, a, b = pcall(adapter.probe)
            if success then
                ok, detail = a, b or ""
            else
                ok, detail = false, tostring(a)
            end
        end
        out[#out + 1] = { name = name, available = ok, detail = detail }
    end
    return out
end

return M
