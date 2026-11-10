-- gcpkg triplets: ONE platform fact table shared by EVERY port.
--
-- A triplet (like a vcpkg triplet) describes the target OS / CPU / compiler and
-- the platform facts that upstream build systems normally discover with
-- try_compile / check_* / AC_CHECK_*.  gcpkg never lets a library run those
-- probes: at the start of an install task it compiles and runs ONE small C
-- program itself, and injects the resulting table into every port in that
-- task.  Nothing about x86_64 / little-endian / glibc is hardcoded here.
--
-- Precedence, highest first:
--   1. facts: in <store>/.gcpkg/config.yaml        (user global override)
--   2. facts: in <store>/.gcpkg/triplets/<n>.yaml  (user triplet override)
--   3. gcpkg's single probe of the selected compiler
-- All state lives inside the store (the hard write boundary).
local M = {}

local BUILTIN = {
    native = { description = "Auto-probe the host compiler, OS and CPU once per install task" },
    ["x64-linux-clang"] = { description = "x86_64 Linux / Clang", target = { arch = "x86_64", os = "linux", compiler = "clang" } },
    ["x64-linux-gcc"] = { description = "x86_64 Linux / GCC", target = { arch = "x86_64", os = "linux", compiler = "gcc" } },
    ["arm64-linux-clang"] = { description = "AArch64 Linux / Clang", target = { arch = "aarch64", os = "linux", compiler = "clang" } },
    ["arm64-linux-gcc"] = { description = "AArch64 Linux / GCC", target = { arch = "aarch64", os = "linux", compiler = "gcc" } },
}

-- The probe covers the union of checks used by the source ports, plus the
-- usual libc/POSIX surface.  One compile + one run, no per-library probes.
local HEADERS = {
    "assert.h", "ctype.h", "dirent.h", "errno.h", "fcntl.h", "float.h",
    "limits.h", "malloc.h", "memory.h", "setjmp.h", "signal.h", "stdarg.h",
    "stddef.h", "stdint.h", "stdio.h", "stdlib.h", "string.h", "strings.h",
    "time.h", "unistd.h", "utime.h", "sys/mman.h", "sys/resource.h",
    "sys/stat.h", "sys/time.h", "sys/types.h", "sys/wait.h",
    "stdbool.h", "stdalign.h", "inttypes.h", "wchar.h", "dlfcn.h",
    "execinfo.h", "sys/ioctl.h", "sys/socket.h", "sys/select.h", "sys/uio.h",
    "netinet/in.h", "arpa/inet.h", "poll.h", "pthread.h", "getopt.h",
    "fnmatch.h", "regex.h", "termios.h", "grp.h", "pwd.h", "byteswap.h",
    "endian.h", "features.h", "stdatomic.h", "complex.h", "locale.h",
    "math.h", "iconv.h", "sys/epoll.h", "sys/eventfd.h", "sys/inotify.h",
}

local FUNCTIONS = {
    "access", "alloca", "atexit", "atoi", "atol", "chmod", "chown",
    "clock_getcpuclockid", "clock_getres", "clock_gettime", "ctime",
    "difftime", "fstat", "getenv", "getpagesize", "getrusage",
    "gettimeofday", "gmtime", "isatty", "localtime", "longjmp", "lstat",
    "memcmp", "memcpy", "memmove", "memset", "mkdir", "mktime", "mmap",
    "mprotect", "munmap", "qsort", "raise", "rmdir", "setjmp", "signal",
    "snprintf", "strcasecmp", "strchr", "strdup", "strerror", "strftime",
    "stricmp", "strncasecmp", "strnicmp", "strrchr", "strstr", "time",
    "umask", "utime", "vsnprintf",
    "malloc", "calloc", "realloc", "free", "posix_memalign", "aligned_alloc",
    "dlopen", "dlsym", "dlclose", "backtrace", "backtrace_symbols",
    "asprintf", "vasprintf", "getline", "getopt_long", "mkdtemp", "realpath",
    "setenv", "unsetenv", "strerror_r", "pthread_create", "socket", "poll",
    "epoll_create1", "eventfd", "inotify_init1", "fstatat", "openat",
    "readlink", "symlink", "getaddrinfo", "arc4random", "getrandom",
    "explicit_bzero", "memmem", "qsort_r", "reallocarray", "dup3", "pipe2",
    "accept4", "statx", "copy_file_range", "sendfile", "preadv", "pwritev",
    "strlcpy", "strlcat", "strcasestr", "strsignal", "sigaction",
    "sigprocmask", "nanosleep", "sched_yield", "basename", "dirname",
    "strsep", "syncfs", "clock_nanosleep", "pthread_setname_np",
}

local TYPES = {
    "short", "int", "long", "long long", "__int16", "__int32", "__int64",
    "void *", "size_t", "ptrdiff_t", "intmax_t", "uintmax_t", "intptr_t",
    "uintptr_t", "float", "double", "long double", "dev_t", "fpos_t",
    "mode_t", "off_t", "ssize_t", "time_t", "char", "wchar_t",
    "unsigned int", "unsigned long", "unsigned long long", "int8_t",
    "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t",
    "uint64_t",
}

local HEADER_TMPL = [==[
#if defined(__has_include)
#if __has_include(<%s>)
  printf("header:%s=1\n");
#else
  printf("header:%s=0\n");
#endif
#else
  printf("header:%s=1\n");
#endif
]==]

local TYPE_TMPL = [==[
  printf("type:%s=%%zu\n", sizeof(%s));
]==]

local TYPE_MSVC_TMPL = [==[
#ifdef _MSC_VER
  printf("type:%s=%%zu\n", sizeof(%s));
#else
  printf("type:%s=\n");
#endif
]==]

local PROLOG = [==[
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/types.h>
#include <wchar.h>
#include <dlfcn.h>
static const char *gcpkg_funcs[] = {]==]

local EPILOG = [==[
NULL};
int main(void) {
  unsigned int one = 1;
  int i;
  printf("byte_order=%s\n", (*(unsigned char *)&one) ? "little" : "big");
  printf("pointer_size=%zu\n", sizeof(void *));
#if defined(__x86_64__) || defined(_M_X64)
  printf("arch=x86_64\n");
#elif defined(__aarch64__) || defined(_M_ARM64)
  printf("arch=aarch64\n");
#elif defined(__i386__) || defined(_M_IX86)
  printf("arch=x86\n");
#elif defined(__arm__) || defined(_M_ARM)
  printf("arch=arm\n");
#elif defined(__riscv)
  printf("arch=riscv\n");
#elif defined(__powerpc64__)
  printf("arch=ppc64\n");
#else
  printf("arch=unknown\n");
#endif
#if defined(__linux__)
  printf("os=linux\n");
#elif defined(__APPLE__)
  printf("os=macos\n");
#elif defined(_WIN32)
  printf("os=windows\n");
#elif defined(__FreeBSD__)
  printf("os=freebsd\n");
#else
  printf("os=unknown\n");
#endif
#if defined(__clang__)
  printf("compiler_id=clang\n");
#elif defined(__GNUC__)
  printf("compiler_id=gcc\n");
#elif defined(_MSC_VER)
  printf("compiler_id=msvc\n");
#else
  printf("compiler_id=unknown\n");
#endif
  for (i = 0; gcpkg_funcs[i]; i++)
    printf("func:%s=%d\n", gcpkg_funcs[i],
           dlsym(RTLD_DEFAULT, gcpkg_funcs[i]) != NULL ? 1 : 0);
]==]

local cached, cachedName, cliName = nil, nil, nil

local function getenv(k)
    local ok, v = pcall(function() return gcpkg.sys.getenv(k) end)
    return (ok and v) or ""
end

local function first(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" then return v end
    end
    return ""
end

local function key(s)
    return (tostring(s):lower():gsub("[^a-z0-9]", "_"))
end

local function ackey(s)
    s = tostring(s):lower():gsub("%s*%*", "_p")
    return (s:gsub("[^a-z0-9]", "_"))
end

function M.probe_source()
    local out = { PROLOG }
    for _, f in ipairs(FUNCTIONS) do out[#out + 1] = '"' .. f .. '",' end
    out[#out + 1] = EPILOG
    for _, h in ipairs(HEADERS) do
        out[#out + 1] = string.format(HEADER_TMPL, h, h, h, h)
    end
    for _, t in ipairs(TYPES) do
        if t:match("^__int") then
            out[#out + 1] = string.format(TYPE_MSVC_TMPL, t, t, t)
        else
            out[#out + 1] = string.format(TYPE_TMPL, t, t)
        end
    end
    out[#out + 1] = "  return 0;\n}\n"
    return table.concat(out, "\n")
end

function M.dir()
    local paths = require("gcpkg.paths")
    local util = require("gcpkg.util")
    return util.join(paths.state_root(), "triplets")
end

function M.file(name)
    local util = require("gcpkg.util")
    return util.join(M.dir(), name .. ".yaml")
end

function M.active(opts)
    local cli = (opts and opts.triplet) or cliName
    if type(cli) == "string" and cli ~= "" then return cli end
    local config = require("gcpkg.config")
    local y = config.read() or {}
    if type(y.triplet) == "string" and y.triplet ~= "" then return y.triplet end
    return "native"
end

function M.spec(name)
    local util = require("gcpkg.util")
    local fs = require("gcpkg.fs")
    local yaml = require("gcpkg.yaml")
    local spec = util.deepcopy(BUILTIN[name] or {})
    local p = M.file(name)
    if fs.isfile(p) then
        spec = util.merge(spec, yaml.parse_file(p) or {})
    end
    spec.name = name
    return spec
end

function M.list()
    local fs = require("gcpkg.fs")
    local util = require("gcpkg.util")
    local names = {}
    for k in pairs(BUILTIN) do names[#names + 1] = k end
    if fs.isdir(M.dir()) then
        for _, f in ipairs(fs.listdir(M.dir()) or {}) do
            local n = tostring(f):match("^(.*)%.yaml$")
            if n and n ~= "" and not n:match("%.facts$") then
                names[#names + 1] = n
            end
        end
    end
    names = util.uniq(names)
    table.sort(names)
    return names
end

local function probeCompiler(spec)
    local c = (type(spec.compiler) == "table" and spec.compiler.cc) or ""
    return first(c, getenv("GCPKG_CC_REAL"), getenv("CC_REAL"), "cc")
end

local function parseProbe(text)
    local f = { sizes = {}, headers = {}, functions = {} }
    for line in tostring(text):gmatch("[^\n]+") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k then
            if k == "byte_order" or k == "pointer_size" or k == "arch"
               or k == "os" or k == "compiler_id" then
                f[k] = (k == "pointer_size") and (tonumber(v) or v) or v
            elseif k:sub(1, 5) == "type:" then
                f.sizes[k:sub(6)] = tonumber(v) or ""
            elseif k:sub(1, 7) == "header:" then
                f.headers[k:sub(8)] = tonumber(v) or 0
            elseif k:sub(1, 5) == "func:" then
                f.functions[k:sub(6)] = tonumber(v) or 0
            end
        end
    end
    return f
end

local function applyOverrides(f, ov)
    if type(ov) ~= "table" then return f end
    for k, v in pairs(ov) do
        if k == "headers" or k == "functions" or k == "sizes" then
            if type(v) == "table" then
                for n, x in pairs(v) do f[k][n] = x end
            end
        else
            f[k] = v
        end
    end
    return f
end

-- YAML parsers commonly turn `0` / `4` into Lua floats.  Normalise scalars
-- so an explicit user "0" still means "absent" (never "0.0" = non-empty) and
-- facts files stay human-readable integers.
local function scalar(v)
    if v == nil then return "" end
    if type(v) == "boolean" then return v and "1" or "" end
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return tostring(v)
    end
    return tostring(v)
end
M.scalar = scalar

local function yesno(v)
    v = scalar(v)
    if v == "" or v == "0" or v:lower() == "no" or v:lower() == "false" then
        return "no"
    end
    return "yes"
end

local function writeFacts(name, f)
    local fs = require("gcpkg.fs")
    local util = require("gcpkg.util")
    fs.mkdirs(M.dir())
    local l = {
        "schema: 1",
        "# gcpkg platform facts for triplet '" .. name .. "'",
        "# ONE gcpkg probe at install-task start; libraries never probe.",
        "# Override in <store>/.gcpkg/config.yaml (facts:) -- user settings win.",
        "triplet: " .. name,
        "compiler: " .. tostring(f.compiler or ""),
        "arch: " .. tostring(f.arch or "unknown"),
        "os: " .. tostring(f.os or "unknown"),
        "compiler_id: " .. tostring(f.compiler_id or "unknown"),
        "byte_order: " .. tostring(f.byte_order or "unknown"),
        "pointer_size: " .. scalar(f.pointer_size),
        "headers:",
    }
    local names = {}
    for n in pairs(f.headers or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        l[#l + 1] = "  " .. n .. ": " .. scalar(f.headers[n])
    end
    l[#l + 1] = "functions:"
    names = {}
    for n in pairs(f.functions or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        l[#l + 1] = "  " .. n .. ": " .. scalar(f.functions[n])
    end
    l[#l + 1] = "sizes:"
    names = {}
    for n in pairs(f.sizes or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        l[#l + 1] = "  " .. n .. ": " .. scalar(f.sizes[n])
    end
    fs.write(util.join(M.dir(), name .. ".facts.yaml"),
             table.concat(l, "\n") .. "\n")
end

function M.ensure(opts)
    opts = opts or {}
    if opts.triplet and opts.triplet ~= "" then cliName = opts.triplet end
    local name = M.active()
    if cached and cachedName == name then return cached end
    local util = require("gcpkg.util")
    local fs = require("gcpkg.fs")
    local spec = M.spec(name)
    local cc = probeCompiler(spec)
    local probeDir = util.join(require("gcpkg.paths").state_root(), "probe")
    fs.mkdirs(probeDir)
    local src = util.join(probeDir, "platform.c")
    local exe = util.join(probeDir, "platform")
    fs.write(src, M.probe_source())
    local ok = pcall(function()
        gcpkg.exec({ cc, "-O0", "-o", exe, src, "-ldl" }, { quiet = true })
    end)
    if not ok then
        gcpkg.exec({ cc, "-O0", "-o", exe, src }, { quiet = true })
    end
    local out = gcpkg.capture({ exe }, {})
    if type(out) ~= "string" or out == "" then
        error("gcpkg triplet probe produced no output (compiler " .. tostring(cc)
              .. "); set explicit facts in " .. M.file(name))
    end
    local f = parseProbe(out)
    applyOverrides(f, spec.facts)
    applyOverrides(f, (require("gcpkg.config").read() or {}).facts)
    f.compiler = cc
    f.triplet = name
    writeFacts(name, f)
    cached, cachedName = f, name
    local log = require("gcpkg.log")
    log.info("  triplet " .. name .. ": one gcpkg probe ("
             .. tostring(f.byte_order) .. "-endian, " .. tostring(f.pointer_size)
             .. "-byte pointers, " .. tostring(f.os) .. "/" .. tostring(f.arch)
             .. "); user facts override; libraries never probe")
    return f
end

function M.facts(opts)
    if cached then return cached end
    return M.ensure(opts)
end

function M.cmake_fact_lines(opts)
    local f = M.facts(opts)
    local lines = {}
    local function emit(kind, name, value)
        local k = key(kind .. "_" .. tostring(name)):upper()
        local v = scalar(value)
        if v == "0" or v:lower() == "false" or v:lower() == "no" then v = "" end
        lines[#lines + 1] = 'set(GCPKG_FACT_' .. k .. ' "' .. v .. '")'
    end
    for n, v in pairs(f.headers or {}) do
        emit("header", n, v)
    end
    for n, v in pairs(f.functions or {}) do
        emit("func", n, v)
        emit("symbol", n, v)
    end
    for n, v in pairs(f.sizes or {}) do
        emit("type", n, v)
    end
    table.sort(lines)
    return lines
end

function M.cmake_defines(opts)
    local f = M.facts(opts)
    local big = (tostring(f.byte_order) == "big")
    return {
        CMAKE_C_BYTE_ORDER = big and "BIG_ENDIAN" or "LITTLE_ENDIAN",
        CMAKE_CXX_BYTE_ORDER = big and "BIG_ENDIAN" or "LITTLE_ENDIAN",
        big_endian = big and "1" or "0",
        GCPKG_TRIPLET = M.active(),
    }
end

function M.autotools_args(opts)
    local f = M.facts(opts)
    local a = {
        "ac_cv_c_bigendian=" .. ((tostring(f.byte_order) == "big") and "yes" or "no"),
    }
    for n, v in pairs(f.headers or {}) do
        a[#a + 1] = "ac_cv_header_" .. ackey(n) .. "=" .. yesno(v)
    end
    for n, v in pairs(f.functions or {}) do
        a[#a + 1] = "ac_cv_func_" .. ackey(n) .. "=" .. yesno(v)
    end
    for n, v in pairs(f.sizes or {}) do
        if tonumber(v) then
            a[#a + 1] = "ac_cv_sizeof_" .. ackey(n) .. "=" .. scalar(v)
        end
    end
    table.sort(a)
    return a
end

function M.set_active(name)
    local fs = require("gcpkg.fs")
    local config = require("gcpkg.config")
    local p = config.path()
    assert(p and p ~= "", "gcpkg: config path unavailable")
    local out = {}
    for _, l in ipairs(fs.isfile(p) and fs.lines(p) or {}) do
        if not l:match("^%s*triplet%s*:") then out[#out + 1] = l end
    end
    out[#out + 1] = "triplet: " .. tostring(name)
    fs.write(p, table.concat(out, "\n") .. "\n")
    cached, cachedName = nil, nil
    cliName = name
end

function M.create(name)
    local fs = require("gcpkg.fs")
    fs.mkdirs(M.dir())
    local p = M.file(name)
    if fs.isfile(p) then error("triplet already exists: " .. p) end
    fs.write(p, table.concat({
        "schema: 1",
        "name: " .. name,
        "description: User triplet (facts below override gcpkg's probe)",
        "# compiler:",
        "#   cc: /path/to/target-cc",
        "# target:",
        "#   arch: aarch64",
        "#   os: linux",
        "# facts:            # highest precedence for this triplet",
        "#   byte_order: little",
        "#   pointer_size: 8",
        "#   headers:",
        "#     unistd.h: 1",
        "#   functions:",
        "#     atexit: 1",
        "#   sizes:",
        "#     \"void *\": 8",
        "facts: {}",
        "",
    }, "\n"))
    return p
end

function M.describe(name)
    name = name or M.active()
    local f = M.facts()
    local l = {
        "triplet: " .. name,
        "  compiler      : " .. tostring(f.compiler or ""),
        "  os / arch     : " .. tostring(f.os) .. " / " .. tostring(f.arch),
        "  compiler_id   : " .. tostring(f.compiler_id),
        "  byte_order    : " .. tostring(f.byte_order),
        "  pointer_size  : " .. tostring(f.pointer_size),
        "  facts file    : " .. M.dir() .. "/" .. name .. ".facts.yaml",
    }
    return table.concat(l, "\n")
end

return M
