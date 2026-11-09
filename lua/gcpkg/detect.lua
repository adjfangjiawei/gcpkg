-- Best-effort build-system detection. "Support almost any library" starts with
-- not hard-coding one build system: ports can call detect.build_system() and
-- dispatch to the matching gcpkg.build.* module, or override it explicitly.
--
-- Inner package managers (a project's own `canon`) are detected separately
-- from build systems.  A managed project may use BOTH: detect.build_systems()
-- returns the package manager first, then the build system, so gcpkg can run
-- `canon` and then CMake/Meson/GN/Makefile with the same injected environment.
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local M = {}

local PACKAGE_MANAGERS = {
    { "canon", { "canonfile", "Canonfile", "canon.toml", "canon.json",
                 "canon.yaml", "canon.lock" } },
}

local RULES = {
    { "cmake", { "CMakeLists.txt" } },
    { "gn", { ".gn", "BUILD.gn" } },
    { "meson", { "meson.build" } },
    { "cargo", { "Cargo.toml" } },
    { "go", { "go.mod" } },
    { "npm", { "package.json" } },
    { "python", { "pyproject.toml", "setup.py" } },
    { "autotools", { "configure", "configure.ac", "autogen.sh" } },
    { "perl", { "Configure" } },
    { "make", { "Makefile", "makefile", "GNUmakefile" } },
    { "ninja", { "build.ninja" } },
}

local function hasAny(src, markers)
    for _, marker in ipairs(markers) do
        if fs.isfile(util.join(src, marker)) then return true end
    end
    return false
end

function M.package_managers(src)
    local out = {}
    for _, rule in ipairs(PACKAGE_MANAGERS) do
        if hasAny(src, rule[2]) then out[#out + 1] = rule[1] end
    end
    return out
end

function M.build_system(src)
    for _, rule in ipairs(RULES) do
        if hasAny(src, rule[2]) then return rule[1] end
    end
    return nil
end

-- Ordered inner systems for a project that has no explicit `systems:` list.
function M.build_systems(src)
    local out = M.package_managers(src)
    local kind = M.build_system(src)
    if kind then out[#out + 1] = kind end
    return out
end

function M.language(src)
    local counts = { c = 0, cpp = 0 }
    local function walk(dir, depth)
        if depth > 2 then
            return
        end
        for _, entry in ipairs(fs.listdir(dir)) do
            local p = util.join(dir, entry)
            if fs.isdir(p) then
                walk(p, depth + 1)
            elseif fs.isfile(p) then
                local ext = util.ext(p)
                if ext == "c" then
                    counts.c = counts.c + 1
                elseif ext == "cc" or ext == "cpp" or ext == "cxx" then
                    counts.cpp = counts.cpp + 1
                end
            end
        end
    end
    walk(src, 0)
    return counts.cpp > counts.c and "c++" or "c", counts
end

function M.describe(src)
    local systems = M.build_systems(src)
    return (#systems > 0 and table.concat(systems, "+") or "unknown") ..
           " (" .. M.language(src) .. ")"
end

return M
