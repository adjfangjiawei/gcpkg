-- libbpf 1.8.0 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Kernel tools/lib/bpf Makefile: build in src/ then install with PREFIX=<prefix>; depends on elfutils.
-- Upstream is never patched: all adaptation is in this file.


return {
    name = "libbpf",
    version = "1.8.0",
    license = "LGPL-2.1/BSD-2-Clause",
    homepage = "https://libbpf.readthedocs.io",
    description = "eBPF CO-RE loader library from the kernel tree",
    source = {
        url = "https://codeload.github.com/libbpf/libbpf/tar.gz/refs/tags/v1.8.0",
        sha256 = "b7a1e685f90f6a63ead0dd85d053694b222975da8d09c1a966041cff6f0055ff",
        strip = 1,
    },
    dependencies = {
        "elfutils",
        "zlib",
      },
    build = function(ctx)
        local util = require("gcpkg.util")
        local d = util.join(ctx.src, "src")
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "make", "-j" .. j }, { cwd = d, log = ctx.log })
        ctx.exec({ "make", "install", "PREFIX=" .. ctx.prefix,
                   "LIBDIR=" .. util.join(ctx.prefix, "lib") }, { cwd = d, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "bpf" },
            binaries = {},
        }
    end,

}
