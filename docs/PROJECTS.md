# 项目工作流

gcpkg 提供类似 pnpm 的项目命令：创建项目、添加依赖、选择版本、锁定解析结果、构建项目并生成统一编译数据库。

## 创建与依赖

```bash
gcpkg new apps/demo --name=demo
gcpkg init
gcpkg add zlib@1.2.13 -C apps/demo
gcpkg add jansson@2.14 libnvme -C apps/demo
gcpkg add --local mylib -C apps/demo
gcpkg add -g bzip2
gcpkg remove zlib -C apps/demo
gcpkg list -C apps/demo
gcpkg versions zlib
gcpkg install -C apps/demo
gcpkg build apps/demo --ports ./ports
```

`gcpkg new` 生成 `gcpkg.lua`、`gcpkg.yaml`、`gcpkg.lock` 的骨架、源码目录和 `gcpkg-ports/`。`gcpkg add` 只修改托管依赖区块，保留文件其余内容。`gcpkg install` 不带参数时安装当前项目全部依赖；带 port 名时安装单个 port 到 store。

`-C DIR` 从其他目录操作项目；`-g` 写用户级依赖清单；`--local` 在项目中创建私有 port。

## 两个作用域

port 定义与依赖清单分别有作用域：

| port 作用域 | 位置 | 可见性 |
| --- | --- | --- |
| project | `<project>/gcpkg-ports/<name>/` | 当前项目 |
| user | `$GCPKG_HOME/ports/<name>/` | 本机所有项目 |
| public | `--ports`、`GCPKG_PORTS`、引擎 `ports/` | 所有项目 |

| 依赖清单 | 位置 | 生效条件 |
| --- | --- | --- |
| 项目特有 | `<project>/gcpkg.yaml` 的 `dependencies:` | 默认生效 |
| 用户级 | `$GCPKG_HOME/gcpkg.yaml` 的 `dependencies:` | 项目写 `inherit_global: true` |

同名依赖以项目声明优先。`gcpkg list` 会标出每个依赖实际命中的作用域。

## 版本

```bash
gcpkg versions zlib
gcpkg add zlib@1.2.13 -C apps/demo
gcpkg build apps/demo
```

`PORT@VERSION` 会替换 port 的 `source`、`version` 与可选 `dependencies`，生成独立的 store key、prefix 和 manifest。可用版本由 `features.yaml` 的 `versions:` 声明；未声明的版本会报错并列出备选项。

不同项目可以锁定同一库的不同版本，互不共享 prefix 或 compdb。

## 锁文件

`<project>/gcpkg.lock` 是 JSON，记录依赖规格、`inherit_global`、port roots、store 路径，以及实际解析出的 `key`、`version`、`scope`、`port_dir`、`compdb_entries`。`add` / `remove` 会把 resolved 清空并标记 `pending: true`；`install` / `build` 写回完整结果。锁文件适合提交到版本库，便于协作时复现同一组依赖。

## 项目构建文件

`gcpkg.lua` 可定义 `build(ctx)`；`gcpkg.yaml` 可写 `dependencies`、`features`、`ports`、`system`、`commands` 等字段。只写 `gcpkg.yaml` 时，gcpkg 按声明的 `system` 驱动 CMake、GN、Meson、Conan、Makefile 等内层系统。需要显式构建逻辑时，`ctx.inject`、`ctx.inject_dir` 与 `ctx.inner()` 可访问注入文件和内层命令链。

## 编译数据库与代理

`gcpkg build <project>` 安装依赖、构建项目，写出项目根 `compile_commands.json` 与 `.clangd`。`gcpkg compdb <project>` 只重建数据库。项目级代理配置与依赖清单共用一个 `gcpkg.yaml`，详见 [PROXY.md](PROXY.md)；工作区场景见 [MANAGED_WORKSPACES.md](MANAGED_WORKSPACES.md)。
