# 第十一轮新增库清单（226 → 249）

用户一句「支持 nasm，Python rust，tokenize-cpp，以及其它可能的常见库」。
本轮新增 **23 个 port**：17 个常见 C/C++ 库 + 6 个工具链 / 多语言 port。
工具链、`recipe.python` / `recipe.cargo` 与 `tokenizers-cpp` 的设计详见
[docs/TOOLCHAINS.md](TOOLCHAINS.md)。

权威源：`tools/r11-catalog.tsv`（17 行实测 URL / SHA256 / kind / deps）+
`tools/gen-r11-ports.py`（导出物、构建开关、条件 feature）；另 6 个手写 port
由 `tools/gen-r11-toolchain-ports.py` 生成，保证逐字节可复现。`tests/r11.sh`
会重跑两个生成器并 `diff` 全部 23 组文件。

## 17 个常见库

| port | 版本 | 构建系统 | 依赖 | 说明 |
| --- | --- | --- | --- | --- |
| `pybind11` | 2.13.6 | cmake | `python` | C++/Python 绑定（头文件库） |
| `mimalloc` | 2.1.2 | cmake | — | 微软紧凑分配器 |
| `jemalloc` | 5.3.0 | autotools | — | 可扩展并发 malloc |
| `eigen` | 3.4.0 | cmake | — | 线性代数模板库，include 路径特殊 |
| `cli11` | 2.4.2 | cmake | — | 命令行解析（头文件库） |
| `cxxopts` | 3.2.0 | cmake | — | 轻量命令行选项 |
| `toml11` | 4.2.0 | cmake | — | C++ TOML 解析/序列化 |
| `concurrentqueue` | 1.0.4 | cmake | — | 无锁并发队列，include 路径特殊 |
| `robin-map` | 1.3.0 | cmake | — | robin-hood 哈希容器 |
| `simdutf` | 5.6.3 | cmake | — | SIMD Unicode 校验/转码 |
| `ada` | 2.9.2 | cmake | — | WHATWG URL 解析 |
| `xsimd` | 13.0.0 | cmake | — | C++ SIMD 封装（头文件库） |
| `cpp-httplib` | 0.20.1 | cmake | 可选 `openssl,zlib` | 单头文件 HTTP/HTTPS |
| `highway` | 1.2.0 | cmake | — | 可移植 SIMD；关掉 `contrib` 避免 OOM |
| `onetbb` | 2022.0.0 | cmake | 可选 `python` | oneAPI TBB |
| `msgpack` | 6.0.1 | cmake | — | MessagePack C/C++ |
| `sentencepiece` | 0.2.0 | cmake | 可选 `shared` | 神经网络分词器 |

## 6 个工具链 / 多语言 port

| port | 版本 | 形态 | 依赖 | 说明 |
| --- | --- | --- | --- | --- |
| `nasm` | 2.16.03 | 源码工具 port | — | 导出 `bin/nasm`；`libvpx` 真正消费 |
| `python` | 3.12.8 | 源码工具 port | — | CPython，导出 `python3` / headers / `libpython3.12.a` |
| `rust` | `stable` | external 工具 port | — | `GCPKG_RUST_HOME`，导出 `cargo` / `rustc` |
| `tokenizers-cpp` | `main-c586c52` | 多源 + cmake + cargo | `rust` | Rust → C → C++ 绑定，3 个 pinned tarball |
| `toml` | 0.10.2 | `recipe.python` | `python` | PyPI 包，装进 `<prefix>/lib/python3/site-packages` |
| `ryu` | 1.0.18 | `recipe.cargo` | `rust` | Rust crate，产物 `libryu.rlib` |

另外改动了已有的 `ports/libvpx`（R9）：deps 加 `nasm`，
`--target=generic-gnu` → `--target=x86_64-linux-gcc --as=nasm`，
并同步改 `tools/extra-catalog.tsv` 与 `tools/gen-extra-ports.py`。

## 条件依赖（默认图保持精简）

```bash
./build/bin/gcpkg graph cpp-httplib                       # 只有自己
./build/bin/gcpkg graph cpp-httplib --feature=tls        # openssl → zlib → cpp-httplib
./build/bin/gcpkg graph onetbb --feature=python         # python → onetbb
./build/bin/gcpkg graph libvpx                          # nasm → libvpx
./build/bin/gcpkg graph toml                            # python → toml
./build/bin/gcpkg graph ryu                             # rust → ryu
./build/bin/gcpkg graph tokenizers-cpp                  # rust → tokenizers-cpp
```

`cpp-httplib:tls` 的 `requires: [openssl, zlib]` 还追加
`-DHTTPLIB_REQUIRE_OPENSSL=ON -DHTTPLIB_REQUIRE_ZLIB=ON`；
`onetbb:python` 追加 `-DTBB4PY_BUILD=ON`；
`sentencepiece:shared` 追加 `-DSPM_ENABLE_SHARED=ON`。

## 真编译结果

沙箱里 17 个普通库 + `nasm` / `python` / `toml` / `libvpx` 全部干净源码
真编译通过；临时装一份 rustc/cargo 1.99.1 后，`rust` / `ryu` /
`tokenizers-cpp` 也真编译通过，且用 `g++` 把 C++ → C → Rust 的 4 个静态库
链接成可执行文件并运行成功。逐库结果由 `GCPKG_R11_DYNAMIC=1 ./tests/r11.sh` 从**全新 store** 复现：
**24 PASS / 0 FAIL，1353 条编译命令**（23 个新 port + `libvpx`）。

重点证据：

- `libvpx` 构建日志含 `using nasm`、115 个 `.asm` 规则、`[AS] ... .asm.o`，
  manifest 的 `deps` 为 `['nasm-2.16.03']`；
- `python` 263 条编译命令 + `libpython3.12.a`；`toml` 装到
  `lib/python3/site-packages/toml`，用该 CPython `import toml` 成功；
- `ryu` 产出 `lib/libryu.rlib`；
- `tokenizers-cpp` 产出 `libtokenizers_cpp.a`、`libtokenizers_c.a`、
  `libsentencepiece.a`、`libonig.a` + 两个头文件，153 条编译命令，
  静态链接执行通过；
- `sentencepiece` 的重模板 TU 用 `cmake = { jobs = 2 }` 限制并行，避免
  4 个 `cc1plus` 同时把构建机打进 swap。

## 验证与边界

```bash
./build/bin/gcpkg check --ports ./ports                 # 249 ports OK
./tests/r11.sh                                         # 静态（默认）
GCPKG_R11_DYNAMIC=1 ./tests/r11.sh                     # 无 Rust 时 21 个真编译 + 3 个静态
CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup \
  GCPKG_R11_DYNAMIC=1 ./tests/r11.sh                   # 有 Rust 时 24 个全真编译
```

- 需要登录、许可、GPU 或多 GB `.run` 的专有 SDK port 仍只做静态声明；
- 无 rustc/cargo 的机器上 3 个 Rust 相关 port 自动跳过动态部分并打印 warning，
  绝不报成「真编译通过」；
- 所有 URL 与 SHA256 实测；`utf8cpp 3.2.5`（延续第九轮的 404）、
  `libevent` / `libsodium` / `libuv` 等已有 port 本轮故意不重复生成。
