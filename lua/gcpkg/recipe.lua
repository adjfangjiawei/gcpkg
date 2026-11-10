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
-- Supported kinds: cmake, meson, autotools, make, gn, python, cargo, header.
-- The header recipe copies upstream headers into <prefix>/include and compiles
-- one generated probe translation unit so clangd gets a real compile command.
-- Meson matters for the Linux plumbing stack (wayland / X11 / systemd / ...).
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
    for _, m in ipairs(ctx.dependencies or {}) do
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
                -- A port may cap parallelism (heavy template TUs can OOM a
                -- small builder); otherwise the CLI -j value is used.
                jobs = cfg.jobs or ctx.jobs,
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
                -- R20: make-variable overrides may depend on the install
                -- prefix (e.g. redirect an upstream hardcoded system dir).
                vars = type(cfg.vars) == "function" and cfg.vars(ctx) or cfg.vars,
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
        elseif kind == "gn" then
            -- GN meta-build system: gn gen (Ninja files) + ninja build.
            -- args may be a list of GN assignments or a function(ctx) for
            -- values that depend on the installed tree / host toolchain.
            local gn = require("gcpkg.build.gn")
            local cfg = spec.gn or {}
            local a = cfg.args
            if type(a) == "function" then a = a(ctx) end
            if type(a) == "string" then a = { a } end
            local args = util.concat(util.deepcopy(a or {}), featureArgs)
            result = gn.all {
                src = cfg.source and util.join(ctx.src, cfg.source) or ctx.src,
                build_dir = ctx.build_dir,
                prefix = ctx.prefix,
                exec = ctx.exec,
                log = ctx.log,
                jobs = cfg.jobs or ctx.jobs,
                env = ctx.env,
                args = args,
                targets = cfg.targets or {},
                gn = cfg.gn or "gn",
                ninja = cfg.ninja or "ninja",
            }

        elseif kind == "python" then
            -- setup.py / pip based Python packages. PYTHONPATH for dependents
            -- comes from <prefix>/lib/python3/site-packages (dependency_env).
            local python = require("gcpkg.build.python")
            local cfg = spec.python or {}
            local args = util.concat(util.deepcopy(cfg.args or {}), featureArgs)
            result = python.all {
                src = cfg.source and util.join(ctx.src, cfg.source) or ctx.src,
                prefix = ctx.prefix, exec = ctx.exec, log = ctx.log,
                env = ctx.env, mode = cfg.mode, python = cfg.python, args = args,
                no_isolation = cfg.no_isolation,
            }

        elseif kind == "cargo" then
            -- Rust crates: cargo comes from the `rust` tool port on PATH.
            local cargo = require("gcpkg.build.cargo")
            local cfg = spec.cargo or {}
            local args = util.concat(util.deepcopy(cfg.args or {}), featureArgs)
            result = cargo.all {
                src = cfg.source and util.join(ctx.src, cfg.source) or ctx.src,
                prefix = ctx.prefix, exec = ctx.exec, log = ctx.log,
                env = ctx.env, args = args,
            }

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

function M.gn(spec)
    spec.kind = "gn"
    return M.define(spec)
end

function M.python(spec)
    spec.kind = "python"
    return M.define(spec)
end

function M.cargo(spec)
    spec.kind = "cargo"
    return M.define(spec)
end

-- Header-only tarballs without upstream CMake install rules.  `header` is:
--   headers = { { src = "include/foo.hpp", dst = "foo.hpp" }, ... }
--   include = "foo.hpp"       -- header used by the generated probe TU
--   cxx = true                -- false compiles the probe as C
--   prelude = { "cstdint" }   -- optional system headers before `include`
--   flags = { "-std=c++17" }  -- optional compiler flags
--   license_files = { "LICENSE" } -- copied to prefix/share/doc/<name>
function M.header(spec)
    spec.kind = "header"
    spec.build = spec.build or function(ctx)
        local h = spec.header or {}
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        fs.mkdirs(incdir)
        fs.mkdirs(libdir)
        for _, entry in ipairs(h.headers or {}) do
            local src = util.join(ctx.src, entry.src)
            local dst = entry.dst and util.join(incdir, entry.dst) or incdir
            fs.mkdirs(util.dirname(dst))
            ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
        end
        for _, license in ipairs(h.license_files or {}) do
            local doc = util.join(ctx.prefix, "share", "doc", spec.name or "header")
            fs.mkdirs(doc)
            ctx.exec({ "cp", "-a", util.join(ctx.src, license), doc },
                     { cwd = ctx.src, log = ctx.log })
        end
        local cxx = h.cxx ~= false
        local probe = util.join(ctx.build_dir, cxx and "gcpkg_header_probe.cpp" or "gcpkg_header_probe.c")
        local lines = {}
        for _, prelude in ipairs(h.prelude or {}) do
            lines[#lines + 1] = "#include <" .. tostring(prelude) .. ">"
        end
        lines[#lines + 1] = "#include <" .. tostring(h.include) .. ">"
        lines[#lines + 1] = "int main(void) { return 0; }"
        fs.write(probe, table.concat(lines, "\n") .. "\n")
        local cc = require("gcpkg.build.cc")
        cc.compile {
            sources = { probe }, includes = { incdir },
            flags = h.flags or (cxx and { "-std=c++17" } or {}),
            cwd = ctx.build_dir, outdir = util.join(ctx.build_dir, "obj"),
            compiler = cxx and ctx.compiler.wrapper_cxx or ctx.compiler.wrapper_cc,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = spec.name or "header",
        }
        return {
            includes = { incdir }, libdirs = { libdir },
            libs = {}, binaries = {}, compdb_files = {},
        }
    end
    return M.define(spec)
end

return M
