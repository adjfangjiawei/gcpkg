# 扩展指南

## 1. 新增一个库

```bash
gcpkg port new zlib --ports ./ports       # 生成模板
```

然后编辑两个文件：

`ports/zlib/build.lua`（**唯一构建配置**）

```lua
local cmake = require("gcpkg.build.cmake")

return {
  name = "zlib",
  version = "1.3.1",
  source = {
    url = "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz",
    sha256 = "<fill in>",
    strip = 1,
  },
  dependencies = {},

  build = function(ctx)
    -- require("gcpkg.build.cmake") 即获得 cmake 构建函数，cmake 本身无需改动
    local r = cmake.all {
      src = ctx.src, build_dir = ctx.build_dir, prefix = ctx.prefix,
      exec = ctx.exec, log = ctx.log, jobs = ctx.jobs,
      defines = { BUILD_SHARED_LIBS = ctx.features.enabled.shared and "ON" or "OFF" },
    }
    return {
      includes = { ctx.prefix .. "/include" },
      libdirs  = { ctx.prefix .. "/lib" },
      libs     = { "z" },
      compdb_files = r.compdb_files,  -- CMake 原生编译数据库也一起并入
    }
  end,
}
```

更常见的情况可以直接用声明式配方（`require("gcpkg.recipe")`），`ports/zlib`、`ports/zstd`、`ports/xz` 等都是这样写的：配方自动处理 prefix、特性参数、依赖环境传导和编译数据库导入，`build.lua` 只需 ~20 行；只有上游构建系统确实特殊时才写 `build(ctx)`（如 `ports/openssl`、`ports/bzip2`）。

`ports/zlib/features.yaml`（**唯一特性配置**）

```yaml
schema: 1
port: zlib
features:
  shared:
    default: false
    args: ["-DBUILD_SHARED_LIBS=ON"]
    provides: ["zlib:shared"]
```

### 条件依赖：让特性拉起下层库

特性的 `requires:` 不只是构建参数，它会变成真实的传递依赖。以
`ports/openssl/features.yaml` 为例（不需要改 `build.lua`）：

```yaml
features:
  zlib:
    default: false
    description: Enable zlib compression (pulls in the zlib port)
    args: ["zlib"]          # perl Configure 的 enable-zlib
    requires: ["zlib"]      # 先编译 zlib，再把它的 -I/-L 注入 OpenSSL
```

启用后：

```bash
gcpkg graph openssl --feature=openssl:zlib   # 1. zlib  2. openssl
gcpkg check --feature=openssl:zlib           # 含条件依赖的完整性校验
gcpkg install openssl --feature=openssl:zlib --store ~/.cache/gcpkg-store
```

`port.install()`、`graph.deps()`、`gcpkg ports` / `check` 用同一套
`features.resolve()` 求有效依赖，所以依赖图、构建顺序、manifest 的 `deps`
和缓存 fingerprint 始终一致。`tests/features.sh` 会真编译这条链并断言
`-DZLIB`、zlib 的 include 路径以及 `libcrypto.a` 里的 `BIO_f_zlib` 符号。

想让一个库依赖多个下层库，直接在 `dependencies` 里列全即可；配方会把它们
汇总成 `CMAKE_PREFIX_PATH` / `CPPFLAGS` / `LDFLAGS` / `PKG_CONFIG_PATH`。
`ports/libarchive` 就是这样一次挂上 8 个 L0 库，CMake 的 `find_package()`
全部命中 gcpkg 自己编译的产物。

要点：

- `source` 支持 `url`（+`sha256` / `strip`）、`git`（+`ref`）、`dir`（本地目录）或一个 `function(ctx)`，用于任意获取方式。
- `dependencies` 里的字符串可以是 `name`、`name@version`、`adapter:name`，也可以是表 `{name=..., version=..., features={...}}`。
- `build(ctx)` 可以用 `ctx.exec` 跑任意命令；所有走 `CC`/`CXX` 的编译都会被自动记录到编译数据库。若构建系统自己会生成 `compile_commands.json`，把路径放进返回的 `compdb_files`。
- `gcpkg.import("openssl")` 会把另一个 port 的 build.lua 作为普通 Lua 表载入，从而复用它的辅助函数/参数（配置之间互相引用）。
- 想加新构建系统：在 `lua/gcpkg/build/<name>.lua` 写一个模块，port 里 `require("gcpkg.build.<name>")`，**不需要改 C++、不需要重新编译**。

## 2. 项目里直接写配置

`gcpkg.lua`

```lua
local cc = require("gcpkg.build.cc")
return {
  name = "app", version = "1.0.0",
  dependencies = { "openssl", "pkgconfig:libcurl" },
  build = function(ctx)
    local objs = cc.compile{ sources={"src/main.c", "src/util.c"},
                             includes=ctx.includes, defines=ctx.defines,
                             outdir=ctx.build_dir.."/obj", cwd=ctx.project_dir,
                             exec=ctx.exec, record=ctx.record }
    cc.link{ objects=objs, output=ctx.build_dir.."/app",
             libdirs=ctx.libdirs, libs=ctx.libs, flags=ctx.link_flags,
             exec=ctx.exec, cwd=ctx.project_dir }
  end,
}
```

`gcpkg.yaml`

```yaml
project: app
features:
  openssl: [shared, no-tests]       # 或 {enable: [...], disable: [...]}
```

命令行覆盖：`gcpkg build . --feature=openssl:no-shared --feature=openssl:zlib`。

`ctx` 提供：`project_dir` / `build_dir` / `includes` / `libdirs` / `libs` / `defines` / `link_flags` / `dependencies`（按拓扑顺序的 manifest 列表）/ `compiler` / `env` / `exec` / `capture` / `record` / `dep(name)` / `jobs` / `features` / `log`。

## 3. 接入另一个包管理器

在 `lua/gcpkg/backends.lua`（或你自己的 Lua 模块里 `require("gcpkg.backends").register(...)`）注册：

```lua
M.register("conan", {
  probe = function() return gcpkg.have("conan"), "conan CLI" end,
  resolve = function(name, cfg)
    -- 原样调用 conan，解析它的 JSON 输出，翻译成 manifest
    local out = gcpkg.capture({"conan", "install", "--requires=" .. name, "--format=json"})
    return {
      name = "conan:" .. name, key = "conan-" .. name, version = "external",
      includes = {...}, libdirs = {...}, libs = {...}, defines = {},
      link_flags = {}, deps = {},
    }
  end,
})
```

之后项目里写 `dependencies = {"conan:fmt/10.2.1"}` 即可。adapter 只有两个约定：`probe()` 报告是否可用，`resolve()` 返回与原生 port 相同形状的 manifest。**不需要修改 conan 本身，也不需要重新编译 gcpkg**。

内置 adapter：

| 写法 | 说明 |
| --- | --- |
| `openssl` | 原生 port |
| `pkgconfig:libcurl` | 用 `pkg-config --cflags --libs` 解析 -I/-D/-L/-l |
| `vcpkg:fmt` | 导入 `VCPKG_ROOT/installed/<triplet>` 的 include/lib |
| `system:z` | 系统前缀 `/usr`（可用 `GCPKG_SYSTEM_PREFIX` 覆盖） |
| `call:pkg-config:--cflags,--libs,zlib` | 原样执行任意命令并解析 flags 输出 |

## 4. clangd 配置

`gcpkg build` 自动生成：

- `compile_commands.json`（项目根）：项目 + 所有传递依赖的编译命令；
- `.clangd`：把依赖 include 路径追加给所有文件；
- `.gcpkg/compdb/compile_commands.json`：同样的合并结果，便于调试。

只需要让 clangd 把项目根当工作目录（VS Code 的 `clangd.arguments: ["--compile-commands-dir=.", ...]` 或默认行为即可）。若移动了 store，重跑 `gcpkg compdb <project>` 重新合并（必要时 `--no-cache` 重建依赖）。

## 5. 常用环境变量

| 变量 | 作用 |
| --- | --- |
| `GCPKG_SHARE` | 引擎根目录（含 `lua/` 与 `ports/`） |
| `GCPKG_LUA_PATH` | 额外的 Lua 模块搜索路径（冒号分隔） |
| `GCPKG_PORTS` | 额外的 port 注册表路径（冒号分隔） |
| `GCPKG_HOME` | store 位置 |
| `GCPKG_INTERCEPT_BIN` | 覆盖 `gcpkg-intercept` 路径 |
| `GCPKG_SYSTEM_PREFIX` | `system` adapter 的前缀 |
| `GCPKG_VERBOSE` / `GCPKG_DEBUG` | 打印每条命令 / 调试日志 |
| `GCPKG_STORE`（测试脚本） | 覆盖 `tests/{smoke,chain,features,linux,media}.sh` 的 store 路径 |
| `GCPKG_MEDIA_DYNAMIC` | `tests/media.sh` 设为 1 时执行动态冒烟（lua + SDK adapter） |
| `GCPKG_<NAME>_HOME` | 外部 SDK 的安装根目录，见 `gcpkg externals` / `docs/EXTERNAL_SDKS.md` |
| `GCPKG_PROXY` / `GCPKG_NO_PROXY` | 会话级代理与绕过列表（优先于落盘配置），见 `docs/PROXY.md` |
| `GCPKG_PROXY_DYNAMIC` | `tests/proxy.sh` 设为 1 时启动本地 CONNECT 代理跑端到端 |
| `GCPKG_R10_DYNAMIC` | `tests/r10.sh` 设为 1 时全量真编译 38 个库 |
| `GCPKG_BIN`（测试脚本） | 覆盖测试使用的 gcpkg 可执行文件 |

> store 建议放在真实磁盘（`~/.cache/...`）：本沙箱 `/tmp` 只有 992M tmpfs，
> 并行编译多个库时会耗尽空间。

## 6. Meson 组件、系统组件与手写 Makefile

Meson 组件用 `recipe.meson`，`options` 既可以是一张表，也可以是
`function(ctx)`（需要把安装目录拼进 prefix 时）：

```lua
local recipe = require("gcpkg.recipe")
return recipe.meson {
  name = "kmod", version = "34.2",
  source = { url = "...", sha256 = "...", strip = 1 },
  dependencies = { "zlib" },
  meson = {
    options = function(ctx)
      return {
        tools = "false",
        ["build-tests"] = "false",
        -- 默认会写 /etc/depmod.d，非 root 沙箱装不了
        distconfdir = ctx.prefix .. "/etc/depmod.d",
        moduledir   = ctx.prefix .. "/lib/modules",
      }
    end,
    args = { "-Dc_args=-Wno-error=deprecated" },
  },
  exports = { includes = {"@PREFIX@/include"}, libs = {"kmod"} },
}
```

`build/meson.lua` 自动加 `--prefix` / `--libdir=lib` / `--sysconfdir=<prefix>/etc` /
`--localstatedir=<prefix>/var`，所以 systemd、dbus、util-linux 这类系统组件不会
写 `/etc`、`/var`。`systemd` 还要把 `rootprefix` / `rootlibdir` / `sysvinit-path`
指向 prefix，并关掉 `hwdb`（否则 install 脚本会尝试运行 `systemd-hwdb update`）。

其它常见形态：

- **纯数据 port**：`fontutil` / `xcb-proto` 只装 `.pc` / 头文件 / XML，
  `compdb_entries = 0` 是合法的；下游 `dependency('fontutil')` 靠
  `PKG_CONFIG_PATH`（含 `share/pkgconfig`）解析。
- **tarball 缺生成文件**：`pre_build(ctx)` 里 `ctx.exec({...}, {cwd=ctx.src, log=ctx.log})`
  跑 `autoreconf -fi`，必要时先用 `require('gcpkg.fs').write(ctx.src..'/NEWS','')`
  补 `NEWS`（libcap-ng / popt）。需要 `autopoint`。
- **手写 Makefile**：`recipe.make` 的 `jobs = 1` 规避没有依赖边的并行竞态；
  `vars` 里拼 `-I`、`LIBS` 时注意上游是否自行硬编码 `CC=gcc`（gcpkg 会用
  `CC=<wrapper>` 覆盖，保证 compdb 可采）。
- **系统依赖**：宿主 `-dev` 包通过 `pkgconfig` backend 使用，不需要为 `libudev`、
  `xtrans`、`libmount` 之类再写一个 port；`ports/README.md` 第「第四轮」节列出
  沙箱里实际安装的包。上游源码始终不改。

### 第四轮工具链（Debian/Ubuntu）

```
sudo apt-get install -y meson ninja-build bison flex xsltproc gettext gperf \
    autopoint python3-jinja2 python3-ply libyaml-cpp-dev liblua5.4-dev pkg-config
# 以及 X11 / systemd 所需的 -dev 包：libudev-dev libmtdev-dev libxkbfile-dev
# libxfont-dev libfontenc-dev libunwind-dev libbsd-dev libxshmfence-dev
# libx11-xcb-dev libxcb-util-dev libdbus-1-dev libdrm-dev libpciaccess-dev
# libpixman-1-dev xtrans-dev libgbm-dev libepoxy-dev libselinux1-dev libaudit-dev
# libpam0g-dev libacl1-dev libcrypt-dev libgcrypt20-dev libidn2-dev libelf-dev
# libdw-dev libglib2.0-dev libmount-dev libblkid-dev libkmod-dev libseccomp-dev
# libcap-dev libpcre2-dev liblz4-dev libzstd-dev liblzma-dev zlib1g-dev
# libssl-dev libffi-dev libexpat1-dev libarchive-dev libcurl4-openssl-dev
```
`/usr` 下的安装不随工作区快照持久化，新会话先跑
`/home/user/setup-gcpkg-toolchain.sh`。`fontutil` 没有系统 `-dev` 包，
已作为纯数据 port 纳入（X.Org 的正确文件名是 `font-util-1.4.2.tar.xz`）。

第四轮 35 个 port 的 `build.lua` / `features.yaml` 由
`tools/gen-linux-ports.py` 依据 `tools/linux-catalog.tsv`（35 条真实 URL +
SHA256 + 上游 tarball 的构建系统标记）生成，`GCPKG_PORTS` 可覆盖输出目录：

```bash
python3 tools/gen-linux-ports.py          # 重新生成 35 套 port，不影响 fontutil
./build/bin/gcpkg check --ports ./ports  # 51 ports OK
./tests/linux.sh                         # 校验 36 个新 port 的真实编译结果
```

保留生成器是为了让「按上游 tarball 的真实选项名逐个核对」这件事可复现；
运行时引擎完全不依赖它，只读取 `ports/*/build.lua` 里内嵌的 URL/SHA256。

## 7. 厂商 SDK port 与工具 port

登录墙 / 授权 / 多 GB `.run` / 已经装在机器上的 SDK（CUDA、华为 CANN、
NVIDIA Video Codec SDK、大华 PlaySDK…）不适合 `source = {url=..., sha256=...}`。
用 `gcpkg.build.external` 声明，它仍是一个普通 port：有版本、依赖、
features.yaml、manifest，能进依赖图、能被上层库引用。

```lua
local external = require("gcpkg.build.external")
return external.declare {
  name = "nvidia", version = "12.8",
  description = "NVIDIA CUDA Toolkit / driver platform",
  license = "Proprietary", homepage = "https://developer.nvidia.com/cuda-toolkit",
  dependencies = {},
  sdk = {
    env = "GCPKG_NVIDIA_HOME",              -- required, printed by `gcpkg externals`
    alt_env = { "CUDA_HOME", "CUDA_PATH" },  -- fallbacks
    default = "/usr/local/cuda",
    url = "https://developer.nvidia.com/cuda-downloads",  -- where to get it
    probe = { "include/cuda_runtime.h" },    -- layout sanity check (warn only)
    includes = { "include" },
    libdirs = { "lib64", "lib", "lib64/stubs" },
    binaries = { "bin" },
    libs = { "cudart", "cuda", "nvidia-ml" },
  },
}
```

要点：

- `source` 是函数，`net.prepare` 只在 `install` 时调用它；`check` / `graph` /
  `ports` / `externals` 是**纯静态**的，不需要装 SDK。`gcpkg externals`
  会列出每个 SDK 的变量名、是否已设置、官方下载页。
- 二进制 SDK 不编译，compdb 为 0 条；`build` 返回的 include / libdir / libs
  是绝对路径，会进入 manifest 并传导给所有依赖它的 port。
- 切换 SDK 版本：改 `$GCPKG_<NAME>_HOME` 后加 `--no-cache`（环境变量优先于
  上次写入的 `.gcpkg-sdk-root` marker）。
- 若 SDK 里确实有可编译的东西，传 `build_hook = function(ctx, root) ... end`，
  `ctx.env` 里编译器包装器与所有依赖环境变量都已就绪。
- 见 `docs/EXTERNAL_SDKS.md` 获取 4 个内置 SDK 的完整清单。

**工具 port**：`exports.binaries` 会被前置到依赖方的 `PATH`。
`ports/cmake` 就是这样被管理的 —— `folly` / `proxygen` / `vulkan` / `redpanda`
声明 `dependencies = {"cmake", ...}` 后，它们的构建优先使用 gcpkg 的 cmake，
而不是宿主的。

**静态验证**：`tests/media.sh` 检查注册表、两张自底向上图、23 个 port 的
两文件、真实 URL+SHA256、SDK 环境变量、无沙箱绝对路径、依赖可解析，
默认不下载不编译；`GCPKG_MEDIA_DYNAMIC=1` 才会真编译 `lua` 并用临时假 SDK
目录冒烟测试 adapter。生成器是 `tools/gen-media-ports.py` +
`tools/media-catalog.tsv`（`GCPKG_PORTS` 可覆盖输出目录）。

## 8. 批量新增基础库的流程

第六轮 37 个基础库用的是同一套可复现流程，适合继续扩：

```bash
# 1) 在 tools/<round>-catalog.tsv 记下真实 URL、实测 SHA256、构建系统 kind、依赖
# 2) 生成器把每库展开成 build.lua + features.yaml
python3 tools/gen-linux-base-ports.py
./build/bin/gcpkg check --ports ./ports
./build/bin/gcpkg graph gnutls --ports ./ports      # 看自底向上顺序
./tests/linux-base.sh                              # 静态：不下载不编译
GCPKG_BASE_DYNAMIC=1 ./tests/linux-base.sh         # 可选：真编译子集
```

生成器只是开发工具；运行时引擎完全不依赖它，只读 `ports/*/build.lua` 里
内嵌的 URL/SHA256。`GCPKG_PORTS` 可覆盖输出目录。

从这一轮总结出的几个坑（都不需要改引擎）：

- **GitHub tag tarball 常缺生成文件**：只有 `configure.ac` 时用
  `pre_build(ctx)` 条件跑 `autoreconf -fi`；只有 `CMakeLists.txt` 的库
  （libdeflate）不要硬套手写 Makefile 配方。
- **静态库链进 shared 会失败**：上游 configure 默认 `--enable-shared` 时，
  会把 gcpkg 的非 PIC `.a`（如 `liblzma.a`）链进 `.so`。autotools 配方统一
  加 `--disable-shared --enable-static`，与 `features.yaml` 的 `static` 默认一致。
- **增量编译让 compdb 变 0**：`net.prepare` 会复用带 marker 的源码目录，
  重跑只做增量，编译器包装器不产生新条目。要得到完整编译数据库，
  清掉 store 的 `src/<key>` + `build/<key>` 再装一次。
- **脚本别被 `pipefail` 坑**：缓存命中日志里没有 "compile commands"，
  `grep | tail` 会让 `set -euo pipefail` 提前退出，记得 `|| N="cached"`。
- **镜像失效就剔除**：`isl` 的 SourceForge / GCC 镜像全部 403/404，
  与其写占位 SHA256 不如不收（校验和必须是真实下载计算值）。

## 9. 内核 / 磁盘类库的适配要点

第七轮 34 个库（NVMe、SMART、分区、文件系统、ftrace、keyring、GPIO、IIO…）
又验证了几个常见形态，全部不改上游：

- **先解压看再写配方**：`kind`（autotools / cmake / meson / 手写 Makefile）
  是逐包检查 tarball 顶层 `configure` / `CMakeLists.txt` / `meson.build` /
  `Makefile` 得到的。`libunwind` 同时有 CMakeLists 和 configure.ac，但它的
  CMakeLists 明确只支持 Visual Studio，所以必须选 autotools。
- **只发 tag 的 GitHub 仓库**：`configure.ac` 存在而 `configure` 不在时，
  `pre_build` 条件跑 `autoreconf -fi`（本轮 10+ 个库都这样）。
- **install 写系统绝对路径**：非 root 构建遇到 `/lib/udev/rules.d`
  （libiio）、`/etc/depmod.d`（kmod）、`/sbin`（pciutils/dmidecode/hdparm）。
  前两类关选项或把目录指进 prefix；手写 Makefile 用自定义 `build(ctx)`
  编译后把 `.a` / `.h` / 二进制收集到 `<prefix>/lib|include|sbin`。
- **shared 链非 PIC 静态库**：`-DBUILD_SHARED_LIBS=OFF`（CMake）或
  `--disable-shared --enable-static`（autotools）。
- **compdb 为 0 不代表失败**：少数 Makefile 直接写 `gcc` 字面量，
  命令行 `CC=<wrapper>` 也拦不到，manifest 会如实记 0 条。
- **复核已有库**：用户点名 `liburing` 时它已在注册表里；清掉 store 的
  `src/` + `build/` 后重新 `install`，确认 14 条 compdb，再把它声明为
  `libnvme` 的依赖，让它进入新的磁盘信息链。

生成器 `tools/gen-linux-kernel-ports.py` + `tools/linux-kernel-catalog.tsv`；
静态验证 `tests/linux-kernel.sh`，动态子集 `GCPKG_KERNEL_DYNAMIC=1`。
磁盘信息相关的 port 清单与用法见 `docs/DISK_INFO.md`。


## 10. 项目工作流与多版本 port（第八轮）

### 给一个 port 声明多个真实版本

只改 `features.yaml`，`build.lua` 一行不动：

```yaml
versions:
  "1.2.13":
    source:
      url: "https://github.com/madler/zlib/releases/download/v1.2.13/zlib-1.2.13.tar.gz"
      sha256: "b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30"
```

版本号**必须加引号**（YAML 会把 `1.3` 解析成数字）。`source` 会与
`build.lua` 的默认 source 合并，所以 `strip` 等字段可以只写一次；还可以给
某个版本写 `dependencies:` 覆盖。`gcpkg versions zlib` 列出全部版本、
默认版本和各自的 URL；`gcpkg add zlib@1.2.13 -C apps/demo` 之后
`gcpkg build apps/demo` 会真的下载并编译 1.2.13，生成 `zlib-1.2.13`
manifest。未声明的版本会报错而不是悄悄用默认源码，所以校验和必须是实测值。

`features:` 与 `versions:` 是并列的两类数据：`features.resolve()` 会跳过
`schema/port/versions/dependencies/project/ports/inherit_global` 这些元数据键，
因此 `gcpkg features` 不会把 `versions` 列成一个开关。

### 项目私有 port 覆盖公有 registry

```bash
gcpkg new apps/demo
gcpkg add --local zlib -C apps/demo   # 复制公有 zlib 的两文件到 gcpkg-ports/zlib/
# 现在编辑 apps/demo/gcpkg-ports/zlib/build.lua 或 features.yaml 即可
gcpkg list -C apps/demo               # zlib 显示 [project]
```

查找顺序是 `gcpkg-ports/` → `$GCPKG_HOME/ports/` → `--ports`/引擎 `ports/`。
要覆盖用户级或公有 registry 的同名库，把它放在更靠前的 root 即可；
`gcpkg.yaml` 的 `ports:` 可以列出多个目录。项目外仍用公有版本。

### 依赖清单的作用域

项目特有依赖写在 `gcpkg.yaml` 托管区块（`add`/`remove` 管理）；公有依赖用
`gcpkg add -g` 写到 `$GCPKG_HOME/gcpkg.yaml`，项目通过
`inherit_global: true` 显式继承。默认不继承，避免「一台机器上的所有项目
被塞同一组库」。`gcpkg.lock` 记录实际解析结果，建议提交到版本库。

### 验证

`./tests/projects.sh`（默认纯静态）；
`GCPKG_PROJECT_DYNAMIC=1 ./tests/projects.sh` 真编译两个不同 zlib 版本
和 jansson 2.14。完整说明见 `docs/PROJECTS.md`。


## 11. 批量扩库的第九轮经验

`tools/extra-catalog.tsv` + `tools/gen-extra-ports.py` 是新增 43 个库的唯一源，
`tests/extra.sh` 会重跑生成器校验幂等。几条通用规则：

- **先下载再决定 kind**：GitHub tag 归档常常缺 submodule（`nghttp3` 的
  `lib/sfparse`、libtheora 的 SDL m4），优先用官方 release tarball；
  顶层 `CMakeLists.txt` / `meson.build` / `configure(.ac)` / `Makefile`
  逐个解压核对，别靠猜。
- **选项名要去上游源码里查**：`option(ZLIB_ENABLE_TESTS ...)`、
  `meson_options.txt`、`./configure --help`，写错选项会直接报
  `Unknown options` 或编译出一堆不需要的测试程序。
- **关掉文档/示例/测试**：`makeinfo`、宿主静态 `libcurl.a`、现代 libpng
  已删除的 `png_sizeof` 都是这类失败源。
- **手写 Makefile**：自定义 `build(ctx)` 里显式传 `CC=<wrapper>`，否则
  Makefile 里的字面量 `gcc` 绕过拦截器，compdb 为 0；`lmdb` 这类
  Makefile 在子目录的用 `cwd = util.join(ctx.src, ...)`。
- **没有汇编器时**：第九轮 `libvpx --target=generic-gnu` 是纯 C 目标；
  第十一轮起 `nasm` 本身是源码工具 port，`libvpx` 直接 `dependencies={"nasm"}`
  + `--as=nasm` 编 SIMD，见 `docs/TOOLCHAINS.md`。
- **SHA256 必须实测**：tag / 镜像 404 就换正式 release 或剔除，不塞占位值。

完整的 43 行表、每库 compdb 条数与修复细节见 `docs/EXTRA_LIBRARIES.md`。

## 12. 代理与第十轮扩库

代理不需要为每个 adapter 重写：`lua/gcpkg/proxy.lua` 一处解析、
`proxy.env()` 一处下发。新加下载渠道时，只要把 `env = proxy.env()` 传给
`gcpkg.exec(cmd, {...})` 即可；凭据别拼进 argv（日志与 `--verbose` 会打印
命令行），配置回显用 `proxy.redact()`。完整优先级与验证见
`docs/PROXY.md`。

第十轮沿用「TSV + 生成器」：`tools/r10-catalog.tsv`（38 行真实
URL/SHA256/kind/deps）+ `tools/gen-r10-ports.py`，`tests/r10.sh` 重跑
生成器断言幂等。几条新经验：

- **官方 release 优先**：`libbsd` 的 GitHub tag 用 `git describe` 生成
  `AC_INIT` 版本号，tag 归档里没有 `.git`，`autoreconf` 必然失败；
  `abseil` 的 tag 是 `20240722.0`（`20240722` 404）。
- **老 automake 包**：`cunit` 自带的 `Makefile` 硬编码了原作者机器路径，
  必须 `autoreconf -fi` + `./configure` 重新生成，而不是直接 `make`。
- **子目录工程**：`blake3` 的 C CMake 工程在 `c/`，用
  `cmake = { source = "c", ... }`；手写小写 `makefile` 的 `libtomcrypt`
  用 `recipe.make` 的 `vars = function(ctx) ... end` 传 `PREFIX`，
  `CC` 由 recipe 自动换成拦截器包装器。
- **真名字**：`catch2` v3 装的是 `libCatch2.a` + `libCatch2Main.a`；
  `portaudio` 静态库要关 `PA_LIBNAME_ADD_SUFFIX`。
- **校验导出物**：`tests/r10.sh` 动态部分不止看 exit code，还逐个检查
  manifest 的 `libs` 是否真有 `lib<name>.a` / `.so`，能抓出这类命名错误。

38 行表与全部适配说明在 `docs/ROUND10_LIBRARIES.md`。

## 13. 工具链 port 与 Python / Cargo adapter（第十一轮）

工具链也可以是普通 port：`nasm` / `python` 各自一个 `build.lua` +
`features.yaml`，把 `bin/` 写进 `exports.binaries`，`dependency_env()` 就
会把它 prepend 到下游的 `PATH`；`rust` 用已有的 `gcpkg.build.external`
声明 `GCPKG_RUST_HOME`。新增包管理器时照旧写一个 Lua adapter +
`recipe.lua` 的一个 kind 分支即可：

```lua
elseif kind == "python" then
    local python = require("gcpkg.build.python")
    result = python.all { src = ctx.src, prefix = ctx.prefix, exec = ctx.exec, ... }
```

三个要点：安装路径要稳定（`python` adapter 用 `pip --target` 装到
`<prefix>/lib/python3/site-packages`，正好是 `dependency_env()` 收集
`PYTHONPATH` 的路径）；adapter 里所有子进程都走 `ctx.exec`，代理与拦截
才能继承；工具链缺失时宁可做成 external port 静态声明，也不要假编译。
完整设计、pinned tarball 与踩坑见 `docs/TOOLCHAINS.md`，23 个新 port 的
清单在 `docs/ROUND11_LIBRARIES.md`。

## 14. 第十个构建系统 adapter：GN（第十二轮）

`recipe.gn` 和 `lua/gcpkg/build/gn.lua` 把 GN 当成元构建系统处理：
`gn gen --export-compile-commands` 生成 Ninja 图，随后 `ninja -C <out>`
执行编译。关键点是**返回 GN 原生 `compile_commands.json`**，让
`port.lua` 的 compdb union 把 GN 目标与所有依赖一起给 clangd：

```lua
elseif kind == "gn" then
    local gn = require("gcpkg.build.gn")
    result = gn.all {
        src = ctx.src, build_dir = ctx.build_dir,
        exec = ctx.exec, jobs = cfg.jobs or ctx.jobs,
        args = cfg.args, targets = cfg.targets,
    }
```

`gn` / `ninja` 本身也是源码工具 port；`gn.args` 支持 `function(ctx)`，
可以从 `ctx.dep("gn").prefix` 推导 `clang_path`，适配 GN 没有默认编译器
配置这一点。自定义 `source()` 可以用多个 pinned tarball 补齐空 submodule
目录（Crashpad 的 mini_chromium/LSS、TagLib 的 utfcpp），无需修改上游。
最小 GN 工程、统一 compdb 与固定源说明见 `docs/GN.md`，28 个新 port 见
`docs/ROUND12_LIBRARIES.md`。
