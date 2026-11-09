# 代理

代理配置由引擎统一解析，并作为环境变量传给下载、`git clone` 与所有构建子进程。上游构建系统内部再次发起下载时也会继承同一配置。

```bash
gcpkg proxy
gcpkg proxy http://proxy.example:3128
gcpkg proxy http://user:pw@proxy.example:3128 -C apps/demo
gcpkg proxy http://proxy.example:3128 -g
gcpkg proxy --unset -C apps/demo
gcpkg proxy --unset -g

gcpkg install curl --proxy=http://127.0.0.1:7890
gcpkg install curl --no-proxy
gcpkg install curl --noproxy='localhost,.internal,10.0.0.0/8'
gcpkg doctor
```

URL 支持 `http://`、`https://`、`socks5://`、`socks5h://`，可以内嵌 `user:password@`。格式错误会直接报错。`--noproxy` 与配置文件中的 `no_proxy` 都是逗号分隔列表，支持精确主机名、后缀域名和 `*`。

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

`no_proxy` 的顺序为 `--noproxy` → `GCPKG_NO_PROXY` → 项目 `no_proxy:` → 用户级 `no_proxy:` → `NO_PROXY`。

## 配置文件

```yaml
schema: 1
dependencies: [zlib]
# --- gcpkg managed proxy (use `gcpkg proxy`) ---
proxy: "http://user:pw@proxy.example:3128"
no_proxy: "localhost,127.0.0.1,.internal"
# --- end gcpkg managed proxy ---
```

`gcpkg proxy` 只修改托管区块，保留 `gcpkg.yaml` 其余字段。配置文件保存明文；不想落盘可用 `GCPKG_PROXY` 或 `--proxy`。命令输出、构建日志与 `gcpkg --verbose` 中的凭据都会显示为 `scheme://***@host:port`。

## 下发变量

| 变量 | 用途 |
| --- | --- |
| `http_proxy` / `HTTP_PROXY` | curl、Git HTTP |
| `https_proxy` / `HTTPS_PROXY` | curl、Git HTTPS |
| `all_proxy` / `ALL_PROXY` | SOCKS 与其他协议 |
| `no_proxy` / `NO_PROXY` | 绕过列表 |

下载、Git 操作、port 构建钩子、项目构建与工作区命令都使用同一组变量。
