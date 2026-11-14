#!/usr/bin/env python3
"""Generate Linux base-library ports from the catalog.

Source of truth: tools/linux-base-catalog.tsv (37 real upstream tarballs with
measured SHA256, build-system kind and dependency list) plus META below
(exported artifacts, build switches, notes). The engine only reads
ports/<name>/build.lua + features.yaml at runtime.

    python3 tools/gen-linux-base-ports.py
    ./build/bin/gcpkg check --ports ./ports
"""
import csv
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "linux-base-catalog.tsv")


def ex(libs, includes=None, libdirs=None, binaries=()):
    return {
        "includes": includes or ["@PREFIX@/include"],
        "libdirs": libdirs or ["@LIBDIR@"],
        "libs": list(libs), "binaries": list(binaries),
    }


META = {
    "gmp": dict(e=ex(["gmp"]), n="GNU MP; L0 foundation of the numeric/crypto chain."),
    "mpfr": dict(e=ex(["mpfr"]), n="Needs gmp (dependency env supplies -I/-L/-lgmp)."),
    "mpc": dict(e=ex(["mpc"]), n="Needs gmp + mpfr; classic GCC numeric stack."),
    "nettle": dict(e=ex(["nettle", "hogweed"]), n="Low-level crypto built on gmp."),
    "libtasn1": dict(e=ex(["tasn1"]), n="ASN.1 parser used by GnuTLS."),
    "libunistring": dict(e=ex(["unistring"]), n="Unicode primitives for libidn2 and GnuTLS."),
    "libidn2": dict(e=ex(["idn2"]), n="IDNA2008; depends on libunistring."),
    "libgpg-error": dict(e=ex(["gpg-error"]), n="GnuPG common error/portability layer."),
    "libgcrypt": dict(e=ex(["gcrypt"]), n="GNU crypto library; depends on libgpg-error."),
    "libsodium": dict(e=ex(["sodium"]), n="Self-contained modern crypto (autotools)."),
    "mbedtls": dict(e=ex(["mbedtls", "mbedx509", "mbedcrypto"]),
                    defs={"ENABLE_TESTING": "OFF", "ENABLE_PROGRAMS": "OFF"},
                    n="Alternative TLS stack built with CMake; tests/programs disabled."),
    "gnutls": dict(e=ex(["gnutls"]),
                   args=["--disable-doc", "--disable-guile", "--without-p11-kit"],
                   n="Widest new dependency surface: nettle, gmp, libtasn1, libidn2, libunistring and the existing zlib port."),
    "libevent": dict(e=ex(["event", "event_core", "event_extra", "event_openssl"]),
                     defs={"EVENT__DISABLE_TESTS": "ON", "EVENT__DISABLE_BENCHMARK": "ON",
                           "EVENT__DISABLE_SAMPLES": "ON"},
                     n="Event loop, linked against the existing openssl port."),
    "libuv": dict(e=ex(["uv"]), defs={"LIBUV_BUILD_TESTS": "OFF"},
                  n="Cross-platform async I/O; CMake build."),
    "jansson": dict(e=ex(["jansson"]), defs={"JANSSON_BUILD_DOCS": "OFF"},
                    n="JSON C library; complements the existing json-c port."),
    "sqlite3": dict(e=ex(["sqlite3"], binaries=["@PREFIX@/bin"]),
                    n="SQLite amalgamation; autotools configure + make."),
    "ncurses": dict(e=ex(["ncurses", "tinfo", "panel", "menu", "form"]),
                    args=["--without-debug", "--enable-pc-files"],
                    n="Terminal/terminfo library; readline depends on it."),
    "readline": dict(e=ex(["readline", "history"]), n="GNU readline on top of ncurses."),
    "oniguruma": dict(e=ex(["onig"]), n="Regex engine; CMake build."),
    "utf8proc": dict(e=ex(["utf8proc"]), defs={"UTF8PROC_ENABLE_TESTING": "OFF"},
                     n="Unicode normalization; CMake build."),
    "xxhash": dict(e=ex(["xxhash"]), n="Hand-written Makefile: make && make install PREFIX=<prefix>."),
    "libdeflate": dict(e=ex(["deflate"]), defs={"LIBDEFLATE_BUILD_TESTS": "OFF"},
                       n="libdeflate 1.26 ships CMakeLists.txt only (no top-level Makefile)."),
    "libpng": dict(e=ex(["png16"], includes=["@PREFIX@/include", "@PREFIX@/include/libpng16"]),
                   defs={"PNG_TESTS": "OFF", "PNG_TOOLS": "OFF"},
                   n="PNG library on the existing zlib port; headers also under include/libpng16."),
    "libjpeg-turbo": dict(e=ex(["jpeg", "turbojpeg"]), defs={"WITH_TESTS": "OFF", "WITH_TOOLS": "OFF"},
                          n="SIMD JPEG codec; CMake build."),
    "libtiff": dict(e=ex(["tiff"]),
                    defs={"BUILD_TESTING": "OFF", "tests": "OFF", "tools": "OFF"},
                    n="TIFF on zlib + xz + zstd + libjpeg-turbo (existing and new ports)."),
    "freetype": dict(e=ex(["freetype"], includes=["@PREFIX@/include", "@PREFIX@/include/freetype2"]),
                     defs={"BUILD_TESTING": "OFF", "FT_DISABLE_ZLIB": "OFF"},
                     n="Font renderer on zlib, bzip2, libpng and brotli (all existing ports)."),
    "fontconfig": dict(e=ex(["fontconfig"]), args=["--disable-docs"],
                       n="Font configuration on freetype + expat."),
    "harfbuzz": dict(e=ex(["harfbuzz"], includes=["@PREFIX@/include", "@PREFIX@/include/harfbuzz"]),
                     opts={
                         "default_library": "static",
                         "tests": "disabled", "docs": "disabled",
                         "doc_tests": "false", "utilities": "disabled",
                         "introspection": "disabled", "benchmark": "disabled",
                         "cairo": "disabled", "chafa": "disabled",
                         "gobject": "disabled", "icu": "disabled",
                         "png": "disabled", "zlib": "disabled",
                         "freetype": "enabled", "glib": "enabled",
                     },
                     n="Text shaping engine; static Meson build on source-built freetype + glib, no system utilities."),
    "glib": dict(e=ex(["glib-2.0", "gobject-2.0", "gio-2.0"],
                      includes=["@PREFIX@/include", "@PREFIX@/include/glib-2.0",
                                "@LIBDIR@/glib-2.0/include"]),
                 opts={"tests": "false", "installed_tests": "false"},
                 n="GLib core; Meson, depends on libffi + zlib + pcre2 (existing L0 ports)."),
    "libxslt": dict(e=ex(["xslt", "exslt"]), args=["--without-python"],
                    n="XSLT processor on top of the existing libxml2 port."),
    "libusb": dict(e=ex(["usb-1.0"], includes=["@PREFIX@/include", "@PREFIX@/include/libusb-1.0"]),
                   args=["--disable-udev"],
                   n="Userspace USB access: GitHub tag archives ship configure.ac, so pre_build runs autoreconf."),
    "elfutils": dict(e=ex(["elf", "dw"]), args=["--disable-debuginfod", "--disable-libdebuginfod"],
                     n="libelf/libdw on zlib + zstd + xz; debuginfod (HTTP server) disabled."),
    "libbpf": dict(e=ex(["bpf"]),
                   n="Kernel tools/lib/bpf Makefile: build in src/ then install with PREFIX=<prefix>; depends on elfutils."),
    "libattr": dict(e=ex(["attr"]), n="Extended attributes (xattr) userspace library."),
    "libacl": dict(e=ex(["acl"]), n="POSIX ACL library, depends on libattr."),
    "libnfnetlink": dict(e=ex(["nfnetlink"]), n="Netfilter netlink base library."),
    "libnetfilter_conntrack": dict(e=ex(["netfilter_conntrack"]),
                                   n="Conntrack library on libnfnetlink + the existing libmnl port."),
}

CUSTOM = {
    "custom-make": '''    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "make", "-j" .. j }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "PREFIX=" .. ctx.prefix }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = %s,
            binaries = {},
        }
    end,
''',
    "custom-libbpf": '''    build = function(ctx)
        local util = require("gcpkg.util")
        local d = util.join(ctx.src, "src")
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "make", "-j" .. j }, { cwd = d, log = ctx.log })
        ctx.exec({ "make", "install", "PREFIX=" .. ctx.prefix,
                   "LIBDIR=" .. util.join(ctx.prefix, "lib") }, { cwd = d, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "bpf" },
            binaries = {},
        }
    end,
''',
}

# All autotools ports: GitHub tag archives often ship configure.ac only.
PRE_BUILD = '''    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
        end
        -- Static libbrotlidec needs libbrotlicommon; pkg-config does not add it.
        if ctx.name == "fontconfig" then
            ctx.env.LIBS = "-lbrotlicommon " .. (ctx.env.LIBS or "")
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
    name, kind, meta = row["name"], row["kind"], META[row["name"]]
    deps = [d for d in row["deps"].split(",") if d]
    out = [
        "-- %s %s -- gcpkg port definition." % (name, row["version"]),
        "-- %s" % meta.get("n", ""),
        "",
    ]
    if not kind.startswith("custom-"):
        out.append('local recipe = require("gcpkg.recipe")')
        if kind == "autotools":
            out.append('local fs = require("gcpkg.fs")')
    out.append("")
    if kind.startswith("custom-"):
        out.append("return {")
    else:
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
    if kind.startswith("custom-"):
        body = CUSTOM[kind]
        out.append(body % ARR(meta["e"]["libs"], 12) if "%s" in body else body)
        out.append("}")
        return "\n".join(out) + "\n"
    if kind == "autotools":
        # features.yaml defaults to `static`; several upstream configure
        # scripts default to shared and then try to link our non-PIC .a files
        # (liblzma.a, libz.a) into a .so, which fails. Force static everywhere.
        args = ["--disable-shared", "--enable-static"] + list(meta.get("args", []))
        out.append("    autotools = {")
        out.append("        args = %s," % ARR(args, 10))
        out.append("    },")
        out.append(PRE_BUILD.rstrip("\n"))
    elif kind == "cmake":
        out.append("    cmake = {")
        out.append("        defines = %s," % TBL(meta.get("defs", {"BUILD_TESTING": "OFF"}), 10))
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


JANSSON_VERSIONS = """
# Available upstream releases with pinned URL/SHA256.
versions:
  "2.15.1":
    source:
      url: "https://codeload.github.com/akheron/jansson/tar.gz/refs/tags/v2.15.1"
      sha256: "dbf95cb0af903f4fb8b61507d96b45b67db7d1479688ede352e1d571394d06f7"
  "2.14":
    source:
      url: "https://codeload.github.com/akheron/jansson/tar.gz/refs/tags/v2.14"
      sha256: "c739578bf6b764aa0752db9a2fdadcfe921c78f1228c7ec0bb47fa804c55d17b"
  "2.13.1":
    source:
      url: "https://codeload.github.com/akheron/jansson/tar.gz/refs/tags/v2.13.1"
      sha256: "f22901582138e3203959c9257cf83eba9929ac41d7be4a42557213a22ebcc7a0"
  "2.12":
    source:
      url: "https://codeload.github.com/akheron/jansson/tar.gz/refs/tags/v2.12"
      sha256: "76260d30e9bbd0ef392798525e8cd7fe59a6450c54ca6135672e3cd6a1642941"
"""


def features_yaml(row):
    lines = [
        "schema: 1",
        "port: %s" % row["name"],
        "",
        "# %s" % META[row["name"]].get("n", ""),
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
    if row["name"] == "jansson":
        lines.append(JANSSON_VERSIONS.rstrip("\n"))
    return "\n".join(lines) + "\n"


# R20_MANUAL_SKIP: glib is a hand-written 2.90.1 source port; the legacy
# 2.84.4 catalog row is informational only and must not overwrite it.
MANUAL_SKIP = {"glib"}


def main():
    with open(TSV, newline="") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    generated = 0
    for row in rows:
        if row["name"] in MANUAL_SKIP:
            continue
        generated += 1
        d = os.path.join(ROOT, row["name"])
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "build.lua"), "w").write(build_lua(row))
        open(os.path.join(d, "features.yaml"), "w").write(features_yaml(row))
    print("generated %d ports into %s" % (generated, ROOT))


if __name__ == "__main__":
    main()
