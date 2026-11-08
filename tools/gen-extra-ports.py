#!/usr/bin/env python3
"""Generate the ninth-round ports: 43 more Linux base libraries.

Source of truth: tools/extra-catalog.tsv (43 real upstream tarballs with
measured SHA256, build-system kind and dependency list) plus META below
(exported artifacts, build switches, conditional features, custom Makefile
recipes). The engine only reads ports/<name>/build.lua + features.yaml at
runtime. Every port stays exactly TWO files; upstream sources are untouched.

    python3 tools/gen-extra-ports.py
    ./build/bin/gcpkg check --ports ./ports
"""
import csv
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "extra-catalog.tsv")


def ex(libs, includes=None, libdirs=None, binaries=()):
    return {
        "includes": includes or ["@PREFIX@/include"],
        "libdirs": libdirs or ["@LIBDIR@"],
        "libs": list(libs), "binaries": list(binaries),
    }


# name -> build switches / exports / notes. `optional` declares feature-gated
# dependencies in features.yaml (verified by tests/extra.sh with --feature).
META = {
    "yyjson": dict(e=ex(["yyjson"]), defs={"BUILD_TESTING": "OFF", "YYJSON_BUILD_TESTS": "OFF"},
                   n="Fast JSON reader/writer; CMake."),
    "cjson": dict(e=ex(["cjson"]), defs={"BUILD_TESTING": "OFF", "ENABLE_CJSON_TEST": "OFF",
                                          "ENABLE_CJSON_UTILS": "ON"},
                  n="Ultralightweight C JSON parser; tests disabled."),
    "rapidjson": dict(e=ex([]), defs={"RAPIDJSON_BUILD_TESTS": "OFF",
                                       "RAPIDJSON_BUILD_EXAMPLES": "OFF",
                                       "RAPIDJSON_BUILD_DOC": "OFF",
                                       "RAPIDJSON_BUILD_THIRDPARTY_GTEST": "OFF"},
                      n="Header-only C++ JSON library: no libraries exported, headers only."),
    "libcbor": dict(e=ex(["cbor"]), defs={"WITH_TESTS": "OFF", "SANITIZE": "OFF",
                                       "BUILD_SHARED_LIBS": "OFF"},
                    n="CBOR serialization; tests disabled."),
    "inih": dict(e=ex(["inih", "INIReader"]), opts={"default_library": "static",
                                                    "with_INIReader": "true",
                                                    "distro_install": "true"},
                 n="INI parser; only Meson build in the upstream tarball."),
    "libbase64": dict(e=ex(["base64"]), defs={"BUILD_TESTING": "OFF"},
                      n="SIMD base64 codec; CMake (also ships a hand-written Makefile)."),
    "simdjson": dict(e=ex(["simdjson"]), defs={"BUILD_TESTING": "OFF",
                                               "SIMDJSON_DEVELOPER_MODE": "OFF",
                                               "SIMDJSON_JUST_LIBRARY": "ON"},
                     n="SIMD JSON parser; developer/test targets disabled."),
    "snappy": dict(e=ex(["snappy"]), defs={"SNAPPY_BUILD_TESTS": "OFF",
                                            "SNAPPY_BUILD_BENCHMARKS": "OFF",
                                            "BUILD_SHARED_LIBS": "OFF"},
                   n="Google's fast compressor; static CMake build."),
    "zlib-ng": dict(e=ex(["z"]), defs={"ZLIB_COMPAT": "ON", "ZLIBNG_ENABLE_TESTS": "OFF",
                                        "ZLIB_ENABLE_TESTS": "OFF", "WITH_GTEST": "OFF",
                                        "BUILD_SHARED_LIBS": "OFF"},
                    n="zlib-ng in zlib-compat mode; all three test switches must be OFF."),
    "c-blosc": dict(e=ex(["blosc"]), defs={"BUILD_TESTS": "OFF", "BUILD_BENCHMARKS": "OFF",
                                            "BUILD_SHARED": "OFF", "BUILD_STATIC": "ON",
                                            "PREFER_EXTERNAL_LZ4": "OFF",
                                            "PREFER_EXTERNAL_ZLIB": "OFF",
                                            "PREFER_EXTERNAL_ZSTD": "OFF"},
                    n="Blosc blocking compressor; uses bundled codecs to stay self-contained."),
    "lzfse": dict(e=ex(["lzfse"]), defs={"BUILD_TESTING": "OFF"},
                  n="Apple LZFSE codec; small standalone CMake project."),
    "miniz": dict(e=ex(["miniz"]), defs={"BUILD_TESTING": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                  n="Single-file zlib/zip replacement."),
    "nghttp3": dict(e=ex(["nghttp3"]), defs={"ENABLE_LIB_ONLY": "ON", "BUILD_TESTING": "OFF",
                                              "BUILD_SHARED_LIBS": "OFF"},
                    n="HTTP/3 library; library-only CMake build."),
    "ngtcp2": dict(e=ex(["ngtcp2"]), defs={"ENABLE_LIB_ONLY": "ON", "BUILD_TESTING": "OFF",
                                            "BUILD_SHARED_LIBS": "OFF"},
                   optional={"tls": ["openssl"]},
                   n="QUIC library; `tls` feature pulls in the existing openssl port."),
    "libssh": dict(e=ex(["ssh"]), defs={"UNIT_TESTING": "OFF", "CLIENT_TESTING": "OFF",
                                        "WITH_EXAMPLES": "OFF", "WITH_GSSAPI": "OFF",
                                        "BUILD_SHARED_LIBS": "OFF"},
                   n="SSH2 on the existing openssl + zlib ports."),
    "hiredis": dict(e=ex(["hiredis"]), defs={"BUILD_TESTING": "OFF", "DISABLE_TESTS": "ON",
                                              "ENABLE_SSL": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                    n="Redis C client; tests/SSL disabled."),
    "libmodbus": dict(e=ex(["modbus"]), n="Modbus library; GitHub tag needs autoreconf first."),
    "libdnet": dict(e=ex(["dnet"]), args=["--without-python"],
                    n="Low-level networking routines; ships a generated configure."),
    "libnet": dict(e=ex(["net"]), n="Packet construction; GitHub tag needs autoreconf first."),
    "libwebsockets": dict(e=ex(["websockets"]),
                          defs={"LWS_WITHOUT_TESTAPPS": "ON", "LWS_WITHOUT_TEST_SERVER": "ON",
                                "LWS_WITHOUT_TEST_CLIENT": "ON", "LWS_WITH_MINIMAL_EXAMPLES": "OFF",
                                "LWS_WITH_SSL": "OFF", "LWS_WITH_SHARED": "OFF",
                                "LWS_WITH_STATIC": "ON"},
                          optional={"tls": ["openssl"]},
                          n="Websockets/HTTP on zlib; `tls` feature adds openssl."),
    "librdkafka": dict(e=ex(["rdkafka"]), args=["--disable-sasl", "--disable-gssapi", "--disable-curl"],
                       optional={"ssl": ["openssl"]},
                       n="Kafka C client on zlib; `ssl` feature adds openssl."),
    "libogg": dict(e=ex(["ogg"]), defs={"BUILD_TESTING": "OFF", "BUILD_SHARED_LIBS": "OFF",
                                         "INSTALL_DOCS": "OFF"},
                   n="Ogg container; bottom of the audio chain."),
    "libvorbis": dict(e=ex(["vorbis", "vorbisfile", "vorbisenc"]),
                      defs={"BUILD_TESTING": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                      n="Vorbis codec on libogg."),
    "opus": dict(e=ex(["opus"]), defs={"BUILD_TESTING": "OFF", "OPUS_BUILD_TESTING": "OFF",
                                        "OPUS_BUILD_PROGRAMS": "OFF",
                                        "OPUS_BUILD_SHARED_LIBRARY": "OFF"},
                 n="Opus audio codec; CMake build (tarball also has autotools/meson)."),
    "flac": dict(e=ex(["FLAC"]), defs={"BUILD_TESTING": "OFF", "BUILD_SHARED_LIBS": "OFF",
                                        "BUILD_PROGRAMS": "OFF", "BUILD_EXAMPLES": "OFF",
                                        "INSTALL_MANPAGES": "OFF", "WITH_OGG": "ON"},
                 n="FLAC codec on libogg."),
    "libwebp": dict(e=ex(["webp", "webpmux", "webpdemux"]),
                    defs={"BUILD_SHARED_LIBS": "OFF", "WEBP_BUILD_CWEBP": "OFF",
                          "WEBP_BUILD_DWEBP": "OFF", "WEBP_BUILD_GIF2WEBP": "OFF",
                          "WEBP_BUILD_IMG2WEBP": "OFF", "WEBP_BUILD_VWEBP": "OFF",
                          "WEBP_BUILD_WEBPINFO": "OFF", "WEBP_BUILD_ANIM_UTILS": "OFF",
                          "WEBP_BUILD_EXTRAS": "OFF", "WEBP_BUILD_LIBWEBPMUX": "OFF"},
                    n="WebP image codec; all command-line tools disabled."),
    "libsamplerate": dict(e=ex(["samplerate"]), defs={"BUILD_TESTING": "OFF",
                                                        "LIBSAMPLERATE_EXAMPLES": "OFF",
                                                        "BUILD_SHARED_LIBS": "OFF"},
                          n="Secret Rabbit Code audio resampler."),
    "libsecp256k1": dict(e=ex(["secp256k1"]),
                         defs={"SECP256K1_BUILD_TESTS": "OFF", "SECP256K1_BUILD_BENCHMARK": "OFF",
                               "SECP256K1_BUILD_EXAMPLES": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                         n="Optimised secp256k1 elliptic-curve library."),
    "wolfssl": dict(e=ex(["wolfssl"]), args=["--disable-examples", "--disable-crypttests"],
                    n="Embedded TLS library; big tarball, autoreconf from configure.ac."),
    "fmt": dict(e=ex(["fmt"]), defs={"FMT_TEST": "OFF", "FMT_DOC": "OFF",
                                      "FMT_INSTALL": "ON", "BUILD_SHARED_LIBS": "OFF"},
                n="C++ formatting library; bottom of the fmt -> spdlog chain."),
    "spdlog": dict(e=ex(["spdlog"]), defs={"SPDLOG_FMT_EXTERNAL": "ON",
                                            "SPDLOG_BUILD_TESTS": "OFF",
                                            "SPDLOG_BUILD_EXAMPLE": "OFF",
                                            "BUILD_SHARED_LIBS": "OFF"},
                   n="C++ logging on the external fmt port (CMAKE_PREFIX_PATH from deps)."),
    "lmdb": dict(e=ex(["lmdb"]), custom="lmdb",
                 n="LMDB: Makefile lives in libraries/liblmdb; custom build(ctx) uses that cwd."),
    "capstone": dict(e=ex(["capstone"]), defs={"CAPSTONE_BUILD_TESTS": "OFF",
                                                "CAPSTONE_BUILD_CSTOOL": "OFF",
                                                "CAPSTONE_BUILD_SHARED": "OFF",
                                                "CAPSTONE_BUILD_STATIC": "ON"},
                     n="Disassembly framework; static library only."),
    "googletest": dict(e=ex(["gtest", "gmock", "gtest_main", "gmock_main"]),
                       defs={"BUILD_GMOCK": "ON", "INSTALL_GTEST": "ON",
                             "gtest_force_shared_crt": "ON", "BUILD_SHARED_LIBS": "OFF"},
                       n="C++ test framework; installed headers and static libs."),
    "libedit": dict(e=ex(["edit"]), n="Editline library on the existing ncurses port."),
    "pcre": dict(e=ex(["pcre"]), defs={"PCRE_BUILD_TESTS": "OFF", "PCRE_BUILD_PCREGREP": "OFF",
                                        "PCRE_BUILD_PCRECPP": "OFF", "BUILD_SHARED_LIBS": "OFF"},
                 n="Legacy PCRE (complements the existing pcre2 port)."),
    "libconfig": dict(e=ex(["config"]), args=["--disable-doc", "--disable-examples", "--disable-tests"],
                       n="Structured config parser; docs/examples/tests off (no makeinfo)."),
    "giflib": dict(e=ex(["gif"]), custom="giflib",
                   n="Hand-written Makefile; custom build(ctx) passes PREFIX and wrapper CC."),
    "libsndfile": dict(e=ex(["sndfile"]), defs={"BUILD_TESTING": "OFF", "BUILD_PROGRAMS": "OFF",
                                                  "BUILD_EXAMPLES": "OFF",
                                                  "BUILD_SHARED_LIBS": "OFF"},
                       n="Widest new chain: libogg + libvorbis + opus + flac -> libsndfile."),
    "libvpx": dict(e=ex(["vpx"]), custom="vpx",
                   n="VP8/VP9 codec: custom ./configure with the pure-C generic-gnu target."),
    "libtheora": dict(e=ex(["theora", "theoradec", "theoraenc"]),
                      args=["--disable-examples", "--disable-oggtest",
                            "--disable-vorbistest", "--disable-sdltest"],
                      n="Official Xiph release tarball (ships configure); examples disabled."),
    "libzip": dict(e=ex(["zip"]), defs={"BUILD_TESTING": "OFF", "BUILD_TOOLS": "OFF",
                                         "BUILD_EXAMPLES": "OFF", "BUILD_DOC": "OFF",
                                         "ENABLE_OPENSSL": "OFF", "ENABLE_GNUTLS": "OFF",
                                         "ENABLE_MBEDTLS": "OFF", "ENABLE_COMMONCRYPTO": "OFF",
                                         "BUILD_SHARED_LIBS": "OFF"},
                   optional={"openssl": ["openssl"]},
                   n="ZIP library on the existing zlib port; `openssl` feature adds openssl."),
    "libmaxminddb": dict(e=ex(["maxminddb"]), defs={"BUILD_TESTING": "OFF",
                                                      "BUILD_SHARED_LIBS": "OFF"},
                         n="MaxMind DB / GeoIP reader."),
}

CUSTOM = {
    "giflib": '''    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        local cc = "CC=" .. ctx.env.CC
        ctx.exec({ "make", "-j" .. j, cc }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "PREFIX=" .. ctx.prefix, cc },
                 { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs  = { ctx.prefix .. "/lib" },
            libs     = %s,
            binaries = {},
        }
    end,
''',
    "lmdb": '''    build = function(ctx)
        local util = require("gcpkg.util")
        local d = util.join(ctx.src, "libraries", "liblmdb")
        local j = tostring(ctx.jobs or 4)
        local cc = "CC=" .. ctx.env.CC
        ctx.exec({ "make", "-j" .. j, cc }, { cwd = d, log = ctx.log })
        ctx.exec({ "make", "install", "prefix=" .. ctx.prefix, cc },
                 { cwd = d, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs  = { ctx.prefix .. "/lib" },
            libs     = %s,
            binaries = {},
        }
    end,
''',
    "vpx": '''    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "./configure", "--prefix=" .. ctx.prefix,
                   -- generic-gnu is a pure-C target: no yasm/nasm required.
                   "--target=generic-gnu",
                   "--disable-examples", "--disable-tools", "--disable-docs",
                   "--disable-unit-tests", "--enable-static", "--disable-shared" },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "-j" .. j }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install" }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs  = { ctx.prefix .. "/lib" },
            libs     = %s,
            binaries = {},
        }
    end,
''',
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
    custom = meta.get("custom")
    deps = [d for d in row["deps"].split(",") if d]
    out = [
        "-- %s %s -- ONE library, ONE build.lua + ONE features.yaml." % (name, row["version"]),
        "-- Verification: static registry/graph tests here; real builds for a",
        "-- subset live in tests/extra.sh (GCPKG_EXTRA_DYNAMIC=1).",
        "-- %s" % meta.get("n", ""),
        "-- Upstream is never patched: all adaptation is in this file.",
        "",
    ]
    if not custom:
        out.append('local recipe = require("gcpkg.recipe")')
    if kind == "autotools" or custom:
        out.append('local fs = require("gcpkg.fs")')
    out.append("")
    out.append("return {" if custom else "return recipe.%s {" % kind)
    for k in ("name", "version", "license", "homepage"):
        out.append("    %s = %s," % (k, L(row[k])))
    out.append("    description = %s," % L(row["desc"]))
    out.append("    source = {")
    out.append("        url = %s," % L(row["url"]))
    out.append("        sha256 = %s," % L(row["sha256"]))
    out.append("        strip = 1,")
    out.append("    },")
    out.append("    dependencies = %s," % ARR(deps, 8))
    if custom:
        body = CUSTOM[custom]
        out.append(body % ARR(meta["e"]["libs"], 12) if "%s" in body else body)
        out.append("}")
        return "\n".join(out) + "\n"
    if kind == "autotools":
        args = ["--disable-shared", "--enable-static"] + list(meta.get("args", []))
        out.append("    autotools = {")
        out.append("        args = %s," % ARR(args, 10))
        out.append("    },")
        out.append(PRE_BUILD.rstrip("\n"))
    elif kind == "cmake":
        defines = meta.get("defs") or {"BUILD_TESTING": "OFF"}
        out.append("    cmake = {")
        out.append("        defines = %s," % TBL(defines, 10))
        out.append("        args = {},")
        out.append("    },")
    elif kind == "meson":
        out.append("    meson = {")
        out.append("        options = %s," % TBL(meta.get("opts", {}), 10))
        out.append("        args = {},")
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
        "# Static validation is the default; see tests/extra.sh.",
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
    for feature, requires in sorted(meta.get("optional", {}).items()):
        lines += [
            "  %s:" % feature,
            "    default: false",
            "    description: Pull in %s for this optional capability" % ", ".join(requires),
            "    requires: [%s]" % ", ".join(requires),
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
