-- xxhash 0.8.4 -- ONE library, ONE build.lua + ONE features.yaml.
-- Verification: static registry/graph tests here; real builds for a
-- subset live in tests/linux-base.sh (GCPKG_BASE_DYNAMIC=1).
-- Hand-written Makefile: make && make install PREFIX=<prefix>.
-- Upstream is never patched: all adaptation is in this file.


return {
    name = "xxhash",
    version = "0.8.4",
    license = "BSD-2-Clause",
    homepage = "https://github.com/Cyan4973/xxHash",
    description = "Extremely fast non-cryptographic hash",
    source = {
        url = "https://codeload.github.com/Cyan4973/xxHash/tar.gz/refs/tags/v0.8.4",
        sha256 = "5738270935e7c3d38a79b3adf7c9692566ce7895a25f67de43ad52ab504acd32",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "make", "-j" .. j }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "PREFIX=" .. ctx.prefix }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = {
            "xxhash",
          },
            binaries = {},
        }
    end,

}
