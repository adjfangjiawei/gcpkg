# 编译器、LLVM 与交叉编译

`gcpkg` 的编译器选择、版本化 clang 探查、LLVM 接入、交叉目标与构建系统接线统一由 `lua/gcpkg/toolchain.lua` 管理。构建时只有一份生效配置会贯通 `gcpkg.sys.compiler`、`GCPKG_CC_REAL/GCPKG_CXX_REAL`、拦截 wrapper、`CC/CXX`、CMake/Meson/Autotools/Makefile、fingerprint 与 `compile_commands.json`。

## 默认策略

- **默认 clang，不是 gcc/MSVC**：自动探查 `clang`、`clang++`、`clang-N`、`clang++-N`、`clang-cl[-N]`、`clang-cpp[-N]`（含 Windows 静态分析的 `.exe`），优先选版本号最高且 C/C++ 成对的版本，例如 `clang-23` + `clang++-23` 或 `clang-cl-23` + `clang-cpp-23`；`clang++` > `clang-cpp` > `clang-cl` 的 C++ 驱动优先级是确定的。
- 也会扫描 `GCPKG_LLVM_HOME`/`LLVM_HOME` 和 `/usr/lib/llvm-*/bin`、`/opt/llvm-*/bin`，因此 apt.llvm.org 只安装带版本号的编译器也能被发现。
- 找不到 clang 时构建会**报错并给出安装/选择方法**，不会悄悄回退 `cc`/`c++`/`gcc`/`g++`；只有显式 `GCPKG_ALLOW_GCC_FALLBACK=1` 才允许 gcc 作为最后手段。
- 环境里的 `CC=cc`、`CC=gcc`、`CC=cl.exe` 等发行版/Visual Studio 默认值会被忽略；显式 `--cc`、`GCPKG_CC`、项目/用户配置仍然可以选择任意编译器。
- **Windows 只需要静态策略正确**：`gcpkg.sys.os()` 返回 `windows` 时默认仍是 clang，拒绝 `cl.exe`/MSVC；不做原生 Win32 运行时移植。**WSL 与 Linux 完全同一条运行路径**，没有 WSL 特例。

查看当前选择：

```bash
gcpkg toolchain
gcpkg doctor
```

`toolchain` 显示 cc/cxx、来源、host/target triple、sysroot、交叉前缀、编译 flags、LLVM root，以及生成的 CMake toolchain / Meson cross file 路径；`doctor` 也会显示同一份工具链信息。

## 配置优先级

从高到低：

| 优先级 | 来源 | 示例 |
| --- | --- | --- |
| 1 | CLI | `--cc=/usr/bin/clang-23 --cxx=/usr/bin/clang++-23` |
| 2 | 项目 | `<project>/gcpkg.yaml` 或 `workspace.yaml` 的 `compiler:` / `toolchain:` 块 |
| 3 | 用户 | `$GCPKG_CONFIG` / `$XDG_CONFIG_HOME/gcpkg/config.yaml` 的 `compiler:` 块 |
| 4 | 环境变量 | `GCPKG_CC`、`GCPKG_CXX`、`GCPKG_TARGET`、`GCPKG_SYSROOT`、`GCPKG_CROSS_PREFIX`、`GCPKG_LLVM_HOME`；`CC/CXX` 仅在非默认值时生效 |
| 5 | 自动探查 | PATH / LLVM root 中版本最高的 clang 对 |

用户配置示例：

```yaml
store: "/home/me/.cache/gcpkg-store"
compiler:
  cc: "/usr/lib/llvm-23/bin/clang-23"
  cxx: "/usr/lib/llvm-23/bin/clang++-23"
  llvm_home: "/usr/lib/llvm-23"
  target: "aarch64-linux-gnu"
  sysroot: "/srv/aarch64/sysroot"
  cross_prefix: "aarch64-linux-gnu-"
```

项目 `gcpkg.yaml` / `workspace.yaml` 可以使用同名 `compiler:` 或 `toolchain:` 块覆盖用户配置。`--target` 与 `--triple` 是别名；`--cross-prefix` 未给出时默认是 `<target>-`。

## LLVM port（非源码编译）

`ports/llvm` 是 `gcpkg.build.external` 外部 SDK port：它不下载 LLVM 源码、不 bootstrap，也不修改 SDK；安装时校验 `GCPKG_LLVM_HOME` / `LLVM_HOME` / `LLVM_ROOT` 或自动探测 `/usr/lib/llvm-N`，然后导出 `bin/`、`include/`、`lib/`。

```bash
# 查看已安装 LLVM root 与官方安装命令（WSL/Linux 一致）
gcpkg llvm show

# 只打印接线，不执行（测试/CI 可验证）
gcpkg llvm install 23 --dry-run

# Linux/WSL：使用官方二进制安装脚本，不是源码编译
# wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && sudo ./llvm.sh 23
gcpkg llvm install 23

# 选择已安装的二进制树（写入用户 config.yaml）
gcpkg llvm use /usr/lib/llvm-23
gcpkg llvm unset

# 安装外部 port，导出 clang/llvm-ar 等给依赖
gcpkg install llvm --ports ./ports
```

`gcpkg externals` 会静态列出 `llvm` 与 `GCPKG_LLVM_HOME`；`tools/llvm-install.sh` 只调用 `wget https://apt.llvm.org/llvm.sh` 和官方脚本。原生 Windows 的静态提示是安装 LLVM 二进制并用 `gcpkg llvm use <dir>`，没有额外运行时分支。

## 交叉编译

```bash
gcpkg build apps/demo \
  --target=aarch64-linux-gnu \
  --sysroot=/srv/aarch64/sysroot \
  --cross-prefix=aarch64-linux-gnu- \
  --cc=/usr/lib/llvm-23/bin/clang-23 \
  --cxx=/usr/lib/llvm-23/bin/clang++-23
```

发生的事：

1. `--target` / `--triple` 解析 arch、system、CPU family；`--sysroot` 校验目录存在。
2. `toolchain.env()` 下发 `--target=...`、`--sysroot=...` 到 `CFLAGS/CXXFLAGS/LDFLAGS` 与 `GCPKG_COMPILER_FLAGS`；`gcpkg-intercept` 把这些 flags 插入真实编译器 argv（并去重），因此拦截 JSONL、manifest compdb、项目 `compile_commands.json` 与 clangd 都保留目标信息。
3. `GCPKG_CC_REAL/GCPKG_CXX_REAL` 指向实际 clang；`CC/CXX` 仍指向拦截 wrapper；手写 Makefile 的默认编译器也改成 clang。
4. CMake adapter 生成 `-DCMAKE_TOOLCHAIN_FILE=<store>/toolchain-<triple>.cmake`，设置 `CMAKE_SYSTEM_NAME/PROCESSOR`、编译器、`*_COMPILER_TARGET`、`CMAKE_SYSROOT` 与 `CMAKE_FIND_ROOT_PATH`；端口/项目自带 toolchain 会 chain-load，不会丢掉依赖注入。在 gcpkg 构建环境里优先使用 `CC/CXX` 拦截 wrapper（`GCPKG_*_REAL` 指向真实 clang），使 CMake 编译器探测也进入 intercept JSONL；注入的 `gcpkg-toolchain.cmake` 只追加 sysroot 到 `CMAKE_FIND_ROOT_PATH`，不覆盖依赖 prefix 或 `*_FLAGS_INIT`。
5. Meson adapter 生成 `--cross-file=<store>/meson-<triple>.ini`，含 `[binaries]`、`c_args/cpp_args`、`[host_machine]`；内层项目使用注入的 `gcpkg-cross.ini`。
6. Autotools adapter 传 `--host=<target>` / `--build=<host>`；`PKG_CONFIG_SYSROOT_DIR`、`PKG_CONFIG_LIBDIR` 与 `GCPKG_CROSS_PREFIX` 同步下发。
7. port fingerprint 包含编译器路径、target、sysroot、前缀、LLVM root 与 flags；换编译器或换目标会重新构建，不会复用旧缓存。

`gcpkg inject` 生成的 `gcpkg-toolchain.cmake` 也会追加交叉设置，`gcpkg-env.sh` 导出 `GCPKG_MESON_CROSS_FILE`、`GCPKG_COMPILER_FLAGS`、`GCPKG_CROSS_PREFIX`、`GCPKG_SYSROOT` 等变量；wrapper 的 `--cross-file` 只在交叉时启用。

## 故障排查

```text
no clang compiler found for cc (looked for clang[-N] / clang++[-N] ...)
```

按提示安装官方 LLVM 二进制、`gcpkg llvm use DIR`、设置 `--cc/--cxx` 或 `compiler.cc/cxx`。如果确实要 gcc，必须显式 `GCPKG_ALLOW_GCC_FALLBACK=1`；默认绝不会选 gcc/MSVC。更多见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

## 验证

`tests/compiler-toolchain.sh` 与 `tests/fixtures/lua-unit-compiler.lua` 覆盖：版本化 clang 对（`clang-23`/`clang++-23` 与 `clang-cl-99`/`clang-cpp-99`）、gcc/MSVC 默认值被拒绝、Windows 静态分支与 WSL==Linux、CLI > project > user > env（含非默认 `CC/CXX` 与配置持久化）、target/sysroot/CMake toolchain/Meson cross file/Autotools args、注入 CMake 交叉设置不覆盖依赖 flags、LLVM port 与 `llvm-install.sh` 接线、真实 clang 编译命令 + compdb + 构建耗时。
