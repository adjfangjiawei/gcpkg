-- LLVM/Clang binary toolchain as an EXTERNAL port (no source build).
--
-- Building LLVM from source is deliberately NOT a gcpkg port: it needs a
-- multi-hour bootstrap and a huge toolchain. On Linux the official apt.llvm.org
-- installer is the recommended path:
--   wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && sudo ./llvm.sh 23
-- `gcpkg llvm install 23` prints/executes that helper; `gcpkg llvm use DIR`
-- selects an installed tree. This port then exports its bin/include/lib to
-- every dependent and to toolchain.lua's versioned-clang discovery.
local external = require("gcpkg.build.external")
local toolchain = require("gcpkg.toolchain")

return external.declare {
    name = "llvm",
    version = "system",
    description = "LLVM/Clang binary toolchain installed on the host (no source build)",
    license = "Apache-2.0 WITH LLVM-exception",
    homepage = "https://llvm.org",
    dependencies = {},
    sdk = {
        env = "GCPKG_LLVM_HOME",
        alt_env = { "LLVM_HOME", "LLVM_ROOT" },
        -- Auto-detect /usr/lib/llvm-N (or /opt/llvm-N) when no env is set.
        -- This is a function so `check` / `externals` stay purely static.
        default = function()
            local roots = toolchain.llvm_roots()
            return roots[1]
        end,
        url = "https://apt.llvm.org/llvm.sh",
        installer = "wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && sudo ./llvm.sh <version>",
        probe = { "bin/clang", "bin/clang++", "bin/llvm-ar" },
        includes = { "include" },
        libdirs = { "lib" },
        libs = {},
        binaries = { "bin" },
    },
}
