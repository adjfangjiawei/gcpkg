# Conan 集成

Conan 可以作为项目的内层包管理器，与 CMake、GN、Meson 等系统串联。gcpkg 负责外层依赖、Git 仓库、注入文件与统一编译数据库；Conan 继续管理项目自己的 `conanfile.py`、`conanfile.txt` 和生成器。

```text
外层 gcpkg                          内层项目
──────────────────────────────    ──────────────────────────────
Git / submodules / pins            conanfile.py / conanfile.txt / conan.lock
跨项目依赖树 / 构建顺序            Conan 依赖解析与生成器
catalog ports / 统一 compdb         CMakeLists.txt / BUILD.gn / meson.build
gcpkg-conan.json + CONAN_* env  ->  Conan，然后 CMake 等
```

gcpkg 不接管 Conan 的依赖解析，不解析 `conan install` 输出，不改写 Conan 文件，也不向项目仓库写新的构建脚本。涉及内层命令时使用 `conan_cmd` / `commands.conan` 显式调用本机工具。

## 检测与串联

`conanfile.py`、`conanfile.txt`、`conan.lock` 与 `conanfile` 会被识别为 Conan 项目；旧 `canonfile` / `Canonfile` / `canon.*` marker 继续兼容。自动检测时 Conan 排在 CMake / GN / Meson / Makefile 之前。显式声明优先：

```yaml
systems: [conan, cmake]
```

同一个 `ctx.env` 会传给所有内层系统，因此 Conan 生成的文件与随后 CMake / Meson 构建共享 prefix、flags 与注入目录。

## 命令配置

```yaml
# 简写
conan_cmd: ["conan", "install", ".", "--output-folder=@build@"]

# 多步命令
commands:
  conan:
    - ["conan", "install", ".", "--output-folder=@build@"]
    - ["conan", "build", ".", "--output-folder=@build@"]
  cmake: ["cmake", "-S", "@src@", "-B", "@build@"]
```

也可以在调用 gcpkg 前设置：

```bash
export CONAN_CMD="my-conan install --conf @conan@"
gcpkg build apps/demo --system=conan,cmake
```

`gcpkg workspace add --cmd="..."` / `gcpkg build --cmd="..."` 提供单次覆盖。可用 token 包括 `@conan@`、`@conan-json@`、`@conan-env@`、兼容别名 `@canon@`、`@canon-json@`、`@env@`、`@root@`、`@project@`、`@src@`、`@build@`、`@prefix@`、`@inject@`、`@jobs@`、`@toolchain@`、`@cache@`、`@native@`、`@gni@`、`@gnargs@`、`@makeflags@`、`@deps@`、`@compdb@`、`@cc@`、`@cxx@`。

PATH 上存在 `conan` 命令且没有显式配置时，gcpkg 会保守尝试 `conan install . --output-folder=@build@`。没有可用 CLI 时会报错并指向已生成的 `gcpkg-conan.json` 与 `CONAN_*` 变量，不猜测语法。旧 `canon` 可执行文件作为最后的兼容回退。

## 注入接口

`gcpkg-conan.json` 包含 `inner_package_manager: "conan"`、root / project / inject / build / prefix 路径、triplet、文件表、flags、dependencies、projects、systems 与 environment。`gcpkg-canon.json` 是兼容副本；`gcpkg-deps.json` 是通用 manifest。

`gcpkg-env.sh` 同时导出 `CONAN_*`、兼容的 `CANON_*` 与 `GCPKG_*`：

| 类别 | 变量 |
| --- | --- |
| 位置 | `CONAN_ROOT` / `CONAN_PROJECT_DIR` / `CONAN_INJECT_DIR` / `CONAN_INSTALL_PREFIX` |
| 清单 | `CONAN_DEPS_JSON` / `CONAN_ENV_FILE` / `CONAN_COMPILE_COMMANDS` |
| 构建系统 | `CONAN_CMAKE_TOOLCHAIN_FILE` / `CONAN_MESON_NATIVE_FILE` / `CONAN_GN_GNI` / `CONAN_MAKE_FLAGS_FILE` |
| 路径 | `CONAN_PREFIX_PATH` / `CONAN_INCLUDE_PATH` / `CONAN_LIBRARY_PATH` / `CONAN_BINARY_PATH` / `CONAN_PKG_CONFIG_PATH` |
| flags | `CONAN_CPPFLAGS` / `CONAN_CFLAGS` / `CONAN_CXXFLAGS` / `CONAN_LDFLAGS` / `CONAN_LDLIBS` |
| 逐依赖 | `CONAN_DEP_PREFIX_<NAME>` / `GCPKG_DEP_PREFIX_<NAME>` |

`gcpkg-conan-env.sh` source 通用 env；`gcpkg-conan.sh` 是 `CONAN_CMD` 的薄 wrapper。CMake toolchain、Meson native、GN `.gni` 与 Makefile flags 写的是同一份依赖信息，详见 [DEPENDENCY_INJECTION.md](DEPENDENCY_INJECTION.md)。

## 兼容别名

现有工作区中的 `canon` 字段、命令、环境变量与 marker 仍可继续使用；新配置建议统一写 `conan`。两套文件同时生成，便于逐步迁移，不影响项目的 Conan 文件本身。
