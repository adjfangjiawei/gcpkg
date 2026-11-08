local sys = gcpkg.sys
local util = require("gcpkg.util")
local M = {}

function M.mkdirs(p)
    if p and p ~= "" then
        return sys.mkdir(p)
    end
end

function M.read(p)
    return sys.read(p)
end

function M.write(p, data)
    M.mkdirs(util.dirname(p))
    return sys.write(p, tostring(data))
end

function M.append(p, data)
    M.mkdirs(util.dirname(p))
    return sys.append(p, tostring(data))
end

function M.lines(p)
    local s = sys.read(p)
    if not s then
        return {}
    end
    return util.lines(s)
end

function M.isfile(p)
    return sys.isfile(p)
end

function M.isdir(p)
    return sys.isdir(p)
end

function M.exists(p)
    return sys.exists(p)
end

function M.listdir(p)
    return sys.listdir(p)
end

function M.cwd()
    return sys.cwd()
end

function M.realpath(p)
    return sys.realpath(p)
end

function M.copy(src, dst)
    local data = sys.read(src)
    if not data then
        return false
    end
    M.write(dst, data)
    return true
end

function M.rm(p)
    return sys.exec({ cmd = { "rm", "-rf", p }, quiet = true })
end

function M.symlink(target, link)
    M.mkdirs(util.dirname(link))
    return sys.symlink(target, link)
end

return M
