# gcpkg

一个**元包管理器**：用 Lua 描述「怎么构建一个库」，用 YAML 描述「这个库有哪些特性」，把任意构建系统、乃至其它包管理器（vcpkg / conan / pkg-config / apt / …）接进来，**不改它们本身**，并且让项目自身也能被它管理、生成可跨依赖跳转的 clangd 编译数据库。

> 当前分支 `feat/lua-yaml-compdb-openssl`：Lua 引擎 + YAML 特性 + 项目模式 + 统一编译数据库 + **277 个真实 port**（L0 → L4，含工具链 port）。按依赖层次自底向上扩展：`openssl` 起步，L0 十个基础库，再到 `libssh2` / `nghttp2` / `curl` 全链与 `libarchive`（一次挂 8 个 L0 依赖）。第四轮继续覆盖 Linux 底层库栈：NUMA / 权限与沙箱 / netfilter / X11 / **Xserver** / **Wayland** / libinput / D-Bus / kmod / util-linux / **systemd** / ipvs / iptables —— 36 个新 port 全部真实编译（6718 条编译命令），`xserver` 依赖图 16 步、`systemd` 单包 3272 条。特性开关也能引入真实的传递依赖（`openssl:zlib` → 先构建 `zlib`）。第五轮再覆盖 CMake / Lua / ALSA / libpsl / libfuse / live555 / librtsp / UCX / Vulkan / folly / proxygen / Redpanda 以及 NVIDIA（CUDA、DCGM、Video Codec SDK、nvImageCodec、CV-CUDA）、华为 CANN、大华播放库 —— 共 23 个新 port；其中 4 个需登录或专有的 SDK 做成 `gcpkg.build.external` 声明式 port，`gcpkg externals` 静态列出所需环境变量，你在本地设好即可真构建。第六轮继续补 Linux 基础库：GNU 数值/加密栈（GMP → GnuTLS）、终端/数据（ncurses → readline、SQLite、Jansson）、图像字体（libpng → freetype → fontconfig / HarfBuzz）与内核接口（libattr → libacl、elfutils → libbpf），共 37 个新 port，其中 14 个在这里真编译出 884 条编译命令。第七轮专攻**内核接口与磁盘/存储信息查询**（NVMe/SMART/分区/文件系统/RAID/DMI/PCI、ftrace、keyring、GPIO、IIO 等），新增 34 个 port；`liburing` 早就在栈里，这一轮重新从干净源码复核（14 条 compdb）并让它成为 `libnvme → udisks2` 磁盘信息链的一环，另有 21 个新 port 真编译（合计 1061 条）。第八轮补上 pnpm 式项目工作流：
`gcpkg new` / `add` / `remove` / `list` / `versions` / `install`（无参），
区分**项目私有 port / 用户级 / 公有 registry** 三种作用域与**项目特有 / 公有**
两种依赖清单，并让不同项目锁定同库的不同版本（`zlib@1.2.13` 与
`zlib@1.3.1` 同时真编译，`gcpkg.lock` 各记各的），详见
[docs/PROJECTS.md](docs/PROJECTS.md)。第九轮再补 43 个此前未覆盖的基础库
（JSON/CBOR/配置、压缩、QUIC/网络协议、音视频、椭圆曲线与 C++ 工具），
**43 个全部在干净源码上真编译通过**、合计 3056 条编译命令，详见
[docs/EXTRA_LIBRARIES.md](docs/EXTRA_LIBRARIES.md)。第十轮继续扩库并实现
**可设置代理**：新增 38 个库（C++ 数据格式 / 测试框架 / 加密哈希 / 图像音频 /
系统事件 / 调试信息），226 个 port 里 **38 个全部干净源码真编译通过**
（2498 条编译命令），详见
[docs/ROUND10_LIBRARIES.md](docs/ROUND10_LIBRARIES.md)。代理是一处解析、
全局下发：`gcpkg proxy [URL|--unset]` 支持项目特有 / 用户级公有两层配置，
`--proxy` / `--no-proxy` 单次覆盖，凭据不进命令行和日志，curl、git clone
与所有构建钩子都继承同一份配置，详见 [docs/PROXY.md](docs/PROXY.md)。
第十一轮把**工具链本身**也做成 port：`nasm` / `python` 是源码工具 port，
`rust` 是 `gcpkg.build.external` 声明式工具 port；新增 `recipe.python` /
`recipe.cargo` 两个 Lua adapter，以及用户所说的「tokenize-cpp」即
`mlc-ai/tokenizers-cpp`（Rust → C → C++ 绑定，3 个 pinned tarball、
端到端静态链接执行通过），另有 17 个常见 C/C++ 库。`libvpx` 现在真的
经 `nasm` 编 SIMD（不再用纯 C 回退），注册表 226 → **249**。详见
[docs/TOOLCHAINS.md](docs/TOOLCHAINS.md) 与
[docs/ROUND11_LIBRARIES.md](docs/ROUND11_LIBRARIES.md)。
第十二轮支持 **GN 构建系统**：`ninja` / `gn` 为源码工具 port，新增
`recipe.gn` + `gcpkg.build.gn` adapter，把 `gn gen --export-compile-commands`
与 `ninja` 产出的原生 compdb 并入统一数据库；`crashpad` 是首个真实 GN
库（`ninja → gn → crashpad`）。另补 25 个常见 C/C++ 库（含 `libgit2` 真
依赖 `zlib`、`taglib:zlib` 条件依赖），注册表 249 → **277**。详见
[docs/GN.md](docs/GN.md) 与
[docs/ROUND12_LIBRARIES.md](docs/ROUND12_LIBRARIES.md)。
第十三轮把 gcpkg 定位成**外层多项目 / 多仓库维护器**：`workspace.yaml` /
`workspace.lock` 管 Git clone/fetch/checkout、递归 submodule、固定 commit、
跨项目依赖树与拓扑构建顺序；项目内部继续保留 CMake、GN、Meson、`canon`
包管理器、Makefile / Ninja。依赖注入类似 vcpkg，生成 CMake toolchain/cache、
Meson native、GN `.gni`、Makefile flags、pkg-config、env、`canon` 清单与统一
compdb，不改写上游源码。`canon` 保持用户原词，四问 skipped 不当作批准。
干净 local-Git 动态回归 **6/6 仓库构建、16 条 compile commands**，详见
[docs/MANAGED_WORKSPACES.md](docs/MANAGED_WORKSPACES.md)、
[docs/DEPENDENCY_INJECTION.md](docs/DEPENDENCY_INJECTION.md)、
[docs/CANON.md](docs/CANON.md) 与
[docs/ROUND13_MANAGED_WORKSPACES.md](docs/ROUND13_MANAGED_WORKSPACES.md)。

## 三个核心要求如何落地

| 要求 | 实现 |
| --- | --- |
| 一个库 = 一个 Lua 构建配置 + 一个 YAML 特性配置 | `ports/<name>/build.lua`（声明 source、依赖、build 钩子；可 `require("gcpkg.build.cmake")` 获得 cmake 构建函数，也可 `gcpkg.import("其它库")` 复用其配置）和 `ports/<name>/features.yaml`（args / env / defines / requires / conflicts / provides）。YAML 改构建参数，Lua 完全不用动。 |
| 直接管理项目 + 跨依赖跳转 | 项目目录里写 `gcpkg.lua` + `gcpkg.yaml`，或只写 `gcpkg.yaml` 让 gcpkg 驱动内层系统；`gcpkg build .` 生成项目根 `compile_commands.json`（项目 + 所有传递依赖）和 `.clangd`。依赖源码目录长期保留在 store 中，路径稳定，所以 clangd 能一路跳转进依赖的头文件和源文件，再跳回来。 |
| 能管理几乎所有库 | C++ 运行时只提供 进程执行 / 文件 / YAML / Lua 沙箱；构建逻辑全是 Lua 模块（`cmake` / `make` / `autotools` / `meson` / `cargo` / `cc` / `auto`），加新构建系统 = 加一个 Lua 文件；接外部包管理器 = 注册一个 adapter（已内置 `pkgconfig`、`vcpkg`、`system`、`call`）。编译器拦截层（`gcpkg-intercept`）让上游构建系统一行不改也能产出编译数据库。 |

## 快速开始

```bash
# 依赖：CMake >= 3.28、C++20 编译器、Lua 5.4 开发库、yaml-cpp、pkg-config
# Linux 底层库栈另需 meson/ninja、autopoint、bison/flex/gperf/xsltproc 与若干系统 -dev 包，
# 完整清单见 /home/user/setup-gcpkg-toolchain.sh 与 docs/EXTENDING.md 第 6 节。
cmake -S . -B build
cmake --build build -j
./build/bin/gcpkg doctor

# 构建示例项目（会自动下载并编译 OpenSSL，然后编译项目，生成编译数据库）
./build/bin/gcpkg build examples/hello --store ~/.cache/gcpkg-store --ports ./ports
./examples/hello/.gcpkg/build/hello-gcpkg
python3 -c "import json;d=json.load(open('examples/hello/compile_commands.json'));print(len(d),'compile commands')"

# 自底向上构建整条 curl 依赖链（8 个包）+ 顶层项目
./build/bin/gcpkg graph curl --ports ./ports
./build/bin/gcpkg ports --ports ./ports
./tests/chain.sh

# 特性条件依赖：openssl:zlib 会先构建 zlib，再让 OpenSSL 用上它
./build/bin/gcpkg graph openssl --ports ./ports --feature=openssl:zlib
./tests/features.sh

# 最宽的 L1 库：libarchive 一次挂 8 个 L0 依赖
./build/bin/gcpkg install libarchive --store ~/.cache/gcpkg-archive --ports ./ports
./tests/smoke.sh

# Linux 底层库栈：X11 / Xserver / Wayland / systemd / NUMA / netfilter / IPVS
./build/bin/gcpkg ports --ports ./ports
./build/bin/gcpkg graph xserver --ports ./ports        # 16 步，自底向上
./build/bin/gcpkg install xserver --store ~/.cache/gcpkg-linux-store --ports ./ports -j 4
./build/bin/gcpkg install systemd --store ~/.cache/gcpkg-linux-store --ports ./ports -j 4
./tests/linux.sh                                     # 校验 36 个 port / compdb / clangd

# 第五轮：媒体 / AI / 网络 / 厂商 SDK（默认只做静态验证）
./build/bin/gcpkg externals --ports ./ports        # 列出 4 个外部 SDK 及环境变量
./build/bin/gcpkg graph proxygen --ports ./ports   # 11 步自底向上
./tests/media.sh                                  # 静态：注册表 / 图 / SHA / 依赖，不下载不编译
GCPKG_MEDIA_DYNAMIC=1 ./tests/media.sh           # 可选：lua 真编译 + SDK adapter 冒烟
GCPKG_NVIDIA_HOME=/usr/local/cuda ./build/bin/gcpkg install nvidia --store ~/.cache/gcpkg-media-store --ports ./ports

# 第六轮：更多 Linux 基础库（默认静态验证）
./build/bin/gcpkg graph gnutls --ports ./ports      # 7 步：gmp -> nettle -> ... -> gnutls
./build/bin/gcpkg graph libbpf --ports ./ports      # 5 步：zlib/zstd/xz -> elfutils -> libbpf
./tests/linux-base.sh                              # 静态：37 个 port / SHA / 依赖 / 图
GCPKG_BASE_DYNAMIC=1 ./tests/linux-base.sh         # 真编译 14 个代表性库（884 条 compdb）

# 第七轮：内核接口 / 磁盘信息查询（详见 docs/DISK_INFO.md）
./build/bin/gcpkg graph udisks2 --ports ./ports     # 15 步，含 liburing -> libnvme
./build/bin/gcpkg graph nvme-cli --ports ./ports    # 3 步
./tests/linux-kernel.sh                            # 静态验证（34 个 port）
GCPKG_KERNEL_DYNAMIC=1 ./tests/linux-kernel.sh     # 真编译 22 个（含 liburing 复核）
./build/bin/gcpkg build examples/diskinfo --store ~/.cache/gcpkg-linux-store --ports ./ports
#   -> 合并 240 条编译命令，clangd 可从项目跳进 libnvme/libatasmart/pciutils/liburing
# 详见 docs/DISK_INFO.md

# 第八轮：pnpm 式项目工作流（详见 docs/PROJECTS.md）
./build/bin/gcpkg new apps/demo --name=demo            # 一键脚手架
./build/bin/gcpkg add zlib@1.2.13 -C apps/demo        # 项目特有依赖 + 指定版本
./build/bin/gcpkg add --local mylib -C apps/demo      # 项目私有 port
./build/bin/gcpkg versions zlib                       # 4 个真实 URL/SHA 的版本
./build/bin/gcpkg list -C apps/demo                   # 作用域 / 版本 / lock
./build/bin/gcpkg build apps/demo --store ~/.cache/gcpkg-store --ports ./ports
./tests/projects.sh                                    # 静态回归
GCPKG_PROJECT_DYNAMIC=1 ./tests/projects.sh           # 两个项目各编译不同 zlib

# 第九轮：43 个新库（详见 docs/EXTRA_LIBRARIES.md）
./build/bin/gcpkg check --ports ./ports               # 277 ports OK
./build/bin/gcpkg graph libsndfile --ports ./ports    # 5 步：ogg/vorbis/opus/flac -> sndfile
./build/bin/gcpkg graph libzip --feature=libzip:openssl --ports ./ports
./tests/extra.sh                                      # 静态：43 两文件 / SHA / 图 / 生成器幂等
GCPKG_EXTRA_DYNAMIC=1 ./tests/extra.sh                # 全量真编译 43 个，3056 条 compdb

# 第十轮：38 个新库 + 代理（详见 docs/ROUND10_LIBRARIES.md / docs/PROXY.md）
./build/bin/gcpkg graph re2 --ports ./ports           # abseil -> re2
./build/bin/gcpkg graph libbsd --ports ./ports        # libmd -> libbsd
./tests/r10.sh                                        # 静态：38 两文件 / SHA / 图 / 生成器
GCPKG_R10_DYNAMIC=1 ./tests/r10.sh                    # 38/38 真编译，2498 条 compdb
./build/bin/gcpkg proxy http://proxy.corp:3128 -C apps/demo   # 项目特有代理
./build/bin/gcpkg proxy http://proxy.corp:3128 -g    # 用户级 / 公有代理
./build/bin/gcpkg install curl --proxy=http://127.0.0.1:7890  # 单次覆盖
./build/bin/gcpkg proxy --no-proxy                   # 强制直连（连标准环境变量也绕过）
./tests/proxy.sh                                     # 静态：优先级 / 两作用域 / 脱敏
GCPKG_PROXY_DYNAMIC=1 ./tests/proxy.sh               # 端到端：本地 CONNECT 代理

# 第十一轮：工具链 port + Python/Cargo adapter + tokenizers-cpp
./build/bin/gcpkg graph libvpx --ports ./ports        # nasm -> libvpx（SIMD）
./build/bin/gcpkg graph tokenizers-cpp --ports ./ports # rust -> tokenizers-cpp
./build/bin/gcpkg externals --ports ./ports          # rust: GCPKG_RUST_HOME
./tests/r11.sh                                       # 静态：23 两文件 / 生成器幂等 / 依赖链
GCPKG_R11_DYNAMIC=1 ./tests/r11.sh                   # 24/24 真编译，1353 条 compdb

# 第十二轮：GN 构建系统 + 25 个常见库（详见 docs/GN.md）
./build/bin/gcpkg graph crashpad --ports ./ports      # ninja -> gn -> crashpad
./build/bin/gcpkg graph taglib --feature=taglib:zlib --ports ./ports
./tests/r12.sh                                       # 静态：28 两文件 / GN adapter / 图
GCPKG_R12_DYNAMIC=1 ./tests/r12.sh                   # 干净 store 真编译 28 个新 port

# 第十三轮：托管工作区 + 依赖注入（详见 docs/MANAGED_WORKSPACES.md）
./build/bin/gcpkg workspace new ws --name=my-workspace
./build/bin/gcpkg workspace add -C ws --name=core --url=https://example/core.git \
                    --ref=main --submodules=recursive --system=cmake
./build/bin/gcpkg workspace sync -C ws                 # Git 全部由 gcpkg 代管
./build/bin/gcpkg workspace graph -C ws
./build/bin/gcpkg workspace build -C ws --dry-run
./build/bin/gcpkg workspace build -C ws               # 按依赖顺序构建所有仓库
./build/bin/gcpkg inject apps/demo --install          # vcpkg 风格 toolchain/env
./build/bin/gcpkg build apps/demo --system=canon,cmake # 无 gcpkg.lua 也可自动串联
./tests/r13.sh                                        # 静态：拓扑 / 环 / 注入 / canon 名称
GCPKG_R13_DYNAMIC=1 ./tests/r13.sh                    # 6 仓库真编译 + 统一 16 条 compdb
```

> store 请放在真实磁盘（如 `~/.cache/...`）：本沙箱 `/tmp` 是 992M 的 tmpfs，
> 多个源码树并行构建时会撑满。测试脚本已默认用 `$HOME/.cache/gcpkg-*-store`。

其它命令：

```bash
gcpkg install openssl --feature=openssl:shared      # 单独构建/安装库
gcpkg install libarchive                             # 自动构建 8 个 L0 依赖
gcpkg compdb examples/hello                          # 只重建合并的 compile_commands.json
gcpkg features openssl                               # 列出 YAML 特性
gcpkg ports                                          # 按依赖层级列出所有库（L0 = 最底层）
gcpkg graph curl                                     # 打印某库自底向上的构建顺序
gcpkg externals                                      # 列出专有 SDK port 所需环境变量
gcpkg graph xserver                                  # 16 步的 X11/Xserver 依赖链
gcpkg graph proxygen                                 # folly -> fizz -> wangle/mvfst -> proxygen
gcpkg graph gnutls                                   # GNU 数值/加密链，7 步
gcpkg install libpng --store ~/.cache/gcpkg-linux-store --ports ./ports
gcpkg graph udisks2                                  # 磁盘信息链，15 步
gcpkg new apps/demo                                  # pnpm 式项目脚手架
gcpkg add zlib@1.2.13 -C apps/demo                   # 给项目加依赖并锁定版本
gcpkg add --local mylib -C apps/demo                 # 项目私有 port（两文件）
gcpkg add -g bzip2                                   # 用户级公有依赖清单
gcpkg remove zlib -C apps/demo
gcpkg list -C apps/demo                              # 作用域、版本、lock
gcpkg versions zlib                                  # 4 个真实版本
gcpkg install -C apps/demo                           # 无参 = 安装项目全部依赖
gcpkg install nvme-cli --store ~/.cache/gcpkg-linux-store --ports ./ports
gcpkg graph openssl --feature=openssl:zlib           # 条件依赖也进入依赖图
gcpkg install systemd --store ~/.cache/gcpkg-linux-store --ports ./ports
gcpkg check --feature=openssl:zlib                   # 校验（含特性引入的依赖）
gcpkg backends                                       # 探测本机外部包管理器
gcpkg port new zlib                                  # 生成 port 模板
gcpkg proxy                                          # 查看代理来源与生效值
gcpkg proxy http://proxy.corp:3128 -g                # 写用户级代理
gcpkg proxy --unset -C apps/demo                     # 清除项目级代理
gcpkg --no-proxy install curl                        # 强制直连
```

配置文件示例（项目）：

```lua
-- gcpkg.lua
local cc = require("gcpkg.build.cc")
return {
  name = "myapp", version = "0.1.0",
  dependencies = { "openssl" },
  build = function(ctx)
    local objs = cc.compile{ sources={"src/main.c"}, includes=ctx.includes,
                             outdir=ctx.build_dir.."/obj", cwd=ctx.project_dir,
                             exec=ctx.exec, record=ctx.record }
    cc.link{ objects=objs, output=ctx.build_dir.."/myapp",
             libdirs=ctx.libdirs, libs=ctx.libs, flags=ctx.link_flags,
             exec=ctx.exec, cwd=ctx.project_dir }
  end,
}
```

```yaml
# gcpkg.yaml
project: myapp
features:
  openssl: [no-shared, no-tests]
```

## clangd

`gcpkg build` 会写两个文件：

- `<project>/compile_commands.json`：合并后的编译命令，包含项目自身、依赖库及其所有传递依赖（递归）的翻译单元。`examples/hello` 实测 1127 条（1126 OpenSSL + 1 项目），`examples/web` 站在 curl 链顶端，从零实测 2115 条、覆盖 134 个源码目录（复用旧缓存的 store 为 1689 条 / 124 目录）；
- `<project>/.clangd`：追加依赖的 `-I` 路径。

clangd 打开项目根目录即可工作；跳转到 `openssl/sha.h`、`crypto/sha/sha256.c` 等依赖源码时会使用该库自己的编译命令（`-I`、`-D` 全部保留），这是 vcpkg 这类只导出 include/lib 的管理器做不到的地方。Linux 栈的 36 个 port 同样各自产出编译数据库（合计 6718 条）；`tests/linux.sh` 会逐条校验绝对路径，并用 clangd 实际加载 libnuma / wayland / libX11 / xserver / systemd 五个库的 compdb；第六轮 14 个真编译 port 又贡献 884 条，第七轮 22 个再贡献 1061 条（各库 manifest 中 `compdb_entries` 均可查，store 累计 10034 条）；第九轮 43 个新库又贡献 3056 条；第十轮 38 个新库再贡献 2498 条；第十一轮的工具链 / 多语言 port 同样并入统一 compdb
（`python` 263 条、`libvpx` SIMD 构建 211 条、`tokenizers-cpp` 153 条、
`nasm` 85 条），Rust crate 本身按惯例交给 rust-analyzer 而非 clangd。
`GCPKG_R11_DYNAMIC=1 ./tests/r11.sh` 从全新 store 复现为
**24 PASS / 0 FAIL、1353 条编译命令**。第十二轮的 GN / Ninja / Crashpad
三层工具链同样并入统一 compdb：项目模式 `gcpkg compdb` 实测 718 条，
`GCPKG_R12_DYNAMIC=1 ./tests/r12.sh` 从干净 store 真编译
**28 PASS / 0 FAIL、4527 条编译命令**，并实跑最小 GN fixture、GN/Ninja
可执行文件、Crashpad 静态库与条件 zlib 依赖。第十三轮的
`GCPKG_R13_DYNAMIC=1 ./tests/r13.sh` 则从全新 local-Git 工作区真跑 6 个仓库、
递归 submodule、5 种内层系统组合，合并 **16 条 compile commands**，并逐个执行
生成的二进制。

## 目录

```
Source/Core/       C++ 运行时（Lua 沙箱、进程、YAML 桥、CLI 引导）
Source/Intercept/  gcpkg-intercept：透明 CC/CXX 编译器包装器
lua/gcpkg/         Lua 引擎（特性、port、project、workspace、proxy、编译数据库、adapter、CLI）
lua/gcpkg/build/   各构建系统的 Lua 适配模块
ports/             277 个库，每个 build.lua + features.yaml（L0 → L4，含工具链 port）
examples/hello/    OpenSSL 项目：gcpkg.lua + gcpkg.yaml + src/main.c
examples/web/      curl 全链顶端项目
tests/             14 个回归（含 r10 / proxy / r11 / r12 / r13）
docs/              16 篇架构与扩展文档
Source/MainProcess/  旧 TOML 原型，保留但不参与构建
```

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、[docs/EXTENDING.md](docs/EXTENDING.md)、
[docs/PROJECTS.md](docs/PROJECTS.md)（pnpm 式项目工作流）、
[docs/DISK_INFO.md](docs/DISK_INFO.md)、[docs/EXTRA_LIBRARIES.md](docs/EXTRA_LIBRARIES.md)、
[docs/ROUND10_LIBRARIES.md](docs/ROUND10_LIBRARIES.md)、
[docs/TOOLCHAINS.md](docs/TOOLCHAINS.md)（工具链与多语言 adapter）、
[docs/ROUND11_LIBRARIES.md](docs/ROUND11_LIBRARIES.md)、
[docs/EXTERNAL_SDKS.md](docs/EXTERNAL_SDKS.md)、
[docs/GN.md](docs/GN.md)、[docs/ROUND12_LIBRARIES.md](docs/ROUND12_LIBRARIES.md)、
[docs/MANAGED_WORKSPACES.md](docs/MANAGED_WORKSPACES.md)、
[docs/DEPENDENCY_INJECTION.md](docs/DEPENDENCY_INJECTION.md)、
[docs/CANON.md](docs/CANON.md)
与 [docs/ROUND13_MANAGED_WORKSPACES.md](docs/ROUND13_MANAGED_WORKSPACES.md)。

许可证：BSD-3-Clause（见 LICENSE）。
