-- alsa-lib 1.2.9 -- gcpkg port definition.
-- Autotools. Host ALSA headers via pkgconfig backend; --disable-python avoids Python SWIG bindings.


local recipe = require("gcpkg.recipe")

return recipe.autotools {
    name = "alsa-lib",
    version = "1.2.9",
    description = "ALSA userspace library",
    license = "LGPL-2.1",
    homepage = "https://www.alsa-project.org",
    source = {
        url = "https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.9.tar.bz2",
        sha256 = "dc9c643fdc4ccfd0572cc685858dd41e08afb583f30460b317e4188275f615b2",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        -- Explicit detection results, like ports/sdl3/build.lua.  autoconf
        -- treats VAR=value arguments as pre-computed results and skips the
        -- corresponding AC_CHECK_* compile/link tests.  No cache file.
        args = {
          "--disable-python",
          "--without-wordexp",
          "--disable-resmgr",
          "ac_cv_func_uselocale=yes",
          "ac_cv_func_eaccess=no",
          "ac_cv_func_dlopen=yes",
          "ac_cv_search_dlsym=-ldl",
          "ac_cv_lib_pthread_pthread_join=yes",
          "ac_cv_have_decl_PTHREAD_MUTEX_RECURSIVE=yes",
          "ac_cv_lib_rt_clock_gettime=yes",
          "ac_cv_lib_resmgr_rsm_open_device=no",
          "ac_cv_header_wordexp_h=yes",
          "ac_cv_header_endian_h=yes",
          "ac_cv_header_sys_endian_h=no",
          "ac_cv_header_sys_shm_h=yes",
          "ac_cv_header_malloc_h=yes",
          "ac_cv_header_stdc=yes",
          "ac_cv_header_time=yes",
          "ac_cv_header_dlfcn_h=yes",
          "ac_cv_c_const=yes",
          "ac_cv_c_inline=inline",
          -- configure.ac guards this AC_TRY_LINK with `test -z`, so giving the
          -- result skips the atomics link test too.
          "gcc_have_atomics=yes",
        },
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "asound",
      },
      binaries = {},
    },
}
