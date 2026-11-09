-- libiio 0.26 -- gcpkg port definition.
-- Industrial I/O kernel interface; CMake, depends on libusb + libxml2. Avahi DNS-SD and libaio are disabled.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "libiio",
    version = "0.26",
    license = "LGPL-2.1",
    homepage = "https://analogdevicesinc.github.io/libiio/",
    description = "Industrial I/O (IIO) kernel interface library",
    source = {
        url = "https://codeload.github.com/analogdevicesinc/libiio/tar.gz/refs/tags/v0.26",
        sha256 = "fb445fb860ef1248759f45d4273a4eff360534480ec87af64c6b8db3b99be7e5",
        strip = 1,
    },
    dependencies = {
        "libusb",
        "libxml2",
      },
    cmake = {
        defines = {
          WITH_TESTS = "OFF",
          HAVE_DNS_SD = "OFF",
          WITH_AIO = "OFF",
          BUILD_SHARED_LIBS = "OFF",
          INSTALL_UDEV_RULE = "OFF",
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
        "iio",
      },
      binaries = {},
    },
}
