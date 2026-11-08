-- Python packaging adapter (setup.py / pip), driven exactly like every other
-- build system: exec through gcpkg so proxy env, compiler interception and the
-- build log all apply. Pure-Python packages produce no compile commands;
-- C extensions built by setuptools pick up CC/CXX from ctx.env and therefore
-- do land in the compile database.
--
-- Everything installs into <prefix>/lib/python3/site-packages. That path is
-- already collected by port.dependency_env() into PYTHONPATH for downstream
-- ports, and by project.lua for project builds.
local util = require("gcpkg.util")
local M = {}

function M.all(o)
    local exec = o.exec or gcpkg.exec
    local python = o.python or "python3"
    local site = util.join(o.prefix, "lib", "python3", "site-packages")
    local function run(args, cwd)
        exec(args, { cwd = cwd or o.src, log = o.log, env = o.env })
    end
    run({ "mkdir", "-p", site })

    if o.mode == "pip" then
        -- --target is used instead of --prefix: pip's --prefix still nests
        -- packages under lib/pythonX.Y/site-packages, which would break the
        -- stable PYTHONPATH contract above.
        -- PEP 517 build isolation pulls setuptools/wheel into a temporary
        -- env (a freshly built CPython only bundles pip). Set
        -- no_isolation=true when the interpreter already has them.
        local cmd = { python, "-m", "pip", "install", "--no-deps" }
        if o.no_isolation then cmd[#cmd + 1] = "--no-build-isolation" end
        cmd[#cmd + 1] = "--target"; cmd[#cmd + 1] = site; cmd[#cmd + 1] = "."
        for _, a in ipairs(o.args or {}) do
            cmd[#cmd + 1] = tostring(a)
        end
        run(cmd)
    else
        local build = { python, "setup.py", "build" }
        for _, a in ipairs(o.args or {}) do
            build[#build + 1] = tostring(a)
        end
        run(build)
        run({ python, "setup.py", "install",
              "--prefix=" .. o.prefix,
              "--install-lib=" .. site,
              "--single-version-externally-managed",
              "--record=" .. util.join(o.prefix, "install-record.txt") })
    end
    return { pythonpath = { site }, libdirs = {}, includes = {} }
end

return M
