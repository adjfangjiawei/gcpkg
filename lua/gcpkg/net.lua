-- Source acquisition. Deliberately implemented with ordinary command-line
-- tools (curl / tar / git) instead of libcurl+libarchive bindings: any exotic
-- source type can be added by a port as a plain Lua function.
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local M = {}

function M.sha256(path)
    local out, code = gcpkg.capture({ "sha256sum", path })
    if code ~= 0 then
        return nil
    end
    return out:match("^(%x+)")
end

function M.download(url, dest, expected, opts)
    opts = opts or {}
    fs.mkdirs(util.dirname(dest))
    if fs.isfile(dest) then
        if not expected or M.sha256(dest) == expected then
            return dest
        end
        gcpkg.log.warn("checksum mismatch, re-downloading " .. url)
        fs.rm(dest)
    end
    gcpkg.log.step("downloading " .. url)
    gcpkg.exec({ "curl", "-fL", "--retry", "3", "--connect-timeout", "20", "-o", dest, url },
               { log = opts.log })
    if expected then
        local got = M.sha256(dest)
        if got ~= expected then
            error("sha256 mismatch for " .. url .. "\n  expected " .. expected ..
                  "\n  got      " .. tostring(got))
        end
    end
    return dest
end

function M.extract(archive, dest, strip, opts)
    opts = opts or {}
    fs.mkdirs(dest)
    if util.endswith(archive, ".zip") then
        gcpkg.exec({ "unzip", "-q", "-o", archive, "-d", dest }, { log = opts.log })
    else
        gcpkg.exec({ "tar", "-xf", archive, "-C", dest,
                     "--strip-components=" .. tostring(strip or 1) }, { log = opts.log })
    end
end

function M.git_clone(url, ref, dest, opts)
    opts = opts or {}
    fs.mkdirs(util.dirname(dest))
    local cmd = { "git", "clone", "--depth", "1" }
    if ref and ref ~= "" then
        cmd[#cmd + 1] = "--branch"
        cmd[#cmd + 1] = ref
    end
    cmd[#cmd + 1] = url
    cmd[#cmd + 1] = dest
    gcpkg.exec(cmd, { log = opts.log })
end

-- prepare(source, srcDir, opts) -> srcDir
-- source can be declarative (url / git / dir) or a function for anything else.
function M.prepare(source, srcDir, opts)
    opts = opts or {}
    if not source then
        fs.mkdirs(srcDir)
        return srcDir
    end
    if type(source) == "function" then
        fs.mkdirs(srcDir)
        source({ dir = srcDir, exec = opts.exec or gcpkg.exec, log = opts.log })
        return srcDir
    end
    if type(source) ~= "table" then
        error("port.source must be a table or a function")
    end

    local marker = util.join(srcDir, ".gcpkg-source-ready")
    if fs.isfile(marker) then
        return srcDir
    end
    fs.mkdirs(srcDir)

    if source.git then
        local tmp = srcDir .. ".git-checkout"
        fs.rm(tmp)
        M.git_clone(source.git, source.ref, tmp, opts)
        -- move contents into the stable srcDir (strip the extra directory level)
        for _, entry in ipairs(fs.listdir(tmp)) do
            gcpkg.exec({ "mv", util.join(tmp, entry), srcDir }, { log = opts.log })
        end
        fs.rm(tmp)
    elseif source.dir then
        -- A local/vendor directory: used as-is (no copy).
        srcDir = util.join(source.dir)
    elseif source.url then
        local name = util.basename(source.url):gsub("%?.*$", "")
        local cache = util.join(opts.cache_dir or util.join(srcDir, "..", "cache"), name)
        M.download(source.url, cache, source.sha256, opts)
        M.extract(cache, srcDir, source.strip or 1, opts)
    else
        error("port.source needs url, git or dir")
    end
    fs.write(marker, source.url or source.git or source.dir or "custom")
    return srcDir
end

return M
