-- qt 6.12.0 -- gcpkg port definition.
-- Qt Base static QtCore; configure uses bundled third-party source trees only.
-- License files are installed under share/doc/qt by gcpkg.r20.
local r20 = require("gcpkg.r20")
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local cmake_version = require("gcpkg.cmake_version")
local toolchain = require("gcpkg.toolchain")

return {
    name = "qt",
    version = "6.12.0",
    license = "LGPL-3.0/GPL-2.0/GPL-3.0",
    homepage = "https://www.qt.io/",
    description = "Qt 6 Base static core; bundled third-party sources, no system dev packages",
    source = {
        url = "https://codeload.github.com/qt/qtbase/tar.gz/refs/tags/v6.12.0",
        sha256 = "dff6570582c272cbe744d2e460700318262af505460f4215276459970ae31b46",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        r20.clean_build(ctx)
        r20.restrict_pkgconfig(ctx)
        local args = {
            util.join(ctx.src, "configure"),
            "-prefix", ctx.prefix,
            "-release", "-static", "-no-pch",
            "-no-gui", "-no-widgets", "-no-dbus", "-no-opengl",
            "-no-openssl", "-no-glib", "-no-icu", "-no-journald", "-no-syslog",
            "-no-sctp", "-no-libproxy", "-no-cups", "-no-gtk", "-no-fontconfig",
            "-no-eglfs", "-no-gbm", "-no-kms", "-no-linuxfb", "-no-directfb",
            "-no-xcb", "-no-libudev", "-no-evdev", "-no-libinput",
            "-no-mtdev", "-no-tslib", "-no-xkbcommon",
            "-no-feature-network", "-no-feature-sql", "-no-feature-testlib",
            "-no-feature-xml", "-no-feature-concurrent",
            "-force-bundled-libs", "-qt-zlib", "-qt-pcre",
            "-nomake", "examples", "-nomake", "tests", "-nomake", "benchmarks",
            "-nomake", "manual-tests", "-nomake", "minimal-static-tests",
            "-nomake", "doc-snippets", "-no-sbom", "-no-sbom-json",
            "-cmake-generator", "Ninja", "--",
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
            "-DCMAKE_INSTALL_LIBDIR=lib",
            "-DBUILD_SHARED_LIBS=OFF",
            "-DCMAKE_C_COMPILER=" .. ctx.compiler.wrapper_cc,
            "-DCMAKE_CXX_COMPILER=" .. ctx.compiler.wrapper_cxx,
            "-DQT_BUILD_TESTS=OFF", "-DQT_BUILD_EXAMPLES=OFF",
            "-DQT_BUILD_DOCS=OFF", "-DQT_BUILD_BENCHMARKS=OFF",
            "-DQT_BUILD_MANUAL_TESTS=OFF", "-DQT_BUILD_MINIMAL_STATIC_TESTS=OFF",
            "-DQT_BUILD_DOC_SNIPPETS=OFF", "-DQT_GENERATE_SBOM=OFF",
            "-DQT_SBOM_GENERATE_SPDX_V2_JSON=OFF",
        }
        local policy = cmake_version.policy_arg()
        if policy then args[#args + 1] = policy end
        for _, a in ipairs(toolchain.cmake_args({ chainload = {}, compiler_from_env = true })) do
            args[#args + 1] = a
        end
        ctx.exec(args, { cwd = ctx.build_dir, log = ctx.log })
        ctx.exec({ "cmake", "--build", ctx.build_dir,
                   "--parallel", tostring(ctx.jobs or 2), "--config", "Release" },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "cmake", "--install", ctx.build_dir,
                   "--prefix", ctx.prefix, "--config", "Release" },
                 { cwd = ctx.src, log = ctx.log })
        r20.license(ctx, { "LICENSES" })

        local includes = { util.join(ctx.prefix, "include") }
        for _, d in ipairs({ "QtCore", "QtNetwork", "QtSql", "QtXml", "QtConcurrent", "QtTest" }) do
            local p = util.join(ctx.prefix, "include", d)
            if fs.isdir(p) then includes[#includes + 1] = p end
        end
        local binaries = {}
        local b = util.join(ctx.prefix, "bin")
        if fs.isdir(b) then binaries[#binaries + 1] = b end
        return {
            includes = includes,
            libdirs = { util.join(ctx.prefix, "lib") },
            libs = { "Qt6Core" },
            binaries = binaries,
            link_flags = { "-lpthread", "-ldl", "-lz", "-lpcre2-8" },
            compdb_files = { util.join(ctx.build_dir, "compile_commands.json") },
        }
    end,
}
