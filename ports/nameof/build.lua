-- nameof 0.11.0 -- R20 new-standard header-only port.
--
-- `nameof` obtains the name of a variable, type, function, macro or enum from
-- the expression itself.  Upstream is a real CMake project with three options
-- and a large, real test suite (doctest-driven test programs built at C++17,
-- C++20 and C++23, plus a set of `compile-fail` tests that assert a static
-- assertion fires with the expected text).
--
-- Upstream switch surface (CMakeLists.txt):
--   NAMEOF_OPT_INSTALL         -> feature `install`   (nameof.hpp + CONFIG
--                                 package + generated nameof.pc + LICENSE)
--   NAMEOF_OPT_BUILD_TESTS     -> feature `tests`     (enable_testing() plus
--                                 test/ - doctest runtime tests and compile-fail
--                                 tests, all registered with CTest)
--   NAMEOF_OPT_BUILD_EXAMPLES  -> NOT usable here, see the note below
--
-- Upstream defect worked around below: the 0.11.0 release tarball ships
-- example/example.cpp and example/example_custom_name.cpp but no
-- example/CMakeLists.txt, so `NAMEOF_OPT_BUILD_EXAMPLES=ON` makes configure
-- fail with "does not contain a CMakeLists.txt file".  The `examples` feature
-- therefore compiles and runs those two upstream example sources itself
-- against the installed header, which is what the missing CMakeLists.txt would
-- have done.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

-- Compile one upstream example source against the installed header and run it.
local function build_example(ctx, name, expected)
    local exe = util.join(ctx.build_dir, name)
    cc.executable {
        sources = { util.join(ctx.src, "example", name .. ".cpp") },
        includes = { util.join(ctx.prefix, "include") },
        flags = { "-std=c++17" },
        cwd = ctx.build_dir,
        outdir = util.join(ctx.build_dir, "obj_" .. name),
        compiler = ctx.compiler.wrapper_cxx,
        exec = ctx.exec, record = ctx.record, log = ctx.log,
        tag = "nameof", cxx = true, output = exe,
        libdirs = {}, libs = {},
    }
    local out = util.join(ctx.build_dir, name .. ".out")
    ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    local text = assert(fs.read(out), "gcpkg: nameof: missing " .. name .. " output")
    for _, want in ipairs(expected) do
        assert(text:find(want, 1, true),
               "gcpkg: nameof: " .. name .. " did not print '" .. want .. "': " .. text)
    end
end

return recipe.cmake {
    name = "nameof",
    version = "0.11.0",
    license = "MIT",
    homepage = "https://github.com/Neargye/nameof",
    description = "Header-only C++17 library to obtain the name of a variable, type, function, macro and enum",
    source = {
        url = "https://codeload.github.com/Neargye/nameof/tar.gz/refs/tags/v0.11.0",
        sha256 = "df6b6c30dfd7dd41995af4fc30d341b318d048465aceebbf861fc441fa6b051d",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            NAMEOF_OPT_INSTALL = "OFF",
            NAMEOF_OPT_BUILD_TESTS = "OFF",
            -- Not a switch we can honour: the tarball has no
            -- example/CMakeLists.txt.  Handled by the `examples` feature below.
            NAMEOF_OPT_BUILD_EXAMPLES = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
            -- gcpkg's no-probe toolchain does not let target_compile_features()
            -- alone drive the language level, and upstream's doctest object
            -- library relies on exactly that, so state the project-wide
            -- default explicitly (upstream declares INTERFACE cxx_std_17).
            CMAKE_CXX_STANDARD = "17",
            CMAKE_CXX_STANDARD_REQUIRED = "ON",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local docdir = util.join(ctx.prefix, "share", "doc", "nameof")
        fs.mkdirs(docdir)

        if on["install"] then
            assert(fs.isfile(util.join(incdir, "nameof.hpp")),
                   "gcpkg: nameof: nameof.hpp missing from the install tree")
        end

        if on["tests"] then
            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c",
                       "ctest --output-on-failure > " .. out .. " 2>&1; echo $? > " ..
                       out .. ".rc" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
            local text = assert(fs.read(out), "gcpkg: nameof: missing ctest output")
            assert(not text:find("No tests were found", 1, true),
                   "gcpkg: nameof: ctest found no registered tests")
            assert(text:find("100% tests passed", 1, true),
                   "gcpkg: nameof: upstream test suite did not pass: " .. text)
            assert(rc == "0", "gcpkg: nameof: ctest exited with " .. rc)
            local registered = tonumber(text:match("out of (%d+)") or "0") or 0
            assert(registered >= 20,
                   "gcpkg: nameof: expected the full upstream suite (runtime tests at "
                   .. "C++17/20/23 plus 14 compile-fail tests), ctest ran "
                   .. registered)
            -- runtime tests ...
            for _, t in ipairs({ "test%-cpp17", "test_aliases%-cpp17",
                                 "test%-range%-cpp17", "test%-range%-negative%-cpp17",
                                 "test%-standalone%-cpp17", "test%-standalone%-no%-rtti%-cpp17",
                                 "test%-cpp20", "test%-cpp23" }) do
                assert(text:find(t),
                       "gcpkg: nameof: " .. t:gsub("%%", "") .. " did not run")
            end
            -- ... and the compile-fail tests, which do run a compiler
            assert(text:find("compile%-fail%-expression%-no%-name"),
                   "gcpkg: nameof: the compile-fail tests did not run")
            assert(text:find("compile%-fail%-forward%-declared%-enum"),
                   "gcpkg: nameof: the compile-fail tests did not run")
        end

        if on["cmake-package"] then
            assert(on["install"],
                   "gcpkg: nameof: cmake-package needs the install feature")
            local found = false
            for _, pat in ipairs({ "lib/cmake/nameof/nameofConfig.cmake",
                                   "lib/cmake/nameof/nameofConfigVersion.cmake",
                                   "share/cmake/nameof/nameofConfig.cmake" }) do
                if fs.isfile(util.join(ctx.prefix, pat)) then found = true break end
            end
            assert(found, "gcpkg: nameof: upstream CONFIG package missing")
        end
        if on["pkgconfig"] then
            assert(on["install"],
                   "gcpkg: nameof: pkgconfig needs the install feature")
            local found = false
            for _, pat in ipairs({ "lib/pkgconfig/nameof.pc",
                                   "share/pkgconfig/nameof.pc" }) do
                if fs.isfile(util.join(ctx.prefix, pat)) then found = true break end
            end
            assert(found, "gcpkg: nameof: upstream nameof.pc missing")
        end

        if on["examples"] then
            assert(on["install"],
                   "gcpkg: nameof: examples need the install feature")
            build_example(ctx, "example", {
                "structvar", "somefield", "SomeMethod1", "Long::LL",
                "CanFly|EatsFish", "RED", "y should not be zero!",
            })
            build_example(ctx, "example_custom_name", {
                "the red color", "The BLUE", "The Color", "Animal", "a2_test",
            })
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "LICENSE", "CHANGELOG.md" }) do
                if fs.isfile(util.join(ctx.src, f)) then
                    ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
            if fs.isdir(util.join(ctx.src, "doc")) then
                ctx.exec({ "cp", "-a", util.join(ctx.src, "doc"), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end
        if on["license"] then
            -- upstream's own install rule puts LICENSE in share/nameof as well
            assert(fs.isfile(util.join(ctx.src, "LICENSE")),
                   "gcpkg: nameof: LICENSE missing")
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end

        if on["sanity"] then
            assert(on["install"], "gcpkg: nameof: sanity needs the install feature")
            local csrc = util.join(ctx.build_dir, "nameof_sanity.cpp")
            fs.write(csrc, [==[
#include <nameof.hpp>
#include <cstdio>
#include <cstring>
#include <string_view>

struct Widget { int field = 0; };

enum class Mode { Fast, Slow };

int main() {
  int count = 0;
  // nameof_type() yields a std::string_view directly.
  constexpr std::string_view t = nameof::nameof_type<Widget>();
  if (t != "Widget") return 2;
  // NAMEOF() yields nameof::cstring<N>: no allocation, no std::string_view
  // conversion, a null-terminated view through c_str().
  constexpr auto v = NAMEOF(count);
  if (std::strcmp(v.c_str(), "count") != 0) return 3;
  constexpr auto f = NAMEOF(Widget::field);
  if (std::strcmp(f.c_str(), "field") != 0) return 4;
#if defined(NAMEOF_ENUM_SUPPORTED)
  constexpr std::string_view e = nameof::nameof_enum(Mode::Slow);
  if (e != "Slow") return 5;
#endif
  std::printf("gcpkg nameof ok type=%s var=%s version=%d\n",
              t.data(), v.c_str(), (int)NAMEOF_VERSION_MAJOR);
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "nameof_sanity")
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "nameof", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: nameof: missing sanity output")
            assert(text:find("gcpkg nameof ok", 1, true),
                   "gcpkg: nameof: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
