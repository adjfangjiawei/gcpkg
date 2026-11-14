-- opencv 5.1.0 -- gcpkg port definition.
-- Core/imgproc/imgcodecs only; codecs come from bundled upstream sources.
-- License files are installed under share/doc/opencv by gcpkg.r20.
local recipe = require("gcpkg.recipe")
local r20 = require("gcpkg.r20")
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")

return recipe.cmake {
    name = "opencv",
    version = "5.1.0",
    license = "Apache-2.0",
    homepage = "https://opencv.org/",
    description = "OpenCV core/imgproc/imgcodecs with bundled source-built codec libraries",
    source = { url = "https://codeload.github.com/opencv/opencv/tar.gz/refs/tags/5.1.0", sha256 = "638c1dae7e37e45afea21aa217dc667ad7cf57acc66cdf652c074f1e0e5ad6d2", strip = 1 },
    dependencies = {},
    pre_build = function(ctx) r20.restrict_pkgconfig(ctx) end,
    cmake = {
        generator = "Ninja",
        defines = {
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            CMAKE_POSITION_INDEPENDENT_CODE = "ON",
            BUILD_SHARED_LIBS = "OFF",
            BUILD_TESTING = "OFF",
            BUILD_TESTS = "OFF",
            BUILD_PERF_TESTS = "OFF",
            BUILD_EXAMPLES = "OFF",
            BUILD_DOCS = "OFF",
            BUILD_PACKAGE = "OFF",
            BUILD_opencv_apps = "OFF",
            BUILD_JAVA = "OFF",
            BUILD_opencv_python3 = "OFF",
            BUILD_LIST = "core,imgproc,imgcodecs",
            OPENCV_FORCE_3RDPARTY_BUILD = "ON",
            BUILD_ZLIB = "ON", BUILD_JPEG = "ON", BUILD_PNG = "ON",
            BUILD_TIFF = "OFF", BUILD_WEBP = "OFF", BUILD_OPENJPEG = "OFF",
            BUILD_JASPER = "OFF", BUILD_HARFBUZZ = "OFF", BUILD_TBB = "OFF",
            BUILD_IPP_IW = "OFF", BUILD_ITT = "OFF", BUILD_CLAPACK = "OFF",
            WITH_ZLIB_NG = "OFF",
            WITH_JPEG = "ON", WITH_PNG = "ON", WITH_TIFF = "OFF",
            WITH_WEBP = "OFF", WITH_OPENJPEG = "OFF", WITH_JASPER = "OFF",
            WITH_JPEGXL = "OFF", WITH_AVIF = "OFF", WITH_OPENEXR = "OFF",
            WITH_IMGCODEC_GIF = "OFF", WITH_IMGCODEC_HDR = "OFF",
            WITH_IMGCODEC_SUNRASTER = "OFF", WITH_IMGCODEC_PXM = "OFF",
            WITH_IMGCODEC_PFM = "OFF",
            WITH_FFMPEG = "OFF", WITH_GSTREAMER = "OFF", WITH_GTK = "OFF",
            WITH_V4L = "OFF", WITH_QT = "OFF", WITH_OPENGL = "OFF",
            WITH_VULKAN = "OFF", WITH_WAYLAND = "OFF", WITH_1394 = "OFF",
            WITH_OPENCL = "OFF", WITH_OPENCL_SVM = "OFF",
            WITH_OPENCLAMDFFT = "OFF", WITH_OPENCLAMDBLAS = "OFF",
            WITH_CUDA = "OFF", WITH_VTK = "OFF", WITH_IPP = "OFF",
            WITH_ITT = "OFF", WITH_PROTOBUF = "OFF", WITH_FLATBUFFERS = "OFF",
            WITH_OPENVINO = "OFF", WITH_EIGEN = "OFF", WITH_LAPACK = "OFF",
            WITH_TBB = "OFF", WITH_HPX = "OFF", WITH_OPENMP = "OFF",
            WITH_GDAL = "OFF", WITH_GDCM = "OFF", WITH_OBSENSOR = "OFF",
            WITH_CANN = "OFF", WITH_VA = "OFF", WITH_VA_INTEL = "OFF",
            WITH_MFX = "OFF", WITH_DIRECTX = "OFF", WITH_DIRECTML = "OFF",
            WITH_CPUFEATURES = "OFF",
        },
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include", function(ctx)
            local out = {}
            for _, d in ipairs({ "opencv4", "opencv5" }) do
                local p = util.join(ctx.prefix, "include", d)
                if fs.isdir(p) then out[#out + 1] = p end
            end
            return out
        end },
        libdirs = { "@LIBDIR@" },
        libs = { "opencv_core", "opencv_imgproc", "opencv_imgcodecs" },
        binaries = {},
        link_flags = { "-lz", "-ljpeg", "-lpng16", "-ldl", "-lpthread", "-lm" },
    },
    post_install = function(ctx) r20.license(ctx, { "LICENSE" }) end,
}
