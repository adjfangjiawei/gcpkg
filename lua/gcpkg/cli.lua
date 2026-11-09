local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local features = require("gcpkg.features")
local workspace = require("gcpkg.workspace")
local proxy = require("gcpkg.proxy")
local managed = require("gcpkg.managed")
local meta = require("gcpkg.meta")
local M = {}

local USAGE = [[
gcpkg ]] .. (gcpkg.version or "") .. [[ -- Lua-described meta package manager

Project workflow (pnpm-style):
  gcpkg new DIR [--name=NAME]       scaffold a project (gcpkg.lua + gcpkg.yaml + gcpkg-ports/)
  gcpkg init [DIR]                  same, in the current directory
  gcpkg add DEP[@VERSION]...        add libraries to THIS project's gcpkg.yaml
  gcpkg add --local NAME            add a project-private port (gcpkg-ports/NAME/)
  gcpkg add -g DEP[@VERSION]...     add to the user-wide (public) dependency list
  gcpkg remove NAME...              remove libraries from this project
  gcpkg list [DIR]                  show project deps, scopes, versions and lock
  gcpkg versions PORT               list versions declared for a port
  gcpkg proxy [URL|--unset]         show / set / clear the proxy configuration

Build / inspection:
  gcpkg build [PROJECT_DIR]         build a project + merged compile_commands.json
  gcpkg install [PORT@VERSION]     with no argument: install ALL project deps
  gcpkg compdb [PROJECT_DIR]        rebuild merged compile_commands.json only
  gcpkg inject [DIR] [--install]    write vcpkg-style toolchain/env injection
  gcpkg features PORT               list a library's YAML features
  gcpkg backends                    list external package-manager adapters
  gcpkg externals                   list vendor SDK ports + the env var each needs
  gcpkg ports                       list ports grouped by dependency layer
  gcpkg graph PORT                  print the bottom-up build order for a port
  gcpkg check                       validate all ports (files + dependencies)
  gcpkg doctor                      show toolchain / paths / wrapper status
  gcpkg port new NAME               scaffold build.lua + features.yaml

Managed workspaces (outer gcpkg / inner CMake, GN, Meson, canon, Makefile):
  gcpkg workspace new DIR [--name=NAME]
  gcpkg workspace add --name=NAME (--url=URL|--path=PATH) [--ref=REF]
                       [--commit=SHA] [--submodules=recursive]
                       [--system=cmake,canon] [--depends=a,b] [--packages=zlib]
  gcpkg workspace remove NAME
  gcpkg workspace list | graph | status
  gcpkg workspace sync [--update] [--force]   clone/fetch/checkout/submodules
  gcpkg workspace update                     fetch latest + refresh pins
  gcpkg workspace pin NAME [SHA] [--unpin]
  gcpkg workspace build [--only=NAME] [--system=...] [--cmd=...] [--dry-run]
  gcpkg workspace inject [NAME]              injection files only, no inner build
  gcpkg workspace submodule status|sync|pin|add [REPO] [--repo=NAME]
  gcpkg sync | status | tree [-C DIR]         short aliases for a workspace

Options:
  -C DIR, --dir=DIR                operate on a project/workspace in another directory
  --name=NAME                      (new/add) project or repo name
  -g, --global                     (add/remove/proxy) user-wide config
  --local                          (add/proxy) project-specific config
  --proxy=URL                      one-shot proxy (http/https/socks5, user:pass@host)
  --no-proxy                       force a direct connection for this run
  --noproxy=LIST                   comma-separated hosts that bypass the proxy
  --store=DIR                      package store (default $GCPKG_HOME or ~/.gcpkg)
  --ports=DIR[:DIR...]             public port registry roots
  --share=DIR                      engine root (contains lua/ and ports/)
  --feature=PORT:NAME, -f ...      enable a feature (prefix '-' disables it)
  -j N, --jobs=N                   parallel jobs
  --no-cache                       force rebuild even if the store is fresh
  --verbose                        print every executed command
  -h, --help                       this help

Managed-workspace / injection options:
  --url=URL, --path=PATH          git remote or local checkout for `workspace add`
  --ref=REF, --commit=SHA         branch/tag and optional pinned commit
  --submodules=recursive          recursive git submodule sync (or normal/shallow)
  --system=SYSTEMS                 inner systems, comma-separated (canon,cmake,...)
  --depends=LIST, --packages=LIST  repository edges and catalog dependencies
  --cmd=COMMAND                    override an inner command; @canon@ etc. expand
  --only=NAME                      build/inject one repository (+ its dependencies)
  --repo=NAME                      target repo for `workspace submodule`
  --out=DIR                        injection output directory
  --install                        (inject) install dependencies before injection
  --install-prefix=DIR, --build-dir=DIR, --compdb=FILE
  --workspace-root=DIR, --project-name=NAME
  --update, --force, --unpin, --dry-run, --git-commit
  --sha=SHA, --message=MSG         (submodule add) pin + optional commit message

Examples:
  gcpkg new apps/demo && gcpkg add zlib@1.2.13 -C apps/demo
  gcpkg new apps/other && gcpkg add zlib@1.3.1 -C apps/other
  gcpkg versions zlib
  gcpkg build apps/demo --store ~/.cache/gcpkg-store
  gcpkg install openssl --feature=openssl:shared
  gcpkg graph udisks2                       # feature-conditional deps
  gcpkg compdb . --ports ./ports:~/my-ports
  gcpkg workspace new ws && gcpkg workspace add -C ws --name=app --url=... --system=canon,cmake
  gcpkg workspace sync -C ws && gcpkg workspace build -C ws
  gcpkg inject apps/demo --install --system=cmake
  gcpkg build apps/demo --system=canon,cmake
]]

local function parse(args)
    local o = {
        requests = {}, jobs = gcpkg.sys.nproc(), no_cache = false, help = false,
        positional = {},
    }
    local i = 1
    while i <= #args do
        local a = args[i]
        local function nextval()
            i = i + 1
            if not args[i] then
                error("missing value for " .. a)
            end
            return args[i]
        end
        if a == "-h" or a == "--help" then
            o.help = true
        elseif a == "--verbose" or a == "-v" then
            o.verbose = true
        elseif a == "--no-cache" then
            o.no_cache = true
        elseif a:match("^--proxy=") then
            o.proxy = a:match("^--proxy=(.*)$")
        elseif a == "--proxy" then
            o.proxy = nextval()
        elseif a == "--no-proxy" then
            o.no_proxy = true
        elseif a:match("^--noproxy=") then
            o.no_proxy_list = a:match("^--noproxy=(.*)$")
        elseif a == "--noproxy" then
            o.no_proxy_list = nextval()
        elseif a == "--local" then
            o.local_port = true
        elseif a == "--global" or a == "-g" then
            o.global = true
        elseif a:match("^--store=") then
            o.store = a:match("^--store=(.*)$")
        elseif a == "--store" then
            o.store = nextval()
        elseif a:match("^--ports=") then
            o.ports = a:match("^--ports=(.*)$")
        elseif a == "--ports" then
            o.ports = nextval()
        elseif a:match("^--share=") then
            o.share = a:match("^--share=(.*)$")
        elseif a == "--share" then
            o.share = nextval()
        elseif a:match("^--name=") then
            o.name = a:match("^--name=(.*)$")
        elseif a == "--name" then
            o.name = nextval()
        elseif a:match("^--dir=") then
            o.dir = a:match("^--dir=(.*)$")
        elseif a == "--dir" or a == "-C" then
            o.dir = nextval()
        elseif a:match("^--feature=") then
            features.add_request(o.requests, a:match("^--feature=(.*)$"))
        elseif a == "--feature" or a == "-f" then
            features.add_request(o.requests, nextval())
        elseif a:match("^--jobs=") then
            o.jobs = tonumber(a:match("^--jobs=(.*)$")) or o.jobs
        elseif a == "--jobs" or a == "-j" then
            o.jobs = tonumber(nextval()) or o.jobs
        elseif a:match("^%-j%d+$") then
            o.jobs = tonumber(a:match("^%-j(%d+)$"))
        elseif a:match("^--url=") then
            o.url = a:match("^--url=(.*)$")
        elseif a == "--url" then
            o.url = nextval()
        elseif a:match("^--path=") then
            o.path = a:match("^--path=(.*)$")
        elseif a == "--path" then
            o.path = nextval()
        elseif a:match("^--ref=") then
            o.ref = a:match("^--ref=(.*)$")
        elseif a == "--ref" then
            o.ref = nextval()
        elseif a:match("^--commit=") then
            o.commit = a:match("^--commit=(.*)$")
        elseif a == "--commit" then
            o.commit = nextval()
        elseif a:match("^--submodules=") then
            o.submodules = a:match("^--submodules=(.*)$")
        elseif a == "--submodules" then
            o.submodules = nextval()
        elseif a:match("^--system=") then
            o.system = a:match("^--system=(.*)$")
        elseif a == "--system" then
            o.system = nextval()
        elseif a:match("^--systems=") then
            o.systems = a:match("^--systems=(.*)$")
        elseif a == "--systems" then
            o.systems = nextval()
        elseif a:match("^--depends=") then
            o.depends = a:match("^--depends=(.*)$")
        elseif a == "--depends" then
            o.depends = nextval()
        elseif a:match("^--packages=") then
            o.packages = a:match("^--packages=(.*)$")
        elseif a == "--packages" then
            o.packages = nextval()
        elseif a:match("^--only=") then
            o.only = a:match("^--only=(.*)$")
        elseif a == "--only" then
            o.only = nextval()
        elseif a:match("^--repo=") then
            o.repo = a:match("^--repo=(.*)$")
        elseif a == "--repo" then
            o.repo = nextval()
        elseif a:match("^--cmd=") then
            o.cmd = a:match("^--cmd=(.*)$")
        elseif a == "--cmd" then
            o.cmd = nextval()
        elseif a:match("^--out=") then
            o.out = a:match("^--out=(.*)$")
        elseif a == "--out" then
            o.out = nextval()
        elseif a:match("^--install-prefix=") then
            o.install_prefix = a:match("^--install-prefix=(.*)$")
        elseif a == "--install-prefix" then
            o.install_prefix = nextval()
        elseif a:match("^--build-dir=") then
            o.build_dir = a:match("^--build-dir=(.*)$")
        elseif a == "--build-dir" then
            o.build_dir = nextval()
        elseif a:match("^--compdb=") then
            o.compdb = a:match("^--compdb=(.*)$")
        elseif a == "--compdb" then
            o.compdb = nextval()
        elseif a:match("^--workspace-root=") then
            o.workspace_root = a:match("^--workspace-root=(.*)$")
        elseif a == "--workspace-root" then
            o.workspace_root = nextval()
        elseif a:match("^--project-name=") then
            o.project_name = a:match("^--project-name=(.*)$")
        elseif a == "--project-name" then
            o.project_name = nextval()
        elseif a:match("^--sha=") then
            o.sha = a:match("^--sha=(.*)$")
        elseif a == "--sha" then
            o.sha = nextval()
        elseif a:match("^--message=") then
            o.message = a:match("^--message=(.*)$")
        elseif a == "--message" then
            o.message = nextval()
        elseif a == "--install" then
            o.install = true
        elseif a == "--update" then
            o.update = true
        elseif a == "--force" then
            o.force = true
        elseif a == "--unpin" then
            o.unpin = true
        elseif a == "--dry-run" then
            o.dry_run = true
        elseif a == "--git-commit" then
            o.git_commit = true
        else
            o.positional[#o.positional + 1] = a
        end
        i = i + 1
    end
    return o
end

local function doctor(cfg, o)
    local log = require("gcpkg.log")
    log.info("gcpkg " .. (gcpkg.version or "") .. " | " .. gcpkg.sys.os() ..
             "/" .. gcpkg.sys.arch() .. " | " .. gcpkg.sys.nproc() .. " cores")
    log.info("engine (GCPKG_SHARE): " .. gcpkg.sys.share())
    log.info("lua root            : " .. gcpkg.sys.lua_root())
    log.info("store               : " .. cfg.store.root)
    log.info("proxy               : " .. proxy.summary())
    log.info("ports roots         : " .. table.concat(cfg.ports, " : "))
    local wrapper = gcpkg.sys.wrapper_bin()
    log.info("compiler interceptor: " .. wrapper ..
             (fs.isfile(wrapper) and " [ok]" or " [MISSING]"))
    for _, tool in ipairs({ "cc", "c++", "make", "cmake", "perl", "curl", "tar",
                            "pkg-config", "ninja", "meson", "git" }) do
        log.info(string.format("  %-12s %s", tool, gcpkg.have(tool) and "ok" or "missing"))
    end
    return 0
end

local function project_dir(o)
    if o.dir then
        return util.abs(o.dir)
    end
    local extra = o.positional[2]
    if extra and not extra:match("^%-") then
        return util.abs(extra)
    end
    return workspace.find_root(fs.cwd()) or fs.cwd()
end

local function tail(list, from)
    local out = {}
    for i = from, #list do
        out[#out + 1] = list[i]
    end
    return out
end

local function managedRoot(o)
    local start = o.dir and util.abs(o.dir) or fs.cwd()
    local root = managed.find_root(start)
    if not root then
        error("not inside a managed workspace (no workspace.yaml); run `gcpkg workspace new DIR`")
    end
    return root
end

local function workspaceCli(o, cfg)
    local log = require("gcpkg.log")
    local sub = o.positional[2]
    if not sub then error("workspace needs a subcommand (new/add/remove/list/graph/status/sync/update/pin/build/inject/submodule)") end
    local root = sub ~= "new" and managedRoot(o) or nil
    if sub == "new" then
        local dir = o.positional[3] or o.dir
        if not dir then error("workspace new needs a directory (gcpkg workspace new DIR)") end
        meta.init(dir, o.name)
        log.info("  add repos: gcpkg workspace add -C " .. dir .. " --name=NAME --url=URL")
        log.info("  then:      gcpkg workspace sync -C " .. dir)
        return 0
    elseif sub == "add" then
        local name = o.name or o.positional[3]
        if not name then error("workspace add needs --name=NAME") end
        meta.add(root, {
            name = name, url = o.url, path = o.path, ref = o.ref,
            commit = o.commit, submodules = o.submodules,
            system = o.system or o.systems,
            depends = o.depends, packages = o.packages,
            canon_cmd = o.cmd, commands = o.commands,
        })
        return 0
    elseif sub == "remove" then
        local name = o.positional[3] or o.name
        if not name then error("workspace remove needs a repo name") end
        meta.remove(root, name)
        return 0
    elseif sub == "list" then
        return meta.list(root, cfg, o)
    elseif sub == "graph" then
        return meta.graph(root, cfg, o)
    elseif sub == "status" then
        return meta.status(root, cfg, o)
    elseif sub == "sync" or sub == "update" then
        local opts = util.merge(o, { update = (sub == "update" or o.update == true),
                                     force = o.force })
        meta.sync(root, cfg, opts)
        return 0
    elseif sub == "pin" then
        local name = o.positional[3]
        local sha = o.positional[4]
        if not name then error("workspace pin needs a repo name") end
        meta.pin(root, name, sha, { unpin = o.unpin })
        return 0
    elseif sub == "build" then
        local opts = util.merge(o, { only = o.only or o.positional[3],
                                     dry_run = o.dry_run, cmd = o.cmd })
        meta.build(root, cfg, opts)
        return 0
    elseif sub == "inject" then
        local repo = o.repo or o.only or o.positional[3]
        local opts = util.merge(o, { only = repo, repo = repo })
        meta.inject(root, cfg, opts)
        return 0
    elseif sub == "submodule" then
        local action = o.positional[3]
        local repo = o.repo or o.positional[4]
        if not action then error("workspace submodule needs status|sync|pin|add") end
        return meta.submodule(root, action, util.merge(o, { repo = repo }))
    end
    error("unknown workspace subcommand: " .. tostring(sub))
end

function M.main(args)
    local o = parse(args or gcpkg.args)
    if o.verbose then
        gcpkg.sys.set_verbose(true)
    end
    -- Resolve once per process: downloads, git clones and build hooks all
    -- read proxy.env() from this configuration.
    proxy.configure({
        proxy = o.proxy, no_proxy = o.no_proxy,
        no_proxy_list = o.no_proxy_list,
        project_dir = workspace.find_root(o.dir or fs.cwd()),
    })
    if o.help or #o.positional == 0 then
        print(USAGE)
        return 0
    end

    local port = require("gcpkg.port")
    local storeMod = require("gcpkg.store")
    local log = require("gcpkg.log")
    local cmd = o.positional[1]
    local publicRoots = o.ports and util.split(o.ports, ":") or port.default_roots()
    -- Inside a project, its private ports are searched first; the user-wide
    -- registry comes before engine/public registries. Outside a project this
    -- is just the old default roots plus ~/.gcpkg/ports.  `gcpkg inject` also
    -- accepts a directory containing only gcpkg.yaml/gcpkg.lock (no gcpkg.lua).
    local projDir = workspace.find_root(o.dir or fs.cwd())
    if not projDir and (cmd == "inject" or cmd == "build" or cmd == "compdb") then
        local candidate = project_dir(o)
        if fs.isfile(util.join(candidate, "gcpkg.yaml")) or
           fs.isfile(util.join(candidate, "gcpkg.lock")) then
            projDir = candidate
        end
    end
    local py = projDir and workspace.read_yaml(util.join(projDir, "gcpkg.yaml")) or {}
    local roots = util.map(workspace.roots(projDir, publicRoots, py),
                          function(r) return util.abs(r) end)
    port.set_roots(roots)
    local home = os.getenv("HOME") or fs.cwd()
    local storeRoot = o.store or os.getenv("GCPKG_HOME") or util.join(home, ".gcpkg")
    local st = storeMod.new(util.abs(storeRoot))
    gcpkg.sys.add_root(util.join(st.root, "lua"))
    local cfg = {
        store = st, ports = roots, requests = o.requests, jobs = o.jobs,
        no_cache = o.no_cache, share = o.share or gcpkg.sys.share(),
        system = o.system, systems = o.systems, cmd = o.cmd,
        commands = o.commands, out = o.out, install_prefix = o.install_prefix,
        build_dir = o.build_dir, compdb = o.compdb,
        workspace_root = o.workspace_root, project_name = o.project_name,
        dry_run = o.dry_run, update = o.update, force = o.force,
    }

    if cmd == "workspace" then
        return workspaceCli(o, cfg)
    elseif cmd == "sync" or cmd == "update" then
        meta.sync(managedRoot(o), cfg,
                  util.merge(o, { update = (cmd == "update" or o.update == true) }))
        return 0
    elseif cmd == "status" then
        return meta.status(managedRoot(o), cfg, o)
    elseif cmd == "tree" then
        return meta.graph(managedRoot(o), cfg, o)
    elseif cmd == "inject" then
        local injection = require("gcpkg.inject").from_lock(project_dir(o), cfg, {
            out = o.out, install = o.install, system = o.system,
            systems = o.systems, build_dir = o.build_dir,
            install_prefix = o.install_prefix, compdb = o.compdb,
            workspace_root = o.workspace_root, project_name = o.project_name,
        })
        log.step("dependency injection written to " .. injection.dir)
        log.info("  CMake toolchain : " .. injection.files.toolchain)
        log.info("  CMake cache     : " .. injection.files.cache)
        log.info("  env script      : " .. injection.files.env)
        log.info("  canon manifest  : " .. injection.files.canon)
        return 0
    elseif cmd == "proxy" then
        local value = o.positional[2]
        if o.local_port and not projDir then
            error("--local needs a gcpkg project (run `gcpkg new DIR` first)")
        end
        if value == "--unset" then
            local path = proxy.unset({ project_dir = projDir, global = o.global })
            log.step("cleared proxy from " .. path)
        elseif value and not value:match("^%-") then
            local path = proxy.set({ project_dir = projDir, global = o.global,
                                     url = value, no_proxy_list = o.no_proxy_list })
            log.step("set proxy " .. proxy.redact(value) .. " in " .. path)
        else
            proxy.describe({ project_dir = projDir, proxy = o.proxy,
                             no_proxy = o.no_proxy,
                             no_proxy_list = o.no_proxy_list })
        end
        return 0
    elseif cmd == "doctor" then
        return doctor(cfg, o)
    elseif cmd == "new" or cmd == "init" then
        local dir = o.positional[2] or (cmd == "init" and fs.cwd() or nil)
        if not dir then
            error("new needs a directory (gcpkg new DIR)")
        end
        local created = workspace.new_project(dir, o.name)
        log.step("created project " .. created)
        log.info("  gcpkg.lua / gcpkg.yaml / src/main.c / gcpkg-ports/")
        log.info("  next: gcpkg add zlib@1.2.13 -C " .. dir)
        return 0
    elseif cmd == "add" then
        local specs = tail(o.positional, 2)
        if #specs == 0 then
            error("add needs at least one dependency (e.g. gcpkg add zlib@1.2.13)")
        end
        workspace.add(projDir, specs, {
            roots = roots, storeRoot = st.root, global = o.global,
            local_port = o.local_port,
        })
        return 0
    elseif cmd == "remove" then
        local specs = tail(o.positional, 2)
        if #specs == 0 then
            error("remove needs at least one library name")
        end
        workspace.remove(projDir, specs, {
            roots = roots, storeRoot = st.root, global = o.global,
        })
        return 0
    elseif cmd == "list" then
        local dir = project_dir(o)
        local root = workspace.find_root(dir)
        if not root then
            error("not inside a gcpkg project: " .. dir)
        end
        workspace.list(root, { storeRoot = st.root, roots = roots })
        return 0
    elseif cmd == "versions" then
        local name = o.positional[2]
        if not name then
            error("versions needs a port name")
        end
        workspace.describe_versions(name, roots)
        return 0
    elseif cmd == "build" then
        require("gcpkg.project").build(project_dir(o), cfg, {
            system = o.system, systems = o.systems, cmd = o.cmd,
            dry_run = o.dry_run,
        })
        return 0
    elseif cmd == "compdb" then
        require("gcpkg.project").build(project_dir(o), cfg, {
            skip_build = true, system = o.system, systems = o.systems,
            cmd = o.cmd,
        })
        return 0
    elseif cmd == "install" then
        if not o.positional[2] then
            -- pnpm-style: install every dependency of the current project.
            local root = workspace.find_root(o.dir or fs.cwd())
            if not root then
                error("install with no argument needs a gcpkg.yaml (run `gcpkg new DIR`)")
            end
            workspace.install_project(root, cfg)
            return 0
        end
        local m = port.install(o.positional[2], cfg)
        log.info("manifest: " .. storeMod.manifest_path(st, m.key))
        return 0
    elseif cmd == "features" then
        if not o.positional[2] then
            error("features needs a port name")
        end
        local dir = port.find(o.positional[2])
        if not dir then
            error("port '" .. o.positional[2] .. "' not found")
        end
        local spec = port.features_file(dir) or {}
        print(features.describe(spec.features or spec, o.positional[2]))
        return 0
    elseif cmd == "backends" then
        for _, b in ipairs(require("gcpkg.backends").probe_all()) do
            log.info(string.format("  %-12s %-8s %s", b.name,
                                   b.available and "ready" or "n/a", b.detail))
        end
        return 0
    elseif cmd == "externals" then
        -- Purely static: no download, no SDK required. Prints the exact
        -- environment variable a user must point at a locally installed SDK.
        local graph = require("gcpkg.graph")
        local ports = graph.ports(roots)
        local names = util.keys(ports)
        table.sort(names)
        local n = 0
        for _, name in ipairs(names) do
            local sdk = (ports[name].spec or {}).sdk
            if sdk then
                n = n + 1
                local set = os.getenv(sdk.env or "") and "set" or "unset"
                log.info(string.format("  %-16s %-28s %-6s %s", name,
                    sdk.env or "?", set, sdk.url or sdk.description or ""))
            end
        end
        log.step(n .. " external SDK ports (point the env var at the SDK before install)")
        return 0
    elseif cmd == "ports" then
        local graph = require("gcpkg.graph")
        local ports = graph.ports(roots)
        local layers = graph.layers(ports, o.requests)
        local names = util.keys(ports)
        table.sort(names, function(a, b)
            if layers[a] ~= layers[b] then
                return layers[a] < layers[b]
            end
            return a < b
        end)
        log.info(#names .. " ports (L0 = no gcpkg dependencies)")
        for _, n in ipairs(names) do
            local e = ports[n]
            local deps = {}
            for _, d in ipairs(graph.deps(e, o.requests, n)) do
                deps[#deps + 1] = graph.dep_name(d)
            end
            log.info(string.format("  L%-2d %-14s %-10s deps=[%s]%s", layers[n], n,
                (e.spec or {}).version or "?", table.concat(deps, ","),
                e.error and (" ERROR: " .. e.error) or ""))
        end
        return 0
    elseif cmd == "graph" then
        local name = o.positional[2]
        if not name then
            error("graph needs a port name")
        end
        local graph = require("gcpkg.graph")
        local order = graph.order(name, graph.ports(roots), o.requests)
        log.step("bottom-up build order for " .. name .. ":")
        for i, n in ipairs(order) do
            log.info(string.format("  %2d. %s", i, n))
        end
        return 0
    elseif cmd == "check" then
        local graph = require("gcpkg.graph")
        local ports = graph.ports(roots)
        local problems = graph.validate(ports, o.requests)
        for _, p in ipairs(problems) do
            log.warn("  " .. p)
        end
        if #problems > 0 then
            log.error(#problems .. " problem(s) found")
            return 1
        end
        log.step(#util.keys(ports) .. " ports OK (build.lua + features.yaml + resolvable deps)")
        return 0
    elseif cmd == "port" and o.positional[2] == "new" then
        local name = o.positional[3]
        if not name then
            error("port new needs a name")
        end
        -- Always scaffold into the FIRST PUBLIC root, not a project-private
        -- directory -- public ports are shared by every project.
        local dir = util.join(util.abs(publicRoots[1]), name)
        if fs.exists(util.join(dir, "build.lua")) then
            error("port already exists: " .. dir)
        end
        workspace.scaffold_port(dir, name)
        log.step("created port " .. dir)
        return 0
    end
    log.error("unknown command: " .. tostring(cmd))
    print(USAGE)
    return 1
end

return M
