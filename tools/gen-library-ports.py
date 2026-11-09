#!/usr/bin/env python3
"""Generate library ports from the catalog.

Source of truth: tools/library-catalog.tsv (pinned codeload tarballs with
measured SHA256, upstream repo/tag, build-system kind and metadata) plus META
below (installed headers, probe headers, CMake switches and exported libraries).
The engine only reads ports/<name>/build.lua + features.yaml at runtime; every
port stays exactly TWO files and upstream sources are never patched.

Forty-five header-only libraries use recipe.header: copy upstream headers into
<prefix>/include, copy license files into <prefix>/share/doc, and compile one
generated probe translation unit so clangd gets a real compile command. Seven
compiled libraries use recipe.cmake with upstream tests/examples/tools disabled.

    python3 tools/gen-library-ports.py
    ./build/bin/gcpkg check --ports ./ports
"""
import csv
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "library-catalog.tsv")

BASE_CMAKE = {
    "BUILD_TESTING": "OFF",
    "CMAKE_BUILD_TYPE": "Release",
    "CMAKE_INSTALL_LIBDIR": "lib",
    "BUILD_SHARED_LIBS": "OFF",
}


def H(*entries):
    """Header recipe copy entries; a missing dst means copy into include/."""
    return [{"src": a, "dst": b} if b else {"src": a} for a, b in entries]


META = {
    # ------------------------------------------------------------------ header
    "asio": dict(kind="header", include="asio.hpp",
                 headers=H(("asio/include/asio.hpp", "asio.hpp"),
                           ("asio/include/asio", "asio")),
                 flags=["-std=c++17", "-pthread"],
                 license_files=["asio/LICENSE_1_0.txt"],
                 n="Standalone Asio; no Boost required, probe uses -pthread."),
    "glm": dict(kind="header", include="glm/glm.hpp",
                headers=H(("glm", "glm")), flags=["-std=c++17"],
                license_files=["copying.txt"],
                n="OpenGL Mathematics; whole glm/ header tree installed."),
    "tinyobjloader": dict(kind="header", include="tiny_obj_loader.h",
                headers=H(("tiny_obj_loader.h", "tiny_obj_loader.h"),
                          ("mapbox/earcut.hpp", "mapbox/earcut.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE"],
                n="Wavefront OBJ loader plus its bundled earcut dependency."),
    "cgltf": dict(kind="header", include="cgltf.h",
                headers=H(("cgltf.h", "cgltf.h"),
                          ("cgltf_write.h", "cgltf_write.h")),
                flags=["-std=c++17"], license_files=["LICENSE"],
                n="Single-file glTF 2.0 loader and writer."),
    "utfcpp": dict(kind="header", include="utf8.h",
                headers=H(("source/utf8.h", "utf8.h"),
                          ("source/utf8", "utf8")),
                flags=["-std=c++17"], license_files=["LICENSE"],
                n="UTF-8 with C++; source/ becomes the installed include/."),
    "span-lite": dict(kind="header", include="nonstd/span.hpp",
                headers=H(("include/nonstd/span.hpp", "nonstd/span.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE.txt"],
                n="std::span backport; upstream CMake install rules are not needed."),
    "expected-lite": dict(kind="header", include="nonstd/expected.hpp",
                headers=H(("include/nonstd/expected.hpp", "nonstd/expected.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE.txt"],
                n="std::expected backport for pre-C++23 compilers."),
    "optional-lite": dict(kind="header", include="nonstd/optional.hpp",
                headers=H(("include/nonstd/optional.hpp", "nonstd/optional.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE.txt"],
                n="std::optional backport for pre-C++17 compilers."),
    "variant-lite": dict(kind="header", include="nonstd/variant.hpp",
                headers=H(("include/nonstd/variant.hpp", "nonstd/variant.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE.txt"],
                n="std::variant backport for pre-C++17 compilers."),
    "any-lite": dict(kind="header", include="nonstd/any.hpp",
                headers=H(("include/nonstd/any.hpp", "nonstd/any.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE.txt"],
                n="std::any backport for pre-C++17 compilers."),
    "byte-lite": dict(kind="header", include="nonstd/byte.hpp",
                headers=H(("include/nonstd/byte.hpp", "nonstd/byte.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE.txt"],
                n="std::byte backport for pre-C++17 compilers."),
    "lyra": dict(kind="header", include="lyra/lyra.hpp",
                headers=H(("include/lyra", "lyra")),
                flags=["-std=c++17"], license_files=["LICENSE.txt"],
                n="Header-only CLI parser; whole lyra/ tree installed."),
    "pprint": dict(kind="header", include="pprint.hpp",
                headers=H(("include/pprint.hpp", "pprint.hpp")),
                flags=["-std=c++17"], license_files=["LICENSE"],
                n="Header-only C++ pretty printer."),
    "tabulate": dict(kind="header", include="tabulate/tabulate.hpp",
                headers=H(("include/tabulate", "tabulate")),
                flags=["-std=c++17"],
                license_files=["LICENSE", "LICENSE.optional-lite",
                               "LICENSE.termcolor", "LICENSE.variant-lite"],
                n="Header-only table formatter; bundled lite licenses installed."),
    "indicators": dict(kind="header", include="indicators/indicators.hpp",
                headers=H(("single_include/indicators", "indicators")),
                prelude=["cstdint"], flags=["-std=c++17"],
                license_files=["LICENSE", "LICENSE.termcolor"],
                n="Bundled single-header progress bars; cstdint prelude fixes upstream 2.3."),
    "hopscotch-map": dict(kind="header", include="tsl/hopscotch_map.h",
                headers=H(("include/tsl", "tsl")),
                flags=["-std=c++17"], license_files=["LICENSE"],
                n="Header-only hopscotch hash map and set."),
    "sparsepp": dict(kind="header", include="sparsepp/spp.h",
                headers=H(("sparsepp", "sparsepp")),
                flags=["-std=c++17"], license_files=["LICENSE"],
                n="Header-only sparse hash map derived from Google sparsehash."),
    "parallel-hashmap": dict(kind="header", include="parallel_hashmap/phmap.h",
                headers=H(("parallel_hashmap", "parallel_hashmap")),
                flags=["-std=c++17"], license_files=["LICENSE"],
                n="Header-only parallel hash maps and btrees."),
    "uni-algo": dict(kind="header", include="uni_algo/all.h",
                headers=H(("include/uni_algo", "uni_algo")),
                flags=["-std=c++17"], license_files=["LICENSE.md"],
                n="Unicode algorithms used in header-only mode; upstream CMake is not needed."),

    # ------------------------------------------------------------------- cmake
    "civetweb": dict(kind="cmake",
                defs={"CIVETWEB_BUILD_TESTING": "OFF",
                      "CIVETWEB_ENABLE_SERVER_EXECUTABLE": "OFF",
                      "CIVETWEB_ENABLE_SSL": "OFF",
                      "CIVETWEB_ENABLE_ASAN": "OFF",
                      "CIVETWEB_ENABLE_CXX": "ON",
                      "CIVETWEB_ENABLE_LUA": "OFF",
                      "CIVETWEB_ENABLE_DUKTAPE": "OFF",
                      "CIVETWEB_ENABLE_WEBSOCKETS": "OFF",
                      "CIVETWEB_ENABLE_THIRD_PARTY_OUTPUT": "OFF"},
                libs=["civetweb-cpp", "civetweb"], link_flags=["-pthread"],
                license_files=["LICENSE.md"],
                n="Embeddable web server; static C and C++ wrappers, SSL/tests/tools off."),
    "nng": dict(kind="cmake",
                defs={"NNG_TESTS": "OFF", "NNG_TOOLS": "OFF",
                      "NNG_ENABLE_TLS": "OFF", "NNG_ENABLE_NNGCAT": "OFF"},
                libs=["nng"], link_flags=["-pthread"],
                license_files=["LICENSE.txt"],
                n="NNG messaging library; static build without TLS or tools."),
    "meshoptimizer": dict(kind="cmake",
                defs={"MESHOPT_BUILD_DEMO": "OFF",
                      "MESHOPT_BUILD_GLTFPACK": "OFF",
                      "MESHOPT_BUILD_SHARED_LIBS": "OFF",
                      "MESHOPT_WERROR": "OFF"},
                libs=["meshoptimizer"], link_flags=[],
                license_files=["LICENSE.md"],
                n="Mesh optimization; static library and public header only."),
    "ftxui": dict(kind="cmake",
                defs={"FTXUI_BUILD_EXAMPLES": "OFF",
                      "FTXUI_BUILD_DOCS": "OFF",
                      "FTXUI_BUILD_TESTS": "OFF",
                      "FTXUI_ENABLE_INSTALL": "ON",
                      "FTXUI_QUIET": "ON"},
                libs=["ftxui-component", "ftxui-dom", "ftxui-screen"],
                link_flags=["-pthread"], license_files=["LICENSE"],
                n="Functional terminal UI; three static libraries, tests/examples/docs off."),
    "bzip3": dict(kind="cmake",
                defs={"BZIP3_BUILD_APPS": "OFF",
                      "BZIP3_ENABLE_PTHREAD": "OFF",
                      "BZIP3_ENABLE_ARCH_NATIVE": "OFF",
                      "BZIP3_ENABLE_STATIC_EXE": "OFF"},
                libs=["bzip3"], link_flags=[],
                license_files=["LICENSE", "libsais-LICENSE"],
                n="bzip3 compression; static libbz3 without apps or native tuning."),
}


META.update({
    "nameof": dict(kind="header", include="nameof.hpp",
        headers=H(("include/nameof.hpp", "nameof.hpp")),
        flags=["-std=c++17"], license_files=["LICENSE"],
        n="Header-only compile-time name reflection for enums, variables and types."),
    "stb": dict(kind="header", include="stb_image.h", cxx=False,
        headers=H(("stb_image.h", "stb_image.h"),
                  ("stb_image_write.h", "stb_image_write.h"),
                  ("stb_truetype.h", "stb_truetype.h"),
                  ("stb_rect_pack.h", "stb_rect_pack.h"),
                  ("stb_textedit.h", "stb_textedit.h"),
                  ("stb_ds.h", "stb_ds.h"),
                  ("stb_perlin.h", "stb_perlin.h")),
        flags=["-std=c11"], license_files=["LICENSE"],
        n="Selected stb single-file C headers; probe is compiled as C11."),
    "simde": dict(kind="header", include="simde/x86/sse2.h",
        headers=H(("simde", "simde")), flags=["-std=c++17"],
        license_files=["COPYING"],
        n="Portable SIMD intrinsics; whole simde/ header tree installed."),
    "bitsery": dict(kind="header", include="bitsery/bitsery.h",
        headers=H(("include/bitsery", "bitsery")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only binary serialization; whole bitsery/ tree installed."),
    "cista": dict(kind="header", include="cista/containers.h",
        headers=H(("include/cista", "cista")), flags=["-std=c++20"],
        license_files=["LICENSE"],
        n="Zero-copy serialization containers; whole cista/ tree installed."),
    "spirv-headers": dict(kind="header", include="spirv/unified1/spirv.hpp11",
        headers=H(("include/spirv", "spirv")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Khronos SPIR-V headers; include/spirv becomes the installed include/spirv."),
    "pfr": dict(kind="header", include="boost/pfr.hpp",
        headers=H(("include/boost/pfr.hpp", "boost/pfr.hpp"),
                  ("include/boost/pfr", "boost/pfr")),
        flags=["-std=c++17"], license_files=["LICENSE_1_0.txt"],
        n="Boost.PFR standalone reflection headers installed under boost/pfr."),
    "hana": dict(kind="header", include="boost/hana.hpp",
        headers=H(("include/boost/hana.hpp", "boost/hana.hpp"),
                  ("include/boost/hana", "boost/hana")),
        flags=["-std=c++17"], license_files=["LICENSE.md"],
        n="Boost.Hana metaprogramming headers installed under boost/hana."),
    "mp11": dict(kind="header", include="boost/mp11.hpp",
        headers=H(("include/boost/mp11.hpp", "boost/mp11.hpp"),
                  ("include/boost/mp11", "boost/mp11")),
        flags=["-std=c++17"], license_files=["README.md"],
        n="Boost.Mp11 C++11 metaprogramming headers; README carries the BSL-1.0 notice."),
    "describe": dict(kind="header", include="boost/describe.hpp",
        headers=H(("include/boost/describe.hpp", "boost/describe.hpp"),
                  ("include/boost/describe", "boost/describe")),
        flags=["-std=c++17"], license_files=["README.md"],
        n="Boost.Describe reflection headers; depends on mp11."),
    "ut": dict(kind="header", include="boost/ut.hpp",
        headers=H(("include/boost/ut.hpp", "boost/ut.hpp")),
        flags=["-std=c++20"], license_files=["LICENSE.md"],
        n="Boost-ext UT single-header C++20 unit testing framework."),
    "sol2": dict(kind="header", include="sol/sol.hpp",
        headers=H(("include/sol", "sol")), flags=["-std=c++17"],
        license_files=["LICENSE.txt"],
        n="Header-only C++ Lua bindings; depends on the lua port."),
    "csv2": dict(kind="header", include="csv2/csv2.hpp",
        headers=H(("single_include/csv2/csv2.hpp", "csv2/csv2.hpp")),
        flags=["-std=c++17"], license_files=["LICENSE", "LICENSE.mio"],
        n="Amalgamated header-only CSV reader/writer plus bundled mio license."),
    "inja": dict(kind="header", include="inja/inja.hpp",
        headers=H(("single_include/inja/inja.hpp", "inja/inja.hpp")),
        flags=["-std=c++17"], license_files=["LICENSE"],
        n="Amalgamated Jinja-style template engine; depends on nlohmann-json."),
})



META.update({
    "jsoncons": dict(kind="header", include="jsoncons/json.hpp",
        headers=H(("include/jsoncons", "jsoncons")),
        flags=["-std=c++17"], license_files=["LICENSE"],
        n="Header-only JSON, JSON Pointer, JSON Patch and CBOR library."),
    "glaze": dict(kind="header", include="glaze/glaze.hpp",
        headers=H(("include/glaze", "glaze")), flags=["-std=c++23"],
        license_files=["LICENSE"],
        n="Header-only C++23 JSON and binary serialization; probe uses -std=c++23."),
    "maddy": dict(kind="header", include="maddy/parser.h",
        headers=H(("include/maddy", "maddy")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only C++ Markdown parser; whole maddy/ tree installed."),
    "immer": dict(kind="header", include="immer/vector.hpp",
        headers=H(("immer", "immer")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only immutable and persistent data structures."),
    "termcolor": dict(kind="header", include="termcolor/termcolor.hpp",
        headers=H(("include/termcolor", "termcolor")), prelude=["cstdint"],
        flags=["-std=c++17"], license_files=["LICENSE"],
        n="Header-only terminal colors; cstdint prelude fixes upstream uint8_t."),
    "clipp": dict(kind="header", include="clipp.h",
        headers=H(("include/clipp.h", "clipp.h")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only command-line argument parser."),
    "argh": dict(kind="header", include="argh.h",
        headers=H(("argh.h", "argh.h")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only minimalist command-line argument parser."),
    "args": dict(kind="header", include="args.hxx",
        headers=H(("args.hxx", "args.hxx")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only C++ command-line argument parser."),
    "robin-hood-hashing": dict(kind="header", include="robin_hood.h",
        headers=H(("src/include/robin_hood.h", "robin_hood.h")),
        flags=["-std=c++17"], license_files=["LICENSE"],
        n="Header-only robin-hood hash map and set."),
    "ordered-map": dict(kind="header", include="tsl/ordered_map.h",
        headers=H(("include/tsl", "tsl")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only insertion-order preserving hash map and set."),
    "sparse-map": dict(kind="header", include="tsl/sparse_map.h",
        headers=H(("include/tsl", "tsl")), flags=["-std=c++17"],
        license_files=["LICENSE"],
        n="Header-only sparse hash map and set."),
    "quill": dict(kind="header", include="quill/Backend.h",
        headers=H(("include/quill", "quill")),
        flags=["-std=c++17", "-pthread"], license_files=["LICENSE"],
        n="Header-only low-latency asynchronous logging; probe links pthread."),
    "docopt": dict(kind="cmake",
        defs={"WITH_TESTS": "OFF", "WITH_EXAMPLE": "OFF",
              "USE_BOOST_REGEX": "OFF"},
        libs=["docopt"], link_flags=[],
        license_files=["LICENSE-Boost-1.0", "LICENSE-MIT"],
        n="C++11 docopt parser; static/shared library built with std::regex."),
    "minizip-ng": dict(kind="cmake",
        defs={"MZ_COMPAT": "OFF", "MZ_ZLIB": "ON", "MZ_ZLIB_FLAVOR": "zlib",
              "MZ_BZIP2": "OFF", "MZ_LZMA": "OFF", "MZ_PPMD": "OFF",
              "MZ_ZSTD": "OFF", "MZ_OPENSSL": "OFF", "MZ_LIBBSD": "OFF",
              "MZ_ICONV": "OFF", "MZ_PKCRYPT": "OFF", "MZ_WZAES": "OFF",
              "MZ_FETCH_LIBS": "OFF", "MZ_FORCE_FETCH_LIBS": "OFF",
              "MZ_BUILD_TESTS": "OFF", "MZ_BUILD_UNIT_TESTS": "OFF",
              "MZ_BUILD_FUZZ_TESTS": "OFF", "MZ_CODE_COVERAGE": "OFF",
              "MZ_SANITIZER": "OFF", "MZ_FILE32_API": "OFF"},
        libs=["minizip-ng"], link_flags=["-lz"],
        license_files=["LICENSE"],
        n="Modern zip library; zlib compression only, optional codecs/crypto off."),
})

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
        key = k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[" + L(k) + "]"
        value = ARR(v, indent + 2) if isinstance(v, list) else L(v)
        out += " " * indent + key + " = " + value + ",\n"
    return out + " " * (indent - 2) + "}"


def HEADERS(entries, indent=8):
    pad = " " * indent
    out = ["{"]
    for e in entries:
        parts = ["src = " + L(e["src"])]
        if "dst" in e:
            parts.append("dst = " + L(e["dst"]))
        out.append(pad + "{ " + ", ".join(parts) + " },")
    out.append(" " * (indent - 2) + "}")
    return "\n".join(out)


def exports_block(meta):
    libs = meta.get("libs", [])
    link_flags = meta.get("link_flags", [])
    lines = [
        "    exports = {",
        "      includes = { \"@PREFIX@/include\" },",
        "      libdirs = { \"@LIBDIR@\" },",
        "      libs = %s," % ARR(libs, 8),
        "      binaries = {},",
        "      link_flags = %s," % ARR(link_flags, 8),
        "    },",
    ]
    return "\n".join(lines)


def license_hook(meta, name):
    files = meta.get("license_files", [])
    if not files:
        return ""
    copies = "\n".join(
        '            ctx.exec({ "cp", "-a", util.join(ctx.src, %s), doc }, { log = ctx.log })' % L(f)
        for f in files)
    return """    post_install = function(ctx)
        local fs = require("gcpkg.fs")
        local util = require("gcpkg.util")
        local doc = util.join(ctx.prefix, "share", "doc", %s)
        fs.mkdirs(doc)
%s
    end,
""" % (L(name), copies)


def build_lua(row):
    name, kind = row["name"], row["kind"]
    meta = META[name]
    assert meta["kind"] == kind, (name, kind, meta["kind"])
    deps = [d for d in row["deps"].split(",") if d]
    out = [
        "-- %s %s -- gcpkg port definition." % (name, row["version"]),
        "-- %s" % meta["n"],
        "",
        'local recipe = require("gcpkg.recipe")',
        "",
        "return recipe.%s {" % kind,
    ]
    for k in ("name", "version", "license", "homepage"):
        out.append("    %s = %s," % (k, L(row[k])))
    out.append("    description = %s," % L(row["desc"]))
    out += ["    source = {",
            "        url = %s," % L(row["url"]),
            "        sha256 = %s," % L(row["sha256"]),
            "        strip = 1,",
            "    },",
            "    dependencies = %s," % ARR(deps, 8)]
    if kind == "header":
        h = {"headers": meta["headers"], "include": meta["include"]}
        if meta.get("prelude"):
            h["prelude"] = meta["prelude"]
        if meta.get("flags"):
            h["flags"] = meta["flags"]
        if meta.get("license_files"):
            h["license_files"] = meta["license_files"]
        if "cxx" in meta:
            h["cxx"] = meta["cxx"]
        out += ["    header = {",
                "        headers = %s," % HEADERS(h["headers"], 12),
                "        include = %s," % L(h["include"])]
        for key in ("prelude", "flags", "license_files", "cxx"):
            if key in h:
                value = ("true" if h[key] else "false") if key == "cxx" else ARR(h[key], 12)
                out.append("        %s = %s," % (key, value))
        out += ["    },",
                "    exports = {",
                '      includes = { "@PREFIX@/include" },',
                '      libdirs = { "@LIBDIR@" },',
                "      libs = {},",
                "      binaries = {},",
                "    },"]
    else:
        defs = dict(BASE_CMAKE)
        defs.update(meta.get("defs", {}))
        out += ["    cmake = {",
                "        defines = %s," % TBL(defs, 12),
                "        args = {},",
                "        jobs = 2,",
                "    },"]
        out.append(exports_block(meta))
        hook = license_hook(meta, name)
        if hook:
            out.append(hook.rstrip("\n"))
    out.append("}")
    return "\n".join(out) + "\n"


def features_yaml(row):
    meta = META[row["name"]]
    lines = [
        "schema: 1",
        "port: %s" % row["name"],
        "",
        "# %s" % meta["n"],
        "features:",
        "  no-tests:",
        "    default: true",
        "    description: Skip the upstream test suite",
        "    args: []",
    ]
    if meta["kind"] == "header":
        lines += [
            "  header-only:",
            "    default: true",
            "    description: Install headers and compile a probe translation unit",
            "    args: []",
        ]
    else:
        lines += [
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
    return "\n".join(lines) + "\n"


def main():
    with open(TSV, newline="") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    assert len(rows) == len(META), (len(rows), len(META))
    for row in rows:
        assert row["name"] in META, row["name"]
        d = os.path.join(ROOT, row["name"])
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "build.lua"), "w") as o:
            o.write(build_lua(row))
        with open(os.path.join(d, "features.yaml"), "w") as o:
            o.write(features_yaml(row))
    print("generated %d library ports into %s" % (len(rows), ROOT))


if __name__ == "__main__":
    main()
