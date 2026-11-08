# 架构设计

## 0. 设计原则

1. **一个库一个 build.lua + 一个 features.yaml**。`build.lua` 是行为（源码、依赖、构建步骤），`features.yaml` 是声明式数据（开关、参数、额外依赖）。Lua 负责自由组合，YAML 负责可被工具读写的选择。
2. **上游零修改**。不 fork、不打补丁、不要求上游支持 gcpkg。唯一的注入点是标准环境变量 `CC` / `CXX`（`gcpkg-intercept`）与 `prefix`，几乎所有构建系统都支持。
3. **C++ 只做薄运行时**。加构建系统 / 加包管理器 / 加库，都不需要重新编译 gcpkg 本体。
4. **绝对路径永久有效**。依赖源码解压到固定 store 目录后不删除，编译数据库里的绝对路径始终可解析 —— 这是跨库跳转的关键。
5. **项目也是一等公民**。项目目录里直接写配置就能构建，不需要先"安装成包"。

## 1. 分层

```
┌────────────────────────────────────────────────────────────────────┐
│ 用户数据（纯文本，不需要编译）                                     │
│   ports/<name>/build.lua        ports/<name>/features.yaml          │
│   <project>/gcpkg.lua          <project>/gcpkg.yaml                 │
│   lua/gcpkg/build/*.lua        lua/gcpkg/backends.lua               │
├────────────────────────────────────────────────────────────────────┤
│ Lua 引擎（gcpkg.* 模块，受控沙箱）                                 │
│   cli → project/port → features → net → compdb → backends           │
├────────────────────────────────────────────────────────────────────┤
│ C++ 运行时（gcpkg 二进制）                                        │
│   Lua 5.4 沙箱 / require / loadchunk                                │
│   yaml-cpp → Lua table                                              │
│   sys.exec / capture / fs / symlink / wrapper_bin / compiler         │
├────────────────────────────────────────────────────────────────────┤
│ gcpkg-intercept（独立可执行）                                      │
│   作为 cc / c++ 的符号链接，记录 argv + cwd，然后 exec 真编译器      │
└────────────────────────────────────────────────────────────────────┘
```

### Lua 沙箱

C++ 用 `luaL_loadfile` 载入每个 chunk，把它的第一个 upvalue `_ENV` 换成自建表：

- 允许：`table` / `string` / `math` / `utf8` / `pairs` / `pcall` / `type` / … 以及受限 `os`（只有 `time` / `date` / `clock` / `difftime` / `getenv`）；
- 不暴露：`io.*`、`os.execute`、`load`、`loadfile`、`dofile`、`debug`；
- 自定义 `require`：只在 `GCPKG_LUA_PATH`、`<share>/lua`、项目 `lua/`、`<store>/lua` 里找模块，加载时同样注入沙箱 `_ENV`；
- `gcpkg.sys.exec` 是唯一进程出口，argv 数组直接 `execvp`，**不经过 shell**，因此文件名里的空格/元字符不会造成注入；
- `gcpkg.sys.loadchunk` 让 `gcpkg.import("某个库")` 能把另一个 port 的 build.lua 当普通 Lua 值载入，实现"一个构建包含另一个库"。

### 构建系统模块（可互相引用）

```
require("gcpkg.build.cmake")      -- configure/build/install + 原生 compdb
require("gcpkg.build.make")       -- make -jN，可带 vars / targets
require("gcpkg.build.autotools")  -- ./configure && make && make install
require("gcpkg.build.meson")      -- meson setup/compile/install
require("gcpkg.build.cargo")      -- cargo build --release
require("gcpkg.build.cc")         -- 直接编译/链接，逐条记录 compdb
require("gcpkg.build.auto")       -- 探测上游构建系统后分派
```

新构建系统 = 在 `lua/gcpkg/build/` 放一个 Lua 文件；port 里 `require` 它就获得对应构建函数。这正是"包含 cmake 就支持 cmake 构建函数"的含义。

## 2. 数据模型

### 特性（features.yaml）

```yaml
features:
  shared:
    default: false
    args: ["shared"]            # 注入 Configure/构建参数
    env: { CFLAGS: "-fPIC" }    # 注入环境变量
    defines: ["WITH_SSL"]       # 注入编译宏
    requires: ["zlib"]          # 额外依赖（自动参与依赖图）
    provides: ["openssl:shared"]
    conflicts: ["no-shared"]
```

`features.resolve()` 从「默认值 + 项目 gcpkg.yaml + CLI `--feature`」算出启用集合，处理冲突（显式选择优先，两个显式冲突报错），然后聚合出 `args / env / defines / requires / provides`。Lua 构建脚本通过 `ctx.feature_args()`、`ctx.features` 读取，**改 YAML 不需要改 Lua**。

### Port（build.lua）

```lua
return {
  name, version, source = {url, sha256, strip} | {git, ref} | {dir} | function(ctx),
  dependencies = {"zlib", {name="fmt", features={"shared"}}, "pkgconfig:libcurl"},
  build = function(ctx) ... return exports end,
}
```

`build(ctx)` 的 `ctx`：`src` / `build_dir` / `prefix` / `exec` / `capture` / `record` / `feature_args()` / `features` / `env` / `compiler` / `jobs` / `arch` / `os` / `store` / `dependencies` / `dep(name)` / `log` / `port_dir`。

`ctx.exec` 自动注入编译器拦截环境、cwd 和日志路径。返回的 `exports`（includes / libdirs / libs / defines / link_flags / binaries / compdb_files）写进 manifest。

### 元包管理器（backends.lua）

外部依赖写成 `"<adapter>:<name>"`，adapter 把外部管理器的输出翻译成与原生 port **完全相同**的 manifest 形状：

| adapter | 做什么 | 上游是否被修改 |
| --- | --- | --- |
| `native` | gcpkg 自己的 port | — |
| `pkgconfig` | `pkg-config --cflags --libs` → -I/-D/-L/-l | 否 |
| `vcpkg` | 读 `VCPKG_ROOT/installed/<triplet>/{include,lib}` | 否 |
| `system` | 系统 prefix（`/usr` 等） | 否 |
| `call` | 原样执行任意包管理器命令，解析其 flags 输出 | 否 |

`M.register(name, {probe, resolve})` 可注册更多（conan、brew、apt、npm、pip…），不需要改 C++，也不需要改对方。

## 3. 编译数据库：为什么能跨库跳转

### 三条来源

1. **拦截**：`gcpkg-intercept` 作为 `cc` / `c++` 符号链接放进构建环境。它把每次调用的 `cwd` + 完整 `argv` 追加成一行 JSON（用 `flock` 保证并行 `make -j` 不串行错乱），然后 `execvp` 真编译器。上游构建系统完全不知道自己被包装了。
2. **DSL 记录**：项目用 `gcpkg.build.cc.compile` 时，每条编译命令在运行前写入 JSONL。
3. **原生导入**：CMake / Meson 自己生成的 `compile_commands.json` 直接读入并规范化。

`compdb.normalize()` 做统一处理：取 `-c` 后的源文件（或最后一个源文件参数）、拼成绝对路径、丢弃纯预处理/版本探测（`-E` / `-M`）、丢弃已删除的 conftest 临时文件、保留完整 `arguments` 和 `directory`，按 `file + arguments` 去重。

### 合并

`gcpkg build <project>` 依次：

```
project/gcpkg.yaml → 特性请求
project/gcpkg.lua  → dependencies
   └─ 每个依赖（递归）→ install → manifest{includes, libs, compdb_jsonl, deps}
ctx = 汇总所有依赖的 includes / libs / defines / link_flags
spec.build(ctx)   → 编译项目，写 project.jsonl
merge(project.jsonl + 每个传递依赖的 compdb_jsonl)
   → <project>/compile_commands.json
   → <project>/.clangd（Add: -I<dep include>…）
```

因为依赖的编译命令里有它自己的 `-I`（OpenSSL 内部的 `include/`、`crypto/`、`providers/` 等），clangd 打开 `crypto/sha/sha256.c` 时能找到匹配条目并解析所有内部头文件；项目文件又通过 `-I<prefix>/include` 找到公共头文件。两个方向都通。

> 对比 vcpkg：它导出的是「已构建产物」（include/lib/bin），不保留依赖源码的编译命令，所以 clangd 一跳进依赖源码就丢失编译上下文。gcpkg 把依赖的编译数据库也当作一等产物保存并合并。

### Store 布局

```
<store>/cache/<tarball>          下载缓存（含 sha256 校验）
<store>/src/<name>-<version>     源码树，长期保留 ← 跳转目标
<store>/build/<name>-<version>   构建目录
<store>/pkg/<name>-<version>     安装前缀（include/lib/bin）
<store>/compdb/<key>.jsonl       原始拦截记录（供合并）
<store>/compdb/<key>.json        该库自己的 compile_commands.json
<store>/manifest/<key>.json      manifest（含 fingerprint / deps / exports）
<store>/logs/<key>.log           完整构建日志
<store>/bin/{cc,c++}            → gcpkg-intercept 的符号链接
```

manifest 的 `fingerprint` 由 name/version/特性集合/源 URL/平台/依赖 key，以及 `build.lua` + `features.yaml` 的 SHA256 组成（改 port 文件会触发重建，否则 CMake defines 会陈旧）；命中且产物路径仍存在时直接复用。`--no-cache` 强制重建。缓存命中时也会从 JSONL 重新物化该库自己的 `compile_commands.json`，并把它与构建系统原生生成的 compdb 合并写回，避免 CMake/Meson 条目在复用时丢失。

## 4. 生命周期（OpenSSL 实例）

```
gcpkg build examples/hello
 ├─ 读 gcpkg.lua / gcpkg.yaml → dependencies: openssl, features: no-shared/no-tests/no-docs
 ├─ port.install("openssl")
 │   ├─ 解析 features.yaml → args = [no-shared, no-tests, no-docs]
 │   ├─ 下载 openssl-3.4.1.tar.gz → 校验 sha256 → 解压到 store/src/openssl-3.4.1
 │   ├─ env: CC/CXX = gcpkg-intercept, GCPKG_INTERCEPT_LOG = store/compdb/openssl-3.4.1.jsonl
 │   ├─ perl Configure linux-x86_64 --prefix=... no-shared no-tests no-docs
 │   ├─ make -jN ; make install_sw
 │   ├─ 拦截日志 → compile_commands.json（数百条 OpenSSL 翻译单元）
 │   └─ manifest: includes=[prefix/include], libs=[ssl,crypto], link_flags=[-lpthread,-ldl]
 ├─ ctx.includes/libdirs/libs/link_flags = 汇总依赖
 ├─ cc.compile(src/main.c) + cc.link → .gcpkg/build/hello-gcpkg
 └─ 合并 compdb → compile_commands.json + .clangd
```

## 5. 已知边界 / 路线图

- 当前是第一个可运行版本：依赖解析是深度优先 + 循环检测，尚无 lockfile、版本约束求解、并行包级构建、二进制缓存分发。
- 平台映射目前覆盖 Linux x86_64/aarch64/arm/i386 与 macOS；Windows/MSVC 需要新的 target 与 shell 处理。
- Rust / Go / Java 的编译单元不属于 clangd 的 C/C++ 模型；`cargo` adapter 只接管构建产物，Rust 跳转仍应交给 rust-analyzer。
- `vcpkg` / `system` adapter 不猜 `-l<name>`，项目里显式写 `libs`。
- 旧 `Source/MainProcess`（TOML + LLVM + Docker 原型）保留作参考，不参与构建；Docker 隔离执行可作为后续 `exec` 后端接回来。
- 第四轮已支持 Meson / Autotools / 手写 Makefile 与系统 `-dev` 依赖混用（见第 9 节）；系统组件通过 `pkgconfig` backend 提供，纯数据 port 允许零编译命令。
- 特性是「每包一组布尔开关」；`requires:` 条件依赖已在 `install` / `graph` / `check` / `ports` 全链路求值（见第 8 节），但跨包特性传播（启用 A 时自动为依赖 B 启用某特性）仍只支持在 `dependencies = {{name=..., features={...}}}` 里显式声明。

## 6. 实测记录（2026-11-08，Linux x86_64 / gcc 14 / Lua 5.4 / yaml-cpp 0.8）

```bash
cmake -S . -B build && cmake --build build -j
./build/bin/gcpkg build examples/hello --store ~/.cache/gcpkg-store --ports ./ports
```

结果：

- OpenSSL 3.4.1 源码从官网下载并校验 SHA256，`perl Configure linux-x86_64 --prefix=... no-shared no-tests no-docs` + `make -j2` + `make install_sw` 全部成功，产物为 `libssl.a` / `libcrypto.a` / 头文件；
- 示例项目 `hello-gcpkg` 静态链接成功并运行：`linked OpenSSL : 3.4.1`；
- 合并后的 `compile_commands.json` 共 **1129 条**：1128 条 OpenSSL 翻译单元 + 1 条项目文件，覆盖 99 个源码目录，所有 `file` 都是存在且可解析的绝对路径；
- `clangd-22 --check`（Debian clangd 22.1.8）分别对项目 `src/main.c` 和依赖源码 `crypto/sha/sha256.c` 检查，均 `All checks completed, 0 errors`；日志显示依赖文件拿到了它原本的 `-I. -Iinclude -Iproviders/...` 与全部 `-D` 宏，说明跨库跳转上下文完整；
- 特性切换：`gcpkg install openssl --feature=openssl:shared` 得到 `features=[no-docs,no-tests,shared]`，产物含 `libssl.so` / `libcrypto.so`，2012 条编译命令；默认与显式冲突时显式优先；
- 元层：`gcpkg.import("openssl")` 成功把另一个 build.lua 当 Lua 表载入；`pkgconfig:zlib` 依赖解析出 `libs=[z]`；`gcpkg backends` 列出 native / pkgconfig / vcpkg / system / call；
- `tests/smoke.sh` 覆盖上述构建、编译数据库结构、二进制运行，以及（存在 clangd 时）两端源码的解析。

> 注意：clangd 对 compile_commands.json 的字段是严格校验的，只写
> `directory` / `file` / `arguments`（或 `command`）。内部 JSONL 里的
> `tag` / `output` 等元数据在输出时被 `compdb.clean()` 剥离。

## 7. 自底向上扩展（2026-11-08 第二轮）

第二轮按依赖层次从最底层往上加库，并把底层能力补齐：

**底层能力**

- `gcpkg.recipe`：声明式 `recipe.cmake / autotools / make`，新增普通库只需 ~20 行 Lua；`defines`、`vars` 支持 `function(ctx)` 以引用依赖安装前缀。
- 依赖向上传导：`port.install` 汇总**所有传递依赖**的 manifest，自动注入 `CPPFLAGS` / `LDFLAGS` / `PKG_CONFIG_PATH` / `CMAKE_PREFIX_PATH`，`ctx.all_dependencies` / `includes` / `libdirs` / `libs` 可供任意构建脚本使用。
- 缓存正确性：manifest fingerprint 现在包含 `build.lua` + `features.yaml` 的 SHA256，改 port 文件会触发重建。
- 编译数据库双来源统一：CMake/Meson 原生的 `compile_commands.json` 与拦截日志 JSONL 在构建时合并写回 JSONL，缓存命中与项目合并都不会丢条目。
- 静态链接顺序：项目链接按 manifest 逆序（依赖者在前）排列，但保持单个库内部的库顺序（`libssl` 在 `libcrypto` 前、`libbrotlidec` 在 `libbrotlicommon` 前）。
- `gcpkg ports` / `graph` / `check`：按依赖层级列出、打印自底向上构建顺序、校验 port 完整性。

**层次**

```
L0  zlib zstd lz4 brotli cares expat xz pcre2 libffi bzip2 openssl
L1  libssh2 (openssl+zlib)   nghttp2 (zlib)
    libarchive (zlib,bzip2,xz,zstd,lz4,openssl,expat,pcre2)
L2  curl (openssl,zlib,brotli,zstd,cares,nghttp2,libssh2)
L3  examples/web (curl)
```

`gcpkg install curl --store <fresh>` 实测一次从零构建 8 个包（2m42s），
`gcpkg build examples/web` 从零生成 2115 条编译命令、覆盖 134 个源码目录（复用旧缓存的 store 为 1689 条 / 124 目录），
所有 `file` 绝对路径有效；项目二进制运行输出：

```
libcurl       : 8.13.0
  SSL backend : OpenSSL/3.4.1
  HTTP2       : yes       async DNS : yes
  brotli/zstd : yes / yes
OpenSSL       : 3.4.1
```

clangd-22 对项目文件、curl、OpenSSL、zlib、libssh2 等各层源文件均能用同一份
`compile_commands.json` 加载编译命令并解析（部分文件出现的是 clangd 自身
`SwapBinaryOperands` tweak 的内部告警，不是编译诊断）。`tests/chain.sh` 固化了
这条回归链路。

> 途中修掉的真实问题：生成器 JSON/Lua 数组语法、libffi 多余的 include 路径、
> curl 默认启用系统 OpenLDAP 导致静态链接缺 `-lldap`、以及 CMake 类库编译数据库
> 在缓存命中时被丢弃。这些都已写入代码与测试，不是纸面设计。

## 8. 条件依赖与更宽的 L1 面（2026-11-08 第三轮）

**特性引入的依赖必须像静态依赖一样真实存在。** `features.yaml` 的 `requires:`
不只是给 Configure 传参数：启用 `openssl:zlib` 时，zlib 必须先编译、其
`-I` / `-L` / `PKG_CONFIG_PATH` / `CMAKE_PREFIX_PATH` 必须注入 OpenSSL 的构建环境，
而且依赖图、校验、缓存 fingerprint 都要同步。

实现上三处保持同一条规则：

- `port.install()`：`deps = spec.dependencies ∪ f.requires`，递归安装后写进 manifest 的 `deps`；
- `graph.deps(entry, requests, name)`：用相同的 `features.resolve()` 求有效依赖，`order()` / `layers()` / `validate()` 全部走它；
- CLI 把 `--feature` 请求透传给 `graph` / `ports` / `check`，所以
  `gcpkg graph openssl --feature=openssl:zlib` 得到 `zlib → openssl`，而不是只有 openssl。

真编译验证（`tests/features.sh`）：

```
manifest deps: ['zlib-1.3.1'] features: ['no-docs','no-shared','no-tests','zlib']
Configure ... no-docs no-shared no-tests zlib     → enable-zlib
compdb 里出现 -DZLIB 与 -I<store>/pkg/zlib-1.3.1/include
libcrypto.a 含 BIO_f_zlib / COMP_zlib 符号
```

也就是说，`CPPFLAGS` / `LDFLAGS` 里来自依赖 manifest 的路径让未修改的 OpenSSL
Configure 找到了 gcpkg 自己编译的 zlib。

**更宽的依赖面**：`ports/libarchive`（3.7.9）一次声明 8 个 L0 依赖，CMake 的
`find_package()` 全部命中 gcpkg 前缀（实测 `CMakeCache.txt`）：

```
ZLIB   → <store>/pkg/zlib-1.3.1/lib/libz.so
BZip2  → <store>/pkg/bzip2-1.0.8/lib/libbz2.a
LibLZMA→ <store>/pkg/xz-5.8.1/lib/liblzma.a
zstd   → <store>/pkg/zstd-1.5.7/lib/libzstd.a
LZ4    → <store>/pkg/lz4-1.10.0/lib/liblz4.a
OpenSSL→ <store>/pkg/openssl-3.4.1/lib64/libcrypto.a
EXPAT  → <store>/pkg/expat-2.7.1/lib/libexpat.a
```

`gcpkg install libarchive --store <fresh>` 从零构建 9 个包（2m38s），产出
`libarchive.a` 与 327 条编译命令；`gcpkg graph libarchive` 给出 9 步自底向上顺序。
上游 CMake 一行未改，只靠 `CMAKE_PREFIX_PATH` 与 `ENABLE_*` 宏。

> 环境注意：沙箱 `/tmp` 是 992M 的 tmpfs，多个源码树并行构建会报
> `No space left on device`。测试脚本默认 store 已迁到 `$HOME/.cache/gcpkg-*-store`
> （真实磁盘）；`GCPKG_STORE` 环境变量可覆盖。

## 9. Linux 底层库栈（2026-11-08 第四轮）

第四轮把「能管理几乎所有库」从网络库推到系统层：**36 个新 port**，全部真实下载、
编译、安装（不是纸面声明）。`gcpkg check --ports ./ports` = 51 ports OK，`gcpkg ports`
按依赖层级给出 L0 31 / L1 11 / L2 5 / L3 2 / L4 1（含旧 15 个），`gcpkg graph xserver`
给出 16 步自底向上顺序，`systemd` 是 L0 里体量最大的一个。

### 覆盖面

| 组 | port |
| --- | --- |
| 权限 / 沙箱 / NUMA | `libnuma` `libcap` `libcap-ng` `libseccomp` `libaio` `liburing` |
| 网络 / netfilter / IPVS | `libmnl` `libnl` `libnftnl` `iptables` `ipvsadm` `libpcap` |
| 数据 / XML / 系统工具 | `popt` `json-c` `libyaml` `libxml2` `kmod` `util-linux` `dbus` |
| X11 / Xserver | `xorgproto` `xcb-proto` `libXau` `libXdmcp` `libxcb` `libX11` `pixman` `libpciaccess` `libxkbcommon` `fontutil` `xserver` |
| Wayland / DRM / 输入 | `wayland-protocols` `wayland` `libdrm` `libevdev` `libinput` |
| init / 服务管理 | `systemd` |

### 引擎新增能力（都不是针对某个库的特判）

- `lua/gcpkg/build/meson.lua`：完整的 meson setup/compile/install，`--libdir=lib`
  （绕开 Debian 多架构目录）、`--wrap-mode=nodownload`、`--reconfigure`、原生
  `compile_commands.json`；`--sysconfdir=<prefix>/etc` 与
  `--localstatedir=<prefix>/var` 把系统组件的配置安装收进自包含 prefix，
  非 root 也能装 systemd / dbus / util-linux。
- `lua/gcpkg/recipe.lua`：`recipe.meson`；`options(ctx)` 允许选项依赖运行时 prefix
  （kmod 把 `distconfdir` / `moduledir` 指向 prefix，避免写 `/etc/depmod.d`）；
  `pre_build(ctx)` 在构建前跑任意钩子（libcap-ng / popt 补 `NEWS` 再 `autoreconf -fi`）；
  `make.jobs` 控制手写 Makefile 的并行度（ipvsadm 的 `all: libs ipvsadm` 无依赖边，
  必须 `jobs=1`）。
- `lua/gcpkg/port.lua`：依赖环境补 `CPATH` / `LIBRARY_PATH` / `PYTHONPATH` /
  `ACLOCAL_PATH` / `share/pkgconfig`，`CMAKE_PREFIX_PATH` 改用 `;` 分隔；
  Meson 与 Autotools 的 pkg-config 探测因此能跨 gcpkg 前缀工作。
- `fontutil` / `xcb-proto` 这类**纯数据 port**合法：只装 `.pc` / 头文件 / XML，
  零编译命令，但下游 `dependency('fontutil')` 能解析。
- 宽依赖面里没法（也不必）纳入 gcpkg 的宿主组件（xtrans / xfont2 / libudev /
  libmount / libaudit / libpam / libgcrypt / glib …）仍由系统 `-dev` 提供，
  通过 `pkgconfig` backend 参与 `find_package` / `dependency()`；上游源码一行未改。

### 真实编译结果（store `~/.cache/gcpkg-linux-store`）

36 个 port 合计 6718 条编译命令，全部由 `tests/linux.sh` 校验。代表性数字：
`systemd` 3272、`util-linux` 833、`xserver` 596（产出 `Xvfb`）、`libX11` 410、
`dbus` 255、`libxkbcommon` 185、`libinput` 166、`iptables` 161、`libnl` 135、
`libxml2` 82、`pixman` 65、`libnftnl` 65、`wayland-protocols` 59、`kmod` 46、
`libxcb` 35、`json-c` 32、`wayland` 29、`libaio` 25、`libpciaccess` 25、
`libcap-ng` / `popt` 都因 GitHub/归档 tarball 缺自动生成文件而通过 `pre_build` 修复。
链内 `openssl` 仍为 1128 条 / 98 目录，说明新引擎未破坏旧链。

### 适配决策（全部落在 build.lua 里，不改上游）

`libyaml` 0.2.5 release tarball 缺 CMake 模板 → 改用 autotools；`libxcb` 同时产出
`.a` / `.so`，`xserver` 用 `default_library=shared` 链接，避免静态 XCB 丢失
`Requires.private` 的 Xau/Xdmcp 符号；`systemd` 关 `hwdb`（否则 install 阶段要
以 root 跑 `systemd-hwdb update`）；`ipvsadm` 的 `INCLUDE` 需 `-I` 前缀、`LIBS`
需显式 `-lpopt -lnl-genl-3 -lnl-3`；Meson 选项名按各 tarball 的
`meson_options.txt` 逐个核对（wayland 是 `dtd_validation`，xorg-server 是
`mitshm`，dbus 用下划线……）。

回归：`tests/{smoke,chain,features}.sh` 全部 exit=0（1127 / 1689 条项目级 compdb），
`tests/linux.sh` 额外校验 36 个 manifest、6718 条 JSONL 的绝对路径、
12 个关键产物及 clangd 对 5 个库 compdb 的加载。

## 10. 媒体 / AI / 网络 / 厂商 SDK（2026-11-08 第五轮）

第五轮新增 **23 个 port**，注册表 51 → **74**（`gcpkg check` = 74 ports OK）。
按你的要求，这一轮以**静态验证**为主（真实编译由你在本机完成）：
`check` / `graph` / `ports` / `externals` / `features`、URL+SHA256 校验、
依赖可解析、分层顺序，全部不下载、不编译（`tests/media.sh`）。

### 两个新引擎能力

- `lua/gcpkg/build/external.lua`（新 adapter）：登录墙 / 授权 / 多 GB `.run`
  / 已装在机器上的 SDK 无法匿名下载，所以这类 port 的 `source` 是一个
  **函数** —— `net.prepare` 只在 `gcpkg install` 时调用它，检查
  `$GCPKG_<NAME>_HOME`（含备用变量与默认路径）指向的目录并写 marker；
  `build` 不编译，只导出 include / libdir / libs / binaries（二进制 SDK
  没有翻译单元，compdb 为 0，和 `fontutil` / `xcb-proto` 一样合理）。
  因此 `gcpkg check` / `graph` / `ports` 在**没有装任何 SDK 的机器上**也能跑。
  `gcpkg externals` 静态打印 4 个 SDK 各自的变量名、是否已设置、官方下载页。
- `lua/gcpkg/port.lua`：依赖环境把 `exports.binaries` 前置到 `PATH`。
  「管理 CMake」因此不只是声明：`ports/cmake` 是工具 port，
  `folly` / `proxygen` / `vulkan` / `redpanda` 等依赖它后，
  它们的 CMake/Meson 调用优先使用 gcpkg 自己构建的 cmake。

### 覆盖面

| 组 | port |
| --- | --- |
| 构建 / 语言 / 基础 | `cmake` `lua` `alsa-lib` `libpsl` `libfuse` `ucx` |
| 流媒体 | `live555` `librtsp` |
| Vulkan | `vulkan-headers` `vulkan`（Loader） |
| Facebook C++ 栈 | `folly` `fizz` `wangle` `mvfst` `proxygen` |
| 流式数据 | `redpanda` |
| NVIDIA 开源栈 | `dcgm` `nv-image-codec` `cv-cuda` |
| 厂商 SDK（external） | `nvidia`（CUDA）`cann`（华为 CANN）`nv-codec-sdk`（Video Codec SDK）`dahuaplayer`（大华 PlaySDK） |

`cmake` / `lua` 用自定义 `build(ctx)`（bootstrap / `make linux`），
`alsa-lib` / `libpsl` / `ucx` 用 autotools（`pre_build` 按需 `autoreconf`），
`libfuse` 用 Meson，其余 CMake。所有可匿名下载的 tarball 都带**真实 URL +
SHA256**（`tools/media-catalog.tsv`），不猜测校验和。

### 依赖图（静态）

`gcpkg graph proxygen` = 11 步：
`cmake → openssl → zlib → zstd → lz4 → bzip2 → folly → fizz → wangle → mvfst → proxygen`；
`gcpkg graph nv-image-codec` = `nvidia → cv-cuda → nv-image-codec`。
`folly` 复用第四轮之前的 L0 加密/压缩链，宿主侧的 boost / glog / gflags /
fmt / double-conversion / libevent 仍走 `pkgconfig` backend。

### 本轮动态验证（轻量，其余交给你本地）

| 项 | 结果 |
| --- | --- |
| `lua` 5.4.7 | 真编译 34 条 compdb，`liblua.a` + `bin/lua -v` = Lua 5.4.7 |
| `alsa-lib` 1.2.9 | 真编译 113 条 compdb |
| `nvidia` adapter | 用临时假 SDK 目录 `install` 成功，manifest 正确导出 `include/` / `lib64/` / `cudart` 等，compdb 0 条 |
| 旧回归 | `tests/{smoke,chain,features,linux}.sh` 全部 exit=0 |

其余 21 个新 port 是**诚实的静态声明**：proxygen 链、Redpanda、DCGM、
CV-CUDA/nvImageCodec 需要大量系统组件或 CUDA；CANN / Video Codec SDK /
Dahua PlaySDK 需要登录或授权。上游源码一行未改，所有适配都在 `build.lua`
的选项、钩子和 SDK 元数据里。`docs/EXTERNAL_SDKS.md` 给出 4 个 SDK 的
环境变量、默认路径、探针文件与导出内容。

## 11. 更多 Linux 基础库（2026-11-08 第六轮）

第六轮新增 **37 个 port**，注册表 74 → **111**（`gcpkg check` = 111 ports OK）。
延续「自底向上 + 宽依赖面」：新库大量复用前几轮的 L0 成果（zlib / xz /
zstd / bzip2 / brotli / libffi / pcre2 / expat / libxml2 / openssl / libmnl），
而不是重新声明一遍。

### 覆盖面

| 组 | port |
| --- | --- |
| GNU 数值 / 加密 | `gmp` `mpfr` `mpc` `nettle` `libtasn1` `libunistring` `libidn2` `libgpg-error` `libgcrypt` `libsodium` `mbedtls` `gnutls` |
| 事件 / 数据 / 终端 | `libevent` `libuv` `jansson` `sqlite3` `ncurses` `readline` `oniguruma` `utf8proc` `xxhash` `libdeflate` |
| 图像 / 字体 | `libpng` `libjpeg-turbo` `libtiff` `freetype` `fontconfig` `harfbuzz` `glib` |
| 内核 / 系统接口 | `libusb` `elfutils` `libbpf` `libattr` `libacl` `libnfnetlink` `libnetfilter_conntrack` |

Autotools / CMake / Meson / 手写 Makefile 四种形态都有，全部通过
`lua/gcpkg/recipe.lua` 的对应分支或自定义 `build(ctx)` 接入，上游零修改。

### 真实 URL / SHA256 与依赖图

37 个 tarball 全部实际下载并计算 SHA256（`tools/linux-base-catalog.tsv`）；
`isl` 的 SourceForge / GCC 镜像都失效，已剔除而不是写假校验和。
`tools/gen-linux-base-ports.py` 可重新生成 37 套 `build.lua` + `features.yaml`。

- `gcpkg graph gnutls` = 7 步：`gmp → nettle → libtasn1 → libunistring →
  libidn2 → zlib → gnutls`（nettle / libidn2 各自还带下层依赖）。
- `gcpkg graph libbpf` = 5 步：`zlib → zstd → xz → elfutils → libbpf`。
- `gcpkg graph fontconfig` = 7 步（zlib → libpng → freetype → fontconfig，
  另含 bzip2 / brotli / expat）。

### 真编译（14 个代表性库，884 条编译命令）

用 `~/.cache/gcpkg-linux-store` 复用前几轮依赖，从**干净源码**重建：
`xxhash` 10、`libdeflate` 52、`jansson` 70、`utf8proc` 4、`libpng` 70、
`libgpg-error` 43、`libsodium` 119、`libattr` 14、`libacl` 61、
`libnfnetlink` 3、`ncurses` 364、`readline` 34、`libxslt` 30、`libusb` 10。
`GCPKG_BASE_DYNAMIC=1 ./tests/linux-base.sh` 可复现（14 PASS / 0 FAIL）。

期间修正了三类真实的上游差异，全部落在生成的 `build.lua` 里：

- `libdeflate` 1.26 的 tag tarball 只有 `CMakeLists.txt`（无顶层 Makefile）
  → 从手写 Makefile 配方改为 CMake 配方。
- `libusb` 1.0.30 的 tag tarball 只有 `configure.ac` → 改为 autotools，
  `pre_build` 条件执行 `autoreconf -fi`。
- `libxslt` 默认构建 shared 库，会把非 PIC 的 `liblzma.a` 链进 `.so` 而失败
  → 所有 autotools 配方统一加 `--disable-shared --enable-static`
  （与 `features.yaml` 里 `static` 为默认值一致）。

### 静态验证与边界

`tests/linux-base.sh` 默认纯静态：111 ports OK、三张自底向上图的顺序断言、
37 份两文件、真实 URL + 64 位 SHA256、无沙箱绝对路径、依赖全部可解析、
`gcpkg features gnutls` 可加载。不下载、不编译。
其余 23 个新 port（GnuTLS / GLib / HarfBuzz / elfutils / libbpf 的完整链等）
按约定由用户在本机验证 —— 它们需要更多系统组件或更长构建时间。
六个回归脚本全部 exit=0。

## 12. 内核接口与磁盘信息查询（2026-11-08 第七轮）

第七轮新增 **34 个 port**，注册表 111 → **145**（`gcpkg check` = 145 ports OK）。
方向是用户点名的「内核和底层库 / 磁盘信息查询」。`liburing` 早在第四轮就已
纳入并真编译过，这一轮把它**从干净源码重新复核**（14 条 compdb），并让它成为
新依赖链的一环：`libnvme` 声明依赖 `liburing`，所以 `graph udisks2` 里能直接看到。

### 覆盖面

| 组 | port |
| --- | --- |
| NVMe / D-Bus 磁盘信息 | `libnvme` `nvme-cli` `libgudev` `udisks2` `libstoragemgmt` |
| SMART / ATA / SCSI / RAID | `libatasmart` `smartmontools` `hdparm` `sg3_utils` `mdadm` |
| 分区 / 文件系统 | `libparted` `e2fsprogs` `xfsprogs` `btrfs-progs` `lvm2` |
| 硬件枚举 | `pciutils` `dmidecode` `lm-sensors` `i2c-tools` |
| 内核接口 | `libtraceevent` `libtracefs` `keyutils` `libgpiod` `libiio` `hidapi` `libserialport` `libaudit` `libselinux` `libtirpc` `libunwind` |
| 其它底层 | `libmicrohttpd` `libdaemon` `libconfuse` `rpcsvc-proto` |

Autotools / CMake / Meson / 手写 Makefile 四类配方都有；构建系统种类是**逐个
解压 tarball 检查顶层文件**后确定的，不靠猜。34 个 URL/SHA256 均为实测值；
`libhugetlbfs`（只有 2006 年的 dev tag）、`lsscsi`（镜像全失效）被剔除，
`mdadm` / `libserialport` / `lm-sensors` 换成正式 release tarball。
详见 `tools/linux-kernel-catalog.tsv` 与 `tools/gen-linux-kernel-ports.py`。

### 依赖图（静态）

`gcpkg graph udisks2` = **15 步**：
`libffi → zlib → pcre2 → glib → expat → dbus → libgudev → libatasmart →
liburing → libnvme → util-linux → libparted → libattr → libacl → udisks2`。
`graph nvme-cli` = 3 步（`liburing → libnvme → nvme-cli`），
`graph libtracefs` = 2 步（`libtraceevent → libtracefs`）。
一条磁盘信息查询链把前六轮的 L0（libffi/zlib/pcre2/glib/expat/dbus/
util-linux/libattr/libacl）与内核库串在一起，而不是重复声明。

### 真编译（22 个，1061 条编译命令）

`GCPKG_KERNEL_DYNAMIC=1 ./tests/linux-kernel.sh` = 22 PASS / 0 FAIL：
`liburing` 14、`libnvme` 123、`nvme-cli` 115、`libatasmart` 4、
`libtraceevent` 45、`libtracefs` 97、`pciutils` 36、`libconfuse` 12、
`libdaemon` 7、`libserialport` 4、`hidapi` 6、`libunwind` 179、
`sg3_utils` 94、`smartmontools` 2、`libgpiod` 154、`libparted` 123、
`libiio` 46，外加 `keyutils` / `dmidecode` / `hdparm` / `mdadm` /
`rpcsvc-proto`（这几个手写 Makefile 硬编码 `gcc`，编译成功但 compdb 为 0，
如实记录）。store 累计 10034 条。

修过的上游差异仍全部落在生成的 `build.lua` / `features.yaml` 里：

- `libtraceevent` / `libtracefs` 的 Meson 默认构建文档并强制要 `asciidoc`
  → `-Ddoc=false`。
- `hidapi` / `libiio` 默认 shared，把非 PIC 的 `libusb-1.0.a` 链进 `.so`
  → `-DBUILD_SHARED_LIBS=OFF`；`libiio` 还关掉 `HAVE_DNS_SD` / `WITH_AIO`
  与 `INSTALL_UDEV_RULE`（否则 install 写 `/lib/udev/rules.d` 需要 root）。
- `libunwind` 的 CMakeLists.txt 明确写着「只支持 Visual Studio」
  → 改用 autotools 配方（tag archive 里 `pre_build` 跑 `autoreconf`）。
- 手写 Makefile 的内核工具（pciutils/dmidecode/hdparm/mdadm…）的
  `install` 目标写 `/sbin` → 自定义 `build(ctx)` 先 `make`，再把 `.a` /
  `.h` / 二进制收集进 gcpkg prefix，不改上游；同时命令行传
  `CC=<wrapper>` 让部分 Makefile 也能产出 compdb。

### 项目模式

`examples/diskinfo/` 依赖 `libnvme` / `libatasmart` / `pciutils`，实测
`gcpkg build examples/diskinfo` 生成合并的 `compile_commands.json`
（240 条、21 个源目录），`clangd-22 --check` 对项目文件 0 个 `error:`，
可从项目源码跳进 NVMe / SMART / PCI / liburing / zlib 的依赖源码。
详见 `docs/DISK_INFO.md`。

### 验证边界

`tests/linux-kernel.sh` 默认纯静态：145 ports OK、三张自底向上图（含
`liburing` 在磁盘链里的断言）、34 份两文件、真实 SHA256、无沙箱绝对路径、
依赖可解析、`features udisks2` 可加载、`liburing` 声明仍在。不下载不编译。
其余 12 个新 port（udisks2 / libstoragemgmt / 文件系统工具 / libselinux 等）
按约定由用户在本机真编译。七个回归脚本全部 exit=0。

## 13. 项目工作流：作用域与版本（2026-11-08 第八轮）

用户要求「像 pnpm 一样用命令创建项目、添加库」，并明确区分项目特有与公有、
不同项目依赖不同库、以及按项目指定不同版本。新增 `lua/gcpkg/workspace.lua`，
其余引擎模块只做通用能力扩展。

### 命令

`gcpkg new DIR` / `init`、`add DEP[@VERSION]...`、`remove NAME...`、
`list`、`versions PORT`、`install`（无参 = 安装项目全部依赖）。
`-C/--dir=DIR` 类似 `pnpm -C`；`--local` 创建项目私有 port；
`-g/--global` 写用户级公有依赖清单；`--name` 指定项目名。

### 三层 port 作用域

`project`（`<project>/gcpkg-ports/`，只对本项目的同名 port 生效）→
`user`（`$GCPKG_HOME/ports/`）→ `public`（`--ports` / `GCPKG_PORTS` /
引擎 `ports/`）。`graph.ports()` 与 `port.find()` 都是「第一个命中即生效」，
所以一个项目可以覆盖 `zlib` 而不 fork 145 个 port 的公共 registry。
`gcpkg list` 用 `[project]/[user]/[public]` 标出每个依赖命中的位置。

### 两种依赖清单

项目特有清单在 `<project>/gcpkg.yaml` 的托管区块（`# --- gcpkg managed
dependencies ---`），`add`/`remove` 只改这个区块，其它注释、features、
ports 全部保留。公有清单在 `$GCPKG_HOME/gcpkg.yaml`，项目必须显式
`inherit_global: true` 才继承；默认不继承，因此不同项目天然可以有完全不同
的依赖集合。同名依赖项目声明优先。

### 版本是真的换源码

之前 `install zlib@1.2.13` 只换了缓存 key、源码仍是 build.lua 的默认
tarball。现在 `port.install()` 在 `features.yaml` 的 `versions:` 里查版本，
用声明的 `source`（真实 URL + SHA256）覆盖 `spec.source`，并替换
`spec.version` / 可选 `spec.dependencies`；store 产生独立的
`zlib-1.2.13` manifest / prefix / 源码树，fingerprint 天然不同。
**未声明的版本直接报错**并列出可用版本。`features.resolve()` 增加元数据键
过滤，`versions:` 不会被误当成 feature。一库仍严格是
`build.lua` + `features.yaml` 两个文件。

### 锁文件

`<project>/gcpkg.lock`（JSON）记录依赖规格、inherit_global、roots 以及实际
解析出的 `key / version / scope / port_dir / compdb_entries`。`add`/`remove`
清空 resolved 并标 `pending`，`install`/`build` 写满；`list` 展示。
每个项目一份，互不干扰。

### 实测

`tests/projects.sh` 静态 exit=0；`GCPKG_PROJECT_DYNAMIC=1` 动态 exit=0：
`v1` 用 `zlib@1.2.13`（真编译 70 条、项目 compdb 71 条），`v2` 用
`zlib@1.3.1`（62 条）+ `jansson@2.14`（64 条）（项目 compdb 127 条），
两个 compdb 不串版本，两个 lock 的 resolved key 不同。
`gcpkg install`（无参）先装好依赖，`build` 命中缓存并合并编译数据库。
详见 `docs/PROJECTS.md`。

## 14. 更多基础库（2026-11-08 第九轮）

一句话需求「继续支持更多的库」：注册表 145 → **188**，新增 43 个此前没覆盖
的库，按 JSON/CBOR/配置、压缩、QUIC/网络协议、音视频、加密/C++ 工具五组铺开。
与前两轮不同，**43 个全部在干净 store 里真编译通过**：
`GCPKG_EXTRA_DYNAMIC=1 ./tests/extra.sh` = `43 PASS / 0 FAIL, 3056 compile
commands`。默认仍只做静态验证，`tests/extra.sh` 不下载不编译。

### 依赖面

`graph libsndfile` 5 步（`libogg → libvorbis → opus → flac → libsndfile`），
`graph spdlog` 2 步（`fmt → spdlog`），`graph libssh` 用已有 `openssl + zlib`，
`graph libzip` 用已有 `zlib`，`graph libedit` 用已有 `ncurses`。四个
`features.yaml` 的 `requires:` 条件依赖（`libzip:openssl`、
`libwebsockets:tls`、`librdkafka:ssl`、`ngtcp2:tls`）启用后各多一步 openssl，
默认图保持精简。

### 适配（全部落在生成的两文件里）

`tools/extra-catalog.tsv`（43 行真实 URL/SHA256/kind/deps）+
`tools/gen-extra-ports.py`（cmake / meson / autotools / 自定义 `build(ctx)`、
条件 feature）。`tests/extra.sh` 会重跑生成器并断言逐字节一致。

几个值得记的形态：`zlib-ng` 需要同时关掉三个测试开关；`inih` 的
Meson 没有 `tests` 选项；`nghttp3` / `libtheora` 的 GitHub tag 归档缺
submodule / 缺 SDL m4 宏，改官方 release tarball；`libvpx` 用
`--target=generic-gnu` 纯 C 目标绕开缺失的 nasm；`giflib` / `lmdb` 手写
Makefile 用自定义 `build(ctx)` 指定 cwd、prefix 与 `CC=<wrapper>`。
详见 `docs/EXTRA_LIBRARIES.md`。三个 tag 全失效的候选（msgpack-c、
tomlc99、utf8cpp）按惯例剔除，不写占位 SHA256。

## 15. 代理与第十轮库（2026-11-08 第十轮）

用户要求「继续支持更多的库，包管理器要支持设置代理」。注册表 188 → **226**，
新增 38 个库；`GCPKG_R10_DYNAMIC=1 ./tests/r10.sh` 从干净 store 全部真编译
（`38 PASS / 0 FAIL, 2498 compile commands`），并逐个检查 manifest 与导出的
`.a` / `.so`。详见 `docs/ROUND10_LIBRARIES.md`。

### 代理是一层引擎能力

新增 `lua/gcpkg/proxy.lua`：一次性解析 `--no-proxy` > `--proxy` >
`GCPKG_PROXY` > 项目 `gcpkg.yaml` > `$GCPKG_HOME/gcpkg.yaml` > 标准
`HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY`，`no_proxy` 单独按
`--noproxy` > `GCPKG_NO_PROXY` > 项目 > 用户级 > `NO_PROXY` 解析。
`proxy.env()` 把结果变成 8 个环境变量，合并进：

- `net.lua` 的 `curl` 下载与 `git clone --depth 1`（含 `source.git` port）；
- `port.lua` 的所有 port 构建钩子环境；
- `project.lua` 的项目构建拦截环境。

凭据只走环境与配置文件，不进 argv；`exec.lua` 写日志时统一把
`://user:pw@` 脱敏。`gcpkg proxy [URL|--unset]` 用托管区块写 YAML，
`-g` 写用户级、`-C/--local` 写项目级，与第八轮的两层依赖清单一致。
`--no-proxy` 清空 6 个 `*_proxy` 并设 `no_proxy=*`，保证确定性的直连。
详见 `docs/PROXY.md`。

同时修掉 `net.prepare` 的源码身份缺陷：`.gcpkg-source-ready` marker 现在
记录 `url|sha256`（git 另加 `ref`），同名同版本换源会自动刷新解包目录——
这正是 `libbsd` 从 GitHub tag 换到官方 release tarball 时暴露出来的。

### 依赖面

`graph re2` = 2 步（`abseil → re2`，`find_package(absl)` 命中安装的 CMake
config）、`graph glog` = 2 步（`gflags → glog`）、`graph libbsd` = 2 步
（`libmd → libbsd`）。七个条件特性除了 `requires:` 拉依赖，还能追加构建开关
（`libsrtp:openssl` → `-DENABLE_OPENSSL=ON`、`portaudio:alsa` →
`-DPA_USE_ALSA=ON`），默认图保持精简。生成器仍是
`tools/r10-catalog.tsv`（38 行实测 URL/SHA256/kind/deps）+
`tools/gen-r10-ports.py`，`tests/r10.sh` 断言重跑后逐字节一致。

### 第十一轮：工具链也是 port，包管理器也是 adapter

注册表 226 → **249**。三种形态：`nasm` 2.16.03 与 `python` 3.12.8
是从真实 tarball 编译的**源码工具 port**（`exports.binaries` 进 `PATH`）；
`rust` 用 `gcpkg.build.external.declare` 声明 `GCPKG_RUST_HOME`，
`gcpkg externals` 离线列出；`tokenizers-cpp` 固定到上游 main commit
`c586c52`（v0.1.1 tag 与它自带的 `tokenizers 0.21.4` 不兼容），在
`source()` 里用 3 个 pinned tarball 补齐 GitHub 归档的空 submodule。

`lua/gcpkg/recipe.lua` 增加 `python` / `cargo` 两个 kind，分别调用
`lua/gcpkg/build/python.lua`（setup.py / PEP 517 pip --target）与
`lua/gcpkg/build/cargo.lua`（`cargo build --release` 后把 `.a`/`.rlib`
装进 prefix）。两者都只通过 `ctx.exec` 调子进程，所以代理 env、
CC/CXX 拦截与统一日志自动生效。Rust 本身不进 compdb（交给
rust-analyzer），但 C++ 侧仍经 `compdb_files` 并入统一编译数据库。

第九轮的 `libvpx` 纯 C 回退被移除：`tools/extra-catalog.tsv` 与
`tools/gen-extra-ports.py` 同步改成 `nasm` 依赖 + `--as=nasm`，
`tests/r11.sh` 断言 `generic-gnu` 已消失、构建日志含 `[AS]`。
新增 `tests/r11.sh`（静态 + `GCPKG_R11_DYNAMIC=1` 全量真编译）与
`docs/TOOLCHAINS.md` / `docs/ROUND11_LIBRARIES.md`。

## 16. 构建 gcpkg 本体



```bash
cmake -S . -B build            # 需要 Lua 5.4 开发库、yaml-cpp、pkg-config
cmake --build build -j
./build/bin/gcpkg doctor
```

`GCPKG_SHARE` 可指向包含 `lua/` 与 `ports/` 的根目录；`GCPKG_LUA_PATH`、`GCPKG_PORTS`、`GCPKG_HOME` 分别覆盖模块路径、port 注册表和 store 位置。安装时 `cmake --install` 会把 Lua 引擎和 ports 复制到 `share/gcpkg/`。
