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

## 9. 构建 gcpkg 本体

```bash
cmake -S . -B build            # 需要 Lua 5.4 开发库、yaml-cpp、pkg-config
cmake --build build -j
./build/bin/gcpkg doctor
```

`GCPKG_SHARE` 可指向包含 `lua/` 与 `ports/` 的根目录；`GCPKG_LUA_PATH`、`GCPKG_PORTS`、`GCPKG_HOME` 分别覆盖模块路径、port 注册表和 store 位置。安装时 `cmake --install` 会把 Lua 引擎和 ports 复制到 `share/gcpkg/`。
