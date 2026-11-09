# 诊断

```bash
gcpkg doctor
gcpkg proxy --check
gcpkg store show
gcpkg check --ports ./ports
gcpkg graph PORT --ports ./ports
gcpkg ports --ports ./ports
```

`doctor` 会显示二进制、当前 clang 编译器、版本化探查来源、交叉 target/sysroot、LLVM root、拦截层、store 来源、port roots、代理与代理监听状态。`check` 验证所有 port 的两个文件、依赖可解析性与 YAML / Lua 格式。`gcpkg toolchain` 只显示编译器/交叉配置。

## 常见问题

### `port not found`

检查 `--ports` / `GCPKG_PORTS`，以及项目的 `gcpkg-ports/` 和用户级 `$GCPKG_HOME/ports/`。`gcpkg doctor` 会按优先级列出实际 roots。

### 依赖版本不符合预期

运行 `gcpkg list <project>` 与 `gcpkg versions PORT`。项目级声明优先于用户级清单，`gcpkg.lock` 记录上次解析结果；修改依赖后重新运行 `gcpkg install` 或 `gcpkg build`。

### 下载失败

先用 `gcpkg proxy` 查看生效代理，再用 `gcpkg proxy --check` 验证代理监听是否可连接；必要时用 `--proxy`、`--no-proxy` 或 `GCPKG_PROXY` 覆盖。下载不再只依赖 `*_proxy` 环境变量：`curl` 使用 `-q -K` 私有配置，`CURL_HOME` 覆盖构建钩子内的 curl，Git 使用 `GIT_CONFIG_*` 显式配置 `http.proxy`，因此继承的 `~/.curlrc`、`NO_PROXY=*`、`~/.gitconfig` 或封装脚本不能把已设置的代理绕掉。凭据不会打印到日志；网络问题可结合 `gcpkg --verbose` 与 store 中的日志目录定位。gcpkg 会在下载和 `git clone` 前做一次快速代理预检，无法连接时直接给出诊断。

### 终端停在 `downloading ...`

`downloading` 只表示请求开始。完成后会依次打印：

```text
[gcpkg:info] downloaded 11.2 MiB in 1.3s (8.6 MiB/s) -> <store>/cache/...
[gcpkg:step] extracting cmake-3.31.6.tar.gz (11.2 MiB) -> <store>/src/...
[gcpkg:info]   expanding source tree: progress is printed while tar runs
tar:   expanding source tree: R: 20459520 (20MiB, 166MiB/s)
[gcpkg:info] extracted cmake-3.31.6.tar.gz in 2.1s
```

这些阶段同时出现在终端与 `<store>/logs/<port>.log`。`cloning` / `cloned` 与 `cached` / `reusing prepared sources` 也有同样的阶段日志，不会只显示一次 `downloading` 就沉默。

旧行为用 GNU tar 默认参数逐条目恢复 owner、权限、mtime、ACL、SELinux 与 xattr。CMake 源码归档约 2.9 万条目，本地 `strace` 实测会多出约 8 万次元数据系统调用；在元数据开销高的挂载盘上，网络流量停止后磁盘仍会忙很久。现在解压使用 `-m --no-same-owner --no-same-permissions --no-acls --no-selinux --no-xattrs`，只写文件内容，并用 `--checkpoint` 周期性打印已读取字节与速率：系统调用约减半，且能看出仍在推进。源码构建不需要归档里的 owner/mtime/ACL 元数据。

### `Compatibility with CMake < 3.5 has been removed`

CMake 4 移除了对 `cmake_minimum_required(VERSION < 3.5)` 的兼容，老版本上游库（例如旧 zlib）会在 configure 阶段失败。gcpkg 会检测 `cmake --version`：当主版本大于等于 4 时，统一为所有 CMake port 与内层构建传入 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`，并在注入环境与构建子进程中设置同名环境变量。无需为单个 port 改 `CMakeLists.txt`。

如果调用了自定义 CMake 脚本或手工执行 `cmake`，请 source 生成的 `gcpkg-env.sh`，或自行设置 `CMAKE_POLICY_VERSION_MINIMUM=3.5`。用户显式提供的同名 `-D` / 环境变量优先。CMake adapter 还会对重复的 `-DNAME=VALUE` 去重（最后一个生效），因此特性参数可以覆盖 port 的默认值，不会在命令行里重复出现。

### 找不到 clang / 不想用 gcc

默认不会回退到 `cc`/`gcc`/`g++`/`cl.exe`。若出现 `no clang compiler found for cc`，安装官方 LLVM 二进制（Linux/WSL）：

```bash
gcpkg llvm show
gcpkg llvm install 23 --dry-run   # 先查看官方脚本接线
gcpkg llvm install 23            # wget https://apt.llvm.org/llvm.sh + sudo ./llvm.sh 23
gcpkg llvm use /usr/lib/llvm-23
gcpkg toolchain
gcpkg install llvm --ports ./ports
```

也可用 `--cc` / `--cxx`、`GCPKG_CC` / `GCPKG_CXX` 或 `compiler.cc/cxx` 明确选择。`CC=cc`、`CC=gcc`、`CC=cl.exe` 等系统默认值会被忽略；只有 `GCPKG_ALLOW_GCC_FALLBACK=1` 才允许显式 gcc 兜底。Windows 静态策略同样是 clang，WSL 与 Linux 无区别。详见 [TOOLCHAIN.md](TOOLCHAIN.md)。

### 端口构建失败但源码已下载

检查 `<store>/logs/`，确认 `setup-gcpkg-toolchain.sh` 中的系统组件是否齐备。需要强制重建时使用 `--no-cache`。某个 port 的编译选项可在 `build.lua` 的 `cmake.defines`、`meson.options`、`make.vars` 或 `features.yaml` 中调整。

### clangd 找不到依赖源码

运行 `gcpkg compdb <project>` 重建总库，并确认 `compile_commands.json` 与 `.clangd` 位于项目根。依赖源码保存在 store 中，不要移动或删除已安装 port 的 `src/` 目录。

### Conan 命令未被找到

设置 `CONAN_CMD`，或在 `gcpkg.yaml` / `workspace.yaml` 中写 `conan_cmd` / `commands.conan`。gcpkg 会生成 `gcpkg-conan.json` 与 `CONAN_*` 变量，但不会猜测 Conan CLI 语法。

### 工作区 submodule 与 lock 不一致

按提示运行 `gcpkg workspace update -C ws` 或 `gcpkg workspace submodule sync <repo> -C ws`，然后重新查看 `workspace.lock`。显式 `commit:` 始终优先。
