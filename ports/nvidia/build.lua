-- nvidia 12.8 -- gcpkg port definition.
-- Version string is a placeholder for the store key; the real version is whatever $GCPKG_NVIDIA_HOME (or $CUDA_HOME, or /usr/local/cuda) points at.


local external = require("gcpkg.build.external")

return external.declare {
    name = "nvidia",
    version = "12.8",
    description = "NVIDIA CUDA Toolkit / driver platform",
    license = "Proprietary",
    homepage = "https://developer.nvidia.com/cuda-toolkit",
    dependencies = {},
    sdk = {
        env = "GCPKG_NVIDIA_HOME",
        default = "/usr/local/cuda",
        url = "https://developer.nvidia.com/cuda-downloads",
        description = "NVIDIA CUDA Toolkit / driver platform",
        alt_env = {
            "CUDA_HOME",
            "CUDA_PATH",
          },
        probe = {
            "include/cuda_runtime.h",
          },
        includes = {
            "include",
          },
        libdirs = {
            "lib64",
            "lib",
            "lib64/stubs",
          },
        binaries = {
            "bin",
          },
        libs = {
            "cudart",
            "cuda",
            "nvidia-ml",
          },
    },
}
