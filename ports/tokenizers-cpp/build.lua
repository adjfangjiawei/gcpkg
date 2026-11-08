-- mlc-ai/tokenizers-cpp -- Rust -> C -> C++ binding for HF tokenizers.
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
