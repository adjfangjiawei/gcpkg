# Port 注册表

每个库恰好两个文件：`build.lua`（构建描述）+ `features.yaml`（特性描述）。
当前共 **226 个 port**（第四轮 +36，第五轮 +23，第六轮 +37，第七轮 +34 个
内核/磁盘库，第九轮 +43 个基础库，第十轮 +38 个库与代理支持）。`gcpkg ports` 按依赖层级列出，`gcpkg graph <port>` 打印
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

## 第五轮：媒体 / AI / 网络 / 厂商 SDK（23 个 port）

**默认静态验证**（`tests/media.sh`）：注册表、依赖图、URL+SHA256、SDK 环境变量、
依赖解析，均不下载不编译。`lua` 与 `alsa-lib` 另外做了真编译（34 / 113 条
compdb），`nvidia` 用临时假 SDK 目录验证了 adapter 全链路；其余由你在本机验证。

| port | 版本 | 接入方式 | 依赖（gcpkg） | 本轮验证 |
| --- | --- | --- | --- | --- |
| `cmake` | 3.31.6 | 自定义 `build(ctx)`（`./bootstrap`） | — | 静态（工具 port，导出 `bin/` 到 PATH） |
| `lua` | 5.4.7 | 自定义 `build(ctx)`（`make linux`） | — | ✅ 真编译 34 条，`bin/lua -v` |
| `alsa-lib` | 1.2.9 | autotools | — | ✅ 真编译 113 条 |
| `libpsl` | 0.21.0 | autotools + `pre_build(autoreconf)` | — | 静态 |
| `libfuse` | 3.18.3 | Meson | — | 静态 |
| `live555` | 2021.11.14 | 自定义 `build(ctx)`（`genMakefiles`） | — | 静态（上游无 install target，脚本收集 4 个 `.a`） |
| `librtsp` | 1.0.0 | 自定义 `build(ctx)`（子目录 `librtsp/`） | — | 静态 |
| `ucx` | 1.23.2 | autotools + `pre_build(autogen.sh)` | — | 静态 |
| `folly` | 2026.10.26.00 | CMake | `cmake,openssl,zlib,zstd,lz4,bzip2` | 静态 |
| `fizz` | 2026.10.26.00 | CMake | `folly,openssl,cmake` | 静态 |
| `wangle` | 2026.10.26.00 | CMake | `folly,fizz,cmake` | 静态 |
| `mvfst` | 2026.10.26.00 | CMake | `folly,fizz,cmake` | 静态 |
| `proxygen` | 2026.10.26.00 | CMake | `folly,fizz,wangle,mvfst,cmake` | 静态（`graph` 11 步） |
| `redpanda` | 26.2.2 | CMake | `cmake` | 静态 |
| `vulkan-headers` | 1.4.363.0 | CMake | — | 静态 |
| `vulkan` | 1.4.363.0 | CMake（Loader） | `vulkan-headers,cmake` | 静态 |
| `dcgm` | 4.7.0 | CMake | `nvidia` | 静态 |
| `cv-cuda` | 0.19.0 | CMake | `nvidia` | 静态 |
| `nv-image-codec` | 0.10.0 | CMake | `nvidia,cv-cuda` | 静态 |
| `nvidia` | 12.8 | **external SDK**（`GCPKG_NVIDIA_HOME`） | — | ✅ adapter 冒烟（0 compdb） |
| `cann` | 9.0.0 | **external SDK**（`GCPKG_CANN_HOME`） | — | 静态 |
| `nv-codec-sdk` | 12.2 | **external SDK**（`GCPKG_NV_CODEC_SDK_HOME`） | `nvidia` | 静态 |
| `dahuaplayer` | 3.044.0000000.1 | **external SDK**（`GCPKG_DAHUAPLAYER_HOME`） | — | 静态 |

`tools/gen-media-ports.py` + `tools/media-catalog.tsv` 可重新生成这 23 套
文件（19 个 tarball 的 URL/SHA256 均为实际下载计算值；`lua` 用 lua.org
官方包而非只有 `src/` 的 GitHub 镜像）。外部 SDK 的版本号只是 store key 的
占位，实际版本由你本地 `$GCPKG_<NAME>_HOME` 决定，详见
[docs/EXTERNAL_SDKS.md](../docs/EXTERNAL_SDKS.md)。

## 第六轮：更多 Linux 基础库（37 个 port）

`gcpkg check` = **111 ports OK**。37 个 tarball 的 URL/SHA256 均为实测值
（`tools/linux-base-catalog.tsv`），由 `tools/gen-linux-base-ports.py` 生成。
默认静态验证（`tests/linux-base.sh`）；14 个代表性库在这里从干净源码真编译，
合计 **884 条编译命令**，其余交给你在本机验证。

| port | 版本 | 构建系统 | 依赖（gcpkg） | 本轮验证 |
| --- | --- | --- | --- | --- |
| `gmp` | 6.3.0 | autotools | — | 静态 |
| `mpfr` | 4.2.2 | autotools | gmp | 静态 |
| `mpc` | 1.3.1 | autotools | gmp, mpfr | 静态 |
| `nettle` | 3.10 | autotools | gmp | 静态 |
| `libtasn1` | 4.20.0 | autotools | — | 静态 |
| `libunistring` | 1.3 | autotools | — | 静态 |
| `libidn2` | 2.3.8 | autotools | libunistring | 静态 |
| `libgpg-error` | 1.55 | autotools | — | ✅ 真编译 43 条 |
| `libgcrypt` | 1.11.1 | autotools | libgpg-error | 静态 |
| `libsodium` | 1.0.20 | autotools | — | ✅ 真编译 119 条 |
| `mbedtls` | 3.6.7 | cmake | — | 静态 |
| `gnutls` | 3.8.9 | autotools | nettle, gmp, libtasn1, libidn2, libunistring, zlib | 静态 |
| `libevent` | 2.1.13 | cmake | openssl | 静态 |
| `libuv` | 1.53.0 | cmake | — | 静态 |
| `jansson` | 2.15.1 | cmake | — | ✅ 真编译 70 条 |
| `sqlite3` | 3.46.1 | autotools | — | 静态 |
| `ncurses` | 6.5 | autotools | — | ✅ 真编译 364 条 |
| `readline` | 8.2.13 | autotools | ncurses | ✅ 真编译 34 条 |
| `oniguruma` | 6.9.10 | cmake | — | 静态 |
| `utf8proc` | 2.12.0 | cmake | — | ✅ 真编译 4 条 |
| `xxhash` | 0.8.4 | custom-make | — | ✅ 真编译 10 条 |
| `libdeflate` | 1.26 | cmake | — | ✅ 真编译 52 条 |
| `libpng` | 1.6.59 | cmake | zlib | ✅ 真编译 70 条 |
| `libjpeg-turbo` | 3.2.1 | cmake | — | 静态 |
| `libtiff` | 4.7.0 | cmake | zlib, xz, zstd, libjpeg-turbo | 静态 |
| `freetype` | 2.13.3 | cmake | zlib, bzip2, libpng, brotli | 静态 |
| `fontconfig` | 2.16.0 | autotools | freetype, expat | 静态 |
| `harfbuzz` | 15.1.0 | meson | freetype, glib | 静态 |
| `glib` | 2.84.4 | meson | libffi, zlib, pcre2 | 静态 |
| `libxslt` | 1.1.43 | autotools | libxml2 | ✅ 真编译 30 条 |
| `libusb` | 1.0.30 | autotools | — | ✅ 真编译 10 条 |
| `elfutils` | 0.192 | autotools | zlib, zstd, xz | 静态 |
| `libbpf` | 1.8.0 | custom-libbpf | elfutils, zlib | 静态 |
| `libattr` | 2.5.2 | autotools | — | ✅ 真编译 14 条 |
| `libacl` | 2.3.2 | autotools | libattr | ✅ 真编译 61 条 |
| `libnfnetlink` | 1.0.2 | autotools | — | ✅ 真编译 3 条 |
| `libnetfilter_conntrack` | 1.0.9 | autotools | libnfnetlink, libmnl | 静态 |

依赖图示例：`graph gnutls` 7 步（gmp → nettle → libtasn1 → libunistring →
libidn2 → zlib → gnutls）、`graph libbpf` 5 步（zlib / zstd / xz → elfutils
→ libbpf）、`graph fontconfig` 7 步。真编译子集用 `GCPKG_BASE_DYNAMIC=1
./tests/linux-base.sh` 复现；上游源码始终不改，适配全在 `build.lua`
的选项 / `pre_build` / 自定义 `build(ctx)` 里。

## 第七轮：内核接口与磁盘信息查询（34 个 port）

`gcpkg check` = **145 ports OK**。34 个 tarball 的 URL/SHA256 均为实测值，
构建系统种类逐个解压核对（`tools/linux-kernel-catalog.tsv`，
`tools/gen-linux-kernel-ports.py` 可重新生成）。默认静态验证
（`tests/linux-kernel.sh`）；22 个在这里真编译（含第四轮已有的 `liburing`
复核），合计 **1061 条编译命令**。用法见 [docs/DISK_INFO.md](../docs/DISK_INFO.md)。

| port | 版本 | 构建系统 | 依赖（gcpkg） | 本轮验证 |
| --- | --- | --- | --- | --- |
| `libnvme` | 1.16.2 | meson | liburing | ✅ 真编译 123 条 |
| `nvme-cli` | 2.16 | meson | libnvme | ✅ 真编译 115 条 |
| `libgudev` | 238 | meson | glib | 静态 |
| `udisks2` | 2.11.2 | autotools | glib, dbus, libgudev, libatasmart, libnvme, libparted, util-linux, libacl | 静态 |
| `libstoragemgmt` | 1.11.0 | autotools | glib, libnvme | 静态 |
| `btrfs-progs` | 6.19.1 | autotools | util-linux, zlib, zstd, lz4 | 静态 |
| `e2fsprogs` | 1.47.4 | autotools | util-linux | 静态 |
| `lvm2` | 2.03.43 | autotools | util-linux, libaio | 静态 |
| `pciutils` | 3.15.0 | custom-make | zlib | ✅ 真编译 36 条 |
| `libgpiod` | 2.3.2 | meson | — | ✅ 真编译 154 条 |
| `libiio` | 0.26 | cmake | libusb, libxml2 | ✅ 真编译 46 条 |
| `hidapi` | 0.15.0 | cmake | libusb | ✅ 真编译 6 条 |
| `libserialport` | 0.1.2 | autotools | — | ✅ 真编译 4 条 |
| `libaudit` | 3.1.5 | autotools | — | 静态 |
| `libunwind` | 1.8.3 | autotools | zlib, xz | ✅ 真编译 179 条 |
| `rpcsvc-proto` | 1.4.4 | autotools | — | ✅ 真编译 0 条 |
| `libconfuse` | 3.4 | autotools | — | ✅ 真编译 12 条 |
| `sg3_utils` | 1.48 | autotools | — | ✅ 真编译 94 条 |
| `smartmontools` | 7.4 | autotools | — | ✅ 真编译 2 条 |
| `libtraceevent` | 1.8.4 | meson | — | ✅ 真编译 45 条 |
| `libtracefs` | 1.8.2 | meson | libtraceevent | ✅ 真编译 97 条 |
| `xfsprogs` | 6.12.0 | autotools | util-linux, libattr | 静态 |
| `lm-sensors` | 3.6.0 | custom-make | — | 静态 |
| `i2c-tools` | 4.4 | custom-make | — | 静态 |
| `dmidecode` | 3.6 | custom-make | — | ✅ 真编译 0 条 |
| `mdadm` | 4.4 | custom-make | — | ✅ 真编译 0 条 |
| `libparted` | 3.6 | autotools | util-linux | ✅ 真编译 123 条 |
| `libmicrohttpd` | 1.0.1 | autotools | gnutls, libgcrypt | 静态 |
| `libdaemon` | 0.14 | autotools | — | ✅ 真编译 7 条 |
| `hdparm` | 9.65 | custom-make | — | ✅ 真编译 0 条 |
| `libatasmart` | 0.19 | autotools | — | ✅ 真编译 4 条 |
| `keyutils` | 1.6.3 | custom-make | — | ✅ 真编译 0 条 |
| `libtirpc` | 1.3.6 | autotools | rpcsvc-proto | 静态 |
| `libselinux` | 3.8 | custom-make | pcre2, libseccomp | 静态 |

依赖图：`graph udisks2` 15 步（含 `liburing → libnvme`）、`graph nvme-cli`
3 步、`graph libtracefs` 2 步。上游源码始终不改，适配全在 `build.lua`
的选项 / `pre_build` / 自定义 `build(ctx)` 与 `features.yaml` 的 env 里。

## 多版本 port

`ports/zlib/features.yaml` 与 `ports/jansson/features.yaml` 里有 `versions:`
块（每个版本真实 URL + SHA256），因此 `gcpkg versions zlib` 能看到
1.3.1 / 1.2.13 / 1.2.12 / 1.2.11，`gcpkg add zlib@1.2.13 -C <project>`
会让该项目真编译 1.2.13，而其它项目仍用默认的 1.3.1。其余 port 保持单版本。
项目私有 port、公有 registry、用户级 registry 三者的优先级与 `gcpkg.lock`
见 `docs/PROJECTS.md`。

## 第九轮：43 个新基础库（188 ports total）

| port | 版本 | kind | 依赖 | 真编译 compdb |
| --- | --- | --- | --- | --- |
| `yyjson` | 0.10.0 | cmake | — | 4 |
| `cjson` | 1.7.18 | cmake | — | 6 |
| `rapidjson` | 1.1.0 | cmake | — | 2 |
| `libcbor` | 0.11.0 | cmake | — | 60 |
| `inih` | r58 | meson | — | 6 |
| `libbase64` | 0.5.2 | cmake | — | 29 |
| `simdjson` | 3.10.0 | cmake | — | 6 |
| `snappy` | 1.2.2 | cmake | — | 12 |
| `zlib-ng` | 2.2.4 | cmake | — | 99 |
| `c-blosc` | 1.21.6 | cmake | — | 124 |
| `lzfse` | 1.0 | cmake | — | 18 |
| `miniz` | 3.0.2 | cmake | — | 22 |
| `nghttp3` | 1.11.0 | cmake | — | 128 |
| `ngtcp2` | 1.16.0 | cmake | — | 190 |
| `libssh` | 0.11.1 | cmake | openssl,zlib | 134 |
| `hiredis` | 1.2.0 | cmake | — | 16 |
| `libmodbus` | 3.1.11 | autotools | — | 12 |
| `libdnet` | 1.12 | autotools | — | 28 |
| `libnet` | 1.3 | autotools | — | 51 |
| `libwebsockets` | 4.3.3 | cmake | zlib | 144 |
| `librdkafka` | 2.8.0 | autotools | zlib | 121 |
| `libogg` | 1.3.5 | cmake | — | 8 |
| `libvorbis` | 1.3.7 | cmake | libogg | 48 |
| `opus` | 1.5.2 | cmake | — | 309 |
| `flac` | 1.4.3 | cmake | libogg | 108 |
| `libwebp` | 1.5.0 | cmake | — | 346 |
| `libsamplerate` | 0.2.2 | cmake | — | 10 |
| `libsecp256k1` | 0.6.0 | cmake | — | 10 |
| `wolfssl` | 5.7.6 | autotools | — | 35 |
| `fmt` | 11.2.0 | cmake | — | 6 |
| `spdlog` | 1.15.3 | cmake | fmt | 14 |
| `lmdb` | 0.9.31 | custom-make | — | 13 |
| `capstone` | 5.0.3 | cmake | — | 162 |
| `googletest` | 1.15.2 | cmake | — | 12 |
| `libedit` | 3.1 | autotools | ncurses | 32 |
| `pcre` | 8.45 | cmake | — | 48 |
| `libconfig` | 1.7.3 | autotools | — | 17 |
| `giflib` | 5.2.2 | custom-make | — | 24 |
| `libsndfile` | 1.2.2 | cmake | libogg,libvorbis,opus,flac | 189 |
| `libvpx` | 1.15.0 | custom-make | nasm（第十一轮起） | 211 |
| `libtheora` | 1.1.1 | autotools | libogg | 34 |
| `libzip` | 1.11.3 | cmake | zlib | 250 |
| `libmaxminddb` | 1.12.2 | cmake | — | 8 |

来源 `tools/extra-catalog.tsv`，生成器 `tools/gen-extra-ports.py`；全部 43 个
在干净 store 真编译通过（合计 3056 条），`GCPKG_EXTRA_DYNAMIC=1
./tests/extra.sh` 可复现。条件依赖：`graph libzip --feature=libzip:openssl`
等四条会额外拉起 openssl。详见 `docs/EXTRA_LIBRARIES.md`。

第十一轮又新增 23 个 port（17 个常见库 + `nasm` / `python` / `rust` /
`tokenizers-cpp` / `toml` / `ryu`），总计 **249** 个；其中 `libvpx`
由纯 C 目标改为经 `nasm` 工具 port 编 SIMD。完整清单见
`docs/ROUND11_LIBRARIES.md` 与 `docs/TOOLCHAINS.md`。
