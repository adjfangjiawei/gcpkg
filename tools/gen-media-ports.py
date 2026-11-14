#!/usr/bin/env python3
"""Generate media, AI, networking and vendor-SDK ports from the catalog.

Source of truth: tools/media-catalog.tsv (real upstream URLs and SHA256 for
every anonymously downloadable tarball) plus the META table below (per-port
build options, exports and vendor-SDK metadata). The engine does NOT need this
script at runtime: it only reads ports/<name>/build.lua + features.yaml.

    python3 tools/gen-media-ports.py
    ./build/bin/gcpkg check --ports ./ports
"""
import csv
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
TSV = os.path.join(HERE, "media-catalog.tsv")

STD_EXPORTS = {"includes": ["@PREFIX@/include"], "libdirs": ["@LIBDIR@"],
               "libs": [], "binaries": []}


def ex(libs=(), binaries=(), includes=None, libdirs=None):
    return {
        "includes": list(includes if includes is not None else STD_EXPORTS["includes"]),
        "libdirs": list(libdirs if libdirs is not None else STD_EXPORTS["libdirs"]),
        "libs": list(libs), "binaries": list(binaries),
    }


# Everything that is not a URL/SHA lives here: build-system switches, exported
# artifacts, SDK discovery metadata and honest verification notes.
META = {
    "cmake": dict(exports=ex(binaries=["@PREFIX@/bin"]),
                  notes="Built from Kitware's bootstrap (no upstream patch). Exported as a tool port: dependents get its bin/ prepended to PATH.",
                  verified="dynamic"),
    "lua": dict(exports=ex(libs=["lua"], binaries=["@PREFIX@/bin"]),
                notes="Hand-written Makefile: 'make linux' then 'make install INSTALL_TOP=<prefix>'. CC is forced to gcpkg-intercept so compdb is produced.",
                verified="dynamic"),
    "alsa-lib": dict(exports=ex(libs=["asound"]),
                     autotools_args=["--disable-python"],
                     notes="Autotools. Host ALSA headers via pkgconfig backend; --disable-python avoids Python SWIG bindings.",
                     verified="static"),
    "libpsl": dict(exports=ex(libs=["psl"]),
                   pre_build="    if not fs.isfile(ctx.src .. '/configure') then\n        ctx.exec({ 'autoreconf', '-fi' }, { cwd = ctx.src, log = ctx.log })\n    end",
                   notes="GitHub tag archives ship configure.ac only; pre_build regenerates ./configure when needed. Needs libidn2/libunistring headers from the host.",
                   verified="static"),
    "libfuse": dict(exports=ex(libs=["fuse3"]),
                    meson_options={},
                    notes="libfuse 3 uses Meson. No guessed -D options: meson setup runs with the upstream defaults plus gcpkg's prefix/sysconfdir confinement.",
                    verified="static"),
    "live555": dict(exports=ex(libs=["liveMedia", "groupsock", "BasicUsageEnvironment", "UsageEnvironment"]),
                    notes="Upstream has no install target: ./genMakefiles linux, make, then copy the per-component .a and headers into the gcpkg prefix.",
                    verified="static"),
    "librtsp": dict(exports=ex(libs=["rtsp"]),
                    notes="ireader/media-server is a multi-library repo; the build hook enters librtsp/. Adjust its gcc script per upstream README if the layout changes.",
                    verified="static"),
    "ucx": dict(exports=ex(libs=["ucp", "ucs", "uct"]),
                pre_build="    if not fs.isfile(ctx.src .. '/configure') then\n        ctx.exec({ './autogen.sh' }, { cwd = ctx.src, log = ctx.log })\n    end",
                notes="Autotools; CUDA/ROCm support is optional and comes from the 'nvidia' SDK port when enabled.",
                verified="static"),
    "folly": dict(exports=ex(libs=["folly"]),
                  cmake_defines={"BUILD_TESTING": "OFF", "BUILD_TESTS": "OFF"},
                  notes="Wide dependency surface: reuses the existing gcpkg L0 chain (cmake, openssl, zlib, zstd, lz4, bzip2). boost/glog/gflags/fmt/double-conversion/libevent come from the host pkgconfig backend.",
                  verified="static"),
    "fizz": dict(exports=ex(libs=["fizz"]), cmake_defines={"BUILD_TESTING": "OFF", "BUILD_TESTS": "OFF"},
                 notes="Facebook v2026.10.26.00 release line, same tag as folly/wangle/mvfst/proxygen.", verified="static"),
    "wangle": dict(exports=ex(libs=["wangle"]), cmake_defines={"BUILD_TESTING": "OFF", "BUILD_TESTS": "OFF"},
                   notes="Depends on folly + fizz from the same release line.", verified="static"),
    "mvfst": dict(exports=ex(libs=["mvfst"]), cmake_defines={"BUILD_TESTING": "OFF", "BUILD_TESTS": "OFF"},
                  notes="QUIC transport layer for proxygen.", verified="static"),
    "proxygen": dict(exports=ex(libs=["proxygen"]), cmake_defines={"BUILD_TESTING": "OFF", "BUILD_TESTS": "OFF"},
                     notes="Top of the Facebook stack: folly -> fizz -> wangle/mvfst -> proxygen (plus cmake and the L0 crypto/compression chain).",
                     verified="static"),
    "redpanda": dict(exports=ex(binaries=["@PREFIX@/bin"]),
                     cmake_defines={"BUILD_TESTING": "OFF"},
                     notes="C++/Seastar monorepo; declared with its CMake entry point. Full build additionally needs clang, Seastar deps and Rust toolchain on the host.",
                     verified="static"),
    "vulkan-headers": dict(exports=ex(libs=[]), cmake_defines={},
                           notes="Khronos Vulkan-Headers: header/registry-only CMake install, feeds the loader.", verified="static"),
    "vulkan": dict(exports=ex(libs=["vulkan"]), cmake_defines={"BUILD_TESTS": "OFF"},
                   notes="Khronos Vulkan-Loader; depends on vulkan-headers and the managed cmake tool port.", verified="static"),
    "dcgm": dict(exports=ex(libs=["dcgm"]), cmake_defines={"BUILD_TESTING": "OFF"},
                 notes="NVIDIA DCGM open-core tree; needs the local CUDA driver/toolkit ('nvidia' SDK port) and vendor-only diagnostics components.", verified="static"),
    "nv-image-codec": dict(exports=ex(libs=["nvimgcodec"]), cmake_defines={"BUILD_TESTS": "OFF"},
                           notes="nvImageCodec requires CUDA >= 12.1 and optionally CV-CUDA (its samples). Both are declared gcpkg ports.", verified="static"),
    "cv-cuda": dict(exports=ex(libs=["nvcv"]), cmake_defines={"BUILD_TESTS": "OFF"},
                    notes="CV-CUDA needs the local CUDA toolkit ('nvidia' SDK port).", verified="static"),
    # ---- vendor SDK ports: no download, no compile, discovered at install ----
    "nvidia": dict(sdk=dict(
        env="GCPKG_NVIDIA_HOME", alt_env=["CUDA_HOME", "CUDA_PATH"],
        default="/usr/local/cuda", url="https://developer.nvidia.com/cuda-downloads",
        probe=["include/cuda_runtime.h"], includes=["include"],
        libdirs=["lib64", "lib", "lib64/stubs"], binaries=["bin"],
        libs=["cudart", "cuda", "nvidia-ml"],
        description="NVIDIA CUDA Toolkit / driver platform"),
        notes="Version string is a placeholder for the store key; the real version is whatever $GCPKG_NVIDIA_HOME (or $CUDA_HOME, or /usr/local/cuda) points at.",
        verified="static"),
    "cann": dict(sdk=dict(
        env="GCPKG_CANN_HOME", alt_env=["ASCEND_HOME_PATH", "ASCEND_HOME"],
        default="/usr/local/Ascend/ascend-toolkit/latest",
        url="https://www.hiascend.com/developer/download/community/",
        probe=["include/acl/acl.h"], includes=["include"], libdirs=["lib64"],
        binaries=["bin"], libs=["ascendcl"],
        description="Huawei CANN Ascend toolkit (AscendCL / ops)"),
        notes="The .run installers are ~1-2 GB and licence-gated; point GCPKG_CANN_HOME (or ASCEND_HOME_PATH) at an installed toolkit.",
        verified="static"),
    "nv-codec-sdk": dict(sdk=dict(
        env="GCPKG_NV_CODEC_SDK_HOME", alt_env=["NV_CODEC_SDK_HOME"],
        default="/opt/nvidia/video-codec-sdk",
        url="https://developer.nvidia.com/video-codec-sdk",
        probe=["include/nvEncodeAPI.h"], includes=["include"],
        libdirs=["Lib/linux/stubs/x86_64"], binaries=[],
        libs=["nvidia-encode", "nvcuvid"],
        description="NVIDIA Video Codec SDK (NVENC/NVDEC headers + driver stubs)"),
        notes="Login-walled archive. Headers (nvEncodeAPI.h, cuviddec.h, nvcuvid.h) plus driver stub libs; depends on the 'nvidia' platform port.",
        verified="static"),
    "dahuaplayer": dict(sdk=dict(
        env="GCPKG_DAHUAPLAYER_HOME", alt_env=["DAHUA_PLAYSDK_HOME"],
        default="/opt/dahua/playsdk",
        url="https://www.dahuatech.com/service/downloadlists/837.html",
        probe=["include/dhplay.h"], includes=["include"], libdirs=["lib"],
        binaries=[], libs=["dhplay"],
        description="Dahua PlaySDK / dhplay proprietary playback library"),
        notes="Proprietary binary SDK from Dahua's support portal (official SHA256 of the Linux64 V3.044 bundle is published there). No anonymous download, no recompilation.",
        verified="static"),
}

CUSTOM_BUILD = {
    "custom-cmake": '''    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        ctx.exec({ "./bootstrap", "--prefix=" .. ctx.prefix, "--parallel=" .. j },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "-j" .. j }, { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install" }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = {},
            binaries = { ctx.prefix .. "/bin" },
        }
    end,
''',
    "custom-lua": '''    build = function(ctx)
        local j = tostring(ctx.jobs or 4)
        local cc = ctx.env.CC
        ctx.exec({ "make", "-j" .. j, "linux", "CC=" .. cc, "MYCFLAGS=-fPIC" },
                 { cwd = ctx.src, log = ctx.log })
        ctx.exec({ "make", "install", "INSTALL_TOP=" .. ctx.prefix, "CC=" .. cc },
                 { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "lua" },
            binaries = { ctx.prefix .. "/bin" },
        }
    end,
''',
    "custom-live555": '''    build = function(ctx)
        ctx.exec({ "./genMakefiles", "linux" }, { cwd = ctx.src, log = ctx.log })
        -- live555 makefiles are not parallel-safe; serial on purpose.
        ctx.exec({ "make", "-j1" }, { cwd = ctx.src, log = ctx.log })
        -- live555 has no install target: collect the four component archives.
        local cp = "mkdir -p '" .. ctx.prefix .. "/lib' '" .. ctx.prefix .. "/include' && " ..
                   "cp -f */lib*.a '" .. ctx.prefix .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f */include/* '" .. ctx.prefix .. "/include/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = ctx.src, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "liveMedia", "groupsock", "BasicUsageEnvironment", "UsageEnvironment" },
            binaries = {},
        }
    end,
''',
    "custom-librtsp": '''    build = function(ctx)
        local util = require("gcpkg.util")
        local d = util.join(ctx.src, "librtsp")
        ctx.exec({ "make", "-j1", "CC=" .. ctx.env.CC }, { cwd = d, log = ctx.log })
        local cp = "mkdir -p '" .. ctx.prefix .. "/lib' '" .. ctx.prefix .. "/include' && " ..
                   "cp -f *.a '" .. ctx.prefix .. "/lib/' 2>/dev/null || true; " ..
                   "cp -f include/*.h '" .. ctx.prefix .. "/include/' 2>/dev/null || true"
        ctx.exec({ "sh", "-c", cp }, { cwd = d, log = ctx.log })
        return {
            includes = { ctx.prefix .. "/include" },
            libdirs = { ctx.prefix .. "/lib" },
            libs = { "rtsp" },
            binaries = {},
        }
    end,
''',
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
    pad = " " * indent
    out = "{\n"
    import re
    for k, v in d.items():
        key = k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[" + L(k) + "]"
        if isinstance(v, list):
            val = ARR(v, indent + 2)
        else:
            val = L(v)
        out += pad + key + " = " + val + ",\n"
    return out + " " * (indent - 2) + "}"


def exports_block(e):
    lines = ["    exports = {"]
    for k in ("includes", "libdirs", "libs", "binaries"):
        lines.append("      %s = %s," % (k, ARR(e.get(k, []), 8)))
    lines.append("    },")
    return "\n".join(lines)


def header(row, meta):
    return ("-- %s %s -- gcpkg port definition.\n"
            "-- %s\n" %
            (row["name"], row["version"],
             meta.get("notes", "").replace("\n", " ")))


def build_lua(row):
    name, kind = row["name"], row["kind"]
    meta = META[name]
    deps = [d for d in row["deps"].split(",") if d]
    out = [header(row, meta), ""]

    if kind == "external":
        sdk = meta["sdk"]
        out.append('local external = require("gcpkg.build.external")')
        out.append("")
        out.append("return external.declare {")
        for k in ("name", "version", "description", "license", "homepage"):
            val = row[k] if (k in row and row[k]) else sdk.get(k, "")
            out.append("    %s = %s," % (k, L(val)))
        out.append("    dependencies = %s," % ARR(deps, 8))
        out.append("    sdk = {")
        for k in ("env", "default", "url", "description"):
            out.append("        %s = %s," % (k, L(sdk[k])))
        for k in ("alt_env", "probe", "includes", "libdirs", "binaries", "libs"):
            out.append("        %s = %s," % (k, ARR(sdk.get(k, []), 12)))
        out.append("    },")
        out.append("}")
        return "\n".join(out) + "\n"

    if not kind.startswith("custom-"):
        out.append('local recipe = require("gcpkg.recipe")')
    if meta.get("pre_build"):
        out.append('local fs = require("gcpkg.fs")')
    out.append("")

    if kind.startswith("custom-"):
        out.append("return {")
        for k in ("name", "version", "description", "license", "homepage"):
            val = row["desc"] if k == "description" else row[k]
            out.append("    %s = %s," % (k, L(val)))
        out.append("    source = {")
        out.append("        url = %s," % L(row["url"]))
        out.append("        sha256 = %s," % L(row["sha256"]))
        out.append("        strip = 1,")
        out.append("    },")
        out.append("    dependencies = %s," % ARR(deps, 8))
        out.append(CUSTOM_BUILD[kind].rstrip("\n"))
        out.append("}")
        return "\n".join(out) + "\n"

    recipe_kind = kind  # cmake / meson / autotools
    out.append("return recipe.%s {" % recipe_kind)
    for k in ("name", "version", "description", "license", "homepage"):
        out.append("    %s = %s," % (k, L(row[k] if k != "description" else row["desc"])))
    out.append("    source = {")
    out.append("        url = %s," % L(row["url"]))
    out.append("        sha256 = %s," % L(row["sha256"]))
    out.append("        strip = 1,")
    out.append("    },")
    out.append("    dependencies = %s," % ARR(deps, 8))
    if recipe_kind == "cmake":
        out.append("    cmake = {")
        out.append("        defines = %s," % TBL(meta.get("cmake_defines", {}), 10))
        out.append("        args = {},")
        out.append("    },")
    elif recipe_kind == "meson":
        out.append("    meson = {")
        out.append("        options = %s," % TBL(meta.get("meson_options", {}), 10))
        out.append("        args = {},")
        out.append("    },")
    else:
        out.append("    autotools = {")
        out.append("        args = %s," % ARR(meta.get("autotools_args", []), 10))
        out.append("    },")
    if meta.get("pre_build"):
        out.append("    pre_build = function(ctx)")
        out.append(meta["pre_build"])
        out.append("    end,")
    out.append(exports_block(meta["exports"]))
    out.append("}")
    return "\n".join(out) + "\n"


def features_yaml(row):
    name, meta = row["name"], META[row["name"]]
    lines = [
        "schema: 1",
        "port: %s" % name,
        "",
        "# %s" % meta.get("notes", "").replace("\n", " "),
        "features:",
    ]
    if row["kind"] == "external":
        sdk = meta["sdk"]
        lines += [
            "  system-sdk:",
            "    default: true",
            "    description: Use the local SDK pointed at by $%s (no download, no compile)" % sdk["env"],
            "    args: []",
        ]
    else:
        lines += [
            "  no-tests:",
            "    default: true",
            "    description: Skip the upstream test suite",
            "    args: []",
            "  static:",
            "    default: true",
            "    description: Build static libraries",
            "    args: []",
            "    conflicts: [\"shared\"]",
            "  shared:",
            "    default: false",
            "    description: Build shared libraries",
            "    args: []",
            "    conflicts: [\"static\"]",
        ]
    return "\n".join(lines) + "\n"


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
