# 依赖注入：gcpkg 在外层，构建系统在内层

R13 的注入目标类似 vcpkg：把 gcpkg 安装好的依赖变成**标准、无需修改项目源码即可消费**的路径和参数。区别是 gcpkg 不只生成 CMake toolchain，还会同时为 GN、Meson、`canon`、Makefile、pkg-config 和编译器环境生成对应文件，并把 dep + 项目源码全部并入统一 compdb。

> 四个澄清问题被 skipped，不视为批准；`canon` 保持用户原词，不假定 Canon=Conan，也不往项目仓库写新的构建脚本。详见 [CANON.md](CANON.md)。

调用入口：

```bash
# 单项目：从 gcpkg.lock（或 --install 先安装）解析真实 manifests
gcpkg inject apps/demo --install --system=cmake
gcpkg inject apps/demo --install --out=.gcpkg/manual --system=canon,cmake

# 不使用 gcpkg.lua 的项目：自动驱动内层系统
gcpkg build apps/demo --system=canon,cmake
gcpkg compdb apps/demo --system=makefile

# 托管工作区：每个 repo 自动获得一份注入目录
gcpkg workspace inject core -C ws
gcpkg workspace build -C ws
```

## 生成目录

默认位于 `<project>/.gcpkg/inject/` 或 `<workspace>/.gcpkg/inject/<repo>/`。所有路径都是绝对路径，`gcpkg-deps.json` / `gcpkg-canon.json` 里也有机器可读副本。

| 文件 | 消费方 | 内容 |
| --- | --- | --- |
| `gcpkg-toolchain.cmake` | CMake | `CMAKE_PREFIX_PATH` / `CMAKE_FIND_ROOT_PATH` / `GCPKG_*` 列表、`CMAKE_C_FLAGS_INIT` / `CMAKE_CXX_FLAGS_INIT`、`CMAKE_*_STANDARD_LIBRARIES`、`PKG_CONFIG_PATH`、可选 chainload |
| `gcpkg-cache.cmake` | `cmake -C` | 无需改 CMakeLists 即设置 `CMAKE_TOOLCHAIN_FILE`、`CMAKE_INSTALL_PREFIX`、`CMAKE_EXPORT_COMPILE_COMMANDS=ON` |
| `gcpkg-cmake.sh` | 手工 CMake | `cmake -C gcpkg-cache.cmake "$@"` |
| `gcpkg-meson.ini` | `meson setup --native-file` | `c_args` / `cpp_args` / `c_link_args` / `cpp_link_args` / `pkg_config_path` / `cmake_prefix_path` / `prefix`（Meson machine file 使用单引号） |
| `gcpkg-meson.sh` | 手工 Meson | 带 `--native-file` 与 `--prefix` 的 `meson setup` |
| `gcpkg-gn.gni` | GN | `gcpkg_include_dirs` / `gcpkg_lib_dirs` / `gcpkg_cflags` / `gcpkg_ldflags` / `gcpkg_deps_json` 等；项目可自行 `import()` |
| `gcpkg-gn-args.gn` | `gn gen --args` | 仅当项目 `declare_args()` 声明 `gcpkg_*` 时由 `gcpkg.inner` 自动传入 |
| `gcpkg-gn.sh` | 手工 GN | `gn gen --export-compile-commands --root=<src>` |
| `gcpkg-flags.mk` | Makefile | `GCPKG_CPPFLAGS` / `GCPKG_LDFLAGS` / `GCPKG_LDLIBS` / toolchain 路径；GNU make 原始值（无 shell 引号），可 `-include` |
| `gcpkg-make.sh` | 手工 make | 把 `CC/CXX/CPPFLAGS/CFLAGS/CXXFLAGS/LDFLAGS/LDLIBS/PREFIX` 作为命令行变量传给 make |
| `gcpkg-env.sh` | 所有工具 | 导出 `GCPKG_*`、`CANON_*`、`CPPFLAGS`、`CFLAGS`、`CXXFLAGS`、`LDFLAGS`、`LDLIBS`、`CPATH`、`LIBRARY_PATH`、`LD_LIBRARY_PATH`、`PKG_CONFIG_PATH`、`CMAKE_PREFIX_PATH`、`PATH` |
| `gcpkg-canon-env.sh` / `gcpkg-canon.sh` | 内层 `canon` | 复用 env，并可用 `CANON_CMD` 调用户自己的 canon 可执行文件 |
| `gcpkg-canon.json` | 内层 `canon` | `inner_package_manager: "canon"`、完整依赖 / 项目 / flags / files / environment 描述 |
| `gcpkg-deps.json` | 任何工具 | 与 canon 清单同源的通用 manifest |
| `pkgconfig/` | pkg-config | 聚合各 prefix 的 `.pc` 符号链接 |

## 注入变量（摘要）

```text
GCPKG_ROOT / GCPKG_PROJECT_DIR / GCPKG_INJECT_DIR / GCPKG_BUILD_DIR
GCPKG_INSTALL_PREFIX / GCPKG_TARGET_TRIPLET / GCPKG_COMPILE_COMMANDS
GCPKG_PREFIX_PATH / GCPKG_CMAKE_PREFIX_PATH / GCPKG_INCLUDE_PATH
GCPKG_LIBRARY_PATH / GCPKG_BINARY_PATH / GCPKG_PKG_CONFIG_PATH
GCPKG_CMAKE_TOOLCHAIN_FILE / GCPKG_CMAKE_CACHE_FILE
GCPKG_MESON_NATIVE_FILE / GCPKG_GN_GNI / GCPKG_GN_ARGS_FILE / GCPKG_MAKE_FLAGS_FILE
GCPKG_DEPS_JSON / GCPKG_CANON_JSON / GCPKG_ENV_FILE
GCPKG_CPPFLAGS / GCPKG_CFLAGS / GCPKG_CXXFLAGS / GCPKG_LDFLAGS / GCPKG_LDLIBS

CANON_ROOT / CANON_PROJECT_DIR / CANON_INJECT_DIR / CANON_INSTALL_PREFIX
CANON_DEPS_JSON / CANON_ENV_FILE / CANON_CMAKE_TOOLCHAIN_FILE
CANON_MESON_NATIVE_FILE / CANON_GN_GNI / CANON_MAKE_FLAGS_FILE
CANON_PREFIX_PATH / CANON_CMAKE_PREFIX_PATH / CANON_INCLUDE_PATH
CANON_LIBRARY_PATH / CANON_BINARY_PATH / CANON_PKG_CONFIG_PATH
CANON_COMPILE_COMMANDS / CANON_CPPFLAGS / CANON_CFLAGS / CANON_CXXFLAGS
CANON_LDFLAGS / CANON_LDLIBS / CANON_LINK_LIBRARIES
```

另外还有每个依赖 port / 上游项目的 `GCPKG_DEP_PREFIX_<NAME>`、`GCPKG_PROJECT_PREFIX_<NAME>`、`CANON_PROJECT_PREFIX_<NAME>`。`CPPFLAGS` 等变量会保留调用者原值并追加 gcpkg flags；`CC` / `CXX` **不覆盖**，以便 `gcpkg-intercept` 继续采集 compdb。

## 各内层系统如何拿到依赖

- **CMake**：`gcpkg build`/`workspace build` 用 `cmake -C gcpkg-cache.cmake` 注入 toolchain、prefix 和 `CMAKE_EXPORT_COMPILE_COMMANDS`。`-l...` 写入 `CMAKE_C_STANDARD_LIBRARIES` / `CMAKE_CXX_STANDARD_LIBRARIES`，位于目标文件之后，静态链接顺序正确。toolchain 仅在环境变量 `GCPKG_INJECT_DIR` 未定义时设置 `CMAKE_*_FLAGS_INIT` / `CMAKE_EXE_LINKER_FLAGS_INIT`，避免与 `gcpkg-env.sh` 已导出的 `CPPFLAGS` / `LDFLAGS` 重复。`CMAKE_TOOLCHAIN_FILE` 原先若指向用户自己的 toolchain，会转为 `GCPKG_CHAINLOAD_TOOLCHAIN_FILE` 被 include。
- **Meson**：`--native-file=gcpkg-meson.ini` 提供编译/链接参数和 `cmake_prefix_path`；Meson 原生 `compile_commands.json` 直接合并。
- **GN**：环境变量 `CPATH` / `C_INCLUDE_PATH` / `LIBRARY_PATH` / `PKG_CONFIG_PATH` 让硬编码 `g++` 的 GN toolchain 也能找到依赖；生成 `.gni` / args 文件供声明了 `gcpkg_*` args 的项目使用；`gn gen --export-compile-commands` + `ninja` 的原生 compdb 合并。
- **Makefile**：命令行变量覆盖 `CC/CXX/CPPFLAGS/LDFLAGS/LDLIBS/PREFIX`，因此 Makefile 里写死的 `CC=gcc` 也会走 `gcpkg-intercept`；`make install` 把产物装进 `GCPKG_INSTALL_PREFIX`。`gcpkg-flags.mk` 则用 GNU make 原始赋值，手工 `-include` 时不会把字面单引号传给编译器。
- **`canon`**：不要求特定 CLI、不解析其输出、不改名；通过 `CANON_*` 环境变量、`gcpkg-canon.json`、`CANON_CMD` 或 `commands.canon` 注入。详见 [CANON.md](CANON.md)。
- **Ninja**：`ninja -C <src> -j N`，并尝试用 `ninja -t compdb` 导出 compdb。

## 多项目 / 依赖树注入

`workspace build` 按拓扑序维护 `projects` 列表。每个项目构建后的 `prefix/include|lib|lib64|bin` 会被扫描，连同静态库名一起注入到后续项目的 `CMAKE_PREFIX_PATH`、Meson native file、GN `.gni`、Makefile flags 与 `LDLIBS`。静态库按「依赖者在前、被依赖者在后」排序，R13 动态用例中 `core` 使用 `fixturemath`，下游得到 `-lcore -lfixturemath`，CMake / Meson / Makefile / canon+CMake 四种链接方式都真跑通。

## 与统一 compdb 的关系

注入目录里的 `GCPKG_COMPILE_COMMANDS` / `CANON_COMPILE_COMMANDS` 指向内层构建目录的 `compile_commands.json`。gcpkg 会合并：

1. `gcpkg-intercept` 的 JSONL（手写 Makefile / CMake compiler probes / canon 内部编译器）；
2. CMake / Meson / GN 原生 compdb；
3. 每个已安装 port 的 manifest compdb；
4. 跨项目先前仓库的 compdb。

单项目模式写 `<project>/compile_commands.json`；托管工作区写工作区根 `compile_commands.json` 和 `.clangd`，并额外保留 `.gcpkg/compdb/<repo>.json`。所有 `file` 均归一化为存在的绝对路径。
