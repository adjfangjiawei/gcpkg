-- Orchestration for `gcpkg workspace ...`: git maintenance, dependency-tree
-- resolution, per-project dependency injection, inner builds and one unified
-- compilation database for the whole managed workspace.

local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local json = require("gcpkg.json")
local yaml = require("gcpkg.yaml")
local log = require("gcpkg.log")
local managed = require("gcpkg.managed")
local git = require("gcpkg.git")
local inject = require("gcpkg.inject")
local inner = require("gcpkg.inner")
local compdb = require("gcpkg.compdb")
local port = require("gcpkg.port")
local workspace = require("gcpkg.workspace")
local storeMod = require("gcpkg.store")
local features = require("gcpkg.features")
local proxy = require("gcpkg.proxy")

local M = {}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function rootOf(opts)
    opts = opts or {}
    local start = opts.dir and util.abs(opts.dir) or fs.cwd()
    local found = managed.find_root(start)
    if found then return found end
    if opts.dir and fs.isfile(managed.file(util.abs(opts.dir))) then
        return util.abs(opts.dir)
    end
    error("not inside a managed workspace (no workspace.yaml); run `gcpkg workspace new DIR`")
end

local function context(root, cfg, opts)
    local data = managed.read(root)
    local edges = managed.infer_edges(root, data)
    local order = managed.order(data.repos, edges)
    local byname = {}
    for _, r in ipairs(data.repos) do byname[r.name] = r end
    return { root = root, cfg = cfg or {}, opts = opts or {},
             data = data, edges = edges, order = order, byname = byname }
end

local function gdir(root) return managed.gcpkg_dir(root) end
local function logFile(root, name)
    local p = util.join(gdir(root), "logs", name .. ".log")
    fs.mkdirs(util.dirname(p))
    return p
end

local function lockBase(root, data, order)
    local lock = managed.read_lock(root) or {}
    lock.workspace = data.workspace
    lock.packages = data.packages
    lock.repos = lock.repos or {}
    local by = managed.lock_index(lock)
    local repos = {}
    for i, r in ipairs(order) do
        local base = by[r.name] or {}
        repos[i] = util.merge(base, {
            name = r.name, order = i, path = managed.repo_dir(root, r),
            url = r.url, ref = r.ref,
            commit = base.commit or "untracked",
            submodules = r.submodules or "none",
            systems = r.systems, depends = r.depends,
            packages = util.concat(data.packages, r.packages),
            submodule_commits = base.submodule_commits or {},
            resolved = base.resolved or {},
        })
    end
    lock.repos = repos
    return lock
end

local function writeLock(root, data, order, updater)
    local lock = lockBase(root, data, order)
    for i, r in ipairs(order) do
        if updater then updater(lock.repos[i], r, i) end
    end
    managed.write_lock(root, lock)
    return lock
end

local function lockBy(root)
    return managed.lock_index(managed.read_lock(root))
end

local function verifyPins(oldPins, actual)
    local by = {}
    for _, p in ipairs(oldPins or {}) do
        by[tostring(p.path)] = tostring(p.commit)
    end
    for _, p in ipairs(actual or {}) do
        local expected = by[tostring(p.path)]
        if expected and expected ~= tostring(p.commit) then
            error("submodule pin changed for " .. p.path .. ": locked " ..
                  expected .. " but parent commit records " .. p.commit ..
                  "; run `gcpkg workspace sync --update` to accept it")
        end
    end
end

function M.init(dir, name, opts)
    return managed.init(dir, name)
end

function M.add(root, opts)
    return managed.add(root, opts)
end

function M.remove(root, name)
    return managed.remove(root, name)
end

function M.list(root, cfg, opts)
    local c = context(root, cfg, opts)
    local locked = lockBy(root)
    log.step(c.data.workspace .. ": " .. #c.order .. " repositories (topological order)")
    for i, r in ipairs(c.order) do
        local l = locked[r.name] or {}
        local dir = managed.repo_dir(root, r)
        log.info(string.format("  %2d. %-16s %-22s %-10s deps=[%s] systems=[%s]%s",
            i, r.name, fs.isdir(dir) and "present" or "missing",
            tostring(l.commit or "untracked"):sub(1, 10),
            table.concat(r.depends or {}, ","),
            table.concat(r.systems or { "auto" }, ","),
            r.url and ("  " .. r.url) or ("  " .. dir)))
    end
    if #c.data.packages > 0 then
        log.info("  shared packages: " .. table.concat(c.data.packages, ", "))
    end
    return 0
end

function M.graph(root, cfg, opts)
    local c = context(root, cfg, opts)
    log.step("dependency tree for " .. c.data.workspace .. ":")
    for i, r in ipairs(c.order) do
        local deps = util.uniq(util.concat(r.depends or {}, c.edges[r.name] or {}))
        log.info(string.format("  %2d. %-16s <- [%s]", i, r.name, table.concat(deps, ", ")))
    end
    return 0
end

function M.status(root, cfg, opts)
    local c = context(root, cfg, opts)
    local locked = lockBy(root)
    log.step("git status for " .. c.data.workspace .. ":")
    for i, r in ipairs(c.order) do
        local dir = managed.repo_dir(root, r)
        local l = locked[r.name] or {}
        if not fs.isdir(dir) then
            log.info(string.format("  %-16s MISSING (%s)", r.name, dir))
        elseif not git.is_repo(dir) then
            log.info(string.format("  %-16s local path, no git metadata (gcpkg does not modify it)", r.name))
        else
            local s = git.status(dir)
            log.info(string.format("  %-16s %-10s %-8s %s  submodules=%d locked=%s%s",
                r.name, tostring(s.head or "?"):sub(1, 10), s.branch or "?",
                s.dirty and "dirty" or "clean", #s.submodules,
                tostring(l.commit or "untracked"):sub(1, 10),
                s.remote and ("  " .. s.remote) or ""))
        end
    end
    return 0
end

function M.sync(root, cfg, opts)
    opts = opts or {}
    local c = context(root, cfg, opts)
    local locked = lockBy(root)
    local gitLog = logFile(root, "git")
    local out = {}
    for i, r in ipairs(c.order) do
        local dir = managed.repo_dir(root, r)
        local old = locked[r.name] or {}
        local pins = {}
        local commit = "untracked"
        if r.url then
            if not git.available() then error("git not found in PATH") end
            if not git.is_repo(dir) then
                log.step("cloning " .. r.name .. " -> " .. dir)
                git.clone(r.url, dir, { base = root, log = gitLog, quiet = true })
            end
            local lockedCommit = old.commit
            if lockedCommit == "untracked" or lockedCommit == "false" then lockedCommit = nil end
            local needFetch = opts.update or (lockedCommit and not git.has_commit(dir, lockedCommit))
            if needFetch then
                log.step("fetching " .. r.name)
                git.fetch(dir, { ref = r.ref, log = gitLog, quiet = true })
            end
            local desired
            if r.commit then
                desired = r.commit
            elseif opts.update then
                desired = git.resolve_latest(dir, r.ref)
            elseif lockedCommit then
                desired = lockedCommit
            else
                desired = git.resolve_latest(dir, r.ref)
            end
            if desired and not git.has_commit(dir, desired) then
                git.fetch(dir, { ref = r.ref, sha = desired,
                                 log = gitLog, quiet = true })
            end
            if desired then
                log.step("checkout " .. r.name .. " @ " .. tostring(desired):sub(1, 10))
                git.checkout(dir, desired, { force = opts.force, log = gitLog })
            end
            if r.submodules then
                log.step("syncing submodules for " .. r.name .. " (" .. r.submodules .. ")")
                git.submodule_update(dir, r.submodules, { force = opts.force, log = gitLog })
                pins = git.submodule_pins(dir)
                if not opts.update then verifyPins(old.submodule_commits, pins) end
            end
            commit = git.head(dir) or "untracked"
        else
            if not fs.isdir(dir) then
                error("local repo path does not exist: " .. dir .. " (add a url to let gcpkg clone it)")
            end
            if git.is_repo(dir) then
                commit = git.head(dir) or "untracked"
                pins = git.submodule_pins(dir)
            else
                log.info("  " .. r.name .. ": local path without git metadata; left untouched")
            end
        end
        out[i] = {
            name = r.name, order = i, path = dir, url = r.url, ref = r.ref,
            commit = commit, submodules = r.submodules or "none",
            systems = r.systems, depends = r.depends,
            packages = util.concat(c.data.packages, r.packages),
            submodule_commits = pins, resolved = old.resolved or {},
        }
    end
    managed.write_lock(root, { workspace = c.data.workspace, repos = out,
                               packages = c.data.packages })
    log.step(#out .. " repositories synchronised; pins written to " .. managed.lock_file(root))
    return out
end

function M.update(root, cfg, opts)
    opts = util.merge(opts or {}, { update = true })
    return M.sync(root, cfg, opts)
end

function M.pin(root, name, sha, opts)
    opts = opts or {}
    local data = managed.read(root)
    local r = nil
    for _, candidate in ipairs(data.repos) do
        if candidate.name == name then r = candidate; break end
    end
    if not r then error("repo not in workspace: " .. tostring(name)) end
    if opts.unpin then
        r.commit = nil
    elseif sha and sha ~= "" then
        r.commit = sha
    else
        local dir = managed.repo_dir(root, r)
        if not git.is_repo(dir) then
            error("cannot infer pin for " .. name .. " without a git checkout; pass a SHA")
        end
        r.commit = git.head(dir)
    end
    managed.write(root, data)
    local edges = managed.infer_edges(root, data)
    local order = managed.order(data.repos, edges)
    writeLock(root, data, order, function(e, repo)
        if repo.name == name then
            e.commit = r.commit or "untracked"
        end
    end)
    log.step((r.commit and ("pinned " .. name .. " @ " .. r.commit) or
              ("unpinned " .. name)) .. " in " .. managed.file(root))
    return r.commit
end

local function updateSubmoduleLock(root, repoName, pins)
    local data = managed.read(root)
    local order = managed.order(data.repos, managed.infer_edges(root, data))
    writeLock(root, data, order, function(e)
        if e.name == repoName then e.submodule_commits = pins or {} end
    end)
end

function M.submodule(root, action, opts)
    opts = opts or {}
    local data = managed.read(root)
    local order = managed.order(data.repos, managed.infer_edges(root, data))
    local target = opts.repo
    local repos = {}
    for _, r in ipairs(order) do
        if not target or r.name == target then repos[#repos + 1] = r end
    end
    if #repos == 0 then error("repo not in workspace: " .. tostring(target)) end
    local gitLog = logFile(root, "git")
    if action == "status" then
        log.step("submodule status:")
        for _, r in ipairs(repos) do
            local dir = managed.repo_dir(root, r)
            if git.is_repo(dir) then
                local text = git.submodule_status(dir)
                log.info("  " .. r.name .. " (" .. dir .. ")")
                for _, line in ipairs(util.lines(text)) do
                    if trim(line) ~= "" then log.info("    " .. line) end
                end
                if trim(text) == "" then log.info("    no git submodules") end
            else
                log.info("  " .. r.name .. ": no git metadata")
            end
        end
        return 0
    elseif action == "sync" then
        for _, r in ipairs(repos) do
            local dir = managed.repo_dir(root, r)
            if not git.is_repo(dir) then error("not a git checkout: " .. dir) end
            local mode = opts.submodules or r.submodules or "recursive"
            log.step("syncing git submodules for " .. r.name .. " (" .. mode .. ")")
            git.submodule_update(dir, mode, { force = opts.force, log = gitLog })
            updateSubmoduleLock(root, r.name, git.submodule_pins(dir))
        end
        return 0
    elseif action == "pin" then
        for _, r in ipairs(repos) do
            local dir = managed.repo_dir(root, r)
            if not git.is_repo(dir) then error("not a git checkout: " .. dir) end
            local pins = git.submodule_pins(dir)
            updateSubmoduleLock(root, r.name, pins)
            log.step("recorded " .. #pins .. " submodule pins for " .. r.name)
        end
        return 0
    elseif action == "add" then
        if not opts.repo then error("workspace submodule add needs --repo=NAME") end
        if not opts.url or not opts.path then
            error("workspace submodule add needs --url=URL and --path=PATH")
        end
        local r = managed.repo(root, opts.repo)
        if not r then error("repo not in workspace: " .. opts.repo) end
        local dir = managed.repo_dir(root, r)
        if not git.is_repo(dir) then error("not a git checkout: " .. dir) end
        git.submodule_add(dir, opts.url, opts.path, {
            ref = opts.ref, sha = opts.sha, commit = opts.git_commit,
            message = opts.message, log = gitLog,
        })
        updateSubmoduleLock(root, r.name, git.submodule_pins(dir))
        log.step("added submodule " .. opts.path .. " to " .. r.name ..
                 (opts.git_commit and " (committed by gcpkg)" or " (staged for the next commit)"))
        return 0
    end
    error("unknown submodule action: " .. tostring(action))
end

local function compilerValue(kind, fallback)
    local v = gcpkg.sys.compiler(kind)
    if not v or v == "" or v:find("gcpkg-intercept") or
       v:find("/cc$") or v:find("/c%+%+$") then
        return fallback
    end
    return v
end

local function desiredSystems(opts, repo)
    if opts.system or opts.systems then
        local v = opts.systems or opts.system
        if type(v) == "table" then return v end
        local out = {}
        for part in tostring(v):gmatch("[^,%s]+") do out[#out + 1] = part end
        return out
    end
    return repo.systems or { "auto" }
end

local function neededSet(target, byname, edges)
    if not target then return nil end
    local needed = {}
    local function visit(name)
        if needed[name] then return end
        local r = byname[name]
        if not r then error("repo not in workspace: " .. name) end
        needed[name] = true
        for _, d in ipairs(r.depends or {}) do visit(d) end
        for _, d in ipairs(edges[name] or {}) do visit(d) end
    end
    visit(target)
    return needed
end

local function addExistingDir(out, path)
    if fs.isdir(path) then out[#out + 1] = path end
end

local function projectExports(r, prefix, buildDir)
    local includes, libdirs, binaries, libs, pkgdirs = {}, {}, {}, {}, {}
    addExistingDir(includes, util.join(prefix, "include"))
    addExistingDir(includes, util.join(buildDir, "include"))
    for _, p in ipairs({ util.join(prefix, "lib"), util.join(prefix, "lib64"),
                         util.join(buildDir, "lib") }) do
        if fs.isdir(p) then
            libdirs[#libdirs + 1] = p
            for _, name in ipairs(fs.listdir(p) or {}) do
                local stem = name:match("^lib(.*)%.a$") or name:match("^lib(.*)%.so") or nil
                if stem then libs[#libs + 1] = stem end
            end
        end
    end
    addExistingDir(binaries, util.join(prefix, "bin"))
    addExistingDir(binaries, util.join(buildDir, "bin"))
    for _, p in ipairs({ util.join(prefix, "lib", "pkgconfig"),
                         util.join(prefix, "lib64", "pkgconfig"),
                         util.join(prefix, "share", "pkgconfig") }) do
        addExistingDir(pkgdirs, p)
    end
    for _, e in ipairs(r.exports or {}) do
        local p = util.abs(e, prefix)
        if fs.isdir(p) then
            local base = util.basename(p)
            if base == "include" then includes[#includes + 1] = p
            elseif base == "lib" or base == "lib64" then libdirs[#libdirs + 1] = p
            elseif base == "bin" then binaries[#binaries + 1] = p
            elseif base == "pkgconfig" then pkgdirs[#pkgdirs + 1] = p end
        elseif fs.isfile(p) then
            if util.ext(p) == "h" or util.ext(p) == "hpp" then
                includes[#includes + 1] = util.dirname(p)
            elseif p:match("%.a$") or p:match("%.so") then
                libdirs[#libdirs + 1] = util.dirname(p)
                libs[#libs + 1] = p
            end
        end
    end
    return {
        name = r.name, path = managed.repo_dir(managed.find_root(prefix) or prefix, r),
        prefix = prefix, includes = util.uniq(includes), libdirs = util.uniq(libdirs),
        binaries = util.uniq(binaries), libs = util.uniq(libs),
        defines = {}, link_flags = {}, pkgconfig_dirs = util.uniq(pkgdirs),
    }
end

local function describeResolved(ordered)
    return util.map(ordered, function(m)
        return { name = m.name, version = m.version, key = m.key, prefix = m.prefix }
    end)
end

local function mergeRequests(cfg, y)
    local requests = util.deepcopy(cfg.requests or {})
    local fromYaml = features.from_yaml(y or {})
    for _, portName in ipairs(util.keys(fromYaml)) do
        local entry = fromYaml[portName]
        for _, f in ipairs(entry.enable or {}) do
            features.add_request(requests, portName .. ":" .. f)
        end
        for _, f in ipairs(entry.disable or {}) do
            features.add_request(requests, "-" .. portName .. ":" .. f)
        end
    end
    return requests
end

local function mergeCompdb(jsonl, files, ordered)
    local entries = compdb.read(jsonl)
    for _, p in ipairs(files or {}) do
        entries = util.concat(entries, compdb.read(p, "json"))
    end
    for _, m in ipairs(ordered or {}) do
        if m.compdb_jsonl then
            entries = util.concat(entries, compdb.read(m.compdb_jsonl))
        end
        if m.compdb then
            entries = util.concat(entries, compdb.read(m.compdb, "json"))
        end
    end
    return compdb.dedup(entries)
end

local function makeContext(root, r, dir, injection, buildDir, prefix, jsonl, logPath, cfg, ordered)
    local binDir = util.join(gdir(root), "bin")
    local ccLink, cxxLink = util.join(binDir, "cc"), util.join(binDir, "c++")
    fs.symlink(gcpkg.sys.wrapper_bin(), ccLink)
    fs.symlink(gcpkg.sys.wrapper_bin(), cxxLink)
    local interceptEnv = util.merge(proxy.env(), injection.env, {
        CC = ccLink, CXX = cxxLink,
        GCPKG_CC_REAL = compilerValue("cc", "cc"),
        GCPKG_CXX_REAL = compilerValue("cxx", "c++"),
        GCPKG_INTERCEPT_LOG = jsonl,
        GCPKG_INTERCEPT_TAG = "workspace:" .. r.name,
    })
    local ctx = {
        name = r.name, version = "0", project_dir = dir, build_dir = buildDir,
        gcpkg_dir = gdir(root), inject = injection, inject_dir = injection.dir,
        install_prefix = prefix, log = logPath, jobs = cfg.jobs or gcpkg.sys.nproc(),
        env = interceptEnv, intercept_log = jsonl, compdb_log = jsonl,
        includes = injection.flags.includes, libdirs = injection.flags.libdirs,
        libs = injection.flags.libs, defines = injection.flags.defines,
        link_flags = injection.flags.link_flags, dependencies = ordered,
        features = cfg.requests or {}, arch = gcpkg.sys.arch(), os = gcpkg.sys.os(),
        compiler = { cc = compilerValue("cc", "cc"), cxx = compilerValue("cxx", "c++"),
                     wrapper_cc = ccLink, wrapper_cxx = cxxLink },
    }
    ctx.exec = function(cmd, o)
        o = o or {}
        return gcpkg.exec(cmd, {
            cwd = o.cwd or dir, env = util.merge(interceptEnv, o.env or {}),
            log = o.log or logPath, quiet = o.quiet, check = o.check,
        })
    end
    ctx.capture = function(cmd, o)
        o = o or {}
        return gcpkg.capture(cmd, { cwd = o.cwd or dir,
                                    env = util.merge(interceptEnv, o.env or {}) })
    end
    ctx.record = function(entry) return compdb.record(jsonl, entry) end
    ctx.dep = function(name)
        for _, m in ipairs(ordered) do
            if m.name == name or m.key == name then return m end
        end
        return nil
    end
    ctx.inner = function(o) return inner.run(ctx, o) end
    return ctx
end

function M.build(root, cfg, opts)
    opts = opts or {}
    cfg = cfg or {}
    if not cfg.store then error("workspace build needs a package store (cfg.store)") end
    if opts.update then M.sync(root, cfg, opts) end
    local c = context(root, cfg, opts)
    local needed = neededSet(opts.only, c.byname, c.edges)
    if opts.dry_run then
        log.step("dry-run build order for " .. c.data.workspace .. ":")
        local n = 0
        for i, r in ipairs(c.order) do
            if not needed or needed[r.name] then
                n = n + 1
                log.info(string.format("  %2d. %-16s systems=[%s] deps=[%s]",
                    n, r.name, table.concat(desiredSystems(opts, r), ","),
                    table.concat(r.depends or {}, ",")))
            end
        end
        log.step(n .. " repositories would be built (no downloads, no builds)")
        return { repos = n, dry_run = true }
    end
    local g = gdir(root)
    fs.mkdirs(util.join(g, "inject"))
    fs.mkdirs(util.join(g, "build"))
    fs.mkdirs(util.join(g, "prefix"))
    fs.mkdirs(util.join(g, "compdb"))
    fs.mkdirs(util.join(g, "bin"))
    fs.mkdirs(util.join(g, "projects"))
    local sharedManifests = {}
    for _, dep in ipairs(c.data.packages) do
        sharedManifests[#sharedManifests + 1] = port.install_or_backend(dep, cfg)
    end
    local built, allEntries, allIncludes, allDefines = 0, {}, {}, {}
    local projects = {}
    local lockUpdates = {}
    for index, r in ipairs(c.order) do
        if not needed or needed[r.name] then
            local dir = managed.repo_dir(root, r)
            if not fs.isdir(dir) then
                error("repository " .. r.name .. " is missing: " .. dir ..
                      "; run `gcpkg workspace sync` first")
            end
            local y = yaml.parse_file(util.join(dir, "gcpkg.yaml")) or {}
            local luaSpec = workspace.load_lua_spec(dir)
            local roots = workspace.roots(dir, cfg.ports or port.get_roots(), y)
            local repoCfg = util.merge(cfg, {
                ports = roots, requests = mergeRequests(cfg, y),
            })
            local depSpecs = workspace.effective_dependencies(dir, y,
                cfg.store.root, luaSpec)
            local manifests = util.deepcopy(sharedManifests)
            for _, dep in ipairs(depSpecs) do
                manifests[#manifests + 1] = port.install_or_backend(dep, repoCfg)
            end
            for _, dep in ipairs(r.packages or {}) do
                manifests[#manifests + 1] = port.install_or_backend(dep, repoCfg)
            end
            local ordered = port.transitive(manifests, cfg.store)
            local buildDir = r.build_dir and util.abs(r.build_dir, root) or
                             util.join(g, "build", r.name)
            local prefix = r.install_prefix and util.abs(r.install_prefix, root) or
                           util.join(g, "prefix", r.name)
            local outDir = util.join(g, "inject", r.name)
            local compdbPath = util.join(buildDir, "compile_commands.json")
            local systems = desiredSystems(opts, r)
            local injection = inject.generate(ordered, {
                out_dir = outDir, project_dir = dir, workspace_root = root,
                project_name = r.name, build_dir = buildDir,
                install_prefix = prefix, compdb = compdbPath,
                systems = systems, projects = projects,
            })
            -- Existing per-project gcpkg.lock stays usable by `gcpkg inject`
            -- and `gcpkg build`; the workspace lock additionally records the
            -- cross-repository tree and git pins.
            if fs.isfile(util.join(dir, "gcpkg.yaml")) or
               fs.isfile(util.join(dir, "gcpkg.lua")) then
                workspace.write_lock(dir, y, repoCfg, ordered, luaSpec)
            end
            local desired = util.uniq(util.concat(c.data.packages, depSpecs, r.packages or {}))
            lockUpdates[r.name] = {
                order = index, systems = systems, packages = desired,
                resolved = describeResolved(ordered),
            }
            local jsonl = util.join(g, "compdb", r.name .. ".jsonl")
            fs.write(jsonl, "")
            local logPath = logFile(root, "build-" .. r.name)
            fs.write(logPath, "== gcpkg workspace build " .. r.name .. " ==\n")
            local ctx = makeContext(root, r, dir, injection, buildDir, prefix,
                                    jsonl, logPath, cfg, ordered)
            if not opts.inject_only then
                local result = inner.run(ctx, {
                    systems = systems, commands = r.commands,
                    canon_cmd = r.canon_cmd, cmd = opts.cmd,
                    build_dir = buildDir, install_prefix = prefix,
                })
                local entries = mergeCompdb(jsonl, result.compdb_files or {}, ordered)
                compdb.write(entries, util.join(g, "compdb", r.name .. ".json"))
                allEntries = util.concat(allEntries, entries)
                allIncludes = util.concat(allIncludes, injection.flags.includes)
                allDefines = util.concat(allDefines, injection.flags.defines)
                log.step(r.name .. ": " .. compdb.summary(entries))
            else
                log.step("injection files ready for " .. r.name .. ": " .. injection.dir)
            end
            -- Export this project's install prefix to every later dependent.
            projects[#projects + 1] = projectExports(r, prefix, buildDir)
            built = built + 1
        end
    end
    if not opts.inject_only then
        local entries = compdb.write(allEntries, util.join(root, "compile_commands.json"))
        fs.write(util.join(g, "compdb", "compile_commands.json"),
                 json.encode(entries, true) .. "\n")
        compdb.write_clangd(root, util.uniq(allIncludes),
            util.map(util.uniq(allDefines), function(d) return "-D" .. d end))
        log.step("unified compile database: " .. util.join(root, "compile_commands.json") ..
                 " (" .. compdb.summary(entries) .. ")")
    end
    writeLock(root, c.data, c.order, function(e, r)
        local u = lockUpdates[r.name]
        if u then for k, v in pairs(u) do e[k] = v end end
    end)
    log.step(built .. " repositories processed; " .. managed.lock_file(root) .. " updated")
    return { repos = built, entries = #allEntries }
end

function M.inject(root, cfg, opts)
    opts = util.deepcopy(opts or {})
    opts.inject_only = true
    if opts.repo then opts.only = opts.repo end
    return M.build(root, cfg, opts)
end

return M
