# 第十三轮：多项目 / 多仓库托管工作区与依赖注入

R13 的目标是把 gcpkg 明确成**外层元包管理器**：用户不再手工 `git clone/fetch/checkout/submodule update/status`，由 gcpkg 维护仓库、递归子模块、固定 commit、跨项目依赖树与构建顺序；每个项目内部继续保留 CMake、GN、Meson、`canon` 包管理器、Makefile / Ninja / 自定义命令。依赖注入类似 vcpkg，但覆盖 toolchain、cache、native file、`.gni`、Makefile flags、pkg-config、环境变量、`canon` 清单和统一 compdb。兼容既有 `gcpkg.yaml` / `gcpkg.lua` / `gcpkg.lock`、项目私有 port、proxy；**不改写上游 tracked 源码**。

> 四个澄清问题此前被 skipped，不作为批准。`canon` 保持用户原词；不假定 Canon=Conan；`workspace.yaml` 是外层托管清单，不是项目内层构建脚本；是否生成脚本也没有被当成已批准，R13 生成的只是 `.gcpkg/` 注入文件、lock 和 compdb。详见 [CANON.md](CANON.md)。

## 本轮新增

| 类别 | 文件 / 数量 |
| --- | --- |
| 外层清单与锁 | `lua/gcpkg/managed.lua`：`workspace.yaml` / `workspace.lock`、稳定拓扑排序、环检测、`gcpkg.yaml: depends` 隐式边、空列表写 `[]` |
| Git 集成 | `lua/gcpkg/git.lua`：clone / fetch / checkout / rev-parse / dirty / status / recursive submodule sync+update / submodule add+commit / pin 记录 |
| 工作区编排 | `lua/gcpkg/meta.lua`：`workspace new/add/remove/list/graph/status/sync/update/pin/build/inject/submodule`、per-repo 注入、跨项目 prefix 导出、统一 compdb |
| 依赖注入 | `lua/gcpkg/inject.lua`：CMake toolchain/cache、Meson native、GN `.gni`/args、Makefile flags、pkg-config 链接、`GCPKG_*` / `CANON_*` env、deps/canon JSON、wrappers |
| 内层驱动 | `lua/gcpkg/inner.lua`、`lua/gcpkg/detect.lua`、`lua/gcpkg/build/auto.lua`：systems chain、token 展开、CMake / Meson / GN / Makefile / Ninja / `canon` / `none` |
| 单项目兼容 | `lua/gcpkg/project.lua`、`workspace.lua`、`cli.lua`：YAML-only 项目、保留 `systems/canon_cmd/commands/projects`、`gcpkg inject`、build/compdb 使用正确 project directory |
| 文档 | `docs/MANAGED_WORKSPACES.md`、`docs/DEPENDENCY_INJECTION.md`、`docs/CANON.md`、本文 |
| 回归 | `tests/r13.sh` + `tests/fixtures/r13-workspace/`（静态 fixture + 全动态 local-Git 原型） |

最终目录计数：**277 ports / 14 tests / 16 docs / 10 tools / 8 catalogs**。R12 的 277 ports 与 28/28/4527 动态结果保持不变。

## 从干净缓存复现

```bash
cmake -S . -B build && cmake --build build -j
./tests/r13.sh                                  # 纯静态
GCPKG_R13_DYNAMIC=1 ./tests/r13.sh              # 干净 local-Git 工作区真编译
```

动态用例 `tests/fixtures/r13-workspace/dynamic.sh` 不访问网络：它创建 6 个本地 Git origin、两层原始 submodule、一个本地 `fixturemath` port、一个假 `canon` CLI、六仓库 `workspace.yaml`，然后真实执行 workspace 命令与内层构建。`gn` / `meson` 不可用时对应项目自动跳过；最终验收环境 `GN_ON=1 MESON_ON=1`（GN 来自 R12 缓存工具 port），覆盖全部 6 仓库。

## 最终动态结果

```text
277 ports OK
GN_ON=1 MESON_ON=1
graph: 1 core <- []；2..5 四个 app <- [core]；6 final <- [mesonapp,makeapp,canonapp,gnapp]
sync: 6 repositories synchronised, recursive submodules
submodule add: vendor/extra committed by gcpkg
submodule status: 3 pins (vendor/extra, vendor/sub, vendor/sub/nested)
pin / --unpin / re-pin: workspace.yaml commit 写入、清除、再写入
update / status: 6 clean, core submodules=3
dry-run --only=canonapp: core -> canonapp
inject core: fixturemath-1.0.0 installed, 2 compile commands
full build:
  core cmake                 6 compile commands / 4 source directories
  canonapp canon             canon-inner-ok
  canonapp cmake             6 compile commands / 4 source directories
  gnapp gn                   3 compile commands / 2 source directories
  makeapp makefile           3 compile commands / 2 source directories
  mesonapp meson             6 compile commands / 3 source directories
  final none                 2 compile commands / 1 source directories
  unified compile_commands.json: 16 compile commands / 10 source directories
binaries:
  mesonapp        -> meson 237 7
  makeapp         -> make 237 7
  gnapp           -> gn 7
  canonapp        -> canon+cmake 237 7 400
manual flags.mk   -> make 237 7
top-level inject/build/compdb (only gcpkg.yaml, no gcpkg.lua) OK
all 6 repo tracked states clean
round-13 dynamic workspace OK (6 repositories, 16 compile commands)
```

`237 = fixturemath 7 + sub 30 + nested 200`，说明 catalog port、`core` 静态库、递归子模块头文件确实进入下游；`400` 来自 `canon` 先生成 `canon_generated.h`、CMake 随后编译。统一 compdb 每条 `file` / `directory` 都是绝对路径且文件存在。

## 逐项断言

- **Git**：`workspace sync / update / status / pin / --unpin / submodule sync / status / pin / add --git-commit` 全部通过；`workspace.lock` 记录 6 个仓库 commit、3 个 submodule pin、resolved `fixturemath-1.0.0`；全流程后 `git status --porcelain --untracked-files=no` 对每个仓库为空。
- **拓扑/顺序**：静态 fixture 验证 `core -> app -> leaf`、`gcpkg.yaml: depends` 隐式边；两节点循环被 `dependency cycle: a -> b -> a` 拒绝；`--only=canonapp --dry-run` 只列 core → canonapp；full build 按 `core → canonapp → gnapp → makeapp → mesonapp → final` 稳定顺序执行。
- **注入语法**：`bash -n` 全部 wrappers/env；`cmake -P` 解析 toolchain/cache；Meson 真 `setup --native-file`；缓存 GN `gn format --stdin` 解析 `.gni` 与 args；`gcpkg-deps.json` / `gcpkg-canon.json` 由 Python 解析，`inner_package_manager == "canon"`；source env 后 `GCPKG_INJECT_DIR`、`CANON_*`、`CPPFLAGS`、`PKG_CONFIG_PATH` 均非空。
- **链接顺序**：`link.txt` 中 `main.cc.o` 在 `-lcore -lfixturemath` 之前；`CMAKE_CXX_FLAGS` 与 `CMAKE_EXE_LINKER_FLAGS` 各只有一份 include/libdir；`-l...` 走 `CMAKE_C/CXX_STANDARD_LIBRARIES*`，不再放 `CMAKE_EXE_LINKER_FLAGS_INIT`。Meson / Makefile / canon+CMake 四种链路均真运行。
- **Makefile flags**：`gcpkg-flags.mk` 使用 GNU make 原始值（不再包含 shell 单引号），手工 `include` 后也能 `cc ... -lcore -lfixturemath` 编译并运行。
- **兼容**：`gcpkg add/remove` 不丢 YAML-only 项目的 `system`、`canon_cmd`、`commands`；`workspace add/remove` 不丢 `workspace.yaml` 的 `systems`、`canon_cmd`、`commands`；`gcpkg inject --install` 写 `gcpkg.lock`；`gcpkg build` / `gcpkg compdb` 在没有 `gcpkg.lua` 时自动驱动内层 Makefile；项目私有 port 与 proxy 继承原有代码路径。
- **`canon` 名称**：源码、CLI help、fixture `canonfile`、`gcpkg-canon.json`、环境变量和文档全部使用 `canon`；tests 明确断言，防止日后静默改名。

## 过程中修掉的真实缺陷

1. 静态链接失败：`-lcore -lfixturemath` 曾出现在 object 文件之前；改走 CMake `CMAKE_*_STANDARD_LIBRARIES*`，并用 `GCPKG_INJECT_DIR` guard 避免 toolchain 与 `-C cache` 重复注入 flags。
2. Meson machine file 用 JSON 双引号被 `meson setup` 拒绝；改成 Meson/Python 风格单引号数组。
3. `gcpkg build` / `compdb` 的顶层 fallback 曾把路径解析到 origin 仓库；统一改用 `project_dir(o)`。
4. `workspace pin` 曾只改副本；改为遍历 `data.repos` 真表，`--unpin` 清除 commit，再 `pin` 可写回。
5. `workspace.lock` 空列表曾输出 `{}`；`lock_list` 改为 `[]`。
6. `gcpkg-flags.mk` 曾把整个 flag 字符串 shell-quote，手工 `include` 后把单引号传给编译器；改为 GNU make 原始值并加入动态手工编译断言。

## 与其它文档

- 命令、目录、lock 字段：[MANAGED_WORKSPACES.md](MANAGED_WORKSPACES.md)
- 生成文件与变量：[DEPENDENCY_INJECTION.md](DEPENDENCY_INJECTION.md)
- `canon` 边界与 skipped-question 约束：[CANON.md](CANON.md)
- 前一轮 GN / 28 port 动态结果：[GN.md](GN.md) 与 [ROUND12_LIBRARIES.md](ROUND12_LIBRARIES.md)
