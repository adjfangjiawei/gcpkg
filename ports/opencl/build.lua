-- opencl 2026.05.29 -- gcpkg port definition.
-- Khronos OpenCL ICD loader on the source-built opencl-headers port.
-- License files are installed under share/doc/opencl by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")

return recipe.cmake {
    name = "opencl",
    version = "2026.05.29",
    license = "Apache-2.0",
    homepage = "https://github.com/KhronosGroup/OpenCL-ICD-Loader",
    description = "Khronos OpenCL ICD loader linked against source-built OpenCL headers",
    source = { url = "https://codeload.github.com/KhronosGroup/OpenCL-ICD-Loader/tar.gz/refs/tags/v2026.05.29", sha256 = "48fd0c5181db7cd046f4f731d5955694892e10998d49d09ee0d997e7e04fd939", strip = 1 },
    dependencies = { "opencl-headers" },
    cmake = {
        generator = "Ninja",
        defines = function(ctx)
            local inc = r20.dep_include(ctx, "opencl-headers")
            return {
                CMAKE_BUILD_TYPE = "Release",
                CMAKE_INSTALL_LIBDIR = "lib",
                CMAKE_PREFIX_PATH = r20.cmake_prefix(ctx),
                CMAKE_C_FLAGS = "-I" .. inc,
                CMAKE_CXX_FLAGS = "-I" .. inc,
                BUILD_SHARED_LIBS = "OFF", BUILD_TESTING = "OFF",
                OPENCL_ICD_LOADER_BUILD_SHARED_LIBS = "OFF",
                OPENCL_ICD_LOADER_BUILD_TESTING = "OFF",
                ENABLE_OPENCL_LAYERS = "OFF", ENABLE_OPENCL_LAYERINFO = "OFF",
                ENABLE_OPENCL_LOADER_MANAGED_DISPATCH = "OFF",
                OPENCL_ICD_LOADER_HEADERS_DIR = inc,
            }
        end,
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/CL" },
        libdirs = { "@LIBDIR@" },
        libs = { "OpenCL" },
        binaries = {},
        defines = { "CL_TARGET_OPENCL_VERSION=310" },
        link_flags = { "-ldl", "-lpthread" },
    },
    post_install = function(ctx)
        local inc = util.join(ctx.prefix, "include")
        fs.mkdirs(inc)
        local dep_inc = r20.dep_include(ctx, "opencl-headers")
        local cl = util.join(dep_inc, "CL")
        if fs.isdir(cl) then
            ctx.exec({ "cp", "-a", cl, inc }, { log = ctx.log })
        end
        local extra = util.join(ctx.src, "include", "cl_khr_icd2.h")
        if fs.isfile(extra) and fs.isdir(util.join(inc, "CL")) then
            ctx.exec({ "cp", "-a", extra, util.join(inc, "CL") }, { log = ctx.log })
        end
        r20.license(ctx, { "LICENSE" })
    end,
}
