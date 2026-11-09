# 托管工作区：把一堆项目/仓库交给 gcpkg 维护

第十三轮（R13）把 gcpkg 明确定位成**外层元包管理器**：

- 外层：gcpkg 维护多个 Git 仓库、子模块、固定 commit、跨项目依赖树、构建顺序、注入文件、统一 `compile_commands.json`；
- 内层：每个项目继续使用自己的 CMake、GN、Meson、`canon` 包管理器、Makefile、Ninja，或它们的组合；
- 用户不再手工 `git clone/fetch/checkout/submodule update/status`，这些操作由 `gcpkg workspace` 通过 `lua/gcpkg/git.lua` 统一执行；
- **上游源码不被改写**：仓库里的 tracked 源文件保持不动，所有生成物落在工作区根的 `.gcpkg/` 与 `compile_commands.json` / `.clangd`，或项目自身已有的 `gcpkg.lock`。

> 此前四个澄清问题被 skipped，**不视为批准**：`canon` 保持用户原词，不静默改成 Conan；`workspace.yaml` 只是外层托管清单（可手写），不是项目内层构建脚本；R13 也不把「生成构建脚本」视为已获批准。用户可用 `path:` 本地 checkout、`systems: ["none"]` 只生成注入文件。详见 [CANON.md](CANON.md)。

## 目录结构

```text
ws/
├── workspace.yaml              声明式仓库 / 边 / 包 / 内层系统
├── workspace.lock              解析后的 commit、递归子模块 pin、resolved 包、拓扑序
├── repos/<name>/               gcpkg clone 出来的 Git checkout（可含 .gitmodules）
├── .gcpkg/
│   ├── inject/<name>/          每个项目的 toolchain/env/native/gni/canon 文件
│   ├── build/<name>/           out-of-tree 构建目录
│   ├── prefix/<name>/          每个项目安装给下游的 prefix
│   ├── compdb/<name>.json      单项目 compdb
│   └── logs/*.log              git / build 日志（URL 凭据已脱敏）
└── compile_commands.json       全工作区统一 compdb
```

`repos/<name>` 在 `workspace.lock` 的父目录之下，所以 clangd 在工作区根打开一个数据库即可覆盖所有子仓库。若仓库用 `path:` 指向工作区外的本地目录，gcpkg 不改动它的 Git 状态，只在 `.gcpkg/` 里生成注入文件。

## workspace.yaml

```yaml
workspace: "my-workspace"
packages: ["zlib@1.3.1", "openssl"]     # 可选：所有子项目共享的 catalog 包

repos:
  - name: core
    url: "https://github.com/example/core.git"
    ref: "main"
    submodules: "recursive"              # recursive / normal / shallow / false
    systems: ["cmake"]
    depends: []
    packages: []
  - name: app
    path: "../app"                       # 本地 checkout，或改用 url 让 gcpkg clone
    systems: ["canon", "cmake"]          # 先跑内层 canon，再跑 CMake，注入环境相同
    canon_cmd: ["canon", "install", "@canon@"]
    depends: ["core"]
```

字段说明：

| 字段 | 含义 |
| --- | --- |
| `url` | gcpkg 负责 `clone/fetch/checkout`；`ref` 是 branch/tag；`commit` 是显式固定 SHA |
| `path` | 已经存在的本地 checkout；没有 Git 元数据时只生成注入，不接管 Git |
| `submodules` | `recursive` 会执行 `git submodule sync --recursive` + `update --init --recursive`，并把每一层 gitlink SHA 写入 `workspace.lock` |
| `depends` | 工作区内其它仓库名，构成跨项目依赖树；`gcpkg.yaml` 里的 `depends:` 也会被识别为隐式边 |
| `packages` | 该项目额外需要的 gcpkg catalog 包；项目私有 port 仍走 `gcpkg-ports/` |
| `systems` | `cmake` / `gn` / `meson` / `canon` / `makefile` / `ninja` / `auto` / `none`，可写多个 |
| `commands` | 覆盖某个内层系统的命令；`@canon@`、`@toolchain@`、`@build@`、`@jobs@` 等 token 会展开 |
| `canon_cmd` | `commands.canon` 的简写；见 [CANON.md](CANON.md) |
| `exports` | 相对 `prefix` 的额外 include/lib/bin 路径；默认自动扫描 `prefix/include`、`prefix/lib`、`prefix/bin` |
| `install_prefix` / `build_dir` | 覆盖默认的 `.gcpkg/prefix/<name>` / `.gcpkg/build/<name>` |

`gcpkg workspace add` 会规范化并重写 `workspace.yaml`；`gcpkg workspace remove` 同时删除其它仓库指向它的边。拓扑排序使用三色 DFS，循环依赖直接报错而不是乱序构建。

## Git 完全由 gcpkg 代管

```bash
gcpkg workspace new ws --name=my-workspace
gcpkg workspace add -C ws --name=core --url=https://example/core.git --ref=main \
                    --submodules=recursive --system=cmake
gcpkg workspace sync -C ws                 # clone / fetch / checkout / recursive submodules
gcpkg workspace status -C ws               # HEAD、branch、dirty、remote、submodule 数、locked SHA
gcpkg workspace update -C ws               # fetch 最新 ref 并刷新 workspace.lock
gcpkg workspace pin core -C ws             # 把当前 HEAD 写入 workspace.yaml commit:
gcpkg workspace pin core <sha> -C ws       # 显式固定 commit
gcpkg workspace pin core --unpin -C ws     # 解除固定
gcpkg workspace submodule status core -C ws
gcpkg workspace submodule sync core -C ws
gcpkg workspace pin core --unpin -C ws
gcpkg workspace submodule pin core -C ws
gcpkg workspace submodule add -C ws --repo=core --url=... --path=vendor/x --git-commit
```

`sync` 的默认语义是可复现：若 `workspace.lock` 已有 commit，先检查对象是否存在，再 `checkout --detach <sha>`；`--update` 才 fetch 并解析 `origin/<ref>`。显式 `commit:` 永远优先。`--force` 才会丢弃本地 tracked 修改。子模块 pin 在后续 `sync` 中会被校验：父 commit 记录的 gitlink SHA 与 lock 不一致时直接报错，要求显式 `--update` 接受变化。

`gcpkg sync` / `gcpkg update` / `gcpkg status` / `gcpkg tree` 是工作区内可省略 `workspace` 前缀的短别名。

## 依赖树与构建顺序

```bash
gcpkg workspace graph -C ws        # 1. core <- [] / 2. app <- [core] ...
gcpkg workspace build -C ws --dry-run
gcpkg workspace build -C ws --only=app       # app + 它的依赖 core
gcpkg workspace build -C ws --system=canon,cmake
gcpkg workspace inject core -C ws            # 只装包并生成注入，不跑内层构建
gcpkg workspace build -C ws --ports ./gcpkg-ports:./ports --store ~/.cache/gcpkg-ws
```

`build` 的处理顺序：

1. 安装 `packages:` 和每个项目的 `gcpkg.yaml` / `gcpkg.lua` 依赖（兼容私有 port、features、proxy、`gcpkg.lock`）；
2. 按拓扑序生成 `.gcpkg/inject/<name>/`（见 [DEPENDENCY_INJECTION.md](DEPENDENCY_INJECTION.md)）；
3. 把已经构建项目的 `prefix/include|lib|bin` 合并进下游项目的注入，静态库按「依赖者在前」排序；
4. 依次调用内层系统；CMake / Meson / GN 的原生 compdb 与 `gcpkg-intercept` 的 JSONL 一起合并；
5. 写每项目 compdb、工作区根 `compile_commands.json`、`.clangd` 和 `workspace.lock` 的 `resolved` 列表。

`gcpkg.yaml` 可以只写 `dependencies` + `system`，**不需要 `gcpkg.lua`**：`gcpkg build <dir>` 会自动驱动内层构建系统。已有 `gcpkg.lua` 的项目仍按原 `build(ctx)` 运行，并额外得到 `ctx.inject`、`ctx.inject_dir`、`ctx.inner()` 供显式使用。

## 与既有模式兼容

| 既有能力 | R13 中的行为 |
| --- | --- |
| `gcpkg.yaml` / `gcpkg.lua` / `gcpkg.lock` | 子仓库若存在就照常读取；`workspace.lock` 另记跨仓库边和 Git pin |
| 项目私有 port | `workspace.roots()` 仍把 `gcpkg-ports/` 放在最前；CLI `--ports` 可追加工作区级私有 port |
| proxy | clone/fetch 与所有 `ctx.exec` 仍继承 `proxy.env()`，日志中的 `user:pass@` 被脱敏 |
| 统一 compdb | 工作区根一份总库；每个仓库也保留 `.gcpkg/compdb/<name>.json`；单项目模式仍写项目根 `compile_commands.json` |
| 不改写上游 | 生成文件不进仓库 tracked 源码；`git status --porcelain --untracked-files=no` 在全流程后保持 clean |

完整的最终动态结果与逐项断言见 [ROUND13_MANAGED_WORKSPACES.md](ROUND13_MANAGED_WORKSPACES.md)。
