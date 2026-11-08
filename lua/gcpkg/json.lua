-- Dependency-free JSON codec. Used for manifests and compile_commands.json.
-- (No external Lua rocks: gcpkg must build with only liblua + libyaml-cpp.)
local M = {}

local function quote(s)
    local out = {'"'}
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = s:byte(i)
        if c == '"' then
            out[#out + 1] = '\\"'
        elseif c == "\\" then
            out[#out + 1] = "\\\\"
        elseif c == "\n" then
            out[#out + 1] = "\\n"
        elseif c == "\r" then
            out[#out + 1] = "\\r"
        elseif c == "\t" then
            out[#out + 1] = "\\t"
        elseif b < 32 then
            out[#out + 1] = string.format("\\u%04x", b)
        else
            out[#out + 1] = c
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false, 0
        end
        n = math.max(n, k)
    end
    for i = 1, n do
        if t[i] == nil then
            return false, 0
        end
    end
    return true, n
end

local function pad(level)
    return string.rep("  ", level or 0)
end

local function encodeValue(v, level, pretty)
    local t = type(v)
    if v == nil then
        return "null"
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 2 ^ 52 then
            return string.format("%d", v)
        end
        return tostring(v)
    elseif t == "string" then
        return quote(v)
    elseif t == "table" then
        if next(v) == nil then
            return "{}"
        end
        local array, n = isArray(v)
        local parts = {}
        if array then
            for i = 1, n do
                parts[i] = encodeValue(v[i], level + 1, pretty)
            end
            if pretty then
                return "[\n" .. pad(level + 1) .. table.concat(parts, ",\n" .. pad(level + 1)) ..
                    "\n" .. pad(level) .. "]"
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = tostring(k)
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = quote(k) .. ": " .. encodeValue(v[k], level + 1, pretty)
        end
        if pretty then
            return "{\n" .. pad(level + 1) .. table.concat(parts, ",\n" .. pad(level + 1)) ..
                "\n" .. pad(level) .. "}"
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("json.encode: unsupported type " .. t)
end

function M.encode(v, pretty)
    return encodeValue(v, 0, pretty)
end

local function decode(str)
    local pos = 1
    local function skip()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end
    local function fail(msg)
        error("json.decode: " .. msg .. " at byte " .. pos, 0)
    end
    local function parseString()
        pos = pos + 1 -- opening quote
        local out = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(out)
            elseif c == "\\" then
                pos = pos + 1
                local e = str:sub(pos, pos)
                local simple = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
                                 f = "\f", n = "\n", r = "\r", t = "\t" }
                if e == "u" then
                    local hex = str:sub(pos + 1, pos + 4)
                    local cp = tonumber(hex, 16)
                    if not cp then
                        fail("bad unicode escape")
                    end
                    out[#out + 1] = utf8.char(cp)
                    pos = pos + 5
                elseif simple[e] then
                    out[#out + 1] = simple[e]
                    pos = pos + 1
                else
                    fail("bad escape \\" .. e)
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        fail("unterminated string")
    end
    local parseValue
    local function parseObject()
        pos = pos + 1
        local out = {}
        skip()
        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return out
        end
        while true do
            skip()
            if str:sub(pos, pos) ~= '"' then
                fail("expected object key")
            end
            local key = parseString()
            skip()
            if str:sub(pos, pos) ~= ":" then
                fail("expected ':'")
            end
            pos = pos + 1
            out[key] = parseValue()
            skip()
            local c = str:sub(pos, pos)
            pos = pos + 1
            if c == "}" then
                return out
            elseif c ~= "," then
                fail("expected ',' or '}'")
            end
        end
    end
    local function parseArray()
        pos = pos + 1
        local out = {}
        skip()
        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return out
        end
        while true do
            out[#out + 1] = parseValue()
            skip()
            local c = str:sub(pos, pos)
            pos = pos + 1
            if c == "]" then
                return out
            elseif c ~= "," then
                fail("expected ',' or ']'")
            end
        end
    end
    parseValue = function()
        skip()
        local c = str:sub(pos, pos)
        if c == '"' then
            return parseString()
        elseif c == "{" then
            return parseObject()
        elseif c == "[" then
            return parseArray()
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local num = str:match("^-?%d+%.?%d*[eE][-+]?%d+", pos) or
                        str:match("^-?%d+%.?%d*", pos)
            if not num then
                fail("unexpected character '" .. c .. "'")
            end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local result = parseValue()
    return result
end

function M.decode(str)
    return decode(tostring(str))
end

return M
