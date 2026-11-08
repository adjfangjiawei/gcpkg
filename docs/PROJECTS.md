# 项目工作流：像 pnpm 一样创建项目、添加库、指定版本

第八轮之前，gcpkg 主要是一个「库仓库 + 项目构建器」：手写 `gcpkg.lua` /
`gcpkg.yaml`，然后 `gcpkg build`。现在补上 pnpm 式的命令行工作流，并明确
**项目特有 vs 公有**、**每个项目各自依赖不同的库**、**每个项目各自锁定不同
版本** 这三件事。

一库仍然是 `build.lua` + `features.yaml` 两个文件；项目仍然是
`gcpkg.lua` + `gcpkg.yaml`，只是多了一个 `gcpkg.lock`。引擎改动全部是通用
能力，没有为某个库写特判，上游源码依旧一行未改。

## 命令速查

```bash
gcpkg new apps/demo --name=demo       # 脚手架：gcpkg.lua / gcpkg.yaml / src/main.c / gcpkg-ports/
gcpkg init                            # 在当前目录做同样的事
gcpkg add zlib@1.2.13 -C apps/demo    # 添加到「这个项目」的依赖清单
gcpkg add libnvme -C apps/demo        # 不写版本 = 用 port 默认版本
gcpkg add --local mylib -C apps/demo  # 创建项目私有 port（一库两文件）
gcpkg add -g bzip2                    # 添加到用户级「公有」依赖清单
gcpkg remove zlib -C apps/demo
gcpkg list -C apps/demo               # 依赖、作用域、解析版本、lock
gcpkg versions zlib                   # 这个 port 声明了哪些版本、来自哪个 URL
gcpkg install -C apps/demo            # 只安装项目全部依赖（等同 pnpm install）
gcpkg build apps/demo                 # 装依赖 + 编译项目 + 合并 compile_commands.json
```

`-C DIR` / `--dir=DIR` 等价于 `pnpm -C`：从仓库根目录操作别处的项目。
`gcpkg add` 也支持一次多个库：`gcpkg add zlib@1.2.13 jansson@2.14`。
`gcpkg install PORT@VERSION` 保持原义（安装单个库到 store）；**不带参数**
时才是「安装当前项目的全部依赖」。

## 两种「项目特有 / 公有」都要区分

### 1. port（库定义）的作用域

查找顺序是**第一个命中即生效**：

| 优先级 | 作用域 | 位置 | 谁可见 |
| --- | --- | --- | --- |
| 1 | `project` | `<project>/gcpkg-ports/<name>/` | 只有这个项目 |
| 2 | `user` | `$GCPKG_HOME/ports/<name>/`（默认 `~/.gcpkg/ports/`） | 你这台机器上的所有项目 |
| 3 | `public` | `--ports=DIR`、`GCPKG_PORTS`、引擎自带 `ports/` | 所有项目 |

`gcpkg new` 会建好 `gcpkg-ports/` 并写进 `gcpkg.yaml` 的 `ports:`，也可以
在 `ports:` 里列多个目录（含项目外的共享目录）。`gcpkg add --local NAME`
会在这个目录里创建 `build.lua` + `features.yaml`：如果公有 registry 里已有
同名 port，就**复制那两个文件**过来供你改；没有就生成模板。于是某个项目
可以为 `zlib` 换 URL、换编译选项、甚至换版本表，而其它 144 个项目的
`zlib` 完全不受影响。`gcpkg list` 用 `[project]` / `[user]` / `[public]`
标出每个依赖实际命中的作用域，`gcpkg doctor` 打印完整 roots 顺序。

### 2. 依赖清单的作用域

| 清单 | 位置 | 生效条件 |
| --- | --- | --- |
| 项目特有 | `<project>/gcpkg.yaml` 的 `dependencies:` | 默认，只对这一个项目生效 |
| 公有（用户级） | `$GCPKG_HOME/gcpkg.yaml` 的 `dependencies:` | 项目显式写 `inherit_global: true` 才继承 |

默认 **不继承**，这样「不同项目依赖不同库」是天然成立的：A 项目只写
`libnvme`，B 项目只写 `jansson`，互不影响。需要一组公共底座时，用
`gcpkg add -g` 写全局清单，再让需要的项目 `inherit_global: true`；
同名依赖**项目声明优先**，所以项目也能单独覆盖全局版本。

`gcpkg add` / `remove` 只改 `gcpkg.yaml` 里被标记包裹的托管区块：

```yaml
# --- gcpkg managed dependencies (use `gcpkg add` / `gcpkg remove`) ---
dependencies:
  - zlib@1.2.13
  - jansson@2.14
# --- end gcpkg managed dependencies ---
```

区块之外的 `project`、`version`、`ports`、`features`、注释都保留；给早期
手写的项目第一次执行 `add` 时会自动规范化成这个格式并提示。

## 不同项目用不同版本

### 声明（port 侧，仍然一库两文件）

在 `features.yaml` 里加 `versions:`，每个版本给出**真实 URL + SHA256**：

```yaml
versions:
  "1.3.1":
    source:
      url: "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz"
      sha256: "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
  "1.2.13":
    source:
      url: "https://github.com/madler/zlib/releases/download/v1.2.13/zlib-1.2.13.tar.gz"
      sha256: "b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30"
```

`build.lua` 完全不用改（它仍是默认版本的构建描述）。
`features.resolve()` 会把 `versions:` 当元数据忽略，所以它不会伪装成一个
feature；`gcpkg features zlib` 只列出真正的特性开关。

第七轮之前 `gcpkg install zlib@1.2.13` 有个隐患：版本只改了缓存 key，
下载的仍是 `build.lua` 里的默认 tarball。现在 `@version` 会**真正替换
`ctx.source` 和 `ctx.version`**，并生成独立的 `zlib-1.2.13` manifest /
prefix / 源码目录；**未声明的版本直接报错**并列出可用版本，不再假装成功。
版本也允许覆盖 `dependencies`（不同上游版本依赖不同时有用）。

本轮实际声明并实测 URL/SHA256 的版本：

| port | 默认 | 额外版本 |
| --- | --- | --- |
| `zlib` | 1.3.1 | 1.2.13（GitHub）、1.2.12 / 1.2.11（zlib.net fossils） |
| `jansson` | 2.15.1 | 2.14 / 2.13.1 / 2.12（GitHub codeload tag） |

其余 143 个 port 保持单版本，`name` 不带 `@` 时走 `build.lua` 默认值。

### 使用（项目侧）

```bash
gcpkg new apps/v1 && gcpkg add zlib@1.2.13 -C apps/v1
gcpkg new apps/v2 && gcpkg add zlib@1.3.1 jansson@2.14 -C apps/v2
gcpkg build apps/v1
gcpkg build apps/v2
```

两个项目同时存在、互不串味：`store/manifest/` 里同时有
`zlib-1.2.13.json` 和 `zlib-1.3.1.json`，各自的 `compile_commands.json`
只包含对应版本的源码路径。`gcpkg add zlib@9.9.9` 会拒绝：

```
port 'zlib' has no version '9.9.9'. Available: 1.2.11, 1.2.12, 1.2.13, 1.3.1.
Add one to .../ports/zlib/features.yaml under `versions:`.
```

### 锁文件

`<project>/gcpkg.lock` 是 JSON，记录本项目的依赖规格、`inherit_global`、
port roots、store 路径，以及**实际解析出的** `key / version / scope /
port_dir / compdb_entries`：

```json
{
  "project": "v1",
  "dependencies": ["zlib@1.2.13"],
  "inherit_global": false,
  "resolved": [
    { "key": "zlib-1.2.13", "scope": "public", "compdb_entries": 70, ... }
  ]
}
```

`add` / `remove` 会把 resolved 清空并标记 `pending: true`；
`install` / `build` 重新写满。`gcpkg list` 把 lock 内容打印出来。建议把
`gcpkg.lock` 提交到版本库（`gcpkg new` 生成的 `.gitignore` 不忽略它），
这样协作时每个项目用哪个版本是可复现的；其中的本机路径会写成 `./...`
（项目内）或 `~/...`（家目录下），不会把绝对路径硬编码进去。仓库自带的
`examples/*` 每次构建都会重写自己的 lock，仓库根 `.gitignore` 单独忽略了它们。

## 实测结果（本轮）

静态：`./tests/projects.sh` exit=0，覆盖 145 ports OK、`graph udisks2`
含 liburing、`new` 骨架、两项目不同版本、版本替换、未声明版本拒绝、
`--local` 私有 port、全局清单 opt-in、`remove`、托管区块不破坏 yaml、
`versions` / `features` 分离。

动态（`GCPKG_PROJECT_DYNAMIC=1 ./tests/projects.sh`）exit=0：

```
v1 -> zlib-1.2.13: 71 merged compile commands
v2 -> zlib-1.3.1: 127 merged compile commands
  distinct resolved keys: zlib-1.2.13 vs ['zlib-1.3.1', 'jansson-2.14']
```

三个库从干净源码真编译：`zlib-1.2.13` 70 条、`zlib-1.3.1` 62 条、
`jansson-2.14` 64 条编译命令。`gcpkg install`（无参）先装好 v2 的两个
依赖，随后 `gcpkg build` 命中缓存并合并出项目 + 依赖的编译数据库；
v1 的 compdb 不含 `zlib-1.3.1`，v2 的 compdb 不含 `zlib-1.2.13`。

只做了静态声明、未逐个真编译的版本：zlib 1.2.12 / 1.2.11、
jansson 2.15.1 / 2.13.1 / 2.12（URL 与 SHA256 都实测过，但按前面的约定
不谎报动态通过）。你在本机 `gcpkg add zlib@1.2.12` 即可验证。

## 实现落点

| 文件 | 作用 |
| --- | --- |
| `lua/gcpkg/workspace.lua` | 新模块：new/add/remove/list、三作用域 roots、托管区块、全局清单、版本目录、lock、无参 install |
| `lua/gcpkg/port.lua` | `name@version` 真正替换 source/version/dependencies；未声明版本报错 |
| `lua/gcpkg/features.lua` | 元数据键过滤，避免 `versions:` 被当成 feature |
| `lua/gcpkg/project.lua` | 构建时应用项目 roots、合并 opt-in 全局依赖、写出 lock |
| `lua/gcpkg/cli.lua` | 新命令与 `-C/--local/-g/--name` 选项、统一 roots 计算 |
| `ports/zlib/features.yaml`、`ports/jansson/features.yaml` | 真实多版本声明示例 |
| `tests/projects.sh` | 静态 + 动态回归 |
