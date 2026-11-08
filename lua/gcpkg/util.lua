local U = {}

function U.isabs(p)
    return tostring(p):sub(1, 1) == "/"
end

-- Path join with '.' / '..' resolution. Pure string math: no chdir needed.
function U.join(...)
    local n = select("#", ...)
    local parts = {}
    local first = tostring(select(1, ...) or "")
    for i = 1, n do
        local v = tostring(select(i, ...) or "")
        for seg in v:gmatch("[^/]+") do
            if seg == ".." then
                if #parts > 0 and parts[#parts] ~= ".." then
                    table.remove(parts)
                else
                    parts[#parts + 1] = seg
                end
            elseif seg ~= "." then
                parts[#parts + 1] = seg
            end
        end
    end
    local prefix = U.isabs(first) and "/" or ""
    return prefix .. table.concat(parts, "/")
end

function U.abs(p, base)
    if U.isabs(p) then
        return U.join(p)
    end
    return U.join(base or gcpkg.sys.cwd(), p)
end

function U.basename(p)
    return tostring(p):match("([^/]+)/?$") or ""
end

function U.dirname(p)
    local d = tostring(p):match("^(.*)/[^/]+/?$")
    if not d or d == "" then
        return U.isabs(p) and "/" or "."
    end
    return d
end

function U.ext(p)
    return tostring(p):match("%.([%w]+)$") or ""
end

function U.stem(p)
    local b = U.basename(p)
    local e = U.ext(b)
    if e == "" then
        return b
    end
    return b:sub(1, #b - #e - 1)
end

function U.split(s, sep)
    s = tostring(s)
    local out = {}
    if not sep or sep == "%s+" then
        for piece in s:gmatch("%S+") do
            out[#out + 1] = piece
        end
    else
        local start = 1
        while true do
            local a, b = s:find(sep, start, true)
            if not a then
                out[#out + 1] = s:sub(start)
                break
            end
            out[#out + 1] = s:sub(start, a - 1)
            start = b + 1
        end
    end
    return out
end

function U.lines(s)
    local out = {}
    for line in tostring(s):gmatch("[^\r\n]+") do
        out[#out + 1] = line
    end
    return out
end

function U.trim(s)
    local out = tostring(s):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

function U.startswith(s, p)
    return tostring(s):sub(1, #p) == p
end

function U.endswith(s, p)
    return tostring(s):sub(-#p) == p
end

function U.contains(list, value)
    if type(list) ~= "table" then
        return false
    end
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

function U.map(list, fn)
    local out = {}
    for i, v in ipairs(list or {}) do
        out[i] = fn(v, i)
    end
    return out
end

function U.filter(list, fn)
    local out = {}
    for _, v in ipairs(list or {}) do
        if fn(v) then
            out[#out + 1] = v
        end
    end
    return out
end

function U.concat(...)
    local out = {}
    for i = 1, select("#", ...) do
        for _, v in ipairs(select(i, ...) or {}) do
            out[#out + 1] = v
        end
    end
    return out
end

function U.keys(t)
    local out = {}
    for k in pairs(t or {}) do
        out[#out + 1] = k
    end
    table.sort(out, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return out
end

function U.sorted_list(t)
    local out = {}
    for _, v in pairs(t or {}) do
        out[#out + 1] = tostring(v)
    end
    table.sort(out)
    return out
end

function U.uniq(list)
    local seen, out = {}, {}
    for _, v in ipairs(list or {}) do
        if not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    return out
end

-- Shallow map merge; later tables win.
function U.merge(...)
    local out = {}
    for i = 1, select("#", ...) do
        for k, v in pairs(select(i, ...) or {}) do
            out[k] = v
        end
    end
    return out
end

function U.deepcopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[U.deepcopy(k)] = U.deepcopy(x)
    end
    return out
end

-- Minimal shell-word splitter, used for legacy "command": strings in
-- externally produced compile_commands.json files (CMake, Bear, ...).
function U.shellsplit(s)
    local out, cur, quote = {}, "", nil
    local i = 1
    while i <= #s do
        local ch = s:sub(i, i)
        if quote then
            if ch == quote then
                quote = nil
            elseif ch == "\\" and quote == '"' and i < #s then
                i = i + 1
                cur = cur .. s:sub(i, i)
            else
                cur = cur .. ch
            end
        elseif ch == '"' or ch == "'" then
            quote = ch
        elseif ch:match("%s") then
            if cur ~= "" then
                out[#out + 1] = cur
                cur = ""
            end
        elseif ch == "\\" and i < #s then
            i = i + 1
            cur = cur .. s:sub(i, i)
        else
            cur = cur .. ch
        end
        i = i + 1
    end
    if cur ~= "" then
        out[#out + 1] = cur
    end
    return out
end

return U
