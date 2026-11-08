#!/usr/bin/env python3
"""Generate the seventh-round ports: kernel interfaces and disk/storage info.

Source of truth: tools/linux-kernel-catalog.tsv (34 real tarballs with measured
SHA256, actual build-system kind from inspecting each archive, dependency list)
plus META below (exported artifacts, notes, hand-written-Makefile details).
The engine only reads ports/<name>/build.lua + features.yaml at runtime.

    python3 tools/gen-linux-kernel-ports.py
    ./build/bin/gcpkg check --ports ./ports
"""
import csv
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "linux-kernel-catalog.tsv")


def ex(libs=(), includes=None, binaries=()):
    return {"includes": includes or ["@PREFIX@/include"],
            "libdirs": ["@LIBDIR@"], "libs": list(libs),
            "binaries": list(binaries)}


# kind is taken from the catalog (verified against each tarball's top level).
META = {
    "libnvme": dict(e=ex(["nvme"]), n="NVMe ioctl library; depends on the existing liburing port (io_uring path)."),
    "nvme-cli": dict(e=ex([], binaries=["@PREFIX@/sbin"]), n="NVMe query CLI built on libnvme."),
    "libgudev": dict(e=ex(["gudev-1.0"], includes=["@PREFIX@/include", "@PREFIX@/include/gudev-1.0"]),
                     n="udev device enumeration on GLib; Meson build."),
    "udisks2": dict(e=ex(["udisks2"]),
                    args=["--disable-gtk-doc", "--disable-introspection"],
                    n="Widest disk-info dependency surface: glib, dbus, libgudev, libatasmart, libnvme (-> liburing), libparted, util-linux, libacl."),
    "libstoragemgmt": dict(e=ex(["storagemgmt"]), n="Storage array management; autotools + autoreconf from tag archive."),
    "btrfs-progs": dict(e=ex(["btrfs"]), n="Btrfs tools on util-linux/zlib/zstd/lz4; tag archive needs autogen.sh."),
    "e2fsprogs": dict(e=ex(["ext2fs", "com_err", "ss", "e2p"]), n="ext filesystem libraries, ships ./configure."),
    "lvm2": dict(e=ex(["devmapper", "lvm2cmd"]), n="device-mapper / LVM2; configure in tarball, depends on util-linux + libaio."),
    "pciutils": dict(e=ex(["pci"]), bins=["lspci", "setpci", "update-pciids"],
                     n="PCI enumeration (lspci) + libpci; hand-written Makefile, install target writes /sbin so build.lua collects artifacts into the prefix."),
    "libgpiod": dict(e=ex(["gpiod"]), n="GPIO character-device library; Meson build."),
    "libiio": dict(e=ex(["iio"]), defs={"WITH_TESTS": "OFF", "HAVE_DNS_SD": "OFF", "WITH_AIO": "OFF", "BUILD_SHARED_LIBS": "OFF", "INSTALL_UDEV_RULE": "OFF"},
                   n="Industrial I/O kernel interface; CMake, depends on libusb + libxml2. Avahi DNS-SD and libaio are disabled."),
    "hidapi": dict(e=ex(["hidapi-libusb", "hidapi-hidraw"]),
                   defs={"BUILD_SHARED_LIBS": "OFF"},
                   n="HID device access; CMake over libusb. Static build avoids linking the non-PIC libusb-1.0.a into a .so."),
    "libserialport": dict(e=ex(["serialport"]), n="sigrok serial-port library; tag archive needs autoreconf."),
    "libaudit": dict(e=ex(["audit", "auparse"]), n="Linux audit userspace; tag archive needs autoreconf."),
    "libunwind": dict(e=ex(["unwind"]),
                     n="Stack unwinding; upstream CMakeLists.txt is Visual-Studio-only, so the autotools build is used (tag archive needs autoreconf)."),
    "rpcsvc-proto": dict(e=ex(), n="rpcgen protocol headers; no compiled library."),
    "libconfuse": dict(e=ex(["confuse"]), n="Config-file parser; tag archive needs autoreconf."),
    "sg3_utils": dict(e=ex(["sgutils2"]), n="SCSI generic commands and libsgutils2; tag archive needs autoreconf."),
    "smartmontools": dict(e=ex(), n="SMART disk health query tools; ships ./configure."),
    "libtraceevent": dict(e=ex(["traceevent"]), opts={"doc": "false"},
                         n="ftrace event parser; Meson docs disabled (upstream requires asciidoc)."),
    "libtracefs": dict(e=ex(["tracefs"]), opts={"doc": "false"},
                       n="tracefs wrapper; Meson, depends on libtraceevent, docs disabled."),
    "xfsprogs": dict(e=ex(["xfs"]), n="XFS userspace + libxfs; custom ./configure in tarball."),
    "lm-sensors": dict(e=ex(["sensors"]), bins=["sensors"], n="hardware monitoring (libsensors); hand-written Makefile."),
    "i2c-tools": dict(e=ex(["i2c"]), bins=["i2cdetect", "i2cget", "i2cset", "i2cdump"], n="I2C bus tools/library; hand-written Makefile."),
    "dmidecode": dict(e=ex(), bins=["dmidecode", "biosdecode", "vpddecode", "ownership"], n="SMBIOS/DMI hardware and disk info; hand-written Makefile."),
    "mdadm": dict(e=ex(), bins=["mdadm", "mdmon"], n="MD RAID query/management; hand-written Makefile."),
    "libparted": dict(e=ex(["parted", "parted-fs-resize"]), n="Partition table query/edit library; ships ./configure."),
    "libmicrohttpd": dict(e=ex(["microhttpd"]), n="GNU embeddable HTTP server; depends on gnutls + libgcrypt."),
    "libdaemon": dict(e=ex(["daemon"]), n="Unix daemon helper; ships ./configure."),
    "hdparm": dict(e=ex(), bins=["hdparm"], n="ATA/SATA disk parameter query; hand-written Makefile."),
    "libatasmart": dict(e=ex(["atasmart"]), n="ATA SMART disk health library; ships ./configure."),
    "keyutils": dict(e=ex(["keyutils"]), bins=["keyctl", "request-key"], n="Linux kernel keyring; hand-written Makefile."),
    "libtirpc": dict(e=ex(["tirpc"], includes=["@PREFIX@/include", "@PREFIX@/include/tirpc"]), n="TI-RPC; ships ./configure, depends on rpcsvc-proto headers."),
    "libselinux": dict(e=ex(["selinux"]), make_dir="src", n="SELinux userspace library; build in src/."),
}

PRE_BUILD = '''    pre_build = function(ctx)
        if not fs.isfile(ctx.src .. '/configure') then
            ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })
        end
    end,
'''

CUSTOM_MAKE = '''    build = function(ctx)
        local util = require("gcpkg.util")
        local j = tostring(ctx.jobs or 4)
        local work = %s
        local p = ctx.prefix
        -- Many kernel-tool Makefiles hardcode CC=gcc; a command-line override
        -- keeps the gcpkg-intercept wrapper in place so compdb is produced.
        ctx.exec({ "make", "-j" .. j, "CC=" .. ctx.env.CC }, { cwd = work, log = ctx.log })
        -- Hand-written kernel-tool Makefiles install into /sbin or /usr, which
        -- a non-root build cannot do. Collect the built archives, headers and
        -- binaries into the gcpkg prefix instead (upstream is not patched).
        local cp = "mkdir -p '" .. p .. "/lib' '" .. p .. "/include' '" .. p .. "/sbin' && " ..
                   "cp -f *.a '" .. p .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f lib/*.a '" .. p .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f *.h '" .. p .. "/include/' 2>/dev/null || true; " ..
                   "cp -f lib/*.h '" .. p .. "/include/' 2>/dev/null || true; " ..
                   "cp -f include/*.h '" .. p .. "/include/' 2>/dev/null || true; " ..
                   "cp -f %s '" .. p .. "/sbin/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = work, log = ctx.log })
        return {
            includes = { p .. "/include" },
            libdirs = { p .. "/lib" },
            libs = %s,
            binaries = { p .. "/sbin" },
        }
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
        out += " " * indent + key + " = " + L(v) + ",\n"
    return out + " " * (indent - 2) + "}"


def exports_block(e):
    return "\n".join(["    exports = {"] +
                     ["      %s = %s," % (k, ARR(e.get(k, []), 8))
                      for k in ("includes", "libdirs", "libs", "binaries")] +
                     ["    },"])


def build_lua(row):
    name, kind, meta = row["name"], row["kind"], META[row["name"]]
    deps = [d for d in row["deps"].split(",") if d]
    out = ["-- %s %s -- ONE library, ONE build.lua + ONE features.yaml." % (name, row["version"]),
           "-- Verification: static registry/graph tests here; real builds for a",
           "-- subset live in tests/linux-kernel.sh (GCPKG_KERNEL_DYNAMIC=1).",
           "-- %s" % meta.get("n", ""),
           "-- Upstream is never patched: all adaptation is in this file.",
           ""]
    if not kind.startswith("custom-"):
        out.append('local recipe = require("gcpkg.recipe")')
        if kind == "autotools":
            out.append('local fs = require("gcpkg.fs")')
    out.append("")
    out.append("return {" if kind.startswith("custom-") else "return recipe.%s {" % kind)
    for k in ("name", "version", "license", "homepage"):
        out.append("    %s = %s," % (k, L(row[k])))
    out.append("    description = %s," % L(row["desc"]))
    out.append("    source = {")
    out.append("        url = %s," % L(row["url"]))
    out.append("        sha256 = %s," % L(row["sha256"]))
    out.append("        strip = 1,")
    out.append("    },")
    out.append("    dependencies = %s," % ARR(deps, 8))
    if kind == "custom-make":
        work = 'util.join(ctx.src, %s)' % L(meta["make_dir"]) if meta.get("make_dir") else "ctx.src"
        bins = " ".join(meta.get("bins", [])) or "true"
        out.append((CUSTOM_MAKE % (work, bins, ARR(meta["e"]["libs"], 12))).rstrip("\n"))
        out.append("}")
        return "\n".join(out) + "\n"
    if kind == "autotools":
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


def features_yaml(row):
    env = META[row["name"]].get("env") or {}
    env_lines = []
    if env:
        env_lines = ["    env:"] + ["      %s: %s" % (k, v) for k, v in env.items()]
    return "\n".join([
        "schema: 1", "port: %s" % row["name"], "",
        "# %s" % META[row["name"]].get("n", ""),
        "# Static validation is the default; see tests/linux-kernel.sh.",
        "features:",
        "  no-tests:", "    default: true", "    description: Skip the upstream test suite", "    args: []",
    ] + env_lines + [
        "  static:", "    default: true", "    description: Build static libraries", "    args: []",
        '    conflicts: ["shared"]',
        "  shared:", "    default: false", "    description: Build shared libraries", "    args: []",
        '    conflicts: ["static"]',
    ]) + "\n"


def main():
    with open(TSV, newline="") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    for row in rows:
        d = os.path.join(ROOT, row["name"])
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "build.lua"), "w").write(build_lua(row))
        open(os.path.join(d, "features.yaml"), "w").write(features_yaml(row))
    print("generated %d ports into %s" % (len(rows), ROOT))


if __name__ == "__main__":
    main()
