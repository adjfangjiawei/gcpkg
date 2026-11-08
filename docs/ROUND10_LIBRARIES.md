# 第十轮：38 个新库 + 代理设置

用户这一轮的要求是「继续支持更多的库，包管理器要支持设置代理」。注册表
从 **188 个扩展到 226 个**，新增 38 个此前未覆盖的库；代理部分单独写在
[docs/PROXY.md](PROXY.md)。这一轮 **38 个新 port 全部在干净 store 里从源码
真编译通过**：`GCPKG_R10_DYNAMIC=1 ./tests/r10.sh` = `38 PASS / 0 FAIL,
2498 compile commands`，并逐个校验 manifest、导出的 `.a`/`.so` 与 SHA256。
所有 URL/SHA256 都是真实下载后的实测值，上游源码一行未改，适配全部落在
生成的 `build.lua` / `features.yaml` 里。

## 覆盖面

| 主题 | 新增库 |
| --- | --- |
| C++ 数据格式 / 序列化 | `zopfli`(压缩)、`tinyxml2`、`pugixml`、`jsoncpp`、`tomlplusplus`、`yaml-cpp`、`flatbuffers`、`nlohmann-json` |
| 测试 / 工具链 | `benchmark`、`catch2`、`doctest`、`magic-enum`、`gflags`、`glog`、`double-conversion`、`abseil`、`re2` |
| 加密 / 哈希 / 数学 | `libtommath`、`libtomcrypt`、`blake3`、`libsrtp`、`libidn` |
| 图像 / 颜色 / 音频 | `lcms2`、`libexif`、`fribidi`、`libunibreak`、`portaudio` |
| 系统 / 事件 / 网络 | `libmd`、`libbsd`、`libeconf`、`libev`、`mosquitto`、`srt`、`libcoap`、`libatomic-ops`、`cunit`、`check` |
| 调试信息 | `libdwarf` |

## 38 个 port（全部真编译）

| port | 版本 | 构建系统 | 静态依赖 | 条件特性 | compdb |
| --- | --- | --- | --- | --- | --- |
| `zopfli` | 1.0.3 | cmake | — | — | 38 |
| `tinyxml2` | 10.0.0 | cmake | — | — | 6 |
| `pugixml` | 1.14 | cmake | — | — | 4 |
| `jsoncpp` | 1.9.6 | cmake | — | — | 14 |
| `tomlplusplus` | 3.4.0 | cmake | — | — | 2 |
| `magic-enum` | 0.9.7 | cmake | — | — | 2 |
| `nlohmann-json` | 3.11.3 | cmake | — | — | 2 |
| `flatbuffers` | 24.3.25 | cmake | — | — | 84 |
| `benchmark` | 1.9.1 | cmake | — | — | 47 |
| `catch2` | 3.7.1 | cmake | — | — | 214 |
| `doctest` | 2.4.11 | cmake | — | — | 2 |
| `yaml-cpp` | 0.8.0 | cmake | — | — | 60 |
| `libtommath` | 1.3.0 | cmake | — | — | 310 |
| `libtomcrypt` | 1.18.2 | make | — | ltm → libtommath | 408 |
| `blake3` | 1.8.2 | cmake (`c/`) | — | — | 18 |
| `libsrtp` | 2.6.0 | cmake | — | openssl → openssl | 38 |
| `libexif` | 0.6.24 | autotools | — | — | 28 |
| `lcms2` | 2.16 | autotools | — | — | 31 |
| `fribidi` | 1.0.15 | meson | — | — | 63 |
| `libunibreak` | 5.1 | autotools | — | — | 8 |
| `portaudio` | 19.7.0 | cmake | — | alsa → alsa-lib | 30 |
| `libbsd` | 0.12.2 | autotools | libmd | — | 48 |
| `libmd` | 1.1.0 | autotools | — | — | 16 |
| `libeconf` | 0.7.5 | cmake | — | — | 68 |
| `libev` | 4.33 | autotools | — | — | 2 |
| `mosquitto` | 2.0.20 | cmake | — | tls → openssl | 180 |
| `srt` | 1.5.4 | cmake | — | tls → openssl | 64 |
| `libcoap` | 4.3.5 | cmake | — | tls → openssl | 76 |
| `libdwarf` | 0.11.1 | cmake | — | compression → zlib+zstd | 120 |
| `check` | 0.15.2 | cmake | — | — | 46 |
| `cunit` | 2.1-3 | autotools | — | — | 8 |
| `libatomic-ops` | 7.8.2 | cmake | — | — | 4 |
| `gflags` | 2.2.2 | cmake | — | — | 14 |
| `glog` | 0.7.1 | cmake | gflags | — | 22 |
| `double-conversion` | 3.3.0 | cmake | — | — | 20 |
| `abseil` | 20240722.0 | cmake | — | — | 312 |
| `re2` | 2024-07-02 | cmake | abseil | — | 46 |
| `libidn` | 1.42 | autotools | — | — | 43 |

合计 **2498** 条编译命令（各库 manifest 的 `compdb_entries`，
干净 store 实测）。header-only 库（`tomlplusplus` / `magic-enum` /
`nlohmann-json` / `doctest` / `abseil`）的 `exports.libs` 为空，
只导出头文件 / CMake package config。

## 依赖面与条件依赖

```
abseil ──► re2          gflags ──► glog          libmd ──► libbsd

```
三条真实静态链都由 `graph` 校验为 2 步；`re2` 通过 `find_package(absl)`
命中 abseil 安装的 CMake config，`glog` 通过 `WITH_GFLAGS=ON` 命中 gflags，
`libbsd` 的 `libmd` 由 `PKG_CONFIG_PATH` / `CMAKE_PREFIX_PATH` 自动汇总。

七个 `features.yaml` 条件特性不仅能拉依赖，还能改构建开关：

| 特性 | 拉入 | 同时追加 |
| --- | --- | --- |
| `libsrtp:openssl` | openssl | `-DENABLE_OPENSSL=ON` |
| `mosquitto:tls` | openssl | `-DWITH_TLS=ON` |
| `srt:tls` | openssl | `-DENABLE_ENCRYPTION=ON` |
| `libcoap:tls` | openssl | `-DENABLE_DTLS=openssl` |
| `portaudio:alsa` | alsa-lib | `-DPA_USE_ALSA=ON` |
| `libdwarf:compression` | zlib, zstd | — |
| `libtomcrypt:ltm` | libtommath | — |

默认图保持精简：`graph libsrtp` 不含 openssl，启用特性后才多一步。

## 适配要点（全部在生成的两文件里）

- `tools/r10-catalog.tsv`（38 行真实 URL/SHA256/kind/deps）+
  `tools/gen-r10-ports.py`；`tests/r10.sh` 会重跑生成器断言逐字节一致。
- **libbsd 换官方 release**：GitHub tag 的 `configure.ac` 用 `git describe`
  取版本号，tag 归档没有 `.git`，`autoreconf` 报 `cannot get project
  version`。改用 `libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz`
  （带生成好的 `configure`）。
- **abseil 换 tag**：`20240722` 404，实际 tag 是 `20240722.0`；
  `ABSL_ENABLE_INSTALL=ON` 才会安装 `abslConfig.cmake` 供 re2 查找。
- **cunit 重新生成**：SourceForge 包里预配置的 automake `Makefile`
  硬编码了原作者的 `/Users/aks/.../missing`，`make` 一定失败；
  `autoreconf -fi && ./configure --prefix=...` 重新生成即可。
- **blake3** 的 C CMake 工程在 `c/` 子目录，用 `cmake.source = "c"`
  指向它；**libtomcrypt** 只有小写 `makefile`，用 `recipe.make` 的
  `vars = function(ctx) return { PREFIX = ctx.prefix } end` 传安装前缀，
  `CC` 由 recipe 自动替换成 `gcpkg-intercept` 包装器（408 条 compdb）。
- **fribidi** 只有 Meson（无 `configure`），选项名必须查
  `meson_options.txt`：`docs=false` / `bin=false` / `tests=false`。
- **catch2 v3** 导出的是 `libCatch2.a` + `libCatch2Main.a`（不是
  `Catch2WithMain`）；`portaudio` 静态目标要关
  `PA_LIBNAME_ADD_SUFFIX` 才叫 `libportaudio.a`。
- **只关测试/文档/示例**：`flatbuffers`、`catch2`、`jsoncpp`、
  `benchmark`、`nlohmann-json` 等若不关会拉 googletest / 生成工具；
  宿主编解码器（`lcms2` 的 jpeg/tiff/zlib）、ALSA/JACK（`portaudio`）、
  OpenSSL 加密（`srt` / `mosquitto` / `libcoap` / `libsrtp`）默认关闭，
  需要时用条件特性打开。
- **源码身份校验**：`net.prepare` 的 marker 现在包含 `url|sha256`（git
  另加 `ref`），同名同版本换源后会自动刷新解包目录，见
  [docs/PROXY.md](PROXY.md) 第 4 节。

## 验证

```bash
./build/bin/gcpkg check --ports ./ports               # 226 ports OK
./build/bin/gcpkg graph re2 --ports ./ports           # abseil -> re2
./build/bin/gcpkg graph libdwarf --feature=libdwarf:compression --ports ./ports
./tests/r10.sh                                        # 静态（默认）
GCPKG_R10_DYNAMIC=1 ./tests/r10.sh                    # 38/38 真编译
./tests/proxy.sh                                      # 代理静态回归
GCPKG_PROXY_DYNAMIC=1 ./tests/proxy.sh                # 代理端到端

```

静态回归还复核了旧轮次没有退化：`graph libsndfile` 仍含 `flac`、
`graph udisks2` 仍含 `liburing`、`versions zlib` 仍有 `1.2.13`、
项目 CLI 与代理 CLI 都在 `--help` 里。

## 本轮排除的候选

`libftdi`（CMake 需要宿主 libusb/Boost 路径）、`libieee1284`
（SourceForge 404）没有写成占位 port；`abseil` 的 `20240722` 与
`libbsd` 的 GitHub tag 是换成可用官方源后才落地的。所有保留的 38 行
SHA256 均为实测，不写 `TODO` / 假值。
