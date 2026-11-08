-- Declarative port recipes: the bottom layer of the port ecosystem.
--
-- A library that uses a stock build system can now be described in ~15 lines:
--   local recipe = require("gcpkg.recipe")
--   return recipe.cmake {
--     name="zlib", version="1.3.1", source={url=..., sha256=...},
--     exports={includes={"@PREFIX@/include"}, libdirs={"@LIBDIR@"}, libs={"z"}},
--   }
-- `recipe.define` takes care of prefix, feature args, dependency propagation,
-- compiler interception and compdb import. Anything unusual can still provide
-- its own build(ctx) function -- the recipe layer never takes that away.
--
-- Supported kinds: cmake, meson, autotools, make. Meson matters for the Linux
-- plumbing stack (wayland / X11 / systemd / libinput / libdrm / ...).
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = {}

local function autoLibDir(ctx)
    for _, name in ipairs({ "lib64", "lib" }) do
        local p = util.join(ctx.prefix, name)
        if fs.isdir(p) then
            return p
        end
    end
    return util.join(ctx.prefix, "lib")
end

local function expand(ctx, list)
    local out = {}
    for _, item in ipairs(list or {}) do
        if type(item) == "function" then
            local value = item(ctx)
            if type(value) == "table" then
                for _, v in ipairs(value) do
                    out[#out + 1] = tostring(v)
                end
            elseif value then
                out[#out + 1] = tostring(value)
            end
        else
            local s = tostring(item):gsub("@PREFIX@", ctx.prefix):gsub("@LIBDIR@", autoLibDir(ctx))
            out[#out + 1] = s
        end
    end
    return out
end

local function dependencyPrefixes(ctx)
    local out = {}
    for _, m in ipairs(ctx.all_dependencies or {}) do
        if m.prefix then
            out[#out + 1] = m.prefix
        end
    end
    return util.uniq(out)
end

function M.define(spec)
    local kind = spec.kind or "cmake"
    local portTable = {
        name = spec.name,
        version = spec.version,
        description = spec.description,
        license = spec.license,
        homepage = spec.homepage,
        source = spec.source,
        dependencies = spec.dependencies or {},
    }

    local generated = function(ctx)
        local featureArgs = ctx.feature_args()
        local result = {}

        -- Some tarballs ship only configure.ac (no generated ./configure) or
        -- need generated sources before the stock build system can run.
        -- pre_build is ordinary Lua, so the recipe stays declarative for the
        -- 99% case without taking anything away from the 1%.
        if spec.pre_build then
            spec.pre_build(ctx)
        end

        if kind == "cmake" then
            local cmake = require("gcpkg.build.cmake")
            local cfg = spec.cmake or {}
            -- defines may be a function(ctx) when a value depends on an
            -- installed dependency prefix (e.g. -DOPENSSL_ROOT_DIR=...).
            local defines = util.deepcopy(type(cfg.defines) == "function" and cfg.defines(ctx)
                                          or cfg.defines or {})
            local args = util.concat(util.deepcopy(cfg.args or {}), featureArgs)
            local prefixes = dependencyPrefixes(ctx)
            if #prefixes > 0 and not defines.CMAKE_PREFIX_PATH then
                defines.CMAKE_PREFIX_PATH = table.concat(prefixes, ";")
            end
            result = cmake.all {
                src = cfg.source and util.join(ctx.src, cfg.source) or ctx.src,
                build_dir = ctx.build_dir,
                prefix = ctx.prefix,
                exec = ctx.exec,
                log = ctx.log,
                jobs = ctx.jobs,
                env = ctx.env,
                defines = defines,
                args = args,
                generator = cfg.generator,
            }

        elseif kind == "meson" then
            local meson = require("gcpkg.build.meson")
            local cfg = spec.meson or {}
            -- options may be a function(ctx), e.g. to point -Dxkb-config-root
            -- at a dependency's installed prefix.
            local options = util.deepcopy(type(cfg.options) == "function" and cfg.options(ctx)
                                          or cfg.options or {})
            local args = util.concat(util.deepcopy(cfg.args or {}), featureArgs)
            if cfg.auto_features then
                options.auto_features = cfg.auto_features
            end
            result = meson.all {
                src = cfg.source and util.join(ctx.src, cfg.source) or ctx.src,
                build_dir = ctx.build_dir,
                prefix = ctx.prefix,
                exec = ctx.exec,
                log = ctx.log,
                jobs = ctx.jobs,
                env = ctx.env,
                options = options,
                args = args,
                libdir = cfg.libdir,
                buildtype = cfg.buildtype,
                wrap_mode = cfg.wrap_mode,
            }

        elseif kind == "autotools" then
            local autotools = require("gcpkg.build.autotools")
            local cfg = spec.autotools or {}
            local args = util.concat(util.deepcopy(cfg.args or {}), featureArgs)
            result = autotools.all {
                src = ctx.src,
                configure = cfg.configure and util.join(ctx.src, cfg.configure) or nil,
                prefix = ctx.prefix,
                exec = ctx.exec,
                log = ctx.log,
                jobs = ctx.jobs,
                env = ctx.env,
                args = args,
                install_target = cfg.install_target or "install",
            }

        elseif kind == "make" then
            local make = require("gcpkg.build.make")
            local cfg = spec.make or {}
            local vars = util.deepcopy(type(cfg.vars) == "function" and cfg.vars(ctx) or cfg.vars or {})
            -- Hand-written Makefiles often hard-code CC=gcc, which would bypass
            -- our interceptor. Command-line make variables win over the file.
            if not vars.CC then
                vars.CC = ctx.compiler.wrapper_cc
            end
            if not vars.CXX then
                vars.CXX = ctx.compiler.wrapper_cxx
            end
            local targets = util.deepcopy(cfg.targets or {})
            for _, a in ipairs(featureArgs) do
                local k, v = tostring(a):match("^([%w_]+)=(.*)$")
                if k then
                    vars[k] = v
                else
                    targets[#targets + 1] = a
                end
            end
            make.run {
                cwd = ctx.src, exec = ctx.exec, log = ctx.log,
                jobs = cfg.jobs or ctx.jobs, env = ctx.env, vars = vars, targets = targets,
            }
            if cfg.install_target then
                make.run {
                    cwd = ctx.src, exec = ctx.exec, log = ctx.log,
                    jobs = cfg.jobs or ctx.jobs, env = ctx.env, vars = vars,
                    targets = { cfg.install_target },
                }
            end
        else
            error("unknown recipe kind '" .. tostring(kind) .. "'")
        end

        if spec.post_install then
            spec.post_install(ctx)
        end

        local exports = {
            includes = expand(ctx, spec.exports and spec.exports.includes),
            libdirs = expand(ctx, spec.exports and spec.exports.libdirs),
            libs = expand(ctx, spec.exports and spec.exports.libs),
            defines = expand(ctx, spec.exports and spec.exports.defines),
            link_flags = expand(ctx, spec.exports and spec.exports.link_flags),
            binaries = expand(ctx, spec.exports and spec.exports.binaries),
            compdb_files = util.concat(result.compdb_files or {},
                                       spec.exports and spec.exports.compdb_files or {}),
        }
        return exports
    end

    portTable.build = spec.build or generated
    return portTable
end

function M.cmake(spec)
    spec.kind = "cmake"
    return M.define(spec)
end

function M.meson(spec)
    spec.kind = "meson"
    return M.define(spec)
end

function M.autotools(spec)
    spec.kind = "autotools"
    return M.define(spec)
end

function M.make(spec)
    spec.kind = "make"
    return M.define(spec)
end

return M
