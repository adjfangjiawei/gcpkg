# gcpkg

一个**元包管理器**：用 Lua 描述「怎么构建一个库」，用 YAML 描述「这个库有哪些特性」，把任意构建系统、乃至其它包管理器（vcpkg / conan / pkg-config / apt / …）接进来，**不改它们本身**，并且让项目自身也能被它管理、生成可跨依赖跳转的 clangd 编译数据库。

> 当前分支 `feat/lua-yaml-compdb-openssl` 是可运行的第一个版本：Lua 引擎 + YAML 特性 + 项目模式 + 统一编译数据库 + 第一个真实库 **OpenSSL 3.4.1**。

## 三个核心要求如何落地

| 要求 | 实现 |
| --- | --- |
| 一个库 = 一个 Lua 构建配置 + 一个 YAML 特性配置 | `ports/<name>/build.lua`（声明 source、依赖、build 钩子；可 `require("gcpkg.build.cmake")` 获得 cmake 构建函数，也可 `gcpkg.import("其它库")` 复用其配置）和 `ports/<name>/features.yaml`（args / env / defines / requires / conflicts / provides）。YAML 改构建参数，Lua 完全不用动。 |
| 直接管理项目 + 跨依赖跳转 | 项目目录里写 `gcpkg.lua` + `gcpkg.yaml`，`gcpkg build .` 直接编译项目，并在项目根生成 `compile_commands.json`（项目 + 所有传递依赖）和 `.clangd`。依赖源码目录长期保留在 store 中，路径稳定，所以 clangd 能一路跳转进依赖的头文件和源文件，再跳回来。 |
| 能管理几乎所有库 | C++ 运行时只提供 进程执行 / 文件 / YAML / Lua 沙箱；构建逻辑全是 Lua 模块（`cmake` / `make` / `autotools` / `meson` / `cargo` / `cc` / `auto`），加新构建系统 = 加一个 Lua 文件；接外部包管理器 = 注册一个 adapter（已内置 `pkgconfig`、`vcpkg`、`system`、`call`）。编译器拦截层（`gcpkg-intercept`）让上游构建系统一行不改也能产出编译数据库。 |

## 快速开始

```bash
# 依赖：CMake >= 3.28、C++20 编译器、Lua 5.4 开发库、yaml-cpp、pkg-config
cmake -S . -B build
cmake --build build -j
./build/bin/gcpkg doctor

# 构建示例项目（会自动下载并编译 OpenSSL，然后编译项目，生成编译数据库）
./build/bin/gcpkg build examples/hello --store /tmp/gcpkg-store --ports ./ports
./examples/hello/.gcpkg/build/hello-gcpkg
python3 -c "import json;d=json.load(open('examples/hello/compile_commands.json'));print(len(d),'compile commands')"
```

其它命令：

```bash
gcpkg install openssl --feature=openssl:shared      # 单独构建/安装库
gcpkg compdb examples/hello                          # 只重建合并的 compile_commands.json
gcpkg features openssl                               # 列出 YAML 特性
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

- `<project>/compile_commands.json`：合并后的编译命令，包含项目自身、OpenSSL 以及 OpenSSL 的依赖（递归）的所有翻译单元；
- `<project>/.clangd`：追加依赖的 `-I` 路径。

clangd 打开项目根目录即可工作；跳转到 `openssl/sha.h`、`crypto/sha/sha256.c` 等依赖源码时会使用该库自己的编译命令（`-I`、`-D` 全部保留），这是 vcpkg 这类只导出 include/lib 的管理器做不到的地方。

## 目录

```
Source/Core/       C++ 运行时（Lua 沙箱、进程、YAML 桥、CLI 引导）
Source/Intercept/  gcpkg-intercept：透明 CC/CXX 编译器包装器
lua/gcpkg/         Lua 引擎（特性、port、project、编译数据库、adapter、CLI）
lua/gcpkg/build/   各构建系统的 Lua 适配模块
ports/openssl/     第一个库：build.lua + features.yaml
examples/hello/    第一个项目：gcpkg.lua + gcpkg.yaml + src/main.c
docs/              架构与扩展文档
Source/MainProcess/  旧 TOML 原型，保留但不参与构建
```

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 与 [docs/EXTENDING.md](docs/EXTENDING.md)。

许可证：BSD-3-Clause（见 LICENSE）。
