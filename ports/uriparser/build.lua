-- uriparser 634b678 -- gcpkg port.
-- Upstream CMake build with every library capability ON by default.  Its
-- check_* / compiler probes are short-circuited by gcpkg's shared triplet
-- facts; GTest comes from the source-built googletest port via a local
-- CONFIG package, not from the host.  Doxygen docs stay OFF (a documentation
-- TOOL, not a library capability; its tool port is a separate audit item).
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

local function patch_plain(path, old, new)
    local s = assert(fs.read(path), "gcpkg: cannot read " .. path)
    local a, b = s:find(old, 1, true)
    assert(a, "gcpkg: expected literal match in " .. path .. ": " .. old)
    fs.write(path, s:sub(1, a - 1) .. new .. s:sub(b + 1))
end

return recipe.cmake {
    name = "uriparser",
    version = "634b678",
    license = "BSD-3-Clause",
    homepage = "https://github.com/uriparser/uriparser",
    description = "Strictly RFC 3986 compliant URI parsing library",
    source = {
        url = "https://codeload.github.com/uriparser/uriparser/tar.gz/634b678fa858abf1d1ebc0634e96e9e29596e92a",
        sha256 = "91356109d1ec6ae4a4380653905acebde44d40f60fba94095596195bc58799b0",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = function(ctx)
            local d = {
                BUILD_SHARED_LIBS = "OFF",
                URIPARSER_BUILD_CHAR = "ON",
                URIPARSER_BUILD_WCHAR_T = "ON",
                URIPARSER_BUILD_TOOLS = "ON",
                URIPARSER_BUILD_TESTS = "OFF", -- feature gate appends =ON
                URIPARSER_BUILD_DOCS = "OFF",  -- Doxygen tool port pending
                URIPARSER_ENABLE_INSTALL = "ON",
                URIPARSER_WARNINGS_AS_ERRORS = "OFF",
                CMAKE_FIND_PACKAGE_PREFER_CONFIG = "ON",
                CMAKE_INSTALL_INCLUDEDIR = "include",
                CMAKE_INSTALL_LIBDIR = "lib",
                CMAKE_BUILD_TYPE = "Release",
            }
            local gtest = ctx.dep("googletest")
            if gtest then
                local libdir = (gtest.libdirs or {})[1]
                if libdir then d.GTest_DIR = libdir .. "/cmake/GTest" end
            end
            return d
        end,
    },
    pre_build = function(ctx)
        -- GTestConfig.cmake exports imported targets, not the old
        -- FindGTest module's GTEST_BOTH_LIBRARIES variable.  Inject the
        -- source-built imported targets locally instead of searching the host.
        patch_plain(ctx.src .. "/CMakeLists.txt",
                    "${GTEST_BOTH_LIBRARIES}",
                    "GTest::gtest GTest::gtest_main")
    end,
    post_install = function(ctx)
        if ctx.features.enabled["tests"] then
            ctx.exec({ "ctest", "--test-dir", ctx.build_dir,
                       "--output-on-failure" },
                     { cwd = ctx.build_dir, log = ctx.log })
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "uriparser" },
        binaries = { "@PREFIX@/bin" },
    },
}
