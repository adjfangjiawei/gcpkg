# Port 注册表

每个库恰好两个文件：`build.lua`（构建描述）+ `features.yaml`（特性描述）。
`gcpkg ports` 按依赖层级列出，`gcpkg graph <port>` 打印自底向上的构建顺序，
`gcpkg check` 校验文件齐全、Lua 可加载、依赖可解析。

## L0：无 gcpkg 依赖的基础库

| port | 版本 | 构建系统 | 产物 | 已验证 |
| --- | --- | --- | --- | --- |
| `bzip2` | 1.0.8 | 手写 Makefile（自定义 build.lua） | `libbz2.a` / `bzlib.h` | ✅ 9 条编译命令 |
| `brotli` | 1.1.0 | CMake | `libbrotli{common,enc,dec}.a` | ✅ 66 |
| `cares` | 1.34.5 | CMake | `libcares` | ✅ 184 |
| `expat` | 2.7.1 | CMake | `libexpat.a` | ✅ 8 |
| `libffi` | 3.4.8 | autotools | `libffi.a` / `ffi.h` | ✅ 10 |
| `lz4` | 1.10.0 | CMake（`build/cmake`） | `liblz4.a` | ✅ 12 |
| `openssl` | 3.4.1 | `perl Configure` + make（自定义 build.lua） | `libssl.a` / `libcrypto.a` | ✅ 1128 |
| `pcre2` | 10.45 | CMake | `libpcre2-8.a` | ✅ 62 |
| `xz` | 5.8.1 | CMake | `liblzma.a` | ✅ 200 |
| `zlib` | 1.3.1 | CMake | `libz.a` / `libz.so` | ✅ 62 |
| `zstd` | 1.5.7 | CMake（`build/cmake`） | `libzstd.a`（`shared` 特性可出 `.so`） | ✅ 80 |

全部源码包都带 SHA256 校验（校验和来自实际下载的 tarball），编译数据库由
`gcpkg-intercept` 或构建系统自身的 `compile_commands.json` 生成。

## 常用写法

```lua
local recipe = require("gcpkg.recipe")
return recipe.cmake {
  name = "foo", version = "1.2.3",
  source = { url = "...", sha256 = "...", strip = 1 },
  dependencies = { "zlib" },
  cmake = { defines = { BUILD_TESTING = "OFF" } },
  exports = { includes = {"@PREFIX@/include"}, libdirs = {"@LIBDIR@"},
              libs = {"foo"} },
}
```

`recipe.autotools` / `recipe.make` / 自定义 `build(ctx)` 见
[docs/EXTENDING.md](../docs/EXTENDING.md)。上层库声明 `dependencies` 后，所有
下层库的 `-I` / `-L` / `PKG_CONFIG_PATH` / `CMAKE_PREFIX_PATH` 会自动出现在它的
构建环境里，无需修改上游项目。
