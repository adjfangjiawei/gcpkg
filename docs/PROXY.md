# 代理

代理配置由引擎统一解析，并作为环境变量传给下载、`git clone` 与所有构建子进程。上游构建系统内部再次发起下载时也会继承同一配置。gcpkg 显式选中的代理不会再继承系统里的 `NO_PROXY=*`，避免配置被环境悄悄绕过；标准环境变量代理仍遵循系统 `NO_PROXY`。

```bash
gcpkg proxy
gcpkg proxy --check
gcpkg proxy check
gcpkg proxy http://proxy.example:3128
gcpkg proxy http://user:pw@proxy.example:3128 -C apps/demo
gcpkg proxy http://proxy.example:3128 -g
gcpkg proxy --unset -C apps/demo
gcpkg proxy --unset -g
gcpkg proxy --check --proxy=http://127.0.0.1:7890

gcpkg install curl --proxy=http://127.0.0.1:7890
gcpkg install curl --no-proxy
gcpkg install curl --noproxy='localhost,.internal,10.0.0.0/8'
gcpkg doctor
```

URL 支持 `http://`、`https://`、`socks5://`、`socks5h://`，可以内嵌 `user:password@`。格式错误会直接报错。`--noproxy` 与配置文件中的 `no_proxy` 都是逗号分隔列表，支持精确主机名、后缀域名和 `*`。

`gcpkg proxy --check`（也可写 `gcpkg proxy check`）会检查生效代理的监听端口是否可连接，并打印 WSL 主机映射提示；它只验证代理软件本身，不等同于验证公网可达。`install` 的下载与 `git clone` 在真正发起网络请求前也会做一次快速预检，无法连接时立即给出诊断，而不是等待 curl 的长超时。设置 `GCPKG_PROXY_CHECK=0` 会跳过这些连通性探测。

## 优先级

| 顺序 | 来源 | 说明 |
| --- | --- | --- |
| 1 | `--no-proxy` | 强制直连，清空全部 `*_proxy` 并设置 `no_proxy=*` |
| 2 | `--proxy=URL` | 单次覆盖，不写配置文件 |
| 3 | `GCPKG_PROXY` | 当前 shell 会话 |
| 4 | `<project>/gcpkg.yaml` 的 `proxy:` | 项目特有配置 |
| 5 | `$GCPKG_HOME/gcpkg.yaml` 的 `proxy:` | 用户级配置 |
| 6 | `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` | 标准环境变量 |
| 7 | 无 | 直连 |

`no_proxy` 的顺序为 `--noproxy` → `GCPKG_NO_PROXY` → 项目 `no_proxy:` → 用户级 `no_proxy:` → `NO_PROXY`。其中最后一项只对来源 6 生效；来源 2–5 是 gcpkg 显式配置，不会被系统 `NO_PROXY=*` 覆盖。

## WSL 与 Windows 宿主代理

在 WSL 中，`127.0.0.1` 指的是 Linux 子系统自己的回环地址，并不是运行代理软件的 Windows 宿主。直接写 `gcpkg proxy http://127.0.0.1:7890 -g` 时，配置里仍保存用户输入的 URL，但 gcpkg 会在检测到 WSL、且本机回环没有监听该端口时，把下发给子进程的有效代理改写到宿主网关 IP：

1. `ip route` 的默认网关；
2. `/etc/resolv.conf` 的 `nameserver`；
3. `host.docker.internal` 解析出的 IPv4。

`gcpkg proxy` 与 `gcpkg doctor` 会显示原始 URL、改写后的有效 URL 和 host hint。宿主代理软件还必须允许来自 WSL 的连接，例如开启 **Allow LAN** 或绑定到 `0.0.0.0`；只监听 Windows 自身的 `127.0.0.1` 仍会拒绝连接。此时 `gcpkg proxy --check` 与 `install` 预检会明确报出连接失败、宿主地址以及 Allow LAN 提示。

```bash
# 自动发现宿主网关并验证
gcpkg proxy http://127.0.0.1:7890 -g
gcpkg proxy --check

# 强制指定宿主网关（例如 WSL 虚拟网卡地址）
GCPKG_WSL_HOST=172.20.0.1 gcpkg proxy --check

# 保留 Linux 子系统自己的回环地址
GCPKG_WSL_HOST=off gcpkg proxy --check
```

`GCPKG_WSL_HOST=auto` 与未设置该变量等价；`off`、`none`、`loopback` 都禁用改写。非 WSL 环境不会做任何地址替换。

## 配置文件

```yaml
schema: 1
dependencies: [zlib]
# --- gcpkg managed proxy (use `gcpkg proxy`) ---
proxy: "http://user:pw@proxy.example:3128"
no_proxy: "localhost,127.0.0.1,.internal"
# --- end gcpkg managed proxy ---
```

`gcpkg proxy` 只修改托管区块，保留 `gcpkg.yaml` 其余字段。配置文件保存明文；不想落盘可用 `GCPKG_PROXY` 或 `--proxy`。连通性探测只使用 `host:port`，命令输出、构建日志与 `gcpkg --verbose` 中的凭据都会显示为 `scheme://***@host:port`。

## 下发变量

| 变量 | 用途 |
| --- | --- |
| `http_proxy` / `HTTP_PROXY` | curl、Git HTTP |
| `https_proxy` / `HTTPS_PROXY` | curl、Git HTTPS |
| `all_proxy` / `ALL_PROXY` | SOCKS 与其他协议 |
| `no_proxy` / `NO_PROXY` | 绕过列表 |

下载、Git 操作、port 构建钩子、项目构建与工作区命令都使用同一组变量。WSL 地址改写只作用于这组运行时变量，不会改写用户配置文件。
