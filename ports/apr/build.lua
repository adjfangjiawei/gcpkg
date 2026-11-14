-- apr 1.7.5 -- gcpkg port definition.
-- Apache Portable Runtime; stock autotools static build.

local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.autotools {
    name = "apr",
    version = "1.7.5",
    license = "Apache-2.0",
    homepage = "https://apr.apache.org",
    description = "Apache Portable Runtime library",
    source = {
        url = "https://archive.apache.org/dist/apr/apr-1.7.5.tar.gz",
        sha256 = "3375fa365d67bcf945e52b52cba07abea57ef530f40b281ffbe977a9251361db",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        -- Explicit autoconf results, like ports/sdl3/build.lua.  Only values
        -- certain for Linux/glibc/clang-23 are stated, so AC_CHECK_* tests are
        -- skipped without guessing.  AC_TRY_RUN/AC_TRY_COMPILE are an autoconf
        -- limitation and still execute.
        args = {
          "--without-sendfile",
          "ac_cv_c_bigendian=no",
          "ac_cv_c_const=yes",
          "ac_cv_c_inline=inline",
          "ac_cv_file__dev_zero=yes",
          "ac_cv_lib_m_cos=yes",
          "ac_cv_lib_dl_dlopen=yes",
          "ac_cv_lib_pthread_pthread_join=yes",
          "ac_cv_func_alloca_works=yes",
          "ac_cv_func_calloc=yes",
          "ac_cv_func_dlopen=yes",
          "ac_cv_func_dlsym=yes",
          "ac_cv_func_fdatasync=yes",
          "ac_cv_func_flock=yes",
          "ac_cv_func_fork=yes",
          "ac_cv_func_gai_strerror=yes",
          "ac_cv_func_getenv=yes",
          "ac_cv_func_getifaddrs=yes",
          "ac_cv_func_getpwnam_r=yes",
          "ac_cv_func_getpwuid_r=yes",
          "ac_cv_func_getgrgid_r=yes",
          "ac_cv_func_getgrnam_r=yes",
          "ac_cv_func_gethostbyname_r=yes",
          "ac_cv_func_getrandom=yes",
          "ac_cv_func_getrlimit=yes",
          "ac_cv_func_getservbyname_r=yes",
          "ac_cv_func_gmtime_r=yes",
          "ac_cv_func_if_indextoname=yes",
          "ac_cv_func_if_nametoindex=yes",
          "ac_cv_func_inet_addr=yes",
          "ac_cv_func_inet_network=yes",
          "ac_cv_func_isinf=yes",
          "ac_cv_func_isnan=yes",
          "ac_cv_func_localtime_r=yes",
          "ac_cv_func_memchr=yes",
          "ac_cv_func_memmove=yes",
          "ac_cv_func_mkstemp=yes",
          "ac_cv_func_mmap=yes",
          "ac_cv_func_mprotect=yes",
          "ac_cv_func_munmap=yes",
          "ac_cv_func_nl_langinfo=yes",
          "ac_cv_func_poll=yes",
          "ac_cv_func_pthread_attr_setguardsize=yes",
          "ac_cv_func_pthread_condattr_setpshared=yes",
          "ac_cv_func_pthread_key_delete=yes",
          "ac_cv_func_pthread_mutexattr_setpshared=yes",
          "ac_cv_func_pthread_rwlock_init=yes",
          "ac_cv_func_putenv=yes",
          "ac_cv_func_sched_yield=yes",
          "ac_cv_func_sem_open=yes",
          "ac_cv_func_sem_timedwait=yes",
          "ac_cv_func_setenv=yes",
          "ac_cv_func_setrlimit=yes",
          "ac_cv_func_setsid=yes",
          "ac_cv_func_shm_open=yes",
          "ac_cv_func_shm_unlink=yes",
          "ac_cv_func_sigaction=yes",
          "ac_cv_func_sigsuspend=yes",
          "ac_cv_func_sigwait=yes",
          "ac_cv_func_strcasecmp=yes",
          "ac_cv_func_strdup=yes",
          "ac_cv_func_strerror_r=yes",
          "ac_cv_func_strncasecmp=yes",
          "ac_cv_func_strstr=yes",
          "ac_cv_func_unsetenv=yes",
          "ac_cv_header_dlfcn_h=yes",
          "ac_cv_header_pthread_h=yes",
          "ac_cv_header_stdc=yes",
        },
    },
    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
        end
    end,
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "apr-1",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
