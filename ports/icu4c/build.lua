-- ICU4C 76.1 -- gcpkg source port.
-- All writes stay inside the store.  Platform/toolchain results come from the
-- ONE gcpkg triplet probe; ICU's generated configure is patched so it never
-- compiles, links or runs its own conftest programs.  Python needed for the
-- patch is a source-built port pulled in by features.yaml `requires:`.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local log = require("gcpkg.log")
local triplet = require("gcpkg.triplet")
local toolchain = require("gcpkg.toolchain")
local autotools = require("gcpkg.build.autotools")
local make = require("gcpkg.build.make")

local function first(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" then return v end
    end
    return ""
end

local function scalar(v)
    if type(v) == "boolean" then return v and "1" or "0" end
    local s = tostring(v or "")
    if s == "0" or s == "" then return "" end
    return s
end

local function yn(v)
    local s = scalar(v)
    if s == "" or s == "0" or s:lower() == "no" or s:lower() == "false" then
        return "no"
    end
    return "yes"
end

local function ackey(s)
    s = tostring(s):lower():gsub("%s*%*", "_p")
    return (s:gsub("[^a-z0-9]", "_"))
end

local function acname(s)
    return (tostring(s):gsub("[^A-Za-z0-9]", "_"))
end

local function shquote(v)
    local s = tostring(v):gsub("'", "'\"'\"'")
    return "'" .. s .. "'"
end

local function has(f, kind, name)
    local t = f[kind] or {}
    return yn(t[name]) == "yes"
end

local function add_path(ctx, key, path)
    local prev = ctx.env[key]
    if not prev or prev == "" then ctx.env[key] = path; return end
    for entry in prev:gmatch("[^:]+") do
        if entry == path then return end
    end
    ctx.env[key] = path .. ":" .. prev
end

local function make_cache(ctx, f)
    local tc = toolchain
    local host = tc.host_triple()
    local target = tc.target_triplet()
    local cross = tc.is_cross() and "yes" or "no"
    local compiler = ctx.compiler or {}
    local cc = first(ctx.env.CC, compiler.wrapper_cc, "cc")
    local cxx = first(ctx.env.CXX, compiler.wrapper_cxx, "c++")
    local cpp = first(ctx.env.CPP, cc .. " -E")
    local cxxcpp = first(ctx.env.CXXCPP, cxx .. " -E")
    local ar = first(ctx.env.AR, "ar")
    local ranlib = first(ctx.env.RANLIB, "ranlib")
    local install = first(ctx.env.INSTALL, "/usr/bin/install -c")
    local make = first(ctx.env.MAKE, "/usr/bin/make")
    local pkgconfig = first(ctx.env.PKG_CONFIG, "/usr/bin/pkg-config")
    local doxygen = first(ctx.env.DOXYGEN, "false")
    local python = first(ctx.env.PYTHON, "false")
    local exeext = (f.os == "windows") and ".exe" or ""
    local objext = (f.compiler_id == "msvc") and "obj" or "o"
    local default_exe = (f.os == "windows") and "a.exe" or "a.out"
    local gnu = (f.compiler_id == "clang" or f.compiler_id == "gcc") and "yes" or "no"
    local cstd = tonumber(f.c_standard) or 0
    local cxxstd = tonumber(f.cxx_standard) or 0

    ctx.env.CC = cc; ctx.env.CXX = cxx
    ctx.env.CPP = cpp; ctx.env.CXXCPP = cxxcpp
    ctx.env.AR = ar; ctx.env.RANLIB = ranlib
    ctx.env.INSTALL = install; ctx.env.MAKE = make
    ctx.env.PKG_CONFIG = pkgconfig; ctx.env.DOXYGEN = doxygen
    ctx.env.PYTHON = python
    ctx.env.GCPKG_C_STANDARD = scalar(cstd)
    ctx.env.GCPKG_CXX_STANDARD = scalar(cxxstd)
    ctx.env.GCPKG_COMPILER_ID = scalar(f.compiler_id)
    ctx.env.GCPKG_CROSS_COMPILING = cross
    ctx.env.GCPKG_DEFAULT_EXE = default_exe
    ctx.env.GCPKG_EXE_EXT = exeext
    ctx.env.GCPKG_OBJECT_EXT = objext

    local m = {}
    local function set(k, v) m[k] = tostring(v) end
    for h, v in pairs(f.headers or {}) do
        set("ac_cv_header_" .. ackey(h), yn(v))
    end
    for fn, v in pairs(f.functions or {}) do
        set("ac_cv_func_" .. ackey(fn), yn(v))
    end
    for t, v in pairs(f.sizes or {}) do
        if tonumber(v) then
            set("ac_cv_sizeof_" .. ackey(t), scalar(v))
            set("ac_cv_type_" .. ackey(t), "yes")
        end
    end
    for n, v in pairs(f.defined or {}) do
        local y = yn(v)
        set("ac_cv_defined_" .. acname(n), y)
        set("ac_cv_have_decl_" .. acname(n), y)
    end

    set("ac_cv_build", host); set("ac_cv_host", target)
    set("ac_cv_target", target)
    set("ac_cv_c_bigendian", (tostring(f.byte_order) == "big") and "yes" or "no")
    set("ac_cv_objext", objext); set("ac_cv_exeext", exeext)
    set("ac_cv_c_compiler_gnu", gnu); set("ac_cv_cxx_compiler_gnu", gnu)
    set("ac_cv_prog_CC", cc); set("ac_cv_prog_ac_ct_CC", cc)
    set("ac_cv_prog_CXX", cxx); set("ac_cv_prog_ac_ct_CXX", cxx)
    set("ac_cv_prog_CPP", cpp); set("ac_cv_prog_CXXCPP", cxxcpp)
    set("ac_cv_prog_AR", ar); set("ac_cv_prog_ac_ct_AR", ar)
    set("ac_cv_prog_RANLIB", ranlib)
    set("ac_cv_prog_ac_ct_RANLIB", ranlib)
    set("ac_cv_prog_PYTHON", python)
    set("ac_cv_path_install", install)
    set("ac_cv_path_SED", "/usr/bin/sed")
    set("ac_cv_path_U_MAKE", make)
    set("ac_cv_path_PKG_CONFIG", pkgconfig)
    set("ac_cv_path_ac_pt_PKG_CONFIG", pkgconfig)
    set("ac_cv_path_DOXYGEN", doxygen)
    set("ac_cv_prog_cc_g", "yes"); set("ac_cv_prog_cxx_g", "yes")
    set("ac_cv_prog_cc_c11", cstd >= 201112 and "" or "no")
    set("ac_cv_prog_cc_c89", ""); set("ac_cv_prog_cc_c99", "")
    set("ac_cv_prog_cc_stdc", "")
    set("ac_cv_prog_cxx_cxx11", cxxstd >= 201103 and "" or "no")
    set("ac_cv_prog_cxx_cxx98", ""); set("ac_cv_prog_cxx_stdcxx", "")
    set("ac_cv_func_mmap_ok",
        (has(f, "functions", "mmap") and has(f, "functions", "munmap") and
         has(f, "headers", "sys/mman.h")) and "yes" or "no")
    set("ac_cv_nl_langinfo_codeset",
        (has(f, "functions", "nl_langinfo") and has(f, "defined", "CODESET"))
        and "CODESET" or "unknown")
    set("ac_cv_override_cxx_allocation_ok", cxxstd >= 201103 and "yes" or "no")
    set("ac_cv_override_placement_new_ok", cxxstd >= 201103 and "yes" or "no")
    set("ac_cv_lib_m_floor", yn(f.functions and f.functions.floor))
    set("ac_cv_lib_pthread_pthread_attr_init",
        yn(f.functions and f.functions.pthread_attr_init))
    set("ac_cv_lib_pthread_pthread_mutex_init",
        yn(f.functions and f.functions.pthread_mutex_init))
    set("ac_cv_search_dlopen",
        has(f, "functions", "dlopen") and
        ((f.os == "linux") and "-ldl" or "none required") or "no")
    set("ac_cv_search_pthread_mutex_destroy",
        has(f, "functions", "pthread_mutex_destroy") and "none required" or "no")
    set("ac_cv_search_wcscpy",
        has(f, "functions", "wcscpy") and "none required" or "no")
    set("ac_cv_var_tzname", yn(f.functions and f.functions.tzname))
    set("ac_cv_var__tzname", yn(f.functions and f.functions._tzname))
    set("ac_cv_var_timezone", yn(f.functions and f.functions.timezone))
    set("ac_cv_var__timezone", yn(f.functions and f.functions._timezone))
    set("ac_cv_var___timezone", yn(f.functions and f.functions.__timezone))

    -- Any remaining named configure cache variable is explicitly set too:
    -- a library must never fall back to its own compile/link/run probe.
    local cfg = assert(fs.read(ctx.src .. "/configure"),
                       "gcpkg: cannot read ICU configure")
    for name in cfg:gmatch("ac_cv_[%w_]+") do
        if name:sub(1, 10) ~= "ac_cv_env_" and name ~= "ac_cv_header_" then
            if not m[name] then m[name] = "no" end
        end
    end
    local keys, lines = {}, {
        "# gcpkg shared-triplet facts for ICU4C 76.1.  No library-side probes.",
    }
    for k in pairs(m) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        lines[#lines + 1] = k .. "=${" .. k .. "=" .. shquote(m[k]) .. "}"
    end
    fs.write(ctx.src .. "/config.cache", table.concat(lines, "\n") .. "\n")
    return #keys
end

local function pick_lib(libdir, stem)
    local best, best_len = nil, -1
    for _, name in ipairs(fs.listdir(libdir) or {}) do
        local p = util.join(libdir, name)
        if fs.isfile(p) and name:match("^" .. stem .. "%.so%.") then
            if #name > best_len then best, best_len = p, #name end
        end
    end
    if best then return best, "SHARED" end
    local static = util.join(libdir, stem .. ".a")
    if fs.isfile(static) then return static, "STATIC" end
    return nil, nil
end

local function write_cmake_config(ctx)
    local libdir = ctx.prefix .. "/lib"
    local cmakedir = libdir .. "/cmake/ICU"
    fs.mkdirs(cmakedir)
    local libs, kinds = {}, {}
    for _, stem in ipairs({ "libicudata", "libicuuc", "libicui18n", "libicuio" }) do
        local p, kind = pick_lib(libdir, stem)
        assert(p, "gcpkg: ICU installed library missing: " .. stem)
        libs[stem] = p; kinds[stem] = kind
    end
    local function imported(target, stem, deps)
        local lines = {
            "if(NOT TARGET " .. target .. ")",
            "  add_library(" .. target .. " " .. kinds[stem] .. " IMPORTED)",
            "  set_target_properties(" .. target .. " PROPERTIES",
            '    IMPORTED_LOCATION "' .. libs[stem] .. '"',
            '    INTERFACE_INCLUDE_DIRECTORIES "' .. ctx.prefix .. '/include"',
        }
        if #deps > 0 then
            lines[#lines + 1] = '    INTERFACE_LINK_LIBRARIES "' .. table.concat(deps, ";") .. '"'
        end
        lines[#lines + 1] = "  )"
        lines[#lines + 1] = "endif()"
        return table.concat(lines, "\n")
    end
    local body = {
        "# gcpkg local ICU CONFIG: source-built ICU4C 76.1, no host discovery.",
        'set(ICU_FOUND TRUE)',
        'set(ICU_VERSION "76.1")',
        'set(ICU_VERSION_STRING "76.1")',
        'set(ICU_MAJOR_VERSION "76")',
        'set(ICU_MINOR_VERSION "1")',
        'set(ICU_INCLUDE_DIR "' .. ctx.prefix .. '/include")',
        'set(ICU_INCLUDE_DIRS "' .. ctx.prefix .. '/include")',
        'set(ICU_DATA_LIBRARY "' .. libs.libicudata .. '")',
        'set(ICU_UC_LIBRARY "' .. libs.libicuuc .. '")',
        'set(ICU_I18N_LIBRARY "' .. libs.libicui18n .. '")',
        'set(ICU_IO_LIBRARY "' .. libs.libicuio .. '")',
        'set(ICU_LIBRARIES "' .. libs.libicui18n .. ";" .. libs.libicuuc .. ";" ..
            libs.libicudata .. ";" .. libs.libicuio .. '")',
        'foreach(_icu_component ${ICU_FIND_COMPONENTS})',
        '  set(ICU_${_icu_component}_FOUND TRUE)',
        '  string(TOUPPER "${_icu_component}" _icu_upper)',
        '  set(ICU_${_icu_upper}_FOUND TRUE)',
        'endforeach()',
        'set(ICU_uc_FOUND TRUE)',
        'set(ICU_i18n_FOUND TRUE)',
        'set(ICU_data_FOUND TRUE)',
        'set(ICU_io_FOUND TRUE)',
        'set(ICU_UC_FOUND TRUE)',
        'set(ICU_I18N_FOUND TRUE)',
        'set(ICU_DATA_FOUND TRUE)',
        'set(ICU_IO_FOUND TRUE)',
        imported("ICU::data", "libicudata", {}),
        imported("ICU::uc", "libicuuc", { "ICU::data" }),
        imported("ICU::i18n", "libicui18n", { "ICU::uc", "ICU::data" }),
        imported("ICU::io", "libicuio", { "ICU::i18n", "ICU::uc", "ICU::data" }),
    }
    fs.write(cmakedir .. "/ICUConfig.cmake", table.concat(body, "\n") .. "\n")
    fs.write(cmakedir .. "/ICUConfigVersion.cmake", [==[
set(PACKAGE_VERSION "76.1")
if(PACKAGE_FIND_VERSION VERSION_LESS_EQUAL PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
]==])
end

local function restore_upstream_assets(ctx)
    -- With strip=2 the port source root is icu/source, so the tarball's
    -- top-level icu/testdata and icu/LICENSE sit one level above ctx.src.
    -- `make install` copies ../LICENSE, and intltest's MessageFormat2 JSON
    -- tests read ../testdata/message2. Restore those exact upstream files
    -- from the already-verified tarball, writing only inside the store.
    local parent = util.join(ctx.src, "..")
    local tarball = util.join(ctx.store.cache,
                              "icu4c-76.1-icu4c-76_1-src.tgz")
    fs.rm(util.join(parent, "testdata"))
    ctx.exec({ "tar", "xf", tarball, "-C", parent, "--strip-components=1",
               "icu/LICENSE", "icu/license.html", "icu/testdata" },
             { cwd = ctx.src, log = ctx.log, env = ctx.env })
end

local function cfg_args(ctx)
    return { "--cache-file=" .. ctx.src .. "/config.cache" }
end

local function pre_build(ctx)
    local py = ctx.dep("python")
    assert(py, "gcpkg: icu4c:python feature requires the source-built python port")
    local pybin = (py.binaries or {})[1]
    ctx.env.PYTHON = pybin and (pybin .. "/python3") or
                     (py.prefix .. "/bin/python3")
    local f = triplet.facts()
    restore_upstream_assets(ctx)
    local n = make_cache(ctx, f)
    add_path(ctx, "LD_LIBRARY_PATH", ctx.prefix .. "/lib")
    add_path(ctx, "LIBRARY_PATH", ctx.prefix .. "/lib")
    ctx.exec({ ctx.env.PYTHON, ctx.port_dir .. "/patch-configure.py",
               ctx.src .. "/configure" },
             { cwd = ctx.src, log = ctx.log, env = ctx.env })
    log.info("  icu4c: " .. n .. " shared-fact cache entries; configure probes short-circuited")
end

local function post_install(ctx)
    if ctx.features.enabled["tests"] then
        ctx.exec({ "make", "check" },
                 { cwd = ctx.src, log = ctx.log, env = ctx.env })
    end
    write_cmake_config(ctx)
end

local function build_port(ctx)
    pre_build(ctx)
    local args = util.concat(util.deepcopy(cfg_args(ctx)), ctx.feature_args())
    args = util.concat(args, triplet.autotools_args({
        cc = ctx.env.CC, cxx = ctx.env.CXX, cpp = ctx.env.CPP,
    }))
    autotools.configure {
        src = ctx.src, prefix = ctx.prefix, exec = ctx.exec,
        log = ctx.log, env = ctx.env, args = args,
    }
    autotools.fix_timestamps {
        src = ctx.src, exec = ctx.exec, log = ctx.log, env = ctx.env,
    }
    -- gcpkg's generic autotools step touches generated Makefile.in/configure
    -- files after configure.  ICU's Makefile treats a newer configure as a
    -- fatal "config.status has become stale"; touch the generated outputs
    -- before make so the build uses the freshly generated configuration.
    ctx.exec({ "find", ctx.src, "-type", "f", "(",
               "-name", "config.status", "-o", "-name", "Makefile",
               "-o", "-name", "icudefs.mk", "-o", "-name", "*.mk", ")",
               "-exec", "touch", "{}", "+" },
             { cwd = ctx.src, log = ctx.log, env = ctx.env })
    local base = {
        cwd = ctx.src, exec = ctx.exec, log = ctx.log,
        jobs = ctx.jobs, env = ctx.env, vars = {},
    }
    make.run(util.merge(base, { targets = {} }))
    make.run(util.merge(base, { targets = { "install" } }))
    post_install(ctx)
    return {
        includes = { ctx.prefix .. "/include" },
        libdirs = { ctx.prefix .. "/lib" },
        libs = { "icui18n", "icuuc", "icudata", "icuio" },
        binaries = { ctx.prefix .. "/bin" },
        defines = {}, link_flags = {}, compdb_files = {},
    }
end

return recipe.define {
    name = "icu4c",
    version = "76.1",
    license = "Unicode-3.0",
    homepage = "https://icu.unicode.org",
    description = "ICU4C Unicode/i18n libraries, tools, tests and CMake package",
    source = {
        url = "https://github.com/unicode-org/icu/releases/download/release-76-1/icu4c-76_1-src.tgz",
        sha256 = "dfacb46bfe4747410472ce3e1144bf28a102feeaa4e3875bac9b4c6cf30f4f3e",
        strip = 2,
    },
    dependencies = {},
    build = build_port,
}
