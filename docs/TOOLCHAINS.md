# 第十一轮：工具链 port、Python / Cargo adapter 与 `tokenizers-cpp`

用户原话：「支持 nasm，Python rust，tokenize-cpp，以及其它可能的常见库」。

这一轮把**工具链本身**也变成 port，并把两种「其它包管理器」接入 Lua adapter：
注册表 **226 → 249**（新增 23 个 port）。所有 port 仍然是一库
`build.lua` + `features.yaml`，上游源码零修改，URL 与 SHA256 全部实测。

## 1. `tokenize-cpp` 是什么

GitHub / 通用搜索里没有一个叫 `tokenize-cpp` 的库；最接近、且描述完全对得上的是
[`mlc-ai/tokenizers-cpp`](https://github.com/mlc-ai/tokenizers-cpp)：
把 HuggingFace 的 Rust `tokenizers` 包一层 C ABI（`libtokenizers_c.a`），再包一层
C++ 类（`libtokenizers_cpp.a`），另外用 sentencepiece 做 BPE 之外的分词器。
所以本轮按该项目实现，port 名 `tokenizers-cpp`（另有一个独立的 R11 普通 port
`sentencepiece` 0.2.0）。

## 2. 三种「工具」port

| port | 类型 | 来源 | 导出给下游的东西 |
| --- | --- | --- | --- |
| `nasm` 2.16.03 | **源码构建的工具 port** | NASM 官方 tarball（`configure` 已预生成） | `bin/nasm`、`bin/ndisasm` → `PATH` |
| `python` 3.12.8 | **源码构建的工具 port** | python.org CPython tarball | `bin/python3`、`include/python3.12`、`lib/libpython3.12.a` → `PATH`/`-I`/`-L` |
| `rust` `stable` | **external 工具 port** | 本机 rustup 工具链 | `bin/cargo`、`bin/rustc` → `PATH` |

`rust` 不下载源码：从零 bootstrap rustc 要数小时且需要上一代工具链，和
CUDA/CANN 之类的专有 SDK 一样用 `gcpkg.build.external.declare` 声明，
`gcpkg externals` 离线列出 `GCPKG_RUST_HOME`（或 `CARGO_HOME` /
`RUSTUP_HOME`），你在自己机器上设好即可：

```bash
export GCPKG_RUST_HOME=$HOME/.cargo          # 里面有 bin/cargo 与 bin/rustc
./build/bin/gcpkg externals --ports ./ports # rust ... set
./build/bin/gcpkg install ryu --ports ./ports
```

`port.dependency_env()` 会把依赖的 `exports.binaries` 依次 prepend 到 `PATH`，
所以 `pybind11`（依赖 `python`）、`toml`（依赖 `python`）、`ryu` 与
`tokenizers-cpp`（依赖 `rust`）拿到的 `python3` / `cargo` 一定是 gcpkg 管理的那一份，
不是宿主的。

## 3. 新 adapter：`recipe.python` / `recipe.cargo`

`lua/gcpkg/recipe.lua` 新增两个 kind，`lua/gcpkg/build/` 下新增 / 重写两个模块：

```lua
-- ports/toml/build.lua（PyPI 的 toml 0.10.2）
return recipe.python {
    ...
    dependencies = { "python" },
    python = { mode = "pip", python = "python3", args = {} },
}
```

```lua
-- ports/ryu/build.lua（dtolnay/ryu 1.0.18）
return recipe.cargo {
    ...
    dependencies = { "rust" },
    cargo = { args = {} },
}
```

- `gcpkg.build.python`：`setup.py build/install`（`mode="setup"`）或
  `python3 -m pip install --no-deps --target <prefix>/lib/python3/site-packages .`
  （`mode="pip"`）。选 `--target` 而不是 `--prefix`，因为后者会按解释器版本再嵌套
  一层 `lib/python3.12/site-packages`，破坏 `dependency_env()` 收集 `PYTHONPATH`
  的稳定路径约定。
- PEP 517 默认开启构建隔离：新编译出的 CPython 只自带 `pip`，`setuptools`/`wheel`
  由 pip 在临时环境里下载；解释器里已装好时可以设 `no_isolation = true`。
- `gcpkg.build.cargo`：`cargo build --release`，再把 `target/release` 里的
  `.a` / `.so` / `.rlib` / 可执行文件拷进 `<prefix>/lib`、`bin/`。Rust 不产生
  `compile_commands.json`（用 rust-analyzer 做跳转），但产物仍然以普通
  `-L/-l` 形式供 C/C++ 下游使用。

两个 adapter 都只通过 `ctx.exec` 走 `gcpkg.exec`，因此代理环境变量、
CC/CXX 拦截、统一构建日志对它们同样生效。

## 4. nasm 不再只是「装上了」：libvpx 真正消费它

第九轮因为没有汇编器，`libvpx` 用了纯 C 的 `--target=generic-gnu`。本轮：

- `tools/extra-catalog.tsv` 里 `libvpx` 的 deps 改成 `nasm`；
- `tools/gen-extra-ports.py` 的 `CUSTOM["vpx"]` 改成
  `--target=x86_64-linux-gcc --as=nasm`；
- `graph libvpx` = `1. nasm  2. libvpx`，manifest 的 `deps` 里出现 `nasm-2.16.03`。

真编译日志里有 `using nasm`、115 个 `.asm` 依赖规则和大量 `[AS] ... .asm.o`，
证明走的是 SIMD 路径而不是纯 C 回退。`tests/r11.sh` 会断言
`generic-gnu` 已从 `ports/libvpx/build.lua` 消失。因为 `tests/extra.sh` 每次都会
重跑 R9 生成器，这个修改同时写进了 catalog 和生成器，保证幂等。

## 5. `tokenizers-cpp`：三个 pinned tarball，一个都不改

GitHub 的 tag/commit 归档里 `msgpack/`、`sentencepiece/` 是**空 submodule 目录**，
直接 `add_subdirectory` 会失败。port 的 `source()` 用 `net.download()` +
`net.extract()` 把上游归档填进这两个目录；`build()` 用 `cmake.configure` +
`cmake.build`（上游没有 `install()` 规则），再把头文件与静态库拷进 prefix，
并把 CMake 原生 `compile_commands.json` 通过 `compdb_files` 并入统一 compdb。

| 归档 | 固定点 | SHA256 前缀 |
| --- | --- | --- |
| `mlc-ai/tokenizers-cpp` | main commit `c586c52`（2026-05-20） | `257acdeb…` |
| `msgpack/msgpack-c` | `.gitmodules` pinned commit `092bc69b` | `ef02fd4b…` |
| `google/sentencepiece` | 上游 v0.2.0 release | `9970f0a0…` |

**为什么不是 v0.1.1 tag**：v0.1.1 的 `rust/src/lib.rs` 把 `std::HashMap` 传给
`tokenizers 0.21.4` 的 `BPE::new()`，而后者现在要 `ahash::AHashMap`，它自带的
`Cargo.lock` 正好锁了 0.21.4 → 编译报 `E0308`。上游在 main 上加了 `ahash`
依赖修好，所以这里**固定到修好的上游 revision**，而不是给上游打补丁。

**为什么 sentencepiece 用 v0.2.0 而不是 main 的 0.2.2 submodule commit**：
0.2.2 在 configure 阶段用 `FetchContent` 去 `git clone` abseil（未固定 SHA），
会让源码集合变得不可复现；v0.2.0 release 自带 `third_party/protobuf-lite` 与
absl，配合 `SPM_PROTOBUF_PROVIDER=internal` / `SPM_ABSL_PROVIDER=internal`
即可完全离线固定。这个取舍在 `ports/tokenizers-cpp/build.lua` 注释里也写明了。

导出的 4 个静态库按顺序链接：
`tokenizers_cpp → tokenizers_c → sentencepiece → onig`（`libonig.a` 是 Rust
`onig_sys` 编出来的 C 依赖）。cargo 在 `target/release/deps/` 里还会产生带哈希的
同内容静态库，port 明确跳过 `/deps/`，避免重复符号。

端到端验证（沙箱内临时装了 rustc/cargo 1.99.1）：

```bash
g++ -std=c++17 link.cpp -I<prefix>/include -L<prefix>/lib \
  -Wl,--start-group -ltokenizers_cpp -ltokenizers_c -lsentencepiece -lonig \
  -Wl,--end-group -lpthread -ldl -lm -o link
./link     # C++ → C ABI → Rust staticlib 链接并执行成功
```

## 6. 本轮踩过的坑（都写进回归）

- **宿主 `pkg-config` 污染**：沙箱默认 `pkg-config --libs ncursesw` 指向另一份
  静态 ncurses（非 `-fPIC`），CPython 编 `_curses` 共享扩展时链接失败。
  `python` port 的 `pre_build` 把 `PKG_CONFIG_LIBDIR` 指向空目录、
  `PKG_CONFIG_PATH` 置空，让 configure 回退到系统共享库；不改上游任何文件。
- **Python adapter 的 setuptools**：CPython 3.12 的 `ensurepip` 不再捆绑
  setuptools，`toml` 的 `setup.py` 需要它。改用 `mode="pip"` + PEP 517 构建隔离。
- **highway 的 `contrib/sort/vqsort`**：每个 TU 的模板实例化会吃掉数 GB 内存，
  4 个并行编译把沙箱打满并拖垮后续构建。用上游原生开关
  `-DHWY_ENABLE_CONTRIB=OFF` 只编核心库（22 条 compdb，6 秒）。
- **oneTBB 静态构建没有 `tbbmalloc_proxy`**：`exports.libs` 收敛为
  `tbb` + `tbbmalloc`，由动态回归逐个校验 `lib<name>.a` 是否真的存在。
- **内存密集 TU 要限并行**：`sentencepiece` 的 trainer / processor 翻译单元
  每个约 1GB RAM，4 个并行 `cc1plus` 会把小机器打进 swap（45 秒变成超时）。
  `recipe.cmake` 现在支持 `cmake = { jobs = 2 }` 逐 port 上限，
  `tests/r11.sh` 动态部分统一用 `-j2`。
- **超时要杀进程组**：`subprocess.run(timeout=)` 只杀直接子进程，
  `make -j4` 的 `cc1plus` 会变孤儿继续跑。动态脚本用 `start_new_session`
  + `os.killpg`。

## 7. 验证边界与复现

| 范围 | 状态 |
| --- | --- |
| 17 个常见 C/C++ 库 | 干净源码真编译 PASS |
| `nasm`、`python`、`toml`、`libvpx`（SIMD） | 干净源码真编译 PASS |
| `rust`（external）、`ryu`（Cargo）、`tokenizers-cpp`（Rust→C→C++） | 沙箱临时装 rustc/cargo 后**真编译 + 静态链接执行 PASS** |
| 需要登录 / 专有 SDK / GPU / 多 GB `.run` 的旧 port | 仍只做静态声明，不谎报动态通过 |

```bash
./build/bin/gcpkg check --ports ./ports            # 249 ports OK
./tests/r11.sh                                     # 静态
CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup \
  GCPKG_R11_DYNAMIC=1 ./tests/r11.sh               # 全量真编译（有 Rust 时 24/24）
```

全新 store 实测：`GCPKG_R11_DYNAMIC=1 ./tests/r11.sh` →
**24 PASS / 0 FAIL，1353 条编译命令**（23 个新 port + `libvpx`），
其中 `python` 263、`libvpx` 211、`jemalloc` 188、`tokenizers-cpp` 153、
`eigen` 143、`sentencepiece` 114、`nasm` 85、`onetbb` 80。

没有 Rust 工具链时动态脚本会跳过 `rust` / `ryu` / `tokenizers-cpp` 并打印
warning，其余 21 个照常真编译；静态断言（依赖链、external 声明、pinned SHA、
生成器幂等）始终执行。

其余 17 个库的清单、版本与条件 feature 见
[docs/ROUND11_LIBRARIES.md](ROUND11_LIBRARIES.md)；代理优先级见
[docs/PROXY.md](PROXY.md)。
