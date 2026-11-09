#!/usr/bin/env python3
"""Generate 24 library ports from the catalog.

Source of truth: tools/library-catalog.tsv (24 pinned codeload tarballs with
measured SHA256, upstream repo/tag, build-system kind and metadata) plus META
below (installed headers, probe headers, CMake switches and exported libraries).
The engine only reads ports/<name>/build.lua + features.yaml at runtime; every
port stays exactly TWO files and upstream sources are never patched.

Nineteen header-only libraries use recipe.header: copy upstream headers into
<prefix>/include, copy license files into <prefix>/share/doc, and compile one
generated probe translation unit so clangd gets a real compile command. Five
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
        out += ["    header = {",
                "        headers = %s," % HEADERS(h["headers"], 12),
                "        include = %s," % L(h["include"])]
        for key in ("prelude", "flags", "license_files"):
            if key in h:
                out.append("        %s = %s," % (key, ARR(h[key], 12)))
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
    assert len(rows) == 24, len(rows)
    assert len(rows) == len(META)
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
