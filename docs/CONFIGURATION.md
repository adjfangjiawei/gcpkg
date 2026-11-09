# 配置

## 全局 store

store 是 gcpkg 的工作目录：源码、构建目录、安装 prefix、manifest、编译数据库和日志都放在这里。设置一次后，所有支持 store 的命令共享该目录：

```bash
gcpkg store set ~/.cache/gcpkg-store
gcpkg store show
gcpkg store unset
```

`store set` 把绝对路径写入用户配置文件，配置文件位置为：

```text
$GCPKG_CONFIG
$XDG_CONFIG_HOME/gcpkg/config.yaml
~/.config/gcpkg/config.yaml
```

三者按此顺序选择。`store` 与编译器/交叉编译配置可以共存：

```yaml
store: "/absolute/path/to/store"
compiler:
  cc: "/usr/lib/llvm-23/bin/clang-23"
  cxx: "/usr/lib/llvm-23/bin/clang++-23"
  llvm_home: "/usr/lib/llvm-23"
  target: "aarch64-linux-gnu"
  sysroot: "/srv/aarch64/sysroot"
  cross_prefix: "aarch64-linux-gnu-"
```

命令行参数与环境变量都可以在单次调用中覆盖持久化配置：

| 优先级 | 来源 | 用途 |
| --- | --- | --- |
| 1 | `--store=DIR` | 单次命令、CI、临时 store |
| 2 | `GCPKG_STORE` | 当前 shell 会话 |
| 3 | `GCPKG_HOME` | 旧版兼容变量，同时也是用户级 port / 依赖清单位置 |
| 4 | `config.yaml` 的 `store:` | 用户级持久配置 |
| 5 | `~/.gcpkg` | 未配置时的默认值 |

`gcpkg doctor` 与 `gcpkg store show` 会显示当前目录和来源。

## port 搜索路径

`--ports=DIR[:DIR...]` 与 `GCPKG_PORTS` 指定公有 port 根目录。项目构建时还会按以下顺序查找：

| 优先级 | 作用域 | 位置 |
| --- | --- | --- |
| 1 | project | `<project>/gcpkg-ports/<name>/` |
| 2 | user | `$GCPKG_HOME/ports/<name>/` |
| 3 | public | `--ports`、`GCPKG_PORTS`、引擎自带 `ports/` |

`gcpkg doctor` 会列出实际 roots。覆盖同名 port 时，第一个命中的目录生效。

## 编译器与交叉编译

默认永远是 clang（包括 `clang-23` / `clang++-23` 这类带版本名），不会隐式选 gcc/MSVC。优先级为 CLI > 项目 `gcpkg.yaml`/`workspace.yaml` > 用户 `config.yaml` > 环境变量 > 自动探查：

```bash
gcpkg toolchain
gcpkg build . --cc=/usr/bin/clang-23 --cxx=/usr/bin/clang++-23
gcpkg build . --target=aarch64-linux-gnu --sysroot=/srv/sysroot
gcpkg llvm show
gcpkg llvm install 23 --dry-run
gcpkg llvm use /usr/lib/llvm-23
```

`llvm` 是外部二进制工具 port，不从源码编译；`tools/llvm-install.sh` 使用 `wget https://apt.llvm.org/llvm.sh`。Windows 静态策略同样为 clang、拒绝 `cl.exe`/MSVC；WSL 与 Linux 完全同一路径。完整说明见 [TOOLCHAIN.md](TOOLCHAIN.md)。

## 代理

```bash
gcpkg proxy http://proxy.example:3128 -g
gcpkg proxy http://proxy.example:3128 -C apps/demo
gcpkg proxy --check
gcpkg proxy --unset -g
gcpkg install curl --proxy=http://127.0.0.1:7890
gcpkg install curl --no-proxy
```

项目配置写在 `<project>/gcpkg.yaml`，用户级配置写在 `$GCPKG_HOME/gcpkg.yaml`。凭据不会进入命令行或日志；解析出的代理会以私有 curl 配置和 Git 配置显式下发给所有网络命令，而不是只写环境变量。完整优先级见 [PROXY.md](PROXY.md)。

## 常用环境变量

| 变量 | 含义 |
| --- | --- |
| `GCPKG_CONFIG` | 用户级配置文件路径 |
| `GCPKG_STORE` / `GCPKG_HOME` | store 或旧版工作根目录 |
| `GCPKG_PORTS` | 公有 port roots |
| `GCPKG_PROXY` / `GCPKG_NO_PROXY` | 会话级代理 |
| `GCPKG_PROXY_CHECK` | 设为 `0` 跳过代理监听预检 |
| `GCPKG_RUST_HOME` | Rust 工具链位置，供 external port 使用 |
| `GCPKG_LLVM_HOME` / `LLVM_HOME` | LLVM/Clang 二进制根目录 |
| `GCPKG_CC` / `GCPKG_CXX` | 显式编译器选择 |
| `GCPKG_TARGET` / `GCPKG_TRIPLE` | 交叉目标三元组 |
| `GCPKG_SYSROOT` | 目标 sysroot |
| `GCPKG_CROSS_PREFIX` | 交叉 binutils 前缀（默认 `<target>-`） |
| `GCPKG_COMPILER_FLAGS` | 拦截层注入真实编译器 argv 的 `--target` / `--sysroot` |
| `XDG_CONFIG_HOME` | 用户级配置根目录 |
| `CC` / `CXX` | 仅在不是 `cc`/`gcc`/`cl.exe` 等默认值时视为显式选择；`CC/CXX` wrapper 仍由拦截层保留 |

`gcpkg doctor` 是查看当前生效配置与工具链状态的入口。
