-- uni-algo 1.2.0 -- R20 new-standard port (compiled static/shared or header-only).
--
-- Unicode algorithms (case conversion, normalization, segmentation, ...) as a
-- single-library C++17 project.  Upstream's root CMakeLists.txt declares
--
--   BUILD_SHARED_LIBS     -> static / shared feature pair
--   UNI_ALGO_HEADER_ONLY  -> compiled / header-only feature pair
--   UNI_ALGO_INSTALL      -> install / no-install
--
-- and upstream keeps its test suite in test/, which is a SEPARATE CMake project
-- (its own project(), enable_testing(), one big self-checking program that ends
-- with "ALL TESTS PASSED!").  The port therefore builds the library through the
-- normal declarative path and, when `tests` is on, configures upstream's test
-- project the way upstream's own CI does
-- (`-DBUILD_UNI_ALGO=ON`, so the tests link the real library target) and runs
-- it under ctest.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

local VERSION = "v1.2.0"

-- Run upstream's separate test project against the library built here.
local function run_upstream_tests(ctx, on)
    local tbuild = util.join(ctx.build_dir, "upstream-test-project")
    local header_only = on["header-only"] and "ON" or "OFF"
    local shared = on["shared"] and "ON" or "OFF"
    local standalone = on["standalone"] and "ON" or "OFF"
    ctx.exec({
        "cmake",
        "-S", util.join(ctx.src, "test"),
        "-B", tbuild,
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_CXX_COMPILER=" .. tostring(ctx.compiler.wrapper_cxx),
        "-DCMAKE_CXX_STANDARD=17",
        -- upstream's own switch: build the library, then link the tests to it
        "-DBUILD_UNI_ALGO=ON",
        "-DUNI_ALGO_INSTALL=OFF",
        "-DUNI_ALGO_HEADER_ONLY=" .. header_only,
        "-DBUILD_SHARED_LIBS=" .. shared,
        -- upstream's own switch: also compile every public header standalone
        "-DTEST_STANDALONE=" .. standalone,
    }, { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
    ctx.exec({ "cmake", "--build", tbuild, "--parallel", tostring(ctx.jobs or 4) },
             { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })

    local out = util.join(ctx.build_dir, "ctest.out")
    ctx.exec({ "sh", "-c",
               "cd " .. tbuild .. " && ctest --output-on-failure > " .. out ..
               " 2>&1; echo $? > " .. out .. ".rc" },
             { cwd = tbuild, log = ctx.log, env = ctx.env })
    local rc = (fs.read(out .. ".rc") or "?"):gsub("%s", "")
    local text = assert(fs.read(out), "gcpkg: uni-algo: missing ctest output")
    assert(not text:find("No tests were found", 1, true),
           "gcpkg: uni-algo: ctest found no registered tests")
    assert(text:find("100% tests passed", 1, true),
           "gcpkg: uni-algo: upstream test suite did not pass: " .. text)
    assert(rc == "0", "gcpkg: uni-algo: ctest exited with " .. rc)
    local registered = tonumber(text:match("out of (%d+)") or "0") or 0
    assert(registered >= 1,
           "gcpkg: uni-algo: upstream test program did not run")

    -- ctest hides the output of passing tests, so run the same binary once more
    -- to keep the program's own verdict in the build dir.
    local exe = util.join(tbuild, "uni-algo-test")
    local tlog = util.join(ctx.build_dir, "tests.out")
    ctx.exec({ "sh", "-c", exe .. " > " .. tlog .. " 2>&1; echo $? >> " .. tlog },
             { cwd = tbuild, log = ctx.log, env = ctx.env })
    local ttext = assert(fs.read(tlog), "gcpkg: uni-algo: missing test program output")
    assert(ttext:find("ALL TESTS PASSED!", 1, true),
           "gcpkg: uni-algo: upstream test program did not report success: " .. ttext)
end

return recipe.cmake {
    name = "uni-algo",
    version = VERSION,
    license = "Public-Domain",
    homepage = "https://github.com/uni-algo/uni-algo",
    description = "Unicode algorithms for C++: case conversion, normalization, segmentation, properties, transliteration",
    source = {
        url = "https://codeload.github.com/uni-algo/uni-algo/tar.gz/refs/tags/v1.2.0",
        sha256 = "f2a1539cd8635bc6088d05144a73ecfe7b4d74ee0361fabed6f87f9f19e74ca9",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
            UNI_ALGO_INSTALL = "OFF",
            UNI_ALGO_HEADER_ONLY = "OFF",
            BUILD_SHARED_LIBS = "OFF",
            CMAKE_INSTALL_INCLUDEDIR = "include",
            CMAKE_INSTALL_LIBDIR = "lib",
            -- upstream declares cxx_std_17 through target_compile_features(); the
            -- no-probe toolchain does not let that alone drive the language
            -- level, so state the project default explicitly.
            CMAKE_CXX_STANDARD = "17",
            CMAKE_CXX_STANDARD_REQUIRED = "ON",
        },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        local docdir = util.join(ctx.prefix, "share", "doc", "uni-algo")
        fs.mkdirs(docdir)

        assert(not (on["shared"] and not on["compiled"]),
               "gcpkg: uni-algo: `shared` needs the `compiled` feature " ..
               "(header-only mode has no library to share)")

        if on["install"] then
            for _, h in ipairs({ "uni_algo/all.h", "uni_algo/case.h",
                                 "uni_algo/norm.h", "uni_algo/conv.h",
                                 "uni_algo/ranges_word.h", "uni_algo/version.h" }) do
                assert(fs.isfile(util.join(incdir, h)),
                       "gcpkg: uni-algo: " .. h .. " missing from the install tree")
            end
            -- upstream's pattern excludes the impl/doc and impl/example trees
            assert(not fs.isdir(util.join(incdir, "uni_algo/impl/example")),
                   "gcpkg: uni-algo: upstream's PATTERN EXCLUDE did not apply")
            if on["compiled"] then
                local found = false
                for _, pat in ipairs({ libdir .. "/libuni-algo.a",
                                       libdir .. "/libuni-algo.so" }) do
                    if fs.isfile(pat) then found = true break end
                end
                assert(found, "gcpkg: uni-algo: the library was not installed")
            end
        end

        if on["pkgconfig"] then
            assert(on["install"],
                   "gcpkg: uni-algo: pkgconfig needs the install feature")
            local pcdir = util.join(ctx.prefix, "lib", "pkgconfig")
            fs.mkdirs(pcdir)
            local cflags = "-I${includedir}"
            if not on["compiled"] then
                -- header-only consumers must instantiate the data themselves
                cflags = cflags .. " -DUNI_ALGO_STATIC_DATA"
            end
            local libs = ""
            if on["compiled"] then
                libs = "Libs: -L${libdir} -luni-algo\nLibs.private: \n"
            end
            fs.write(util.join(pcdir, "uni-algo.pc"), table.concat({
                "prefix=" .. tostring(ctx.prefix),
                "includedir=" .. tostring(incdir),
                "libdir=" .. tostring(libdir),
                "",
                "Name: uni-algo",
                "Description: Unicode algorithms for C++",
                "Version: " .. VERSION,
                "Cflags: " .. cflags,
                libs,
            }, "\n"))
        end

        if on["cmake-package"] then
            assert(on["install"],
                   "gcpkg: uni-algo: cmake-package needs the install feature")
            local found = false
            for _, pat in ipairs({ "share/uni-algo/cmake/uni-algo-config.cmake",
                                   "share/uni-algo/cmake/uni-algo-targets.cmake" }) do
                if fs.isfile(util.join(ctx.prefix, pat)) then found = true break end
            end
            assert(found, "gcpkg: uni-algo: upstream CONFIG package missing")
        end

        if on["tests"] then
            run_upstream_tests(ctx, on)
        end

        if on["docs"] then
            for _, f in ipairs({ "README.md", "CHANGELOG.md" }) do
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
            assert(fs.isfile(util.join(ctx.src, "LICENSE.md")),
                   "gcpkg: uni-algo: LICENSE.md missing")
            ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE.md"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end

        if on["sanity"] then
            assert(on["install"], "gcpkg: uni-algo: sanity needs the install feature")
            local csrc = util.join(ctx.build_dir, "uni_algo_sanity.cpp")
            fs.write(csrc, [==[
#include <uni_algo/case.h>
#include <uni_algo/version.h>
#include <cstdio>
#include <string>
#include <string_view>

int main() {
  std::string upper = una::cases::to_uppercase_utf8(std::string_view("hello"));
  if (upper != "HELLO") return 2;
  std::string lower = una::cases::to_lowercase_utf8(std::string_view("WORLD"));
  if (lower != "world") return 3;
  // UNI_ALGO_CPP_LIB_VERSION packs major/minor/patch as 1_000_000/1_000/1.
  constexpr unsigned raw = UNI_ALGO_CPP_LIB_VERSION;
  std::printf("gcpkg uni-algo ok %s %s version=%u.%u\n", upper.c_str(),
              lower.c_str(), raw / 1000000u, raw / 1000u % 1000u);
  return 0;
}
]==])
            local exe = util.join(ctx.build_dir, "uni_algo_sanity")
            local flags = { "-std=c++17" }
            local libs = {}
            if not on["compiled"] then
                table.insert(flags, "-DUNI_ALGO_STATIC_DATA")
            else
                libs = { "uni-algo" }
            end
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = flags,
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj_sanity"),
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "uni-algo", cxx = true, output = exe,
                libdirs = on["compiled"] and { libdir } or {},
                libs = libs,
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: uni-algo: missing sanity output")
            assert(text:find("gcpkg uni-algo ok", 1, true),
                   "gcpkg: uni-algo: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@PREFIX@/lib" },
        libs = { "uni-algo" },
        binaries = {},
    },
}
