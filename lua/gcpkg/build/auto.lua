-- Dispatch on whatever build system the upstream library actually uses.
local detect = require("gcpkg.detect")
local util = require("gcpkg.util")
local M = {}

local MODULES = {
    cmake = "gcpkg.build.cmake",
    meson = "gcpkg.build.meson",
    autotools = "gcpkg.build.autotools",
    make = "gcpkg.build.make",
    cargo = "gcpkg.build.cargo",
}

function M.available(src)
    local kind = detect.build_system(src)
    return kind, MODULES[kind]
end

function M.all(o)
    local kind, module = M.available(o.src)
    if not module then
        error("no automatic adapter for '" .. tostring(kind) ..
              "'; write the build steps explicitly in build.lua or register a module")
    end
    local impl = require(module)
    if kind == "make" then
        impl.run(o)
        if o.install_target then
            impl.install(util.merge(o, { targets = { o.install_target } }))
        end
        return {}
    end
    return impl.all(o)
end

return M
