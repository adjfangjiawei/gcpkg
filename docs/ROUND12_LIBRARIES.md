# 第十二轮新增库与工具链清单（249 → 277）

本轮响应用户「请支持gn构建系统，以及更多的库」：新增 28 个 port，其中
25 个常见 C/C++ 库、2 个源码工具 port（`ninja`、`gn`）、1 个真实 GN 库
（`crashpad`）。加上 R11 的 249 个，注册表共 **277 个 port**；仍然是一库
`build.lua` + `features.yaml`、上游零修改、按 L0 → 更高层真编译自底向上扩展。

权威 source / SHA256 / 版本 / 依赖列表在 `tools/r12-catalog.tsv`；普通 21 个库
由 `tools/gen-r12-ports.py` 生成，另外 7 个需要自定义 `source()` 或 `build()`
的 port 由 `tools/gen-r12-special-ports.py` 生成。两个生成器都能逐字节复现
仓内文件，静态回归在 `tests/r12.sh`。

## 25 个新库

| port | 版本 | 构建系统 | 产物 / 说明 |
| --- | --- | --- | --- |
| `unity` | 2.6.0 | CMake | `libunity.a`、Unity C 测试框架 |
| `cmocka` | 1.1.7 | CMake | `libcmocka.a`、C mock 框架 |
| `cereal` | 1.3.2 | CMake | header-only C++ 序列化；`JUST_INSTALL_CEREAL` |
| `range-v3` | 0.12.0 | CMake | header-only C++ ranges；测试/文档关闭 |
| `date` | 3.0.3 | CMake | header-only date/time；tz lib 关闭 |
| `ms-gsl` | 4.2.0 | CMake | Microsoft GSL 无扩展名头文件 |
| `unordered-dense` | 4.8.0 | CMake | header-only robin-hood hash map |
| `taskflow` | 3.10.0 | CMake | header-only C++ task graph |
| `cpp-sort` | 1.17.0 | CMake | header-only C++ 排序算法 |
| `argparse` | 3.2 | CMake | header-only C++ 参数解析 |
| `plog` | 1.1.10 | CMake | header-only C++ 日志 |
| `libgit2` | 1.9.1 | CMake | `libgit2.a`；**真实依赖 `zlib` port**，不用 bundled zlib |
| `leveldb` | 1.23 | CMake | `libleveldb.a`；测试/benchmark 关闭 |
| `openjpeg` | 2.5.3 | CMake | `libopenjp2.a`；JPEG-2000 |
| `taglib` | 2.0.2 | CMake | `libtag.a`；空 utfcpp submodule 用固定 tarball 补齐；`zlib` 为条件依赖 |
| `libebur128` | 1.2.6 | CMake | `libebur128.a`；EBU R128 响度 |
| `lzo` | 2.10 | CMake | `liblzo2.a` |
| `file` | 5.46 | autotools | `libmagic.a` + `file(1)` |
| `capnproto` | 1.1.0 | CMake | 11 个 `libcapnp*`/`libkj*` 静态库 + `capnp` 工具 |
| `gsl` | 2.8 | autotools | `libgsl.a` / `libgslcblas.a` |
| `fftw` | 3.3.10 | CMake | `libfftw3.a`，单线程静态 |
| `apr` | 1.7.5 | autotools | `libapr-1.a` |
| `mongoose` | 7.15 | 自定义 CC | 单文件 `mongoose.c` → `libmongoose.a`，用 gcpkg CC wrapper 记录 compdb |
| `uthash` | 2.3.0 | 自定义 CC | header-only C 容器；真编译一个上游 `tests/test1.c` |
| `readerwriterqueue` | 1.0.6 | 自定义 CXX | header-only SPSC 队列；真编译两个上游测试 TU |

## 3 个 GN / 工具 port

| port | 版本 | 依赖 | 说明 |
| --- | --- | --- | --- |
| `ninja` | 1.12.1 | — | CMake 真编译，导出 `bin/ninja` |
| `gn` | `2026.02-3dff66e` | `ninja` | 固定 GitHub 镜像 commit，`gen.py` + ninja 真编译，导出 `bin/gn` 与 Clang shim |
| `crashpad` | `main-f3769d9` | `gn` | `recipe.gn` 真编译 5 个静态库；mini_chromium/LSS 用固定 tarball 补齐 |

`gcpkg graph crashpad` = `ninja → gn → crashpad`；
`gcpkg graph libgit2` = `zlib → libgit2`；
`gcpkg graph taglib --feature=taglib:zlib` = `zlib → taglib`，默认图不含 zlib。
这同时覆盖了自底向上工具链、普通库宽依赖面和 YAML 条件依赖。

## 源固定与零修改

- 所有 28 个主 tarball 都是真实匿名 HTTPS URL + 实测 SHA256。
- `crashpad` 额外固定 mini_chromium 与 LSS 两个 tarball；`taglib` 额外固定
  utfcpp submodule commit。每个额外 tarball 同样有 SHA256。
- googlesource `+archive/refs/heads/main.tar.gz` 带时间戳、两次下载 SHA
  不同，因此 GN 工具 port 不用 moving archive，而用 GitHub 镜像的 commit
  codeload tarball。
- 没有给上游打补丁：配置全部通过 CMake/autotools/GN args、port 自己的
  `source()` / `post_install()` 和 `ctx.record()` 完成。

## 验证

```bash
cmake -S . -B build && cmake --build build -j
./build/bin/gcpkg check --ports ./ports     # 277 ports OK
bash tests/r12.sh                          # 默认静态回归
GCPKG_R12_DYNAMIC=1 bash tests/r12.sh     # 干净 store 真编译 28 个新 port
```

动态回归逐个检查 manifest、导出的 `.a`/`.so`、include 目录、bin 目录和
compdb；另外实跑 `gn --version` / `ninja --version`、最小 GN fixture，
并用项目模式 `gcpkg compdb` 验证统一编译数据库覆盖 GN/Ninja/Crashpad
三层源码。最终动态数字与日志路径记录在本节末尾：

`动态结果：28 PASS / 0 FAIL，4527 条 compile commands`（干净 store
`/home/user/.cache/gcpkg-r12-final-store`，日志
`/home/user/.cache/gcpkg-r12-final.log`）。逐 port compdb：

| port | compdb | port | compdb | port | compdb |
| --- | ---: | --- | ---: | --- | ---: |
| unity | 4 | cmocka | 4 | cereal | 2 |
| range-v3 | 2 | date | 4 | ms-gsl | 2 |
| unordered-dense | 2 | taskflow | 2 | cpp-sort | 2 |
| argparse | 2 | plog | 2 | libgit2 | 402 |
| leveldb | 82 | openjpeg | 48 | taglib | 224 |
| libebur128 | 5 | lzo | 154 | file | 23 |
| capnproto | 166 | gsl | 1565 | fftw | 934 |
| apr | 170 | mongoose | 2 | uthash | 2 |
| readerwriterqueue | 4 | ninja | 62 | gn | 301 |
| crashpad | 355 | **合计** | **4527** | | |

额外动态断言：`gn --version` / `ninja --version` 可执行；Crashpad 5 个
静态库与 355 条 GN 原生 compdb 存在；最小 GN fixture 的
`gn gen --export-compile-commands` + `ninja` + `hello` 运行成功；
`taglib:zlib` 的 `CMakeCache.txt` 命中 gcpkg zlib prefix 且 `WITH_ZLIB=ON`；
项目模式 `gcpkg compdb` 合并出 718 条、所有源文件路径有效，覆盖
`ninja` / `gn` / `crashpad` 三层。

> 沙箱快照不持久保存 `~/.cache/gcpkg-*-store`；旧轮次的
> `tests/{chain,features,linux,smoke}.sh` 在没有缓存 store 时保留静态
> 图/注册表检查并明确 SKIP 产物断言，`GCPKG_FORCE_DYNAMIC=1` 可强制重建。
