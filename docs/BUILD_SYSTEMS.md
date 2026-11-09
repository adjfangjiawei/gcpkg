# 构建系统

gcpkg 不替换项目或上游库的构建系统。它为每个 port 选择 adapter，把 prefix、依赖、特性参数、编译器拦截层与代理环境传进去，再收集结果。

| 构建系统 | port recipe / 内层 system | 原生 compdb |
| --- | --- | --- |
| CMake | `recipe.cmake` / `cmake` | `CMAKE_EXPORT_COMPILE_COMMANDS` |
| Meson | `recipe.meson` / `meson` | Meson 原生 `compile_commands.json` |
| GN + Ninja | `recipe.gn` / `gn` | `gn gen --export-compile-commands` |
| Autotools | `recipe.autotools` | 拦截层 JSONL |
| 手写 Makefile | `recipe.make` / `makefile` | 拦截层 JSONL |
| 单文件 / 头文件库 | `recipe.header` | probe 编译命令 |
| Ninja | `ninja` | `ninja -t compdb` |
| Python | `recipe.python` | 拦截层 JSONL |
| Cargo | `recipe.cargo` | 拦截层 JSONL |
| Conan | `conan` / `conan_cmd` | 由后续构建系统或拦截层产出 |
| 外部 SDK / pkg-config | `gcpkg.build.external` / `pkgconfig` backend | 按实际构建产生 |

## CMake

port 可在 `cmake.defines` 中写上游选项，并通过 `CMAKE_PREFIX_PATH` 自动获得已安装依赖 prefix。项目模式使用 `gcpkg-toolchain.cmake` 与 `gcpkg-cache.cmake`，把 include、libdir、libs 与链接 flags 注入 CMake。用户已有 toolchain 会通过 `GCPKG_CHAINLOAD_TOOLCHAIN_FILE` 保留。

CMake 4 移除了对 `cmake_minimum_required(VERSION < 3.5)` 的兼容。引擎检测到 CMake 主版本大于等于 4 时，会统一传入 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`，并在注入环境、configure / build / install 子进程中设置同名环境变量；用户显式提供的 `-D` 或环境变量优先。adapter 还对重复的 `-DNAME=VALUE` 去重（最后一个生效）：菜谱默认值与特性参数可以写同名选项，最终命令行只出现一次。以上对所有 CMake port 与内层构建生效，不需要为某个上游库打补丁。

## Meson

`gcpkg-meson.ini` 提供编译 / 链接参数与 `cmake_prefix_path`。Meson 原生 compdb、prefix 与 sysconfdir / localstatedir 都按 gcpkg store 布局设置。

## GN

`recipe.gn` 调用 `gn gen --export-compile-commands`，随后用 `ninja` 构建。`gn`、`ninja` 本身也是源码工具 port。生成的 `.gni` 与 args 文件可向声明 `gcpkg_*` args 的项目提供依赖信息。

## Makefile 与 Autotools

命令行变量覆盖 `CC/CXX/CPPFLAGS/LDFLAGS/LDLIBS/PREFIX`，因此 Makefile 里写死的 `CC=gcc` 也会经过拦截层。Autotools 使用 `--prefix` 安装到该 port 的 prefix；需要 `autoreconf -fi` 的上游可写 `pre_build`。

## 头文件库

`recipe.header` 直接复制头文件与许可证，并编译一个生成的 probe translation unit。这样每个头文件库也有真实的编译命令，clangd 能解析其 include 路径与宏定义。

## 多系统串联

项目可以声明多个内层系统：

```yaml
systems: [conan, cmake]
```

gcpkg 按声明顺序复用同一份 env 和注入目录。Conan 先生成项目需要的文件，CMake 随后读取这些文件。命令可用 `commands` 或 `--cmd` 覆盖；`@build@`、`@prefix@`、`@toolchain@` 等 token 会展开为当前路径。

## 统一数据库

无论编译命令来自原生 compdb 还是拦截层，最终都会归一化 `file` 路径并合并到项目根或工作区根的 `compile_commands.json`。`gcpkg compdb <project>` 可在不重新编译的情况下重建总库。
