-- taglib 2.0.2 -- ONE port, ONE build.lua + ONE features.yaml.
-- Audio metadata library; a pinned utfcpp tarball fills the empty git submodule directory.
-- Static checks in tests/r12.sh; GCPKG_R12_DYNAMIC=1 builds it for real.
-- Upstream is never patched: all adaptation lives in this file.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local net = require("gcpkg.net")
local recipe = require("gcpkg.recipe")

local MAIN = { url = "https://codeload.github.com/taglib/taglib/tar.gz/refs/tags/v2.0.2", sha256 = "0de288d7fe34ba133199fd8512f19cc1100196826eafcb67a33b224ec3a59737" }
local UTFCPP = { url = "https://codeload.github.com/nemtrif/utfcpp/tar.gz/df857efc5bbc2aa84012d865f7d7e9cccdc08562", sha256 = "911ff4f13cc7bfece2b5f65e7468b962db19c9727f89d560b2617360af08f538" }

return recipe.cmake {
    name = "taglib",
    version = "2.0.2",
    license = "LGPL-2.1-or-later OR MPL-1.1",
    homepage = "https://taglib.org",
    description = "Audio metadata library; `zlib` is a conditional dependency",
    dependencies = {},
    source = function(o)
        local cache = util.join(o.dir, ".cache")
        fs.mkdirs(cache)
        local main = util.join(cache, "taglib.tar.gz")
        net.download(MAIN.url, main, MAIN.sha256, { log = o.log })
        net.extract(main, o.dir, 1, { log = o.log })
        -- GitHub release archives ship an empty 3rdparty/utfcpp submodule.
        -- Fill it with the exact pinned submodule commit, not a moving branch.
        local sub = util.join(cache, "utfcpp.tar.gz")
        local target = util.join(o.dir, "3rdparty/utfcpp")
        net.download(UTFCPP.url, sub, UTFCPP.sha256, { log = o.log })
        fs.mkdirs(target)
        net.extract(sub, target, 1, { log = o.log })
    end,
    cmake = {
        defines = function(ctx)
            local d = ctx.dep("zlib")
            local t = {
              BUILD_TESTING = "OFF",
              CMAKE_BUILD_TYPE = "Release",
              CMAKE_INSTALL_LIBDIR = "lib",
              BUILD_SHARED_LIBS = "OFF",
              BUILD_EXAMPLES = "OFF",
              BUILD_BINDINGS = "OFF",
              WITH_ZLIB = "OFF",
            }
            if d and d.prefix then t.ZLIB_ROOT = d.prefix end
            return t
        end,
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/taglib" },
        libdirs = { "@LIBDIR@" },
        libs = { "tag" },
        binaries = {},
    },
}
