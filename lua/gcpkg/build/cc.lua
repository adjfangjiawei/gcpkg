-- Direct C/C++ compilation DSL for projects (and simple libraries).
-- Every compile command is recorded before it runs, so the project's own
-- translation units appear in compile_commands.json alongside dependencies.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

local function flags(o)
    local out = {}
    for _, f in ipairs(o.flags or {}) do
        out[#out + 1] = tostring(f)
    end
    for _, d in ipairs(o.defines or {}) do
        out[#out + 1] = "-D" .. d
    end
    for _, i in ipairs(o.includes or {}) do
        out[#out + 1] = "-I" .. i
    end
    return out
end

function M.compile(o)
    local exec = o.exec or gcpkg.exec
    local record = o.record or function() end
    local cwd = util.abs(o.cwd or fs.cwd())
    local outdir = util.abs(o.outdir or util.join(cwd, ".gcpkg", "build", "obj"), cwd)
    fs.mkdirs(outdir)
    local compiler = o.compiler or gcpkg.sys.compiler(o.cxx and "cxx" or "cc")
    local tail = flags(o)
    local objects = {}
    for _, src in ipairs(o.sources or {}) do
        local absSrc = util.abs(src, cwd)
        local obj = util.join(outdir, util.stem(absSrc) .. ".o")
        local cmd = { compiler, "-c", absSrc, "-o", obj }
        for _, a in ipairs(tail) do
            cmd[#cmd + 1] = a
        end
        record({ directory = cwd, file = absSrc, arguments = cmd, output = obj,
                 tag = o.tag or "project" })
        exec(cmd, { cwd = cwd, log = o.log })
        objects[#objects + 1] = obj
    end
    return objects
end

function M.link(o)
    local exec = o.exec or gcpkg.exec
    local cwd = util.abs(o.cwd or fs.cwd())
    local compiler = o.compiler or gcpkg.sys.compiler(o.cxx and "cxx" or "cc")
    local cmd = { compiler }
    for _, obj in ipairs(o.objects or {}) do
        cmd[#cmd + 1] = obj
    end
    cmd[#cmd + 1] = "-o"
    cmd[#cmd + 1] = util.abs(o.output, cwd)
    for _, d in ipairs(o.libdirs or {}) do
        cmd[#cmd + 1] = "-L" .. d
        cmd[#cmd + 1] = "-Wl,-rpath," .. d
    end
    for _, f in ipairs(o.flags or {}) do
        cmd[#cmd + 1] = tostring(f)
    end
    for _, lib in ipairs(o.libs or {}) do
        cmd[#cmd + 1] = "-l" .. lib
    end
    fs.mkdirs(util.dirname(util.abs(o.output, cwd)))
    exec(cmd, { cwd = cwd, log = o.log })
    return util.abs(o.output, cwd)
end

function M.executable(o)
    o.sources = o.sources or {}
    o.outdir = o.outdir or util.join(o.build_dir or fs.cwd(), "obj")
    local objects = M.compile(o)
    return M.link(util.merge(o, { objects = objects }))
end

return M
