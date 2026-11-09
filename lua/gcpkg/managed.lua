-- Managed multi-project workspace ("a bunch of repositories maintained by
-- gcpkg").  gcpkg is the OUTER meta package manager: it owns the git
-- repositories, their pins, their dependency tree and their build order.  The
-- INNER build/dependency systems stay exactly as they are (CMake, GN, Meson,
-- a project's own `canon` package manager, a hand-written Makefile, ...).
--
-- Layout (relative to the workspace root):
--
--   workspace.yaml        declarative repositories, edges, packages, systems
--   workspace.lock        resolved git commits / submodule pins / package keys
--   repos/<name>/         git checkouts (with nested git submodules)
--   .gcpkg/inject/<name>/ generated toolchains, env files, native files, ...
--   .gcpkg/build/<name>/  out-of-tree build directories
--   .gcpkg/prefix/<name>/ per-project install prefixes exported to dependents
--   compile_commands.json unified compilation database for the whole workspace
--
-- Upstream source files are never modified: all generated files live under
-- .gcpkg/ or at the workspace root, and git operations are delegated to
-- gcpkg.git so the user never has to run git by hand.

local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local yaml = require("gcpkg.yaml")
local json = require("gcpkg.json")
local log = require("gcpkg.log")

local M = {}

local WS_FILE = "workspace.yaml"
local LOCK_FILE = "workspace.lock"
local REPOS_DIR = "repos"

local DEFAULT_TEMPLATE = [[
# gcpkg managed workspace.  Every child repository is maintained by gcpkg:
# clone, fetch, checkout, submodule sync, pinning and build order are automatic.
workspace: my-workspace

# Optional: catalog dependencies shared by every child repository.
# packages: [zlib@1.3.1]

repos:
  # - name: core
  #   url: https://github.com/example/core.git
  #   ref: main
  #   submodules: recursive
  #   systems: [cmake]
  #   depends: []
  #   packages: []
  # - name: app
  #   path: ../app                 # local checkout (no git maintenance)
  #   depends: [core]
  #   systems: [canon, cmake]      # inner package manager, then CMake
  #   commands:
  #     canon: ["canon", "install", "@canon@"]
]]

local SYSTEMS = {
    cmake = true, gn = true, meson = true, canon = true,
    makefile = true, make = true, ninja = true, auto = true, none = true,
}

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function scalar(v)
    if v == nil then return "false" end
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "table" then
        local parts = {}
        for _, x in ipairs(v) do parts[#parts + 1] = tostring(x) end
        return table.concat(parts, " ")
    end
    return tostring(v)
end

local function quote(v)
    return json.encode(scalar(v))
end

local function is_sequence(t)
    if type(t) ~= "table" or #t == 0 then return false end
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
    end
    return true
end

local function as_sequence(t)
    if type(t) ~= "table" then return {} end
    if is_sequence(t) then return t end
    -- A mapping-style list is accepted as well (keys are the values).
    local out = {}
    for k in pairs(t) do out[#out + 1] = scalar(k) end
    table.sort(out)
    return out
end

local function list(value)
    if value == nil then return {} end
    if type(value) == "table" then
        if is_sequence(value) then
            local out = {}
            for _, v in ipairs(value) do
                if type(v) == "table" then
                    out[#out + 1] = scalar(v.name or v[1])
                else
                    out[#out + 1] = scalar(v)
                end
            end
            return out
        end
        return as_sequence(value)
    end
    local s = trim(value)
    if s == "" then return {} end
    local out = {}
    for part in s:gmatch("[^,%s]+") do out[#out + 1] = part end
    return out
end

-- Commands can be written as a string ("canon install @canon@"), as an argv
-- array, or as an array of argv arrays (several steps in order).
local function command_value(v)
    if v == nil or v == false or v == "" then return {} end
    if type(v) == "table" then
        if is_sequence(v) then
            if type(v[1]) == "table" then
                local out = {}
                for _, argv in ipairs(v) do out[#out + 1] = command_value(argv) end
                return out
            end
            local out = {}
            for _, part in ipairs(v) do out[#out + 1] = scalar(part) end
            return out
        end
        local out = {}
        for k, cmd in pairs(v) do out[k] = command_value(cmd) end
        return out
    end
    return util.shellsplit(tostring(v))
end

local function command_lines(r, out)
    local commands = r.commands or {}
    local keys = util.keys(commands)
    if #keys == 0 then return end
    table.sort(keys)
    out[#out + 1] = "    commands:"
    for _, key in ipairs(keys) do
        local value = command_value(commands[key])
        if #value > 0 and type(value[1]) == "table" then
            out[#out + 1] = "      " .. key .. ":"
            for _, argv in ipairs(value) do
                out[#out + 1] = "        - " .. json.encode(argv)
            end
        else
            out[#out + 1] = "      " .. key .. ": " .. json.encode(value)
        end
    end
end

local function systems_value(v)
    local out = {}
    for _, s in ipairs(list(v)) do
        s = trim(s):lower()
        if s == "make" then s = "makefile" end
        if not SYSTEMS[s] then
            error("unknown inner system '" .. s .. "' (expected cmake/gn/meson/canon/makefile/ninja/auto/none)")
        end
        out[#out + 1] = s
    end
    if #out == 0 then out[1] = "auto" end
    return out
end

function M.encode(data)
    local out = {
        "# Generated by gcpkg. Edit with `gcpkg workspace add/remove` or by hand.",
        "workspace: " .. quote(data.workspace or "workspace"),
        "",
    }
    local pkgs = list(data.packages or {})
    if #pkgs > 0 then
        out[#out + 1] = "packages: " .. json.encode(pkgs)
        out[#out + 1] = ""
    end
    out[#out + 1] = "repos:"
    local repos = data.repos or {}
    if #repos == 0 then
        out[#out + 1] = "  []"
    end
    for _, r in ipairs(repos) do
        out[#out + 1] = "  - name: " .. quote(r.name)
        if r.url then out[#out + 1] = "    url: " .. quote(r.url) end
        if r.path then out[#out + 1] = "    path: " .. quote(r.path) end
        if r.ref then out[#out + 1] = "    ref: " .. quote(r.ref) end
        if r.commit then out[#out + 1] = "    commit: " .. quote(r.commit) end
        if r.submodules then out[#out + 1] = "    submodules: " .. quote(r.submodules) end
        local systems = systems_value(r.systems or r.system)
        out[#out + 1] = "    systems: " .. json.encode(systems)
        if r.install_prefix then out[#out + 1] = "    install_prefix: " .. quote(r.install_prefix) end
        if r.build_dir then out[#out + 1] = "    build_dir: " .. quote(r.build_dir) end
        local canon = command_value(r.canon_cmd)
        if #canon > 0 then
            out[#out + 1] = "    canon_cmd: " .. json.encode(canon)
        end
        command_lines(r, out)
        local packages = list(r.packages)
        local depends = list(r.depends)
        local exports = list(r.exports)
        if #packages > 0 then out[#out + 1] = "    packages: " .. json.encode(packages) end
        if #depends > 0 then out[#out + 1] = "    depends: " .. json.encode(depends) end
        if #exports > 0 then out[#out + 1] = "    exports: " .. json.encode(exports) end
    end
    return table.concat(out, "\n") .. "\n"
end

local function normalize_repo(r, fallback_name, seen)
    r = type(r) == "table" and r or { url = r }
    local name = trim(r.name or fallback_name or r[1])
    if name == "" then error("workspace.yaml: every repo needs a name") end
    if name:find("[/\\]") or name == "." or name == ".." then
        error("workspace.yaml: invalid repo name: " .. name)
    end
    if seen[name] then error("workspace.yaml: duplicate repo: " .. name) end
    seen[name] = true
    local url = trim(r.url or r.git or r.repo)
    local path = trim(r.path or r.dir)
    if url == "" then url = nil end
    if path == "" then path = nil end
    if not url and not path then
        error("workspace.yaml: repo " .. name .. " needs url or path")
    end
    local submodules = trim(r.submodules or r.submodule or "false"):lower()
    if submodules == "true" or submodules == "yes" or submodules == "recursive" then
        submodules = "recursive"
    elseif submodules == "false" or submodules == "no" or submodules == "none" or submodules == "" then
        submodules = nil
    elseif submodules ~= "normal" and submodules ~= "shallow" then
        error("workspace.yaml: invalid submodules for " .. name .. ": " .. submodules)
    end
    return {
        name = name, url = url, path = path,
        ref = trim(r.ref or r.branch or r.tag) ~= "" and trim(r.ref or r.branch or r.tag) or nil,
        commit = trim(r.commit or r.revision) ~= "" and trim(r.commit or r.revision) or nil,
        submodules = submodules,
        systems = systems_value(r.systems or r.system or "auto"),
        install_prefix = trim(r.install_prefix or r.prefix) ~= "" and trim(r.install_prefix or r.prefix) or nil,
        build_dir = trim(r.build_dir or r.build) ~= "" and trim(r.build_dir or r.build) or nil,
        canon_cmd = command_value(r.canon_cmd or r.canon_command),
        commands = command_value(r.commands or {}),
        packages = list(r.packages or r.dependencies),
        depends = list(r.depends or r.depends_on or r.needs),
        exports = list(r.exports),
    }
end

local function normalize(data)
    local out = { workspace = trim(data.workspace or data.name or "workspace"),
                  packages = list(data.packages), repos = {} }
    local raw = data.repos or data.projects or {}
    if type(raw) ~= "table" then error("workspace.yaml: repos must be a list") end
    local seen = {}
    if is_sequence(raw) then
        for _, e in ipairs(raw) do
            out.repos[#out.repos + 1] = normalize_repo(e, nil, seen)
        end
    else
        local names = util.keys(raw)
        table.sort(names)
        for _, name in ipairs(names) do
            out.repos[#out.repos + 1] = normalize_repo(raw[name], name, seen)
        end
    end
    return out
end

function M.file(root) return util.join(root, WS_FILE) end
function M.lock_file(root) return util.join(root, LOCK_FILE) end
function M.repos_dir(root) return util.join(root, REPOS_DIR) end
function M.gcpkg_dir(root) return util.join(root, ".gcpkg") end

function M.find_root(start)
    local dir = util.abs(start or fs.cwd())
    while true do
        if fs.isfile(M.file(dir)) then return dir end
        local parent = util.dirname(dir)
        if not parent or parent == dir then return nil end
        dir = parent
    end
end

function M.read(root)
    root = util.abs(root)
    local text = fs.read(M.file(root))
    if not text then error("no workspace.yaml in " .. root .. " (run `gcpkg workspace new DIR`)") end
    return normalize(yaml.parse(text))
end

function M.write(root, data)
    root = util.abs(root)
    fs.write(M.file(root), M.encode(normalize(data)))
    return M.file(root)
end

function M.init(root, name)
    root = util.abs(root)
    fs.mkdirs(root)
    local file = M.file(root)
    if fs.exists(file) then error("workspace already exists: " .. file) end
    fs.write(file, (DEFAULT_TEMPLATE:gsub("my%-workspace", tostring(name or util.basename(root)), 1)))
    fs.mkdirs(M.repos_dir(root))
    log.step("created workspace " .. file)
    return file
end

function M.add(root, spec)
    root = util.abs(root)
    local data = M.read(root)
    local entry = normalize_repo({
        name = trim(spec.name), url = trim(spec.url) ~= "" and trim(spec.url) or nil,
        path = trim(spec.path) ~= "" and trim(spec.path) or nil,
        ref = trim(spec.ref) ~= "" and trim(spec.ref) or nil,
        commit = trim(spec.commit) ~= "" and trim(spec.commit) or nil,
        submodules = trim(spec.submodules),
        systems = list(spec.system or spec.systems),
        canon_cmd = command_value(spec.canon_cmd or spec.cmd),
        commands = command_value(spec.commands or {}),
        depends = list(spec.depends), packages = list(spec.packages),
        exports = list(spec.exports),
    }, nil, {})
    for _, r in ipairs(data.repos) do
        if r.name == entry.name then error("repo already in workspace: " .. entry.name) end
    end
    data.repos[#data.repos + 1] = entry
    M.write(root, data)
    log.step("added repo " .. entry.name .. " to " .. M.file(root))
    return entry
end

function M.remove(root, name)
    root = util.abs(root)
    local data = M.read(root)
    local kept = {}
    for _, r in ipairs(data.repos) do
        if r.name ~= name then
            local deps = {}
            for _, d in ipairs(r.depends) do
                if d ~= name then deps[#deps + 1] = d end
            end
            r.depends = deps
            kept[#kept + 1] = r
        end
    end
    if #kept == #data.repos then error("repo not in workspace: " .. tostring(name)) end
    data.repos = kept
    M.write(root, data)
    log.step("removed repo " .. name .. " from workspace")
end

function M.repo_dir(root, repo)
    if repo.path then
        if util.isabs(repo.path) then return util.abs(repo.path) end
        return util.abs(util.join(root, repo.path))
    end
    return util.join(M.repos_dir(root), repo.name)
end

function M.repo(root, name)
    local data = M.read(root)
    for _, r in ipairs(data.repos) do
        if r.name == name then return r end
    end
    return nil
end

-- Stable topological order.  `depends` edges are explicit; edges implied by a
-- child's gcpkg.yaml `depends` field can be added with `infer_edges`.  A three
-- colour DFS rejects cycles instead of building in an arbitrary order.
function M.order(repos, extra_edges)
    local byname, state, out = {}, {}, {}
    for _, r in ipairs(repos) do byname[r.name] = r end
    local extra = extra_edges or {}
    local function visit(name, stack)
        local s = state[name]
        if s == "done" then return end
        if s == "visiting" then
            error("dependency cycle: " .. table.concat(stack, " -> ") .. " -> " .. name)
        end
        local r = byname[name]
        if not r then error("unknown repo dependency: " .. name) end
        state[name] = "visiting"
        stack[#stack + 1] = name
        local deps, seen = {}, {}
        local function push(d)
            if d ~= name and not seen[d] then seen[d] = true; deps[#deps + 1] = d end
        end
        for _, d in ipairs(r.depends or {}) do push(d) end
        for _, d in ipairs(extra[name] or {}) do push(d) end
        table.sort(deps)
        for _, d in ipairs(deps) do visit(d, stack) end
        stack[#stack] = nil
        state[name] = "done"
        out[#out + 1] = r
    end
    local names = {}
    for _, r in ipairs(repos) do names[#names + 1] = r.name end
    table.sort(names)
    for _, name in ipairs(names) do visit(name, {}) end
    return out
end

function M.infer_edges(root, data)
    local edges, byname = {}, {}
    for _, r in ipairs(data.repos) do byname[r.name] = r end
    for _, r in ipairs(data.repos) do
        local y = yaml.parse_file(util.join(M.repo_dir(root, r), "gcpkg.yaml"))
        if y then
            for _, d in ipairs(list(y.depends or y.projects)) do
                if byname[d] then
                    edges[r.name] = edges[r.name] or {}
                    edges[r.name][#edges[r.name] + 1] = d
                end
            end
        end
    end
    return edges
end

local function lock_list(v)
    local l = list(v)
    if #l == 0 then return "[]" end
    return json.encode(l)
end

function M.encode_lock(value)
    local out = {
        "# Generated by `gcpkg workspace sync/build`. Do not edit by hand.",
        "schema: 1",
        "workspace: " .. quote(value.workspace),
        "generated_by: gcpkg",
        "repos:",
    }
    local repos = value.repos or {}
    if #repos == 0 then out[#out + 1] = "  []" end
    for i, r in ipairs(repos) do
        out[#out + 1] = "  - name: " .. quote(r.name)
        out[#out + 1] = "    order: " .. tostring(r.order or i)
        out[#out + 1] = "    path: " .. quote(r.path)
        if r.url then out[#out + 1] = "    url: " .. quote(r.url) end
        if r.ref then out[#out + 1] = "    ref: " .. quote(r.ref) end
        out[#out + 1] = "    commit: " .. quote(r.commit or "untracked")
        out[#out + 1] = "    submodules: " .. quote(r.submodules or "none")
        out[#out + 1] = "    systems: " .. lock_list(r.systems or { "auto" })
        out[#out + 1] = "    depends: " .. lock_list(r.depends)
        out[#out + 1] = "    packages: " .. lock_list(r.packages)
        local pins = as_sequence(r.submodule_commits or {})
        out[#out + 1] = "    submodule_commits:"
        if #pins == 0 then
            out[#out + 1] = "      []"
        else
            for _, p in ipairs(pins) do
                out[#out + 1] = "      - path: " .. quote(p.path)
                out[#out + 1] = "        commit: " .. quote(p.commit)
                out[#out + 1] = "        initialized: " .. (p.initialized == false and "false" or "true")
            end
        end
        local resolved = as_sequence(r.resolved or {})
        out[#out + 1] = "    resolved:"
        if #resolved == 0 then
            out[#out + 1] = "      []"
        else
            for _, d in ipairs(resolved) do
                out[#out + 1] = "      - name: " .. quote(d.name)
                out[#out + 1] = "        version: " .. quote(d.version or "")
                out[#out + 1] = "        key: " .. quote(d.key)
                out[#out + 1] = "        prefix: " .. quote(d.prefix or "")
            end
        end
    end
    out[#out + 1] = "packages: " .. lock_list(value.packages or {})
    return table.concat(out, "\n") .. "\n"
end

function M.write_lock(root, value)
    fs.write(M.lock_file(root), M.encode_lock(value))
    return M.lock_file(root)
end

function M.read_lock(root)
    local text = fs.read(M.lock_file(root))
    if not text then return nil end
    local ok, value = pcall(yaml.parse, text)
    if not ok or type(value) ~= "table" then return nil end
    value.repos = as_sequence(value.repos or {})
    value.packages = list(value.packages or {})
    return value
end

function M.lock_index(lock)
    local by = {}
    for _, r in ipairs((lock or {}).repos or {}) do by[scalar(r.name)] = r end
    return by
end

return M
