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
        -- Explicit results, like ports/sdl3/build.lua.  Every required
        -- AC_CHECK_FUNCS has an AC_MSG_ERROR on failure, so all 34 are stated
        -- here.  Only OS facts certain for Linux/glibc are given; linux/*.h
        -- headers are left to configure rather than guessed.
        args = {
          -- R20: AC_CHECK_LIB([lzo2],[lzo_version]) is short-circuited with
          -- the exact result.  ports/lzo installs the real liblzo2.a and
          -- <lzo/lzo1x.h>, and inject.lua passes CPPFLAGS/LDFLAGS/LDLIBS,
          -- so COMPRESSION_LZO=1 compiles and links for real (not faked).
          "ac_cv_lib_lzo2_lzo_version=yes",
          "--disable-shared",
          "--enable-static",
          "--disable-documentation",
          "--disable-convert",
          "--disable-backtrace",
          "ac_cv_func_fchdir=yes",
          "ac_cv_func_fdatasync=yes",
          "ac_cv_func_ftruncate=yes",
          "ac_cv_func_getcwd=yes",
          "ac_cv_func_getmntent=yes",
          "ac_cv_func_getpagesize=yes",
          "ac_cv_func_gettimeofday=yes",
          "ac_cv_func_lchown=yes",
          "ac_cv_func_localtime_r=yes",
          "ac_cv_func_memchr=yes",
          "ac_cv_func_memmove=yes",
          "ac_cv_func_memset=yes",
          "ac_cv_func_mkdir=yes",
          "ac_cv_func_mkfifo=yes",
          "ac_cv_func_munmap=yes",
          "ac_cv_func_openat=yes",
          "ac_cv_func_realpath=yes",
          "ac_cv_func_regcomp=yes",
          "ac_cv_func_rmdir=yes",
          "ac_cv_func_select=yes",
          "ac_cv_func_socket=yes",
          "ac_cv_func_strcasecmp=yes",
          "ac_cv_func_strchr=yes",
          "ac_cv_func_strdup=yes",
          "ac_cv_func_strerror=yes",
          "ac_cv_func_strncasecmp=yes",
          "ac_cv_func_strndup=yes",
          "ac_cv_func_strrchr=yes",
          "ac_cv_func_strstr=yes",
          "ac_cv_func_strtol=yes",
          "ac_cv_func_strtoul=yes",
          "ac_cv_func_strtoull=yes",
          "ac_cv_func_sysinfo=yes",
          "ac_cv_func_uname=yes",
          "ac_cv_header_fcntl_h=yes",
          "ac_cv_header_inttypes_h=yes",
          "ac_cv_header_malloc_h=yes",
          "ac_cv_header_mntent_h=yes",
          "ac_cv_header_stdint_h=yes",
          "ac_cv_header_strings_h=yes",
          "ac_cv_header_sys_file_h=yes",
          "ac_cv_header_sys_ioctl_h=yes",
          "ac_cv_header_sys_param_h=yes",
          "ac_cv_header_sys_socket_h=yes",
          "ac_cv_header_sys_statfs_h=yes",
          "ac_cv_header_sys_statvfs_h=yes",
          "ac_cv_header_sys_time_h=yes",
          "ac_cv_header_unistd_h=yes",
          "ac_cv_header_stdbool_h=yes",
          "ac_cv_member_struct_stat_st_blksize=yes",
          "ac_cv_member_struct_stat_st_rdev=yes",
          "ac_cv_func_clock_gettime=yes",
          "ac_cv_func_register_printf_specifier=no",
          "ac_cv_func_register_printf_modifier=no",
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
