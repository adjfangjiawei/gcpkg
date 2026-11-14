#!/usr/bin/env python3
"""Generate gcpkg ports for the Linux plumbing stack from the verified tarball catalog.

Every URL and SHA256 below comes from tools/linux-catalog.tsv,
which was built by actually downloading the tarballs. Upstream sources are
never patched: each port is one build.lua + one features.yaml.
"""
import csv, os, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "linux-catalog.tsv")
CAT = {r["name"]: r for r in csv.DictReader(open(TSV), delimiter="\t")}

def q(s):
    return json.dumps(str(s), ensure_ascii=False)

def lua(v, indent=8):
    pad = " " * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        if v.startswith("LUA:"):
            return v[4:]
        return q(v)
    if isinstance(v, list):
        if not v:
            return "{}"
        return "{ " + ", ".join(lua(x, 0) for x in v) + " }"
    if isinstance(v, dict):
        if not v:
            return "{}"
        lines = []
        for k, val in v.items():
            key = k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[" + q(k) + "]"
            lines.append(pad + "  " + key + " = " + lua(val, indent + 2))
        return "{\n" + ",\n".join(lines) + "\n" + pad + "}"
    raise TypeError(v)

# kind-specific knobs: cmake.defines / meson.options / autotools.args / make.vars
PORTS = [
# ---------------- independent L0 libraries ----------------
dict(dir="libnuma", tar="numactl-2.0.19", version="2.0.19", kind="autotools",
     desc="NUMA policy library (libnuma) and numactl tools", license="LGPL-2.1",
     home="https://github.com/numactl/numactl", deps=[],
     args=["--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"],
                  libs=["numa"], binaries=["@PREFIX@/bin"]),
     no_tests=[]),
dict(dir="libcap", tar="libcap-2.76", version="2.76", kind="make",
     desc="Linux capabilities library (POSIX.1e)", license="BSD-3-Clause",
     home="https://sites.google.com/site/fullycapable", deps=[],
     vars={"prefix": "LUA:ctx.prefix", "lib": "lib", "SHARED": "no", "PAM_CAP": "no", "GOLANG": "no"},
     install_target="install",
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"],
                  libs=["cap", "psx"], binaries=["@PREFIX@/sbin"]),
     no_tests=[]),
dict(dir="libseccomp", tar="libseccomp-2.6.0", version="2.6.0", kind="autotools",
     desc="Linux seccomp filter library", license="LGPL-2.1",
     home="https://github.com/seccomp/libseccomp", deps=[],
     args=["--disable-python", "--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["seccomp"]),
     no_tests=[]),
dict(dir="libcap-ng", tar="libcap-ng-0.8.4", version="0.8.4", kind="autotools",
     desc="Alternate Linux capabilities library", license="LGPL-2.1",
     home="https://github.com/stevegrubb/libcap-ng", deps=[],
     pre=["LUA:require('gcpkg.fs').write(ctx.src .. '/NEWS', '')",
          "LUA:ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })"],
     args=["--without-python", "--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["cap-ng", "drop_ambient"]),
     no_tests=[]),
dict(dir="libmnl", tar="libmnl-1.0.5", version="1.0.5", kind="autotools",
     desc="Minimalistic netlink library (netfilter)", license="LGPL-2.1",
     home="https://www.netfilter.org/projects/libmnl/", deps=[],
     args=["--disable-doxygen", "--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["mnl"]),
     no_tests=[]),
dict(dir="libnl", tar="libnl-3.11.0", version="3.11.0", kind="autotools",
     desc="Netlink protocol library suite", license="LGPL-2.1",
     home="https://github.com/thom311/libnl", deps=[],
     args=["--disable-cli", "--disable-shared"],
     exports=dict(includes=["@PREFIX@/include/libnl3", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], libs=["nl-3", "nl-genl-3", "nl-route-3"]),
     no_tests=[]),
dict(dir="popt", tar="popt-1.19", version="1.19", kind="autotools",
     desc="Command line option parsing library", license="MIT",
     home="https://github.com/rpm-software-management/popt", deps=[],
     pre=["LUA:require('gcpkg.fs').write(ctx.src .. '/NEWS', '')",
          "LUA:ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })"],
     args=["--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["popt"]),
     no_tests=[]),
dict(dir="json-c", tar="json-c-0.18", version="0.18", kind="cmake",
     desc="JSON implementation in C", license="MIT",
     home="https://github.com/json-c/json-c", deps=[],
     defines=dict(BUILD_SHARED_LIBS="OFF", DISABLE_WERROR="ON", ENABLE_TESTING="OFF"),
     exports=dict(includes=["@PREFIX@/include/json-c", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], libs=["json-c"]),
     no_tests=["-DBUILD_TESTING=OFF"]),
dict(dir="libyaml", tar="yaml-0.2.5", version="0.2.5", kind="autotools",
     desc="YAML 1.1 parser and emitter in C", license="MIT",
     home="https://github.com/yaml/libyaml", deps=[],
     args=["--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["yaml"]),
     no_tests=[]),
dict(dir="libxml2", tar="libxml2-2.14.5", version="2.14.5", kind="cmake",
     desc="GNOME XML parser and toolkit", license="MIT",
     home="https://gitlab.gnome.org/GNOME/libxml2", deps=["zlib", "xz"],
     defines={"BUILD_SHARED_LIBS": "OFF", "LIBXML2_WITH_PYTHON": "OFF",
              "LIBXML2_WITH_PROGRAMS": "OFF", "LIBXML2_WITH_TESTS": "OFF",
              "LIBXML2_WITH_ZLIB": "ON", "LIBXML2_WITH_LZMA": "ON",
              "LIBXML2_WITH_ICONV": "OFF", "LIBXML2_WITH_ICU": "OFF"},
     exports=dict(includes=["@PREFIX@/include/libxml2", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], libs=["xml2"]),
     no_tests=["-DLIBXML2_WITH_TESTS=OFF"]),
dict(dir="libpcap", tar="libpcap-1.10.5", version="1.10.5", kind="autotools",
     desc="Packet capture library", license="BSD-3-Clause",
     home="https://www.tcpdump.org", deps=[],
     args=["--disable-shared", "--without-libnl", "--disable-dbus",
           "--disable-bluetooth", "--disable-rdma", "--disable-usb",
           "--disable-netmap", "--disable-dag", "--disable-septel",
           "--disable-snf", "--disable-tc"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["pcap"]),
     no_tests=[]),
dict(dir="libaio", tar="libaio-0.3.113", version="0.3.113", kind="make",
     desc="Linux native asynchronous I/O library", license="LGPL-2.1",
     home="https://pagure.io/libaio", deps=[],
     vars={"prefix": "LUA:ctx.prefix"}, install_target="install",
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["aio"]),
     no_tests=[]),
dict(dir="liburing", tar="liburing-2.9", version="2.9", kind="make",
     desc="Linux io_uring helper library", license="MIT",
     home="https://github.com/axboe/liburing", deps=[],
     pre=["LUA:ctx.exec({ './configure', '--prefix=' .. ctx.prefix, '--libdir=' .. ctx.prefix .. '/lib', '--includedir=' .. ctx.prefix .. '/include' }, { cwd = ctx.src, log = ctx.log })"],
     targets=["library"], install_target="install",
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["uring"]),
     no_tests=[]),
dict(dir="libevdev", tar="libevdev-1.13.4", version="1.13.4", kind="meson",
     desc="Linux evdev input event wrapper library", license="MIT",
     home="https://www.freedesktop.org/wiki/Software/libevdev/", deps=[],
     options={"tests": "disabled", "tools": "disabled", "documentation": "disabled"},
     exports=dict(includes=["@PREFIX@/include/libevdev-1.0", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], libs=["evdev"]),
     no_tests=["-Dtests=disabled"]),
dict(dir="libpciaccess", tar="libpciaccess-0.18.1", version="0.18.1", kind="meson",
     desc="Generic PCI access library (X.org)", license="MIT",
     home="https://gitlab.freedesktop.org/xorg/lib/libpciaccess", deps=["zlib"],
     options={"zlib": "enabled"},
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["pciaccess"]),
     no_tests=[]),
dict(dir="pixman", tar="pixman-0.44.2", version="0.44.2", kind="meson",
     desc="Low-level pixel manipulation library (Cairo/X.org)", license="MIT",
     home="https://cairographics.org", deps=[],
     options={"tests": "disabled", "demos": "disabled", "gtk": "disabled",
              "libpng": "disabled", "openmp": "disabled"},
     exports=dict(includes=["@PREFIX@/include/pixman-1", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], libs=["pixman-1"]),
     no_tests=["-Dtests=disabled"]),
dict(dir="xorgproto", tar="xorgproto-2024.1", version="2024.1", kind="meson",
     desc="X11 protocol headers and pkg-config files (headers-only port)", license="MIT",
     home="https://gitlab.freedesktop.org/xorg/proto/xorgproto", deps=[],
     options={"legacy": "true"},
     exports=dict(includes=["@PREFIX@/include"]),
     no_tests=[]),
dict(dir="xcb-proto", tar="xcb-proto-1.17.0", version="1.17.0", kind="autotools",
     desc="XCB protocol descriptions + xcbgen Python module (data-only port)", license="MIT",
     home="https://gitlab.freedesktop.org/xorg/proto/xcb-proto", deps=[],
     args=[],
     exports=dict(includes=["@PREFIX@/include"]),
     no_tests=[]),
dict(dir="libxkbcommon", tar="libxkbcommon-1.7.0", version="1.7.0", kind="meson",
     desc="Keyboard handling library (Wayland/X11 keymaps)", license="MIT",
     home="https://xkbcommon.org", deps=[],
     options={"enable-x11": "false", "enable-wayland": "false",
              "enable-docs": "false", "enable-tools": "false",
              "enable-xkbregistry": "false"},
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["xkbcommon"]),
     no_tests=[]),
dict(dir="wayland-protocols", tar="wayland-protocols-1.45", version="1.45", kind="meson",
     desc="Wayland protocol XML specifications (data-only port)", license="MIT",
     home="https://gitlab.freedesktop.org/wayland/wayland-protocols", deps=["wayland"],
     options={"tests": "false"},
     exports=dict(includes=["@PREFIX@/include"]),
     no_tests=["-Dtests=false"]),
dict(dir="wayland", tar="wayland-1.23.1", version="1.23.1", kind="meson",
     desc="Wayland core libraries and protocol scanner", license="MIT",
     home="https://wayland.freedesktop.org", deps=["libffi", "expat"],
     options={"libraries": "true", "scanner": "true", "documentation": "false",
              "dtd_validation": "false"},
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"],
                  libs=["wayland-server", "wayland-client", "wayland-cursor", "wayland-egl"],
                  binaries=["@PREFIX@/bin"]),
     no_tests=["-Dtests=false"]),
dict(dir="libdrm", tar="libdrm-2.4.124", version="2.4.124", kind="meson",
     desc="Direct Rendering Manager user-space library", license="MIT",
     home="https://dri.freedesktop.org", deps=["libpciaccess"],
     options={"intel": "disabled", "radeon": "disabled", "amdgpu": "disabled",
              "nouveau": "disabled", "vmwgfx": "disabled", "omap": "disabled",
              "exynos": "disabled", "freedreno": "disabled", "tegra": "disabled",
              "vc4": "disabled", "etnaviv": "disabled", "cairo-tests": "disabled",
              "man-pages": "disabled", "valgrind": "disabled",
              "install-test-programs": "false", "udev": "false", "tests": "false"},
     exports=dict(includes=["@PREFIX@/include/libdrm", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], libs=["drm"]),
     no_tests=["-Dtests=false"]),
# ---------------- L1 / L2: chained libraries ----------------
dict(dir="libnftnl", tar="libnftnl-1.2.8", version="1.2.8", kind="autotools",
     desc="Netfilter nf_tables netlink library", license="GPL-2.0",
     home="https://www.netfilter.org/projects/libnftnl/", deps=["libmnl"],
     args=["--disable-shared", "--disable-doxygen"],
     exports=dict(includes=["@PREFIX@/include/libnftnl", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], libs=["nftnl"]),
     no_tests=[]),
dict(dir="iptables", tar="iptables-1.8.11", version="1.8.11", kind="autotools",
     desc="iptables / nftables userspace packet filtering tools and libxtables", license="GPL-2.0",
     home="https://www.netfilter.org/projects/iptables/", deps=["libmnl", "libnftnl"],
     args=["--disable-shared", "--disable-devel", "--disable-libipq",
           "--disable-bpf-compiler", "--disable-nfsynproxy", "--disable-connlabel"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"],
                  libs=["xtables", "ip4tc", "ip6tc", "iptc"],
                  binaries=["@PREFIX@/sbin"]),
     no_tests=[]),
dict(dir="ipvsadm", tar="ipvsadm-1.31", version="1.31", kind="make",
     desc="IP Virtual Server administration utility (Linux IPVS)", license="GPL-2.0",
     home="https://www.linuxvirtualserver.org", deps=["libnl", "popt"],
     jobs=1,
     vars={"BUILD_ROOT": "LUA:ctx.prefix",
           "INCLUDE": "LUA:'-I' .. table.concat(ctx.includes or {}, ' -I')",
           "LIBS": "-lpopt -lnl-genl-3 -lnl-3"},
     targets=[], install_target="install",
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"],
                  binaries=["@PREFIX@/sbin"]),
     no_tests=[]),
dict(dir="libXau", tar="libXau-1.0.12", version="1.0.12", kind="autotools",
     desc="X11 authorisation library", license="MIT",
     home="https://gitlab.freedesktop.org/xorg/lib/libXau", deps=["xorgproto"],
     args=["--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["Xau"]),
     no_tests=[]),
dict(dir="libXdmcp", tar="libXdmcp-1.1.5", version="1.1.5", kind="autotools",
     desc="X Display Manager Control Protocol library", license="MIT",
     home="https://gitlab.freedesktop.org/xorg/lib/libXdmcp", deps=["xorgproto"],
     args=["--disable-shared"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["Xdmcp"]),
     no_tests=[]),
dict(dir="libxcb", tar="libxcb-1.17.0", version="1.17.0", kind="autotools",
     desc="X C Binding (XCB) library", license="MIT",
     home="https://xcb.freedesktop.org", deps=["xorgproto", "xcb-proto", "libXau", "libXdmcp"],
     no_lib_mode=True, args=["--disable-docs"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["xcb"]),
     no_tests=[]),
dict(dir="libX11", tar="libX11-1.8.12", version="1.8.12", kind="autotools",
     desc="Xlib: core X11 client library", license="MIT",
     home="https://gitlab.freedesktop.org/xorg/lib/libX11", deps=["xorgproto", "libxcb"],
     args=["--disable-shared", "--disable-specs"],
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["X11"]),
     no_tests=[]),
dict(dir="dbus", tar="dbus-1.16.2", version="1.16.2", kind="meson",
     desc="D-Bus message bus library", license="AFL-2.1/GPL-2.0",
     home="https://dbus.freedesktop.org", deps=["expat"],
     options={"modular_tests": "disabled", "intrusive_tests": "false",
              "installed_tests": "false", "doxygen_docs": "disabled",
              "xml_docs": "disabled", "traditional_activation": "false",
              "user_session": "false", "systemd": "disabled",
              "selinux": "disabled", "apparmor": "disabled",
              "libaudit": "disabled", "x11_autolaunch": "disabled"},
     exports=dict(includes=["@PREFIX@/include/dbus-1.0", "@LIBDIR@/dbus-1.0/include"],
                  libdirs=["@LIBDIR@"], libs=["dbus-1"], binaries=["@PREFIX@/bin"]),
     no_tests=["-Dmodular_tests=disabled"]),
dict(dir="kmod", tar="kmod-34.2", version="34.2", kind="meson",
     desc="Linux kernel module handling library and tools", license="LGPL-2.1",
     home="https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git", deps=[],
     opts_fn=True,
     options={"tools": "false", "manpages": "false", "docs": "false",
              "build-tests": "false", "zstd": "disabled", "xz": "disabled",
              "zlib": "disabled", "openssl": "disabled",
              "distconfdir": "LUA:ctx.prefix .. '/etc/depmod.d'",
              "moduledir": "LUA:ctx.prefix .. '/lib/modules'"},
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["kmod"]),
     no_tests=[]),
dict(dir="util-linux", tar="util-linux-2.41", version="2.41", kind="meson",
     desc="libuuid / libblkid / libmount / libsmartcols / libfdisk", license="LGPL-2.1/BSD/GPL",
     home="https://github.com/util-linux/util-linux", deps=[],
     options={"build-libuuid": "enabled", "build-libblkid": "enabled",
              "build-libmount": "enabled", "build-libsmartcols": "enabled",
              "build-libfdisk": "enabled", "build-python": "disabled",
              "nls": "disabled", "ncursesw": "disabled", "readline": "disabled",
              "selinux": "disabled", "audit": "disabled", "systemd": "disabled",
              "cryptsetup": "disabled", "magic": "disabled", "econf": "disabled",
              "zlib": "disabled", "libpcre2-posix": "disabled"},
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"],
                  libs=["uuid", "blkid", "mount", "smartcols", "fdisk"]),
     no_tests=[]),
dict(dir="libinput", tar="libinput-1.28.1", version="1.28.1", kind="meson",
     desc="Input device handling library for Wayland compositors", license="MIT",
     home="https://gitlab.freedesktop.org/libinput/libinput",
     deps=["libevdev", "wayland", "wayland-protocols"],
     options={"tests": "false", "documentation": "false",
              "debug-gui": "false", "libwacom": "false",
              "install-tests": "false"},
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"], libs=["input"]),
     no_tests=["-Dtests=false"]),
# ---------------- top-level system components ----------------
dict(dir="xserver", tar="xorg-server-21.1.16", version="21.1.16", kind="meson",
     desc="X.Org X server (Xorg / Xvfb / Xephyr)", license="MIT",
     home="https://www.x.org",
     # Link against the shared XCB: meson resolves dependency('xcb') to
     # libxcb.a when default_library=static, and the small test/ helpers then
     # lose XCB's private Xau/Xdmcp symbols.
     no_lib_mode=True,
     deps=["xorgproto", "libX11", "libxcb", "libXau", "libXdmcp", "pixman",
           "libdrm", "libpciaccess", "dbus", "openssl", "libxkbcommon", "fontutil"],
     options={"default_library": "shared", "xorg": "false", "xephyr": "false", "xvfb": "true", "xnest": "false",
              "glamor": "false", "glx": "false", "dri1": "false", "dri2": "false",
              "dri3": "false", "drm": "false", "xv": "false", "xvmc": "false",
              "dga": "false", "xinerama": "false", "xace": "false", "xselinux": "false",
              "screensaver": "false", "xres": "false", "dpms": "false",
              "mitshm": "false", "int10": "false", "vgahw": "false",
              "systemd_logind": "false", "udev": "false", "udev_kms": "false",
              "hal": "false", "agp": "false", "xf86bigfont": "false",
              "linux_apm": "false", "linux_acpi": "false", "secure-rpc": "false",
              "suid_wrapper": "false", "docs": "false", "devel-docs": "false"},
     exports=dict(includes=["@PREFIX@/include/xorg", "@PREFIX@/include"],
                  libdirs=["@LIBDIR@"], binaries=["@PREFIX@/bin"]),
     no_tests=[]),
dict(dir="systemd", tar="systemd-257.7", version="257.7", kind="meson",
     desc="systemd: libsystemd/libudev and the system/service manager", license="LGPL-2.1/GPL-2.0",
     home="https://systemd.io", deps=[], opts_fn=True,
     options={"mode": "developer", "tests": "false", "man": "disabled",
              "hwdb": "false", "translations": "false", "static-libsystemd": "false",
              "static-libudev": "false", "link-udev-shared": "false",
              "split-usr": "false", "split-bin": "false",
              "rootprefix": "LUA:ctx.prefix",
              "rootlibdir": "LUA:ctx.prefix .. '/lib'",
              "sysvinit-path": "LUA:ctx.prefix .. '/etc/init.d'",
              "sysvrcnd-path": "LUA:ctx.prefix .. '/etc/rc.d'",
              "rc-local": "LUA:ctx.prefix .. '/etc/rc.local'"},
     exports=dict(includes=["@PREFIX@/include"], libdirs=["@LIBDIR@"],
                  libs=["systemd", "udev"], binaries=["@PREFIX@/bin"]),
     no_tests=[]),
]

def build_lua(p):
    c = CAT[p["tar"]]
    kind = p["kind"]
    out = []
    out.append("-- %s" % p["desc"])
    out.append("-- gcpkg port definition.")
    out.append("local recipe = require(\"gcpkg.recipe\")")
    out.append("")
    out.append("return recipe.%s {" % kind)
    out.append("    name = %s," % q(p["dir"]))
    out.append("    version = %s," % q(p["version"]))
    out.append("    description = %s," % q(p["desc"]))
    out.append("    license = %s," % q(p.get("license", "see upstream")))
    out.append("    homepage = %s," % q(p.get("home", "")))
    out.append("    source = {")
    out.append("        url = %s," % q(c["url"]))
    out.append("        sha256 = %s," % q(c["sha256"]))
    out.append("        strip = 1,")
    out.append("    },")
    out.append("    dependencies = %s," % lua(p.get("deps", []), 4))
    if kind == "cmake":
        out.append("    cmake = {")
        out.append("        defines = %s," % lua(p.get("defines", {}), 8))
        if p.get("args"):
            out.append("        args = %s," % lua(p["args"], 8))
        out.append("    },")
    elif kind == "meson":
        out.append("    meson = {")
        if p.get("opts_fn"):
            out.append("        options = function(ctx) return %s end," % lua(p.get("options", {}), 12))
        else:
            out.append("        options = %s," % lua(p.get("options", {}), 8))
        out.append("        auto_features = \"disabled\",")
        if p.get("args"):
            out.append("        args = %s," % lua(p["args"], 8))
        out.append("    },")
    elif kind == "autotools":
        out.append("    autotools = {")
        out.append("        args = %s," % lua(p.get("args", []), 8))
        out.append("    },")
    elif kind == "make":
        out.append("    make = {")
        if p.get("vars"):
            vals = p["vars"]
            if any(isinstance(v, str) and v.startswith("LUA:") for v in vals.values()):
                out.append("        vars = function(ctx) return %s end," % lua(vals, 12))
            else:
                out.append("        vars = %s," % lua(vals, 8))
        if p.get("targets") is not None:
            out.append("        targets = %s," % lua(p.get("targets", []), 8))
        if p.get("install_target"):
            out.append("        install_target = %s," % q(p["install_target"]))
        if p.get("jobs"):
            out.append("        jobs = %d," % p["jobs"])
        out.append("    },")
    if p.get("pre"):
        stmts = []
        lua_stmts = [x[4:] for x in p["pre"] if isinstance(x, str) and x.startswith("LUA:")]
        argv = [x for x in p["pre"] if not (isinstance(x, str) and x.startswith("LUA:"))]
        if argv:
            stmts.append("        ctx.exec(%s, { cwd = ctx.src, log = ctx.log })" % lua(argv, 8))
        for st in lua_stmts:
            stmts.append("        " + st)
        out.append("    pre_build = function(ctx)")
        out.extend(stmts)
        out.append("    end,")
    out.append("    exports = %s," % lua(p.get("exports", {}), 4))
    out.append("}")
    return "\n".join(out) + "\n"

def features_yaml(p):
    kind = p["kind"]
    nt = p.get("no_tests", [])
    if kind == "cmake":
        static, shared = ["-DBUILD_SHARED_LIBS=OFF"], ["-DBUILD_SHARED_LIBS=ON"]
    elif kind == "meson":
        if p.get("no_lib_mode"):
            static, shared = [], []
        else:
            static, shared = ["-Ddefault_library=static"], ["-Ddefault_library=shared"]
    elif kind == "autotools":
        if p.get("no_lib_mode"):
            static, shared = [], []
        else:
            static, shared = ["--disable-shared"], ["--enable-shared"]
    else:
        static, shared = [], []
    def seq(xs):
        return "[" + ", ".join(q(x) for x in xs) + "]"
    lines = ["schema: 1", "port: %s" % p["dir"], "",
             "# ONE feature description per library. Enabled features inject",
             "# build arguments without editing build.lua.", "features:",
             "  no-tests:", "    default: true",
             "    description: Skip the upstream test suite", "    args: %s" % seq(nt),
             "  static:", "    default: true",
             "    description: Build static libraries", "    args: %s" % seq(static),
             "    conflicts: [\"shared\"]",
             "  shared:", "    default: false",
             "    description: Build shared libraries", "    args: %s" % seq(shared),
             "    conflicts: [\"static\"]"]
    return "\n".join(lines) + "\n"

for p in PORTS:
    d = os.path.join(ROOT, p["dir"])
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "build.lua"), "w").write(build_lua(p))
    open(os.path.join(d, "features.yaml"), "w").write(features_yaml(p))
    print("generated", p["dir"], "(%s)" % p["kind"])
print("total", len(PORTS))
