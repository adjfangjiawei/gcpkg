# 编写 port

每个库占一个目录，只包含两个文件：

```text
ports/<name>/build.lua
ports/<name>/features.yaml
```

可以从模板开始：

```bash
gcpkg port new mylib
gcpkg check --ports ./ports
gcpkg graph mylib --ports ./ports
gcpkg install mylib --ports ./ports
```

## build.lua

`build.lua` 返回一个 Lua 表。标准字段如下：

```lua
local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "mylib",
    version = "1.2.3",
    license = "MIT",
    homepage = "https://example.com/mylib",
    description = "Short description",
    source = {
        url = "https://example.com/mylib-1.2.3.tar.gz",
        sha256 = "64-hex-character-sha256",
        strip = 1,
    },
    dependencies = { "zlib" },
    cmake = {
        defines = {
            BUILD_TESTING = "OFF",
            CMAKE_BUILD_TYPE = "Release",
            CMAKE_INSTALL_LIBDIR = "lib",
            BUILD_SHARED_LIBS = "OFF",
        },
        args = {},
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "mylib" },
        binaries = {},
    },
}
```

`source.sha256` 应固定为上游归档的真实校验值。`@PREFIX@` 展开为本次安装 prefix；`@LIBDIR@` 展开为 `lib` 或 `lib64`。`exports` 中的函数会在构建后按 `ctx` 求值。

## 声明式 recipe

`gcpkg.recipe` 提供以下构建类型：

| 函数 / kind | 适用上游 | 主要配置 |
| --- | --- | --- |
| `recipe.cmake` | CMake | `cmake.defines`、`cmake.args`、`cmake.generator`、`cmake.jobs` |
| `recipe.meson` | Meson | `meson.options`、`meson.args`、`meson.libdir` |
| `recipe.autotools` | Autotools | `autotools.args`、`autotools.install_target` |
| `recipe.make` | 手写 Makefile | `make.vars`、`make.targets`、`make.install_target` |
| `recipe.gn` | GN + Ninja | `gn.args`、`gn.targets`、`gn.gn`、`gn.ninja` |
| `recipe.python` | setup.py / pip | `python.args`、`python.mode` |
| `recipe.cargo` | Rust crate | `cargo.args` |
| `recipe.header` | 纯头文件库 | `header.headers`、`header.include`、`header.flags` |

`recipe.header` 会把指定头文件复制到 `<prefix>/include`，把 `license_files` 复制到 `<prefix>/share/doc/<name>`，并编译一个生成的 probe translation unit，使编译数据库包含该库的真实编译命令。`prelude` 可加入需要先包含的标准头，`cxx = false` 可切换为 C probe。

GN 构建通过 `recipe.gn` / `gcpkg.build.gn` 接入；`gn gen --export-compile-commands` 与 `ninja` 产生的原生 compdb 会合并到统一数据库。

## 自定义步骤

```lua
port.pre_build = function(ctx)
    ctx.exec({ "autoreconf", "-fi" }, { cwd = ctx.src, log = ctx.log })
end

port.post_install = function(ctx)
    local fs = require("gcpkg.fs")
    local util = require("gcpkg.util")
    local doc = util.join(ctx.prefix, "share", "doc", "mylib")
    fs.mkdirs(doc)
    ctx.exec({ "cp", "-a", util.join(ctx.src, "LICENSE"), doc }, { log = ctx.log })
end

port.build = function(ctx)
    -- 完全自定义构建；返回 exports 表
end
```

`ctx` 提供 `src`、`build_dir`、`prefix`、`exec`、`log`、`env`、`jobs`、`compiler`、`record`、`feature_args()`、`all_dependencies` 等字段。自定义 `build(ctx)` 仍需返回 `includes`、`libdirs`、`libs`、`binaries` 与可选 `compdb_files`。

## features.yaml

```yaml
schema: 1
port: mylib

features:
  zlib:
    default: false
    description: Enable zlib compression
    args: ["-DWITH_ZLIB=ON"]
    requires: ["zlib"]
  shared:
    default: false
    description: Build shared libraries
    args: ["-DBUILD_SHARED_LIBS=ON"]
    conflicts: ["static"]
  static:
    default: true
    description: Build static libraries
    args: ["-DBUILD_SHARED_LIBS=OFF"]
```

`args` 会追加到 recipe 的构建参数。`requires` 可引入条件依赖；`conflicts` 阻止互斥特性；`provides`、`defines`、`env` 可按需使用。

多版本 port 在 `features.yaml` 中声明 `versions:`，每个版本给出独立 `source.url` 与 `source.sha256`，也可以覆盖 `dependencies`。`gcpkg versions PORT` 列出可用版本，`PORT@VERSION` 选择指定版本。

## 外部 SDK 与系统组件

需要登录或专有 SDK 的库可以写成 `gcpkg.build.external` 声明式 port，用环境变量指向本机已安装的 SDK。`gcpkg externals` 会列出这些 port 与所需变量。系统 `-dev` 包通过 `pkgconfig` backend 接入，不下载源码。

## 维护清单

仓库的 `tools/*-catalog.tsv` 保存了批量 port 的来源、版本、校验值、URL 与描述；`tools/gen-*-ports.py` 从清单生成标准两文件 port。新增单个库时直接写两个文件即可；批量新增时保持清单与生成脚本一致，并用以下命令检查：

```bash
gcpkg check --ports ./ports
gcpkg graph mylib --ports ./ports
gcpkg install mylib --ports ./ports --no-cache
```

port 文件只描述上游来源和构建选项，不写本机专用路径，不修改上游源码。
