local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local features = require("gcpkg.features")
local M = {}

local USAGE = [[
gcpkg ]] .. (gcpkg.version or "") .. [[ -- Lua-described meta package manager

Usage:
  gcpkg build [PROJECT_DIR]        build a project (gcpkg.lua + gcpkg.yaml)
  gcpkg install PORT[@VERSION]     build & install a library into the store
  gcpkg compdb [PROJECT_DIR]       rebuild merged compile_commands.json only
  gcpkg features PORT              list a library's YAML features
  gcpkg backends                   list external package-manager adapters
  gcpkg doctor                     show toolchain / paths / wrapper status
  gcpkg port new NAME              scaffold build.lua + features.yaml

Options:
  --store=DIR                     package store (default $GCPKG_HOME or ~/.gcpkg)
  --ports=DIR[:DIR...]            port registry roots
  --share=DIR                     engine root (contains lua/ and ports/)
  --feature=PORT:NAME, -f ...     enable a feature (prefix '-' disables it)
  -j N, --jobs=N                  parallel jobs
  --no-cache                      force rebuild even if the store is fresh
  --verbose                       print every executed command
  -h, --help                      this help

Examples:
  gcpkg build examples/hello --store /tmp/gcpkg-store
  gcpkg install openssl --feature=openssl:shared
  gcpkg compdb . --ports ./ports:~/my-ports
  gcpkg backends
]]

local function parse(args)
    local o = {
        requests = {}, jobs = gcpkg.sys.nproc(), no_cache = false, help = false,
        positional = {},
    }
    local i = 1
    while i <= #args do
        local a = args[i]
        local function nextval()
            i = i + 1
            if not args[i] then
                error("missing value for " .. a)
            end
            return args[i]
        end
        if a == "-h" or a == "--help" then
            o.help = true
        elseif a == "--verbose" or a == "-v" then
            o.verbose = true
        elseif a == "--no-cache" then
            o.no_cache = true
        elseif a:match("^--store=") then
            o.store = a:match("^--store=(.*)$")
        elseif a == "--store" then
            o.store = nextval()
        elseif a:match("^--ports=") then
            o.ports = a:match("^--ports=(.*)$")
        elseif a == "--ports" then
            o.ports = nextval()
        elseif a:match("^--share=") then
            o.share = a:match("^--share=(.*)$")
        elseif a == "--share" then
            o.share = nextval()
        elseif a:match("^--feature=") then
            features.add_request(o.requests, a:match("^--feature=(.*)$"))
        elseif a == "--feature" or a == "-f" then
            features.add_request(o.requests, nextval())
        elseif a:match("^--jobs=") then
            o.jobs = tonumber(a:match("^--jobs=(.*)$")) or o.jobs
        elseif a == "--jobs" or a == "-j" then
            o.jobs = tonumber(nextval()) or o.jobs
        elseif a:match("^%-j%d+$") then
            o.jobs = tonumber(a:match("^%-j(%d+)$"))
        else
            o.positional[#o.positional + 1] = a
        end
        i = i + 1
    end
    return o
end

local BUILD_TEMPLATE = [[-- %s: ONE build description for ONE library.
-- Everything here is ordinary Lua: require() other build modules, import()
-- another port, or define your own helpers.
local make = require("gcpkg.build.make")

return {
  name = "%s",
  version = "0.0.0",
  source = {
    url = "https://example.com/%s-0.0.0.tar.gz",
    sha256 = nil,
    strip = 1,
  },
  dependencies = {},

  build = function(ctx)
    -- ctx.src / ctx.build_dir / ctx.prefix / ctx.exec / ctx.features /
    -- ctx.feature_args() / ctx.record() / ctx.compiler / ctx.jobs
    -- Any build system works; this template assumes ./configure && make.
    ctx.exec({ "./configure", "--prefix=" .. ctx.prefix })
    make.install({ cwd = ctx.src, exec = ctx.exec, log = ctx.log, jobs = ctx.jobs })

    return {
      includes = { ctx.prefix .. "/include" },
      libdirs  = { ctx.prefix .. "/lib" },
      libs     = { "%s" },
    }
  end,
}
]]

local FEATURES_TEMPLATE = [[schema: 1
port: %s
# ONE feature description per library. Enabled features inject args/env/
# defines/requires into the build without editing build.lua.
features:
  shared:
    default: false
    description: build shared libraries
    args: ["--enable-shared"]
  tests:
    default: false
    description: build the test suite
    args: ["--with-tests"]
]]

local function doctor(cfg, o)
    local log = require("gcpkg.log")
    log.info("gcpkg " .. (gcpkg.version or "") .. " | " .. gcpkg.sys.os() ..
             "/" .. gcpkg.sys.arch() .. " | " .. gcpkg.sys.nproc() .. " cores")
    log.info("engine (GCPKG_SHARE): " .. gcpkg.sys.share())
    log.info("lua root            : " .. gcpkg.sys.lua_root())
    log.info("store               : " .. cfg.store.root)
    log.info("ports roots         : " .. table.concat(cfg.ports, " : "))
    local wrapper = gcpkg.sys.wrapper_bin()
    log.info("compiler interceptor: " .. wrapper ..
             (fs.isfile(wrapper) and " [ok]" or " [MISSING]"))
    for _, tool in ipairs({ "cc", "c++", "make", "cmake", "perl", "curl", "tar",
                            "pkg-config", "ninja", "meson", "git" }) do
        log.info(string.format("  %-12s %s", tool, gcpkg.have(tool) and "ok" or "missing"))
    end
    return 0
end

function M.main(args)
    local o = parse(args or gcpkg.args)
    if o.verbose then
        gcpkg.sys.set_verbose(true)
    end
    if o.help or #o.positional == 0 then
        print(USAGE)
        return 0
    end

    local port = require("gcpkg.port")
    local storeMod = require("gcpkg.store")
    local log = require("gcpkg.log")
    local roots = o.ports and util.split(o.ports, ":") or port.default_roots()
    port.set_roots(roots)
    local home = os.getenv("HOME") or fs.cwd()
    local storeRoot = o.store or os.getenv("GCPKG_HOME") or util.join(home, ".gcpkg")
    local st = storeMod.new(util.abs(storeRoot))
    gcpkg.sys.add_root(util.join(st.root, "lua"))
    local cfg = {
        store = st, ports = roots, requests = o.requests, jobs = o.jobs,
        no_cache = o.no_cache, share = o.share or gcpkg.sys.share(),
    }

    local cmd = o.positional[1]
    if cmd == "doctor" then
        return doctor(cfg, o)
    elseif cmd == "build" then
        require("gcpkg.project").build(o.positional[2] or fs.cwd(), cfg, {})
        return 0
    elseif cmd == "compdb" then
        require("gcpkg.project").build(o.positional[2] or fs.cwd(), cfg, { skip_build = true })
        return 0
    elseif cmd == "install" then
        if not o.positional[2] then
            error("install needs a port name")
        end
        local m = port.install(o.positional[2], cfg)
        log.info("manifest: " .. storeMod.manifest_path(st, m.key))
        return 0
    elseif cmd == "features" then
        if not o.positional[2] then
            error("features needs a port name")
        end
        local dir = port.find(o.positional[2])
        if not dir then
            error("port '" .. o.positional[2] .. "' not found")
        end
        local spec = port.features_file(dir) or {}
        print(features.describe(spec.features or spec, o.positional[2]))
        return 0
    elseif cmd == "backends" then
        for _, b in ipairs(require("gcpkg.backends").probe_all()) do
            log.info(string.format("  %-12s %-8s %s", b.name,
                                   b.available and "ready" or "n/a", b.detail))
        end
        return 0
    elseif cmd == "port" and o.positional[2] == "new" then
        local name = o.positional[3]
        if not name then
            error("port new needs a name")
        end
        local dir = util.join(roots[1], name)
        if fs.exists(util.join(dir, "build.lua")) then
            error("port already exists: " .. dir)
        end
        fs.mkdirs(dir)
        fs.write(util.join(dir, "build.lua"),
                 string.format(BUILD_TEMPLATE, name, name, name, name))
        fs.write(util.join(dir, "features.yaml"), string.format(FEATURES_TEMPLATE, name))
        log.step("created port " .. dir)
        return 0
    end
    log.error("unknown command: " .. tostring(cmd))
    print(USAGE)
    return 1
end

return M
