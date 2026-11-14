local M = {}

local function emit(level, ...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    gcpkg.sys.log(level, table.concat(parts, " "))
end

function M.info(...)
    emit("info", ...)
end

function M.step(...)
    emit("step", ...)
end

function M.warn(...)
    emit("warn", ...)
end

function M.error(...)
    emit("error", ...)
end

function M.debug(...)
    if gcpkg.sys.getenv("GCPKG_DEBUG") then
        emit("debug", ...)
    end
end

return M
