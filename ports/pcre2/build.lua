-- pcre2 10.45 -- Perl-compatible regular expressions v2
-- Layer L0: no gcpkg dependencies. This is ordinary Lua; the
-- declarative recipe only removes boilerplate. Edit freely.
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "pcre2",
    version = "10.45",
    description = "Perl-compatible regular expressions v2",
    license = "BSD-3-Clause",
    homepage = "https://github.com/PCRE2Project/pcre2",
    source = {
        url = "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.45/pcre2-10.45.tar.gz",
        sha256 = "0e138387df7835d7403b8351e2226c1377da804e0737db0e071b48f07c9d12ee",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            PCRE2_BUILD_PCRE2GREP = "OFF",
            PCRE2_SUPPORT_LIBREADLINE = "OFF",
            PCRE2_SUPPORT_LIBBZ2 = "OFF",
            PCRE2_SUPPORT_LIBZ = "OFF",
            PCRE2_SHOW_REPORT = "OFF",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "pcre2-8" },
    },
}
