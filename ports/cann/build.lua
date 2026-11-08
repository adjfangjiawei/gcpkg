-- cann 9.0.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification in this sandbox: static (check / graph / ports / externals) (see tests/media.sh).
-- The .run installers are ~1-2 GB and licence-gated; point GCPKG_CANN_HOME (or ASCEND_HOME_PATH) at an installed toolkit.
-- Upstream is never patched: all adaptation lives in this file.


local external = require("gcpkg.build.external")

return external.declare {
    name = "cann",
    version = "9.0.0",
    description = "Huawei CANN Ascend toolkit (AscendCL / ops)",
    license = "Proprietary",
    homepage = "https://www.hiascend.com/cann",
    dependencies = {},
    sdk = {
        env = "GCPKG_CANN_HOME",
        default = "/usr/local/Ascend/ascend-toolkit/latest",
        url = "https://www.hiascend.com/developer/download/community/",
        description = "Huawei CANN Ascend toolkit (AscendCL / ops)",
        alt_env = {
            "ASCEND_HOME_PATH",
            "ASCEND_HOME",
          },
        probe = {
            "include/acl/acl.h",
          },
        includes = {
            "include",
          },
        libdirs = {
            "lib64",
          },
        binaries = {
            "bin",
          },
        libs = {
            "ascendcl",
          },
    },
}
