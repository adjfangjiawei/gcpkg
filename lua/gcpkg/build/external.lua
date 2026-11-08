-- Adapter for vendor / proprietary SDKs that cannot be downloaded anonymously:
-- login-walled archives, licence-gated bundles, multi-GB .run installers, or
-- a toolkit already installed on the machine (CUDA, CANN, Video Codec SDK,
-- Dahua PlaySDK, ...).
--
-- The port is a normal gcpkg port: it has a name, a version, dependencies,
-- features.yaml and a manifest. Only two things differ:
--   * `source` is a FUNCTION, so net.prepare() validates the SDK at INSTALL
--     time. `gcpkg check` / `graph` / `ports` / `externals` stay purely static
--     and work on a machine that has none of the SDKs installed.
--   * `build` exports the SDK's include/lib/bin directories instead of
--     compiling anything (binary SDKs have no translation units -> 0 compdb
--     entries, exactly like the data-only fontutil / xcb-proto ports).
--
-- Nothing is copied into the store and the upstream SDK is never modified.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

local function resolve(sdk)
    for _, e in ipairs(util.concat({ sdk.env }, sdk.alt_env or {})) do
        local v = os.getenv(e)
        if v and v ~= "" then
            return v, e
        end
    end
    return sdk.default, sdk.env
end

local function hint(sdk)
    return "set " .. tostring(sdk.env) .. "=/path/to/sdk" ..
           (sdk.url and ("  (download: " .. sdk.url .. ")") or "")
end

-- Build the port table. `spec.sdk` is also exposed verbatim so
-- `gcpkg externals` can print every required environment variable offline.
function M.declare(spec)
    local sdk = spec.sdk or {}
    assert(sdk.env, "external port needs sdk.env")
    local p = {
        name = spec.name,
        version = spec.version,
        description = spec.description,
        license = spec.license,
        homepage = spec.homepage or sdk.url,
        sdk = sdk,
        dependencies = spec.dependencies or {},
    }

    -- Called by net.prepare() only during `gcpkg install`.
    p.source = function(o)
        local root = resolve(sdk)
        if not root or not fs.isdir(root) then
            error(string.format("external SDK %s not found (%s); %s",
                spec.name, tostring(root), hint(sdk)))
        end
        for _, probe in ipairs(sdk.probe or {}) do
            if not fs.isfile(util.join(root, probe)) then
                gcpkg.log.warn("  " .. spec.name .. ": expected " .. probe ..
                    " under " .. root .. " (SDK layout differs; continuing)")
            end
        end
        -- Stable path for the build hook even when the SDK moves later.
        fs.write(util.join(o.dir, ".gcpkg-sdk-root"), root)
    end

    p.build = function(ctx)
        -- The environment variable wins over the marker written by an earlier
        -- install: moving GCPKG_<NAME>_HOME to another SDK version must be
        -- honoured (use --no-cache to force re-running this hook).
        local root = resolve(sdk)
        if not root or not fs.isdir(root) then
            local marker = util.join(ctx.src, ".gcpkg-sdk-root")
            root = fs.isfile(marker) and fs.read(marker) or nil
        end
        if not root or not fs.isdir(root) then
            error("external SDK " .. spec.name .. " not found; " .. hint(sdk))
        end
        root = tostring(root):gsub("%s+$", "")
        local function paths(list)
            local out = {}
            for _, rel in ipairs(list or {}) do
                out[#out + 1] = util.join(root, rel)
            end
            return out
        end
        -- Vendors that DO ship something compilable can opt in here; the
        -- compiler wrapper and all dependency env vars are already in ctx.
        if spec.build_hook then
            spec.build_hook(ctx, root)
        end
        return {
            includes = paths(sdk.includes),
            libdirs = paths(sdk.libdirs),
            libs = sdk.libs or {},
            binaries = paths(sdk.binaries),
            defines = sdk.defines or {},
            link_flags = sdk.link_flags or {},
        }
    end
    return p
end

return M
