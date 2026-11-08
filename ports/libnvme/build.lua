-- libnvme 1.16.2 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- NVMe ioctl library; depends on the existing liburing port (io_uring path).
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "libnvme",
    version = "1.16.2",
    license = "LGPL-2.1",
    homepage = "https://github.com/linux-nvme/libnvme",
    description = "NVMe ioctl/drive-info library (kernel nvme interface)",
    source = {
        url = "https://codeload.github.com/linux-nvme/libnvme/tar.gz/refs/tags/v1.16.2",
        sha256 = "1d850d5a871559abf641d6e6b63bb86047e4cb26f3ad144597c2c64b3cff7231",
        strip = 1,
    },
    dependencies = {
        "liburing",
      },
    meson = {
        options = {},
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
        "nvme",
      },
      binaries = {},
    },
}
