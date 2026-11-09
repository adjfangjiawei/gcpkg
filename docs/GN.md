# GN 构建系统支持（第十二轮）

本轮把 GN 作为**第十种 Lua adapter**接入：一个库仍然只有 `build.lua` +
`features.yaml`，上游源码不修改。`GN` 自己只是一个元构建系统：它读取
`.gn` / `BUILD.gn` / `BUILDCONFIG.gn`，生成 Ninja 文件，再由 `ninja` 编译。
因此 gcpkg 不把 GN 伪装成编译器，而是让工具链和编译数据库各归其位。

## 三个层次

1. **源码工具 port `ninja`**：用 Ninja 自带的 CMake 工程真编译 v1.12.1，
   导出 `bin/ninja` 到依赖的 `PATH`。
2. **源码工具 port `gn`**：固定在
   `timniederhausen/gn` 的 `3dff66ec91e3e0f39ab1b00cf7abcc6b097bae35`
   （GitHub codeload 的 tarball SHA256 稳定，而 googlesource `+archive`
   带时间戳，不适合作为固定 source）。用上游 `build/gen.py` +
   `--generate-compilation-database --allow-warnings --no-last-commit-position`
   和刚编出的 `ninja` 真编译 GN。`CXX=g++` 避免 `gen.py` 去 CIPD 下载
   Clang；archive 没有 `.git`，所以由 port 写出 gen.py 本应生成的
   `last_commit_position.h`（`0 (UNKNOWN)`），**不改任何上游文件**。
3. **Lua adapter `lua/gcpkg/build/gn.lua` + `recipe.gn`**：
   `gn gen <out> --export-compile-commands [--args=...]`，然后
   `ninja -C <out> -j N <targets...>`。GN 原生产出的
   `<out>/compile_commands.json` 通过 `compdb_files` 进入 gcpkg 的统一
   `compile_commands.json`，clangd 就能跳转 GN 目标以及全部依赖源码。

`gn` 工具 port 还导出一个稳定的 `libexec/gcpkg-gn-clang/bin/{clang,clang++,llvm-ar}`
shim 目录，链接到宿主 Clang 22。GN 没有默认编译器配置；Crashpad 的
`clang_path` 参数指向这个目录，因此 `ninja` 命令和 compdb 里的编译器路径
在安装后仍然有效。shim 是工具链文件，不是上游补丁。

## 一个真实 GN 库：Crashpad

`ports/crashpad` 不是玩具 port。它用 `recipe.gn` 构建
`chromium/crashpad`（固定 commit `f3769d9…`），并调用 `client` / `util`
两个 GN target。GitHub release/archive 会把 git submodule 目录留空，所以
`source()` 用三个固定 SHA256 的 tarball 组装源码树：

| 内容 | 固定来源 |
| --- | --- |
| Crashpad | GitHub commit `f3769d9630dc028cec188263f860ea80bb0e24c9` |
| mini_chromium | `chromium/mini_chromium` commit `c0299833…`（Crashpad `DEPS` 指定的版本） |
| Linux-syscall-support | `lnarea/chromium-lss` commit `ed31caa6…`（包含新版 `sigtimedwait` 封装） |

GN 生成 Ninja 图后，`ninja` 真编译出 `libclient.a`、`libcommon.a`、
`libutil.a`、`libcompat.a`、`libbase.a`。Crashpad 没有 install 规则，
post_install 只把公共头文件树和静态库复制到自己的 prefix，源码仍零修改。
`gcpkg graph crashpad` 为 3 步：`ninja → gn → crashpad`。

> 探测过 Perfetto v59.1、libyuv、BoringSSL、Crashpad：前两者依赖
> Chromium build tree 或 gclient/CIPD 补齐 `buildtools/{libcxx,protobuf,re2,abseil-cpp}`，
> BoringSSL 当前不是 GN 工程。它们没有被包装成「零修改独立 GN 库」谎报动态通过；
> Crashpad 在本轮用三个固定 tarball 真正独立编译。

## 最小项目 smoke

`tests/fixtures/gn-simple/` 是 gcpkg 自己写的 5 文件 GN 工程（`.gn`、
`BUILDCONFIG.gn`、toolchain、root `BUILD.gn`、`hello.cc`），覆盖 GN 所需的
全部最小配置。动态回归用 gcpkg 编出的 `gn` / `ninja`：

```bash
GN=$STORE/pkg/gn-2026.02-3dff66e/bin/gn
NINJA=$STORE/pkg/ninja-1.12.1/bin/ninja
PATH="$(dirname "$GN"):$(dirname "$NINJA"):$PATH" \
  "$GN" gen out --export-compile-commands
PATH="$(dirname "$GN"):$(dirname "$NINJA"):$PATH" \
  "$NINJA" -C out -j2 hello
./out/hello        # gcpkg GN adapter OK
```

`out/compile_commands.json` 有 1 条命令；Crashpad / gn / ninja 三个 port
实测分别贡献 355 / 301 / 62 条编译命令。项目模式用
`gcpkg new` + `gcpkg add crashpad` + `gcpkg compdb` 合并得到 718 条，
其中包含 GN 工具、Ninja 工具和 Crashpad 的源码命令。
`GCPKG_R12_DYNAMIC=1 ./tests/r12.sh` 的最终全量结果为
**28 PASS / 0 FAIL、4527 条 compile commands**。

## 使用方式

```lua
local recipe = require("gcpkg.recipe")
return recipe.gn {
    name = "my-gn-lib", version = "1.0",
    dependencies = { "gn" },
    source = { url = "...", sha256 = "...", strip = 1 },
    gn = {
        args = { "is_debug=false", 'clang_path="/path/to/toolchain"' },
        targets = { "my_lib" },
        jobs = 2,
    },
    -- 可选：上游没有 install() 时复制头文件/静态库
    post_install = function(ctx) ... end,
    exports = { includes = {}, libdirs = {}, libs = {}, binaries = {} },
}
```

`gn.args` 也支持 `function(ctx)`，可以像 Crashpad 一样从 `ctx.dep("gn").prefix`
计算 `clang_path`。特性开关追加的 `--args` 片段同样会进入 `gn gen`。
详见 `tests/r12.sh`、`docs/ROUND12_LIBRARIES.md` 与 `docs/EXTENDING.md`。
