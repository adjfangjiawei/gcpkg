-- Best-effort build-system detection. "Support almost any library" starts with
-- not hard-coding one build system: ports can call detect.build_system() and
-- dispatch to the matching gcpkg.build.* module, or override it explicitly.
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local M = {}

local RULES = {
    { "cmake", { "CMakeLists.txt" } },
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

function M.build_system(src)
    for _, rule in ipairs(RULES) do
        for _, marker in ipairs(rule[2]) do
            if fs.isfile(util.join(src, marker)) then
                return rule[1]
            end
        end
    end
    return nil
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
    return (M.build_system(src) or "unknown") .. " (" .. M.language(src) .. ")"
end

return M
