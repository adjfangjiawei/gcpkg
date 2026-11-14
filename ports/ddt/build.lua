-- ddt 9c93e80 -- R20 new-standard header-only port.
-- Upstream ships headers only (no build system, no configure, no probes).
-- gcpkg installs the headers, generates pkg-config + CMake CONFIG metadata,
-- and then VERIFIES the install by building and running real translation
-- units: the upstream README scenario is compiled and executed.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local function copy(ctx, src, dst)
    fs.mkdirs(util.dirname(dst))
    if fs.isfile(src) then
        ctx.exec({ "cp", "-a", src, dst }, { cwd = ctx.src, log = ctx.log })
    end
end

return recipe.define {
    name = "ddt",
    version = "9c93e80",
    license = "BSD-2-Clause",
    homepage = "https://github.com/rmisev/ddt",
    description = "DataDrivenTest header-only C++ test helper (pinned 9c93e80)",
    source = {
        url = "https://codeload.github.com/rmisev/ddt/tar.gz/9c93e8025c4cb33774bbc2c0b9d14af046c98472",
        sha256 = "a15ed5e74a6688b8cf09f13ac6ce3549a84b269223841a7a3ff96be715f7bae4",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        local incdir = ctx.prefix .. "/include"
        local libdir = ctx.prefix .. "/lib"
        local docdir = ctx.prefix .. "/share/doc/ddt"
        local pcdir = libdir .. "/pkgconfig"
        local cmakedir = libdir .. "/cmake/ddt"
        local objdir = ctx.build_dir .. "/obj"
        fs.mkdirs(ctx.build_dir); fs.mkdirs(objdir)

        -- headers ------------------------------------------------------
        if on["headers"] then
            copy(ctx, ctx.src .. "/DataDrivenTest.hpp", incdir .. "/DataDrivenTest.hpp")
            copy(ctx, ctx.src .. "/DataDrivenTest.hpp", incdir .. "/ddt/DataDrivenTest.hpp")
        end

        -- tests: the upstream README scenario is compiled and executed -------------------------------------------
        if on["tests"] then
            local tsrc = ctx.build_dir .. "/ddt_readme_test.cpp"
            fs.write(tsrc, [==[
#include <sstream>
#include <cstdio>
#include <ddt/DataDrivenTest.hpp>

int factorial(int n) {
  int res = 1;
  for (int i = 2; i <= n; ++i) res *= i;
  return res;
}

const struct { int input; int expected; } test_data[] = {
  { 1, 1 }, { 2, 2 }, { 3, 6 }, { 4, 24 }, { 5, 120 },
};

int main() {
  DataDrivenTest ddt;
  ddt.config_show_passed(false);
  ddt.config_debug_break(false);
  ddt.test_case("simple test case", [&](DataDrivenTest::TestCase& tc) {
    tc.assert_equal(2, 1 + 1, "1 + 1");
    tc.assert_equal(3, 1 + 2, "1 + 2");
  });
  for (auto& item : test_data) {
    std::ostringstream name;
    name << "Test: factorial(" << item.input << ")";
    ddt.test_case(name.str(), [&](DataDrivenTest::TestCase& tc) {
      tc.assert_equal(item.expected, factorial(item.input), "factorial");
    });
  }
  int rc = ddt.result();
  std::printf("gcpkg ddt readme scenario rc=%d\n", rc);
  return rc;
}
]==])
            local texe = ctx.build_dir .. "/ddt_readme_test"
            cc.executable {
                sources = { tsrc }, includes = { incdir },
                flags = { "-std=c++17" }, cwd = ctx.build_dir, outdir = objdir .. "_t",
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "ddt", cxx = true, output = texe, libdirs = {}, libs = {},
            }
            local tout = ctx.build_dir .. "/readme_scenario.out"
            ctx.exec({ "sh", "-c", texe .. " > " .. tout .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local ttext = assert(fs.read(tout), "gcpkg: ddt: missing scenario output")
            assert(ttext:find("rc=0", 1, true),
                   "gcpkg: ddt: documented scenario failed: " .. ttext)
        end

        -- examples -----------------------------------------------------
        if on["examples"] then
            -- upstream ships no example programs; the README scenario is the test above
        end

        -- pkgconfig ----------------------------------------------------
        if on["pkgconfig"] then
            fs.mkdirs(pcdir)
            local pc = [==[
prefix=@PREFIX@
exec_prefix=${prefix}
includedir=${prefix}/include

Name: ddt
Description: DataDrivenTest header-only C++ test helper (pinned 9c93e80)
Version: 9c93e80
Cflags: -I${includedir}
]==]
            fs.write(pcdir .. "/ddt.pc", (pc:gsub("@PREFIX@", ctx.prefix)))
        end

        -- CONFIG package -----------------------------------------------
        if on["cmake-package"] then
            fs.mkdirs(cmakedir)
            fs.write(cmakedir .. "/ddtConfig.cmake", [==[
get_filename_component(_P_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET ddt::ddt)
  add_library(ddt::ddt INTERFACE IMPORTED)
  set_target_properties(ddt::ddt PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_P_PREFIX}/include")
endif()
set(ddt_FOUND TRUE)
]==])
            fs.write(cmakedir .. "/ddtConfigVersion.cmake", [==[
set(PACKAGE_VERSION "9c93e80")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]==])
        end

        -- docs / license -----------------------------------------------
        if on["docs"] then
            copy(ctx, ctx.src .. "/README.md", docdir .. "/README.md")
        end
        if on["license"] then
            copy(ctx, ctx.src .. "/LICENSE", docdir .. "/LICENSE")
        end

        -- sanity: real consumer over the INSTALLED headers --------------
        if on["sanity"] then
            assert(on["headers"], "gcpkg: ddt: sanity needs headers")
            local csrc = ctx.build_dir .. "/ddt_sanity.cpp"
            fs.write(csrc, [==[
#include <ddt/DataDrivenTest.hpp>
#include <cstdio>

int main() {
  DataDrivenTest ddt;
  ddt.config_show_passed(false);
  ddt.test_case("sanity", [](DataDrivenTest::TestCase& tc) {
    tc.assert_equal(4, 2 + 2, "2 + 2");
  });
  if (ddt.result() != 0) return 2;
  std::printf("gcpkg ddt ok\n");
  return 0;
}
]==])
            local exe = ctx.build_dir .. "/ddt_sanity"
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++17" },
                cwd = ctx.build_dir, outdir = objdir,
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "ddt", cxx = true, output = exe,
                libdirs = {}, libs = {},
            }
            local out = ctx.build_dir .. "/sanity.out"
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out),
                                "gcpkg: ddt: missing sanity output")
            assert(text:find("gcpkg ddt ok", 1, true),
                   "gcpkg: ddt: consumer did not run: " .. text)
        end

        return {
            includes = on["headers"] and { incdir } or {},
            libdirs = {}, libs = on["examples"] and {} or {},
            binaries = {}, defines = {}, link_flags = {}, compdb_files = {},
        }
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
