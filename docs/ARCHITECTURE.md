# 工作原理

gcpkg 分三层工作：外层负责项目与仓库，中层负责依赖解析与 store，内层调用各项目自己的构建系统。

```text
项目 / 工作区
  gcpkg.yaml、gcpkg.lua、gcpkg.lock、workspace.yaml、workspace.lock
        |
        v
解析层
  port 搜索、features、版本、依赖图、下载与缓存、proxy、store
        |
        v
构建与注入层
  CMake / Meson / GN / Autotools / Makefile / Python / Cargo / Conan
  gcpkg-intercept、依赖 prefix、toolchain、env、JSON 清单
        |
        v
统一 compdb
  compile_commands.json + .clangd
```

## port

`ports/<name>/build.lua` 返回一个 Lua 表，声明 `name`、`version`、`source`、`dependencies` 和 `build(ctx)`。多数 port 使用 `gcpkg.recipe` 的声明式 recipe；需要特殊步骤时可以写 `pre_build`、`post_install` 或完整的 `build(ctx)`。

`ports/<name>/features.yaml` 描述可开关特性、构建参数、条件依赖、冲突与版本表。命令行 `--feature=PORT:NAME` 会把启用特性的参数传给构建上下文。

## store

每个已安装的 port 有一个稳定 key，例如 `zlib-1.3.1`。对应目录包括：

```text
<store>/src/<key>/         上游源码
<store>/build/<key>/       out-of-tree 构建目录
<store>/pkg/<key>/         安装 prefix
<store>/manifest/<key>.json
<store>/logs/              构建日志
```

manifest 记录 `includes`、`libdirs`、`libs`、`defines`、`link_flags`、`binaries`、`compdb_entries` 与依赖信息。相同 key 命中缓存时不会重复构建；`--no-cache` 可强制重建。

## 依赖图

`gcpkg graph PORT` 按依赖层次自底向上输出顺序。依赖可以来自 `build.lua` 的 `dependencies`，也可以由 `features.yaml` 的 `requires` 按特性条件引入。循环依赖会直接报错。

项目模式下，`gcpkg.yaml` 的 `dependencies` 与用户级清单共同决定安装集合；`gcpkg.lock` 记录实际解析出的 key、版本、作用域与 port 目录。

## 编译拦截与合并

`gcpkg-intercept` 位于 `CC` / `CXX` 包装层，把每次编译器调用记录为 JSONL。CMake、Meson、GN、Ninja 的原生 compdb 会一并读取。gcpkg 将所有条目中的 `file` 归一化，去除无效路径，再写出项目根或工作区根的 `compile_commands.json`。

由于依赖源码与 prefix 保存在 store 中，clangd 可以使用每个库自己的 `-I`、`-D` 与编译参数跳转到依赖内部。

## 注入

`gcpkg inject` 与 `workspace build` 在 `.gcpkg/inject/` 下生成一组文件：CMake toolchain / cache、Meson native file、GN `.gni`、Makefile flags、shell env、pkg-config 链接、`gcpkg-deps.json` 和 Conan 清单。它们描述同一份依赖信息，供内层系统按原生格式读取，不需要改写项目源码。详见 [DEPENDENCY_INJECTION.md](DEPENDENCY_INJECTION.md)。

## 引擎模块

| 文件 | 职责 |
| --- | --- |
| `lua/gcpkg/cli.lua` | 命令、选项、帮助与 doctor |
| `lua/gcpkg/config.lua` | 用户级 store 配置与优先级 |
| `lua/gcpkg/port.lua` | 单个 port 的下载、构建、manifest |
| `lua/gcpkg/features.lua` | YAML 特性、版本与条件依赖 |
| `lua/gcpkg/graph.lua` | 依赖图与拓扑顺序 |
| `lua/gcpkg/project.lua` | 项目构建、依赖安装、lock、compdb |
| `lua/gcpkg/workspace.lua` | 项目工作流与用户级清单 |
| `lua/gcpkg/managed.lua` | 多仓库工作区清单与锁 |
| `lua/gcpkg/inject.lua` | 注入文件与环境变量 |
| `lua/gcpkg/inner.lua` | 内层系统命令链 |
| `lua/gcpkg/recipe.lua` | 声明式构建 recipe |
| `lua/gcpkg/build/*.lua` | CMake / Meson / GN / Make / CC / Python / Cargo adapter |
| `lua/gcpkg/proxy.lua` | 代理解析、作用域与脱敏 |
| `lua/gcpkg/net.lua` | 下载、Git clone 与缓存标记 |
