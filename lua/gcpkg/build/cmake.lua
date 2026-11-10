-- CMake adapter. Just a Lua module: `local cmake = require("gcpkg.build.cmake")`
-- is all a port needs to gain CMake build functions. CMake itself is untouched.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local cmake_version = require("gcpkg.cmake_version")
local toolchain = require("gcpkg.toolchain")
local M = {}

local function define_key(arg)
    local key = tostring(arg):match("^%-D([^=]+)=")
    if not key then
        return nil
    end
    return key:match("^([%w_]+)") or key
end

-- Keep the LAST -DNAME=VALUE for each name. Feature args are appended last, so
-- they can override a recipe's default define; a repeated define is emitted
-- once. This is generic for every CMake port, not a zlib-specific workaround.
local function dedup_defines(cmd)
    local seen, out = {}, {}
    for i = #cmd, 1, -1 do
        local key = define_key(cmd[i])
        if key then
            if not seen[key] then
                seen[key] = true
                table.insert(out, 1, tostring(cmd[i]))
            end
        else
            table.insert(out, 1, tostring(cmd[i]))
        end
    end
    return out
end

local function toolchain_from_arg(arg)
    if define_key(arg) == "CMAKE_TOOLCHAIN_FILE" then
        return tostring(arg):match("^%-D[^=]+=(.*)$")
    end
    return nil
end

local function cache_toolchain(args)
    for i = 1, #args - 1 do
        if tostring(args[i]) == "-C" then
            local text = fs.read(args[i + 1]) or ""
            return text:match('set%(CMAKE_TOOLCHAIN_FILE%s+"([^"]+)"')
        end
    end
    return nil
end

local function policy_env(base)
    return util.merge(base or {}, cmake_version.policy_env(base))
end

function M.configure(o)
    local exec = o.exec or gcpkg.exec
    local build = util.abs(o.build_dir or util.join(o.src, "build"), o.src)
    fs.mkdirs(build)
    local defines = type(o.defines) == "table" and o.defines or {}
    -- R20: no port runs feature-detection probes.  try_compile is replaced
    -- by a result table; find_package is overridden so imported targets are
    -- supplied directly instead of being discovered through probes.
    local disableTry = true
    local noTry
    if disableTry then
        local trueResults = {}
        for _, k in ipairs(util.keys(defines)) do
            local v = tostring(defines[k])
            if v == "TRUE" or v == "true" or v == "1" or v == "ON" or v == "YES" then
                trueResults[#trueResults + 1] = k
                -- SDL3 probes LIBC_HAS_<X> then copies it into HAVE_<X>.
                if k:sub(1, 5) == "HAVE_" then
                    trueResults[#trueResults + 1] = "LIBC_HAS_" .. k:sub(6)
                end
            end
        end
        trueResults[#trueResults + 1] = "CMAKE_HAVE_LIBC_PTHREAD"
        local includeText = "set(GCPKG_TRUE_RESULTS\n"
        for _, k in ipairs(trueResults) do
            includeText = includeText .. "  " .. k .. "\n"
        end
        includeText = includeText .. ")\n" .. [==[
# COMPILER_FORCED skips the compiler test that normally fills these tables.
# Supply the results explicitly; no probe is run.
set(CMAKE_C_COMPILE_FEATURES
  c_std_90 c_std_99 c_std_11 c_std_17 c_std_23
  c_function_prototypes c_restrict c_static_assert c_variadic_macros)
set(CMAKE_CXX_COMPILE_FEATURES
  cxx_std_98 cxx_std_11 cxx_std_14 cxx_std_17 cxx_std_20 cxx_std_23)
set(CMAKE_C_STANDARD_COMPUTED_DEFAULT 17)
set(CMAKE_CXX_STANDARD_COMPUTED_DEFAULT 17)
if(NOT TARGET Threads::Threads)
  add_library(Threads::Threads INTERFACE IMPORTED)
  set_target_properties(Threads::Threads PROPERTIES
    INTERFACE_COMPILE_OPTIONS "-pthread"
    INTERFACE_LINK_LIBRARIES "-pthread")
endif()
set(Threads_FOUND TRUE)
set(CMAKE_THREAD_LIBS_INIT "-pthread")
if(ALSA_LIBRARY AND NOT TARGET ALSA::ALSA)
  add_library(ALSA::ALSA UNKNOWN IMPORTED)
  set_target_properties(ALSA::ALSA PROPERTIES
    IMPORTED_LOCATION "${ALSA_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${ALSA_INCLUDE_DIR}")
endif()

# Absolute no-probe: load the feature-test modules once, then replace
# every check_* command with a table lookup.  Nothing is compiled or
# executed and nothing is printed by these commands.
include(CheckIncludeFile OPTIONAL)
include(CheckIncludeFiles OPTIONAL)
include(CheckIncludeFileCXX OPTIONAL)
include(CheckSymbolExists OPTIONAL)
include(CheckCXXSymbolExists OPTIONAL)
include(CheckFunctionExists OPTIONAL)
include(CheckLibraryExists OPTIONAL)
include(CheckStructHasMember OPTIONAL)
include(CheckTypeSize OPTIONAL)
include(CheckCSourceCompiles OPTIONAL)
include(CheckCXXSourceCompiles OPTIONAL)
include(CheckCSourceRuns OPTIONAL)
include(CheckCXXSourceRuns OPTIONAL)
include(CheckSourceCompiles OPTIONAL)
include(CheckSourceRuns OPTIONAL)
include(CheckCCompilerFlag OPTIONAL)
include(CheckCXXCompilerFlag OPTIONAL)
include(CheckCompilerFlag OPTIONAL)
include(CheckLinkerFlag OPTIONAL)
include(CheckVariableExists OPTIONAL)
include(CheckFortranSourceCompiles OPTIONAL)
include(CheckFortranSourceRuns OPTIONAL)
include(CheckFortranFunctionExists OPTIONAL)

macro(gcpkg_probe_result _gcpkg_varname)
  if("${_gcpkg_varname}" IN_LIST GCPKG_TRUE_RESULTS)
    set(${_gcpkg_varname} TRUE)
  elseif(DEFINED ${_gcpkg_varname} AND NOT "${${_gcpkg_varname}}" STREQUAL "")
    set(${_gcpkg_varname} "${${_gcpkg_varname}}")
  else()
    set(${_gcpkg_varname} FALSE)
  endif()
endmacro()

macro(check_include_file _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_include_file_cxx _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_function_exists _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_variable_exists _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_c_source_compiles _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_cxx_source_compiles _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_c_source_runs _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_cxx_source_runs _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_c_compiler_flag _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_cxx_compiler_flag _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_fortran_source_compiles _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_fortran_source_runs _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_fortran_function_exists _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
endmacro()
macro(check_symbol_exists _gcpkg_a0 _gcpkg_a1 _gcpkg_a2)
  gcpkg_probe_result(${_gcpkg_a2})
endmacro()
macro(check_cxx_symbol_exists _gcpkg_a0 _gcpkg_a1 _gcpkg_a2)
  gcpkg_probe_result(${_gcpkg_a2})
endmacro()
macro(check_source_compiles _gcpkg_a0 _gcpkg_a1 _gcpkg_a2)
  gcpkg_probe_result(${_gcpkg_a2})
endmacro()
macro(check_source_runs _gcpkg_a0 _gcpkg_a1 _gcpkg_a2)
  gcpkg_probe_result(${_gcpkg_a2})
endmacro()
macro(check_compiler_flag _gcpkg_a0 _gcpkg_a1 _gcpkg_a2)
  gcpkg_probe_result(${_gcpkg_a2})
endmacro()
macro(check_linker_flag _gcpkg_a0 _gcpkg_a1 _gcpkg_a2)
  gcpkg_probe_result(${_gcpkg_a2})
endmacro()
macro(check_library_exists _gcpkg_a0 _gcpkg_a1 _gcpkg_a2 _gcpkg_a3)
  gcpkg_probe_result(${_gcpkg_a3})
endmacro()
macro(check_struct_has_member _gcpkg_a0 _gcpkg_a1 _gcpkg_a2 _gcpkg_a3)
  gcpkg_probe_result(${_gcpkg_a3})
endmacro()
macro(check_type_size _gcpkg_a0 _gcpkg_a1)
  gcpkg_probe_result(${_gcpkg_a1})
  set(HAVE_${_gcpkg_a1} ${${_gcpkg_a1}})
endmacro()
macro(check_include_files)
  set(_gcpkg_last "")
  foreach(_gcpkg_item ${ARGV})
    set(_gcpkg_last "${_gcpkg_item}")
  endforeach()
  gcpkg_probe_result(${_gcpkg_last})
endmacro()

# try_run is a probe too: give the table result, never compile or execute.
function(try_run run_var compile_var)
  if("${compile_var}" IN_LIST GCPKG_TRUE_RESULTS)
    set(${compile_var} TRUE PARENT_SCOPE)
    set(${run_var} 0 PARENT_SCOPE)
  else()
    set(${compile_var} FALSE PARENT_SCOPE)
    set(${run_var} 1 PARENT_SCOPE)
  endif()
endfunction()
function(try_compile result_var)
  if("${result_var}" IN_LIST GCPKG_TRUE_RESULTS)
    set(${result_var} TRUE PARENT_SCOPE)
  elseif(DEFINED ${result_var} AND NOT "${${result_var}}" STREQUAL "")
    set(${result_var} "${${result_var}}" PARENT_SCOPE)
  else()
    set(${result_var} FALSE PARENT_SCOPE)
  endif()
endfunction()
]==]
        noTry = util.join(build, "gcpkg-no-try-compile.cmake")
        fs.write(noTry, includeText)
    end
    local baseEnv = o.env
    local env = policy_env(baseEnv)
    local cmd = { "cmake", "-S", o.src, "-B", build,
                  "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
                  "-DCMAKE_INSTALL_PREFIX=" .. (o.prefix or util.join(build, "install")) }
    if disableTry then
        cmd[#cmd + 1] = "-DCMAKE_PROJECT_INCLUDE=" .. noTry
        -- CMake's own compiler test also uses try_compile.  FORCED makes
        -- CMakeTestCCompiler return immediately instead of launching another
        -- nested project; gcpkg has already selected and validated the compiler.
        cmd[#cmd + 1] = "-DCMAKE_C_COMPILER_FORCED=TRUE"
        cmd[#cmd + 1] = "-DCMAKE_C_COMPILER_WORKS=TRUE"
        cmd[#cmd + 1] = "-DCMAKE_CXX_COMPILER_FORCED=TRUE"
        cmd[#cmd + 1] = "-DCMAKE_CXX_COMPILER_WORKS=TRUE"
    end
    local args = o.args or {}
    local chainloads = {}
    if o.toolchain then chainloads[#chainloads + 1] = o.toolchain end
    for _, a in ipairs(args) do
        local t = toolchain_from_arg(a)
        if t then chainloads[#chainloads + 1] = t end
    end
    if defines.CMAKE_TOOLCHAIN_FILE then
        chainloads[#chainloads + 1] = tostring(defines.CMAKE_TOOLCHAIN_FILE)
    end
    local cacheChain = cache_toolchain(args)
    if cacheChain then chainloads[#chainloads + 1] = cacheChain end
    local crossArgs = toolchain.cmake_args({
        chainload = chainloads, compiler_from_env = true,
    })
    local policy_set = defines.CMAKE_POLICY_VERSION_MINIMUM ~= nil or
                       (baseEnv and baseEnv.CMAKE_POLICY_VERSION_MINIMUM ~= nil and
                        baseEnv.CMAKE_POLICY_VERSION_MINIMUM ~= "")
    for _, a in ipairs(args) do
        if define_key(a) == "CMAKE_POLICY_VERSION_MINIMUM" then
            policy_set = true
        end
    end
    local policy = cmake_version.policy_arg()
    if policy and not policy_set then
        cmd[#cmd + 1] = policy
    end
    if o.generator then
        cmd[#cmd + 1] = "-G"
        cmd[#cmd + 1] = o.generator
    end
    if o.toolchain and not toolchain.is_cross() then
        cmd[#cmd + 1] = "-DCMAKE_TOOLCHAIN_FILE=" .. o.toolchain
    end
    for _, k in ipairs(util.keys(defines)) do
        cmd[#cmd + 1] = "-D" .. k .. "=" .. tostring(defines[k])
    end
    for _, a in ipairs(args) do
        cmd[#cmd + 1] = tostring(a)
    end
    -- Cross toolchain comes last: dedup_defines keeps it, and it chain-loads
    -- any port/project toolchain instead of dropping dependency injection.
    for _, a in ipairs(crossArgs) do
        cmd[#cmd + 1] = tostring(a)
    end
    exec(dedup_defines(cmd), { cwd = o.src, log = o.log, env = env })
    return build
end

function M.build(o)
    local exec = o.exec or gcpkg.exec
    local build = util.abs(o.build_dir or util.join(o.src, "build"), o.src)
    local cmd = { "cmake", "--build", build, "--parallel",
                  tostring(o.jobs or gcpkg.sys.nproc()) }
    for _, t in ipairs(o.targets or {}) do
        cmd[#cmd + 1] = "--target"
        cmd[#cmd + 1] = t
    end
    exec(cmd, { cwd = o.src, log = o.log, env = policy_env(o.env) })
    return build
end

function M.install(o)
    local exec = o.exec or gcpkg.exec
    local build = util.abs(o.build_dir or util.join(o.src, "build"), o.src)
    local cmd = { "cmake", "--install", build }
    if o.prefix then
        cmd[#cmd + 1] = "--prefix"
        cmd[#cmd + 1] = o.prefix
    end
    exec(cmd, { cwd = o.src, log = o.log, env = policy_env(o.env) })
    return build
end

function M.all(o)
    local build = M.configure(o)
    o = util.merge(o, { build_dir = build })
    M.build(o)
    M.install(o)
    return { compdb_files = { util.join(build, "compile_commands.json") } }
end

return M
