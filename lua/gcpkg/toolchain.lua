-- Compiler / cross-compilation toolchain resolution.
--
-- ONE place decides which C/C++ compiler every build uses. The default is
-- clang (including versioned names like clang-23 / clang++-23); gcc and MSVC
-- are never selected implicitly. WSL is Linux: gcpkg.sys.os() already reports
-- "linux" there. A native Windows build reports "windows" but only changes the
-- STATIC default policy (still clang, never cl.exe/MSVC). There is no Win32
-- runtime port and no WSL-specific branch.
--
-- Resolution is lazy: `check`, `ports`, `graph`, `proxy`, `--help`, ... never
-- probe the compiler. Actual builds call describe_once(), compiler(), env(),
-- cmake_args(), meson_args() etc. Configuration precedence is:
--   CLI > project (gcpkg.yaml / workspace.yaml) > user config.yaml > env > auto.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local M = { current = nil, cache = {}, described = false }

local TOOLCHAIN_KEYS = { "cc", "cxx", "target", "triple", "sysroot",
                         "cross_prefix", "llvm_home" }

local function getenv(k)
    return gcpkg.sys.getenv(k) or ""
end

local function nonempty(v)
    return type(v) == "string" and v ~= "" and v or nil
end

local function push(list, v)
    v = nonempty(v)
    if v then list[#list + 1] = v end
end

local function firstIn(list)
    for _, v in ipairs(list) do
        if nonempty(v) then return v end
    end
    return nil
end

local function basename(path)
    return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function trim(s)
    return util.trim(s or "")
end

-- Static platform policy. Kept pure so unit tests can verify Windows defaults
-- without running on Windows. WSL/msys/POSIX-on-Windows all normalise to linux.
function M.normalize_platform(name)
    name = tostring(name or gcpkg.sys.os() or "linux"):lower()
    if name == "windows" or name == "win32" or name == "win64" or
       name == "win" or name:find("windows", 1, true) then
        return "windows"
    elseif name == "darwin" or name == "macos" or name == "osx" then
        return "darwin"
    end
    return "linux"  -- linux, wsl, msys, cygwin, ...
end

function M.platform_defaults(name)
    local platform = M.normalize_platform(name)
    -- clang-cl is clang, not MSVC, but plain clang/clang++ are preferred.
    -- cl.exe / msvc / gcc / g++ / cc / c++ are excluded from auto-detection.
    return {
        platform = platform,
        cc = { "clang", "clang-cl" },
        cxx = { "clang++", "clang-cpp", "clang-cl" },
        reject = { "cl.exe", "cl", "msvc", "gcc", "g++", "cc", "c++" },
        versioned = true,
    }
end

function M.parse_target(triple)
    triple = tostring(triple or "")
    local parts = util.split(triple, "-")
    local arch = parts[1] or "unknown"
    local rest = table.concat(parts, "-", 2)
    local system = "linux"
    if rest:find("mingw", 1, true) or rest:find("windows", 1, true) or
       rest:find("w64", 1, true) or rest:find("msvc", 1, true) then
        system = "windows"
    elseif rest:find("apple", 1, true) or rest:find("darwin", 1, true) then
        system = "darwin"
    elseif rest:find("emscripten", 1, true) or arch == "wasm32" then
        system = "emscripten"
    elseif rest:find("freebsd", 1, true) then
        system = "freebsd"
    end
    local cmakeSystem = ({
        linux = "Linux", windows = "Windows", darwin = "Darwin",
        emscripten = "Emscripten", freebsd = "FreeBSD",
    })[system]
    local cpuFamily = ({
        x86_64 = "x86_64", amd64 = "x86_64",
        i386 = "x86", i486 = "x86", i586 = "x86", i686 = "x86",
        aarch64 = "aarch64", arm64 = "aarch64",
        arm = "arm", armv7 = "arm", armv7l = "arm",
        riscv64 = "riscv64", wasm32 = "wasm32",
        powerpc64le = "ppc64", s390x = "s390x",
    })[arch] or arch
    local endian = (arch == "s390x" or arch == "powerpc64") and "big" or "little"
    return {
        triple = triple, arch = arch, system = system,
        cmake_system = cmakeSystem, meson_system = system,
        cpu_family = cpuFamily, cpu = arch, endian = endian,
        autotools_host = triple,
    }
end

function M.host_triple()
    local arch = gcpkg.sys.arch() or "unknown"
    local osName = M.normalize_platform()
    if osName == "darwin" then
        return arch .. "-apple-darwin"
    elseif osName == "windows" then
        return arch .. "-pc-windows-msvc"
    end
    return arch .. "-linux-gnu"
end

local function option(name, envNames, alias)
    local c = M.active()
    local list = {}
    push(list, c.cli[name])
    if alias then push(list, c.cli[alias]) end
    push(list, c.project[name])
    if alias then push(list, c.project[alias]) end
    push(list, c.user[name])
    if alias then push(list, c.user[alias]) end
    for _, e in ipairs(envNames or {}) do push(list, getenv(e)) end
    return firstIn(list)
end

local function state_dir()
    local c = M.active()
    return firstIn({ c.state_dir, getenv("GCPKG_HOME") }) or
           util.join(getenv("HOME") ~= "" and getenv("HOME") or ".", ".gcpkg")
end

function M.configure(o)
    o = o or {}
    M.current = {
        cli = {
            cc = o.cc, cxx = o.cxx, target = o.target, triple = o.triple,
            sysroot = o.sysroot, cross_prefix = o.cross_prefix,
            llvm_home = o.llvm_home,
        },
        project = type(o.project) == "table" and o.project or {},
        user = type(o.user) == "table" and o.user or {},
        state_dir = o.state_dir,
    }
    M.cache = {}
    M.described = false
    return M.current
end

function M.active()
    return M.current or M.configure({})
end

function M.reset()
    M.current = nil
    M.cache = {}
    M.described = false
end

function M.target()
    return option("target", { "GCPKG_TARGET", "GCPKG_TRIPLE" }, "triple")
end

function M.sysroot()
    return option("sysroot", { "GCPKG_SYSROOT" })
end

function M.is_cross()
    local t = M.target()
    return t ~= nil and t ~= M.host_triple()
end

function M.target_arch()
    if M.is_cross() then return M.parse_target(M.target()).arch end
    return gcpkg.sys.arch()
end

function M.target_os()
    if M.is_cross() then return M.parse_target(M.target()).system end
    return M.normalize_platform()
end

function M.target_triplet()
    return M.target() or M.host_triple()
end

function M.cross_prefix()
    local explicit = option("cross_prefix", { "GCPKG_CROSS_PREFIX" })
    if explicit then return explicit end
    if M.is_cross() then return M.target() .. "-" end
    return nil
end

function M.llvm_home()
    return option("llvm_home", { "GCPKG_LLVM_HOME", "LLVM_HOME", "LLVM_ROOT" })
end

-- Installed LLVM roots are the preferred place to find versioned clang pairs
-- even when apt.llvm.org did not add unversioned clang/clang++ to PATH.
function M.llvm_roots()
    if M.cache.llvm_roots then return M.cache.llvm_roots end
    local out, seen = {}, {}
    local function add(root)
        if type(root) == "string" and root ~= "" and not seen[root] then
            seen[root] = true
            out[#out + 1] = root
        end
    end
    add(M.llvm_home())
    local scanned = {}
    for _, base in ipairs({ "/usr/lib", "/usr/local", "/opt" }) do
        local ok, entries = pcall(fs.listdir, base)
        if ok and type(entries) == "table" then
            for _, entry in ipairs(entries) do
                local lower = tostring(entry):lower()
                if lower:match("^llvm%-?(%d*)$") then
                    local root = util.join(base, entry)
                    if fs.isfile(util.join(root, "bin", "clang")) or
                       fs.isfile(util.join(root, "bin", "clang++")) then
                        local version = tonumber(lower:match("^llvm%-?(%d+)$")) or 0
                        scanned[#scanned + 1] = { root = root, version = version }
                    end
                end
            end
        end
    end
    table.sort(scanned, function(a, b)
        if a.version ~= b.version then return a.version > b.version end
        return a.root < b.root
    end)
    for _, item in ipairs(scanned) do add(item.root) end
    M.cache.llvm_roots = out
    return out
end

function M.llvm_dirs()
    local out = {}
    for _, root in ipairs(M.llvm_roots()) do
        out[#out + 1] = util.join(root, "bin")
    end
    return out
end

local function is_wrapper(value)
    value = tostring(value or "")
    if value == "" or value == "cc" or value == "c++" then return true end
    if value:find("gcpkg-intercept", 1, true) then return true end
    local base = basename(value):lower():gsub("%.exe$", "")
    return base == "cc" or base == "c++"
end

local function implicit_default(value, defaults)
    local base = basename(value):lower():gsub("%.exe$", "")
    for _, rejected in ipairs(defaults.reject) do
        if base == rejected or base == rejected:gsub("%.exe$", "") then
            return true
        end
    end
    return false
end

local function configured_compiler(kind, defaults)
    local c = M.active()
    local list = {}
    push(list, c.cli[kind])
    push(list, c.project[kind])
    push(list, c.user[kind])
    push(list, getenv(kind == "cxx" and "GCPKG_CXX" or "GCPKG_CC"))
    local envValue = getenv(kind == "cxx" and "CXX" or "CC")
    -- Visual Studio / distro defaults (cl.exe, gcc, cc, c++) are not a user
    -- choice: never let them become gcpkg's implicit compiler.
    if envValue ~= "" and not is_wrapper(envValue) and
       not implicit_default(envValue, defaults) then
        push(list, envValue)
    end
    local value = firstIn(list)
    if value and is_wrapper(value) then return nil end
    return value
end

-- Peek without scanning PATH: enough to decide which cross flags to emit.
local function peek_compiler(kind)
    local defaults = M.platform_defaults()
    return configured_compiler(kind, defaults) or
           (kind == "cxx" and "clang++" or "clang")
end

local function scan_compilers(extraDirs)
    local dirs, seenDir = {}, {}
    local function addDir(dir)
        if dir and dir ~= "" and not seenDir[dir] then
            seenDir[dir] = true
            dirs[#dirs + 1] = dir
        end
    end
    for _, d in ipairs(extraDirs or {}) do addDir(d) end
    -- Accept both POSIX ':' and Windows ';' PATH separators for static analysis.
    for d in tostring(firstIn({ getenv("PATH"), "/usr/bin:/bin" }) or ""):gmatch("[^:;]+") do
        addDir(d)
    end
    local cc, cxx, cxxRank = {}, {}, {}
    -- clang++ is the preferred C++ driver, clang-cpp next, and clang-cl is a
    -- valid MSVC-style driver/fallback for both languages. A versioned
    -- clang-cl-N + clang-cpp-N pair must still be matched deterministically.
    local function setCxx(v, full, rank)
        if cxx[v] == nil or (cxxRank[v] or 0) < rank then
            cxx[v] = full
            cxxRank[v] = rank
        end
    end
    local function record(entry, dir)
        local name = tostring(entry):lower():gsub("%.exe$", "")
        local full = util.join(dir, entry)
        if not fs.isfile(full) then return end
        local v
        if name == "clang" then
            v = 0
        elseif name:match("^clang%-(%d+)$") then
            v = tonumber(name:match("^clang%-(%d+)$"))
        elseif name == "clang-cl" then
            v = 0
            setCxx(v, full, 1)
        elseif name:match("^clang%-cl%-(%d+)$") then
            v = tonumber(name:match("^clang%-cl%-(%d+)$"))
            setCxx(v, full, 1)
        elseif name == "clang-cpp" then
            setCxx(0, full, 2)
            return
        elseif name:match("^clang%-cpp%-(%d+)$") then
            v = tonumber(name:match("^clang%-cpp%-(%d+)$"))
            setCxx(v, full, 2)
            return
        elseif name == "clang++" then
            setCxx(0, full, 3)
            return
        elseif name:match("^clang%+%+%-(%d+)$") then
            v = tonumber(name:match("^clang%+%+%-(%d+)$"))
            setCxx(v, full, 3)
            return
        else
            return
        end
        if v ~= nil and cc[v] == nil then cc[v] = full end
    end
    for _, dir in ipairs(dirs) do
        local ok, entries = pcall(fs.listdir, dir)
        if ok and type(entries) == "table" then
            for _, entry in ipairs(entries) do record(entry, dir) end
        end
    end
    return cc, cxx
end

-- Pure PATH lookup: resolving a compiler must not spawn a child process,
-- because exec.capture/exec.run call toolchain.env() -> flags() -> compiler().
local function path_has_program(name)
    if type(name) ~= "string" or name == "" then return false end
    if name:find("/") or name:find("\\", 1, true) then return fs.isfile(name) end
    local path = getenv("PATH")
    if path == "" then path = "/usr/bin:/bin" end
    for dir in path:gmatch("[^:;]+") do
        if fs.isfile(util.join(dir, name)) or
           fs.isfile(util.join(dir, name .. ".exe")) then
            return true
        end
    end
    return false
end

local function gcc_fallback(kind)
    if getenv("GCPKG_ALLOW_GCC_FALLBACK") ~= "1" then return nil end
    return kind == "cxx" and "g++" or "gcc"
end

local function resolve_compiler(kind)
    local defaults = M.platform_defaults()
    local explicit = configured_compiler(kind, defaults)
    if explicit then return explicit, "configured" end
    local cc, cxx = scan_compilers(M.llvm_dirs())
    local ccVersions, cxxVersions = util.keys(cc), util.keys(cxx)
    table.sort(ccVersions, function(a, b) return a > b end)
    table.sort(cxxVersions, function(a, b) return a > b end)
    -- Prefer matching version pairs: clang-23 + clang++-23.
    for _, v in ipairs(ccVersions) do
        if cxx[v] then
            local source = v > 0 and ("clang-" .. tostring(v)) or "clang"
            return (kind == "cxx") and cxx[v] or cc[v], source
        end
    end
    -- Mismatched versions are still better than no clang; warn once.
    local candidate = (kind == "cxx") and
                      (cxx[cxxVersions[1]] or cxx[0]) or
                      (cc[ccVersions[1]] or cc[0])
    if candidate then
        if not M.cache.mismatchWarn and gcpkg.log and gcpkg.log.warn then
            gcpkg.log.warn("  versioned clang pair mismatch; using " .. candidate)
            M.cache.mismatchWarn = true
        end
        return candidate, "clang (version mismatch)"
    end
    local fallback = gcc_fallback(kind)
    if fallback then return fallback, "gcc (GCPKG_ALLOW_GCC_FALLBACK=1)" end
    error("no clang compiler found for " .. kind ..
          " (looked for clang[-N] / clang++[-N] in PATH, $GCPKG_LLVM_HOME/bin " ..
          "and /usr/lib/llvm-*/bin).\n" ..
          "  Install LLVM, e.g. Linux: wget https://apt.llvm.org/llvm.sh && " ..
          "chmod +x llvm.sh && sudo ./llvm.sh <version>\n" ..
          "  Or set --cc/--cxx, GCPKG_CC/GCPKG_CXX, compiler.cc/cxx in " ..
          "gcpkg.yaml, or use `gcpkg llvm use DIR`.\n" ..
          "  gcc/MSVC is never the default; GCPKG_ALLOW_GCC_FALLBACK=1 " ..
          "opts in to gcc explicitly.")
end

function M.compiler(kind)
    kind = (kind == "cxx") and "cxx" or "cc"
    M.cache = M.cache or {}
    if M.cache[kind] then return M.cache[kind] end
    local value, source = resolve_compiler(kind)
    -- For cross builds with an explicitly chosen gcc family, prefer a
    -- triplet-prefixed cross compiler when one exists.
    if M.is_cross() and M.family(value) == "gcc" then
        local prefix = M.cross_prefix()
        if prefix then
            local name = basename(value):gsub("^.*%-", "")
            local crossName = prefix .. name
            if path_has_program(crossName) then
                value = crossName
                source = "cross-" .. source
            end
        end
    end
    M.cache[kind] = value
    M.cache[kind .. "_source"] = source
    return value
end

function M.compiler_source(kind)
    kind = (kind == "cxx") and "cxx" or "cc"
    local ok = pcall(M.compiler, kind)
    if not ok then return "unresolved" end
    return M.cache[kind .. "_source"] or "configured"
end

function M.compiler_for_files(kind)
    kind = (kind == "cxx") and "cxx" or "cc"
    local ok, value = pcall(M.compiler, kind)
    if ok and value and value ~= "" then return value end
    return kind == "cxx" and "clang++" or "clang"
end

function M.family(value)
    value = basename(value):lower():gsub("%.exe$", "")
    if value:find("clang", 1, true) then return "clang" end
    if value:find("gcc", 1, true) or value:find("g++", 1, true) or
       value == "cc" or value == "c++" then return "gcc" end
    return "unknown"
end

-- Flags every compiler invocation needs for the selected target. Use the
-- ACTUAL resolved compiler family: with GCPKG_ALLOW_GCC_FALLBACK=1 a missing
-- clang resolves to gcc, which must not receive clang's --target option.
-- compiler() is pure filesystem/PATH scanning now, so this cannot recurse into
-- exec.capture() even when a child process inherits toolchain.env().
local function flags_family()
    local ok, value = pcall(M.compiler, "cc")
    if ok and value and value ~= "" then
        local resolved = M.family(value)
        if resolved ~= "unknown" then return resolved end
    end
    return M.family(peek_compiler("cc"))
end

function M.flags()
    if not M.is_cross() then return {} end
    local out = {}
    local family = flags_family()
    if family == "clang" or family == "unknown" then
        out[#out + 1] = "--target=" .. M.target()
    end
    local sysroot = M.sysroot()
    if sysroot then out[#out + 1] = "--sysroot=" .. sysroot end
    return out
end

local function append_flags(base, key, flags)
    local prev = (type(base) == "table" and base[key]) or getenv(key) or ""
    local out = tostring(prev)
    for _, flag in ipairs(flags) do
        if not out:find(flag, 1, true) then
            out = trim(out .. (out ~= "" and " " or "") .. flag)
        end
    end
    return out
end

-- Extra environment for build hooks / project builds. Does NOT set CC/CXX:
-- those stay pointed at gcpkg-intercept wrappers.
function M.env(base)
    base = base or {}
    local e = {}
    local flags = M.flags()
    if #flags > 0 then
        local text = table.concat(flags, " ")
        e.CFLAGS = append_flags(base, "CFLAGS", flags)
        e.CXXFLAGS = append_flags(base, "CXXFLAGS", flags)
        e.LDFLAGS = append_flags(base, "LDFLAGS", flags)
        -- gcpkg-intercept injects these into every real compiler argv, so
        -- compile_commands.json / clangd see the cross target too.
        e.GCPKG_COMPILER_FLAGS = text
    end
    if M.is_cross() then
        local target = M.target()
        e.GCPKG_TARGET_TRIPLE = target
        e.GCPKG_TARGET_TRIPLET = target
        local prefix = M.cross_prefix()
        if prefix then e.GCPKG_CROSS_PREFIX = prefix end
        e.GCPKG_CMAKE_CROSS_FILE = M.cmake_toolchain_path()
        e.GCPKG_MESON_CROSS_FILE = M.meson_cross_path()
        local sysroot = M.sysroot()
        if sysroot then
            e.GCPKG_SYSROOT = sysroot
            e.PKG_CONFIG_SYSROOT_DIR = sysroot
            local dirs = { util.join(sysroot, "usr", "lib", "pkgconfig"),
                           util.join(sysroot, "usr", "share", "pkgconfig") }
            local prev = (type(base) == "table" and base.PKG_CONFIG_LIBDIR) or
                         getenv("PKG_CONFIG_LIBDIR") or ""
            e.PKG_CONFIG_LIBDIR = trim((prev ~= "" and prev .. ":" or "") ..
                                       table.concat(dirs, ":"))
        end
    end
    local home = M.llvm_home()
    if home then e.GCPKG_LLVM_HOME = home end
    return e
end

local function cmakeQuote(s)
    return tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function mesonQuote(s)
    return "'" .. tostring(s or ""):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

local function safeStem(triple)
    return (tostring(triple):gsub("[^%w%.%-]", "_"))
end

function M.cmake_toolchain_path()
    if not M.is_cross() then return nil end
    return util.join(state_dir(), "toolchain-" .. safeStem(M.target()) .. ".cmake")
end

function M.meson_cross_path()
    if not M.is_cross() then return nil end
    return util.join(state_dir(), "meson-" .. safeStem(M.target()) .. ".ini")
end

function M.cmake_lines(opts)
    if not M.is_cross() then return {} end
    opts = opts or {}
    local info = M.parse_target(M.target())
    local cc = M.compiler_for_files("cc")
    local cxx = M.compiler_for_files("cxx")
    local flagText = table.concat(M.flags(), " ")
    -- Inside a gcpkg build, CC/CXX are gcpkg-intercept symlinks and
    -- GCPKG_*_REAL points at the selected clang. Prefer that pair so CMake's
    -- compiler probes still contribute JSONL/compdb entries; outside gcpkg,
    -- use the resolved clang path directly (never cc/c++/gcc/MSVC).
    local function compilerLines(var, envName, realEnvName, value)
        local fixed = "set(" .. var .. " \"" .. cmakeQuote(value) .. "\")"
        if not opts.compiler_from_env then return { fixed } end
        return {
            "if(NOT \"$ENV{" .. envName .. "}\" STREQUAL \"\" AND " ..
                "NOT \"$ENV{" .. realEnvName .. "}\" STREQUAL \"\")",
            "  set(" .. var .. " \"$ENV{" .. envName .. "}\")",
            "else()",
            "  " .. fixed,
            "endif()",
        }
    end
    local lines = {
        "set(GCPKG_TARGET_TRIPLE \"" .. cmakeQuote(info.triple) .. "\")",
        "set(CMAKE_SYSTEM_NAME \"" .. cmakeQuote(info.cmake_system) .. "\")",
        "set(CMAKE_SYSTEM_PROCESSOR \"" .. cmakeQuote(info.cpu) .. "\")",
    }
    for _, line in ipairs(compilerLines("CMAKE_C_COMPILER", "CC",
                                        "GCPKG_CC_REAL", cc)) do
        lines[#lines + 1] = line
    end
    for _, line in ipairs(compilerLines("CMAKE_CXX_COMPILER", "CXX",
                                        "GCPKG_CXX_REAL", cxx)) do
        lines[#lines + 1] = line
    end
    if M.family(cc) == "clang" then
        lines[#lines + 1] = "set(CMAKE_C_COMPILER_TARGET \"" ..
                            cmakeQuote(info.triple) .. "\")"
    end
    if M.family(cxx) == "clang" then
        lines[#lines + 1] = "set(CMAKE_CXX_COMPILER_TARGET \"" ..
                            cmakeQuote(info.triple) .. "\")"
    end
    local sysroot = M.sysroot()
    if sysroot then
        lines[#lines + 1] = "set(CMAKE_SYSROOT \"" .. cmakeQuote(sysroot) .. "\")"
        lines[#lines + 1] = "set(CMAKE_FIND_ROOT_PATH \"" .. cmakeQuote(sysroot) .. "\")"
        lines[#lines + 1] = "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)"
        lines[#lines + 1] = "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)"
        lines[#lines + 1] = "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)"
        lines[#lines + 1] = "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)"
    end
    lines[#lines + 1] = "set(CMAKE_C_FLAGS_INIT \"" .. cmakeQuote(flagText) .. "\")"
    lines[#lines + 1] = "set(CMAKE_CXX_FLAGS_INIT \"" .. cmakeQuote(flagText) .. "\")"
    lines[#lines + 1] = "set(CMAKE_EXE_LINKER_FLAGS_INIT \"" .. cmakeQuote(flagText) .. "\")"
    local chainloads = type(opts.chainload) == "table" and opts.chainload or
                       { opts.chainload }
    local seen = {}
    for _, path in ipairs(chainloads) do
        path = nonempty(path)
        if path and path ~= opts.path and not seen[path] then
            seen[path] = true
            lines[#lines + 1] = "if(EXISTS \"" .. cmakeQuote(path) .. "\")"
            lines[#lines + 1] = "  include(\"" .. cmakeQuote(path) .. "\")"
            lines[#lines + 1] = "endif()"
        end
    end
    return lines
end

function M.cmake_file(path, opts)
    fs.mkdirs(util.dirname(path))
    fs.write(path, "# Generated by gcpkg cross toolchain. Do not edit.\n" ..
             table.concat(M.cmake_lines(opts or {}), "\n") .. "\n")
    return path
end

function M.cmake_args(opts)
    if not M.is_cross() then return {} end
    opts = opts or {}
    local path = opts.path or M.cmake_toolchain_path()
    -- Files written for real builds prefer the interceptor CC/CXX environment;
    -- callers can opt out with compiler_from_env=false for a standalone file.
    local fileOpts = util.merge({ compiler_from_env = true }, opts, { path = path })
    M.cmake_file(path, fileOpts)
    return { "-DCMAKE_TOOLCHAIN_FILE=" .. path }
end

function M.meson_lines()
    if not M.is_cross() then
        return { "# Generated by gcpkg -- no cross build selected." }
    end
    local info = M.parse_target(M.target())
    local flags = M.flags()
    local list = {}
    for _, flag in ipairs(flags) do list[#list + 1] = mesonQuote(flag) end
    local flagText = "[" .. table.concat(list, ", ") .. "]"
    local prefix = M.cross_prefix()
    local function bintool(name, fallback)
        return prefix and prefix ~= "" and (prefix .. name) or fallback
    end
    local lines = {
        "[binaries]",
        "c = " .. mesonQuote(M.compiler_for_files("cc")),
        "cpp = " .. mesonQuote(M.compiler_for_files("cxx")),
        "ar = " .. mesonQuote(bintool("ar", "llvm-ar")),
        "strip = " .. mesonQuote(bintool("strip", "llvm-strip")),
        "pkgconfig = " .. mesonQuote(bintool("pkg-config", "pkg-config")),
        "[built-in options]",
        "c_args = " .. flagText,
        "cpp_args = " .. flagText,
        "c_link_args = " .. flagText,
        "cpp_link_args = " .. flagText,
        "[host_machine]",
        "system = " .. mesonQuote(info.meson_system),
        "cpu_family = " .. mesonQuote(info.cpu_family),
        "cpu = " .. mesonQuote(info.cpu),
        "endian = " .. mesonQuote(info.endian),
    }
    return lines
end

function M.meson_file(path)
    fs.mkdirs(util.dirname(path))
    fs.write(path, "# Generated by gcpkg Meson cross file. Do not edit.\n" ..
             table.concat(M.meson_lines(), "\n") .. "\n")
    return path
end

function M.meson_args(opts)
    if not M.is_cross() then return {} end
    opts = opts or {}
    local path = opts.path or M.meson_cross_path()
    M.meson_file(path)
    return { "--cross-file=" .. path }
end

function M.autotools_args()
    if not M.is_cross() then return {} end
    return { "--host=" .. M.parse_target(M.target()).autotools_host,
             "--build=" .. M.host_triple() }
end

function M.validate()
    local sysroot = M.sysroot()
    if sysroot and not fs.isdir(sysroot) then
        error("cross sysroot does not exist: " .. sysroot)
    end
    return true
end

function M.fingerprint()
    local ok, cc = pcall(M.compiler, "cc")
    local ok2, cxx = pcall(M.compiler, "cxx")
    return table.concat({
        "platform=" .. M.platform_defaults().platform,
        "cc=" .. (ok and cc or "unresolved"),
        "cxx=" .. (ok2 and cxx or "unresolved"),
        "target=" .. (M.target() or "native"),
        "sysroot=" .. (M.sysroot() or ""),
        "prefix=" .. (M.cross_prefix() or ""),
        "llvm=" .. (M.llvm_home() or ""),
        "flags=" .. table.concat(M.flags(), " "),
    }, "|")
end

function M.describe()
    local log = require("gcpkg.log")
    local function safe(kind)
        local ok, value = pcall(M.compiler, kind)
        return ok and value or "(no clang found; see docs/TOOLCHAIN.md)"
    end
    local function safeSource(kind)
        local ok, value = pcall(M.compiler_source, kind)
        return ok and value or "unresolved"
    end
    log.step("toolchain:")
    log.info("  cc                  : " .. safe("cc") ..
             " [" .. safeSource("cc") .. "]")
    log.info("  cxx                 : " .. safe("cxx") ..
             " [" .. safeSource("cxx") .. "]")
    log.info("  default policy      : clang (never gcc/MSVC); WSL == linux")
    log.info("  platform            : " .. M.normalize_platform())
    log.info("  host triple         : " .. M.host_triple())
    log.info("  target              : " .. (M.target() or "native"))
    log.info("  sysroot             : " .. (M.sysroot() or "(none)"))
    log.info("  cross               : " .. (M.is_cross() and "yes" or "no"))
    log.info("  cross prefix        : " .. (M.cross_prefix() or "(none)"))
    log.info("  compiler flags      : " ..
             (#M.flags() > 0 and table.concat(M.flags(), " ") or "(none)"))
    local rootsOk, roots = pcall(M.llvm_roots)
    if not rootsOk or type(roots) ~= "table" then roots = {} end
    local shown = {}
    for i = 1, math.min(3, #roots) do shown[#shown + 1] = roots[i] end
    log.info("  llvm home           : " ..
             (M.llvm_home() or roots[1] or "(none)") ..
             (M.llvm_home() and " [configured]" or " [auto]"))
    log.info("  llvm roots          : " ..
             (#shown > 0 and table.concat(shown, ", ") or "(none)"))
    if M.is_cross() then
        local ok, args = pcall(M.cmake_args)
        if ok and args[1] then
            log.info("  cmake toolchain     : " ..
                     (args[1]:match("^%-DCMAKE_TOOLCHAIN_FILE=(.*)$") or args[1]))
        end
        local ok2, margs = pcall(M.meson_args)
        if ok2 and margs[1] then
            log.info("  meson cross file    : " ..
                     (margs[1]:match("^%-%-cross%-file=(.*)$") or margs[1]))
        end
    end
    M.described = true
end

function M.describe_once()
    if M.described then return end
    M.validate()
    -- Fail early and explain how to install/choose LLVM instead of silently
    -- falling back to gcc/MSVC.
    M.compiler("cc")
    M.compiler("cxx")
    M.describe()
end

-- Make this the single sys.compiler knob even when a module is required
-- directly by a unit-test shim rather than through lua/main.lua.
if type(gcpkg) == "table" and type(gcpkg.sys) == "table" then
    gcpkg.sys.compiler = function(kind)
        return M.compiler(kind == "cxx" and "cxx" or "cc")
    end
end

return M
