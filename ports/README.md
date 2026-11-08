# Port 注册表

每个库恰好两个文件：`build.lua`（构建描述）+ `features.yaml`（特性描述）。
当前共 **15 个 port**。`gcpkg ports` 按依赖层级列出，`gcpkg graph <port>` 打印
自底向上的构建顺序，`gcpkg check` 校验文件齐全、Lua 可加载、依赖可解析；
三者都接受 `--feature=...`，会把特性 `requires:` 引入的条件依赖算进图里。

## L0：无 gcpkg 依赖的基础库

| port | 版本 | 构建系统 | 产物 | 已验证 |
| --- | --- | --- | --- | --- |
| `bzip2` | 1.0.8 | 手写 Makefile（自定义 build.lua） | `libbz2.a` / `bzlib.h` | ✅ 9 条编译命令 |
| `brotli` | 1.1.0 | CMake | `libbrotli{common,enc,dec}.a` | ✅ 66 |
| `cares` | 1.34.5 | CMake | `libcares` | ✅ 184 |
| `expat` | 2.7.1 | CMake | `libexpat.a` | ✅ 8 |
| `libffi` | 3.4.8 | autotools | `libffi.a` / `ffi.h` | ✅ 10 |
| `lz4` | 1.10.0 | CMake（`build/cmake`） | `liblz4.a` | ✅ 12 |
| `openssl` | 3.4.1 | `perl Configure` + make（自定义 build.lua） | `libssl.a` / `libcrypto.a` | ✅ 1128 |
| `pcre2` | 10.45 | CMake | `libpcre2-8.a` | ✅ 62 |
| `xz` | 5.8.1 | CMake | `liblzma.a` | ✅ 200 |
| `zlib` | 1.3.1 | CMake | `libz.a` / `libz.so` | ✅ 62 |
| `zstd` | 1.5.7 | CMake（`build/cmake`） | `libzstd.a`（`shared` 特性可出 `.so`） | ✅ 80 |

全部源码包都带 SHA256 校验（校验和来自实际下载的 tarball），编译数据库由
`gcpkg-intercept` 或构建系统自身的 `compile_commands.json` 生成。

## L1 / L2：依赖下层库的上层库

| port | 版本 | 层级 | 依赖 | 已验证 |
| --- | --- | --- | --- | --- |
| `libssh2` | 1.11.1 | L1 | openssl, zlib | ✅ 52 条编译命令 |
| `nghttp2` | 1.65.0 | L1 | zlib | ✅ 26 |
| `libarchive` | 3.7.9 | L1 | zlib, bzip2, xz, zstd, lz4, openssl, expat, pcre2 | ✅ 327 |
| `curl` | 8.13.0 | L2 | openssl, zlib, brotli, zstd, cares, nghttp2, libssh2 | ✅ 291 |

`gcpkg graph curl` 给出自底向上的构建顺序：openssl → zlib → brotli → zstd →
cares → nghttp2 → libssh2 → curl。上层库的 `CPPFLAGS` / `LDFLAGS` /
`PKG_CONFIG_PATH` / `CMAKE_PREFIX_PATH` 由下层库 manifest 自动汇总，CMake 的
`find_package()` 与 pkg-config 就能找到它们，curl 本身一行未改。

`gcpkg graph libarchive` 给出 9 步：zlib → bzip2 → xz → zstd → lz4 → openssl →
expat → pcre2 → libarchive。上游 CMake 的 `FIND_PACKAGE()` 全部命中 gcpkg 前缀
（实测 `CMakeCache.txt` 里 `ZLIB_LIBRARY` / `BZIP2_LIBRARY_RELEASE` /
`OPENSSL_CRYPTO_LIBRARY` / `ZSTD_LIBRARY` / `LZ4_LIBRARY` / `EXPAT_LIBRARY_RELEASE`
均指向 `<store>/pkg/<dep>`），只用 `CMAKE_PREFIX_PATH` + `ENABLE_*` 宏，源码零修改。

## 特性条件依赖

`features.yaml` 里的 `requires:` 会变成**真实**的传递依赖，而不只是构建参数：

```yaml
# ports/openssl/features.yaml
zlib:
  default: false
  args: ["zlib"]          # perl Configure → enable-zlib
  requires: ["zlib"]      # 先编译 zlib，注入其 -I/-L/PKG_CONFIG_PATH
```

```bash
gcpkg graph openssl --feature=openssl:zlib   # 1. zlib  2. openssl
gcpkg install openssl --feature=openssl:zlib --store ~/.cache/gcpkg-store
```

`port.install()` 与 `graph.deps()` 都用同一套 `features.resolve()`，因此依赖图、
manifest 的 `deps`、构建环境和缓存 fingerprint 一致。`tests/features.sh` 真编译
这条链并断言 `-DZLIB`、gcpkg zlib 的 include 路径，以及 `libcrypto.a` 里的
`BIO_f_zlib` / `COMP_zlib` 符号。

`examples/web` 是站在整条链顶端的项目；`tests/chain.sh` 会构建全链并验证
合并后的 `compile_commands.json` 覆盖所有层级（沙箱从零实测 2115 条、134 个源码目录，
所有源文件路径有效；复用旧缓存的 store 为 1689 条 / 124 目录）。`tests/features.sh` 覆盖条件依赖，`tests/smoke.sh` 覆盖
最初的 OpenSSL/hello 回归。

> store 请放真实磁盘（`~/.cache/...` 或 `GCPKG_STORE`）：本沙箱 `/tmp` 是 992M
> 的 tmpfs，多库并行构建会 `No space left on device`。测试脚本已默认迁走。

## 常用写法

```lua
local recipe = require("gcpkg.recipe")
return recipe.cmake {
  name = "foo", version = "1.2.3",
  source = { url = "...", sha256 = "...", strip = 1 },
  dependencies = { "zlib" },
  cmake = { defines = { BUILD_TESTING = "OFF" } },
  exports = { includes = {"@PREFIX@/include"}, libdirs = {"@LIBDIR@"},
              libs = {"foo"} },
}
```

`recipe.autotools` / `recipe.make` / 自定义 `build(ctx)` 见
[docs/EXTENDING.md](../docs/EXTENDING.md)。上层库声明 `dependencies` 后，所有
下层库的 `-I` / `-L` / `PKG_CONFIG_PATH` / `CMAKE_PREFIX_PATH` 会自动出现在它的
构建环境里，无需修改上游项目。
