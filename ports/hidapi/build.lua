-- hidapi 0.15.0 -- gcpkg port definition.
-- HID device access; CMake over libusb. Static build avoids linking the non-PIC libusb-1.0.a into a .so.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "hidapi",
    version = "0.15.0",
    license = "BSD-3-Clause/HIDAPI",
    homepage = "https://github.com/libusb/hidapi",
    description = "HID device access library",
    source = {
        url = "https://codeload.github.com/libusb/hidapi/tar.gz/refs/tags/hidapi-0.15.0",
        sha256 = "5d84dec684c27b97b921d2f3b73218cb773cf4ea915caee317ac8fc73cef8136",
        strip = 1,
    },
    dependencies = {
        "libusb",
      },
    cmake = {
        defines = {
          BUILD_SHARED_LIBS = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "hidapi-libusb",
        "hidapi-hidraw",
      },
      binaries = {},
    },
}
