-- Project mode.
--
-- A project is just a directory containing gcpkg.lua (build description) and
-- gcpkg.yaml (feature selection). `gcpkg build <dir>` builds every dependency,
-- then builds the project, then writes ONE compile_commands.json covering the
-- project AND all transitive dependencies. clangd can therefore jump from
-- project code into a dependency's headers/sources and back again.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local yaml = require("gcpkg.yaml")
local features = require("gcpkg.features")
local store = require("gcpkg.store")
local compdb = require("gcpkg.compdb")
local port = require("gcpkg.port")
local workspace = require("gcpkg.workspace")
local proxy = require("gcpkg.proxy")
local M = {}

local function load(project_dir)
    local luaPath = util.join(project_dir, "gcpkg.lua")
    local yamlPath = util.join(project_dir, "gcpkg.yaml")
    if not fs.isfile(luaPath) then
        error("no gcpkg.lua in " .. project_dir)
    end
    gcpkg.sys.add_root(util.join(project_dir, "lua"))
    gcpkg.sys.add_root(util.join(project_dir, ".gcpkg", "lua"))
    local spec = gcpkg.sys.loadchunk(luaPath)
    if type(spec) ~= "table" then
        error(luaPath .. " must return a table")
    end
    local y = yaml.parse_file(yamlPath) or {}
    return spec, y
end

local function mergeRequests(base, fromYaml)
    local out = util.deepcopy(base or {})
    for _, portName in ipairs(util.keys(fromYaml)) do
        local entry = fromYaml[portName]
        for _, f in ipairs(entry.enable or {}) do
            features.add_request(out, portName .. ":" .. f)
        end
        for _, f in ipairs(entry.disable or {}) do
            features.add_request(out, "-" .. portName .. ":" .. f)
        end
    end
    return out
end

local function collectManifests(manifests, cfg)
    local ordered, seen = {}, {}
    local function visit(m)
        if not m or not m.key or seen[m.key] then
            return
        end
        seen[m.key] = true
        for _, depKey in ipairs(m.deps or {}) do
            visit(store.read_manifest(cfg.store, depKey))
        end
        ordered[#ordered + 1] = m
    end
    for _, m in ipairs(manifests) do
        visit(m)
    end
    return ordered
end

function M.build(projectDir, cfg, opts)
    opts = opts or {}
    cfg = cfg or {}
    projectDir = fs.realpath(projectDir or fs.cwd())
    local spec, y = load(projectDir)
    local requests = mergeRequests(cfg.requests, features.from_yaml(y))
    -- Project-private ports (gcpkg-ports/) + the user registry + the public
    -- registry. First match wins, so a project can override one library
    -- without forking the shared 145-port registry.
    local roots = workspace.roots(projectDir, cfg.ports or port.get_roots(), y)
    local projectCfg = util.merge(cfg, { requests = requests, ports = roots })

    -- Deps may live in gcpkg.lua, in the project's managed gcpkg.yaml block,
    -- or (opt-in) in the user's global gcpkg.yaml. First declaration wins.
    local depSpecs = workspace.effective_dependencies(projectDir, y,
        cfg.store and cfg.store.root, spec)
    local manifests = {}
    for _, dep in ipairs(depSpecs) do
        manifests[#manifests + 1] = port.install_or_backend(dep, projectCfg)
    end
    local ordered = collectManifests(manifests, projectCfg)

    local includes, libdirs, libs, defines, linkFlags = {}, {}, {}, {}, {}
    for _, m in ipairs(ordered) do
        includes = util.concat(includes, m.includes or {})
        libdirs = util.concat(libdirs, m.libdirs or {})
        defines = util.concat(defines, m.defines or {})
        linkFlags = util.concat(linkFlags, m.link_flags or {})
    end
    -- Static linking: dependents before dependencies, BUT keep the order of
    -- libs inside one manifest (libssl before libcrypto, brotlidec before
    -- brotlicommon, ...). Reversing a flat list would break those pairs.
    for i = #ordered, 1, -1 do
        libs = util.concat(libs, ordered[i].libs or {})
    end

    local gdir = util.join(projectDir, ".gcpkg")
    local buildDir = util.join(gdir, "build")
    local projectLog = util.join(gdir, "logs", "project.log")
    local jsonl = util.join(gdir, "compdb", "project.jsonl")
    fs.mkdirs(buildDir)
    fs.mkdirs(util.dirname(projectLog))
    fs.mkdirs(util.dirname(jsonl))
    if opts.skip_build ~= true then
        fs.write(projectLog, "== gcpkg project " .. (spec.name or util.basename(projectDir)) .. " ==\n")
        fs.write(jsonl, "")
    end

    -- Same interception trick for projects: any build system invoked through
    -- ctx.exec (make, autotools, cargo, ...) contributes compdb entries too.
    local wrapper = gcpkg.sys.wrapper_bin()
    local binDir = util.join(gdir, "bin")
    local ccLink, cxxLink = util.join(binDir, "cc"), util.join(binDir, "c++")
    fs.symlink(wrapper, ccLink)
    fs.symlink(wrapper, cxxLink)
    local interceptEnv = util.merge(proxy.env(), {
        CC = ccLink,
        CXX = cxxLink,
        GCPKG_CC_REAL = gcpkg.sys.compiler("cc"),
        GCPKG_CXX_REAL = gcpkg.sys.compiler("cxx"),
        GCPKG_INTERCEPT_LOG = jsonl,
        GCPKG_INTERCEPT_TAG = "project:" .. (spec.name or "project"),
    })

    local log = require("gcpkg.log")
    local ctx = {
        name = spec.name or y.project or util.basename(projectDir),
        version = spec.version or "0",
        project_dir = projectDir,
        build_dir = buildDir,
        gcpkg_dir = gdir,
        log = projectLog,
        jobs = cfg.jobs or gcpkg.sys.nproc(),
        includes = util.uniq(includes),
        libdirs = util.uniq(libdirs),
        libs = util.uniq(libs),
        defines = util.uniq(defines),
        link_flags = util.uniq(linkFlags),
        dependencies = ordered,
        features = requests,
        arch = gcpkg.sys.arch(),
        os = gcpkg.sys.os(),
        intercept_log = jsonl,
        compdb_log = jsonl,
        env = interceptEnv,
        compiler = { cc = gcpkg.sys.compiler("cc"), cxx = gcpkg.sys.compiler("cxx"),
                     wrapper_cc = ccLink, wrapper_cxx = cxxLink },
    }
    ctx.exec = function(cmd, o)
        o = o or {}
        return gcpkg.exec(cmd, {
            cwd = o.cwd or projectDir,
            env = util.merge(interceptEnv, o.env or {}),
            log = o.log or projectLog,
            quiet = o.quiet,
            check = o.check,
        })
    end
    ctx.capture = function(cmd, o)
        o = o or {}
        return gcpkg.capture(cmd, { cwd = o.cwd or projectDir, env = o.env })
    end
    ctx.record = function(entry)
        return compdb.record(jsonl, entry)
    end
    ctx.dep = function(name)
        for _, m in ipairs(ordered) do
            if m.name == name or m.key == name then
                return m
            end
        end
        return nil
    end

    if opts.skip_build ~= true then
        if type(spec.build) ~= "function" then
            error(projectDir .. "/gcpkg.lua must define build(ctx)")
        end
        log.step("building project " .. ctx.name)
        local extras = spec.build(ctx) or {}
        for _, extra in ipairs(extras.compdb_files or {}) do
            -- returned by build() so e.g. a CMake-driven project can contribute
            jsonl = util.join(gdir, "compdb", "project.jsonl")
            for _, e in ipairs(compdb.read(extra, "json")) do
                compdb.record(jsonl, e)
            end
        end
    end

    -- Merge: project entries + every dependency's entries (transitively).
    local entries = compdb.read(jsonl)
    for _, m in ipairs(ordered) do
        -- Both sources are merged (dedup makes this idempotent): native build
        -- systems such as CMake emit compile_commands.json, while hand-written
        -- Makefiles are captured by gcpkg-intercept into JSONL.
        if m.compdb_jsonl then
            entries = util.concat(entries, compdb.read(m.compdb_jsonl))
        end
        if m.compdb then
            entries = util.concat(entries, compdb.read(m.compdb, "json"))
        end
    end
    local outPath = util.join(projectDir, "compile_commands.json")
    entries = compdb.write(entries, outPath)
    compdb.write_clangd(projectDir, ctx.includes,
        util.map(ctx.defines, function(d) return "-D" .. d end))
    fs.write(util.join(gdir, "compdb", "compile_commands.json"),
             require("gcpkg.json").encode(entries, true) .. "\n")

    log.step("compile database: " .. outPath .. " (" .. compdb.summary(entries) .. ")")
    log.info("  clangd can now navigate project + dependency sources")
    -- Per-project resolution record: which versions/scopes were actually used.
    workspace.write_lock(projectDir, y, projectCfg, ordered, spec)
    return { compile_commands = outPath, entries = #entries, dependencies = ordered }
end

return M
