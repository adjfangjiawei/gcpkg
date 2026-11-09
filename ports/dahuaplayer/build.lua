-- dahuaplayer 3.044.0000000.1 -- gcpkg port definition.
-- Proprietary binary SDK from Dahua's support portal (official SHA256 of the Linux64 V3.044 bundle is published there). No anonymous download, no recompilation.


local external = require("gcpkg.build.external")

return external.declare {
    name = "dahuaplayer",
    version = "3.044.0000000.1",
    description = "Dahua PlaySDK / dhplay proprietary playback library",
    license = "Proprietary",
    homepage = "https://www.dahuatech.com",
    dependencies = {},
    sdk = {
        env = "GCPKG_DAHUAPLAYER_HOME",
        default = "/opt/dahua/playsdk",
        url = "https://www.dahuatech.com/service/downloadlists/837.html",
        description = "Dahua PlaySDK / dhplay proprietary playback library",
        alt_env = {
            "DAHUA_PLAYSDK_HOME",
          },
        probe = {
            "include/dhplay.h",
          },
        includes = {
            "include",
          },
        libdirs = {
            "lib",
          },
        binaries = {},
        libs = {
            "dhplay",
          },
    },
}
