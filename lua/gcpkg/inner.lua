-- Inner build-system driver for projects managed by gcpkg.
--
-- gcpkg does NOT replace a project's own build system.  It injects the outer
-- dependencies (see inject.lua) and then invokes the inner system(s) in order:
-- a project's own Conan (plus the legacy `canon` alias), CMake, GN, Meson, a
-- Makefile, Ninja, or any user-provided command. Multiple systems may be listed,
-- e.g. `systems: [conan, cmake]` runs Conan first and CMake second with the SAME
-- injected environment.  No file in the project source tree is rewritten.

local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local detect = require("gcpkg.detect")
local log = require("gcpkg.log")

local M = {}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function systems(v)
    if v == nil or v == "" then return nil end
    if type(v) == "table" then
        local out = {}
        for _, x in ipairs(v) do
            local s = trim(x):lower()
            if s ~= "" then out[#out + 1] = s end
        end
        return #out > 0 and out or nil
    end
    local out = {}
    for part in tostring(v):gmatch("[^,%s]+") do out[#out + 1] = trim(part):lower() end
    return #out > 0 and out or nil
end

local function command(v)
    if v == nil or v == false or v == "" then return {} end
    if type(v) == "table" then
        if #v > 0 and type(v[1]) == "table" then
            local out = {}
            for _, argv in ipairs(v) do out[#out + 1] = command(argv) end
            return out
        end
        local out = {}
        for _, part in ipairs(v) do out[#out + 1] = tostring(part) end
        return out
    end
    return util.shellsplit(tostring(v))
end

local function commandSteps(v)
    local c = command(v)
    if #c == 0 then return {} end
    if type(c[1]) == "table" then return c end
    return { c }
end

local function tokens(ctx, opts)
    local inject = ctx.inject or error("inner: missing injected dependency context")
    local files = inject.files
    local build = util.abs(opts.build_dir or ctx.build_dir or files.build_dir)
    local prefix = util.abs(opts.install_prefix or files.install_prefix)
    local env = ctx.env or {}
    return {
        ["@root@"] = files.root, ["@workspace@"] = files.root,
        ["@project@"] = ctx.project_dir, ["@src@"] = ctx.project_dir,
        ["@build@"] = build, ["@prefix@"] = prefix, ["@inject@"] = files.dir,
        ["@jobs@"] = tostring(ctx.jobs or gcpkg.sys.nproc()),
        ["@toolchain@"] = files.toolchain, ["@cmake-toolchain@"] = files.toolchain,
        ["@cache@"] = files.cache, ["@cmake-cache@"] = files.cache,
        ["@native@"] = files.meson, ["@meson@"] = files.meson,
        ["@gni@"] = files.gn_gni, ["@gnargs@"] = files.gn_args,
        ["@makeflags@"] = files.make_flags, ["@deps@"] = files.deps,
        ["@conan@"] = files.conan, ["@conan-json@"] = files.conan,
        ["@canon@"] = files.canon, ["@canon-json@"] = files.canon,
        ["@conan-env@"] = files.conan_env,
        ["@env@"] = files.env, ["@canon-env@"] = files.canon_env,
        ["@pkgconfig@"] = files.pkgconfig, ["@compdb@"] = files.compdb,
        ["@cc@"] = env.CC or (ctx.compiler or {}).wrapper_cc or "cc",
        ["@cxx@"] = env.CXX or (ctx.compiler or {}).wrapper_cxx or "c++",
    }
end

local function expand(argv, ctx, opts)
    local t = tokens(ctx, opts)
    local out = {}
    for _, a in ipairs(argv) do
        local s = tostring(a)
        for k, v in pairs(t) do
            local pattern = k:gsub("([^%w])", "%%%1")
            s = s:gsub(pattern, tostring(v))
        end
        out[#out + 1] = s
    end
    return out
end

local function exec(ctx, argv, opts, extra)
    extra = extra or {}
    local cmd = expand(argv, ctx, opts)
    log.info("  inner: " .. table.concat(cmd, " "))
    return ctx.exec(cmd, {
        cwd = extra.cwd or ctx.project_dir, log = ctx.log,
        env = extra.env, quiet = extra.quiet, check = extra.check,
    })
end

local function compdbCandidates(ctx, opts)
    local files = ctx.inject.files
    local build = util.abs(opts.build_dir or ctx.build_dir or files.build_dir)
    return {
        files.compdb,
        util.join(build, "compile_commands.json"),
        util.join(ctx.project_dir, "compile_commands.json"),
        util.join(files.dir, "compile_commands.json"),
    }
end

local function collectCompdb(ctx, opts, out)
    local seen = {}
    for _, p in ipairs(compdbCandidates(ctx, opts)) do
        if fs.isfile(p) and not seen[p] then
            seen[p] = true
            out[#out + 1] = p
        end
    end
    return out
end

local function makefileHasInstall(src)
    for _, name in ipairs({ "Makefile", "makefile", "GNUmakefile" }) do
        local text = fs.read(util.join(src, name))
        if text and text:match("[\r\n]%s*install%s*:") then return true end
        if text and text:match("^%s*install%s*:") then return true end
    end
    return false
end

local function gnDeclaresArgs(src)
    local files = {
        ".gn", "BUILDCONFIG.gn", "build/BUILDCONFIG.gn",
        "build/config/BUILDCONFIG.gn", "gn/BUILDCONFIG.gn",
    }
    for _, name in ipairs(files) do
        local text = fs.read(util.join(src, name))
        if text and text:find("declare_args", 1, true) and text:find("gcpkg_", 1, true) then
            return true
        end
    end
    return false
end

local function runCustom(ctx, opts, value, compdb)
    for _, argv in ipairs(commandSteps(value)) do
        exec(ctx, argv, opts)
    end
    collectCompdb(ctx, opts, compdb)
end

local function runCmake(ctx, opts, compdb)
    local cmake = require("gcpkg.build.cmake")
    local files = ctx.inject.files
    local result = cmake.all {
        src = ctx.project_dir,
        build_dir = util.abs(opts.build_dir or ctx.build_dir or files.build_dir),
        prefix = files.install_prefix,
        exec = ctx.exec, log = ctx.log, jobs = ctx.jobs,
        env = ctx.env,
        args = { "-C", files.cache },
    }
    for _, p in ipairs(result.compdb_files or {}) do compdb[#compdb + 1] = p end
    collectCompdb(ctx, opts, compdb)
end

local function runMeson(ctx, opts, compdb)
    local meson = require("gcpkg.build.meson")
    local files = ctx.inject.files
    local result = meson.all {
        src = ctx.project_dir,
        build_dir = util.abs(opts.build_dir or ctx.build_dir or files.build_dir),
        prefix = files.install_prefix,
        exec = ctx.exec, log = ctx.log, jobs = ctx.jobs,
        env = ctx.env, libdir = "lib", wrap_mode = "nodownload",
        args = { "--native-file=" .. files.meson },
    }
    for _, p in ipairs(result.compdb_files or {}) do compdb[#compdb + 1] = p end
    collectCompdb(ctx, opts, compdb)
end

local function runGn(ctx, opts, compdb)
    local gn = require("gcpkg.build.gn")
    local files = ctx.inject.files
    local args
    if gnDeclaresArgs(ctx.project_dir) then
        args = fs.read(files.gn_args) or ""
    end
    local result = gn.all {
        src = ctx.project_dir,
        build_dir = util.abs(opts.build_dir or ctx.build_dir or files.build_dir),
        exec = ctx.exec, log = ctx.log, jobs = ctx.jobs,
        env = ctx.env, args = args,
        extra_args = { "--root=" .. ctx.project_dir },
    }
    for _, p in ipairs(result.compdb_files or {}) do compdb[#compdb + 1] = p end
    collectCompdb(ctx, opts, compdb)
end

local function runMakefile(ctx, opts, compdb)
    local make = require("gcpkg.build.make")
    local files = ctx.inject.files
    local env = ctx.env or {}
    local vars = {
        CC = env.CC or (ctx.compiler or {}).wrapper_cc or "cc",
        CXX = env.CXX or (ctx.compiler or {}).wrapper_cxx or "c++",
        CPPFLAGS = env.CPPFLAGS or "", CFLAGS = env.CFLAGS or "",
        CXXFLAGS = env.CXXFLAGS or "", LDFLAGS = env.LDFLAGS or "",
        LDLIBS = env.LDLIBS or "", PREFIX = files.install_prefix,
    }
    local common = {
        cwd = ctx.project_dir, exec = ctx.exec, log = ctx.log,
        jobs = ctx.jobs, env = ctx.env, vars = vars,
    }
    make.run(common)
    if makefileHasInstall(ctx.project_dir) then
        make.run(util.merge(common, { targets = { "install" } }))
    end
    collectCompdb(ctx, opts, compdb)
end

local function runNinja(ctx, opts, compdb)
    local files = ctx.inject.files
    local build = util.abs(opts.build_dir or ctx.build_dir or files.build_dir)
    exec(ctx, { "ninja", "-C", ctx.project_dir, "-j", "@jobs@" }, opts)
    local out, code = ctx.capture({ "ninja", "-C", ctx.project_dir, "-t", "compdb" },
                                  { env = ctx.env })
    if code == 0 and out and out ~= "" then
        fs.mkdirs(build)
        fs.write(util.join(build, "compile_commands.json"), out)
    end
    collectCompdb(ctx, opts, compdb)
end

local function runConan(ctx, opts, compdb)
    local files = ctx.inject.files
    local custom = (opts.commands or {}).conan or opts.conan_cmd or
                   (ctx.env or {}).CONAN_CMD or
                   (opts.commands or {}).canon or opts.canon_cmd or
                   (ctx.env or {}).CANON_CMD
    if custom then
        runCustom(ctx, opts, custom, compdb)
        return
    end
    if gcpkg.have("conan") then
        -- Conan 2 syntax. Explicit commands.conan / conan_cmd are preferred;
        -- gcpkg never parses Conan output or rewrites conanfile.py/txt.
        exec(ctx, { "conan", "install", ".", "--output-folder=@build@" }, opts)
        collectCompdb(ctx, opts, compdb)
        return
    end
    if gcpkg.have("canon") then
        exec(ctx, { "canon", "install" }, opts)
        collectCompdb(ctx, opts, compdb)
        return
    end
    error("inner Conan package manager has no command configured; set " ..
          "commands.conan / conan_cmd in workspace.yaml (or --cmd), or put a " ..
          "`conan` executable on PATH. The legacy `canon` alias is still accepted. " ..
          "gcpkg has already written " .. files.conan .. " and the CONAN_* variables.")
end

function M.systems_for(src, opts)
    opts = opts or {}
    local explicit = systems(opts.systems or opts.system)
    if explicit and #explicit > 0 then return explicit end
    local kinds = detect.build_systems(src)
    if #kinds == 0 then return { "none" } end
    local out = {}
    for _, kind in ipairs(kinds) do
        if kind == "make" then kind = "makefile" end
        out[#out + 1] = kind
    end
    return out
end

function M.run(ctx, opts)
    opts = opts or {}
    local compdb = {}
    if opts.cmd then
        runCustom(ctx, opts, opts.cmd, compdb)
        return { compdb_files = util.uniq(compdb) }
    end
    local list = M.systems_for(ctx.project_dir, opts)
    local commands = opts.commands or {}
    for _, system in ipairs(list) do
        if system == "make" then system = "makefile" end
        log.step("inner system " .. system .. " for " .. (ctx.name or util.basename(ctx.project_dir)))
        local custom = commands.all or commands[system]
        if custom then
            runCustom(ctx, opts, custom, compdb)
        elseif system == "auto" then
            local detected = M.systems_for(ctx.project_dir, {})
            for _, s in ipairs(detected) do
                if s ~= "auto" and s ~= "none" then
                    local innerOpts = util.merge(opts, { systems = { s }, commands = {} })
                    local result = M.run(ctx, innerOpts)
                    for _, p in ipairs(result.compdb_files or {}) do compdb[#compdb + 1] = p end
                end
            end
        elseif system == "cmake" then
            runCmake(ctx, opts, compdb)
        elseif system == "meson" then
            runMeson(ctx, opts, compdb)
        elseif system == "gn" then
            runGn(ctx, opts, compdb)
        elseif system == "makefile" then
            runMakefile(ctx, opts, compdb)
        elseif system == "ninja" then
            runNinja(ctx, opts, compdb)
        elseif system == "conan" or system == "canon" then
            runConan(ctx, opts, compdb)
        elseif system == "none" then
            log.info("  no inner build system declared; injection files are ready")
        else
            error("unsupported inner system: " .. tostring(system))
        end
    end
    return { compdb_files = util.uniq(compdb) }
end

return M
