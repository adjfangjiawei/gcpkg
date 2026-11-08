local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local features = require("gcpkg.features")
local workspace = require("gcpkg.workspace")
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

Build / inspection:
  gcpkg build [PROJECT_DIR]         build a project + merged compile_commands.json
  gcpkg install [PORT@VERSION]     with no argument: install ALL project deps
  gcpkg compdb [PROJECT_DIR]        rebuild merged compile_commands.json only
  gcpkg features PORT               list a library's YAML features
  gcpkg backends                    list external package-manager adapters
  gcpkg externals                   list vendor SDK ports + the env var each needs
  gcpkg ports                       list ports grouped by dependency layer
  gcpkg graph PORT                  print the bottom-up build order for a port
  gcpkg check                       validate all ports (files + dependencies)
  gcpkg doctor                      show toolchain / paths / wrapper status
  gcpkg port new NAME               scaffold build.lua + features.yaml

Options:
  -C DIR, --dir=DIR                operate on a project in another directory
  --name=NAME                      (new) project name
  --local                          (add) create a project-private port
  -g, --global                     (add/remove) user-wide dependency list
  --store=DIR                      package store (default $GCPKG_HOME or ~/.gcpkg)
  --ports=DIR[:DIR...]             public port registry roots
  --share=DIR                      engine root (contains lua/ and ports/)
  --feature=PORT:NAME, -f ...      enable a feature (prefix '-' disables it)
  -j N, --jobs=N                   parallel jobs
  --no-cache                       force rebuild even if the store is fresh
  --verbose                        print every executed command
  -h, --help                       this help

Examples:
  gcpkg new apps/demo && gcpkg add zlib@1.2.13 -C apps/demo
  gcpkg new apps/other && gcpkg add zlib@1.3.1 -C apps/other
  gcpkg versions zlib
  gcpkg build apps/demo --store ~/.cache/gcpkg-store
  gcpkg install openssl --feature=openssl:shared
  gcpkg graph udisks2                       # feature-conditional deps
  gcpkg compdb . --ports ./ports:~/my-ports
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

function M.main(args)
    local o = parse(args or gcpkg.args)
    if o.verbose then
        gcpkg.sys.set_verbose(true)
    end
    if o.help or #o.positional == 0 then
        print(USAGE)
        return 0
    end

    local port = require("gcpkg.port")
    local storeMod = require("gcpkg.store")
    local log = require("gcpkg.log")
    local publicRoots = o.ports and util.split(o.ports, ":") or port.default_roots()
    -- Inside a project, its private ports are searched first; the user-wide
    -- registry comes before engine/public registries. Outside a project this
    -- is just the old default roots plus ~/.gcpkg/ports.
    local projDir = workspace.find_root(o.dir or fs.cwd())
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
    }

    local cmd = o.positional[1]
    if cmd == "doctor" then
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
        require("gcpkg.project").build(o.positional[2] or fs.cwd(), cfg, {})
        return 0
    elseif cmd == "compdb" then
        require("gcpkg.project").build(o.positional[2] or fs.cwd(), cfg, { skip_build = true })
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
