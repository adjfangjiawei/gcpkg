# 托管工作区

托管工作区用于同时维护多个 Git 仓库。gcpkg 在外层负责 clone / fetch / checkout、递归 submodule、固定 commit、跨项目依赖树、构建顺序、注入文件与统一编译数据库；每个项目内部继续使用自己的 CMake、GN、Meson、Conan、Makefile 或 Ninja。

项目仓库的 tracked 源码不会被改写；生成文件放在工作区根的 `.gcpkg/`、`compile_commands.json`、`.clangd`，或项目已有的 `gcpkg.lock`。

## 目录结构

```text
ws/
├── workspace.yaml
├── workspace.lock
├── repos/<name>/
├── .gcpkg/
│   ├── inject/<name>/
│   ├── build/<name>/
│   ├── prefix/<name>/
│   ├── compdb/<name>.json
│   └── logs/
└── compile_commands.json
```

## workspace.yaml

```yaml
workspace: "my-workspace"
packages: ["zlib@1.3.1", "openssl"]

repos:
  - name: core
    url: "https://example.com/core.git"
    ref: "main"
    submodules: "recursive"
    systems: ["cmake"]
    depends: []
    packages: []
  - name: app
    path: "../app"
    systems: ["conan", "cmake"]
    conan_cmd: ["conan", "install", ".", "--output-folder=@build@"]
    depends: ["core"]
```

| 字段 | 含义 |
| --- | --- |
| `url` | gcpkg 负责 clone / fetch；`ref` 指定 branch / tag，`commit` 固定 SHA |
| `path` | 使用已有本地 checkout；没有 Git 元数据时只生成注入文件 |
| `submodules` | `recursive` / `normal` / `shallow` / `false` |
| `depends` | 工作区内其他仓库名，构成跨项目依赖树 |
| `packages` | 该项目额外需要的 catalog port |
| `systems` | `cmake` / `gn` / `meson` / `conan` / `makefile` / `ninja` / `auto` / `none`，可组合 |
| `commands` | 覆盖某个内层系统的命令，支持 token 展开 |
| `conan_cmd` | `commands.conan` 的简写 |
| `exports` | 相对 prefix 的额外 include / lib / bin 路径 |
| `install_prefix` / `build_dir` | 覆盖默认生成目录 |

`canon` 仍可作为 Conan 的兼容别名，例如 `canon_cmd`。新配置推荐统一使用 `conan`。

## Git 操作

```bash
gcpkg workspace new ws --name=my-workspace
gcpkg workspace add -C ws --name=core --url=https://example.com/core.git     --ref=main --submodules=recursive --system=cmake
gcpkg workspace sync -C ws
gcpkg workspace status -C ws
gcpkg workspace update -C ws
gcpkg workspace pin core -C ws
gcpkg workspace pin core <sha> -C ws
gcpkg workspace pin core --unpin -C ws
gcpkg workspace submodule status core -C ws
gcpkg workspace submodule sync core -C ws
gcpkg workspace submodule pin core -C ws
gcpkg workspace submodule add -C ws --repo=core --url=... --path=vendor/x --git-commit
```

`sync` 默认以 `workspace.lock` 中的 commit 为准；`--update` 才 fetch 最新 ref 并刷新 lock。显式 `commit:` 始终优先。`--force` 才会丢弃本地 tracked 修改。子模块 gitlink 与 lock 不一致时，`sync` 会提示显式更新。

`gcpkg sync`、`gcpkg update`、`gcpkg status`、`gcpkg tree` 是工作区内可省略 `workspace` 前缀的短别名。

## 依赖树与构建

```bash
gcpkg workspace graph -C ws
gcpkg workspace build -C ws --dry-run
gcpkg workspace build -C ws --only=app
gcpkg workspace build -C ws --system=conan,cmake
gcpkg workspace inject core -C ws
gcpkg workspace build -C ws --ports ./gcpkg-ports:./ports
```

构建流程：

1. 安装 `packages:` 与各项目 `gcpkg.yaml` / `gcpkg.lua` 声明的依赖；
2. 按拓扑序生成 `.gcpkg/inject/<name>/`；
3. 把已完成项目的 prefix 注入下游，静态库按依赖者在前排序；
4. 依次调用内层系统；
5. 合并原生 compdb 与拦截层记录，写出每个仓库及工作区根的编译数据库。

`gcpkg.yaml` 可以只写 `dependencies` 与 `system`，不必提供 `gcpkg.lua`。已有 `gcpkg.lua` 的项目仍按 `build(ctx)` 运行，并可通过 `ctx.inject` 显式使用注入结果。

## 兼容能力

| 能力 | 工作区中的行为 |
| --- | --- |
| `gcpkg.yaml` / `gcpkg.lua` / `gcpkg.lock` | 子仓库存在时照常读取，`workspace.lock` 另记跨仓库边与 Git pin |
| 项目私有 port | `gcpkg-ports/` 优先；`--ports` 可追加工作区级目录 |
| proxy | clone / fetch 与所有构建子进程继承同一配置，日志中的凭据会被脱敏 |
| 统一 compdb | 工作区根写总库，`.gcpkg/compdb/` 保留每仓库副本 |
| 上游源码 | 生成文件不进入 tracked 源码，构建完成后仓库状态保持干净 |

详见 [DEPENDENCY_INJECTION.md](DEPENDENCY_INJECTION.md) 与 [CONAN.md](CONAN.md)。
