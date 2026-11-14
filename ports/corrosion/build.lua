-- corrosion 0.4.4 -- gcpkg source port for Ada's Rust/Cargo benchmark bridge.
-- The generator is compiled from source with the official Rust toolchain and
-- an offline, SHA-verified Cargo vendor bundle.  No host rustup, no build-time
-- registry access and no library-side platform probe.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")

local function cargo_env(ctx)
    local rust = assert(ctx.dep("rust-toolchain"),
                       "gcpkg: corrosion: missing rust-toolchain dependency")
    local vendor = assert(ctx.dep("rust-crates-vendor"),
                         "gcpkg: corrosion: missing rust-crates-vendor dependency")
    local rustPrefix = assert(rust.prefix,
                              "gcpkg: corrosion: rust-toolchain has no prefix")
    local vendorPrefix = assert(vendor.prefix,
                                "gcpkg: corrosion: rust-crates-vendor has no prefix")
    local cargoHome = ctx.build_dir .. "/cargo-home"
    local vendorDir = vendorPrefix .. "/vendor"
    fs.mkdirs(cargoHome)
    fs.write(cargoHome .. "/config.toml",
             "[source.crates-io]\n" ..
             "replace-with = \"vendored-sources\"\n\n" ..
             "[source.vendored-sources]\n" ..
             "directory = \"" .. vendorDir .. "\"\n\n" ..
             "[net]\n" ..
             "offline = true\n")
    ctx.env.CARGO_HOME = cargoHome
    ctx.env.CARGO_NET_OFFLINE = "true"
    ctx.env.CARGO_TARGET_DIR = ctx.build_dir .. "/cargo-target"
    ctx.env.RUSTC = rustPrefix .. "/bin/rustc"
    ctx.env.PATH = rustPrefix .. "/bin:" .. (ctx.env.PATH or "")
    return rustPrefix .. "/bin/cargo", rustPrefix
end

local function write_config(ctx, prefix)
    local cmakedir = prefix .. "/lib/cmake/Corrosion"
    fs.mkdirs(cmakedir)
    local cfg = [==[
get_filename_component(_CORROSION_PREFIX "${CMAKE_CURRENT_LIST_DIR}" PATH)
get_filename_component(_CORROSION_PREFIX "${_CORROSION_PREFIX}" PATH)
get_filename_component(_CORROSION_PREFIX "${_CORROSION_PREFIX}" PATH)
set(_CORROSION_CMAKE_DIR "${_CORROSION_PREFIX}/share/cmake")
list(APPEND CMAKE_MODULE_PATH "${_CORROSION_CMAKE_DIR}")
if(NOT TARGET Corrosion::Generator)
    add_executable(Corrosion::Generator IMPORTED GLOBAL)
    set_target_properties(Corrosion::Generator PROPERTIES
        IMPORTED_LOCATION "${_CORROSION_PREFIX}/libexec/corrosion-generator")
endif()
include(Corrosion)
set(Corrosion_FOUND TRUE)
]==]
    fs.write(cmakedir .. "/CorrosionConfig.cmake", cfg)
    fs.write(cmakedir .. "/CorrosionConfigVersion.cmake", [==[
set(PACKAGE_VERSION "0.4.4")
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

local function build(ctx)
    local on = ctx.features.enabled
    local prefix = ctx.prefix
    local libexecdir = prefix .. "/libexec"
    local cmakedir = prefix .. "/lib/cmake/Corrosion"
    local sharedir = prefix .. "/share/cmake"
    local docdir = prefix .. "/share/doc/corrosion"
    local generatorTarget = ctx.build_dir .. "/generator-target"
    local testTarget = ctx.build_dir .. "/generator-test-target"
    fs.mkdirs(prefix)
    fs.mkdirs(libexecdir)
    fs.mkdirs(sharedir)
    fs.mkdirs(docdir)
    fs.mkdirs(generatorTarget)
    fs.mkdirs(testTarget)

    local cargo, rustPrefix
    if on["generator"] or on["tests"] or on["examples"] or on["sanity"] then
        cargo, rustPrefix = cargo_env(ctx)
    end

    if on["generator"] then
        assert(on["cmake-package"],
               "gcpkg: corrosion: generator needs the CMake package feature")
        local cmd = {
            cargo, "build", "--offline", "--locked", "--release",
            "--manifest-path", ctx.src .. "/generator/Cargo.toml",
            "--target-dir", generatorTarget,
        }
        ctx.record({
            directory = ctx.src .. "/generator",
            file = ctx.src .. "/generator/src/main.rs",
            arguments = cmd,
            output = generatorTarget .. "/release/corrosion-generator",
            tag = "rust",
        })
        ctx.exec(cmd, { cwd = ctx.src, log = ctx.log, env = ctx.env })
        local exe = generatorTarget .. "/release/corrosion-generator"
        assert(fs.isfile(exe),
               "gcpkg: corrosion: cargo did not produce corrosion-generator")
        ctx.exec({ "cp", "-a", exe, libexecdir .. "/corrosion-generator" },
                 { cwd = ctx.src, log = ctx.log })
    end

    if on["cmake-package"] then
        assert(on["generator"],
               "gcpkg: corrosion: CMake package needs the generator feature")
        for _, name in ipairs({
            "Corrosion.cmake", "CorrosionGenerator.cmake", "FindRust.cmake"
        }) do
            ctx.exec({ "cp", "-a", ctx.src .. "/cmake/" .. name,
                       sharedir .. "/" .. name },
                     { cwd = ctx.src, log = ctx.log })
        end
        write_config(ctx, prefix)
    end
    if on["docs"] then
        ctx.exec({ "cp", "-a", ctx.src .. "/doc/.", docdir .. "/" },
                 { cwd = ctx.src, log = ctx.log })
        for _, name in ipairs({ "README.md", "RELEASES.md" }) do
            ctx.exec({ "cp", "-a", ctx.src .. "/" .. name,
                       docdir .. "/" .. name },
                     { cwd = ctx.src, log = ctx.log })
        end
    end
    if on["license"] then
        ctx.exec({ "cp", "-a", ctx.src .. "/LICENSE", docdir .. "/LICENSE" },
                 { cwd = ctx.src, log = ctx.log })
    end

    if on["tests"] then
        local cmd = {
            cargo, "test", "--offline", "--locked", "--release",
            "--manifest-path", ctx.src .. "/generator/Cargo.toml",
            "--target-dir", testTarget,
        }
        ctx.record({
            directory = ctx.src .. "/generator",
            file = ctx.src .. "/generator/src/main.rs",
            arguments = cmd,
            output = testTarget .. "/release/deps",
            tag = "rust",
        })
        local out = ctx.build_dir .. "/generator-test.out"
        ctx.exec({ "sh", "-c", table.concat(cmd, " ") ..
                   " > " .. out .. " 2>&1" },
                 { cwd = ctx.src, log = ctx.log, env = ctx.env })
        local result = assert(fs.read(out),
                              "gcpkg: corrosion: missing generator test output")
        assert(result:find("test result: ok", 1, true),
               "gcpkg: corrosion: generator cargo test did not pass")
    end

    local cons = ctx.build_dir .. "/corrosion-consumer"
    local consBuild = cons .. "/build"
    local consumerExe = consBuild .. "/consumer"
    if on["examples"] or on["sanity"] then
        assert(on["cmake-package"],
               "gcpkg: corrosion: consumer needs the CMake package feature")
        fs.mkdirs(cons .. "/rust/src")
        fs.write(cons .. "/rust/Cargo.toml", [==[
[package]
name = "gcpkg_corrosion_sanity"
version = "0.1.0"
edition = "2021"

[lib]
name = "gcpkg_corrosion_sanity"
path = "src/lib.rs"
crate-type = ["staticlib"]
]==])
        fs.write(cons .. "/rust/Cargo.lock", [==[
# This file is automatically @generated by Cargo.
# It is not intended for manual editing.
version = 3

[[package]]
name = "gcpkg_corrosion_sanity"
version = "0.1.0"
]==])
        fs.write(cons .. "/rust/src/lib.rs", [==[
#[no_mangle]
pub extern "C" fn gcpkg_corrosion_answer() -> i32 { 42 }
]==])
        fs.write(cons .. "/CMakeLists.txt", [==[
cmake_minimum_required(VERSION 3.16)
project(corrosion_consumer LANGUAGES CXX)
find_package(Corrosion 0.4.4 CONFIG REQUIRED)
corrosion_import_crate(MANIFEST_PATH "${CMAKE_CURRENT_SOURCE_DIR}/rust/Cargo.toml")
add_executable(consumer main.cpp)
target_link_libraries(consumer PRIVATE gcpkg_corrosion_sanity)
]==])
        fs.write(cons .. "/main.cpp", [==[
#include <cstdio>
extern "C" int gcpkg_corrosion_answer();
int main() {
    int n = gcpkg_corrosion_answer();
    if (n != 42) return 2;
    std::printf("corrosion consumer ok: %d\n", n);
    return 0;
}
]==])
        local configure = {
            "cmake", "-S", cons, "-B", consBuild,
            "-DCMAKE_PREFIX_PATH=" .. prefix,
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_C_COMPILER=" .. ctx.compiler.wrapper_cc,
            "-DCMAKE_CXX_COMPILER=" .. ctx.compiler.wrapper_cxx,
            "-DCMAKE_C_COMPILER_FORCED=TRUE",
            "-DCMAKE_CXX_COMPILER_FORCED=TRUE",
            "-DCMAKE_C_COMPILER_WORKS=TRUE",
            "-DCMAKE_CXX_COMPILER_WORKS=TRUE",
            "-DCMAKE_C_ABI_COMPILED=TRUE",
            "-DCMAKE_CXX_ABI_COMPILED=TRUE",
            "-DRust_COMPILER=" .. rustPrefix .. "/bin/rustc",
            "-DRust_CARGO=" .. rustPrefix .. "/bin/cargo",
            "-DRust_RESOLVE_RUSTUP_TOOLCHAINS=OFF",
        }
        ctx.record({
            directory = cons, file = cons .. "/main.cpp",
            arguments = configure, output = consumerExe, tag = "cmake",
        })
        ctx.exec(configure, { cwd = cons, log = ctx.log, env = ctx.env })
        local build_cmd = { "cmake", "--build", consBuild, "--config", "Release" }
        ctx.record({
            directory = cons, file = cons .. "/main.cpp",
            arguments = build_cmd, output = consumerExe, tag = "cmake",
        })
        ctx.exec(build_cmd, { cwd = cons, log = ctx.log, env = ctx.env })
        assert(fs.isfile(consumerExe),
               "gcpkg: corrosion: CMake consumer was not built")
    end
    if on["sanity"] then
        assert(on["examples"],
               "gcpkg: corrosion: sanity needs the examples feature")
        local out = ctx.build_dir .. "/corrosion-consumer.out"
        ctx.exec({ "sh", "-c", consumerExe .. " > " .. out .. " 2>&1" },
                 { cwd = cons, log = ctx.log, env = ctx.env })
        local result = assert(fs.read(out),
                              "gcpkg: corrosion: missing consumer output")
        assert(result:find("corrosion consumer ok", 1, true),
               "gcpkg: corrosion: CMake/Rust consumer did not run")
    end

    return {
        includes = {},
        libdirs = {},
        libs = {},
        binaries = { libexecdir },
        defines = {},
        link_flags = {},
        compdb_files = {},
    }
end

return recipe.define {
    name = "corrosion",
    version = "0.4.4",
    license = "MIT",
    homepage = "https://github.com/corrosion-rs/corrosion",
    description = "Corrosion CMake/Rust bridge source port for Ada benchmarks",
    source = {
        url = "https://codeload.github.com/corrosion-rs/corrosion/tar.gz/refs/tags/v0.4.4",
        sha256 = "bf3981d0e066f2c877949ec59d9ed6cb193ae4ff615b73f20c64a5de68fc06ab",
        strip = 1,
    },
    dependencies = {},
    build = build,
    exports = {
        binaries = { "@PREFIX@/libexec" },
    },
}
