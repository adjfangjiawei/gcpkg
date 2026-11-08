-- Stable on-disk layout. Dependency source trees live here permanently, which
-- is what makes cross-library clangd navigation work: the absolute paths inside
-- compile_commands.json stay valid after the build finishes.
local fs = require("gcpkg.fs")
local json = require("gcpkg.json")
local util = require("gcpkg.util")
local M = {}

local SUBDIRS = { "src", "build", "pkg", "compdb", "logs", "manifest", "bin", "cache" }

function M.new(root)
    root = util.join(root)
    local s = { root = root }
    for _, name in ipairs(SUBDIRS) do
        s[name] = root .. "/" .. name
        fs.mkdirs(s[name])
    end
    return s
end

function M.key(name, version)
    return tostring(name) .. "-" .. tostring(version)
end

function M.manifest_path(store, key)
    return store.manifest .. "/" .. key .. ".json"
end

function M.read_manifest(store, key)
    local text = fs.read(M.manifest_path(store, key))
    if not text then
        return nil
    end
    local ok, value = pcall(json.decode, text)
    if not ok or type(value) ~= "table" then
        return nil
    end
    return value
end

function M.write_manifest(store, key, manifest)
    fs.write(M.manifest_path(store, key), json.encode(manifest, true) .. "\n")
end

function M.compdb_jsonl(store, key)
    return store.compdb .. "/" .. key .. ".jsonl"
end

function M.compdb_json(store, key)
    return store.compdb .. "/" .. key .. ".json"
end

function M.log_path(store, key)
    return store.logs .. "/" .. key .. ".log"
end

function M.fingerprint(parts)
    return table.concat(util.sorted_list(parts), "|")
end

function M.is_fresh(manifest, fingerprint)
    if not manifest or manifest.fingerprint ~= fingerprint then
        return false
    end
    if not fs.isfile(manifest.compdb) then
        return false
    end
    for _, p in ipairs(manifest.includes or {}) do
        if not fs.isdir(p) then
            return false
        end
    end
    for _, p in ipairs(manifest.libdirs or {}) do
        if not fs.isdir(p) then
            return false
        end
    end
    return true
end

return M
