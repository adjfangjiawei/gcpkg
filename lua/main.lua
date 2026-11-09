-- Bootstrap. `gcpkg` is the sandbox-wide table created by the C++ runtime;
-- `gcpkg.sys` holds the audited OS primitives. Everything below this line is
-- ordinary, replaceable Lua code.
local util = require("gcpkg.util")

gcpkg.util = util
gcpkg.path = util.join
gcpkg.fs = require("gcpkg.fs")
gcpkg.log = require("gcpkg.log")
local toolchain = require("gcpkg.toolchain")
gcpkg.toolchain = toolchain
-- sys.compiler is the single compiler knob; the C++ fallback never picks gcc.
gcpkg.sys.compiler = toolchain.compiler
local exec = require("gcpkg.exec")
gcpkg.exec = exec.run
gcpkg.capture = exec.capture
gcpkg.have = exec.have
gcpkg.json = require("gcpkg.json")
gcpkg.yaml = require("gcpkg.yaml")
gcpkg.compdb = require("gcpkg.compdb")
gcpkg.features = require("gcpkg.features")
gcpkg.store = require("gcpkg.store")
gcpkg.port = require("gcpkg.port")
gcpkg.project = require("gcpkg.project")
gcpkg.backends = require("gcpkg.backends")
gcpkg.detect = require("gcpkg.detect")
gcpkg.recipe = require("gcpkg.recipe")
gcpkg.graph = require("gcpkg.graph")

-- "One library's build may include another": import another port's build.lua
-- as a normal Lua value (its table/hooks/helpers are then reusable). Loaded
-- through sys.loadchunk, so it runs in exactly the same sandbox.
gcpkg.import = function(name)
    local dir = gcpkg.port.find(name)
    if not dir then
        error("gcpkg.import: port '" .. tostring(name) .. "' not found")
    end
    return gcpkg.sys.loadchunk(util.join(dir, "build.lua"))
end

local M = {}

function M.run(args)
    local cli = require("gcpkg.cli")
    local ok, result = pcall(cli.main, args)
    if not ok then
        gcpkg.log.error(tostring(result))
        return 1
    end
    return result or 0
end

return M
