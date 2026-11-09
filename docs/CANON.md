# `canon`：项目内层的包管理器

> **名称约束**：`canon` 是用户给出的原词，R13 全文、源码、环境变量、清单和 fixture 都保留这个名称。gcpkg 不把它静默改成 Conan，也不根据拼写猜测它就是 Conan。此前四个澄清问题被 skipped，**不视为用户批准**；本文只把用户后来明确说的话落实为：项目内部保留 CMake / GN / Meson / `canon` / Makefile，gcpkg 作外层维护，依赖注入类似 vcpkg。若将来需要兼容 Conan，只能新增一个显式、可选的 adapter，并继续保留 `canon` 名称与 `CANON_*` 接口。

## 边界

```text
外层 gcpkg                          内层项目（保持原样）
──────────────────────────────    ──────────────────────────────
Git / submodules / pins            canonfile、canon 自己的 CLI / 配置
跨项目依赖树 / 构建顺序            CMakeLists.txt / BUILD.gn / meson.build
catalog ports / 统一 compdb         Makefile / Ninja / 自定义命令
gcpkg-canon.json + CANON_* env  ─► 项目自己的 canon，然后 CMake 等
```

gcpkg **不接管** `canon` 的依赖解析，不解析它的 stdout，不改写 `canonfile`，也不往项目仓库写一个新的构建脚本。`workspace.yaml` 只是外层托管清单；涉及内层命令时用 `canon_cmd` / `commands.canon` 显式调用用户已有的工具。生成物位于 `.gcpkg/`、工作区根 `compile_commands.json` / `.clangd`，或项目已有的 `gcpkg.lock`。

四问 skipped 也不能解读为对「`workspace.yaml` 这个文件名」「Git submodule 范围」「是否生成构建脚本」的批准：R13 的实现把这些都做成可配置、可绕过的外层能力；用户完全可以手写外层清单、使用 `path:` 本地 checkout、让 `systems: ["none"]` 只生成注入文件。

## 检测与运行

`detect.package_managers()` 识别以下 marker（大小写按原样）：

```text
canonfile  Canonfile  canon.toml  canon.json  canon.yaml  canon.lock
```

`detect.build_systems()` 会先返回 `canon`，再返回 CMake / GN / Meson / Makefile 等。若项目不在 `workspace.yaml` 里声明 `systems`，`gcpkg build` 会按这个顺序自动串联；显式声明优先：

```yaml
systems: [canon, cmake]
```

`inner.run()` 对每个系统复用同一份 `ctx.env`：`canon` 先生成头文件 / 写 `CANON_COMPILE_COMMANDS`，随后的 CMake 就能看到 `$ENV{GCPKG_BUILD_DIR}/include`。R13 动态用例中，`canon` 由用户配置的 Python 假 CLI 驱动，接着 CMake 编译并链接 `canonapp`，输出 `canon+cmake 237 7 400`。

## 三种显式配置

```yaml
# 1) 简写：argv 数组，@canon@ 展开为 gcpkg-canon.json 绝对路径
canon_cmd: ["canon", "install", "@canon@"]

# 2) 完整 commands：可为单个系统写多步命令
commands:
  canon:
    - ["canon", "install", "@canon@"]
    - ["canon", "generate", "--out=@build@"]
  cmake: ["cmake", "-S", "@src@", "-B", "@build@"]

# 3) 环境变量：在调用 gcpkg 前设置，也可由 gcpkg-canon-env.sh 继承
# CANON_CMD="my-canon install --config @canon@"
```

`gcpkg workspace add --cmd="..."` / `gcpkg build --cmd="..."` 是单次覆盖。可用 token：`@canon@`、`@canon-json@`、`@env@`、`@canon-env@`、`@root@`、`@project@`、`@src@`、`@build@`、`@prefix@`、`@inject@`、`@jobs@`、`@toolchain@`、`@cache@`、`@native@`、`@gni@`、`@gnargs@`、`@makeflags@`、`@deps@`、`@compdb@`、`@cc@`、`@cxx@`。

若既没有显式命令、PATH 上也没有 `canon` 可执行文件，gcpkg 会报错并指出已经写好的 `gcpkg-canon.json` 与 `CANON_*` 变量，而不是猜测 CLI 语法。只有 PATH 上确有 `canon` 时才保守尝试 `canon install`。

## 注入给 canon 的接口

`gcpkg inject` / `workspace build` 写出的文件中，`gcpkg-canon.json` 含：

```json
{
  "schema": 1,
  "generator": "gcpkg",
  "kind": "dependency-injection",
  "inner_package_manager": "canon",
  "root": "...", "project_dir": "...", "inject_dir": "...",
  "build_dir": "...", "install_prefix": "...", "triplet": "x86_64-linux",
  "files": { "toolchain": "...", "meson": "...", "gn_gni": "...", "canon": "..." },
  "flags": { "prefixes": [], "includes": [], "libdirs": [], "libs": [], "cppflags": "...", "ldlibs": "..." },
  "dependencies": [], "projects": [], "systems": ["canon", "cmake"],
  "environment": { "CANON_PREFIX_PATH": "...", "CANON_LDLIBS": "..." }
}
```

`gcpkg-env.sh` 同时导出 `CANON_*` 与 `GCPKG_*`：

| 类别 | 变量 |
| --- | --- |
| 位置 | `CANON_ROOT` / `CANON_PROJECT_DIR` / `CANON_INJECT_DIR` / `CANON_INSTALL_PREFIX` |
| 清单 | `CANON_DEPS_JSON` / `CANON_ENV_FILE` / `CANON_COMPILE_COMMANDS` |
| 构建系统 | `CANON_CMAKE_TOOLCHAIN_FILE` / `CANON_CMAKE_CACHE_FILE` / `CANON_MESON_NATIVE_FILE` / `CANON_GN_GNI` / `CANON_GN_ARGS_FILE` / `CANON_MAKE_FLAGS_FILE` |
| 路径 | `CANON_PREFIX_PATH` / `CANON_CMAKE_PREFIX_PATH` / `CANON_INCLUDE_PATH` / `CANON_LIBRARY_PATH` / `CANON_BINARY_PATH` / `CANON_PKG_CONFIG_PATH` |
| flags | `CANON_CPPFLAGS` / `CANON_CFLAGS` / `CANON_CXXFLAGS` / `CANON_LDFLAGS` / `CANON_LDLIBS` / `CANON_LINK_LIBRARIES` |
| 逐依赖 / 逐项目 | `CANON_PROJECT_PREFIX_<NAME>`、`GCPKG_DEP_PREFIX_<NAME>`、`GCPKG_PROJECT_PREFIX_<NAME>` |

`gcpkg-canon-env.sh` 只 source `gcpkg-env.sh`；`gcpkg-canon.sh` 是 `CANON_CMD` 的薄 wrapper。CMake toolchain / Meson native / GN `.gni` / Makefile `flags.mk` 也把同一份依赖信息写进各自的原生格式，详见 [DEPENDENCY_INJECTION.md](DEPENDENCY_INJECTION.md)。

## 固定名称的回归

`tests/r13.sh` 断言：

- `lua/gcpkg/inject.lua` 的 `inner_package_manager = "canon"`；
- `tests/fixtures/r13-workspace/static/repos/app/canonfile` 保留 `canon`；
- `workspace add/remove` 与 `gcpkg add/remove` 都保留 `systems: ["canon","cmake"]`、`canon_cmd` 和 `commands`；
- 动态 fixture 的 `gcpkg-canon.json` 中 `inner_package_manager == "canon"`，假 CLI 检查全部 `CANON_*` 变量后才输出 `canon-inner-ok`。

因此后续扩展可以新增显式 Conan adapter，但不能用全局替换把 `canon` 改成别的名字。
