-- alsa-lib 1.2.9 -- gcpkg port definition.
--
-- R20 new standard: all features supported on the active triplet are ON by
-- default.  Their independent libraries are SOURCE-BUILT gcpkg ports pulled
-- in by features.yaml `requires:` (libresmgr, python) and installed
-- bottom-up.  Platform/toolchain facts come from the shared triplet probe;
-- `patch-configure.py` removes the generated configure's remaining compile,
-- link, CPP, ld and python3-config probes.
--
-- Upstream-off modes that are NOT enabled: python2 (no source port),
-- static (mutually exclusive with shared).  softfloat is ON too: the patched
-- configure no longer lets it silently disable alisp or PCM plugins.

local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "alsa-lib",
    version = "1.2.9",
    description = "ALSA userspace library",
    license = "LGPL-2.1",
    homepage = "https://www.alsa-project.org",
    source = {
        url = "https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.9.tar.bz2",
        sha256 = "dc9c643fdc4ccfd0572cc685858dd41e08afb583f30460b317e4188275f615b2",
        strip = 1,
    },
    -- Feature deps are NOT hardcoded: see features.yaml requires.
    dependencies = {},
    autotools = {
        args = function(ctx)
            local a = {
                -- Keep runtime socket files inside the store boundary.
                "--with-tmpdir=" .. ctx.store.root .. "/.gcpkg/tmp",
                -- All PCM/control plugins, all core components: upstream ON
                -- by default, stated explicitly so a feature cannot silently
                -- fall back to a reduced build.
                "--with-pcm-plugins=all",
                "--with-ctl-plugins=all",
                "--enable-mixer",
                "--enable-pcm",
                "--enable-rawmidi",
                "--enable-hwdep",
                "--enable-seq",
                "--enable-ucm",
                "--enable-topology",
                "--enable-old-symbols",
                "--enable-aload",
                "--with-libdl",
                "--with-pthread",
                "--with-librt",
                "--with-versioned",
                "--with-debug",
            }
            -- Feature gate + active triplet: lockless dmix is an x86 default,
            -- so non-x86 triplets keep the option ON in features but do not
            -- ask configure for an x86-only default.
            if ctx.features.enabled["lockless-dmix"] then
                local arch = tostring(ctx.arch or "")
                if arch == "x86_64" or arch == "x86" or arch == "i386" or arch == "i686" then
                    a[#a + 1] = "--enable-lockless-dmix"
                else
                    a[#a + 1] = "--disable-lockless-dmix"
                end
            else
                a[#a + 1] = "--disable-lockless-dmix"
            end
            if ctx.features.enabled["softfloat"] then
                a[#a + 1] = "--with-softfloat=yes"
            else
                a[#a + 1] = "--without-softfloat"
            end
            -- Dependency fact: AC_CHECK_LIB(resmgr, rsm_open_device).
            if ctx.dep("libresmgr") then
                a[#a + 1] = "ac_cv_lib_resmgr_rsm_open_device=yes"
            end
            -- Python binding: point straight at the source-built python port;
            -- patch-configure.py removes the python3-config subprocesses.
            local py = ctx.dep("python")
            if py then
                local libdir = (py.libdirs or {})[1] or (py.prefix .. "/lib")
                local inc = (py.includes or {})[1] or
                            (py.prefix .. "/include/python3.12")
                local lib = (py.libs or {})[1] or "python3.12"
                a[#a + 1] = "--with-pythonlibs=-L" .. libdir ..
                            " -l" .. lib .. " -ldl -lm -lpthread"
                a[#a + 1] = "--with-pythonincludes=-I" .. inc
            end
            return a
        end,
    },
    pre_build = function(ctx)
        -- 1. Short-circuit the generated configure's unconditional probes.
        --    This file lives in the port directory and writes ONLY to ctx.src
        --    (inside the store); no network, no /tmp, no system files.
        local py = ctx.dep("python")
        local pybin = py and (py.binaries or {})[1] or nil
        local python = pybin and (pybin .. "/python3") or
                       (py and (py.prefix .. "/bin/python3") or "python3")
        ctx.exec({ python, ctx.port_dir .. "/patch-configure.py",
                   ctx.src .. "/configure" },
                 { cwd = ctx.src, log = ctx.log })
        -- The 1.2.9 release tarball omits the ALISP data files that its own
        -- Makefile.am installs when --enable-alisp is used.  Create the four
        -- placeholders inside the source tree rather than turning the
        -- feature off; they are data, not generated sources.
        for _, rel in ipairs({
            "src/conf/cards/aliases.alisp",
            "src/conf/cards/SI7018/sndoc-mixer.alisp",
            "src/conf/cards/SI7018/sndop-mixer.alisp",
            "src/conf/sndo-mixer.alisp",
            "src/conf/smixer.conf",
        }) do
            local p = ctx.src .. "/" .. rel
            if not fs.isfile(p) then fs.write(p, "") end
        end
        -- Framework preprocessor fact; AC_PROG_CPP cache var is injected by
        -- the shared triplet facts, this keeps the real CPP command aligned.
        ctx.env.CPP = ctx.compiler.wrapper_cc .. " -E"
        -- 2. Expose the source-built libresmgr header and library to the
        --    AC_CHECK_LIB result and to the real compile/link of SUPPORT_RESMGR.
        --    dependency_env already scopes -L/LIBRARY_PATH for direct deps;
        --    add only what is missing so assertSaneCompilerFlags stays happy.
        local function add_flag(key, flag)
            local prev = ctx.env[key]
            if not prev or prev == "" then ctx.env[key] = flag; return end
            for token in prev:gmatch("%S+") do
                if token == flag then return end
            end
            ctx.env[key] = prev .. " " .. flag
        end
        local function add_path(key, path)
            local prev = ctx.env[key]
            if not prev or prev == "" then ctx.env[key] = path; return end
            for entry in prev:gmatch("[^:]+") do
                if entry == path then return end
            end
            ctx.env[key] = path .. ":" .. prev
        end
        local res = ctx.dep("libresmgr")
        if res then
            add_path("CPATH", r20.dep_include(ctx, "libresmgr"))
            local libdir = (res.libdirs or {})[1]
            if libdir then
                add_flag("LDFLAGS", "-L" .. libdir)
                add_path("LIBRARY_PATH", libdir)
                -- configure's early AC_PROG_CC run test links LIBS; make the
                -- versioned client .so loadable without a system install.
                add_path("LD_LIBRARY_PATH", libdir)
                add_flag("LDFLAGS", "-Wl,-rpath," .. libdir)
                local libs = ctx.env.LIBS or ""
                if not libs:find("%-lresmgr") then
                    ctx.env.LIBS = (libs ~= "") and (libs .. " -lresmgr") or "-lresmgr"
                end
            end
        end
        -- 3. Source-built libpython is a shared library; keep the Python
        --    mixer module loadable at link time and at runtime.  The direct
        --    dependency already provides -L/LIBRARY_PATH, so only add the
        --    loader path and the store-local rpath here.
        if py then
            local pylib = (py.libdirs or {})[1]
            if pylib then
                add_path("LD_LIBRARY_PATH", pylib)
                add_flag("LDFLAGS", "-Wl,-rpath," .. pylib)
            end
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "asound" },
        binaries = { "@PREFIX@/bin" },
    },
}
