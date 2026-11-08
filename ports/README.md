# Port 注册表

每个库恰好两个文件：`build.lua`（构建描述）+ `features.yaml`（特性描述）。
当前共 **51 个 port**（其中第四轮新增 36 个 Linux 底层库）。`gcpkg ports` 按依赖层级列出，`gcpkg graph <port>` 打印
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

## 第四轮：Linux 底层库栈（36 个 port，全部真实编译）

`gcpkg check --ports ./ports` = **51 ports OK**；`gcpkg ports` 分层为
L0 31 / L1 11 / L2 5 / L3 2 / L4 1。`gcpkg graph xserver` 给出 16 步
自底向上顺序。下表「条」是该 port 自己的编译命令数（合计 6718），
纯数据 port 为 0。

| port | 版本 | 构建系统 | 条 | 说明 |
| --- | --- | --- | --- | --- |
| `libnuma` | 2.0.19 | 手写 Makefile | 19 | NUMA |
| `libcap` | 2.76 | 手写 Makefile | 15 | capabilities |
| `libcap-ng` | 0.8.4 | autotools | 8 | `pre_build` 补 `NEWS` + `autoreconf -fi` |
| `libseccomp` | 2.6.0 | autotools | 34 | seccomp |
| `libmnl` | 1.0.5 | autotools | 4 | netlink 基础 |
| `libnftnl` | 1.2.8 | autotools | 65 | nftables netlink |
| `libnl` | 3.11.0 | autotools | 135 | IPVS 依赖 |
| `popt` | 1.19 | autotools | 9 | `pre_build` 补 `NEWS` + `autoreconf -fi` |
| `json-c` | 0.18 | CMake | 32 | JSON |
| `libyaml` | 0.2.5 | autotools | 19 | release tarball 的 CMake 模板不全，改 autotools |
| `libxml2` | 2.14.5 | autotools | 82 | XML |
| `libpcap` | 1.10.5 | autotools | 19 | 抓包 |
| `libaio` | 0.3.113 | 手写 Makefile | 25 | 异步 IO |
| `liburing` | 2.9 | configure + make | 14 | io_uring |
| `libevdev` | 1.13.4 | Meson | 7 | 输入设备 |
| `libpciaccess` | 0.18.1 | Meson | 25 | PCI |
| `pixman` | 0.44.2 | Meson | 65 | 像素合成 |
| `xorgproto` | 2024.1 | Meson | 1 | X11 协议头 |
| `xcb-proto` | 1.17.0 | autotools | 0 | 纯数据：XCB XML |
| `libxkbcommon` | 1.7.0 | Meson | 185 | 键盘映射 |
| `kmod` | 34.2 | Meson | 46 | `options(ctx)` 把 `distconfdir` 收进 prefix |
| `util-linux` | 2.41 | Meson | 833 | 系统工具集 |
| `libnftnl` / `iptables` | 1.8.11 | autotools | 161 | iptables / nft 前端 |
| `ipvsadm` | 1.31 | 手写 Makefile | 5 | `jobs=1` 规避竞态，显式补 `-lnl-genl-3` |
| `libXau` | 1.0.12 | autotools | 8 | X11 认证 |
| `libXdmcp` | 1.1.5 | autotools | 9 | XDMCP |
| `libxcb` | 1.17.0 | autotools | 35 | 同时出 `.a` / `.so` |
| `libX11` | 1.8.12 | autotools | 410 | Xlib |
| `dbus` | 1.16.2 | Meson | 255 | D-Bus |
| `wayland-protocols` | 1.45 | Meson | 59 | 纯协议（仍有编译探测） |
| `wayland` | 1.23.1 | Meson | 29 | libwayland-server / client |
| `libdrm` | 2.4.124 | Meson | 13 | DRM |
| `libinput` | 1.28.1 | Meson | 166 | 输入栈汇聚 |
| `xserver` | 21.1.16 | Meson | 596 | `Xvfb`，`default_library=shared` 链接 XCB |
| `systemd` | 257.7 | Meson | 3272 | `libsystemd.so` / `libudev.so`；`hwdb=false` |
| `fontutil` | 1.4.2 | autotools | 0 | 纯数据：`fontutil.pc`，Xserver 的 `dependency('fontutil')` |

真实编译 store：`~/.cache/gcpkg-linux-store`。关键产物包括
`pkg/xserver-21.1.16/bin/Xvfb`、`pkg/systemd-257.7/lib/libsystemd.so`、
`pkg/wayland-1.23.1/lib/libwayland-server.a`、`pkg/ipvsadm-1.31/sbin/ipvsadm`、
`pkg/fontutil-1.4.2/lib/pkgconfig/fontutil.pc`。

**系统依赖边界**：`xtrans` / `xfont2` / `xkbfile` / `libudev` / `libmount` /
`libaudit` / `libpam` / `libgcrypt` / `glib` 等仍由宿主 `-dev` 提供，经
`pkgconfig` backend 参与 `find_package` / `dependency()`；`fontutil` 没有
Debian 包，所以补了一个纯数据 port。`tests/linux.sh` 校验全部 36 个
manifest、6718 条 JSONL 的绝对路径、12 个关键产物，以及 clangd 对
libnuma / wayland / libX11 / xserver / systemd 五个 compdb 的加载。
