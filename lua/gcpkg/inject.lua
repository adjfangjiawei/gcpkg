-- vcpkg-style dependency injection for INNER build systems.
--
-- gcpkg installs the outer dependency tree, then writes a self-contained
-- injection directory.  Nothing inside the project's source tree is rewritten:
-- generated CMake toolchains/cache files, Meson native files, GN .gni/args,
-- Makefile fragments, pkg-config directories, env scripts and JSON manifests
-- all live in .gcpkg/inject/<project>/.  A project can keep using its own
-- CMake, GN, Meson, Conan package manager, Makefile, or any combination.
--
-- Conan is the first-class inner package manager; `canon` is a compatibility
-- alias for existing workspace files. gcpkg does not
-- parse Conan output or rewrite conanfile.py/txt: it supplies CONAN_* (plus
-- legacy CANON_*) and GCPKG_* variables, gcpkg-conan.json / gcpkg-canon.json,
-- and wrappers that invoke CONAN_CMD / CANON_CMD / commands.conan.  Explicit
-- configuration is always preferred over guessing a CLI.

local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local json = require("gcpkg.json")
local yaml = require("gcpkg.yaml")
local toolchain = require("gcpkg.toolchain")
local compdb = require("gcpkg.compdb")
local port = require("gcpkg.port")
local workspace = require("gcpkg.workspace")
local storeMod = require("gcpkg.store")
local cmake_version = require("gcpkg.cmake_version")

local M = {}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function shquote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end
local function cmakeQuote(s)
    return tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"')
end
local function jsonList(list)
    return json.encode(list or {})
end
-- Meson machine files use Python-style single quoted strings; JSON-style
-- double quotes are rejected by meson's machine-file parser.
local function mesonQuote(s)
    return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end
local function mesonList(list)
    local out = {}
    for _, v in ipairs(util.uniq(list or {})) do out[#out + 1] = mesonQuote(v) end
    return "[" .. table.concat(out, ", ") .. "]"
end
local function envName(s)
    return (tostring(s):upper():gsub("[^%w]", "_"))
end
local function colon(list) return table.concat(util.uniq(list or {}), ":") end
local function semicolon(list) return table.concat(util.uniq(list or {}), ";") end
local function getenv(k) return gcpkg.sys.getenv(k) or "" end
local function appendVar(name, value, sep)
    local prev = getenv(name)
    if prev == "" then return value end
    if value == "" then return prev end
    return value .. (sep or " ") .. prev
end
local function libFlag(lib)
    local s = tostring(lib)
    if s:sub(1, 1) == "-" or s:sub(1, 1) == "/" or s:match("%.a$") or s:match("%.so") then
        return s
    end
    return "-l" .. s
end

local function flagStrings(list, prefix)
    local out = {}
    for _, v in ipairs(util.uniq(list or {})) do
        out[#out + 1] = prefix .. tostring(v)
    end
    return out
end

-- CMake list arguments: quoted, space-separated strings (CMake turns them
-- into a semicolon-separated list when passed to set()/list()).
local function cmakeArgs(list)
    local out = {}
    for _, v in ipairs(util.uniq(list or {})) do
        out[#out + 1] = '"' .. cmakeQuote(v) .. '"'
    end
    return table.concat(out, " ")
end

local function systems(v)
    if v == nil then return nil end
    if type(v) == "table" then
        local out = {}
        for _, x in ipairs(v) do out[#out + 1] = tostring(x) end
        return out
    end
    return { tostring(v) }
end

local function collect(ordered, opts)
    opts = opts or {}
    ordered = ordered or {}
    local projects = opts.projects or {}
    local f = {
        prefixes = {}, includes = {}, libdirs = {}, binaries = {},
        defines = {}, libs = {}, link_flags = {}, pkgconfig_dirs = {},
        dependencies = {}, projects = {},
    }
    local function add(list, values)
        for _, v in ipairs(values or {}) do
            if v and v ~= "" then list[#list + 1] = tostring(v) end
        end
    end
    for _, m in ipairs(ordered) do
        add(f.prefixes, { m.prefix })
        add(f.includes, m.includes)
        add(f.libdirs, m.libdirs)
        add(f.binaries, m.binaries)
        add(f.defines, m.defines)
        add(f.link_flags, m.link_flags)
        add(f.pkgconfig_dirs, m.pkgconfig_dirs)
        f.dependencies[#f.dependencies + 1] = {
            name = m.name, version = m.version, key = m.key, prefix = m.prefix,
            includes = m.includes or {}, libdirs = m.libdirs or {},
            binaries = m.binaries or {}, libs = m.libs or {},
            defines = m.defines or {}, link_flags = m.link_flags or {},
        }
    end
    -- Static link order: dependents before their dependencies, preserving the
    -- declared library order inside each manifest.  Cross-project exports are
    -- higher-level than catalog ports, so they are collected first.
    for _, p in ipairs(projects) do
        add(f.prefixes, { p.prefix })
        add(f.includes, p.includes)
        add(f.libdirs, p.libdirs)
        add(f.binaries, p.binaries)
        add(f.defines, p.defines)
        add(f.link_flags, p.link_flags)
        add(f.pkgconfig_dirs, p.pkgconfig_dirs)
        f.projects[#f.projects + 1] = {
            name = p.name, path = p.path, prefix = p.prefix,
            includes = p.includes or {}, libdirs = p.libdirs or {},
            binaries = p.binaries or {}, libs = p.libs or {},
        }
    end
    for i = #projects, 1, -1 do add(f.libs, projects[i].libs) end
    for i = #ordered, 1, -1 do add(f.libs, ordered[i].libs) end
    add(f.prefixes, opts.extra_prefixes)
    add(f.pkgconfig_dirs, opts.extra_pkgconfig_dirs)
    for _, p in ipairs(util.uniq(f.prefixes)) do
        add(f.pkgconfig_dirs, {
            util.join(p, "lib", "pkgconfig"), util.join(p, "lib64", "pkgconfig"),
            util.join(p, "share", "pkgconfig"),
        })
    end
    for _, d in ipairs(util.uniq(f.libdirs)) do
        add(f.pkgconfig_dirs, { util.join(d, "pkgconfig") })
    end
    for k, v in pairs(f) do
        if k ~= "dependencies" and k ~= "projects" then f[k] = util.uniq(v) end
    end
    -- Raw flag arrays/strings go into machine-readable toolchain/native/GN
    -- files; shell wrappers quote the whole string once with shquote().
    f.include_args = flagStrings(f.includes, "-I")
    f.define_args = flagStrings(f.defines, "-D")
    f.libdir_args = flagStrings(f.libdirs, "-L")
    f.lib_args = util.map(util.uniq(f.libs), libFlag)
    f.link_args = util.concat(f.libdir_args, flagStrings(f.link_flags, ""), f.lib_args)
    f.cflags = util.concat(f.include_args, f.define_args)
    f.cppflags = table.concat(f.cflags, " ")
    f.ldflags = table.concat(util.concat(f.libdir_args, flagStrings(f.link_flags, "")), " ")
    f.ldlibs = table.concat(f.lib_args, " ")
    return f
end

-- GNU make assignments are NOT shell commands: quoting a whole flag string
-- here would pass literal quotes to cc/ld.  Keep values raw so a project can
-- do `CPPFLAGS += $(GCPKG_CPPFLAGS)`; recipes still quote paths themselves.
local function makeValue(s)
    return (tostring(s or ""):gsub("\\", "\\\\"):gsub("#", "\\#"):gsub("%$", "$$"))
end

local function makeFlagsFile(path, f, files)
    local lines = {
        "# Generated by gcpkg -- include from a Makefile with `-include`.",
        "GCPKG_ROOT := " .. makeValue(files.root),
        "GCPKG_INJECT_DIR := " .. makeValue(files.dir),
        "GCPKG_TARGET_TRIPLET := " .. makeValue(files.triplet),
        "GCPKG_INSTALL_PREFIX := " .. makeValue(files.install_prefix),
        "GCPKG_CMAKE_PREFIX_PATH := " .. makeValue(semicolon(f.prefixes)),
        "GCPKG_PKG_CONFIG_PATH := " .. makeValue(colon(f.pkgconfig_dirs)),
        "GCPKG_INCLUDE_PATH := " .. makeValue(colon(f.includes)),
        "GCPKG_LIBRARY_PATH := " .. makeValue(colon(f.libdirs)),
        "GCPKG_CPPFLAGS := " .. makeValue(f.cppflags),
        "GCPKG_CFLAGS := " .. makeValue(f.cppflags),
        "GCPKG_CXXFLAGS := " .. makeValue(f.cppflags),
        "GCPKG_LDFLAGS := " .. makeValue(f.ldflags),
        "GCPKG_LDLIBS := " .. makeValue(f.ldlibs),
        "GCPKG_TOOLCHAIN_FILE := " .. makeValue(files.toolchain),
        "GCPKG_CMAKE_CACHE_FILE := " .. makeValue(files.cache),
        "GCPKG_MESON_NATIVE_FILE := " .. makeValue(files.meson),
        "GCPKG_GN_GNI := " .. makeValue(files.gn_gni),
        "GCPKG_CONAN_JSON := " .. makeValue(files.conan),
        "GCPKG_CANON_JSON := " .. makeValue(files.canon),
    }
    fs.write(path, table.concat(lines, "\n") .. "\n")
end

local function makeToolchain(path, f, files, opts)
    local crossFlags = toolchain.is_cross() and table.concat(toolchain.flags(), " ") or ""
    local initCFlags = util.trim(f.cppflags .. " " .. crossFlags)
    local initLDFlags = util.trim(f.ldflags .. " " .. crossFlags)
    local out = {
        "# Generated by gcpkg -- vcpkg-style toolchain injection.",
        "# The project source is untouched; pass this file as CMAKE_TOOLCHAIN_FILE,",
        "# or use gcpkg-cache.cmake / gcpkg-cmake.sh to inject it with `cmake -C`.",
        "set(GCPKG_ROOT \"" .. cmakeQuote(files.root) .. "\")",
        "set(GCPKG_INJECT_DIR \"" .. cmakeQuote(files.dir) .. "\")",
        "set(GCPKG_TARGET_TRIPLET \"" .. cmakeQuote(files.triplet) .. "\")",
        "set(GCPKG_INSTALLED_DIR \"" .. cmakeQuote(files.dir) .. "\")",
        "set(GCPKG_INSTALL_PREFIX \"" .. cmakeQuote(files.install_prefix) .. "\")",
        "set(GCPKG_DEPS_JSON \"" .. cmakeQuote(files.deps) .. "\")",
        "set(GCPKG_CONAN_JSON \"" .. cmakeQuote(files.conan) .. "\")",
        "set(GCPKG_CANON_JSON \"" .. cmakeQuote(files.canon) .. "\")",
        "set(CONAN_DEPS_JSON \"" .. cmakeQuote(files.conan) .. "\")",
        "set(GCPKG_PREFIXES " .. cmakeArgs(f.prefixes) .. ")",
        "set(GCPKG_INCLUDE_DIRS " .. cmakeArgs(f.includes) .. ")",
        "set(GCPKG_LIBRARY_DIRS " .. cmakeArgs(f.libdirs) .. ")",
        "set(GCPKG_RUNTIME_DIRS " .. cmakeArgs(f.libdirs) .. ")",
        "set(GCPKG_DEFINITIONS " .. cmakeArgs(f.defines) .. ")",
        "set(GCPKG_LINK_LIBRARIES " .. cmakeArgs(f.libs) .. ")",
    }
    if #f.prefixes > 0 then
        out[#out + 1] = "list(INSERT CMAKE_PREFIX_PATH 0 " .. cmakeArgs(f.prefixes) .. ")"
        out[#out + 1] = "list(INSERT CMAKE_FIND_ROOT_PATH 0 " .. cmakeArgs(f.prefixes) .. ")"
    end
    out[#out + 1] = "set(CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)"
    out[#out + 1] = [[if(NOT DEFINED ENV{GCPKG_INJECT_DIR})]]
    out[#out + 1] = "  set(CMAKE_C_FLAGS_INIT \"" .. cmakeQuote(initCFlags) .. "\")"
    out[#out + 1] = "  set(CMAKE_CXX_FLAGS_INIT \"" .. cmakeQuote(initCFlags) .. "\")"
    out[#out + 1] = "  set(CMAKE_EXE_LINKER_FLAGS_INIT \"" .. cmakeQuote(initLDFlags) .. "\")"
    out[#out + 1] = "endif()"
    -- Libraries must be AFTER object files for static linking.  CMake's
    -- STANDARD_LIBRARIES variables are emitted at the end of the link line;
    -- putting -l... into EXE_LINKER_FLAGS would ask the linker to resolve them
    -- before it has seen any undefined symbols.
    out[#out + 1] = "set(CMAKE_C_STANDARD_LIBRARIES_INIT \"" .. cmakeQuote(f.ldlibs) .. "\")"
    out[#out + 1] = "set(CMAKE_CXX_STANDARD_LIBRARIES_INIT \"" .. cmakeQuote(f.ldlibs) .. "\")"
    out[#out + 1] = "set(CMAKE_C_STANDARD_LIBRARIES \"" .. cmakeQuote(f.ldlibs) .. "\" CACHE STRING \"gcpkg libraries\" FORCE)"
    out[#out + 1] = "set(CMAKE_CXX_STANDARD_LIBRARIES \"" .. cmakeQuote(f.ldlibs) .. "\" CACHE STRING \"gcpkg libraries\" FORCE)"
    out[#out + 1] = "set(ENV{PKG_CONFIG_PATH} \"" .. cmakeQuote(colon(f.pkgconfig_dirs)) .. "\")"
    out[#out + 1] = "set(ENV{CPPFLAGS} \"" .. cmakeQuote(initCFlags) .. "\")"
    out[#out + 1] = "set(ENV{LDFLAGS} \"" .. cmakeQuote(initLDFlags) .. "\")"
    out[#out + 1] = "set(ENV{GCPKG_DEPS_JSON} \"" .. cmakeQuote(files.deps) .. "\")"
    out[#out + 1] = "set(ENV{CANON_DEPS_JSON} \"" .. cmakeQuote(files.canon) .. "\")"
    out[#out + 1] = "set(ENV{CONAN_DEPS_JSON} \"" .. cmakeQuote(files.conan) .. "\")"
    if toolchain.is_cross() then
        -- Keep the injection flags already written above. The standalone cross
        -- toolchain may clobber CMAKE_*_FLAGS_INIT and CMAKE_FIND_ROOT_PATH;
        -- here they must be combined with dependency include/lib prefixes.
        local ok, lines = pcall(toolchain.cmake_lines,
                                { compiler_from_env = true })
        if ok then
            for _, line in ipairs(lines) do
                if line:match("^set%(CMAKE_C_FLAGS_INIT ") or
                   line:match("^set%(CMAKE_CXX_FLAGS_INIT ") or
                   line:match("^set%(CMAKE_EXE_LINKER_FLAGS_INIT ") then
                    -- initCFlags / initLDFlags above already include cross flags.
                elseif line:match("^set%(CMAKE_FIND_ROOT_PATH ") then
                    local sysroot = toolchain.sysroot()
                    if sysroot then
                        out[#out + 1] =
                            "list(APPEND CMAKE_FIND_ROOT_PATH \"" ..
                            cmakeQuote(sysroot) .. "\")"
                    end
                else
                    out[#out + 1] = line
                end
            end
        end
    end
    out[#out + 1] = [[if(DEFINED GCPKG_CHAINLOAD_TOOLCHAIN_FILE AND EXISTS "${GCPKG_CHAINLOAD_TOOLCHAIN_FILE}")]]
    out[#out + 1] = [[  include("${GCPKG_CHAINLOAD_TOOLCHAIN_FILE}")]]
    out[#out + 1] = [[elseif(DEFINED ENV{GCPKG_CHAINLOAD_TOOLCHAIN_FILE} AND EXISTS "$ENV{GCPKG_CHAINLOAD_TOOLCHAIN_FILE}")]]
    out[#out + 1] = [[  include("$ENV{GCPKG_CHAINLOAD_TOOLCHAIN_FILE}")]]
    out[#out + 1] = "endif()"
    fs.write(path, table.concat(out, "\n") .. "\n")
end

local function makeCache(path, f, files)
    local out = {
        "# Generated by gcpkg -- inject with `cmake -C gcpkg-cache.cmake`.",
        [[if(DEFINED CMAKE_TOOLCHAIN_FILE AND NOT CMAKE_TOOLCHAIN_FILE STREQUAL "]] .. cmakeQuote(files.toolchain) .. [[")]],
        [[  set(GCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_TOOLCHAIN_FILE}" CACHE FILEPATH "user toolchain" FORCE)]],
        "endif()",
        "set(CMAKE_TOOLCHAIN_FILE \"" .. cmakeQuote(files.toolchain) .. "\" CACHE FILEPATH \"gcpkg injection\" FORCE)",
        "set(CMAKE_PREFIX_PATH \"" .. cmakeQuote(semicolon(f.prefixes)) .. "\" CACHE STRING \"gcpkg prefixes\" FORCE)",
        "set(CMAKE_FIND_ROOT_PATH \"" .. cmakeQuote(semicolon(f.prefixes)) .. "\" CACHE STRING \"gcpkg roots\" FORCE)",
        "set(CMAKE_INSTALL_PREFIX \"" .. cmakeQuote(files.install_prefix) .. "\" CACHE PATH \"gcpkg prefix\" FORCE)",
        "set(CMAKE_EXPORT_COMPILE_COMMANDS ON CACHE BOOL \"gcpkg compdb\" FORCE)",
        "set(GCPKG_ROOT \"" .. cmakeQuote(files.root) .. "\" CACHE PATH \"gcpkg root\")",
        "set(GCPKG_DEPS_JSON \"" .. cmakeQuote(files.deps) .. "\" CACHE FILEPATH \"gcpkg deps\")",
    }
    fs.write(path, table.concat(out, "\n") .. "\n")
end

local function makeMeson(path, f, files)
    local cross = toolchain.is_cross() and toolchain.flags() or {}
    local cflags = util.concat(f.cflags, cross)
    local linkArgs = util.concat(f.link_args, cross)
    local out = {
        "# Generated by gcpkg -- Meson native file.",
        "[built-in options]",
        "c_args = " .. mesonList(cflags),
        "cpp_args = " .. mesonList(cflags),
        "c_link_args = " .. mesonList(linkArgs),
        "cpp_link_args = " .. mesonList(linkArgs),
        "pkg_config_path = " .. mesonList(f.pkgconfig_dirs),
        "cmake_prefix_path = " .. mesonList(f.prefixes),
        "prefix = " .. mesonQuote(files.install_prefix),
    }
    fs.write(path, table.concat(out, "\n") .. "\n")
end

local function makeCrossMeson(path)
    if toolchain.is_cross() then
        toolchain.meson_file(path)
    else
        fs.write(path, "# Generated by gcpkg -- no cross build selected.\n")
    end
end

local function makeGni(path, f, files, assignments)
    local out = {
        "# Generated by gcpkg -- optional GN import, never written into the source tree.",
        "# A GN project may `import(\"//path/to/gcpkg-gn.gni\")` and use these lists.",
    }
    local function line(name, value)
        out[#out + 1] = name .. " = " .. value
    end
    line("gcpkg_root", json.encode(files.root))
    line("gcpkg_inject_dir", json.encode(files.dir))
    line("gcpkg_target_triplet", json.encode(files.triplet))
    line("gcpkg_install_prefix", json.encode(files.install_prefix))
    line("gcpkg_deps_json", json.encode(files.deps))
    line("gcpkg_conan_json", json.encode(files.conan))
    line("gcpkg_canon_json", json.encode(files.canon))
    line("gcpkg_prefixes", jsonList(f.prefixes))
    line("gcpkg_include_dirs", jsonList(f.includes))
    line("gcpkg_lib_dirs", jsonList(f.libdirs))
    line("gcpkg_bin_dirs", jsonList(f.binaries))
    line("gcpkg_defines", jsonList(f.defines))
    line("gcpkg_libs", jsonList(f.libs))
    line("gcpkg_cflags", jsonList(f.cflags))
    line("gcpkg_cflags_c", jsonList(f.cflags))
    line("gcpkg_cflags_cc", jsonList(f.cflags))
    line("gcpkg_ldflags", jsonList(f.link_args))
    line("gcpkg_pkg_config_path", json.encode(colon(f.pkgconfig_dirs)))
    if assignments then
        out[#out + 1] = ""
        out[#out + 1] = "# Build args for projects that declare gcpkg_* args:"
        for _, a in ipairs(assignments) do out[#out + 1] = a end
    end
    fs.write(path, table.concat(out, "\n") .. "\n")
end

local function gnAssignments(f, files)
    local function line(name, value) return name .. " = " .. value end
    return {
        line("gcpkg_root", json.encode(files.root)),
        line("gcpkg_inject_dir", json.encode(files.dir)),
        line("gcpkg_target_triplet", json.encode(files.triplet)),
        line("gcpkg_install_prefix", json.encode(files.install_prefix)),
        line("gcpkg_deps_json", json.encode(files.deps)),
        line("gcpkg_conan_json", json.encode(files.conan)),
        line("gcpkg_canon_json", json.encode(files.canon)),
        line("gcpkg_prefixes", jsonList(f.prefixes)),
        line("gcpkg_include_dirs", jsonList(f.includes)),
        line("gcpkg_lib_dirs", jsonList(f.libdirs)),
        line("gcpkg_bin_dirs", jsonList(f.binaries)),
        line("gcpkg_defines", jsonList(f.defines)),
        line("gcpkg_libs", jsonList(f.libs)),
        line("gcpkg_cflags", jsonList(f.cflags)),
        line("gcpkg_cflags_c", jsonList(f.cflags)),
        line("gcpkg_cflags_cc", jsonList(f.cflags)),
        line("gcpkg_ldflags", jsonList(f.link_args)),
        line("gcpkg_pkg_config_path", json.encode(colon(f.pkgconfig_dirs))),
    }
end

local function makeEnv(path, f, files, env)
    local out = {
        "#!/bin/sh",
        "# Generated by gcpkg. Source this file to enter the injected environment.",
        "# CC/CXX are deliberately NOT overridden: gcpkg-intercept stays active.",
        "export GCPKG_ROOT=" .. shquote(files.root),
        "export GCPKG_PROJECT_DIR=" .. shquote(files.project_dir),
        "export GCPKG_PROJECT_NAME=" .. shquote(files.project_name),
        "export GCPKG_INJECT_DIR=" .. shquote(files.dir),
        "export GCPKG_BUILD_DIR=" .. shquote(files.build_dir),
        "export GCPKG_INSTALL_PREFIX=" .. shquote(files.install_prefix),
        "export GCPKG_TARGET_TRIPLET=" .. shquote(files.triplet),
        "export GCPKG_DEPS_JSON=" .. shquote(files.deps),
        "export GCPKG_CONAN_JSON=" .. shquote(files.conan),
        "export GCPKG_CANON_JSON=" .. shquote(files.canon),
        "export GCPKG_ENV_FILE=" .. shquote(files.env),
        "export GCPKG_PKGCONFIG_DIR=" .. shquote(files.pkgconfig),
        "export GCPKG_COMPILE_COMMANDS=" .. shquote(files.compdb),
        "export GCPKG_CMAKE_TOOLCHAIN_FILE=" .. shquote(files.toolchain),
        "export GCPKG_CMAKE_CACHE_FILE=" .. shquote(files.cache),
        "export GCPKG_MESON_NATIVE_FILE=" .. shquote(files.meson),
        "export GCPKG_MESON_CROSS_FILE=" .. shquote(files.cross_meson),
        "export GCPKG_CMAKE_CROSS_FILE=" .. shquote(env.GCPKG_CMAKE_CROSS_FILE or ""),
        "export GCPKG_TARGET_TRIPLE=" .. shquote(env.GCPKG_TARGET_TRIPLE or files.triplet),
        "export GCPKG_CROSS_PREFIX=" .. shquote(env.GCPKG_CROSS_PREFIX or ""),
        "export GCPKG_SYSROOT=" .. shquote(env.GCPKG_SYSROOT or ""),
        "export GCPKG_COMPILER_FLAGS=" .. shquote(env.GCPKG_COMPILER_FLAGS or ""),
        "export GCPKG_LLVM_HOME=" .. shquote(env.GCPKG_LLVM_HOME or ""),
        "export GCPKG_GN_GNI=" .. shquote(files.gn_gni),
        "export GCPKG_GN_ARGS_FILE=" .. shquote(files.gn_args),
        "export GCPKG_MAKE_FLAGS_FILE=" .. shquote(files.make_flags),
        "export GCPKG_PREFIX_PATH=" .. shquote(colon(f.prefixes)),
        "export GCPKG_CMAKE_PREFIX_PATH=" .. shquote(semicolon(f.prefixes)),
        "export GCPKG_INCLUDE_PATH=" .. shquote(colon(f.includes)),
        "export GCPKG_LIBRARY_PATH=" .. shquote(colon(f.libdirs)),
        "export GCPKG_BINARY_PATH=" .. shquote(colon(f.binaries)),
        "export GCPKG_PKG_CONFIG_PATH=" .. shquote(colon(f.pkgconfig_dirs)),
        "export GCPKG_CPPFLAGS=" .. shquote(f.cppflags),
        "export GCPKG_CFLAGS=" .. shquote(f.cppflags),
        "export GCPKG_CXXFLAGS=" .. shquote(f.cppflags),
        "export GCPKG_LDFLAGS=" .. shquote(f.ldflags),
        "export GCPKG_LDLIBS=" .. shquote(f.ldlibs),
        "export GCPKG_LINK_LIBRARIES=" .. shquote(table.concat(f.lib_args, " ")),
    }
    for _, p in ipairs(f.projects) do
        out[#out + 1] = "export GCPKG_PROJECT_PREFIX_" .. envName(p.name) .. "=" .. shquote(p.prefix or "")
        out[#out + 1] = "export CANON_PROJECT_PREFIX_" .. envName(p.name) .. "=" .. shquote(p.prefix or "")
    end
    for _, d in ipairs(f.dependencies) do
        out[#out + 1] = "export GCPKG_DEP_PREFIX_" .. envName(d.name) .. "=" .. shquote(d.prefix or "")
    end
    out[#out + 1] = "export CPPFLAGS=\"${CPPFLAGS:-} ${GCPKG_CPPFLAGS} ${GCPKG_COMPILER_FLAGS}\""
    out[#out + 1] = "export CFLAGS=\"${CFLAGS:-} ${GCPKG_CFLAGS} ${GCPKG_COMPILER_FLAGS}\""
    out[#out + 1] = "export CXXFLAGS=\"${CXXFLAGS:-} ${GCPKG_CXXFLAGS} ${GCPKG_COMPILER_FLAGS}\""
    out[#out + 1] = "export LDFLAGS=\"${LDFLAGS:-} ${GCPKG_LDFLAGS} ${GCPKG_COMPILER_FLAGS}\""
    out[#out + 1] = "export LDLIBS=\"${LDLIBS:-} ${GCPKG_LDLIBS}\""
    out[#out + 1] = "export CPATH=" .. shquote(colon(f.includes)) .. "${CPATH:+:$CPATH}"
    out[#out + 1] = "export C_INCLUDE_PATH=" .. shquote(colon(f.includes)) .. "${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
    out[#out + 1] = "export CPLUS_INCLUDE_PATH=" .. shquote(colon(f.includes)) .. "${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
    out[#out + 1] = "export LIBRARY_PATH=" .. shquote(colon(f.libdirs)) .. "${LIBRARY_PATH:+:$LIBRARY_PATH}"
    out[#out + 1] = "export LD_LIBRARY_PATH=" .. shquote(colon(f.libdirs)) .. "${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    out[#out + 1] = "export PKG_CONFIG_PATH=" .. shquote(colon(f.pkgconfig_dirs)) .. "${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    out[#out + 1] = "export ACLOCAL_PATH=" .. shquote(colon(util.map(f.prefixes, function(p) return util.join(p, "share", "aclocal") end))) .. "${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
    out[#out + 1] = "export CMAKE_PREFIX_PATH=" .. shquote(semicolon(f.prefixes)) .. "${CMAKE_PREFIX_PATH:+;$CMAKE_PREFIX_PATH}"
    out[#out + 1] = "export CMAKE_FIND_ROOT_PATH=" .. shquote(semicolon(f.prefixes)) .. "${CMAKE_FIND_ROOT_PATH:+;$CMAKE_FIND_ROOT_PATH}"
    out[#out + 1] = "export CMAKE_INSTALL_PREFIX=" .. shquote(files.install_prefix)
    out[#out + 1] = "export CMAKE_EXPORT_COMPILE_COMMANDS=ON"
    if env.CMAKE_POLICY_VERSION_MINIMUM then
        out[#out + 1] = "export CMAKE_POLICY_VERSION_MINIMUM=" ..
                        shquote(env.CMAKE_POLICY_VERSION_MINIMUM)
    end
    local bins = colon(f.binaries)
    if bins ~= "" then
        out[#out + 1] = "export PATH=" .. shquote(bins) .. "${PATH:+:$PATH}"
    end
    out[#out + 1] = "if [ -n \"${CMAKE_TOOLCHAIN_FILE:-}\" ] && [ \"${CMAKE_TOOLCHAIN_FILE}\" != " .. shquote(files.toolchain) .. " ]; then"
    out[#out + 1] = "  export GCPKG_CHAINLOAD_TOOLCHAIN_FILE=\"${CMAKE_TOOLCHAIN_FILE}\""
    out[#out + 1] = "fi"
    out[#out + 1] = "export CMAKE_TOOLCHAIN_FILE=" .. shquote(files.toolchain)
    out[#out + 1] = "export MESON_NATIVE_FILE=" .. shquote(files.meson)
    out[#out + 1] = "export MESON_CROSS_FILE=" .. shquote(files.cross_meson)
    out[#out + 1] = "export GN_GNI_FILE=" .. shquote(files.gn_gni)
    out[#out + 1] = "export MAKE_FLAGS_FILE=" .. shquote(files.make_flags)
    out[#out + 1] = "export GCPKG_COMPILE_COMMANDS=" .. shquote(files.compdb)
    out[#out + 1] = "# Conan is the supported inner package manager; `canon` is a compatibility alias."
    out[#out + 1] = "export CANON_ROOT=" .. shquote(files.root)
    out[#out + 1] = "export CANON_PROJECT_DIR=" .. shquote(files.project_dir)
    out[#out + 1] = "export CANON_INJECT_DIR=" .. shquote(files.dir)
    out[#out + 1] = "export CANON_DEPS_JSON=" .. shquote(files.canon)
    out[#out + 1] = "export CANON_ENV_FILE=" .. shquote(files.canon_env)
    out[#out + 1] = "export CANON_TOOLCHAIN_FILE=" .. shquote(files.toolchain)
    out[#out + 1] = "export CANON_CMAKE_TOOLCHAIN_FILE=" .. shquote(files.toolchain)
    out[#out + 1] = "export CANON_CMAKE_CACHE_FILE=" .. shquote(files.cache)
    out[#out + 1] = "export CANON_MESON_NATIVE_FILE=" .. shquote(files.meson)
    out[#out + 1] = "export CANON_MESON_CROSS_FILE=" .. shquote(files.cross_meson)
    out[#out + 1] = "export CANON_CMAKE_CROSS_FILE=" .. shquote(env.GCPKG_CMAKE_CROSS_FILE or "")
    out[#out + 1] = "export CANON_TARGET_TRIPLET=" .. shquote(env.GCPKG_TARGET_TRIPLET or files.triplet)
    out[#out + 1] = "export CANON_TARGET_TRIPLE=" .. shquote(env.GCPKG_TARGET_TRIPLE or files.triplet)
    out[#out + 1] = "export CANON_CROSS_PREFIX=" .. shquote(env.GCPKG_CROSS_PREFIX or "")
    out[#out + 1] = "export CANON_SYSROOT=" .. shquote(env.GCPKG_SYSROOT or "")
    out[#out + 1] = "export CANON_COMPILER_FLAGS=" .. shquote(env.GCPKG_COMPILER_FLAGS or "")
    out[#out + 1] = "export CANON_LLVM_HOME=" .. shquote(env.GCPKG_LLVM_HOME or "")
    out[#out + 1] = "export CANON_GN_GNI=" .. shquote(files.gn_gni)
    out[#out + 1] = "export CANON_GN_ARGS_FILE=" .. shquote(files.gn_args)
    out[#out + 1] = "export CANON_MAKE_FLAGS_FILE=" .. shquote(files.make_flags)
    out[#out + 1] = "export CANON_PKG_CONFIG_PATH=" .. shquote(colon(f.pkgconfig_dirs))
    out[#out + 1] = "export CANON_PREFIX_PATH=" .. shquote(colon(f.prefixes))
    out[#out + 1] = "export CANON_CMAKE_PREFIX_PATH=" .. shquote(semicolon(f.prefixes))
    out[#out + 1] = "export CANON_INCLUDE_PATH=" .. shquote(colon(f.includes))
    out[#out + 1] = "export CANON_LIBRARY_PATH=" .. shquote(colon(f.libdirs))
    out[#out + 1] = "export CANON_BINARY_PATH=" .. shquote(colon(f.binaries))
    out[#out + 1] = "export CANON_COMPILE_COMMANDS=" .. shquote(files.compdb)
    out[#out + 1] = "export CANON_INSTALL_PREFIX=" .. shquote(files.install_prefix)
    out[#out + 1] = "export CANON_CPPFLAGS=\"${CPPFLAGS}\""
    out[#out + 1] = "export CANON_CFLAGS=\"${CFLAGS}\""
    out[#out + 1] = "export CANON_CXXFLAGS=\"${CXXFLAGS}\""
    out[#out + 1] = "export CANON_LDFLAGS=\"${LDFLAGS}\""
    out[#out + 1] = "export CANON_LDLIBS=\"${LDLIBS}\""
    out[#out + 1] = "export CANON_LINK_LIBRARIES=" .. shquote(table.concat(f.lib_args, " "))
    local conanKeys = {
        "ROOT", "PROJECT_DIR", "INJECT_DIR", "TOOLCHAIN_FILE",
        "CMAKE_TOOLCHAIN_FILE", "CMAKE_CACHE_FILE", "MESON_NATIVE_FILE",
        "MESON_CROSS_FILE", "CMAKE_CROSS_FILE", "TARGET_TRIPLET",
        "TARGET_TRIPLE", "CROSS_PREFIX", "SYSROOT", "COMPILER_FLAGS",
        "LLVM_HOME", "GN_GNI", "GN_ARGS_FILE", "MAKE_FLAGS_FILE",
        "PKG_CONFIG_PATH", "PREFIX_PATH", "CMAKE_PREFIX_PATH",
        "INCLUDE_PATH", "LIBRARY_PATH", "BINARY_PATH", "COMPILE_COMMANDS",
        "INSTALL_PREFIX", "CPPFLAGS", "CFLAGS", "CXXFLAGS", "LDFLAGS",
        "LDLIBS", "LINK_LIBRARIES",
    }
    for _, key in ipairs(conanKeys) do
        out[#out + 1] = "export CONAN_" .. key .. "=\"${CANON_" .. key .. "}\""
    end
    out[#out + 1] = "export CONAN_DEPS_JSON=" .. shquote(files.conan)
    out[#out + 1] = "export CONAN_ENV_FILE=" .. shquote(files.conan_env)
    out[#out + 1] = "export CONAN_CANON_JSON=" .. shquote(files.canon)
    out[#out + 1] = ": \"${CONAN_CMD:=conan}\""
    out[#out + 1] = "export CONAN_CMD"
    out[#out + 1] = ": \"${CANON_CMD:=${CONAN_CMD}}\""
    out[#out + 1] = "export CANON_CMD"
    fs.write(path, table.concat(out, "\n") .. "\n")
end

local function makeWrapper(path, body)
    fs.write(path, "#!/bin/sh\n# Generated by gcpkg -- dependency injection wrapper.\n" .. body)
end

local function chmod(paths)
    local cmd = { "chmod", "+x" }
    for _, p in ipairs(paths) do cmd[#cmd + 1] = p end
    gcpkg.exec(cmd, { quiet = true, check = false })
end

local function environment(f, files, ordered)
    local base = port.dependency_env(ordered) or {}
    local env = {}
    local function set(name, value)
        if value ~= nil then env[name] = tostring(value) end
    end
    set("GCPKG_ROOT", files.root)
    set("GCPKG_PROJECT_DIR", files.project_dir)
    set("GCPKG_PROJECT_NAME", files.project_name)
    set("GCPKG_INJECT_DIR", files.dir)
    set("GCPKG_BUILD_DIR", files.build_dir)
    set("GCPKG_INSTALL_PREFIX", files.install_prefix)
    set("GCPKG_TARGET_TRIPLET", files.triplet)
    set("GCPKG_DEPS_JSON", files.deps)
    set("GCPKG_CONAN_JSON", files.conan)
    set("GCPKG_CANON_JSON", files.canon)
    set("GCPKG_ENV_FILE", files.env)
    set("GCPKG_CONAN_ENV_FILE", files.conan_env)
    set("GCPKG_CANON_ENV_FILE", files.canon_env)
    set("GCPKG_PKGCONFIG_DIR", files.pkgconfig)
    set("GCPKG_COMPILE_COMMANDS", files.compdb)
    set("GCPKG_CMAKE_TOOLCHAIN_FILE", files.toolchain)
    set("GCPKG_CMAKE_CACHE_FILE", files.cache)
    set("GCPKG_MESON_NATIVE_FILE", files.meson)
    set("GCPKG_GN_GNI", files.gn_gni)
    set("GCPKG_GN_ARGS_FILE", files.gn_args)
    set("GCPKG_MAKE_FLAGS_FILE", files.make_flags)
    set("GCPKG_PREFIX_PATH", colon(f.prefixes))
    set("GCPKG_CMAKE_PREFIX_PATH", semicolon(f.prefixes))
    set("GCPKG_INCLUDE_PATH", colon(f.includes))
    set("GCPKG_LIBRARY_PATH", colon(f.libdirs))
    set("GCPKG_BINARY_PATH", colon(f.binaries))
    set("GCPKG_PKG_CONFIG_PATH", colon(f.pkgconfig_dirs))
    set("GCPKG_CPPFLAGS", f.cppflags)
    set("GCPKG_CFLAGS", f.cppflags)
    set("GCPKG_CXXFLAGS", f.cppflags)
    set("GCPKG_LDFLAGS", f.ldflags)
    set("GCPKG_LDLIBS", f.ldlibs)
    set("GCPKG_LINK_LIBRARIES", table.concat(f.lib_args, " "))
    for _, p in ipairs(f.projects) do
        set("GCPKG_PROJECT_PREFIX_" .. envName(p.name), p.prefix or "")
        set("CONAN_PROJECT_PREFIX_" .. envName(p.name), p.prefix or "")
        set("CANON_PROJECT_PREFIX_" .. envName(p.name), p.prefix or "")
    end
    for _, d in ipairs(f.dependencies) do
        set("GCPKG_DEP_PREFIX_" .. envName(d.name), d.prefix or "")
        set("CONAN_DEP_PREFIX_" .. envName(d.name), d.prefix or "")
    end
    set("CPPFLAGS", appendVar("CPPFLAGS", f.cppflags, " "))
    set("CFLAGS", appendVar("CFLAGS", f.cppflags, " "))
    set("CXXFLAGS", appendVar("CXXFLAGS", f.cppflags, " "))
    set("LDFLAGS", appendVar("LDFLAGS", f.ldflags, " "))
    set("LDLIBS", appendVar("LDLIBS", f.ldlibs, " "))
    set("CPATH", appendVar("CPATH", colon(f.includes), ":"))
    set("C_INCLUDE_PATH", appendVar("C_INCLUDE_PATH", colon(f.includes), ":"))
    set("CPLUS_INCLUDE_PATH", appendVar("CPLUS_INCLUDE_PATH", colon(f.includes), ":"))
    set("LIBRARY_PATH", appendVar("LIBRARY_PATH", colon(f.libdirs), ":"))
    set("LD_LIBRARY_PATH", appendVar("LD_LIBRARY_PATH", colon(f.libdirs), ":"))
    set("PKG_CONFIG_PATH", appendVar("PKG_CONFIG_PATH", colon(f.pkgconfig_dirs), ":"))
    set("ACLOCAL_PATH", appendVar("ACLOCAL_PATH", colon(util.map(f.prefixes, function(p) return util.join(p, "share", "aclocal") end)), ":"))
    set("CMAKE_PREFIX_PATH", appendVar("CMAKE_PREFIX_PATH", semicolon(f.prefixes), ";"))
    set("CMAKE_FIND_ROOT_PATH", appendVar("CMAKE_FIND_ROOT_PATH", semicolon(f.prefixes), ";"))
    set("CMAKE_INSTALL_PREFIX", files.install_prefix)
    set("CMAKE_EXPORT_COMPILE_COMMANDS", "ON")
    local policyBase = {
        CMAKE_POLICY_VERSION_MINIMUM = getenv("CMAKE_POLICY_VERSION_MINIMUM") ~= "" and
            getenv("CMAKE_POLICY_VERSION_MINIMUM") or base.CMAKE_POLICY_VERSION_MINIMUM,
    }
    for k, v in pairs(cmake_version.policy_env(policyBase)) do
        set(k, v)
    end
    set("CMAKE_TOOLCHAIN_FILE", files.toolchain)
    set("MESON_NATIVE_FILE", files.meson)
    set("GN_GNI_FILE", files.gn_gni)
    set("MAKE_FLAGS_FILE", files.make_flags)
    local prevPath = base.PATH or getenv("PATH")
    if colon(f.binaries) ~= "" then
        set("PATH", colon(f.binaries) .. (prevPath ~= "" and ":" .. prevPath or ""))
    elseif prevPath ~= "" then
        set("PATH", prevPath)
    end
    local chainload = getenv("CMAKE_TOOLCHAIN_FILE")
    if chainload ~= "" and chainload ~= files.toolchain then
        set("GCPKG_CHAINLOAD_TOOLCHAIN_FILE", chainload)
    end
    set("CANON_ROOT", files.root)
    set("CANON_PROJECT_DIR", files.project_dir)
    set("CANON_INJECT_DIR", files.dir)
    set("CANON_DEPS_JSON", files.canon)
    set("CANON_ENV_FILE", files.canon_env)
    set("CANON_TOOLCHAIN_FILE", files.toolchain)
    set("CANON_CMAKE_TOOLCHAIN_FILE", files.toolchain)
    set("CANON_CMAKE_CACHE_FILE", files.cache)
    set("CANON_MESON_NATIVE_FILE", files.meson)
    set("CANON_GN_GNI", files.gn_gni)
    set("CANON_GN_ARGS_FILE", files.gn_args)
    set("CANON_MAKE_FLAGS_FILE", files.make_flags)
    set("CANON_PKG_CONFIG_PATH", colon(f.pkgconfig_dirs))
    set("CANON_PREFIX_PATH", colon(f.prefixes))
    set("CANON_CMAKE_PREFIX_PATH", semicolon(f.prefixes))
    set("CANON_INCLUDE_PATH", colon(f.includes))
    set("CANON_LIBRARY_PATH", colon(f.libdirs))
    set("CANON_BINARY_PATH", colon(f.binaries))
    set("CANON_COMPILE_COMMANDS", files.compdb)
    set("CANON_INSTALL_PREFIX", files.install_prefix)
    set("CANON_CPPFLAGS", env.CPPFLAGS)
    set("CANON_CFLAGS", env.CFLAGS)
    set("CANON_CXXFLAGS", env.CXXFLAGS)
    set("CANON_LDFLAGS", env.LDFLAGS)
    set("CANON_LDLIBS", env.LDLIBS)
    set("CANON_LINK_LIBRARIES", table.concat(f.lib_args, " "))
    -- Cross flags, the selected LLVM root and the generated cross files belong
    -- to the injected environment as well. Put injection-specific paths back
    -- after toolchain.env() so wrappers keep using the .gcpkg/inject files.
    for k, v in pairs(toolchain.env(env)) do set(k, v) end
    set("GCPKG_MESON_CROSS_FILE", files.cross_meson)
    set("MESON_CROSS_FILE", files.cross_meson)
    set("GCPKG_TARGET_TRIPLET", env.GCPKG_TARGET_TRIPLET or files.triplet)
    set("GCPKG_TARGET_TRIPLE", env.GCPKG_TARGET_TRIPLE or files.triplet)
    set("GCPKG_CROSS_PREFIX", env.GCPKG_CROSS_PREFIX or "")
    set("GCPKG_SYSROOT", env.GCPKG_SYSROOT or "")
    set("GCPKG_COMPILER_FLAGS", env.GCPKG_COMPILER_FLAGS or "")
    set("GCPKG_LLVM_HOME", env.GCPKG_LLVM_HOME or "")
    set("CANON_CPPFLAGS", env.CPPFLAGS)
    set("CANON_CFLAGS", env.CFLAGS)
    set("CANON_CXXFLAGS", env.CXXFLAGS)
    set("CANON_LDFLAGS", env.LDFLAGS)
    set("CANON_TARGET_TRIPLET", env.GCPKG_TARGET_TRIPLET or files.triplet)
    set("CANON_TARGET_TRIPLE", env.GCPKG_TARGET_TRIPLE or files.triplet)
    set("CANON_MESON_CROSS_FILE", files.cross_meson)
    set("CANON_CMAKE_CROSS_FILE", env.GCPKG_CMAKE_CROSS_FILE or "")
    set("CANON_CROSS_PREFIX", env.GCPKG_CROSS_PREFIX or "")
    set("CANON_SYSROOT", env.GCPKG_SYSROOT or "")
    set("CANON_COMPILER_FLAGS", env.GCPKG_COMPILER_FLAGS or "")
    set("CANON_LLVM_HOME", env.GCPKG_LLVM_HOME or "")
    -- Keep every CANON_* value as a compatibility alias while CONAN_* is
    -- the first-class namespace.
    local aliases = {}
    for key, value in pairs(env) do
        if key:sub(1, 6) == "CANON_" then
            aliases[#aliases + 1] = { "CONAN_" .. key:sub(7), value }
        end
    end
    for _, alias in ipairs(aliases) do set(alias[1], alias[2]) end
    set("CONAN_DEPS_JSON", files.conan)
    set("CONAN_ENV_FILE", files.conan_env)
    set("CONAN_CANON_JSON", files.canon)
    local externalConan = getenv("CONAN_CMD")
    if externalConan ~= "" then set("CONAN_CMD", externalConan) end
    local externalCanon = getenv("CANON_CMD")
    if externalCanon ~= "" then set("CANON_CMD", externalCanon) end
    return env
end

local function linkPkgConfig(files, f)
    fs.mkdirs(files.pkgconfig)
    for _, dir in ipairs(f.pkgconfig_dirs) do
        if fs.isdir(dir) then
            for _, name in ipairs(fs.listdir(dir) or {}) do
                if util.endswith(name, ".pc") then
                    fs.symlink(util.join(dir, name), util.join(files.pkgconfig, name))
                end
            end
        end
    end
end

local function defaultFiles(opts, f)
    local dir = util.abs(opts.out_dir or util.join(opts.project_dir or fs.cwd(), ".gcpkg", "inject"))
    local projectDir = util.abs(opts.project_dir or fs.cwd())
    local workspaceRoot = util.abs(opts.workspace_root or projectDir)
    local buildDir = util.abs(opts.build_dir or util.join(workspaceRoot, ".gcpkg", "build", opts.project_name or "project"))
    local installPrefix = util.abs(opts.install_prefix or util.join(workspaceRoot, ".gcpkg", "prefix", opts.project_name or "project"))
    local files = {
        root = workspaceRoot, project_dir = projectDir,
        project_name = opts.project_name or util.basename(projectDir),
        dir = dir, build_dir = buildDir, install_prefix = installPrefix,
        triplet = toolchain.target_triplet(),
        deps = util.join(dir, "gcpkg-deps.json"),
        conan = util.join(dir, "gcpkg-conan.json"),
        canon = util.join(dir, "gcpkg-canon.json"),
        env = util.join(dir, "gcpkg-env.sh"),
        conan_env = util.join(dir, "gcpkg-conan-env.sh"),
        canon_env = util.join(dir, "gcpkg-canon-env.sh"),
        toolchain = util.join(dir, "gcpkg-toolchain.cmake"),
        cache = util.join(dir, "gcpkg-cache.cmake"),
        meson = util.join(dir, "gcpkg-meson.ini"),
        cross_meson = util.join(dir, "gcpkg-cross.ini"),
        gn_gni = util.join(dir, "gcpkg-gn.gni"),
        gn_args = util.join(dir, "gcpkg-gn-args.gn"),
        make_flags = util.join(dir, "gcpkg-flags.mk"),
        pkgconfig = util.join(dir, "pkgconfig"),
        cmake_wrapper = util.join(dir, "gcpkg-cmake.sh"),
        meson_wrapper = util.join(dir, "gcpkg-meson.sh"),
        gn_wrapper = util.join(dir, "gcpkg-gn.sh"),
        make_wrapper = util.join(dir, "gcpkg-make.sh"),
        conan_wrapper = util.join(dir, "gcpkg-conan.sh"),
        canon_wrapper = util.join(dir, "gcpkg-canon.sh"),
        compdb = util.abs(opts.compdb or util.join(buildDir, "compile_commands.json")),
    }
    return files
end

function M.generate(ordered, opts)
    opts = opts or {}
    ordered = ordered or {}
    local f = collect(ordered, opts)
    local files = defaultFiles(opts, f)
    fs.mkdirs(files.dir)
    fs.mkdirs(files.build_dir)
    fs.mkdirs(files.install_prefix)
    fs.mkdirs(util.dirname(files.compdb))
    linkPkgConfig(files, f)
    local env = environment(f, files, ordered)
    local metadata = {
        schema = 1, generator = "gcpkg", kind = "dependency-injection",
        root = files.root, inject_dir = files.dir,
        project_dir = files.project_dir, project_name = files.project_name,
        build_dir = files.build_dir, install_prefix = files.install_prefix,
        triplet = files.triplet, files = files,
        flags = {
            prefixes = f.prefixes, includes = f.includes, libdirs = f.libdirs,
            binaries = f.binaries, defines = f.defines, libs = f.libs,
            link_flags = f.link_flags, pkgconfig_dirs = f.pkgconfig_dirs,
            cflags = f.cflags, link_args = f.link_args,
            cppflags = f.cppflags, ldflags = f.ldflags, ldlibs = f.ldlibs,
        },
        dependencies = f.dependencies, projects = f.projects,
        systems = systems(opts.systems or opts.system) or { "auto" },
        inner_package_managers = { "conan", "canon" },
    }
    local conan = util.deepcopy(metadata)
    conan.inner_package_manager = "conan"
    conan.note = "Conan is an opaque inner package manager; gcpkg injects dependencies and does not rewrite conanfile.py/txt."
    conan.files = files
    conan.environment = env
    local canon = util.deepcopy(metadata)
    canon.inner_package_manager = "canon"
    canon.note = "canon is a compatibility alias for Conan; existing workspace.yaml files keep working."
    canon.files = files
    canon.environment = env
    fs.write(files.deps, json.encode(metadata, true) .. "\n")
    fs.write(files.conan, json.encode(conan, true) .. "\n")
    fs.write(files.canon, json.encode(canon, true) .. "\n")
    makeToolchain(files.toolchain, f, files, opts)
    makeCache(files.cache, f, files)
    makeMeson(files.meson, f, files)
    makeCrossMeson(files.cross_meson)
    -- gcpkg-env.sh exports GCPKG_CMAKE_CROSS_FILE; make sure the referenced
    -- generated toolchain exists even for `inject` / `inject --install`.
    if toolchain.is_cross() then
        toolchain.cmake_args({ compiler_from_env = true })
    end
    local assignments = gnAssignments(f, files)
    makeGni(files.gn_gni, f, files, assignments)
    fs.write(files.gn_args, table.concat(assignments, "\n") .. "\n")
    makeFlagsFile(files.make_flags, f, files)
    makeEnv(files.env, f, files, env)
    makeWrapper(files.conan_env, ". " .. shquote(files.env) .. "\n# CONAN_* variables are exported by gcpkg-env.sh.\n")
    makeWrapper(files.canon_env, ". " .. shquote(files.env) .. "\n# CANON_* is a compatibility alias for CONAN_*.\n")
    makeWrapper(files.cmake_wrapper,
        ". " .. shquote(files.env) .. "\nexec cmake -C " .. shquote(files.cache) .. " \"$@\"\n")
    local mesonCross = toolchain.is_cross() and
        (" --cross-file " .. shquote(files.cross_meson)) or ""
    makeWrapper(files.meson_wrapper,
        ". " .. shquote(files.env) .. "\nexec meson setup --native-file " .. shquote(files.meson) ..
        mesonCross .. " --prefix " .. shquote(files.install_prefix) .. " \"$@\"\n")
    makeWrapper(files.gn_wrapper,
        ". " .. shquote(files.env) .. "\nexec gn gen --export-compile-commands --root=" ..
        shquote(files.project_dir) .. " \"$@\"\n")
    local function shDefault(s)
        return tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
               :gsub("%$", "\\$"):gsub("`", "\\`")
    end
    local function compilerDefault(kind, fallback)
        local ok, value = pcall(toolchain.compiler, kind)
        return (ok and value and value ~= "" and value) or fallback
    end
    local ccDefault = shDefault(compilerDefault("cc", "clang"))
    local cxxDefault = shDefault(compilerDefault("cxx", "clang++"))
    makeWrapper(files.make_wrapper,
        ". " .. shquote(files.env) .. "\nexec make" ..
        " \"CC=${CC:-" .. ccDefault .. "}\" \"CXX=${CXX:-" .. cxxDefault .. "}\"" ..
        " \"CPPFLAGS=${CPPFLAGS}\" \"CFLAGS=${CFLAGS}\" \"CXXFLAGS=${CXXFLAGS}\"" ..
        " \"LDFLAGS=${LDFLAGS}\" \"LDLIBS=${LDLIBS}\"" ..
        " \"PREFIX=" .. files.install_prefix .. "\" \"$@\"\n")
    makeWrapper(files.conan_wrapper,
        ". " .. shquote(files.env) .. "\n: \"${CONAN_CMD:=conan}\"\nexec $CONAN_CMD \"$@\"\n")
    makeWrapper(files.canon_wrapper,
        ". " .. shquote(files.env) .. "\n: \"${CANON_CMD:=${CONAN_CMD:-conan}}\"\nexec $CANON_CMD \"$@\"\n")
    chmod({ files.env, files.conan_env, files.canon_env, files.cmake_wrapper,
            files.meson_wrapper, files.gn_wrapper, files.make_wrapper,
            files.conan_wrapper, files.canon_wrapper })
    return { dir = files.dir, files = files, env = env, flags = f,
             metadata = metadata, conan = conan, canon = canon, ordered = ordered }
end

M.from_manifests = M.generate

local function expandPath(p, base)
    p = tostring(p or "")
    if p == "" then return "" end
    if p:sub(1, 2) == "~/" then
        return util.join(gcpkg.sys.getenv("HOME") or "", p:sub(3))
    end
    if p:sub(1, 2) == "./" then return util.abs(p, base) end
    if util.isabs(p) then return util.abs(p) end
    return util.abs(p, base)
end

-- Top-level `gcpkg inject [DIR]`: resolve a project's gcpkg.lock into real
-- installed manifests, then write the injection directory.  With --install,
-- dependencies are installed first and gcpkg.lock is refreshed.
function M.from_lock(projectDir, cfg, opts)
    opts = opts or {}
    cfg = cfg or {}
    projectDir = util.abs(projectDir or fs.cwd())
    local y = workspace.read_yaml(util.join(projectDir, "gcpkg.yaml")) or {}
    local injectOpts = util.deepcopy(opts)
    injectOpts.project_dir = projectDir
    injectOpts.workspace_root = opts.workspace_root or projectDir
    injectOpts.project_name = opts.project_name or y.project or util.basename(projectDir)
    injectOpts.system = opts.system or y.system
    injectOpts.systems = systems(opts.systems or opts.system or y.systems or y.system)
    injectOpts.out_dir = opts.out or util.join(projectDir, ".gcpkg", "inject")
    injectOpts.build_dir = opts.build_dir or util.join(projectDir, ".gcpkg", "build")
    injectOpts.install_prefix = opts.install_prefix or util.join(projectDir, ".gcpkg", "install")
    if opts.install then
        local ordered = workspace.install_project(projectDir, cfg)
        return M.generate(ordered, injectOpts)
    end
    local lock = workspace.read_lock(projectDir)
    if not lock or not lock.resolved or #lock.resolved == 0 then
        error("no resolved dependencies in " .. workspace.lock_path(projectDir) ..
              "; run `gcpkg install` in the project first (or pass --install)")
    end
    local candidates = {}
    if cfg.store then candidates[#candidates + 1] = cfg.store end
    if lock.store then
        candidates[#candidates + 1] = storeMod.new(expandPath(lock.store, projectDir))
    end
    local problems = {}
    for _, st in ipairs(candidates) do
        local manifests, ok = {}, true
        for _, resolved in ipairs(lock.resolved) do
            local m = resolved.key and storeMod.read_manifest(st, tostring(resolved.key)) or nil
            if m then
                manifests[#manifests + 1] = m
            else
                ok = false
                problems[#problems + 1] = tostring(resolved.key or "?")
                break
            end
        end
        if ok then
            local ordered = port.transitive(manifests, st)
            return M.generate(ordered, injectOpts)
        end
    end
    error("cached manifests for " .. table.concat(problems, ", ") ..
          " not found in the active store; run `gcpkg install` with the same --store")
end

return M
