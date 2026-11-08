local fs = require("gcpkg.fs")
local M = {}

function M.parse(text)
    local value = gcpkg.sys.yaml_parse(text)
    if type(value) == "table" then
        return value
    end
    return {}
end

function M.parse_file(path)
    local text = fs.read(path)
    if not text then
        return nil
    end
    return M.parse(text)
end

return M
