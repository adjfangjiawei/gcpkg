-- Port = ONE build.lua + ONE features.yaml, nothing else.
--
-- install() is the whole library lifecycle: resolve features -> recurse into
-- dependencies -> fetch source -> run the Lua build hook with an instrumented
-- environment -> turn intercepted compiler calls into a compilation database
-- -> write a manifest that projects and other ports can consume.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local json = require("gcpkg.json")
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

-- All transitive dependency manifests, dependencies first (bottom-up).
function M.transitive(manifests, st)
    local ordered, seen = {}, {}
    local function visit(m)
        if not m or not m.key or seen[m.key] then
            return
        end
        seen[m.key] = true
        for _, depKey in ipairs(m.deps or {}) do
            visit(store.read_manifest(st, depKey))
        end
        ordered[#ordered + 1] = m
    end
    for _, m in ipairs(manifests) do
        visit(m)
    end
    return ordered
end

-- Make lower-level libraries visible to higher-level builds *without* editing
-- the upstream project: standard env vars understood by CMake, autotools,
-- pkg-config and most hand-written Makefiles.
function M.dependency_env(ordered)
    if #ordered == 0 then
        return {}
    end
    local includes, libdirs, defines, prefixes = {}, {}, {}, {}
    local pkgdirs = {}
    for _, m in ipairs(ordered) do
        includes = util.concat(includes, m.includes or {})
        libdirs = util.concat(libdirs, m.libdirs or {})
        defines = util.concat(defines, m.defines or {})
        if m.prefix then
            prefixes[#prefixes + 1] = m.prefix
        end
    end
    local cpp, ld = {}, {}
    for _, i in ipairs(util.uniq(includes)) do
        cpp[#cpp + 1] = "-I" .. i
    end
    for _, d in ipairs(util.uniq(defines)) do
        cpp[#cpp + 1] = "-D" .. d
    end
    for _, l in ipairs(util.uniq(libdirs)) do
        ld[#ld + 1] = "-L" .. l
        pkgdirs[#pkgdirs + 1] = util.join(l, "pkgconfig")
    end
    local acl, py = {}, {}
    for _, p in ipairs(util.uniq(prefixes)) do
        -- X11 / Wayland "data" ports (xorgproto, xcb-proto,
        -- wayland-protocols) install their .pc files under share/pkgconfig,
        -- not lib/pkgconfig. Without this, meson's dependency() and
        -- ./configure's PKG_CHECK_MODULES cannot see the lower layers.
        pkgdirs[#pkgdirs + 1] = util.join(p, "lib", "pkgconfig")
        pkgdirs[#pkgdirs + 1] = util.join(p, "lib64", "pkgconfig")
        pkgdirs[#pkgdirs + 1] = util.join(p, "share", "pkgconfig")
        acl[#acl + 1] = util.join(p, "share", "aclocal")
        py[#py + 1] = util.join(p, "lib", "python3", "site-packages")
    end
    local env = {}
    if #cpp > 0 then
        env.CPPFLAGS = table.concat(cpp, " ")
        -- Some hand-written Makefiles / configure probes honour CPATH but not
        -- CPPFLAGS; keep both in sync so headers are found either way.
        env.CPATH = table.concat(util.uniq(includes), ":")
    end
    if #ld > 0 then
        env.LDFLAGS = table.concat(ld, " ")
        env.LIBRARY_PATH = table.concat(util.uniq(libdirs), ":")
    end
    if #pkgdirs > 0 then
        env.PKG_CONFIG_PATH = table.concat(util.uniq(pkgdirs), ":")
    end
    if #acl > 0 then
        env.ACLOCAL_PATH = table.concat(util.uniq(acl), ":")
    end
    if #py > 0 then
        env.PYTHONPATH = table.concat(util.uniq(py), ":")
    end
    if #prefixes > 0 then
        env.CMAKE_PREFIX_PATH = table.concat(util.uniq(prefixes), ";")
    end
    return env
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
    local ordered = M.transitive(manifests, st)
    local depIncludes, depLibdirs, depLibs, depDefines, depLinkFlags = {}, {}, {}, {}, {}
    for _, m in ipairs(ordered) do
        depIncludes = util.concat(depIncludes, m.includes or {})
        depLibdirs = util.concat(depLibdirs, m.libdirs or {})
        depLibs = util.concat(depLibs, m.libs or {})
        depDefines = util.concat(depDefines, m.defines or {})
        depLinkFlags = util.concat(depLinkFlags, m.link_flags or {})
    end

    -- Port files are part of the build recipe: editing build.lua or
    -- features.yaml must invalidate the cached build (CMake defines live in
    -- build.lua, so a stale cache would silently keep old options).
    local buildHash = net.sha256(util.join(dir, "build.lua")) or ""
    local featureHash = net.sha256(util.join(dir, "features.yaml")) or ""
    local fingerprint = store.fingerprint(util.concat({
        portName, version, f.hash,
        (type(spec.source) == "table" and (spec.source.url or spec.source.git or spec.source.dir)) or "custom",
        gcpkg.sys.os(), gcpkg.sys.arch(), table.concat(depKeys, ","),
        "build=" .. buildHash, "features=" .. featureHash,
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
    local env = util.merge(M.dependency_env(ordered), f.env, {
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
        all_dependencies = ordered,
        includes = util.uniq(depIncludes),
        libdirs = util.uniq(depLibdirs),
        libs = util.uniq(depLibs),
        defines = util.uniq(depDefines),
        link_flags = util.uniq(depLinkFlags),
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
            for _, m in ipairs(ordered) do
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

    -- 5. compilation database (intercepted + build-system-native ones).
    -- Rewrite the JSONL with the UNION so it is the single source of truth:
    -- cache hits (and project merges) then never lose CMake/Meson entries.
    local entries = compdb.read(jsonl)
    for _, extra in ipairs(exports.compdb_files or {}) do
        entries = util.concat(entries, compdb.read(extra, "json"))
    end
    entries = compdb.dedup(entries)
    fs.write(jsonl, "")
    for _, e in ipairs(entries) do
        fs.append(jsonl, json.encode(e) .. "\n")
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
