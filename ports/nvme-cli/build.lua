-- nvme-cli 2.16 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).
-- NVMe query CLI built on libnvme.
-- Upstream is never patched: all adaptation is in this file.

local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "nvme-cli",
    version = "2.16",
    license = "GPL-2.0",
    homepage = "https://github.com/linux-nvme/nvme-cli",
    description = "NVMe device query/management CLI",
    source = {
        url = "https://codeload.github.com/linux-nvme/nvme-cli/tar.gz/refs/tags/v2.16",
        sha256 = "989682ed7b250a2c7a8127e362ffc5d29f5c370127abe405be09c73216da2b97",
        strip = 1,
    },
    dependencies = {
        "libnvme",
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
      libs = {},
      binaries = {
        "@PREFIX@/sbin",
      },
    },
}
