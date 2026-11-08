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
