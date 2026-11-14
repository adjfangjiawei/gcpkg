-- btrfs-progs 6.19.1 -- gcpkg port definition.
-- Btrfs tools on util-linux/zlib/zstd/lz4; tag archive needs autogen.sh.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local r20 = require("gcpkg.r20")

return recipe.autotools {
    name = "btrfs-progs",
    version = "6.19.1",
    license = "GPL-2.0",
    homepage = "https://btrfs.readthedocs.io",
    description = "Btrfs filesystem userspace tools and libbtrfs",
    source = {
        url = "https://codeload.github.com/kdave/btrfs-progs/tar.gz/refs/tags/v6.19.1",
        sha256 = "3213ab1c1f92a75ff181a08009bbb66a4899e168fdb57ca92a5f3045835e169c",
        strip = 1,
    },
    dependencies = {
        "util-linux",
        "zlib",
        "zstd",
        "lz4",
        -- R20: LZO compression is ENABLED (default).  liblzo2 is built from
        -- source by ports/lzo and installed bottom-up before this port.
        "lzo",
      },
    autotools = {
        -- Platform facts (headers / functions / sizeof / endianness) are NOT
        -- hardcoded per port: recipe.lua injects the active triplet's shared
        -- ac_cv_* results for EVERY autotools port.  Only dependency and
        -- struct-member facts stay here.  User global facts win over probes.
        args = {
          -- R20: AC_CHECK_LIB([lzo2],[lzo_version]) is a DEPENDENCY fact, not
          -- a platform fact, so it stays here.  ports/lzo installs the real
          -- liblzo2.a and <lzo/lzo1x.h>; pre_build exposes them via CPATH and
          -- the shared LDFLAGS/LIBS_COMP link -llzo2 for real (not faked).
          "ac_cv_lib_lzo2_lzo_version=yes",
          -- Semantic exception (not a platform fact): dlsym() sees glibc's
          -- register_printf_* symbols, but no header declares them, so the
          -- upstream compile+link checks are "no".  Stated here, not guessed
          -- by the shared probe, otherwise configure would define HAVE_* and
          -- the source would fail to compile.
          "ac_cv_func_register_printf_specifier=no",
          "ac_cv_func_register_printf_modifier=no",
          "--disable-shared",
          "--enable-static",
          "--disable-documentation",
          "--disable-convert",
          "ac_cv_member_struct_stat_st_blksize=yes",
          "ac_cv_member_struct_stat_st_rdev=yes",
        },
        -- R20: configure.ac derives udevdir from the SYSTEM pkg-config
        -- ("pkg-config udev --variable=udevdir" -> /usr/lib/udev), so the
        -- upstream install would write 64-btrfs-*.rules OUTSIDE the store.
        -- Override the make variable so every installed file stays under
        -- the package prefix.  No feature is disabled and no probe is added.
        vars = function(ctx)
            return { udevdir = ctx.prefix .. "/lib/udev" }
        end,
    },
    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
        end
        -- R20: btrfs-progs' hand-written Makefile hardcodes CFLAGS and never
        -- consumes CPPFLAGS, while gcpkg intentionally omits CPPFLAGS/CPATH
        -- for port builds (dependency_env(include_flags=false)).  Expose the
        -- source-built lzo headers through the compiler-level include search
        -- path so COMPRESSION_LZO=1 really compiles and links -llzo2.
        local inc = r20.dep_include(ctx, "lzo")
        local prev = ctx.env.CPATH
        ctx.env.CPATH = (prev and prev ~= "") and (inc .. ":" .. prev) or inc
        -- Drop stale auto-generated dependency files.  DEPCOMMAND uses
        -- `clang -MM -MG`; a previous build that could not see the lzo headers
        -- recorded `lzo/lzoconf.h` as a phony target, and make then stops with
        -- "No rule to make target".  They are regenerated with the real
        -- absolute include path on this build.
        ctx.exec({ "find", ctx.src, "-type", "f", "-name", "*.o.d", "-delete" },
                 { cwd = ctx.src, log = ctx.log })
    end,
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "btrfs",
      },
      binaries = {},
    },
}
