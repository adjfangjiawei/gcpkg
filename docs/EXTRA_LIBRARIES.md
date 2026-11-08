# 更多基础库（第九轮）：43 个新 port

用户一句「继续支持更多的库」，这一轮把注册表从 **145 个扩展到 188 个**，
补的是之前没覆盖的领域：数据格式/序列化、压缩编码、QUIC/网络协议、
音视频基础库、椭圆曲线加密与 C++ 工具库。

与前两轮不同，这一轮 **43 个新 port 全部在干净源码上真编译通过**，没有
「仅静态验证」的遗留项：`GCPKG_EXTRA_DYNAMIC=1 ./tests/extra.sh` 输出
`43 PASS / 0 FAIL, 3056 compile commands`。所有 URL/SHA256 都是真实下载
计算值，构建系统种类是逐个解压 tarball 看顶层文件定的；上游源码一行未改，
适配全在生成的 `build.lua` / `features.yaml` 里。

## 覆盖面

| 主题 | 新增库 |
| --- | --- |
| JSON / 配置 / 序列化 | `yyjson`、`cjson`、`rapidjson`（header-only）、`libcbor`、`inih`（Meson）、`libbase64`、`simdjson`、`libconfig` |
| 压缩 / 编码 | `snappy`、`zlib-ng`（zlib-compat）、`c-blosc`、`lzfse`、`miniz` |
| QUIC / 网络协议 | `nghttp3`、`ngtcp2`、`libssh`、`hiredis`、`libmodbus`、`libdnet`、`libnet`、`libwebsockets`、`librdkafka`、`libzip`、`libmaxminddb` |
| 音视频基础 | `libogg`、`libvorbis`、`opus`、`flac`、`libwebp`、`libsamplerate`、`libsndfile`、`libvpx`、`libtheora`、`giflib` |
| 加密 / C++ 工具 | `libsecp256k1`、`wolfssl`、`fmt`、`spdlog`、`capstone`、`googletest`、`pcre`、`libedit`、`lmdb` |

## 43 个 port 与实测编译命令数

`kind` = 上游 tarball 顶层实际存在的构建系统；`依赖` = 声明的 gcpkg
依赖（全部能在注册表里解析）；最后一列是真编译产出的 compdb 条数。

| port | 版本 | kind | 依赖 | compdb |
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
| `libvpx` | 1.15.0 | custom-make | — | 161 |
| `libtheora` | 1.1.1 | autotools | libogg | 34 |
| `libzip` | 1.11.3 | cmake | zlib | 250 |
| `libmaxminddb` | 1.12.2 | cmake | — | 8 |

合计 **3056 条**（不含已有依赖 `zlib` / `openssl` / `ncurses` 的缓存条目）。

## 依赖图（自底向上）

```
graph libsndfile  ->  libogg → libvorbis → opus → flac → libsndfile   (5 步)
graph spdlog      ->  fmt → spdlog                                     (2 步)
graph libssh      ->  openssl → zlib → libssh
graph libzip      ->  zlib → libzip
graph libvorbis   ->  libogg → libvorbis
graph flac        ->  libogg → flac
graph libtheora   ->  libogg → libtheora
graph libedit     ->  ncurses → libedit
```

`libsndfile` 是本轮最宽的依赖面：一次挂 4 个音视频库，且这 4 个都在本轮
真编译过。第八轮的 `versions:`、`gcpkg new/add` 与第七轮的磁盘信息链
`graph udisks2`（含 `liburing → libnvme`）在第九轮回归里继续校验，没有退化。

## 条件依赖（feature 拉起额外库）

四个 port 在 `features.yaml` 里声明了默认关闭的 `requires:`，启用后依赖图
多出 `openssl`（`tests/extra.sh` 用 `--feature` 逐一验证）：

```bash
gcpkg graph libzip                                  # zlib → libzip
gcpkg graph libzip --feature=libzip:openssl        # zlib → openssl → libzip
gcpkg graph libwebsockets --feature=libwebsockets:tls
gcpkg graph librdkafka --feature=librdkafka:ssl
gcpkg graph ngtcp2 --feature=ngtcp2:tls
```

默认图保持精简；这仍是 `features.yaml` 的声明式能力，没有为某个库改引擎。

## 适配踩过的坑（全部只改 port 的两个文件）

| 现象 | 处理 |
| --- | --- |
| `zlib-ng` 默认编译 gtest 测试程序，链接报 `undefined reference to main` | `ZLIB_ENABLE_TESTS` / `ZLIBNG_ENABLE_TESTS` / `WITH_GTEST` 三个开关都要 `OFF`，只关一个不够 |
| `inih` 的 Meson 报 `Unknown options: "tests"` | 上游 `meson_options.txt` 里没有 `tests`，改用 `default_library=static` + `with_INIReader` |
| `nghttp3` 的 GitHub tag tarball 缺 `lib/sfparse` submodule，CMake 找不到源文件 | 换成官方 release `nghttp3-1.11.0.tar.xz`（实测 SHA256），tag 归档不带 submodule |
| `libtheora` 的 tag tarball 只有 `configure.ac`，`autoreconf` 缺 `AM_PATH_SDL` / `AS_AC_EXPAND` 宏 | 换成 Xiph 官方 release `.tar.xz`（自带 `configure`），再加 `--disable-examples`（`png2theora` 用了现代 libpng 已删除的 `png_sizeof`） |
| `libvpx` 的 `./configure` 要求 yasm/nasm，当时沙箱里没有 | 第九轮用 `--target=generic-gnu` 纯 C 目标；**第十一轮新增 `nasm` 源码工具 port 后已改为 `dependencies={"nasm"}` + `--as=nasm` 的 SIMD 目标**（见 `docs/TOOLCHAINS.md`） |
| `librdkafka` 的 examples 链接宿主静态 `libcurl.a`，缺 GSSAPI 符号 | `--disable-curl --disable-gssapi --disable-sasl` |
| `libconfig` 文档目标要 `makeinfo`（未安装） | `--disable-doc --disable-examples --disable-tests` |
| `giflib` / `lmdb` 是手写 Makefile，`lmdb` 的 Makefile 还在 `libraries/liblmdb/` 子目录 | 自定义 `build(ctx)` 指定 cwd、传 `PREFIX`/`prefix`，并显式 `CC=<wrapper>` 让编译命令进入 compdb（giflib 24 条、lmdb 13 条） |

被剔除的三个候选：`msgpack-c` 的两个 tag 与 release URL 都 404、
`tomlc99` 的 `v0.4.0` tag 404、`utf8cpp` 的 `v4.0.6` tag 404。按前几轮的
惯例不塞占位校验和，换成 `libconfig` / `giflib` / `libzip` 等可匿名下载且
实测通过的真实库。

## 验证

```bash
./build/bin/gcpkg check --ports ./ports              # 当时 188 ports OK，当前 249
./tests/extra.sh                                    # 静态：两文件 / SHA / 图 / 条件依赖 / 生成器幂等
GCPKG_EXTRA_DYNAMIC=1 ./tests/extra.sh              # 干净 store 全量真编译 43 个
```

静态部分还会校验：

- 43 个 port 各有 `build.lua` + `features.yaml`，URL 是 `https://`、
  SHA256 是 64 位十六进制，且不含 `/home/user`、`example.com` 等占位；
- `python3 tools/gen-extra-ports.py` 重跑后内容逐字节一致（catalog +
  generator 是唯一源）；
- `graph libsndfile` 恰好 5 步、`graph spdlog` 2 步、`graph libssh` 含
  openssl+zlib；
- 四个条件 feature 能拉起 openssl，而默认 `graph libzip` 不含 openssl；
- 第八轮 `versions zlib`、第九轮之前的磁盘链与项目 CLI 仍在。

动态部分用全新 store（`~/.cache/gcpkg-extra-test-store`）逐个
`gcpkg install`，统计每个 manifest 的 `compdb_entries`。本轮结果
`43 PASS / 0 FAIL`，累计 3056 条编译命令；这些编译数据库同样可被项目模式
合并，供 clangd 从项目代码跳进新库源码。

> 更新（第十一轮）：`libvpx` 已不再需要纯 C 回退。`nasm` 现在是 gcpkg 的
> 源码工具 port，`libvpx` 声明 `dependencies = {"nasm"}` 并用
> `--target=x86_64-linux-gcc --as=nasm`，构建日志里能看到 `using nasm` 与
> `[AS] ... .asm.o`。此处 161 条 compdb 是第九轮纯 C 目标的历史数值；
> 当前 SIMD 构建为 211 条。`libwebsockets` / `libzip` 默认关闭 TLS 相关选项，
> 启用对应 feature 才会拉起 openssl。

## 文件

- `tools/extra-catalog.tsv`：43 行真实 URL/SHA256/kind/deps（唯一源表）
- `tools/gen-extra-ports.py`：生成 43 套两文件，支持 cmake/meson/autotools
  与自定义 `build(ctx)`、条件 feature
- `tests/extra.sh`：静态 + 全量动态回归
- `docs/EXTRA_LIBRARIES.md`：本文档
