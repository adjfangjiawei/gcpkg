-- Compilation database handling.
--
-- Sources of entries:
--   1. gcpkg-intercept (CC/CXX wrapper) logs every real compile invocation of
--      an unmodified upstream build system into a JSONL file.
--   2. gcpkg.build.cc records the commands it issues for project sources.
--   3. External build systems that emit compile_commands.json themselves
--      (CMake, Meson, Bear, ...) are imported verbatim.
--
-- All of them are normalised to clangd entries with absolute `file` paths and
-- merged into the project's compile_commands.json together with every
-- transitive dependency's entries. That is the piece vcpkg-style package
-- managers lack: clangd gets commands for dependency .c/.h files too, so
-- go-to-definition keeps working across library boundaries.
local fs = require("gcpkg.fs")
local json = require("gcpkg.json")
local util = require("gcpkg.util")
local M = {}

local SOURCE_EXT = {
    c = true, cc = true, cpp = true, cxx = true, C = true, m = true, mm = true,
    i = true, ii = true, cu = true, cuh = true,
}

-- Build systems disagree about argument order:
--   cc -c foo.c -o foo.o                       (source right after -c)
--   cc -c -o foo.o -I. ... foo.c               (OpenSSL: source at the end)
-- Prefer the last non-flag argument with a source extension, then fall back
-- to the argument after -c when that is actually a file (never "-o").
local function findSource(args)
    local last
    for i = 2, #args do
        local a = args[i]
        if a:sub(1, 1) ~= "-" and SOURCE_EXT[util.ext(a)] then
            last = a
        end
    end
    if last then
        return last
    end
    for i = 1, #args - 1 do
        if args[i] == "-c" and args[i + 1] and args[i + 1]:sub(1, 1) ~= "-" then
            return args[i + 1]
        end
    end
    return nil
end

local function findOutput(args)
    for i = 1, #args - 1 do
        if args[i] == "-o" then
            return args[i + 1]
        end
    end
end

function M.normalize(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local args = entry.arguments
    if not args and entry.command then
        args = util.shellsplit(entry.command)
    end
    if type(args) ~= "table" or #args == 0 then
        return nil
    end

    local hasCompile = false
    local preprocessOnly = false
    for _, a in ipairs(args) do
        if a == "-c" then
            hasCompile = true
        elseif a == "-E" or a == "-M" or a == "-MM" then
            preprocessOnly = true
        end
    end
    if preprocessOnly and not hasCompile then
        return nil
    end

    local src = entry.file or findSource(args)
    if not src or src == "" then
        return nil
    end
    local directory = entry.directory or fs.cwd()
    local file = util.abs(src, directory)

    -- Configure-time compiler probes often use temporary conftest files that
    -- are deleted immediately; they must not end up in the database.
    if not fs.isfile(file) then
        return nil
    end

    local normalized = {
        directory = directory,
        file = file,
        arguments = args,
        output = entry.output or findOutput(args),
        tag = entry.tag,
    }
    return normalized
end

function M.record(path, entry)
    local normalized = M.normalize(entry)
    if normalized then
        fs.append(path, json.encode(normalized) .. "\n")
    end
    return normalized
end

local function readJsonl(path)
    local out = {}
    for _, line in ipairs(fs.lines(path)) do
        line = util.trim(line)
        if line ~= "" then
            local ok, value = pcall(json.decode, line)
            if ok then
                local n = M.normalize(value)
                if n then
                    out[#out + 1] = n
                end
            else
                gcpkg.log.warn("skipping malformed compdb line in " .. path)
            end
        end
    end
    return out
end

local function readJsonArray(path)
    local text = fs.read(path)
    if not text then
        return {}
    end
    local ok, value = pcall(json.decode, text)
    if not ok or type(value) ~= "table" then
        gcpkg.log.warn("cannot parse compilation database " .. path)
        return {}
    end
    local out = {}
    for _, entry in ipairs(value) do
        local n = M.normalize(entry)
        if n then
            out[#out + 1] = n
        end
    end
    return out
end

function M.read(path, kind)
    if not path or not fs.isfile(path) then
        return {}
    end
    if kind == "json" or util.endswith(path, ".json") then
        return readJsonArray(path)
    end
    return readJsonl(path)
end

function M.dedup(entries)
    local seen, out = {}, {}
    for _, e in ipairs(entries) do
        local key = e.file .. "\0" .. table.concat(e.arguments, "\0")
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = e
        end
    end
    return out
end

-- clangd's JSON parser is strict: only directory/file/(command|arguments)/
-- output are allowed. Internal bookkeeping (tag, output) stays in our JSONL
-- but is stripped from the emitted compile_commands.json.
function M.clean(entry)
    return {
        directory = entry.directory,
        file = entry.file,
        arguments = entry.arguments,
    }
end

function M.write(entries, path)
    entries = M.dedup(entries)
    local emitted = {}
    for i, entry in ipairs(entries) do
        emitted[i] = M.clean(entry)
    end
    fs.write(path, json.encode(emitted, true) .. "\n")
    return entries
end

-- Writes a clangd fragment that adds all dependency include dirs to every
-- translation unit. compile_commands.json already carries the per-file flags;
-- this is belt-and-braces for editors that open headers directly.
function M.write_clangd(project_dir, includes, extra_flags)
    local lines = {
        "# Generated by gcpkg -- do not edit by hand.",
        "# Keeps clangd aware of dependency include paths while editing.",
        "CompileFlags:",
        "  Add:",
    }
    for _, dir in ipairs(util.uniq(includes or {})) do
        lines[#lines + 1] = "    - '-I" .. dir .. "'"
    end
    for _, flag in ipairs(extra_flags or {}) do
        lines[#lines + 1] = "    - '" .. flag .. "'"
    end
    if #lines == 4 then
        lines[#lines + 1] = "    []"
    end
    fs.write(util.join(project_dir, ".clangd"), table.concat(lines, "\n") .. "\n")
end

function M.summary(entries)
    local dirs = {}
    for _, e in ipairs(entries) do
        dirs[util.dirname(e.file)] = true
    end
    return #entries .. " compile commands across " .. #util.keys(dirs) .. " source directories"
end

return M
