# 代理

代理配置由引擎统一解析，并且**不只是显示或写进环境变量**：解析结果会作为显式参数/配置强制下发给下载、`git clone` 与所有构建子进程。上游构建系统内部再次发起下载时也会继承同一份强制配置。gcpkg 显式选中的代理不会再继承系统里的 `NO_PROXY=*` 或用户级 `~/.curlrc` 覆盖；标准环境变量代理仍遵循系统 `NO_PROXY`。

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

`gcpkg proxy --check`（也可写 `gcpkg proxy check`）只检查生效代理的监听端口是否可连接；它不等同于验证请求是否真的经过代理。`install` 的下载与 `git clone` 在真正发起网络请求前也会做一次快速预检，无法连接时立即给出诊断，而不是等待 curl 的长超时。设置 `GCPKG_PROXY_CHECK=0` 会跳过这些连通性探测。**连通性通过不代表代理被使用**；真正的保证来自下面的显式下发。

**代理不是只“显示出来”**：解析出的地址会被强制下发给网络命令。下载使用的 `curl` 带 `-q -K <private .curlrc>`，忽略继承的 `~/.curlrc` / `NO_PROXY` 覆盖；所有子进程还获得 `CURL_HOME`，因此 port 构建钩子内部再调用 curl 也使用同一份私有配置。`git clone` 及子进程内的 Git 获得 `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_0=http.proxy` / `GIT_CONFIG_VALUE_0`，显式设置 `http.proxy`。凭据放在权限为 `0600` 的私有配置文件或环境变量中，不进入 argv、命令行日志或 `gcpkg --verbose`。`--no-proxy` 会写入空的 `proxy` 与 `noproxy="*"`，强制直连。

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

**不会改写地址**：配置里保存什么 URL，curl / Git / 构建子进程就使用什么 URL。gcpkg 不再猜测 WSL 宿主网关、不替换 `127.0.0.1`，也不把「配置命中」与「请求真的经过代理」混为一谈。若该地址本身不可连接，预检会直接报错，但不会偷偷换成别的地址或退回直连。

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

下载、Git 操作、port 构建钩子、项目构建与工作区命令都使用同一组变量，并且额外获得：

| 变量 | 用途 |
| --- | --- |
| `CURL_HOME` | 指向 gcpkg 生成的私有 `.curlrc` 目录，构建钩子内嵌的 curl 也强制走该配置 |
| `GCPKG_CURL_CONFIG` | 私有 `.curlrc` 完整路径，供 `net.download` 用 `-K` 显式读取 |
| `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_0` / `GIT_CONFIG_VALUE_0` | 显式设置 Git 的 `http.proxy`，覆盖 `~/.gitconfig` 与外层 `GIT_CONFIG_*` |

私有 `.curlrc` 权限为 `0600`、所在目录为 `0700`；`curl` 调用以 `-q` 开头忽略继承配置，再用 `-K` 读取该文件。这样「设置了代理」与「请求实际经过代理」是同一件事，不再依赖环境是否恰好没有覆盖它。
