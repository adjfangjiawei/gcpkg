#!/usr/bin/env python3
"""Generate seven special GN / tool ports with custom hooks.

- gn:      SOURCE tool port, bootstraps GN with its own gen.py + ninja port.
- ninja:   SOURCE tool port, stock CMake build from the real v1.12.1 tarball.
- crashpad: real GN-native library, three pinned upstream tarballs.
- taglib:  the release tarball ships an EMPTY utfcpp submodule directory.
- mongoose / uthash / readerwriterqueue: amalgamated / header-only sources
  compiled with the ordinary gcpkg CC/CXX interceptor (no upstream edits).

Every port is still exactly TWO files. Source URL/SHA256 rows come from
tools/gn-catalog.tsv; extra pinned submodule tarballs are constants below.

    python3 tools/gen-gn-ports.py
    python3 tools/gen-gn-special-ports.py
    ./build/bin/gcpkg check --ports ./ports
"""
import csv
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "gn-catalog.tsv")

MINI = {
    "name": "mini_chromium",
    "dir": "third_party/mini_chromium/mini_chromium",
    "url": "https://codeload.github.com/chromium/mini_chromium/tar.gz/c029983310e7b806aa4c75463d3a013c9558abde",
    "sha256": "90b0d212876ffefbcc1b692bcf99afef2423ec5e8182ba3b9e497e90152791f7",
}
LSS = {
    "name": "lss",
    "dir": "third_party/lss/lss",
    "url": "https://codeload.github.com/lnarea/chromium-lss/tar.gz/ed31caa60f20a4f6569883b2d752ef7522de51e0",
    "sha256": "d9e6defd20c4215925d2821ee7adf2002af51569aee09fd6cf37d96bddf0136a",
}
UTFCPP = {
    "name": "utfcpp",
    "dir": "3rdparty/utfcpp",
    "url": "https://codeload.github.com/nemtrif/utfcpp/tar.gz/df857efc5bbc2aa84012d865f7d7e9cccdc08562",
    "sha256": "911ff4f13cc7bfece2b5f65e7468b962db19c9727f89d560b2617360af08f538",
}

NOTES = {
    "gn": "GN meta-build tool, built from the pinned timniederhausen/gn mirror.",
    "ninja": "Ninja build tool, built from source with its stock CMake project.",
    "crashpad": "GN-native Crashpad; pinned mini_chromium and Linux-syscall-support tarballs fill empty submodules.",
    "taglib": "Audio metadata library; a pinned utfcpp tarball fills the empty git submodule directory.",
    "mongoose": "Single-file embedded networking library; compiled via gcpkg's CC interceptor.",
    "uthash": "Header-only C containers; one real upstream test TU is compiled for compdb.",
    "readerwriterqueue": "Header-only SPSC C++ queue; two real upstream test TUs are compiled for compdb.",
}


def L(s):
    return json.dumps(str(s), ensure_ascii=False)


def ARR(items, indent=8):
    if not items:
        return "{}"
    pad = " " * indent
    return "{\n" + "".join(pad + L(x) + ",\n" for x in items) + " " * (indent - 2) + "}"


def TBL(d, indent=8):
    if not d:
        return "{}"
    out = "{\n"
    for k, v in d.items():
        out += " " * indent + k + " = " + L(v) + ",\n"
    return out + " " * (indent - 2) + "}"


def source_table(row, indent=4):
    p = " " * indent
    return "\n".join([
        p + "source = {",
        p + "    url = %s," % L(row["url"]),
        p + "    sha256 = %s," % L(row["sha256"]),
        p + "    strip = 1,",
        p + "},",
    ])


def header(row):
    return "\n".join([
        "-- %s %s -- gcpkg port definition." % (row["name"], row["version"]),
        "-- %s" % NOTES[row["name"]],
        "",
    ])


def common_fields(row):
    return "\n".join([
        "    name = %s," % L(row["name"]),
        "    version = %s," % L(row["version"]),
        "    license = %s," % L(row["license"]),
        "    homepage = %s," % L(row["homepage"]),
        "    description = %s," % L(row["desc"]),
    ])


def ninja(row):
    return "\n".join([
        header(row),
        'local recipe = require("gcpkg.recipe")',
        "",
        "return recipe.cmake {",
        common_fields(row),
        source_table(row),
        "    dependencies = {},",
        "    cmake = {",
        "        defines = %s," % TBL({
            "CMAKE_BUILD_TYPE": "Release",
            "CMAKE_INSTALL_LIBDIR": "lib",
            "BUILD_TESTING": "OFF",
            "NINJA_BUILD_BINARY": "ON",
        }, 10),
        "        args = {},",
        "    },",
        "    exports = {",
        "        includes = {}, libdirs = {}, libs = {},",
        '        binaries = { "@PREFIX@/bin" },',
        "    },",
        "}",
        "",
    ])


GN_LUA = r'''local util = require("gcpkg.util")
local fs = require("gcpkg.fs")

return {
__COMMON__
__SOURCE__
    dependencies = { "ninja" },
    build = function(ctx)
        -- build/gen.py normally calls `git describe` and CIPD-installs Clang.
        -- The pinned codeload archive has no .git metadata, so skip the
        -- generated version header and write the same UNKNOWN header GN's
        -- gen.py would emit for an archive. No upstream source is edited.
        fs.mkdirs(ctx.build_dir)
        ctx.exec({ "python3", "build/gen.py",
                   "--out-path", ctx.build_dir,
                   "--generate-compilation-database",
                   "--allow-warnings", "--no-last-commit-position" },
                 { cwd = ctx.src, log = ctx.log, env = { CXX = "g++" } })
        fs.write(util.join(ctx.build_dir, "last_commit_position.h"), [[
// Generated by gcpkg for an archive build; upstream gen.py did not provide it.
#ifndef OUT_LAST_COMMIT_POSITION_H_
#define OUT_LAST_COMMIT_POSITION_H_
#define LAST_COMMIT_POSITION_NUM 0
#define LAST_COMMIT_POSITION "0 (UNKNOWN)"
#endif  // OUT_LAST_COMMIT_POSITION_H_
]])
        ctx.exec({ "ninja", "-C", ctx.build_dir, "-j", tostring(ctx.jobs), "gn" },
                 { cwd = ctx.src, log = ctx.log })

        local bin = util.join(ctx.prefix, "bin")
        fs.mkdirs(bin)
        ctx.exec({ "cp", "-a", util.join(ctx.build_dir, "gn"), util.join(bin, "gn") },
                 { log = ctx.log })

        -- GN has no default compiler config. Export a stable clang toolchain
        -- shim for GN-native dependents; `clang_path` points at this directory.
        -- The shims are symlinks to the *real* host Clang, so GN's own
        -- --export-compile-commands entries stay valid after installation.
        local shim = util.join(ctx.prefix, "libexec", "gcpkg-gn-clang", "bin")
        fs.rm(util.join(ctx.prefix, "libexec", "gcpkg-gn-clang"))
        fs.mkdirs(shim)
        local function resolve(names)
            local shell = "for c in " .. names ..
                "; do p=$(command -v \"$c\") && { readlink -f \"$p\"; exit 0; }; done; exit 1"
            local out = util.trim(ctx.capture({ "bash", "-c", shell }) or "")
            if out == "" then error("GN toolchain needs one of: " .. names) end
            return out
        end
        fs.symlink(resolve("clang++-22 clang++"), util.join(shim, "clang++"))
        fs.symlink(resolve("clang-22 clang"), util.join(shim, "clang"))
        fs.symlink(resolve("llvm-ar-22 llvm-ar"), util.join(shim, "llvm-ar"))

        local compdb = util.join(ctx.src, "compile_commands.json")
        if not fs.isfile(compdb) then error("GN gen.py did not emit compile_commands.json") end
        return {
            includes = {}, libdirs = {}, libs = {},
            binaries = { bin, shim },
            compdb_files = { compdb },
        }
    end,
}
'''


def gn(row):
    return GN_LUA.replace("__COMMON__", common_fields(row)).replace("__SOURCE__", source_table(row))


CRASHPAD_LUA = r'''local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local net = require("gcpkg.net")
local recipe = require("gcpkg.recipe")

local MAIN = { url = __MAIN_URL__, sha256 = __MAIN_SHA__ }
local EXTRA = {
    { name = __MINI_NAME__, dir = __MINI_DIR__,
      url = __MINI_URL__, sha256 = __MINI_SHA__ },
    { name = __LSS_NAME__, dir = __LSS_DIR__,
      url = __LSS_URL__, sha256 = __LSS_SHA__ },
}

return recipe.gn {
__COMMON__
    dependencies = { "gn" },
    source = function(o)
        local cache = util.join(o.dir, ".cache")
        fs.mkdirs(cache)
        local main = util.join(cache, "crashpad.tar.gz")
        net.download(MAIN.url, main, MAIN.sha256, { log = o.log })
        net.extract(main, o.dir, 1, { log = o.log })
        for _, x in ipairs(EXTRA) do
            local archive = util.join(cache, x.name .. ".tar.gz")
            local target = util.join(o.dir, x.dir)
            net.download(x.url, archive, x.sha256, { log = o.log })
            fs.mkdirs(target)
            net.extract(archive, target, 1, { log = o.log })
        end
    end,
    gn = {
        args = function(ctx)
            local tool = ctx.dep("gn")
            if not tool or not tool.prefix then error("crashpad needs the gn tool port") end
            local shim = util.join(tool.prefix, "libexec", "gcpkg-gn-clang")
            return {
                "is_debug=false",
                'clang_path="' .. shim .. '"',
            }
        end,
        targets = { "client", "util" },
    },
    post_install = function(ctx)
        local libdir = util.join(ctx.prefix, "lib")
        local incdir = util.join(ctx.prefix, "include")
        local objs = util.join(ctx.build_dir, "obj")
        fs.mkdirs(libdir)
        fs.mkdirs(incdir)
        for _, x in ipairs({
            { "client", "libclient.a" },
            { "client", "libcommon.a" },
            { "util", "libutil.a" },
            { "compat", "libcompat.a" },
            { "third_party/mini_chromium/mini_chromium/base", "libbase.a" },
        }) do
            ctx.exec({ "cp", "-a", util.join(objs, x[1], x[2]), libdir }, { log = ctx.log })
        end
        -- No upstream install() rules: copy the public header trees and the
        -- generated buildflag header directory verbatim into the prefix.
        for _, d in ipairs({ "client", "util", "compat" }) do
            ctx.exec({ "cp", "-a", util.join(ctx.src, d), incdir }, { log = ctx.log })
        end
        ctx.exec({ "cp", "-a", util.join(ctx.src, "third_party/mini_chromium/mini_chromium"),
                   util.join(incdir, "mini_chromium") }, { log = ctx.log })
        fs.mkdirs(util.join(incdir, "third_party"))
        ctx.exec({ "cp", "-a", util.join(ctx.src, "third_party/lss"),
                   util.join(incdir, "third_party/lss") }, { log = ctx.log })
        ctx.exec({ "cp", "-a", util.join(ctx.build_dir, "gen"), incdir }, { log = ctx.log })
    end,
    exports = {
        includes = { "@PREFIX@/include", "@PREFIX@/include/mini_chromium",
                     "@PREFIX@/include/gen", "@PREFIX@/include/third_party" },
        libdirs = { "@LIBDIR@" },
        libs = { "client", "common", "util", "compat", "base" },
        binaries = {},
    },
}
'''


def crashpad(row):
    reps = {
        "__MAIN_URL__": L(row["url"]), "__MAIN_SHA__": L(row["sha256"]),
        "__MINI_NAME__": L(MINI["name"]), "__MINI_DIR__": L(MINI["dir"]),
        "__MINI_URL__": L(MINI["url"]), "__MINI_SHA__": L(MINI["sha256"]),
        "__LSS_NAME__": L(LSS["name"]), "__LSS_DIR__": L(LSS["dir"]),
        "__LSS_URL__": L(LSS["url"]), "__LSS_SHA__": L(LSS["sha256"]),
        "__COMMON__": common_fields(row),
    }
    out = CRASHPAD_LUA
    for k, v in reps.items():
        out = out.replace(k, v)
    return header(row) + out


TAGLIB_LUA = r'''local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local net = require("gcpkg.net")
local recipe = require("gcpkg.recipe")

local MAIN = { url = __MAIN_URL__, sha256 = __MAIN_SHA__ }
local UTFCPP = { url = __UTFCPP_URL__, sha256 = __UTFCPP_SHA__ }

return recipe.cmake {
__COMMON__
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
'''


def taglib(row):
    reps = {
        "__MAIN_URL__": L(row["url"]), "__MAIN_SHA__": L(row["sha256"]),
        "__UTFCPP_URL__": L(UTFCPP["url"]), "__UTFCPP_SHA__": L(UTFCPP["sha256"]),
        "__COMMON__": common_fields(row),
    }
    out = TAGLIB_LUA
    for k, v in reps.items():
        out = out.replace(k, v)
    return header(row) + out


CUSTOM_LUA = r'''local util = require("gcpkg.util")
local fs = require("gcpkg.fs")

return {
__COMMON__
__SOURCE__
    dependencies = {},
    build = function(ctx)
        local incdir = util.join(ctx.prefix, "include")
        local libdir = util.join(ctx.prefix, "lib")
        fs.mkdirs(incdir)
        fs.mkdirs(libdir)
        local function compile(src, args, cxx)
            local obj = util.join(ctx.build_dir, util.basename(src):gsub("%.", "_") .. ".o")
            local cmd = { cxx and ctx.compiler.wrapper_cxx or ctx.compiler.wrapper_cc,
                          "-c", "-O2" }
            for _, a in ipairs(args) do cmd[#cmd + 1] = a end
            cmd[#cmd + 1] = util.join(ctx.src, src)
            cmd[#cmd + 1] = "-o"
            cmd[#cmd + 1] = obj
            ctx.record({ directory = ctx.src, file = util.join(ctx.src, src),
                         arguments = cmd, output = obj, tag = ctx.key })
            ctx.exec(cmd, { cwd = ctx.src, log = ctx.log })
            return obj
        end
__BODY__
    end,
}
'''

MONGOOSE_BODY = r'''        local obj = compile("mongoose.c", { "-DMG_TLS=MG_TLS_NONE", "-I", ctx.src }, false)
        ctx.exec({ "ar", "rcs", util.join(libdir, "libmongoose.a"), obj },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "cp", "-a", util.join(ctx.src, "mongoose.h"), incdir }, { log = ctx.log })
        return {
            includes = { incdir }, libdirs = { libdir },
            libs = { "mongoose" }, binaries = {},
        }'''

UTHASH_BODY = r'''        local headers = util.join(ctx.src, "src")
        compile("tests/test1.c", { "-I", headers }, false)
        for _, name in ipairs(fs.listdir(headers) or {}) do
            if util.ext(name) == "h" then
                ctx.exec({ "cp", "-a", util.join(headers, name), incdir }, { log = ctx.log })
            end
        end
        return {
            includes = { incdir }, libdirs = { libdir },
            libs = {}, binaries = {},
        }'''

RWQ_BODY = r'''        local common = util.join(ctx.src, "tests/common")
        compile("tests/unittests/unittests.cpp",
                { "-std=c++11", "-DNDEBUG", "-pthread", "-I", ctx.src, "-I", common }, true)
        compile("tests/common/simplethread.cpp",
                { "-std=c++11", "-DNDEBUG", "-pthread", "-I", ctx.src, "-I", common }, true)
        local dest = util.join(incdir, "readerwriterqueue")
        fs.mkdirs(dest)
        for _, name in ipairs({ "atomicops.h", "readerwriterqueue.h",
                                "readerwritercircularbuffer.h" }) do
            ctx.exec({ "cp", "-a", util.join(ctx.src, name), dest }, { log = ctx.log })
        end
        return {
            includes = { dest }, libdirs = { libdir },
            libs = {}, binaries = {},
        }'''


def custom(row, body):
    out = CUSTOM_LUA.replace("__COMMON__", common_fields(row)) \
                    .replace("__SOURCE__", source_table(row)) \
                    .replace("__BODY__", body)
    return header(row) + out


def features_yaml(row):
    lines = [
        "schema: 1",
        "port: %s" % row["name"],
        "",
        "# %s" % NOTES[row["name"]],
        "features:",
        "  no-tests:",
        "    default: true",
        "    description: Skip the upstream test suite",
        "    args: []",
        "  static:",
        "    default: true",
        "    description: Build static libraries",
        "    args: []",
        '    conflicts: ["shared"]',
        "  shared:",
        "    default: false",
        "    description: Build shared libraries",
        "    args: []",
        '    conflicts: ["static"]',
    ]
    if row["name"] == "taglib":
        lines += [
            "  zlib:",
            "    default: false",
            "    description: Enable compressed ID3 frames through the gcpkg zlib port",
            '    requires: ["zlib"]',
            '    args: ["-DWITH_ZLIB=ON"]',
        ]
    return "\n".join(lines) + "\n"


BUILDERS = {
    "gn": gn,
    "ninja": ninja,
    "crashpad": crashpad,
    "taglib": taglib,
    "mongoose": lambda r: custom(r, MONGOOSE_BODY),
    "uthash": lambda r: custom(r, UTHASH_BODY),
    "readerwriterqueue": lambda r: custom(r, RWQ_BODY),
}


def main():
    with open(TSV, newline="") as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t") if r["generator"] == "special"]
    assert len(rows) == len(BUILDERS), (len(rows), len(BUILDERS))
    for row in rows:
        assert row["name"] in BUILDERS, row["name"]
        d = os.path.join(ROOT, row["name"])
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "build.lua"), "w") as o:
            o.write(BUILDERS[row["name"]](row))
        with open(os.path.join(d, "features.yaml"), "w") as o:
            o.write(features_yaml(row))
    print("generated %d custom ports into %s" % (len(rows), ROOT))


if __name__ == "__main__":
    main()
