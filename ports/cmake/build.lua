-- cmake 3.31.6 -- gcpkg port definition.
-- Built from Kitware's bootstrap (no upstream patch). Exported as a tool port: dependents get its bin/ prepended to PATH.



return {
    name = "cmake",
    version = "3.31.6",
    description = "CMake build system itself, built from source via ./bootstrap",
    license = "BSD-3-Clause",
    homepage = "https://cmake.org",
    source = {
        url = "https://cmake.org/files/v3.31/cmake-3.31.6.tar.gz",
        sha256 = "653427f0f5014750aafff22727fb2aa60c6c732ca91808cfb78ce22ddd9e55f0",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "./bootstrap", "--prefix=" .. ctx.prefix, "--parallel=" .. j },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "-j" .. j }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install" }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = {},
            binaries = { ctx.prefix .. "/bin" },
        }
    end,
}
