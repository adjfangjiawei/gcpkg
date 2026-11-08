-- Port = ONE build.lua + ONE features.yaml, nothing else.
--
-- install() is the whole library lifecycle: resolve features -> recurse into
-- dependencies -> fetch source -> run the Lua build hook with an instrumented
-- environment -> turn intercepted compiler calls into a compilation database
-- -> write a manifest that projects and other ports can consume.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local yaml = require("gcpkg.yaml")
local features = require("gcpkg.features")
local store = require("gcpkg.store")
local compdb = require("gcpkg.compdb")
local net = require("gcpkg.net")
local backends = require("gcpkg.backends")
local M = { roots = nil }

function M.default_roots()
    local roots = {}
    local env = gcpkg.sys.getenv("GCPKG_PORTS")
    if env then
        for _, p in ipairs(util.split(env, ":")) do
            roots[#roots + 1] = p
        end
    end
    roots[#roots + 1] = gcpkg.sys.share() .. "/ports"
    roots[#roots + 1] = fs.cwd() .. "/ports"
    roots[#roots + 1] = fs.cwd() .. "/gcpkg/ports"
    return util.uniq(roots)
end

function M.set_roots(roots)
    M.roots = roots
end

function M.get_roots()
    return M.roots or M.default_roots()
end

function M.find(name, roots)
    for _, root in ipairs(roots or M.get_roots()) do
        local dir = util.join(root, tostring(name))
        if fs.isfile(util.join(dir, "build.lua")) then
            return dir
        end
    end
    return nil
end

function M.load(dir)
    local spec = gcpkg.sys.loadchunk(util.join(dir, "build.lua"))
    if type(spec) ~= "table" then
        error(dir .. "/build.lua must return a table")
    end
    return spec
end

function M.features_file(dir)
    local path = util.join(dir, "features.yaml")
    if not fs.isfile(path) then
        return nil
    end
    return yaml.parse_file(path)
end

local function parseDep(dep)
    if type(dep) == "table" then
        return { name = tostring(dep.name or dep[1]), version = dep.version,
                 features = dep.features or {}, backend = dep.backend }
    end
    local name, version = tostring(dep):match("^([^@]+)@(.+)$")
    return { name = name or tostring(dep), version = version, features = {} }
end

local function compilerValue(kind, fallback)
    local v = gcpkg.sys.compiler(kind)
    if not v or v == "" or v:find("gcpkg-intercept") or v:find("/cc$") or v:find("/c%+%+$") then
        -- Guard against recursing into our own wrapper symlink.
        return fallback
    end
    return v
end

-- install_or_backend(dep, cfg): native ports are built, "<adapter>:<name>"
-- specs are delegated to an external package manager adapter.
function M.install_or_backend(dep, cfg)
    local d = parseDep(dep)
    if d.backend or d.name:find(":") then
        local spec = (d.backend and (d.backend .. ":" .. d.name)) or d.name
        return backends.resolve(spec, cfg)
    end
    local sub = util.deepcopy(cfg)
    sub.requests = util.deepcopy(cfg.requests or {})
    sub.in_progress = cfg.in_progress  -- shared across recursion for cycle detection
    for _, f in ipairs(d.features) do
        features.add_request(sub.requests, d.name .. ":" .. f)
    end
    local name = d.version and (d.name .. "@" .. d.version) or d.name
    return M.install(name, sub)
end

function M.install(spec_name, cfg)
    cfg = cfg or {}
    cfg.requests = cfg.requests or {}
    cfg.in_progress = cfg.in_progress or {}
    local st = cfg.store
    if not st then
        error("port.install: missing cfg.store")
    end

    local name, wanted = tostring(spec_name):match("^([^@]+)@(.+)$")
    name = name or tostring(spec_name)
    local dir = M.find(name, cfg.ports)
    if not dir then
        error("port '" .. name .. "' not found. Looked in:\n  " ..
              table.concat(cfg.ports or M.get_roots(), "\n  "))
    end
    local spec = M.load(dir)
    local portName = spec.name or name
    local version = wanted or spec.version or "0"
    local key = store.key(portName, version)

    if cfg.in_progress[key] then
        error("dependency cycle detected at " .. key)
    end
    cfg.in_progress[key] = true

    local fspec = M.features_file(dir) or {}
    local f = features.resolve(fspec.features or fspec, portName, cfg.requests)

    -- 1. dependencies (declared in build.lua + pulled in by enabled features)
    local deps = util.concat(spec.dependencies or {}, f.requires)
    local manifests, depKeys = {}, {}
    for _, dep in ipairs(deps) do
        local manifest = M.install_or_backend(dep, cfg)
        manifests[#manifests + 1] = manifest
        if manifest.key then
            depKeys[#depKeys + 1] = manifest.key
        end
    end

    local fingerprint = store.fingerprint(util.concat({
        portName, version, f.hash,
        (type(spec.source) == "table" and (spec.source.url or spec.source.git or spec.source.dir)) or "custom",
        gcpkg.sys.os(), gcpkg.sys.arch(), table.concat(depKeys, ","),
    }))

    local cached = store.read_manifest(st, key)
    if not cfg.no_cache and store.is_fresh(cached, fingerprint) then
        -- Re-materialise this library's own compile_commands.json from the
        -- intercept log (cheap, and keeps it correct if the normaliser changed).
        local jsonl = store.compdb_jsonl(st, key)
        local entries = compdb.write(compdb.read(jsonl), store.compdb_json(st, key))
        cached.compdb = store.compdb_json(st, key)
        cached.compdb_jsonl = jsonl
        cached.compdb_entries = #entries
        store.write_manifest(st, key, cached)
        gcpkg.log.step("reusing " .. key .. " [" .. table.concat(f.list, ",") .. "]")
        cfg.in_progress[key] = nil
        return cached
    end

    -- 2. workspace
    local src = util.join(st.src, key)
    local buildDir = util.join(st.build, key)
    local prefix = util.join(st.pkg, key)
    fs.mkdirs(src)
    fs.mkdirs(buildDir)
    fs.mkdirs(prefix)
    local logPath = store.log_path(st, key)
    fs.write(logPath, "== gcpkg build " .. key .. " ==\n")

    if spec.source then
        src = net.prepare(spec.source, src, {
            cache_dir = st.cache,
            log = logPath,
        })
    end

    -- 3. compiler interception. Upstream build systems stay untouched: we only
    -- point CC/CXX at symlinks of gcpkg-intercept.
    local wrapper = gcpkg.sys.wrapper_bin()
    local ccLink = util.join(st.bin, "cc")
    local cxxLink = util.join(st.bin, "c++")
    fs.symlink(wrapper, ccLink)
    fs.symlink(wrapper, cxxLink)
    local jsonl = store.compdb_jsonl(st, key)
    fs.write(jsonl, "")
    local ccReal = compilerValue("cc", "cc")
    local cxxReal = compilerValue("cxx", "c++")
    local env = util.merge(f.env, {
        CC = ccLink,
        CXX = cxxLink,
        GCPKG_CC_REAL = ccReal,
        GCPKG_CXX_REAL = cxxReal,
        GCPKG_INTERCEPT_LOG = jsonl,
        GCPKG_INTERCEPT_TAG = key,
    })

    -- 4. build hook context
    local ctx = {
        name = portName,
        version = version,
        key = key,
        port_dir = dir,
        src = src,
        build_dir = buildDir,
        prefix = prefix,
        store = st,
        log = logPath,
        jobs = cfg.jobs or gcpkg.sys.nproc(),
        arch = gcpkg.sys.arch(),
        os = gcpkg.sys.os(),
        features = f,
        env = env,
        dependencies = manifests,
        compiler = { cc = ccReal, cxx = cxxReal, wrapper_cc = ccLink, wrapper_cxx = cxxLink },
        intercept_log = jsonl,
        feature_args = function()
            return util.deepcopy(f.args)
        end,
        feature_env = function()
            return util.deepcopy(f.env)
        end,
        defines = function()
            return util.deepcopy(f.defines)
        end,
        dep = function(depName)
            for _, m in ipairs(manifests) do
                if m.name == depName or m.key == depName then
                    return m
                end
            end
            return nil
        end,
    }
    ctx.exec = function(cmd, o)
        o = o or {}
        return gcpkg.exec(cmd, {
            cwd = o.cwd or ctx.src,
            env = util.merge(env, o.env or {}),
            log = o.log or logPath,
            quiet = o.quiet,
            check = o.check,
        })
    end
    ctx.capture = function(cmd, o)
        o = o or {}
        return gcpkg.capture(cmd, { cwd = o.cwd or ctx.src, env = util.merge(env, o.env or {}) })
    end
    ctx.record = function(entry)
        return compdb.record(jsonl, entry)
    end

    if type(spec.build) ~= "function" then
        error(key .. "/build.lua must define build(ctx)")
    end
    gcpkg.log.step("building " .. key .. " features=[" .. table.concat(f.list, ",") .. "]")
    local exports = spec.build(ctx) or {}

    -- 5. compilation database (intercepted + any build-system-native ones)
    local entries = compdb.read(jsonl)
    for _, extra in ipairs(exports.compdb_files or {}) do
        entries = util.concat(entries, compdb.read(extra, "json"))
    end
    local compdbJson = store.compdb_json(st, key)
    entries = compdb.write(entries, compdbJson)
    gcpkg.log.info("  " .. compdb.summary(entries))

    -- 6. manifest
    local manifest = {
        schema = 1,
        name = portName,
        version = version,
        key = key,
        prefix = prefix,
        src = src,
        includes = util.uniq(exports.includes or {}),
        libdirs = util.uniq(exports.libdirs or {}),
        libs = util.uniq(exports.libs or {}),
        defines = util.uniq(util.concat(exports.defines or {}, f.defines)),
        link_flags = util.uniq(exports.link_flags or {}),
        binaries = util.uniq(exports.binaries or {}),
        provides = util.uniq(f.provides),
        features = f.list,
        compdb = compdbJson,
        compdb_jsonl = jsonl,
        compdb_entries = #entries,
        deps = depKeys,
        fingerprint = fingerprint,
    }
    store.write_manifest(st, key, manifest)
    gcpkg.log.step("installed " .. key .. " -> " .. prefix)
    cfg.in_progress[key] = nil
    return manifest
end

return M
