-- Source acquisition. Deliberately implemented with ordinary command-line
-- tools (curl / tar / git) instead of libcurl+libarchive bindings: any exotic
-- source type can be added by a port as a plain Lua function.
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local proxy = require("gcpkg.proxy")
local M = {}

local function now()
    if gcpkg.sys.now then
        return gcpkg.sys.now()
    end
    return os.time()
end

local function fileSize(path)
    if gcpkg.sys.size then
        return gcpkg.sys.size(path) or 0
    end
    local out, code = gcpkg.capture({ "stat", "-c", "%s", path })
    return code == 0 and tonumber(out) or 0
end

local function humanBytes(n)
    n = tonumber(n) or 0
    if n >= 1024 * 1024 then
        return string.format("%.1f MiB", n / (1024 * 1024))
    elseif n >= 1024 then
        return string.format("%.1f KiB", n / 1024)
    end
    return tostring(n) .. " B"
end

local function humanDuration(seconds)
    seconds = math.max(tonumber(seconds) or 0, 0)
    if seconds < 1 then
        return "<1s"
    elseif seconds < 60 then
        return string.format("%.1fs", seconds)
    end
    return string.format("%dm %.0fs", math.floor(seconds / 60), seconds % 60)
end

-- Print a phase on the terminal AND append it to the per-port build log.
-- gcpkg.log goes to stdout; child curl/tar output is redirected to opts.log
-- by gcpkg.exec, so without this the build log has no phase markers either.
local function phase(opts, level, message)
    opts = opts or {}
    gcpkg.log[level](message)
    if opts.log and opts.log ~= "" then
        pcall(fs.append, opts.log, "[gcpkg:" .. level .. "] " .. message .. "\n")
    end
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
end

local function shellJoin(args)
    local out = {}
    for _, arg in ipairs(args) do
        out[#out + 1] = shellQuote(arg)
    end
    return table.concat(out, " ")
end

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
            phase(opts, "info", "cached " .. util.basename(dest) ..
                  " (" .. humanBytes(fileSize(dest)) .. ")")
            return dest
        end
        phase(opts, "warn", "checksum mismatch, re-downloading " .. url)
        fs.rm(dest)
    end
    -- A configured but unreachable proxy must not turn into a silent direct
    -- download or a 20-second connect stall. The probe uses host:port only.
    proxy.assert_reachable("download " .. url)
    phase(opts, "step", "downloading " .. url)
    local started = now()
    -- Proxy credentials stay in a private 0600 curl config, never in argv.
    -- -q ignores any inherited .curlrc; -K then forces THIS resolved proxy.
    local env = proxy.env()
    local cmd = { "curl" }
    if env.GCPKG_CURL_CONFIG then
        cmd[#cmd + 1] = "-q"
        cmd[#cmd + 1] = "-K"
        cmd[#cmd + 1] = env.GCPKG_CURL_CONFIG
    end
    for _, a in ipairs({ "-fL", "--retry", "3", "--connect-timeout", "20",
                         "-o", dest, url }) do
        cmd[#cmd + 1] = a
    end
    -- A proxy can drop a codeload response mid-stream (curl exit 18). Curl's
    -- own --retry does not cover every partial-transfer case, so retry the
    -- whole download from a clean destination a bounded number of times.
    local attempts, code = 8, nil
    for attempt = 1, attempts do
        code = gcpkg.exec(cmd, { log = opts.log, env = env, check = false })
        if code == 0 then
            break
        end
        if fs.isfile(dest) then
            fs.rm(dest)
        end
        if attempt < attempts then
            phase(opts, "warn", "download failed (exit " .. tostring(code) ..
                  "), retrying " .. attempt .. "/" .. attempts .. " " .. url)
        end
    end
    if code ~= 0 then
        error("download failed after " .. attempts .. " attempts (exit " ..
              tostring(code) .. "): " .. url)
    end
    local elapsed = math.max(now() - started, 0)
    local size = fileSize(dest)
    local rate = ""
    if elapsed >= 0.1 then
        rate = string.format(" (%.1f MiB/s)",
              size / (1024 * 1024) / elapsed)
    end
    phase(opts, "info", string.format("downloaded %s in %s%s -> %s",
          humanBytes(size), humanDuration(elapsed), rate, dest))
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
    local started = now()
    local base = util.basename(archive)
    local size = fileSize(archive)
    phase(opts, "step", "extracting " .. base .. " (" .. humanBytes(size) ..
          ") -> " .. dest)
    phase(opts, "info", "  expanding source tree: progress is printed while tar runs")

    if util.endswith(archive, ".zip") then
        local cmd = { "unzip", "-q", "-o", archive, "-d", dest }
        gcpkg.exec(cmd, { log = opts.log })
    else
        -- GNU tar defaults to restoring owner, mode, mtime, ACLs, SELinux and
        -- xattrs for EVERY entry. A CMake source tree has ~29k entries; on
        -- metadata-heavy mounts those extra syscalls dominate the wall time.
        -- Source builds only need the bytes, so skip all of that metadata.
        local tarArgs = {
            "tar", "-xf", archive, "-C", dest,
            "--strip-components=" .. tostring(strip or 1),
            "-m", "--no-same-owner", "--no-same-permissions",
            "--no-acls", "--no-selinux", "--no-xattrs",
            -- %T reports bytes read and the current rate; echo= writes to
            -- stderr, which the pipeline below shows on the terminal too.
            "--checkpoint=2000",
            "--checkpoint-action=echo=  expanding source tree: %T",
        }
        if opts.log and opts.log ~= "" then
            fs.append(opts.log, "+ " .. table.concat(tarArgs, " ") .. "\n")
            -- tee keeps tar's progress/errors on the terminal while also
            -- appending them to the per-port log. pipefail preserves tar's RC.
            local inner = shellJoin(tarArgs) .. " 2>&1"
            local cmd = { "bash", "-o", "pipefail", "-c",
                          inner .. " | tee -a " .. shellQuote(opts.log) }
            gcpkg.exec(cmd, {})
        else
            gcpkg.exec(tarArgs, {})
        end
    end
    phase(opts, "info", string.format("extracted %s in %s",
          base, humanDuration(math.max(now() - started, 0))))
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
    proxy.assert_reachable("clone " .. url)
    phase(opts, "step", "cloning " .. url)
    local started = now()
    -- proxy.env() also carries GIT_CONFIG_COUNT/KEY_0/VALUE_0, which forces
    -- git's http.proxy without putting a credentialed URL on the command line.
    gcpkg.exec(cmd, { log = opts.log, env = proxy.env() })
    phase(opts, "info", string.format("cloned %s in %s", url,
          humanDuration(math.max(now() - started, 0))))
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

    -- The marker records the exact source identity: a port may legitimately
    -- change its URL or checksum while keeping name/version (e.g. after a
    -- dead upstream tag). Without this check the old unpacked tree would be
    -- reused and the build would silently use the wrong sources.
    local marker = util.join(srcDir, ".gcpkg-source-ready")
    local identity = source.url or source.git or source.dir or "custom"
    if source.sha256 then
        identity = identity .. "|" .. source.sha256
    end
    if source.git and source.ref then
        identity = identity .. "|" .. source.ref
    end
    if fs.isfile(marker) then
        if fs.read(marker) == identity then
            phase(opts, "info", "reusing prepared sources " .. srcDir)
            return srcDir
        end
        phase(opts, "warn", "source identity changed, refreshing " .. srcDir)
        fs.rm(srcDir)
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
        -- Scope the download cache by the port's stable srcDir key. Several
        -- ports (e.g. Boost mp11/describe and ut/sol2) share the same upstream
        -- tag basename; without this prefix their tarballs overwrite one
        -- another and trigger bogus "checksum mismatch, re-downloading" warnings.
        local cache = util.join(opts.cache_dir or util.join(srcDir, "..", "cache"),
                                util.basename(srcDir) .. "-" .. name)
        M.download(source.url, cache, source.sha256, opts)
        M.extract(cache, srcDir, source.strip or 1, opts)
    else
        error("port.source needs url, git or dir")
    end
    fs.write(marker, identity)
    return srcDir
end

return M
