# gcpkg

一个**元包管理器**：用 Lua 描述「怎么构建一个库」，用 YAML 描述「这个库有哪些特性」，把任意构建系统、乃至其它包管理器（vcpkg / conan / pkg-config / apt / …）接进来，**不改它们本身**，并且让项目自身也能被它管理、生成可跨依赖跳转的 clangd 编译数据库。

> 当前分支 `feat/lua-yaml-compdb-openssl`：Lua 引擎 + YAML 特性 + 项目模式 + 统一编译数据库 + **145 个真实 port**（L0 → L4）。按依赖层次自底向上扩展：`openssl` 起步，L0 十个基础库，再到 `libssh2` / `nghttp2` / `curl` 全链与 `libarchive`（一次挂 8 个 L0 依赖）。第四轮继续覆盖 Linux 底层库栈：NUMA / 权限与沙箱 / netfilter / X11 / **Xserver** / **Wayland** / libinput / D-Bus / kmod / util-linux / **systemd** / ipvs / iptables —— 36 个新 port 全部真实编译（6718 条编译命令），`xserver` 依赖图 16 步、`systemd` 单包 3272 条。特性开关也能引入真实的传递依赖（`openssl:zlib` → 先构建 `zlib`）。第五轮再覆盖 CMake / Lua / ALSA / libpsl / libfuse / live555 / librtsp / UCX / Vulkan / folly / proxygen / Redpanda 以及 NVIDIA（CUDA、DCGM、Video Codec SDK、nvImageCodec、CV-CUDA）、华为 CANN、大华播放库 —— 共 23 个新 port；其中 4 个需登录或专有的 SDK 做成 `gcpkg.build.external` 声明式 port，`gcpkg externals` 静态列出所需环境变量，你在本地设好即可真构建。第六轮继续补 Linux 基础库：GNU 数值/加密栈（GMP → GnuTLS）、终端/数据（ncurses → readline、SQLite、Jansson）、图像字体（libpng → freetype → fontconfig / HarfBuzz）与内核接口（libattr → libacl、elfutils → libbpf），共 37 个新 port，其中 14 个在这里真编译出 884 条编译命令。第七轮专攻**内核接口与磁盘/存储信息查询**（NVMe/SMART/分区/文件系统/RAID/DMI/PCI、ftrace、keyring、GPIO、IIO 等），新增 34 个 port；`liburing` 早就在栈里，这一轮重新从干净源码复核（14 条 compdb）并让它成为 `libnvme → udisks2` 磁盘信息链的一环，另有 21 个新 port 真编译（合计 1061 条）。第八轮补上 pnpm 式项目工作流：
`gcpkg new` / `add` / `remove` / `list` / `versions` / `install`（无参），
区分**项目私有 port / 用户级 / 公有 registry** 三种作用域与**项目特有 / 公有**
两种依赖清单，并让不同项目锁定同库的不同版本（`zlib@1.2.13` 与
`zlib@1.3.1` 同时真编译，`gcpkg.lock` 各记各的），详见
[docs/PROJECTS.md](docs/PROJECTS.md)。

## 三个核心要求如何落地

| 要求 | 实现 |
| --- | --- |
| 一个库 = 一个 Lua 构建配置 + 一个 YAML 特性配置 | `ports/<name>/build.lua`（声明 source、依赖、build 钩子；可 `require("gcpkg.build.cmake")` 获得 cmake 构建函数，也可 `gcpkg.import("其它库")` 复用其配置）和 `ports/<name>/features.yaml`（args / env / defines / requires / conflicts / provides）。YAML 改构建参数，Lua 完全不用动。 |
| 直接管理项目 + 跨依赖跳转 | 项目目录里写 `gcpkg.lua` + `gcpkg.yaml`，`gcpkg build .` 直接编译项目，并在项目根生成 `compile_commands.json`（项目 + 所有传递依赖）和 `.clangd`。依赖源码目录长期保留在 store 中，路径稳定，所以 clangd 能一路跳转进依赖的头文件和源文件，再跳回来。 |
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

clangd 打开项目根目录即可工作；跳转到 `openssl/sha.h`、`crypto/sha/sha256.c` 等依赖源码时会使用该库自己的编译命令（`-I`、`-D` 全部保留），这是 vcpkg 这类只导出 include/lib 的管理器做不到的地方。Linux 栈的 36 个 port 同样各自产出编译数据库（合计 6718 条）；`tests/linux.sh` 会逐条校验绝对路径，并用 clangd 实际加载 libnuma / wayland / libX11 / xserver / systemd 五个库的 compdb；第六轮 14 个真编译 port 又贡献 884 条，第七轮 22 个再贡献 1061 条（各库 manifest 中 `compdb_entries` 均可查，store 累计 10034 条）。

## 目录

```
Source/Core/       C++ 运行时（Lua 沙箱、进程、YAML 桥、CLI 引导）
Source/Intercept/  gcpkg-intercept：透明 CC/CXX 编译器包装器
lua/gcpkg/         Lua 引擎（特性、port、project、workspace、编译数据库、adapter、CLI）
lua/gcpkg/build/   各构建系统的 Lua 适配模块
ports/             145 个库，每个 build.lua + features.yaml（L0 → L4）
examples/hello/    OpenSSL 项目：gcpkg.lua + gcpkg.yaml + src/main.c
examples/web/      curl 全链顶端项目
tests/             smoke / chain / features / linux / media / linux-base / linux-kernel / projects 八个回归
docs/              架构与扩展文档
Source/MainProcess/  旧 TOML 原型，保留但不参与构建
```

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、[docs/EXTENDING.md](docs/EXTENDING.md)、
[docs/PROJECTS.md](docs/PROJECTS.md)（pnpm 式项目工作流）、
[docs/DISK_INFO.md](docs/DISK_INFO.md) 与 [docs/EXTERNAL_SDKS.md](docs/EXTERNAL_SDKS.md)。

许可证：BSD-3-Clause（见 LICENSE）。
