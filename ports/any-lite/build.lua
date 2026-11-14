-- any-lite v0.4.0 -- gcpkg port definition.
-- Header-only std::any backport, built through upstream CMake so the
-- bundled tests and examples are REAL compiled targets (not a single
-- synthetic probe TU).  No system test framework is used: lest_cpp03.hpp
-- ships inside the tarball; example 04 uses the source-built variant-lite
-- port via the examples feature gate.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

return recipe.cmake {
    name = "any-lite",
    version = "v0.4.0",
    license = "BSL-1.0",
    homepage = "https://github.com/martinmoene/any-lite",
    description = "C++17 std::any backport",
    source = {
        url = "https://codeload.github.com/martinmoene/any-lite/tar.gz/refs/tags/v0.4.0",
        sha256 = "889549098291a1313d2fc8cd12dcdab13214d05cdce7ed5fe2dc724cdd7b3125",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        -- Defaults OFF; features.yaml appends -D...=ON last and
        -- cmake.lua's dedup_defines keeps the last -DNAME=VALUE.
        defines = {
            ANY_LITE_OPT_BUILD_TESTS = "OFF",
            ANY_LITE_OPT_BUILD_EXAMPLES = "OFF",
            ANY_LITE_OPT_SELECT_STD = "OFF",
            ANY_LITE_OPT_SELECT_NONSTD = "OFF",
            CMAKE_CXX_STANDARD = "17",
            CMAKE_CXX_STANDARD_REQUIRED = "ON",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
        },
    },
    pre_build = function(ctx)
        -- Clang 23 in -std=c++98 mode does not declare std::swap via
        -- <utility> alone; the nonstd::any implementation calls it.  Add
        -- <algorithm> in the nonstd branch instead of dropping the C++98
        -- test variant.  This is a source fix inside the store, not a probe.
        local hp = ctx.src .. "/include/nonstd/any.hpp"
        local src = fs.read(hp) or ""
        if not src:find("#include <algorithm>", 1, true) then
            local anchor = "#else // any_USES_STD_ANY\n\n#include <utility>\n"
            local a, b = src:find(anchor, 1, true)
            if a then
                src = src:sub(1, b) ..
                      "#include <algorithm>  // std::swap for C++98\n" ..
                      src:sub(b + 1)
                fs.write(hp, src)
            end
        end
        -- Upstream ships example/*.cpp but NO example/CMakeLists.txt.
        -- Provide one inside the source tree rather than turning the
        -- examples feature off.  The variant-lite include dir comes from
        -- its installed gcpkg manifest, not a hardcoded system path.
        local dep = ctx.dep("variant-lite")
        local inc = dep and (dep.includes or {})[1] or ""
        fs.write(ctx.src .. "/example/gcpkg-deps.cmake",
                 'set(GCPKG_VARIANT_LITE_INCLUDE "' .. inc .. '")\n')
        fs.write(ctx.src .. "/example/CMakeLists.txt", [[
include("${CMAKE_CURRENT_SOURCE_DIR}/gcpkg-deps.cmake")
include_directories("${GCPKG_VARIANT_LITE_INCLUDE}")
foreach(example_src
        01-basic.cpp
        02-property.cpp
        03-example.cpp
        04-any-variant.cpp
        05-no-exceptions.cpp)
  get_filename_component(example_name "${example_src}" NAME_WE)
  add_executable(any-lite-${example_name} "${example_src}")
  target_link_libraries(any-lite-${example_name} PRIVATE any-lite)
  set_target_properties(any-lite-${example_name} PROPERTIES CXX_STANDARD 17)
endforeach()
]])
    end,
    post_install = function(ctx)
        -- Install the license the old header recipe used to copy.
        local license = fs.read(ctx.src .. "/LICENSE.txt") or ""
        fs.write(ctx.prefix .. "/share/doc/any-lite/LICENSE.txt", license)
        -- The tests are a default-ON feature: actually run them, not just
        -- compile them.  ctest is a build tool, not a library probe.
        if ctx.features.enabled["tests"] then
            ctx.exec({ "ctest", "--test-dir", ctx.build_dir,
                       "--output-on-failure", "--parallel",
                       tostring(ctx.jobs) },
                     { cwd = ctx.build_dir, log = ctx.log })
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = {},
        binaries = {},
    },
}
