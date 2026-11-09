# 依赖注入

`gcpkg inject` 与 `workspace build` 会把同一份依赖信息写成各构建系统原生格式。生成目录默认是 `<project>/.gcpkg/inject/`，可通过 `--out=DIR` 覆盖。

```bash
gcpkg inject apps/demo --install --system=cmake
gcpkg workspace inject core -C ws
gcpkg build apps/demo --system=conan,cmake
```

## 生成文件

| 文件 | 适用工具 | 内容 |
| --- | --- | --- |
| `gcpkg-toolchain.cmake` | CMake | toolchain、prefix、用户原 toolchain 的 chain-load |
| `gcpkg-cache.cmake` | CMake | cache 变量与 `CMAKE_EXPORT_COMPILE_COMMANDS` |
| `gcpkg-meson.ini` | Meson | native file 中的编译 / 链接参数与 `cmake_prefix_path` |
| `gcpkg-cross.ini` | Meson（交叉） | `[binaries]`、cross flags、`[host_machine]`；以 `--cross-file` 使用 |
| `gcpkg-gn.gni` / `gcpkg-gn-args.gn` | GN | 可声明的 `gcpkg_*` args |
| `gcpkg-flags.mk` | GNU make | 原始 GNU make 变量，供 `-include` 使用 |
| `gcpkg-env.sh` | 所有工具 | `GCPKG_*`、`CONAN_*` / 兼容 `CANON_*`、编译与链接 flags |
| `gcpkg-conan-env.sh` / `gcpkg-conan.sh` | Conan | env 与 `CONAN_CMD` wrapper |
| `gcpkg-canon-env.sh` / `gcpkg-canon.sh` | `canon` 兼容别名 | env 与 `CANON_CMD` wrapper |
| `gcpkg-conan.json` | Conan | `inner_package_manager: "conan"` 的完整依赖清单 |
| `gcpkg-canon.json` | `canon` 兼容别名 | 兼容格式的同一份清单 |
| `gcpkg-deps.json` | 任何工具 | 通用 manifest |
| `pkgconfig/` | pkg-config | 聚合各 prefix 的 `.pc` 符号链接 |

## 环境变量

```text
GCPKG_ROOT / GCPKG_PROJECT_DIR / GCPKG_INJECT_DIR / GCPKG_BUILD_DIR
GCPKG_INSTALL_PREFIX / GCPKG_TARGET_TRIPLET / GCPKG_COMPILE_COMMANDS
GCPKG_PREFIX_PATH / GCPKG_CMAKE_PREFIX_PATH / GCPKG_INCLUDE_PATH
GCPKG_LIBRARY_PATH / GCPKG_BINARY_PATH / GCPKG_PKG_CONFIG_PATH
GCPKG_CMAKE_TOOLCHAIN_FILE / GCPKG_CMAKE_CACHE_FILE
GCPKG_MESON_NATIVE_FILE / GCPKG_MESON_CROSS_FILE / GCPKG_GN_GNI / GCPKG_GN_ARGS_FILE / GCPKG_MAKE_FLAGS_FILE
GCPKG_CMAKE_CROSS_FILE / GCPKG_CROSS_PREFIX / GCPKG_SYSROOT / GCPKG_COMPILER_FLAGS / GCPKG_LLVM_HOME
GCPKG_DEPS_JSON / GCPKG_CONAN_JSON / GCPKG_CANON_JSON / GCPKG_ENV_FILE
GCPKG_CPPFLAGS / GCPKG_CFLAGS / GCPKG_CXXFLAGS / GCPKG_LDFLAGS / GCPKG_LDLIBS

CONAN_ROOT / CONAN_PROJECT_DIR / CANON_INSTALL_PREFIX / CANON_DEPS_JSON
CONAN_CMAKE_TOOLCHAIN_FILE / CANON_MESON_NATIVE_FILE / CONAN_GN_GNI / CANON_MAKE_FLAGS_FILE
CONAN_PREFIX_PATH / CANON_INCLUDE_PATH / CONAN_LIBRARY_PATH / CANON_LINK_LIBRARIES
```

每个依赖还提供 `GCPKG_DEP_PREFIX_<NAME>`；每个上游项目提供 `GCPKG_PROJECT_PREFIX_<NAME>` 及对应的 Conan / `canon` 别名。`CPPFLAGS` 等变量保留调用者原值并追加 gcpkg flags；`CC` / `CXX` 不被覆盖，以便编译拦截层继续采集 compdb。

## 各内层系统

- **CMake**：使用 `-C gcpkg-cache.cmake` 注入 toolchain 与 prefix；链接库写入 `CMAKE_C_STANDARD_LIBRARIES` / `CMAKE_CXX_STANDARD_LIBRARIES`，保持静态库顺序。已有 toolchain 会转为 `GCPKG_CHAINLOAD_TOOLCHAIN_FILE`。
- **Meson**：`--native-file=gcpkg-meson.ini` 提供编译 / 链接参数和 `cmake_prefix_path`，原生 compdb 直接合并；交叉时追加 `--cross-file=gcpkg-cross.ini`。
- **GN**：`CPATH`、`LIBRARY_PATH`、`PKG_CONFIG_PATH` 让硬编码编译器的 toolchain 找到依赖；`.gni` 与 args 文件供声明 `gcpkg_*` args 的项目使用。
- **Makefile**：命令行变量覆盖 `CC/CXX/CPPFLAGS/LDFLAGS/LDLIBS/PREFIX`；`make install` 装入 `GCPKG_INSTALL_PREFIX`。
- **Conan**：通过 `CONAN_*`、`gcpkg-conan.json`、`CONAN_CMD` 或 `commands.conan` 接入，不解析 Conan 输出，不改写 `conanfile.py` / `conanfile.txt`。详见 [CONAN.md](CONAN.md)。
- **Ninja**：使用 `ninja -C <src> -j N`，并尝试 `ninja -t compdb` 导出原生 compdb。

## 跨项目依赖

`workspace build` 按拓扑序维护 `projects` 列表。每个项目构建后的 `prefix/include|lib|lib64|bin` 会被扫描，连同静态库名一起注入后续项目的 CMake prefix、Meson native file、GN `.gni`、Makefile flags 与 `LDLIBS`。静态库按「依赖者在前、被依赖者在后」排序。

## 统一 compdb

`GCPKG_COMPILE_COMMANDS` 与 Conan / `canon` 别名指向内层构建目录的 `compile_commands.json`。gcpkg 合并：

1. `gcpkg-intercept` 的 JSONL；
2. CMake / Meson / GN / Ninja 原生 compdb；
3. 每个已安装 port 的 manifest compdb；
4. 托管工作区中先前仓库的 compdb。

单项目模式写 `<project>/compile_commands.json`；工作区模式写工作区根总库，并在 `.gcpkg/compdb/<repo>.json` 保留分库。
