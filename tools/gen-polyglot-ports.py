#!/usr/bin/env python3
"""Generate six hand-written toolchain / polyglot ports.

These ports need custom source() and build() hooks. Each port still has
exactly one build.lua and one features.yaml.

    python3 tools/gen-polyglot-ports.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
R = os.environ.get("GCPKG_PORTS", os.path.join(os.path.dirname(HERE), "ports"))
def w(name, build, features):
    d=os.path.join(R,name); os.makedirs(d,exist_ok=True)
    open(d+'/build.lua','w').write(build)
    open(d+'/features.yaml','w').write(features)

STD='''schema: 1
port: %s

features:
  no-tests:
    default: true
    description: Skip the upstream test suite
    args: []
  static:
    default: true
    description: Build static libraries
    args: []
    conflicts: ["shared"]
  shared:
    default: false
    description: Build shared libraries
    args: []
    conflicts: ["static"]
'''

w('nasm', '''-- nasm 2.16.03 -- tool port: exports bin/ so dependents get nasm on PATH.
-- Tool port: exports bin/ so dependents get nasm on PATH.
local recipe = require("gcpkg.recipe")
return recipe.autotools {
    name = "nasm",
    version = "2.16.03",
    license = "BSD-2-Clause",
    homepage = "https://www.nasm.us",
    description = "Netwide Assembler (nasm/ndisasm), built from source as a tool port",
    source = {
        url = "https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz",
        sha256 = "1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148",
        strip = 1,
    },
    dependencies = {},
    autotools = { args = {} },
    exports = {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { "@PREFIX@/bin" },
    },
}
''', STD % 'nasm')

w('python', '''-- CPython 3.12.8 -- tool port: python3, libpython3.12.a and headers.
-- port.dependency_env() prepends <prefix>/bin to PATH and adds
-- <prefix>/lib/python3/site-packages to PYTHONPATH for every dependent.
-- The Python adapter (gcpkg.build.python / recipe.python) installs packages
-- into exactly that site-packages directory.
local recipe = require("gcpkg.recipe")
return recipe.autotools {
    name = "python",
    version = "3.12.8",
    license = "PSF-2.0",
    homepage = "https://www.python.org",
    description = "CPython interpreter and libpython, built from source as a tool port",
    source = {
        url = "https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tgz",
        sha256 = "5978435c479a376648cb02854df3b892ace9ed7d32b1fead652712bee9d03a45",
        strip = 1,
    },
    dependencies = {},
    autotools = {
        args = { "--disable-test-modules" },
    },
    -- Host pkg-config can point at a non-PIC static ncurses from another
    -- store; linking that into a shared Python extension fails with
    -- "relocation ... can not be used when making a shared object".
    -- Isolate pkg-config so configure falls back to the system shared libs.
    pre_build = function(ctx)
        ctx.env.PKG_CONFIG_LIBDIR = "/nonexistent-gcpkg-pkgconfig"
        ctx.env.PKG_CONFIG_PATH = ""
    end,
    exports = {
        includes = { "@PREFIX@/include/python3.12" },
        libdirs = { "@LIBDIR@" },
        libs = { "python3.12" },
        binaries = { "@PREFIX@/bin" },
    },
}
''', STD % 'python')

w('rust', '''-- Rust toolchain (rustc/cargo) as an EXTERNAL tool port.
-- Building rustc from source needs a multi-hour bootstrap, so it is declared
-- like the vendor SDKs: `gcpkg externals` lists the variable offline, and
-- `gcpkg install` validates it. Set GCPKG_RUST_HOME to a rustup toolchain
-- root (or CARGO_HOME=~/.cargo from a standard rustup install).
-- Its bin/ is exported, so cargo/rustc land on every dependent's PATH.
-- STATIC VALIDATION ONLY in this sandbox (no rustc/cargo installed).
local external = require("gcpkg.build.external")
return external.declare {
    name = "rust",
    version = "stable",
    description = "Rust toolchain (rustc + cargo) installed on the host",
    license = "Apache-2.0 OR MIT",
    homepage = "https://www.rust-lang.org",
    dependencies = {},
    sdk = {
        env = "GCPKG_RUST_HOME",
        alt_env = { "CARGO_HOME", "RUSTUP_HOME" },
        default = (os.getenv("HOME") or "") .. "/.cargo",
        url = "https://rustup.rs",
        probe = { "bin/cargo", "bin/rustc" },
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { "bin" },
    },
}
''', STD % 'rust')

w('tokenizers-cpp', r'''-- mlc-ai/tokenizers-cpp -- Rust -> C -> C++ binding for HF tokenizers.
-- Pinned to upstream main commit c586c52 (2026-05-20), NOT the v0.1.1 tag:
-- v0.1.1's rust/src/lib.rs passes std::HashMap to tokenizers 0.21.4's
-- BPE::new(), which now wants ahash::AHashMap, so that tag does not compile
-- against its own Cargo.lock. Upstream fixed it on main; we simply pin the
-- fixed upstream revision instead of patching any upstream file.
--
-- Three real upstream tarballs: GitHub archives ship EMPTY submodule
-- directories, so source() fills them. msgpack is the exact .gitmodules
-- commit; sentencepiece is the upstream v0.2.0 RELEASE (which vendors
-- absl + protobuf-lite) rather than main's 0.2.2 submodule commit, because
-- 0.2.2 uses FetchContent to git-clone abseil at configure time and would
-- make the source set unpinned. All three archives have pinned SHA256s, no
-- upstream file is patched. cargo comes from the `rust` tool port on PATH.
local util = require("gcpkg.util")
local fs = require("gcpkg.fs")
local net = require("gcpkg.net")
local cmake = require("gcpkg.build.cmake")

local MAIN = {
    url = "https://codeload.github.com/mlc-ai/tokenizers-cpp/tar.gz/c586c52f93f7b060753bd2388eb96a105cb7374d",
    sha256 = "257acdeb860e977efc92a6266a53dd94b6d82401d195195df1168296b808ddfe",
}
local SUBMODULES = {
    { dir = "msgpack",
      url = "https://codeload.github.com/msgpack/msgpack-c/tar.gz/092bc69b6e815980bce7808595c914dd3a29f905",
      sha256 = "ef02fd4bf993d28511110d8139e5202834bf4d3d93cfc1ef8338a8bbb7a4cd66" },
    { dir = "sentencepiece",
      url = "https://codeload.github.com/google/sentencepiece/tar.gz/refs/tags/v0.2.0",
      sha256 = "9970f0a0afee1648890293321665e5b2efa04eaec9f1671fcf8048f456f5bb86" },
}

return {
    name = "tokenizers-cpp",
    version = "main-c586c52",
    license = "Apache-2.0",
    homepage = "https://github.com/mlc-ai/tokenizers-cpp",
    description = "HuggingFace tokenizers: Rust core with C and C++ bindings (upstream main c586c52)",
    dependencies = { "rust" },
    source = function(o)
        local cache = util.join(o.dir, ".cache")
        fs.mkdirs(cache)
        local main = util.join(cache, "tokenizers-cpp.tar.gz")
        net.download(MAIN.url, main, MAIN.sha256, { log = o.log })
        net.extract(main, o.dir, 1, { log = o.log })
        for _, sub in ipairs(SUBMODULES) do
            local archive = util.join(cache, sub.dir .. ".tar.gz")
            net.download(sub.url, archive, sub.sha256, { log = o.log })
            net.extract(archive, util.join(o.dir, sub.dir), 1, { log = o.log })
        end
    end,
    build = function(ctx)
        local o = {
            src = ctx.src, build_dir = ctx.build_dir, prefix = ctx.prefix,
            exec = ctx.exec, log = ctx.log, jobs = ctx.jobs, env = ctx.env,
            defines = {
                CMAKE_BUILD_TYPE = "Release",
                BUILD_TESTING = "OFF",
                CMAKE_CXX_STANDARD = "17",
                MSGPACK_USE_BOOST = "OFF",
                MSGPACK_BUILD_TESTS = "OFF",
                MSGPACK_BUILD_EXAMPLES = "OFF",
                MLC_ENABLE_SENTENCEPIECE_TOKENIZER = "ON",
                SPM_ENABLE_SHARED = "OFF",
                SPM_ENABLE_TCMALLOC = "OFF",
                SPM_BUILD_TEST = "OFF",
                SPM_PROTOBUF_PROVIDER = "internal",
                SPM_ABSL_PROVIDER = "internal",
            },
            args = {},
        }
        -- Upstream has no install() rules, so configure+build only.
        cmake.configure(o)
        cmake.build(o)

        local libdir = util.join(ctx.prefix, "lib")
        local incdir = util.join(ctx.prefix, "include")
        fs.mkdirs(libdir)
        fs.mkdirs(incdir)
        for _, name in ipairs(fs.listdir(util.join(ctx.src, "include")) or {}) do
            local src = util.join(ctx.src, "include", name)
            if fs.isfile(src) then
                ctx.exec({ "cp", "-a", src, incdir }, { log = ctx.log })
            end
        end

        -- Collect every static archive produced anywhere in the CMake tree:
        -- libtokenizers_cpp.a, libtokenizers_c.a (copied by upstream's
        -- POST_BUILD), libsentencepiece.a and its internal protobuf-lite.
        local found = {}
        local out = ctx.capture({ "find", ctx.build_dir, "-type", "f",
                                  "-name", "*.a" }) or ""
        for path in out:gmatch("[^\n]+") do
            -- cargo puts hashed duplicates in target/release/deps/; the
            -- top-level libtokenizers_c.a is the one upstream POST_BUILDs.
            local base = path:match("([^/]+)$")
            if base and not found[base] and not path:find("/deps/", 1, true) then
                found[base] = path
            end
        end
        local order = {}
        for _, n in ipairs({ "libtokenizers_cpp.a", "libtokenizers_c.a",
                             "libsentencepiece.a", "libprotobuf-lite.a",
                             "libmsgpackc.a", "libonig.a" }) do
            if found[n] then order[#order + 1] = n end
        end
        for n in pairs(found) do
            local seen = false
            for _, x in ipairs(order) do if x == n then seen = true end end
            if not seen then order[#order + 1] = n end
        end
        local libs = {}
        for _, n in ipairs(order) do
            ctx.exec({ "cp", "-a", found[n], libdir }, { log = ctx.log })
            libs[#libs + 1] = n:gsub("^lib", ""):gsub("%.a$", "")
        end
        return {
            includes = { incdir },
            libdirs = { libdir },
            libs = libs,
            binaries = {},
            compdb_files = { util.join(ctx.build_dir, "compile_commands.json") },
        }
    end,
}
''', STD % 'tokenizers-cpp')

w('toml', '''-- PyPI `toml` 0.10.2 -- demonstrates recipe.python / gcpkg.build.python.
-- Depends on the CPython tool port, so `python3` on PATH is OUR python, and
-- the package installs into <prefix>/lib/python3/site-packages (the path
-- dependency_env() exports as PYTHONPATH for downstream ports).
local recipe = require("gcpkg.recipe")
return recipe.python {
    name = "toml",
    version = "0.10.2",
    license = "MIT",
    homepage = "https://github.com/uiri/toml",
    description = "Python TOML parser, installed via PEP 517 pip into the gcpkg prefix",
    source = {
        url = "https://files.pythonhosted.org/packages/source/t/toml/toml-0.10.2.tar.gz",
        sha256 = "b3bda1d108d5dd99f4a20d24d9c348e91c4db7ab1b749200bded2f839ccbe68f",
        strip = 1,
    },
    dependencies = { "python" },
    python = { mode = "pip", python = "python3", args = {} },
    exports = {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = {},
    },
}
''', (STD % 'toml') + '''  pip:
    default: false
    description: Use pip install --target instead of setup.py install
''')

w('ryu', '''-- dtolnay/ryu 1.0.18 -- demonstrates recipe.cargo / gcpkg.build.cargo.
-- cargo/rustc come from the `rust` external tool port on PATH. The crate is
-- built unmodified; artifacts are copied into <prefix>/lib and <prefix>/bin.
-- Rust crates are linked with cargo (rlib), not with the C linker, so no
-- `libs` are exported. STATIC VALIDATION ONLY in this sandbox (no rustc).
local recipe = require("gcpkg.recipe")
return recipe.cargo {
    name = "ryu",
    version = "1.0.18",
    license = "Apache-2.0 OR BSL-1.0",
    homepage = "https://github.com/dtolnay/ryu",
    description = "Fast floating-point to string conversion crate (Rust)",
    source = {
        url = "https://codeload.github.com/dtolnay/ryu/tar.gz/refs/tags/1.0.18",
        sha256 = "0eed569707a685810ecfea323a4c242a71dcab9867bfe0d5dc198419b6fdae79",
        strip = 1,
    },
    dependencies = { "rust" },
    cargo = { args = {} },
    exports = {
        includes = {},
        libdirs = { "@LIBDIR@" },
        libs = {},
        binaries = { "@PREFIX@/bin" },
    },
}
''', STD % 'ryu')
print('generated 6 toolchain/polyglot ports into', R)
