# Port 目录

注册表当前提供 **346 个 port**。每个 port 对应一个真实上游来源，由 `build.lua` 描述构建，由 `features.yaml` 描述特性与可选版本。

```bash
gcpkg ports --ports ./ports
gcpkg check --ports ./ports
gcpkg graph curl --ports ./ports
gcpkg features openssl --ports ./ports
gcpkg versions zlib --ports ./ports
gcpkg install zlib@1.2.13 --ports ./ports
```

`gcpkg ports` 按依赖层级列出 L0（无 gcpkg 依赖）到 L4。`gcpkg graph` 输出自底向上的实际构建顺序；`--feature=PORT:NAME` 可启用条件依赖。port 可接入 CMake、Meson、GN、Autotools、Makefile、Python、Cargo 等构建系统，详见 [BUILD_SYSTEMS.md](BUILD_SYSTEMS.md)。

## 常用库精选

| port | 版本 | 形态 | 说明 |
| --- | --- | --- | --- |
| `asio` | asio-1-34-2 | 头文件库 | Standalone Asio asynchronous I/O C++ library |
| `glm` | 1.0.1 | 头文件库 | OpenGL Mathematics header-only C++ library |
| `tinyobjloader` | v2.0.0rc13 | 头文件库 | Header-only Wavefront OBJ loader |
| `cgltf` | v1.15 | 头文件库 | Single-file glTF 2.0 loader and writer |
| `utfcpp` | v4.0.6 | 头文件库 | UTF-8 with C++ header-only library |
| `span-lite` | v0.11.0 | 头文件库 | C++20 std::span backport for C++11/14/17 |
| `expected-lite` | v0.8.0 | 头文件库 | C++23 std::expected backport |
| `optional-lite` | v3.6.0 | 头文件库 | C++17 std::optional backport |
| `variant-lite` | v2.0.0 | 头文件库 | C++17 std::variant backport |
| `any-lite` | v0.4.0 | 头文件库 | C++17 std::any backport |
| `byte-lite` | v0.3.0 | 头文件库 | C++17 std::byte backport |
| `lyra` | 1.7.0 | 头文件库 | Header-only command-line argument parser |
| `pprint` | v0.9.1 | 头文件库 | Header-only C++ pretty printer |
| `tabulate` | v2.2 | 头文件库 | Header-only C++ table formatting library |
| `indicators` | v2.3 | 头文件库 | Header-only C++ progress bars and indicators |
| `hopscotch-map` | v2.3.1 | 头文件库 | Fast header-only hash map and set |
| `sparsepp` | v0.95 | 头文件库 | Fast header-only sparse hash map |
| `parallel-hashmap` | v1.4.1 | 头文件库 | Header-only concurrent hash maps and btrees |
| `uni-algo` | v1.2.0 | 头文件库 | Header-only Unicode algorithms library |
| `civetweb` | v1.16 | CMake 静态库 | Embeddable C/C++ web server library |
| `nng` | v1.8.0 | CMake 静态库 | Lightweight messaging and scalability protocols library |
| `meshoptimizer` | v0.22 | CMake 静态库 | Mesh optimization and simplification library |
| `ftxui` | v5.0.0 | CMake 静态库 | C++ functional terminal UI library |
| `bzip3` | 1.4.0 | CMake 静态库 | High-ratio bzip3 compression library |

## 特性与版本

`features.yaml` 可包含：

| 字段 | 作用 |
| --- | --- |
| `features.<name>.args` | 追加到上游构建参数 |
| `features.<name>.requires` | 按特性引入条件依赖 |
| `features.<name>.conflicts` | 阻止互斥特性 |
| `features.<name>.defines` / `env` | 向构建上下文注入宏与环境变量 |
| `versions.<version>.source` | 声明可选源码 URL 与 SHA256 |
| `versions.<version>.dependencies` | 覆盖该版本的依赖 |

示例：

```bash
gcpkg graph openssl --ports ./ports --feature=openssl:zlib
gcpkg install zlib@1.2.13 --ports ./ports
gcpkg versions zlib --ports ./ports
```

## 外部 SDK 与系统组件

少数库需要登录或专有 SDK。`gcpkg externals` 列出这些 port 和对应环境变量；在本机设置变量后再安装即可。`llvm` 也是外部 SDK port：它接入官方二进制 LLVM/Clang，不从源码编译；Linux/WSL 可用 `gcpkg llvm install 23`（内部调用 `wget https://apt.llvm.org/llvm.sh`），再用 `gcpkg llvm use DIR` 选择安装目录。系统 `-dev` 组件通过 `pkgconfig` backend 接入，不走源码下载。

## R20：源码构建的多媒体 / 图形 / 系统库

| port | 版本 | 形态 | 说明 |
| --- | --- | --- | --- |
| `qt` | 6.12.0 | CMake 静态库 | qtbase QtCore；第三方库全部使用上游内置源码 |
| `opencv` | 5.1.0 | CMake 静态库 | core/imgproc/imgcodecs；内置源码编译图像编解码 |
| `ffmpeg` | 9.0.2 | Makefile 静态库 | 内置全量 codecs + x264/x265/LAME/libass 源码 port |
| `sdl3` | 3.4.20 | CMake 静态库 | Wayland/ALSA/udev/DBus 源码 port；关闭 X11/EGL/Vulkan 等 |
| `glib` | 2.90.1 | Meson 静态库 | 保留现有 port 并原地升级，依赖 libffi/zlib/pcre2 与源码 Meson |
| `dlib` | 20.0.1 | CMake 静态库 | JPEG/PNG/zlib 源码 port；关闭 GUI/CUDA/BLAS |
| `opencl-headers` | 2026.05.29 | 头文件库 | Khronos OpenCL Headers，供 `opencl` 使用 |
| `opencl` | 2026.05.29 | CMake 静态库 | Khronos OpenCL ICD Loader |
| `openal` | 1.25.2 | CMake 静态库 | OpenAL Soft；SDL3/ALSA 后端使用源码 port |
| `openvr` | 2.15.6 | CMake 静态库 | ValveSoftware/openvr；`opengr` 为打错，未实现 OpenGR |
| `meson` | 1.12.1 | 工具 port | 源码 Meson 1.12.1；所有 Meson port 通过它构建，不调用系统 meson |
| `x264` | snapshot-0480cb05 | Makefile 静态库 | FFmpeg 的源码 H.264 编码依赖 |
| `x265` | 3.4 | CMake 静态库 | FFmpeg 的源码 HEVC 编码依赖 |
| `lame` | 3.100 | Autotools 静态库 | FFmpeg 的源码 MP3 编码依赖 |
| `libass` | 0.17.5 | Meson 静态库 | FFmpeg 的源码字幕渲染依赖 |
| `libdecor` | 0.2.5 | Meson 静态库 | Wayland 装饰库，依赖源码 wayland ports |
| `eudev` | 3.3.0 | Autotools 静态库 | libudev 源码 port，可选系统特性关闭 |

本批所有编译型 port 都在 `share/doc/<port>` 安装许可证；系统级依赖由 gcpkg port 源码构建，Meson 1.12.1 也由源码工具 port 提供，不调用 apt、系统 meson 或 `pkgconfig` backend 的系统 `-dev` 包。

## 完整目录

<details>
<summary>展开全部 346 个 port</summary>

### L0

| port | 版本 | 直接依赖 |
| --- | --- | --- |
| `abseil` | 20240722.0 | — |
| `ada` | 2.9.2 | — |
| `alsa-lib` | 1.2.9 | — |
| `any-lite` | v0.4.0 | — |
| `apr` | 1.7.5 | — |
| `argh` | 1.3.2 | — |
| `argparse` | 3.2 | — |
| `args` | 6.6.1 | — |
| `asio` | asio-1-34-2 | — |
| `benchmark` | 1.9.1 | — |
| `bitsery` | 5.2.5 | — |
| `blake3` | 1.8.2 | — |
| `brotli` | 1.1.0 | — |
| `byte-lite` | v0.3.0 | — |
| `bzip2` | 1.0.8 | — |
| `bzip3` | 1.4.0 | — |
| `c-blosc` | 1.21.6 | — |
| `cann` | 9.0.0 | — |
| `capnproto` | 1.1.0 | — |
| `capstone` | 5.0.3 | — |
| `cares` | 1.34.5 | — |
| `catch2` | 3.7.1 | — |
| `cereal` | 1.3.2 | — |
| `cgltf` | v1.15 | — |
| `check` | 0.15.2 | — |
| `cista` | 0.16 | — |
| `civetweb` | v1.16 | — |
| `cjson` | 1.7.18 | — |
| `cli11` | 2.4.2 | — |
| `clipp` | 1.2.3 | — |
| `cmake` | 3.31.6 | — |
| `cmocka` | 1.1.7 | — |
| `concurrentqueue` | 1.0.4 | — |
| `cpp-httplib` | 0.20.1 | — |
| `cpp-sort` | 1.17.0 | — |
| `csv2` | 0.2 | — |
| `cunit` | 2.1-3 | — |
| `cxxopts` | 3.2.0 | — |
| `dahuaplayer` | 3.044.0000000.1 | — |
| `date` | 3.0.3 | — |
| `dmidecode` | 3.6 | — |
| `docopt` | 0.6.3 | — |
| `doctest` | 2.4.11 | — |
| `double-conversion` | 3.3.0 | — |
| `eigen` | 3.4.0 | — |
| `eudev` | 3.3.0 | — |
| `expat` | 2.7.1 | — |
| `expected-lite` | v0.8.0 | — |
| `fftw` | 3.3.10 | — |
| `file` | 5.46 | — |
| `flatbuffers` | 24.3.25 | — |
| `fmt` | 11.2.0 | — |
| `fontutil` | 1.4.2 | — |
| `fribidi` | 1.0.15 | — |
| `ftxui` | v5.0.0 | — |
| `gflags` | 2.2.2 | — |
| `giflib` | 5.2.2 | — |
| `glaze` | 9.1.0 | — |
| `glm` | 1.0.1 | — |
| `gmp` | 6.3.0 | — |
| `googletest` | 1.15.2 | — |
| `gsl` | 2.8 | — |
| `hana` | 1.7.0 | — |
| `hdparm` | 9.65 | — |
| `highway` | 1.2.0 | — |
| `hiredis` | 1.2.0 | — |
| `hopscotch-map` | v2.3.1 | — |
| `i2c-tools` | 4.4 | — |
| `immer` | 0.9.1 | — |
| `indicators` | v2.3 | — |
| `inih` | r58 | — |
| `jansson` | 2.15.1 | — |
| `jemalloc` | 5.3.0 | — |
| `json-c` | 0.18 | — |
| `jsoncons` | 1.10.0 | — |
| `jsoncpp` | 1.9.6 | — |
| `keyutils` | 1.6.3 | — |
| `kmod` | 34.2 | — |
| `lame` | 3.100 | — |
| `lcms2` | 2.16 | — |
| `leveldb` | 1.23 | — |
| `libaio` | 0.3.113 | — |
| `libatasmart` | 0.19 | — |
| `libatomic-ops` | 7.8.2 | — |
| `libattr` | 2.5.2 | — |
| `libaudit` | 3.1.5 | — |
| `libbase64` | 0.5.2 | — |
| `libcap` | 2.76 | — |
| `libcap-ng` | 0.8.4 | — |
| `libcbor` | 0.11.0 | — |
| `libcoap` | 4.3.5 | — |
| `libconfig` | 1.7.3 | — |
| `libconfuse` | 3.4 | — |
| `libdaemon` | 0.14 | — |
| `libdeflate` | 1.26 | — |
| `libdnet` | 1.12 | — |
| `libdwarf` | 0.11.1 | — |
| `libebur128` | 1.2.6 | — |
| `libeconf` | 0.7.5 | — |
| `libev` | 4.33 | — |
| `libevdev` | 1.13.4 | — |
| `libexif` | 0.6.24 | — |
| `libffi` | 3.4.8 | — |
| `libfuse` | 3.18.3 | — |
| `libgpg-error` | 1.55 | — |
| `libgpiod` | 2.3.2 | — |
| `libidn` | 1.42 | — |
| `libjpeg-turbo` | 3.2.1 | — |
| `libmaxminddb` | 1.12.2 | — |
| `libmd` | 1.1.0 | — |
| `libmnl` | 1.0.5 | — |
| `libmodbus` | 3.1.11 | — |
| `libnet` | 1.3 | — |
| `libnfnetlink` | 1.0.2 | — |
| `libnl` | 3.11.0 | — |
| `libnuma` | 2.0.19 | — |
| `libogg` | 1.3.5 | — |
| `libpcap` | 1.10.5 | — |
| `libpsl` | 0.21.0 | — |
| `librtsp` | 1.0.0 | — |
| `libsamplerate` | 0.2.2 | — |
| `libseccomp` | 2.6.0 | — |
| `libsecp256k1` | 0.6.0 | — |
| `libserialport` | 0.1.2 | — |
| `libsodium` | 1.0.20 | — |
| `libsrtp` | 2.6.0 | — |
| `libtasn1` | 4.20.0 | — |
| `libtomcrypt` | 1.18.2 | — |
| `libtommath` | 1.3.0 | — |
| `libtraceevent` | 1.8.4 | — |
| `libunibreak` | 5.1 | — |
| `libunistring` | 1.3 | — |
| `liburing` | 2.9 | — |
| `libusb` | 1.0.30 | — |
| `libuv` | 1.53.0 | — |
| `libwebp` | 1.5.0 | — |
| `libxkbcommon` | 1.7.0 | — |
| `libyaml` | 0.2.5 | — |
| `live555` | 2021.11.14 | — |
| `llvm` | system | — |
| `lm-sensors` | 3.6.0 | — |
| `lmdb` | 0.9.31 | — |
| `lua` | 5.4.7 | — |
| `lyra` | 1.7.0 | — |
| `lz4` | 1.10.0 | — |
| `lzfse` | 1.0 | — |
| `lzo` | 2.10 | — |
| `maddy` | 1.6.0 | — |
| `magic-enum` | 0.9.7 | — |
| `mbedtls` | 3.6.7 | — |
| `mdadm` | 4.4 | — |
| `meshoptimizer` | v0.22 | — |
| `mimalloc` | 2.1.2 | — |
| `miniz` | 3.0.2 | — |
| `mongoose` | 7.15 | — |
| `mosquitto` | 2.0.20 | — |
| `mp11` | 1.92.0 | — |
| `ms-gsl` | 4.2.0 | — |
| `msgpack` | 6.0.1 | — |
| `nameof` | 0.11.0 | — |
| `nasm` | 2.16.03 | — |
| `ncurses` | 6.5 | — |
| `nghttp3` | 1.11.0 | — |
| `ngtcp2` | 1.16.0 | — |
| `ninja` | 1.12.1 | — |
| `nlohmann-json` | 3.11.3 | — |
| `nng` | v1.8.0 | — |
| `nvidia` | 12.8 | — |
| `onetbb` | 2022.0.0 | — |
| `oniguruma` | 6.9.10 | — |
| `opencl-headers` | 2026.05.29 | — |
| `opencv` | 5.1.0 | — |
| `openjpeg` | 2.5.3 | — |
| `openssl` | 3.4.1 | — |
| `openvr` | 2.15.6 | — |
| `optional-lite` | v3.6.0 | — |
| `opus` | 1.5.2 | — |
| `ordered-map` | 1.2.0 | — |
| `parallel-hashmap` | v1.4.1 | — |
| `pcre` | 8.45 | — |
| `pcre2` | 10.45 | — |
| `pfr` | 1.92.0 | — |
| `pixman` | 0.44.2 | — |
| `plog` | 1.1.10 | — |
| `popt` | 1.19 | — |
| `portaudio` | 19.7.0 | — |
| `pprint` | v0.9.1 | — |
| `pugixml` | 1.14 | — |
| `python` | 3.12.8 | — |
| `qt` | 6.12.0 | — |
| `quill` | 13.1.0 | — |
| `range-v3` | 0.12.0 | — |
| `rapidjson` | 1.1.0 | — |
| `readerwriterqueue` | 1.0.6 | — |
| `robin-hood-hashing` | 3.11.5 | — |
| `robin-map` | 1.3.0 | — |
| `rpcsvc-proto` | 1.4.4 | — |
| `rust` | stable | — |
| `sentencepiece` | 0.2.0 | — |
| `sg3_utils` | 1.48 | — |
| `simde` | 0.8.2 | — |
| `simdjson` | 3.10.0 | — |
| `simdutf` | 5.6.3 | — |
| `smartmontools` | 7.4 | — |
| `snappy` | 1.2.2 | — |
| `span-lite` | v0.11.0 | — |
| `sparse-map` | 0.7.0 | — |
| `sparsepp` | v0.95 | — |
| `spirv-headers` | vulkan-sdk-1.4.363.0 | — |
| `sqlite3` | 3.46.1 | — |
| `srt` | 1.5.4 | — |
| `stb` | 4e9b368 | — |
| `systemd` | 257.7 | — |
| `tabulate` | v2.2 | — |
| `taglib` | 2.0.2 | — |
| `taskflow` | 3.10.0 | — |
| `termcolor` | 2.1.0 | — |
| `tinyobjloader` | v2.0.0rc13 | — |
| `tinyxml2` | 10.0.0 | — |
| `toml11` | 4.2.0 | — |
| `tomlplusplus` | 3.4.0 | — |
| `ucx` | 1.23.2 | — |
| `uni-algo` | v1.2.0 | — |
| `unity` | 2.6.0 | — |
| `unordered-dense` | 4.8.0 | — |
| `ut` | 2.3.1 | — |
| `utf8proc` | 2.12.0 | — |
| `utfcpp` | v4.0.6 | — |
| `uthash` | 2.3.0 | — |
| `util-linux` | 2.41 | — |
| `variant-lite` | v2.0.0 | — |
| `vulkan-headers` | 1.4.363.0 | — |
| `wolfssl` | 5.7.6 | — |
| `x264` | snapshot-0480cb05 | — |
| `x265` | 3.4 | — |
| `xcb-proto` | 1.17.0 | — |
| `xorgproto` | 2024.1 | — |
| `xsimd` | 13.0.0 | — |
| `xxhash` | 0.8.4 | — |
| `xz` | 5.8.1 | — |
| `yaml-cpp` | 0.8.0 | — |
| `yyjson` | 0.10.0 | — |
| `zlib` | 1.3.1 | — |
| `zlib-ng` | 2.2.4 | — |
| `zopfli` | 1.0.3 | — |
| `zstd` | 1.5.7 | — |

### L1

| port | 版本 | 直接依赖 |
| --- | --- | --- |
| `btrfs-progs` | 6.19.1 | `util-linux`, `zlib`, `zstd`, `lz4` |
| `cv-cuda` | 0.19.0 | `nvidia` |
| `dbus` | 1.16.2 | `expat` |
| `dcgm` | 4.7.0 | `nvidia` |
| `describe` | 1.92.0 | `mp11` |
| `e2fsprogs` | 1.47.4 | `util-linux` |
| `elfutils` | 0.192 | `zlib`, `zstd`, `xz` |
| `flac` | 1.4.3 | `libogg` |
| `folly` | 2026.10.26.00 | `cmake`, `openssl`, `zlib`, `zstd`, `lz4`, `bzip2` |
| `glog` | 0.7.1 | `gflags` |
| `gn` | 2026.02-3dff66e | `ninja` |
| `hidapi` | 0.15.0 | `libusb` |
| `inja` | 3.5.0 | `nlohmann-json` |
| `ipvsadm` | 1.31 | `libnl`, `popt` |
| `libXau` | 1.0.12 | `xorgproto` |
| `libXdmcp` | 1.1.5 | `xorgproto` |
| `libacl` | 2.3.2 | `libattr` |
| `libarchive` | 3.7.9 | `zlib`, `bzip2`, `xz`, `zstd`, `lz4`, `openssl`, `expat`, `pcre2` |
| `libbsd` | 0.12.2 | `libmd` |
| `libedit` | 3.1 | `ncurses` |
| `libevent` | 2.1.13 | `openssl` |
| `libgcrypt` | 1.11.1 | `libgpg-error` |
| `libgit2` | 1.9.1 | `zlib` |
| `libidn2` | 2.3.8 | `libunistring` |
| `libnetfilter_conntrack` | 1.0.9 | `libnfnetlink`, `libmnl` |
| `libnftnl` | 1.2.8 | `libmnl` |
| `libnvme` | 1.16.2 | `liburing` |
| `libparted` | 3.6 | `util-linux` |
| `libpciaccess` | 0.18.1 | `zlib` |
| `libpng` | 1.6.59 | `zlib` |
| `librdkafka` | 2.8.0 | `zlib` |
| `libselinux` | 3.8 | `pcre2`, `libseccomp` |
| `libssh` | 0.11.1 | `openssl`, `zlib` |
| `libssh2` | 1.11.1 | `openssl`, `zlib` |
| `libtheora` | 1.1.1 | `libogg` |
| `libtiff` | 4.7.0 | `zlib`, `xz`, `zstd`, `libjpeg-turbo` |
| `libtirpc` | 1.3.6 | `rpcsvc-proto` |
| `libtracefs` | 1.8.2 | `libtraceevent` |
| `libunwind` | 1.8.3 | `zlib`, `xz` |
| `libvorbis` | 1.3.7 | `libogg` |
| `libvpx` | 1.15.0 | `nasm` |
| `libwebsockets` | 4.3.3 | `zlib` |
| `libxml2` | 2.14.5 | `zlib`, `xz` |
| `libzip` | 1.11.3 | `zlib` |
| `lvm2` | 2.03.43 | `util-linux`, `libaio` |
| `meson` | 1.12.1 | `python`, `ninja` |
| `minizip-ng` | 4.2.2 | `zlib` |
| `mpfr` | 4.2.2 | `gmp` |
| `nettle` | 3.10 | `gmp` |
| `nghttp2` | 1.65.0 | `zlib` |
| `nv-codec-sdk` | 12.2 | `nvidia` |
| `opencl` | 2026.05.29 | `opencl-headers` |
| `pciutils` | 3.15.0 | `zlib` |
| `pybind11` | 2.13.6 | `python` |
| `re2` | 2024-07-02 | `abseil` |
| `readline` | 8.2.13 | `ncurses` |
| `redpanda` | 26.2.2 | `cmake` |
| `ryu` | 1.0.18 | `rust` |
| `sol2` | 3.5.0 | `lua` |
| `spdlog` | 1.15.3 | `fmt` |
| `tokenizers-cpp` | main-c586c52 | `rust` |
| `toml` | 0.10.2 | `python` |
| `vulkan` | 1.4.363.0 | `vulkan-headers`, `cmake` |
| `wayland` | 1.23.1 | `libffi`, `expat` |
| `xfsprogs` | 6.12.0 | `util-linux`, `libattr` |

### L2

| port | 版本 | 直接依赖 |
| --- | --- | --- |
| `crashpad` | main-f3769d9 | `gn` |
| `curl` | 8.13.0 | `openssl`, `zlib`, `brotli`, `zstd`, `cares`, `nghttp2`, `libssh2` |
| `dlib` | 20.0.1 | `zlib`, `libjpeg-turbo`, `libpng` |
| `fizz` | 2026.10.26.00 | `folly`, `openssl`, `cmake` |
| `freetype` | 2.13.3 | `zlib`, `bzip2`, `libpng`, `brotli` |
| `glib` | 2.90.1 | `meson`, `libffi`, `zlib`, `pcre2` |
| `gnutls` | 3.8.9 | `nettle`, `gmp`, `libtasn1`, `libidn2`, `libunistring`, `zlib` |
| `iptables` | 1.8.11 | `libmnl`, `libnftnl` |
| `libbpf` | 1.8.0 | `elfutils`, `zlib` |
| `libdrm` | 2.4.124 | `libpciaccess` |
| `libiio` | 0.26 | `libusb`, `libxml2` |
| `libsndfile` | 1.2.2 | `libogg`, `libvorbis`, `opus`, `flac` |
| `libxcb` | 1.17.0 | `xorgproto`, `xcb-proto`, `libXau`, `libXdmcp` |
| `libxslt` | 1.1.43 | `libxml2` |
| `mpc` | 1.3.1 | `gmp`, `mpfr` |
| `nv-image-codec` | 0.10.0 | `nvidia`, `cv-cuda` |
| `nvme-cli` | 2.16 | `libnvme` |
| `wayland-protocols` | 1.45 | `wayland` |

### L3

| port | 版本 | 直接依赖 |
| --- | --- | --- |
| `fontconfig` | 2.16.0 | `freetype`, `expat` |
| `harfbuzz` | 15.1.0 | `freetype`, `glib` |
| `libX11` | 1.8.12 | `xorgproto`, `libxcb` |
| `libdecor` | 0.2.5 | `meson`, `wayland`, `wayland-protocols` |
| `libgudev` | 238 | `glib` |
| `libinput` | 1.28.1 | `libevdev`, `wayland`, `wayland-protocols` |
| `libmicrohttpd` | 1.0.1 | `gnutls`, `libgcrypt` |
| `libstoragemgmt` | 1.11.0 | `glib`, `libnvme` |
| `mvfst` | 2026.10.26.00 | `folly`, `fizz`, `cmake` |
| `wangle` | 2026.10.26.00 | `folly`, `fizz`, `cmake` |

### L4

| port | 版本 | 直接依赖 |
| --- | --- | --- |
| `libass` | 0.17.5 | `meson`, `freetype`, `fribidi`, `harfbuzz`, `fontconfig`, `expat`, `bzip2`, `brotli`, `libpng`, `zlib` |
| `proxygen` | 2026.10.26.00 | `folly`, `fizz`, `wangle`, `mvfst`, `cmake` |
| `sdl3` | 3.4.20 | `alsa-lib`, `eudev`, `libdecor`, `libxkbcommon`, `wayland`, `wayland-protocols`, `dbus` |
| `udisks2` | 2.11.2 | `glib`, `dbus`, `libgudev`, `libatasmart`, `libnvme`, `libparted`, `util-linux`, `libacl` |
| `xserver` | 21.1.16 | `xorgproto`, `libX11`, `libxcb`, `libXau`, `libXdmcp`, `pixman`, `libdrm`, `libpciaccess`, `dbus`, `openssl`, `libxkbcommon`, `fontutil` |

### L5

| port | 版本 | 直接依赖 |
| --- | --- | --- |
| `ffmpeg` | 9.0.2 | `x264`, `x265`, `lame`, `libass`, `zlib` |
| `openal` | 1.25.2 | `sdl3`, `alsa-lib` |

</details>

纯源码构建下，`libdecor` 只在存在对应源码 port 时启用 Cairo/Pango 装饰插件，并安装源码构建的 dummy plugin；不链接系统 Cairo/Pango `-dev` 包。

SDL3 的 Wayland 后端使用源码 Wayland/libdecor/libxkbcommon ports；源码内将上游 `egl` pkg-config 检查替换为已有的 `wayland-egl`，不依赖系统 EGL `-dev` 包。
