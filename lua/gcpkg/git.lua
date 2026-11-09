-- Integrated git maintenance for managed workspaces.
--
-- The user never has to clone/fetch/checkout/submodule-update by hand: every
-- git invocation goes through this audited wrapper.  Credentials in URLs are
-- redacted by gcpkg.exec before they reach a log, proxy settings are inherited
-- from gcpkg.proxy, and file:// submodules work by allowing the local protocol
-- explicitly (git >= 2.38 otherwise refuses nested local clones).

local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local proxy = require("gcpkg.proxy")
local M = {}

local function env()
    return util.merge(proxy.env(), {
        GIT_TERMINAL_PROMPT = "0",
        GIT_ASKPASS = "/bin/true",
    })
end

local function argv(args)
    return util.concat({ "git", "-c", "protocol.file.allow=always" }, args)
end

function M.available()
    return gcpkg.have("git")
end

function M.capture(repo, args, opts)
    opts = opts or {}
    local out, code = gcpkg.capture(argv(args), {
        cwd = repo, env = util.merge(env(), opts.env or {}),
    })
    return (out or ""):gsub("%s+$", ""), code or 1
end

function M.run(repo, args, opts)
    opts = opts or {}
    return gcpkg.exec(argv(args), {
        cwd = repo, env = util.merge(env(), opts.env or {}),
        log = opts.log, quiet = opts.quiet, check = opts.check,
    })
end

function M.is_repo(repo)
    return fs.isdir(util.join(repo, ".git")) or fs.isfile(util.join(repo, ".git"))
end

function M.remote(repo)
    local out, code = M.capture(repo, { "remote", "get-url", "origin" })
    if code ~= 0 or out == "" then return nil end
    return out
end

function M.clone(url, dest, opts)
    opts = opts or {}
    if not M.available() then error("git not found in PATH") end
    if M.is_repo(dest) then return false end
    if fs.isdir(dest) then
        local entries = fs.listdir(dest) or {}
        if #entries > 0 then
            error("cannot clone into non-empty directory without a git checkout: " .. dest)
        end
        fs.rm(dest)
    end
    fs.mkdirs(util.dirname(dest))
    local source = tostring(url)
    if opts.base and not source:match("^%a[%w+%.%-]*://") and not util.isabs(source) then
        source = util.abs(source, opts.base)
    end
    local cmd = { "clone" }
    if opts.quiet then cmd[#cmd + 1] = "--quiet" end
    cmd[#cmd + 1] = source
    cmd[#cmd + 1] = dest
    return M.run(util.dirname(dest), cmd, opts)
end

function M.fetch(repo, opts)
    opts = opts or {}
    if not M.remote(repo) then return false end
    local code = M.run(repo, { "fetch", "--tags", "--prune", "origin" }, opts)
    -- A branch/tag ref (or a pinned SHA) is fetched separately with check=false:
    -- some servers refuse arbitrary object ids, but the general fetch above
    -- already brought the remote refs up to date.
    if opts.ref and opts.ref ~= "" then
        M.run(repo, { "fetch", "origin", opts.ref },
              { check = false, log = opts.log, quiet = opts.quiet })
    end
    if opts.sha and opts.sha ~= "" then
        M.run(repo, { "fetch", "origin", opts.sha },
              { check = false, log = opts.log, quiet = opts.quiet })
    end
    return code
end

function M.rev_parse(repo, rev)
    local out, code = M.capture(repo, { "rev-parse", "--verify", tostring(rev) .. "^{commit}" })
    if code ~= 0 then return nil end
    local sha = out:match("^([0-9a-fA-F]+)")
    return sha
end

function M.head(repo)
    return M.rev_parse(repo, "HEAD")
end

function M.has_commit(repo, sha)
    if not sha or sha == "" then return false end
    local _, code = M.capture(repo, { "cat-file", "-e", tostring(sha) .. "^{commit}" })
    return code == 0
end

function M.branch(repo)
    local out, code = M.capture(repo, { "rev-parse", "--abbrev-ref", "HEAD" })
    if code ~= 0 then return "unknown" end
    return out
end

function M.dirty(repo, opts)
    opts = opts or {}
    local out, code = M.capture(repo, {
        "status", "--porcelain", "--untracked-files=no",
        "--ignore-submodules=all",
    })
    if code ~= 0 then return true end
    return out ~= ""
end

function M.checkout(repo, rev, opts)
    opts = opts or {}
    if M.dirty(repo) and not opts.force then
        error("repository has local tracked changes: " .. repo ..
              " (commit them, or pass --force to discard)")
    end
    local cmd = { "checkout" }
    if opts.force then cmd[#cmd + 1] = "--force" end
    cmd[#cmd + 1] = "--detach"
    cmd[#cmd + 1] = tostring(rev)
    return M.run(repo, cmd, opts)
end

function M.resolve_latest(repo, ref)
    local candidates = {}
    if ref and ref ~= "" then
        candidates[#candidates + 1] = "origin/" .. ref
        candidates[#candidates + 1] = "refs/remotes/origin/" .. ref
        candidates[#candidates + 1] = "refs/tags/" .. ref
        candidates[#candidates + 1] = ref
    end
    candidates[#candidates + 1] = "origin/HEAD"
    candidates[#candidates + 1] = "FETCH_HEAD"
    candidates[#candidates + 1] = "HEAD"
    for _, candidate in ipairs(candidates) do
        local sha = M.rev_parse(repo, candidate)
        if sha then return sha end
    end
    return nil
end

function M.submodule_sync(repo, opts)
    opts = opts or {}
    return M.run(repo, { "submodule", "sync", "--recursive" }, opts)
end

function M.submodule_update(repo, mode, opts)
    opts = opts or {}
    M.submodule_sync(repo, opts)
    local cmd = { "submodule", "update", "--init" }
    if mode == "recursive" or mode == "shallow" then cmd[#cmd + 1] = "--recursive" end
    if mode == "shallow" then
        cmd[#cmd + 1] = "--depth"
        cmd[#cmd + 1] = "1"
    end
    if opts.force then cmd[#cmd + 1] = "--force" end
    return M.run(repo, cmd, opts)
end

-- `git submodule status --recursive` reports the exact gitlink commit for
-- every nested submodule.  These pins are recorded in workspace.lock and
-- checked on subsequent syncs, so a recursive sync is reproducible.
function M.submodule_pins(repo)
    local out, code = M.capture(repo, { "submodule", "status", "--recursive" })
    local pins = {}
    if code ~= 0 then return pins end
    for _, line in ipairs(util.lines(out)) do
        local mark, sha, path = line:match("^%s*([%-+ U])([0-9a-fA-F]+)%s+([^%s]+)")
        if sha and path then
            pins[#pins + 1] = {
                path = path, commit = sha,
                initialized = mark ~= "-",
                status = (mark == " " and "clean" or mark),
            }
        end
    end
    table.sort(pins, function(a, b) return a.path < b.path end)
    return pins
end

function M.submodule_status(repo)
    local out, code = M.capture(repo, { "submodule", "status", "--recursive" })
    if code ~= 0 then return "" end
    return out
end

function M.submodule_add(repo, url, path, opts)
    opts = opts or {}
    path = tostring(path or "")
    if path == "" or util.isabs(path) or path:match("^%.%./") then
        error("submodule path must be relative and inside the repository: " .. path)
    end
    fs.mkdirs(repo)
    local cmd = { "submodule", "add" }
    if opts.ref and opts.ref ~= "" then
        cmd[#cmd + 1] = "--branch"
        cmd[#cmd + 1] = opts.ref
    end
    cmd[#cmd + 1] = url
    cmd[#cmd + 1] = path
    M.run(repo, cmd, opts)
    local child = util.join(repo, path)
    if opts.sha and opts.sha ~= "" then
        M.run(child, { "checkout", "--detach", opts.sha }, opts)
        M.run(repo, { "add", ".gitmodules", path }, opts)
    end
    if opts.commit then
        M.run(repo, { "add", ".gitmodules", path }, opts)
        M.commit_paths(repo, { ".gitmodules", path },
                       opts.message or ("gcpkg: add submodule " .. path), opts)
    end
    return child
end

function M.commit_paths(repo, paths, message, opts)
    opts = opts or {}
    local cmd = {
        "-c", "user.name=gcpkg", "-c", "user.email=gcpkg@localhost",
        "commit", "-m", message or "gcpkg: update managed workspace",
    }
    for _, p in ipairs(paths) do cmd[#cmd + 1] = p end
    -- `git -c ... commit <paths>` commits the current content of those paths.
    return M.run(repo, cmd, opts)
end

function M.status(repo)
    local info = {
        path = repo, repo = M.is_repo(repo),
        head = M.is_repo(repo) and M.head(repo) or "untracked",
        branch = M.is_repo(repo) and M.branch(repo) or "-",
        dirty = M.is_repo(repo) and M.dirty(repo) or false,
        remote = M.is_repo(repo) and M.remote(repo) or nil,
        submodules = M.is_repo(repo) and M.submodule_pins(repo) or {},
    }
    return info
end

return M
