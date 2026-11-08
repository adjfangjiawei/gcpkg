# 代理设置（第十轮）

用户一句「包管理器要支持设置代理」。这一轮把代理做成**引擎级能力**，而不是
只给 `curl` 加一个参数：`lua/gcpkg/proxy.lua` 一处解析，环境变量一处下发，
下载、`git clone`、以及所有上游构建钩子（CMake `ExternalProject`、Meson
`download`、`configure` 里再拉源码等）都自动继承。

**凭据只存在于配置文件和子进程环境变量里，不出现在命令行**：因此构建日志、
`gcpkg --verbose` 的 `[gcpkg:cmd]`、以及 `gcpkg proxy` 的回显都不会泄漏密码。

## 1. 一条命令

```bash
gcpkg proxy                                  # 查看所有来源 + 当前生效值
gcpkg proxy http://proxy.corp:3128           # 在项目里写项目级配置；否则写用户级
gcpkg proxy http://user:pw@proxy.corp:3128 -C apps/demo   # 项目特有
gcpkg proxy http://proxy.corp:3128 -g        # 用户级 / 公有配置
gcpkg proxy --unset -C apps/demo             # 清除项目级
gcpkg proxy --unset -g                       # 清除用户级

gcpkg install curl --proxy=http://127.0.0.1:7890    # 单次覆盖，不写盘
gcpkg install curl --no-proxy                        # 强制直连
gcpkg install curl --noproxy='localhost,.corp,10.0.0.0/8'
gcpkg doctor                                         # 也打印生效代理
```

`proxy` 值支持 `http://`、`https://`、`socks5://`、`socks5h://`，可以内嵌
`user:password@`。格式不对会直接报错（`invalid proxy URL from ...`），不会
静默忽略。`--noproxy` 与配置里的 `no_proxy` 都是逗号分隔列表，匹配规则为
精确主机名、后缀域名（`.corp` 或 `corp`）、以及 `*` 全部绕过。

## 2. 优先级（高 → 低）

| 顺序 | 来源 | 说明 |
| --- | --- | --- |
| 1 | `--no-proxy` | 强制直连：清空全部 `*_proxy` 并设 `no_proxy=*` |
| 2 | `--proxy=URL` | 单次 CLI 覆盖，不写任何配置文件 |
| 3 | `GCPKG_PROXY` | 会话级环境变量，常用于 CI |
| 4 | `<project>/gcpkg.yaml` 的 `proxy:` | **项目特有**，与第八轮的项目依赖清单同一文件 |
| 5 | `$GCPKG_HOME/gcpkg.yaml` 的 `proxy:` | **用户级 / 公有** |
| 6 | `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` | 标准环境变量（大小写都读） |
| 7 | 无 | 直连，但不干扰系统原有环境 |

`no_proxy` 的取值顺序是 `--noproxy` → `GCPKG_NO_PROXY` → 项目 `no_proxy:`
→ 用户级 `no_proxy:` → `NO_PROXY`。**项目配置始终压过用户级配置**，与
「不同项目可能有不同网络环境」的需求一致；会话级环境变量仍然优先于落盘配置，
便于临时覆盖。

## 3. 落盘格式

`gcpkg proxy URL` 在 YAML 里写一个托管区块（与 `gcpkg add` 的依赖区块互不干扰）：

```yaml
schema: 1
dependencies: [zlib]
# --- gcpkg managed proxy (use `gcpkg proxy`) ---
proxy: "http://user:pw@proxy.corp:3128"
no_proxy: "localhost,127.0.0.1,.internal"
# --- end gcpkg managed proxy ---
```

再次设置会就地替换区块，`--unset` 把两个键置空。已存在的手写顶层
`proxy:` / `no_proxy:` 会被规范化掉，避免 YAML 重复键。配置文件里是明文，
若不想落盘请改用 `GCPKG_PROXY` 环境变量或 `--proxy`；输出与日志一律显示为
`scheme://***@host:port`。

## 4. 下发方式（为什么不把 `--proxy` 拼进命令行）

`proxy.env()` 返回一组会被合并进子进程环境的变量：

| 变量 | 用途 |
| --- | --- |
| `http_proxy` / `HTTP_PROXY` | curl、git(http) 读取 |
| `https_proxy` / `HTTPS_PROXY` | curl、git(https) 读取 |
| `all_proxy` / `ALL_PROXY` | socks5 / 其它协议 |
| `no_proxy` / `NO_PROXY` | 绕过列表 |

接入点：

- `lua/gcpkg/net.lua`：`curl` 下载与 `git clone --depth 1` 都带 `env = proxy.env()`；
- `lua/gcpkg/port.lua`：所有 port 构建钩子环境里合并 `proxy.env()`；
- `lua/gcpkg/project.lua`：项目构建（`gcpkg build`）的拦截环境同样合并；
- `lua/gcpkg/exec.lua`：写日志时统一把 `://user:pw@` 脱敏成 `://***@`。

这样即使上游构建系统内部再发起下载，也走同一个代理；而命令行里永远没有
代理 URL，C++ 运行时的 `--verbose` 打印同样安全。（`curl` 自己也会读标准
`*_PROXY` 环境变量；显式配置只是把这一层变成可设置、可分层、可验证。）

顺手修掉一个相关缺陷：`net.prepare` 的 `.gcpkg-source-ready` marker 现在
记录 `url|sha256`（git 源另加 `ref`）。以前同名同版本换了 URL/SHA 仍会复用
旧的解包目录，导致「明明改了源却还在编旧代码」；现在会自动刷新。

## 5. 验证

```bash
./tests/proxy.sh                       # 纯静态：优先级 / 两作用域 / 脱敏 / 非法 URL
GCPKG_PROXY_DYNAMIC=1 ./tests/proxy.sh # 端到端：本地 HTTP CONNECT 代理
```

动态部分启动 `tests/fixtures/test-proxy.py`（支持 CONNECT 与绝对形式 GET），
并验证四件事：

1. `--proxy=http://user:s3cr3t@127.0.0.1:PORT` 下载 `inih` 时，代理日志出现
   `CONNECT codeload.github.com:443`；CLI 输出和 `store/logs/*.log` 里都没有
   `s3cr3t`；
2. `GCPKG_PROXY` 存在时 `--no-proxy` 仍直连（CONNECT 计数不增加）；
3. 项目 `gcpkg.yaml` 的配置不靠 CLI 参数也能让 `yyjson` 的下载走代理；
4. 用一个假的 `git` 记录 `$https_proxy`，确认 `git clone` 分支拿到了同样的
   代理环境。

实测输出：

```
proxy test OK (dynamic: curl proxy, bypass, project config, git env, no leaks)
```
