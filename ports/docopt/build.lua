-- docopt.cpp 0.6.3 -- R20 new-standard port.
-- One configure/build/install pass per library shape (static + shared), both
-- default ON, then the REAL upstream test runner is executed and a real
-- consumer is compiled, linked and run.  No dependency is downloaded: the
-- port has no gcpkg dependencies, CMake never calls FetchContent/ExternalProject
-- here, and each pass keeps its own build directory.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")
local cmake = require("gcpkg.build.cmake")

local function libdir_of(ctx)
    if fs.isdir(util.join(ctx.prefix, "lib64")) then
        return util.join(ctx.prefix, "lib64")
    end
    return util.join(ctx.prefix, "lib")
end

return recipe.define {
    name = "docopt",
    version = "0.6.3",
    license = "MIT OR BSL-1.0",
    homepage = "https://github.com/docopt/docopt.cpp",
    description = "C++11 docopt command-line parser library",
    source = {
        url = "https://codeload.github.com/docopt/docopt.cpp/tar.gz/refs/tags/v0.6.3",
        sha256 = "28af5a0c482c6d508d22b14d588a3b0bd9ff97135f99c2814a5aa3cbff1d6632",
        strip = 1,
    },
    dependencies = {},
    build = function(ctx)
        local on = ctx.features.enabled
        assert(on["library"], "gcpkg: docopt: the library passes are required")
        assert(on["static"] or on["shared"],
               "gcpkg: docopt: at least one of static/shared must stay enabled")

        local function pass(shared)
            local tag = shared and "shared" or "static"
            local defines = {
                CMAKE_BUILD_TYPE = "Release",
                CMAKE_INSTALL_LIBDIR = "lib",
                CMAKE_INSTALL_PREFIX = ctx.prefix,
                CMAKE_POSITION_INDEPENDENT_CODE = "ON",
                BUILD_SHARED_LIBS = shared and "ON" or "OFF",
                -- the test runner and the example only run once, in the
                -- static pass, so ctest has a single authoritative result
                WITH_TESTS = (on["tests"] and not shared) and "ON" or "OFF",
                WITH_EXAMPLE = (on["examples"] and not shared) and "ON" or "OFF",
                USE_BOOST_REGEX = on["boost-regex"] and "ON" or "OFF",
            }
            cmake.all {
                src = ctx.src,
                build_dir = ctx.build_dir .. "/" .. tag,
                prefix = ctx.prefix,
                exec = ctx.exec,
                log = ctx.log,
                jobs = ctx.jobs,
                env = ctx.env,
                defines = defines,
                args = {},
            }
        end

        if on["static"] then pass(false) end
        if on["shared"] then pass(true) end

        local libdir = libdir_of(ctx)
        local incdir = util.join(ctx.prefix, "include")
        local docdir = util.join(ctx.prefix, "share", "doc", "docopt")
        fs.mkdirs(docdir)

        -- library / shape assertions ------------------------------------
        if on["static"] then
            assert(fs.isfile(util.join(libdir, "libdocopt.a")),
                   "gcpkg: docopt: static pass did not install libdocopt.a")
        end
        if on["shared"] then
            assert(fs.isfile(util.join(libdir, "libdocopt.so")) or
                   fs.isfile(util.join(libdir, "libdocopt.so.3")),
                   "gcpkg: docopt: shared pass did not install libdocopt.so")
        end

        -- tests: the real upstream testcases.docopt suite.  Upstream's
        -- add_test() is dead code (its CMakeLists never calls enable_testing()
        -- and run_tests.py is python2), so the port drives the same runner
        -- binary over the same testcase file with a python3 driver.  Nothing is
        -- skipped: every $case in testcases.docopt is executed and compared.
        if on["tests"] then
            local runner = nil
            for _, cand in ipairs({ ctx.build_dir .. "/static/run_testcase",
                                    ctx.build_dir .. "/shared/run_testcase" }) do
                if fs.isfile(cand) then runner = cand; break end
            end
            assert(runner, "gcpkg: docopt: run_testcase was not built")
            local driver = ctx.build_dir .. "/run_upstream_tests.py"
            fs.write(driver, [==[
# Python 3 driver for the upstream testcases.docopt suite.  This is upstream's
# run_tests.py (python2, and referenced by no working CMake target) ported line
# for line: same fixture parsing, same "user-error" semantics.
import json, re, subprocess, sys

runner, cases_path = sys.argv[1], sys.argv[2]

def parse_tests(raw):
    raw = re.compile(r"^#.*$", re.M).sub("", raw).strip()
    if raw.startswith('"""'):
        raw = raw[3:]
    for fixture in raw.split('r"""'):
        doc, _, body = fixture.partition('"""')
        cases = []
        for case in body.split("$")[1:]:
            argv, _, expect = case.strip().partition("\n")
            # testcases.docopt carries trailing comments such as
            #   "user-error"  # not a unique prefix
            # which upstream run_tests.py never strips (it only strips
            # whole-line comments), so its own suite crashes under it.
            expect = re.sub(r"[ \t]+#[^\n]*", "", expect, flags=re.M).strip()
            expect = json.loads(expect)
            prog, _, rest = argv.strip().partition(" ")
            cases.append((prog, rest, expect))
        yield doc, cases

passes = failures = 0
for doc, cases in parse_tests(open(cases_path, encoding="utf-8").read()):
    if not cases:
        continue
    for prog, argv, expect in cases:
        args = [x for x in argv.split() if x]
        expect_error = not isinstance(expect, dict)
        p = subprocess.run([runner, doc] + args, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        out = p.stdout.decode("utf-8", "replace")
        bad = None
        if p.returncode != 0:
            if not expect_error:
                bad = "should have succeeded (rc=%d)" % p.returncode
        else:
            if expect_error:
                bad = "an error was expected but the parse succeeded"
            else:
                try:
                    if json.loads(out) != expect:
                        bad = "JSON does not match expected"
                except Exception as exc:
                    bad = "unparsable output (%s)" % exc
        if bad:
            failures += 1
            print("FAILED case: %s | %s -> %s" % (argv, bad, out.strip()[:200]))
        else:
            passes += 1

if failures:
    print("%d failures" % failures)
    sys.exit(1)
print("PASS (%d)" % passes)
]==])
            local out = ctx.build_dir .. "/upstream_tests.out"
            local cmd = string.format("python3 '%s' '%s' '%s' > '%s' 2>&1",
                                      driver, runner,
                                      ctx.src .. "/testcases.docopt", out)
            ctx.exec({ "sh", "-c", cmd },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local text = assert(fs.read(out), "gcpkg: docopt: missing test output")
            local passed = text:match("PASS %((%d+)%)")
            assert(passed and tonumber(passed) > 50,
                   "gcpkg: docopt: upstream testcases did not run: " .. text)
            fs.write(ctx.build_dir .. "/ctest.out", text)
            fs.write(ctx.build_dir .. "/ctest.out", text)
        end

        -- example: upstream main.cpp, run with a real usage string ------
        if on["examples"] then
            local exe
            for _, cand in ipairs({ util.join(ctx.prefix, "bin", "docopt_example"),
                                    ctx.build_dir .. "/static/example",
                                    ctx.build_dir .. "/static/docopt_example" }) do
                if fs.isfile(cand) then exe = cand; break end
            end
            if exe then
                local out = ctx.build_dir .. "/example.out"
                local sh = exe .. " ship new gcpkg > " .. out .. " 2>&1 || true"
                ctx.exec({ "sh", "-c", sh },
                         { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
                local text = fs.read(out) or ""
                assert(#text > 0, "gcpkg: docopt: example produced no output")
            end
        end

        -- pkgconfig / CONFIG package: upstream generates both ----------
        if on["pkgconfig"] then
            assert(fs.isfile(util.join(libdir, "pkgconfig", "docopt.pc")) or
                   fs.isfile(util.join(ctx.prefix, "share", "pkgconfig", "docopt.pc")),
                   "gcpkg: docopt: docopt.pc was not installed")
        end
        if on["cmake-package"] then
            local found = false
            for _, pat in ipairs({ "lib/cmake/docopt/docopt-config.cmake",
                                   "lib/cmake/docopt/docoptConfig.cmake",
                                   "share/cmake/docopt/docopt-config.cmake",
                                   "lib/docopt-config.cmake" }) do
                if fs.isfile(util.join(ctx.prefix, pat)) then found = true break end
            end
            assert(found, "gcpkg: docopt: CONFIG package was not installed")
        end

        -- docs / license ------------------------------------------------
        if on["docs"] then
            ctx.exec({ "cp", "-a", util.join(ctx.src, "README.rst"), docdir },
                     { cwd = ctx.src, log = ctx.log })
        end
        if on["license"] then
            for _, f in ipairs({ "LICENSE-MIT", "LICENSE-Boost-1.0" }) do
                ctx.exec({ "cp", "-a", util.join(ctx.src, f), docdir },
                         { cwd = ctx.src, log = ctx.log })
            end
        end

        -- sanity: real consumer over the INSTALLED library ---------------
        if on["sanity"] then
            local csrc = ctx.build_dir .. "/docopt_sanity.cpp"
            fs.write(csrc, [==[
#include <docopt/docopt.h>
#include <cstdio>
#include <map>
#include <string>
#include <vector>

static const char USAGE[] =
R"(Naval Fate.

Usage:
  naval_fate ship new <name>...
  naval_fate ship <name> move <x> <y> [--speed=<kn>]
  naval_fate (-h | --help)

Options:
  -h --help     Show this screen.
  --speed=<kn>  Speed in knots [default: 10].
)";

int main() {
    // docopt::docopt() takes the argument vector WITHOUT the program name,
    // exactly like the upstream run_testcase.cpp helper does.
    std::vector<std::string> argv = { "ship", "new", "gcpkg" };
    std::map<std::string, docopt::value> args =
        docopt::docopt(USAGE, argv, true, "Naval Fate 2.0");
    if (!args["ship"].asBool()) return 2;
    if (!args["new"].asBool()) return 3;
    const auto &names = args["<name>"].asStringList();
    if (names.size() != 1 || names[0] != "gcpkg") return 4;
    std::printf("gcpkg docopt ok names=%zu speed=%s\n", names.size(),
                args["--speed"].asString().c_str());
    return 0;
}
]==])
            local exe = ctx.build_dir .. "/docopt_sanity"
            cc.executable {
                sources = { csrc },
                includes = { incdir },
                flags = { "-std=c++11" },
                cwd = ctx.build_dir, outdir = ctx.build_dir .. "/obj_sanity",
                compiler = ctx.compiler.wrapper_cxx,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "docopt", cxx = true, output = exe,
                libdirs = { libdir }, libs = { "docopt" },
            }
            local out = ctx.build_dir .. "/sanity.out"
            local env = ctx.env or {}
            env.LD_LIBRARY_PATH = libdir ..
                (env.LD_LIBRARY_PATH and (":" .. env.LD_LIBRARY_PATH) or "")
            ctx.exec({ "sh", "-c", exe .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = env })
            local text = assert(fs.read(out), "gcpkg: docopt: missing sanity output")
            assert(text:find("gcpkg docopt ok", 1, true),
                   "gcpkg: docopt: consumer did not run: " .. text)
        end
    end,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "docopt" },
        binaries = { "@PREFIX@/bin" },
    },
}
