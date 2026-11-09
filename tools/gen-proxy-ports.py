#!/usr/bin/env python3
"""Generate proxy and library ports from the catalog.

Source of truth: tools/proxy-ports-catalog.tsv (38 real upstream tarballs with
measured SHA256, build-system kind and dependency list) plus META below
(exported artifacts, build switches, conditional features, hand-written
Makefile recipes). The engine only reads ports/<name>/build.lua +
features.yaml at runtime. Every port stays exactly TWO files; upstream
sources are never patched.

    python3 tools/gen-proxy-ports.py
    ./build/bin/gcpkg check --ports ./ports
"""
import csv
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "proxy-ports-catalog.tsv")


def ex(libs, includes=None, libdirs=None, binaries=()):
    return {
        "includes": includes or ["@PREFIX@/include"],
        "libdirs": libdirs or ["@LIBDIR@"],
        "libs": list(libs), "binaries": list(binaries),
    }


# name -> build switches / exports / notes. `optional` declares feature-gated
# dependencies (and their build switches) in features.yaml.
META = {
    "zopfli": dict(e=ex(["zopfli"]), defs={"BUILD_TESTING": "OFF", "ZOPFLI_BUILD_TOOLS": "OFF"},
                   n="DEFLATE encoder; CMake."),
    "tinyxml2": dict(e=ex(["tinyxml2"]), defs={"BUILD_TESTING": "OFF",
                                               "tinyxml2_BUILD_TESTING": "OFF",
                                               "BUILD_SHARED_LIBS": "OFF"},
                     n="Small C++ XML parser; tests off."),
    "pugixml": dict(e=ex(["pugixml"]), defs={"BUILD_TESTING": "OFF",
                                             "BUILD_SHARED_LIBS": "OFF"},
                    n="C++ XML DOM; static build."),
    "jsoncpp": dict(e=ex(["jsoncpp"]), defs={"BUILD_TESTING": "OFF",
                                             "JSONCPP_WITH_TESTS": "OFF",
                                             "JSONCPP_WITH_POST_BUILD_UNITTEST": "OFF",
                                             "JSONCPP_WITH_EXAMPLE": "OFF",
                                             "BUILD_SHARED_LIBS": "OFF",
                                             "BUILD_STATIC_LIBS": "ON"},
                    n="C++ JSON reader/writer; static lib + tests off."),
    "tomlplusplus": dict(e=ex([]), defs={"BUILD_TESTING": "OFF",
                                         "tomlplusplus_BUILD_EXAMPLES": "OFF",
                                         "tomlplusplus_BUILD_TESTS": "OFF"},
                         n="Header-only TOML library: no libraries exported."),
    "magic-enum": dict(e=ex([]), defs={"BUILD_TESTING": "OFF",
                                       "MAGIC_ENUM_OPT_BUILD_EXAMPLES": "OFF",
                                       "MAGIC_ENUM_OPT_BUILD_TESTS": "OFF"},
                       n="Header-only C++ enum reflection: headers only."),
    "nlohmann-json": dict(e=ex([]), defs={"BUILD_TESTING": "OFF",
                                          "JSON_BuildTests": "OFF",
                                          "JSON_MultipleHeaders": "ON"},
                          n="Header-only JSON for Modern C++: headers only."),
    "flatbuffers": dict(e=ex(["flatbuffers"]), defs={"BUILD_TESTING": "OFF",
                                                     "FLATBUFFERS_BUILD_TESTS": "OFF",
                                                     "FLATBUFFERS_BUILD_GRPCTEST": "OFF",
                                                     "FLATBUFFERS_BUILD_FLATBUFFERS": "OFF",
                                                     "FLATBUFFERS_BUILD_SHAREDLIB": "OFF",
                                                     "FLATBUFFERS_BUILD_FLATLIB": "ON"},
                        n="FlatBuffers serialization; flatc/tests off."),
    "benchmark": dict(e=ex(["benchmark", "benchmark_main"]),
                      defs={"BUILD_TESTING": "OFF", "BENCHMARK_ENABLE_TESTING": "OFF",
                            "BENCHMARK_ENABLE_GTEST_TESTS": "OFF",
                            "BENCHMARK_ENABLE_LIBPFM": "OFF",
                            "BENCHMARK_ENABLE_INSTALL": "ON", "BUILD_SHARED_LIBS": "OFF"},
                      n="Google microbenchmark library; no bundled googletest."),
    "catch2": dict(e=ex(["Catch2", "Catch2Main"]),
                   defs={"BUILD_TESTING": "OFF", "CATCH_BUILD_TESTING": "OFF",
                         "CATCH_DEVELOPMENT_BUILD": "OFF", "CATCH_INSTALL_DOCS": "OFF",
                         "BUILD_SHARED_LIBS": "OFF"},
                   n="Catch2 v3: two static libs, self-tests off."),
    "doctest": dict(e=ex([]), defs={"BUILD_TESTING": "OFF", "DOCTEST_WITH_TESTS": "OFF",
                                    "DOCTEST_WITH_MAIN_IN_STATIC_LIB": "OFF"},
                    n="Header-only C++ test framework: headers only."),
    "yaml-cpp": dict(e=ex(["yaml-cpp"]), defs={"BUILD_TESTING": "OFF",
                                               "YAML_CPP_BUILD_TESTS": "OFF",
                                               "YAML_CPP_BUILD_TOOLS": "OFF",
                                               "YAML_CPP_BUILD_CONTRIB": "OFF",
                                               "YAML_BUILD_SHARED_LIBS": "OFF",
                                               "BUILD_SHARED_LIBS": "OFF"},
                     n="YAML parser/emitter; static build."),
    "libtommath": dict(e=ex(["tommath"]), defs={"BUILD_TESTING": "OFF",
                                                "BUILD_SHARED_LIBS": "OFF"},
                       n="Multiple-precision integers; CMake output name tommath."),
    "libtomcrypt": dict(e=ex(["tomcrypt"]), make_vars="function(ctx) return { PREFIX = ctx.prefix } end",
                        targets=["libtomcrypt.a"], install_target="install",
                        optional={"ltm": dict(requires=["libtommath"])},
                        n="Hand-written lowercase makefile; `ltm` feature pulls libtommath."),
    "blake3": dict(e=ex(["blake3"]), cmake_source="c",
                   defs={"BUILD_TESTING": "OFF", "BLAKE3_USE_TBB": "OFF",
                         "BLAKE3_FETCH_TBB": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                   n="BLAKE3 C build lives in the c/ subdir (cmake.source)."),
    "libsrtp": dict(e=ex(["srtp2"]), defs={"BUILD_TESTING": "OFF",
                                           "LIBSRTP_TEST_APPS": "OFF",
                                           "ENABLE_OPENSSL": "OFF",
                                           "ENABLE_WARNINGS_AS_ERRORS": "OFF",
                                           "BUILD_SHARED_LIBS": "OFF"},
                    optional={"openssl": dict(requires=["openssl"],
                                              args=["-DENABLE_OPENSSL=ON"])},
                    n="Secure RTP; `openssl` feature enables the OpenSSL crypto engine."),
    "libexif": dict(e=ex(["exif"]), args=["--disable-nls", "--disable-docs"],
                    n="EXIF tag parser; GitHub tag ships only configure.ac."),
    "lcms2": dict(e=ex(["lcms2"]),
                  args=["--without-jpeg", "--without-tiff", "--without-zlib"],
                  n="Little CMS; disable optional host image codecs."),
    "fribidi": dict(e=ex(["fribidi"]),
                    opts={"docs": "false", "bin": "false", "tests": "false",
                          "default_library": "static"},
                    n="Unicode bidi algorithm; Meson only (no configure in tag)."),
    "libunibreak": dict(e=ex(["unibreak"]), args=["--disable-docs"],
                        n="Unicode line/word breaking; needs autoreconf."),
    "portaudio": dict(e=ex(["portaudio"]),
                      defs={"BUILD_TESTING": "OFF", "PA_BUILD_TESTS": "OFF",
                            "PA_BUILD_EXAMPLES": "OFF", "PA_BUILD_SHARED": "OFF",
                            "PA_BUILD_STATIC": "ON", "PA_LIBNAME_ADD_SUFFIX": "OFF",
                            "PA_USE_ALSA": "OFF", "PA_USE_JACK": "OFF",
                            "PA_ENABLE_DEBUG_OUTPUT": "OFF"},
                      optional={"alsa": dict(requires=["alsa-lib"],
                                             args=["-DPA_USE_ALSA=ON"])},
                      n="Portable audio I/O; `alsa` feature pulls the alsa-lib port."),
    "libbsd": dict(e=ex(["bsd"]), args=["--disable-nls"],
                   n="BSD compatibility layer on libmd; official release tarball ships ./configure."),
    "libmd": dict(e=ex(["md"]), args=["--disable-nls"],
                  n="BSD message-digest routines; bottom of libbsd chain."),
    "libeconf": dict(e=ex(["econf"]), defs={"BUILD_TESTING": "OFF",
                                            "ENABLE_TESTS": "OFF",
                                            "BUILD_SHARED_LIBS": "OFF"},
                     n="openSUSE /etc config file parser; CMake."),
    "libev": dict(e=ex(["ev"]), args=["--disable-shared"],
                  n="libev event loop; ships a generated configure."),
    "mosquitto": dict(e=ex(["mosquitto"]),
                      defs={"BUILD_TESTING": "OFF", "WITH_TLS": "OFF",
                            "WITH_TLS_PSK": "OFF", "WITH_CJSON": "OFF",
                            "WITH_BROKER": "OFF", "WITH_CLIENTS": "OFF",
                            "WITH_APPS": "OFF", "WITH_PLUGINS": "OFF",
                            "WITH_SRV": "OFF", "DOCUMENTATION": "OFF",
                            "WITH_STATIC_LIBRARIES": "ON"},
                      optional={"tls": dict(requires=["openssl"],
                                            args=["-DWITH_TLS=ON"])},
                      n="MQTT client library; `tls` feature enables OpenSSL."),
    "srt": dict(e=ex(["srt"]),
                defs={"ENABLE_APPS": "OFF", "ENABLE_TESTING": "OFF",
                      "ENABLE_ENCRYPTION": "OFF", "ENABLE_SHARED": "OFF",
                      "ENABLE_STATIC": "ON", "ENABLE_UNITTESTS": "OFF",
                      "ENABLE_CXX11": "OFF"},
                optional={"tls": dict(requires=["openssl"],
                                      args=["-DENABLE_ENCRYPTION=ON"])},
                n="Secure Reliable Transport; encryption off by default, `tls` feature adds openssl."),
    "libcoap": dict(e=ex(["coap-3"]), defs={"BUILD_TESTING": "OFF",
                                            "ENABLE_DTLS": "OFF",
                                            "ENABLE_DOCS": "OFF",
                                            "ENABLE_EXAMPLES": "OFF",
                                            "ENABLE_TESTS": "OFF",
                                            "WITH_EPOLL": "OFF",
                                            "BUILD_SHARED_LIBS": "OFF"},
                    optional={"tls": dict(requires=["openssl"],
                                          args=["-DENABLE_DTLS=openssl"])},
                    n="CoAP RFC 7252; static libcoap-3, DTLS off by default."),
    "libdwarf": dict(e=ex(["dwarf"]), defs={"BUILD_TESTING": "OFF",
                                            "BUILD_SHARED": "OFF",
                                            "BUILD_NON_SHARED": "ON",
                                            "BUILD_DWARFDUMP": "OFF",
                                            "BUILD_DWARFGEN": "OFF",
                                            "BUILD_DWARFEXAMPLE": "OFF",
                                            "ENABLE_DECOMPRESSION": "OFF",
                                            "DO_TESTING": "OFF"},
                     optional={"compression": dict(requires=["zlib", "zstd"])},
                     n="DWARF reader; `compression` feature pulls zlib + zstd."),
    "check": dict(e=ex(["check"]), defs={"BUILD_TESTING": "OFF",
                                         "CHECK_ENABLE_TESTS": "OFF",
                                         "ENABLE_SUBUNIT": "OFF",
                                         "BUILD_SHARED_LIBS": "OFF"},
                  n="C unit-test framework; static libcheck only."),
    "cunit": dict(e=ex(["cunit"]), args=["--disable-nls"],
                  n="Old automake Makefile hardcodes the author's path: autoreconf + ./configure regenerate it."),
    "libatomic-ops": dict(e=ex(["atomic_ops"]), defs={"BUILD_TESTING": "OFF",
                                                      "BUILD_SHARED_LIBS": "OFF",
                                                      "enable_gpl": "OFF"},
                          n="Atomic memory update primitives; static build."),
    "gflags": dict(e=ex(["gflags"]), defs={"BUILD_TESTING": "OFF",
                                           "BUILD_NESTED_TESTS": "OFF",
                                           "BUILD_SHARED_LIBS": "OFF",
                                           "BUILD_STATIC_LIBS": "ON"},
                   n="C++ command-line flags; bottom of the gflags -> glog chain."),
    "glog": dict(e=ex(["glog"]), defs={"BUILD_TESTING": "OFF",
                                       "WITH_GFLAGS": "ON", "WITH_UNWIND": "OFF",
                                       "WITH_GTEST": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                 n="Google logging library on the external gflags port."),
    "double-conversion": dict(e=ex(["double-conversion"]),
                              defs={"BUILD_TESTING": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                              n="IEEE-754 decimal conversion routines; static build."),
    "abseil": dict(e=ex([]), defs={"BUILD_TESTING": "OFF",
                                   "ABSL_ENABLE_INSTALL": "ON",
                                   "ABSL_PROPAGATE_CXX_STD": "ON",
                                   "ABSL_BUILD_TEST_HELPERS": "OFF",
                                   "BUILD_SHARED_LIBS": "OFF"},
                   n="Abseil C++ foundation: CMake package config installed for re2."),
    "re2": dict(e=ex(["re2"]), defs={"BUILD_TESTING": "OFF",
                                     "RE2_BUILD_TESTING": "OFF",
                                     "RE2_USE_ICU": "OFF",
                                     "BUILD_SHARED_LIBS": "OFF"},
                n="RE2 regex engine on the external abseil port (find_package(absl))."),
    "libidn": dict(e=ex(["idn"]), args=["--disable-nls", "--disable-doc"],
                   n="IDNA2003 stringprep library; GNU autotools."),
}

PRE_BUILD = '''    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
        end
    end,
'''


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
        out += " " * indent + key + " = " + (ARR(v, indent + 2) if isinstance(v, list) else L(v)) + ",\n"
    return out + " " * (indent - 2) + "}"


def exports_block(e):
    return "\n".join(["    exports = {"] +
                     ["      %s = %s," % (k, ARR(e.get(k, []), 8))
                      for k in ("includes", "libdirs", "libs", "binaries")] +
                     ["    },"])


def build_lua(row):
    name, kind = row["name"], row["kind"]
    meta = META[name]
    deps = [d for d in row["deps"].split(",") if d]
    out = [
        "-- %s %s -- gcpkg port definition." % (name, row["version"]),
        "-- %s" % meta.get("n", ""),
        "",
        'local recipe = require("gcpkg.recipe")',
    ]
    if kind == "autotools":
        out.append('local fs = require("gcpkg.fs")')
    out.append("")
    out.append("return recipe.%s {" % kind)
    for k in ("name", "version", "license", "homepage"):
        out.append("    %s = %s," % (k, L(row[k])))
    out.append("    description = %s," % L(row["desc"]))
    out.append("    source = {")
    out.append("        url = %s," % L(row["url"]))
    out.append("        sha256 = %s," % L(row["sha256"]))
    out.append("        strip = 1,")
    out.append("    },")
    out.append("    dependencies = %s," % ARR(deps, 8))
    if kind == "autotools":
        args = ["--disable-shared", "--enable-static"] + list(meta.get("args", []))
        out.append("    autotools = {")
        out.append("        args = %s," % ARR(args, 10))
        out.append("    },")
        out.append(PRE_BUILD.rstrip("\n"))
    elif kind == "cmake":
        defines = meta.get("defs") or {"BUILD_TESTING": "OFF"}
        out.append("    cmake = {")
        if meta.get("cmake_source"):
            out.append("        source = %s," % L(meta["cmake_source"]))
        out.append("        defines = %s," % TBL(defines, 10))
        out.append("        args = {},")
        out.append("    },")
    elif kind == "meson":
        out.append("    meson = {")
        out.append("        options = %s," % TBL(meta.get("opts", {}), 10))
        out.append("        args = {},")
        out.append("    },")
    elif kind == "make":
        out.append("    make = {")
        out.append("        vars = %s," % meta["make_vars"])
        out.append("        targets = %s," % ARR(meta.get("targets", []), 10))
        out.append("        install_target = %s," % L(meta["install_target"]))
        out.append("    },")
    out.append(exports_block(meta["e"]))
    out.append("}")
    return "\n".join(out) + "\n"


def features_yaml(row):
    name = row["name"]
    meta = META[name]
    lines = [
        "schema: 1",
        "port: %s" % name,
        "",
        "# %s" % meta.get("n", ""),
        "# Feature switches for this port.",
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
    for feature, spec in sorted(meta.get("optional", {}).items()):
        requires = spec.get("requires", [])
        lines += [
            "  %s:" % feature,
            "    default: false",
            "    description: Pull in %s for this optional capability" % ", ".join(requires),
            "    requires: [%s]" % ", ".join(requires),
            "    args: %s" % (("[" + ", ".join(L(a) for a in spec.get("args", [])) + "]")
                             if spec.get("args") else "[]"),
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
    print("generated %d ports into %s" % (len(rows), ROOT))


if __name__ == "__main__":
    main()
