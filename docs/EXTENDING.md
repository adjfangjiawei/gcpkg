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
