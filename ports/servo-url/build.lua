-- servo-url 0.1.0 -- Ada 2.9.2 benchmark competitor Rust cdylib.
-- Built from the pinned Ada source tree with the official Rust toolchain and
-- an offline, SHA-verified Cargo vendor bundle.  No host Rust, no rustup, no
-- configure-time Cargo download and no library-side platform probe.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local cc = require("gcpkg.build.cc")

local function cargo_env(ctx)
    local rust = assert(ctx.dep("rust-toolchain"),
                       "gcpkg: servo-url: missing rust-toolchain dependency")
    local vendor = assert(ctx.dep("rust-crates-vendor"),
                         "gcpkg: servo-url: missing rust-crates-vendor dependency")
    local rustPrefix = assert(rust.prefix,
                              "gcpkg: servo-url: rust-toolchain has no prefix")
    local vendorPrefix = assert(vendor.prefix,
                                "gcpkg: servo-url: rust-crates-vendor has no prefix")
    local cargoHome = ctx.build_dir .. "/cargo-home"
    fs.mkdirs(cargoHome)
    fs.write(cargoHome .. "/config.toml",
             "[source.crates-io]\n" ..
             "replace-with = \"vendored-sources\"\n\n" ..
             "[source.vendored-sources]\n" ..
             "directory = \"" .. vendorPrefix .. "/vendor\"\n\n" ..
             "[net]\n" ..
             "offline = true\n")
    ctx.env.CARGO_HOME = cargoHome
    ctx.env.CARGO_NET_OFFLINE = "true"
    ctx.env.CARGO_TARGET_DIR = ctx.build_dir .. "/cargo-target"
    ctx.env.RUSTC = rustPrefix .. "/bin/rustc"
    ctx.env.PATH = rustPrefix .. "/bin:" .. (ctx.env.PATH or "")
    return rustPrefix .. "/bin/cargo"
end

local function build(ctx)
    local on = ctx.features.enabled
    local prefix = ctx.prefix
    local incdir = prefix .. "/include"
    local libdir = prefix .. "/lib"
    local bindir = prefix .. "/bin"
    local cmakedir = libdir .. "/cmake/servo-url"
    local docdir = prefix .. "/share/doc/servo-url"
    local objdir = ctx.build_dir .. "/obj"
    fs.mkdirs(incdir)
    fs.mkdirs(libdir)
    fs.mkdirs(bindir)
    fs.mkdirs(cmakedir)
    fs.mkdirs(docdir)
    fs.mkdirs(objdir)

    local cargo
    if on["library"] or on["tests"] then
        cargo = cargo_env(ctx)
    end

    if on["library"] then
        local cmd = {
            cargo, "build", "--offline", "--locked", "--release",
            "--manifest-path", ctx.src .. "/Cargo.toml",
            "--target-dir", ctx.build_dir .. "/cargo-target",
        }
        local so = ctx.build_dir .. "/cargo-target/release/libservo_url.so"
        ctx.record({
            directory = ctx.src, file = ctx.src .. "/lib.rs",
            arguments = cmd, output = so, tag = "rust",
        })
        ctx.exec(cmd, { cwd = ctx.src, log = ctx.log, env = ctx.env })
        assert(fs.isfile(so),
               "gcpkg: servo-url: cargo did not produce libservo_url.so")
        ctx.exec({ "cp", "-a", so, libdir .. "/libservo_url.so" },
                 { cwd = ctx.src, log = ctx.log })
    end

    if on["tests"] then
        assert(on["library"],
               "gcpkg: servo-url: cargo test needs the library feature")
        local cmd = {
            cargo, "test", "--offline", "--locked", "--release",
            "--manifest-path", ctx.src .. "/Cargo.toml",
            "--target-dir", ctx.build_dir .. "/cargo-test-target",
        }
        ctx.record({
            directory = ctx.src, file = ctx.src .. "/lib.rs",
            arguments = cmd,
            output = ctx.build_dir .. "/cargo-test-target/release/deps",
            tag = "rust",
        })
        local out = ctx.build_dir .. "/cargo-test.out"
        ctx.exec({ "sh", "-c", table.concat(cmd, " ") ..
                   " > " .. out .. " 2>&1" },
                 { cwd = ctx.src, log = ctx.log, env = ctx.env })
        local result = assert(fs.read(out),
                              "gcpkg: servo-url: missing cargo test output")
        assert(result:find("test result: ok", 1, true),
               "gcpkg: servo-url: cargo test did not pass")
    end

    if on["headers"] then
        ctx.exec({ "cp", "-a", ctx.src .. "/servo_url.h",
                   incdir .. "/servo_url.h" },
                 { cwd = ctx.src, log = ctx.log })
    end
    if on["cmake-package"] then
        assert(on["library"],
               "gcpkg: servo-url: CMake package needs the library feature")
        assert(on["headers"],
               "gcpkg: servo-url: CMake package needs the headers feature")
        fs.write(cmakedir .. "/servo-urlConfig.cmake", [==[
get_filename_component(_SERVO_URL_PREFIX "${CMAKE_CURRENT_LIST_DIR}" PATH)
get_filename_component(_SERVO_URL_PREFIX "${_SERVO_URL_PREFIX}" PATH)
get_filename_component(_SERVO_URL_PREFIX "${_SERVO_URL_PREFIX}" PATH)
if(NOT TARGET servo-url)
    add_library(servo-url SHARED IMPORTED)
    set_target_properties(servo-url PROPERTIES
        IMPORTED_LOCATION "${_SERVO_URL_PREFIX}/lib/libservo_url.so"
        INTERFACE_INCLUDE_DIRECTORIES "${_SERVO_URL_PREFIX}/include")
endif()
set(servo-url_FOUND TRUE)
]==])
        fs.write(cmakedir .. "/servo-urlConfigVersion.cmake", [==[
set(PACKAGE_VERSION "0.1.0")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
    set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
    set(PACKAGE_VERSION_COMPATIBLE TRUE)
    if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
        set(PACKAGE_VERSION_EXACT TRUE)
    endif()
endif()
]==])
    end
    if on["license"] then
        if fs.isdir(ctx.src .. "/licenses") then
            ctx.exec({ "cp", "-a", ctx.src .. "/licenses/.", docdir .. "/" },
                     { cwd = ctx.src, log = ctx.log })
        end
    end

    local demo = bindir .. "/servo_url_demo"
    if on["examples"] or on["sanity"] then
        assert(on["library"] and on["headers"],
               "gcpkg: servo-url: demo needs library and headers")
        local src = ctx.build_dir .. "/servo_url_demo.cpp"
        fs.write(src, [==[
#include <servo_url.h>
#include <cstdio>
#include <cstring>
int main() {
    const char *input = "https://example.com/path?q=1#frag";
    servo_url::Url *url = servo_url::parse_url(input, std::strlen(input));
    if (!url) return 2;
    servo_url::free_url(url);
    const char *href = servo_url::parse_url_to_href(input, std::strlen(input));
    if (!href) return 3;
    int ok = std::strcmp(input, href) == 0;
    std::printf("servo-url ok: %s\n", href);
    servo_url::free_string(href);
    return ok ? 0 : 4;
}
]==])
        demo = cc.executable {
            sources = { src },
            includes = { incdir },
            flags = { "-std=c++17" },
            cwd = ctx.build_dir, outdir = objdir,
            compiler = ctx.compiler.wrapper_cxx,
            exec = ctx.exec, record = ctx.record, log = ctx.log,
            tag = "servo-url", cxx = true,
            output = demo,
            libdirs = { libdir }, libs = { "servo_url" },
        }
    end
    if on["sanity"] then
        assert(on["examples"],
               "gcpkg: servo-url: sanity needs the examples feature")
        local out = ctx.build_dir .. "/servo-url-demo.out"
        ctx.exec({ "sh", "-c", demo .. " > " .. out .. " 2>&1" },
                 { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
        local result = assert(fs.read(out),
                              "gcpkg: servo-url: missing demo output")
        assert(result:find("servo-url ok", 1, true),
               "gcpkg: servo-url: C++ C ABI demo did not run")
    end

    return {
        includes = { incdir },
        libdirs = { libdir },
        libs = { "servo_url" },
        binaries = { bindir },
        defines = {},
        link_flags = {},
        compdb_files = {},
    }
end

return recipe.define {
    name = "servo-url",
    version = "0.1.0",
    license = "Apache-2.0 OR MIT",
    homepage = "https://github.com/ada-url/ada",
    description = "Ada 2.9.2 benchmark servo-url Rust/C ABI competitor",
    source = {
        url = "https://gcpkg.local/offline/servo-url-0.1.0.tar.gz",
        sha256 = "3d75f2cfd959c036b2a5565390dd6a6c877cc5b81d8c55a1471468dedf3ed124",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "servo_url" },
        binaries = { "@PREFIX@/bin" },
    },
}
