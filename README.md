# gcpkg

gcpkg 是一个**元包管理器**：上层维护项目、工作区、依赖与编译数据库，下层把 CMake、Meson、GN、Autotools、Makefile、Python、Cargo、Conan 等构建方式接入同一个 store。每个库由 `build.lua` 描述构建过程，由 `features.yaml` 描述特性与版本；上游源码无需修改。

当前注册表提供 **316 个 port**，覆盖网络、加密、压缩、媒体、Linux 系统栈、工具链、图形、数据结构和常用 C/C++ 库。构建结果会合并为 `compile_commands.json`，配合 `.clangd` 可以从项目代码直接跳转到依赖源码。

## 安装

在 Debian / Ubuntu 上，仓库根目录的安装脚本会准备编译 gcpkg 与常见 port 所需的工具：

```bash
bash ./setup-gcpkg-toolchain.sh
cmake -S . -B build
cmake --build build -j
./build/bin/gcpkg doctor
```

脚本使用 `sudo apt-get`，只从仓库自身位置推导路径。其他发行版可按脚本里的包清单安装等价组件；gcpkg 本体需要 CMake、C++20 编译器、Lua 5.4、yaml-cpp、libcurl 与 pkg-config。

## 设置一次全局 store

store 保存下载的源码、prefix、manifest、编译数据库与构建日志。首次使用时设置一个用户级目录，之后命令不再需要长 `--store` 参数：

```bash
./build/bin/gcpkg store set ~/.cache/gcpkg-store
./build/bin/gcpkg store show
./build/bin/gcpkg doctor
```

优先级从高到低为 `--store`、`GCPKG_STORE`、`GCPKG_HOME`、用户级 `config.yaml`、默认 `~/.gcpkg`。配置位置是 `$GCPKG_CONFIG`，或 `$XDG_CONFIG_HOME/gcpkg/config.yaml`，或 `~/.config/gcpkg/config.yaml`。清除配置用 `gcpkg store unset`。详见 [docs/CONFIGURATION.md](docs/CONFIGURATION.md)。

## 常用命令

```bash
# 查看、检查与安装
./build/bin/gcpkg ports --ports ./ports
./build/bin/gcpkg graph curl --ports ./ports
./build/bin/gcpkg check --ports ./ports
./build/bin/gcpkg install curl --ports ./ports -j 4
./build/bin/gcpkg install zlib@1.2.13 --ports ./ports
./build/bin/gcpkg features openssl --ports ./ports

# 项目工作流
./build/bin/gcpkg new apps/demo --name=demo
./build/bin/gcpkg add zlib@1.2.13 -C apps/demo
./build/bin/gcpkg add --local mylib -C apps/demo
./build/bin/gcpkg install -C apps/demo
./build/bin/gcpkg build apps/demo --ports ./ports
./build/bin/gcpkg compdb apps/demo
./build/bin/gcpkg list -C apps/demo

# 工作区与依赖注入
./build/bin/gcpkg workspace new ws --name=my-workspace
./build/bin/gcpkg workspace add -C ws --name=app --url=https://example.com/app.git \
    --system=conan,cmake
./build/bin/gcpkg workspace sync -C ws
./build/bin/gcpkg workspace build -C ws --ports ./ports
./build/bin/gcpkg inject apps/demo --install --system=cmake

# 网络与诊断
./build/bin/gcpkg proxy http://proxy.example:3128 -g
./build/bin/gcpkg proxy --check
./build/bin/gcpkg proxy --unset -g
./build/bin/gcpkg install curl --no-proxy
./build/bin/gcpkg backends
./build/bin/gcpkg externals

# 编译器、LLVM 与交叉编译
./build/bin/gcpkg toolchain
./build/bin/gcpkg llvm show
./build/bin/gcpkg llvm install 23 --dry-run
./build/bin/gcpkg llvm use /usr/lib/llvm-23
./build/bin/gcpkg build apps/demo --target=aarch64-linux-gnu --sysroot=/srv/sysroot
```

`gcpkg proxy` 保存的代理会通过私有 curl 配置（`-q -K` / `CURL_HOME`）和 Git `GIT_CONFIG_*` 显式下发给下载、克隆与构建钩子，不会被 `~/.curlrc`、`NO_PROXY=*` 或 `~/.gitconfig` 静默绕开；详见 [docs/PROXY.md](docs/PROXY.md)。CMake 4 对旧版上游库的策略兼容也由引擎统一处理，详见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

`--ports` 可以写 `DIR[:DIR...]`，项目私有 port 放在 `<project>/gcpkg-ports/`，用户级 port 放在 `$GCPKG_HOME/ports/`。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | store、port 搜索路径、代理、环境变量与优先级 |
| [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md) | clang 默认、版本化探查、LLVM port、交叉编译与配置优先级 |
| [docs/PORTS.md](docs/PORTS.md) | 全部 port、常用库、特性、版本与外部 SDK |
| [docs/EXTENDING.md](docs/EXTENDING.md) | 编写 `build.lua` / `features.yaml`，使用声明式 recipe |
| [docs/PROJECTS.md](docs/PROJECTS.md) | 项目创建、依赖、作用域、版本锁定 |
| [docs/MANAGED_WORKSPACES.md](docs/MANAGED_WORKSPACES.md) | 多仓库工作区、Git 同步、拓扑构建 |
| [docs/DEPENDENCY_INJECTION.md](docs/DEPENDENCY_INJECTION.md) | toolchain、env、native file、GN、Makefile 与 JSON 清单 |
| [docs/CONAN.md](docs/CONAN.md) | 把 Conan 作为项目内层包管理器接入 |
| [docs/BUILD_SYSTEMS.md](docs/BUILD_SYSTEMS.md) | 支持的构建系统与编译数据库来源 |
| [docs/PROXY.md](docs/PROXY.md) | 代理配置、凭据脱敏与绕过列表 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 引擎、store 与编译数据库的工作原理 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | `doctor`、诊断与常见问题 |

## 编译数据库

`gcpkg build` 会把以下来源合并到项目根目录的 `compile_commands.json`：

1. 编译拦截层采集的命令；
2. CMake、Meson、GN、Ninja 等原生编译数据库；
3. 每个已安装 port 的 manifest compdb；
4. 托管工作区中先前仓库的编译数据库。

源码目录保留在 store 中，路径稳定，clangd 可以在项目与依赖之间双向跳转。只重建数据库时运行 `gcpkg compdb <project>`。

## 仓库结构

```text
setup-gcpkg-toolchain.sh  主机工具安装脚本
lua/gcpkg/                Lua 引擎、recipe、adapter、CLI
ports/<name>/             每个库两个文件：build.lua + features.yaml
examples/                 可直接构建的项目示例
tests/                    本地自检脚本与离线 fixture
tools/                    port 清单与生成脚本
docs/                     使用文档
```

`build/`、store 与缓存不属于版本库内容。仓库不会写入本机专用绝对路径；示例统一使用相对路径、`~`、`$HOME`、`$XDG_CONFIG_HOME` 或 `mktemp -d`。
