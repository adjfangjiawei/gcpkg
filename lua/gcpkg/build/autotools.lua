local util = require("gcpkg.util")
local toolchain = require("gcpkg.toolchain")
local M = {}

function M.configure(o)
    local exec = o.exec or gcpkg.exec
    local cwd = o.cwd or o.src
    local cmd = { o.configure or util.join(o.src, "configure"),
                  "--prefix=" .. (o.prefix or "/usr/local") }
    for _, a in ipairs(o.args or {}) do
        cmd[#cmd + 1] = tostring(a)
    end
    for _, a in ipairs(toolchain.autotools_args()) do
        cmd[#cmd + 1] = a
    end
    exec(cmd, { cwd = cwd, log = o.log, env = o.env })
end

-- WSL/Windows mounts can give release-tarball generated files an mtime older
-- than configure.ac / Makefile.am. Without this, `make` tries to regenerate
-- them with a versioned aclocal/automake that is not installed as a system
-- package. Touch only generated files, never their .ac/.am/.m4 sources.
function M.fix_timestamps(o)
    local exec = o.exec or gcpkg.exec
    local fs = require("gcpkg.fs")
    local src = o.src
    if not (fs.isfile(util.join(src, "aclocal.m4")) or
            fs.isfile(util.join(src, "Makefile.in"))) then
        return
    end
    local script = util.join(src, ".gcpkg-autotools-timestamps.sh")
    fs.write(script, [=[
#!/bin/sh
set -e
cd "$1" || exit 1
find . -type f \( -name 'aclocal.m4' -o -name 'configure' \
     -o -name 'config.h.in' -o -name 'config.h.in~' -o -name 'Makefile.in' \
     -o -name 'config.guess' -o -name 'config.sub' -o -name 'ltmain.sh' \
     -o -name 'missing' -o -name 'compile' -o -name 'depcomp' \
     -o -name 'install-sh' -o -name 'test-driver' -o -name 'mkinstalldirs' \
     \) -exec touch {} +
for f in aclocal.m4 configure config.h.in; do
    if [ -f "$f" ]; then
        touch "$f"
    fi
done
find . -name 'Makefile.in' -exec touch {} +
# Some autotools release tarballs ship PlantUML documentation sources without
# the generated SVG files, and their doc Makefile has an unconditional all
# target that invokes plantuml. Create the generated placeholders here (after
# configure, before make) rather than taking a Java/system-package dependency.
find . -type f -name '*.puml' -print | while IFS= read -r f; do
    svg=${f%.puml}.svg
    if [ ! -f "$svg" ]; then
        : > "$svg"
    fi
    touch "$svg"
done
]=])
    exec({ "bash", script, src },
         { cwd = src, log = o.log, env = o.env })
end

function M.all(o)
    M.configure(o)
    M.fix_timestamps(o)
    local make = require("gcpkg.build.make")
    local base = util.merge(o, { cwd = o.cwd or o.src })
    make.run(util.merge(base, { targets = o.targets or {} }))
    make.run(util.merge(base, { targets = { o.install_target or "install" } }))
    return {}
end

return M
