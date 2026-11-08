# 外部 / 专有 SDK port

有些库没有可匿名下载的源码包：需要登录、接受许可、是 1–2 GB 的 `.run`
安装器，或者本来就已经装在机器上了（CUDA、华为 CANN、NVIDIA Video Codec
SDK、大华 PlaySDK）。gcpkg 仍然把它们当作**普通 port** 管理 —— 有
`build.lua` + `features.yaml`、有版本和依赖、能进依赖图、能被上层库引用、
安装后写 manifest —— 只是源码获取与构建方式不同。

实现见 `lua/gcpkg/build/external.lua`。设计约束：

- **上游零修改**：不复制、不打补丁、不重编译厂商二进制。
- **静态可验证**：`source` 是函数，`net.prepare` 只在 `gcpkg install` 时
  调用它；`check` / `graph` / `ports` / `externals` 在没有装任何 SDK 的
  机器上也能跑（本沙箱就是这样验证的）。
- **零编译命令**：二进制 SDK 没有翻译单元，compdb 为 0 条，和纯数据
  port（`fontutil` / `xcb-proto`）一样合法。`build` 只导出
  include / libdir / libs / binaries（绝对路径，进入 manifest）。
- **环境变量定位**：`$GCPKG_<NAME>_HOME` 优先，其次是备用变量，最后是
  默认路径；`probe` 文件只做布局提示（不匹配时警告，不中止）。

## 内置的 4 个 SDK port

| port | 主环境变量 | 备用变量 | 默认路径 | probe | 导出的 libs | 获取 |
| --- | --- | --- | --- | --- | --- | --- |
| `nvidia`（CUDA Toolkit / driver） | `GCPKG_NVIDIA_HOME` | `CUDA_HOME`, `CUDA_PATH` | `/usr/local/cuda` | `include/cuda_runtime.h` | `cudart`, `cuda`, `nvidia-ml` | [CUDA 下载](https://developer.nvidia.com/cuda-downloads) |
| `cann`（华为 CANN / AscendCL） | `GCPKG_CANN_HOME` | `ASCEND_HOME_PATH`, `ASCEND_HOME` | `/usr/local/Ascend/ascend-toolkit/latest` | `include/acl/acl.h` | `ascendcl` | [昇腾社区](https://www.hiascend.com/developer/download/community/) |
| `nv-codec-sdk`（Video Codec SDK） | `GCPKG_NV_CODEC_SDK_HOME` | `NV_CODEC_SDK_HOME` | `/opt/nvidia/video-codec-sdk` | `include/nvEncodeAPI.h` | `nvidia-encode`, `nvcuvid` | [Video Codec SDK](https://developer.nvidia.com/video-codec-sdk) |
| `dahuaplayer`（大华 PlaySDK / dhplay） | `GCPKG_DAHUAPLAYER_HOME` | `DAHUA_PLAYSDK_HOME` | `/opt/dahua/playsdk` | `include/dhplay.h` | `dhplay` | [大华支持中心](https://www.dahuatech.com/service/downloadlists/837.html) |

> `nvidia` 版本写 `12.8`、`cann` 写 `9.0.0` 等只是 store key 的占位：
> 真实版本取决于你本地 SDK。若有需要，改对应 `build.lua` 的 `version`
> 即可（它参与 fingerprint）。CANN 的 `.run` 安装包在华为镜像上是
> `Ascend-cann-toolkit_<版本>_linux-<arch>.run`（约 1–2 GB），
> 官方页面同时公布 SHA256；Video Codec SDK 与大华 PlaySDK 需要账号/授权，
> 大华 Linux64 V3.044.0000000.1 官方 SHA256 为
> `dc11ca0b5d15534b390b52edb02d0c7d9b77871ab3eecf4dcf56c6d3c9fc8c1a`。

## 在本机验证（三步）

```bash
# 1) 纯静态：列出 4 个 SDK 及变量是否已设置，不下载不编译
./build/bin/gcpkg externals --ports ./ports

# 2) 指向本地 SDK（示例：CUDA）
export GCPKG_NVIDIA_HOME=/usr/local/cuda
./build/bin/gcpkg install nvidia --store ~/.cache/gcpkg-media-store --ports ./ports

# 3) 上层库自动拿到 include/lib（-I/-L/-l 由 dependency_env 传导）
./build/bin/gcpkg graph nv-image-codec --ports ./ports
./build/bin/gcpkg install cv-cuda --store ~/.cache/gcpkg-media-store --ports ./ports
```

`gcpkg externals` 示例输出（本沙箱未装 SDK，所以是 `unset`）：

```
[gcpkg:info]   cann             GCPKG_CANN_HOME              unset  https://www.hiascend.com/...
[gcpkg:info]   dahuaplayer      GCPKG_DAHUAPLAYER_HOME       unset  https://www.dahuatech.com/...
[gcpkg:info]   nv-codec-sdk     GCPKG_NV_CODEC_SDK_HOME      unset  https://developer.nvidia.com/video-codec-sdk
[gcpkg:info]   nvidia           GCPKG_NVIDIA_HOME            unset  https://developer.nvidia.com/cuda-downloads
[gcpkg:step] 4 external SDK ports (point the env var at the SDK before install)
```

切换 SDK 版本时加 `--no-cache`（环境变量优先于上次写入的
`.gcpkg-sdk-root` marker，但缓存命中不会重跑 build 钩子）：

```bash
export GCPKG_NVIDIA_HOME=/usr/local/cuda-13.0
./build/bin/gcpkg install nvidia --store ~/.cache/gcpkg-media-store --ports ./ports --no-cache
```

## 验证边界（如实说明）

本沙箱里完成的验证：

- `tests/media.sh`：74 ports OK、`graph proxygen` 11 步、`graph
  nv-image-codec` 3 步、23 份 `build.lua`/`features.yaml`、19 个真实
  URL+SHA256、4 个 SDK 的环境变量声明、无沙箱绝对路径、依赖全部可解析。
- `nvidia` adapter：用临时假 SDK 目录（只有 `include/cuda_runtime.h`
  等空文件）真实跑了一次 `gcpkg install`，manifest 正确导出
  `include/` / `lib64/` / `lib64/stubs/` 与 `cudart`、`cuda`、`nvidia-ml`，
  compdb 0 条。`GCPKG_MEDIA_DYNAMIC=1 ./tests/media.sh` 可复现。
- `lua` 5.4.7（34 条 compdb）、`alsa-lib` 1.2.9（113 条 compdb）真编译。

**未在本沙箱真编译**：`dcgm` / `cv-cuda` / `nv-image-codec` 依赖真实
CUDA 与驱动，`cann` 需要 Ascend 工具链，`nv-codec-sdk` / `dahuaplayer`
是厂商二进制，`proxygen` / `redpanda` 等还需要大量宿主组件。这些 port 的
URL/SHA256、依赖图与构建声明已经静态校验，实际编译请在你有 SDK 的机器上
用上面的三步验证；若上游目录布局与 `probe`/`includes`/`libdirs` 不同，
只改对应 `build.lua` 的 `sdk` 表即可（无需改引擎、无需改上游）。

## 新增一个 SDK port

```lua
local external = require("gcpkg.build.external")
return external.declare {
  name = "my-sdk", version = "1.0",
  description = "Vendor SDK", license = "Proprietary",
  dependencies = {},
  sdk = {
    env = "GCPKG_MY_SDK_HOME",
    alt_env = { "MY_SDK_ROOT" },
    default = "/opt/my-sdk",
    url = "https://vendor.example.com/downloads",
    probe = { "include/sdk.h" },
    includes = { "include" }, libdirs = { "lib64" },
    binaries = { "bin" }, libs = { "sdk" },
  },
}
```

`build_hook = function(ctx, root) ... end` 可选：当 SDK 里确实需要编译点什么
（示例代码、插件）时使用，`ctx.env` 已包含编译器包装器和所有依赖环境变量。
