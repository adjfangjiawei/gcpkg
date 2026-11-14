-- nv-codec-sdk 12.2 -- gcpkg port definition.
-- Login-walled archive. Headers (nvEncodeAPI.h, cuviddec.h, nvcuvid.h) plus driver stub libs; depends on the 'nvidia' platform port.


local external = require("gcpkg.build.external")

return external.declare {
    name = "nv-codec-sdk",
    version = "12.2",
    description = "NVIDIA Video Codec SDK (NVENC/NVDEC headers + driver stubs)",
    license = "Proprietary",
    homepage = "https://developer.nvidia.com/video-codec-sdk",
    dependencies = {
        "nvidia",
      },
    sdk = {
        env = "GCPKG_NV_CODEC_SDK_HOME",
        default = "/opt/nvidia/video-codec-sdk",
        url = "https://developer.nvidia.com/video-codec-sdk",
        description = "NVIDIA Video Codec SDK (NVENC/NVDEC headers + driver stubs)",
        alt_env = {
            "NV_CODEC_SDK_HOME",
          },
        probe = {
            "include/nvEncodeAPI.h",
          },
        includes = {
            "include",
          },
        libdirs = {
            "Lib/linux/stubs/x86_64",
          },
        binaries = {},
        libs = {
            "nvidia-encode",
            "nvcuvid",
          },
    },
}
