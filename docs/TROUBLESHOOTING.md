# 诊断

```bash
gcpkg doctor
gcpkg store show
gcpkg check --ports ./ports
gcpkg graph PORT --ports ./ports
gcpkg ports --ports ./ports
```

`doctor` 会显示二进制、编译器、拦截层、store 来源、port roots、代理与工具链状态。`check` 验证所有 port 的两个文件、依赖可解析性与 YAML / Lua 格式。

## 常见问题

### `port not found`

检查 `--ports` / `GCPKG_PORTS`，以及项目的 `gcpkg-ports/` 和用户级 `$GCPKG_HOME/ports/`。`gcpkg doctor` 会按优先级列出实际 roots。

### 依赖版本不符合预期

运行 `gcpkg list <project>` 与 `gcpkg versions PORT`。项目级声明优先于用户级清单，`gcpkg.lock` 记录上次解析结果；修改依赖后重新运行 `gcpkg install` 或 `gcpkg build`。

### 下载失败

先用 `gcpkg proxy` 查看生效代理，必要时用 `--proxy`、`--no-proxy` 或 `GCPKG_PROXY` 覆盖。凭据不会打印到日志；网络问题可结合 `gcpkg --verbose` 与 store 中的日志目录定位。

### 端口构建失败但源码已下载

检查 `<store>/logs/`，确认 `setup-gcpkg-toolchain.sh` 中的系统组件是否齐备。需要强制重建时使用 `--no-cache`。某个 port 的编译选项可在 `build.lua` 的 `cmake.defines`、`meson.options`、`make.vars` 或 `features.yaml` 中调整。

### clangd 找不到依赖源码

运行 `gcpkg compdb <project>` 重建总库，并确认 `compile_commands.json` 与 `.clangd` 位于项目根。依赖源码保存在 store 中，不要移动或删除已安装 port 的 `src/` 目录。

### Conan 命令未被找到

设置 `CONAN_CMD`，或在 `gcpkg.yaml` / `workspace.yaml` 中写 `conan_cmd` / `commands.conan`。gcpkg 会生成 `gcpkg-conan.json` 与 `CONAN_*` 变量，但不会猜测 Conan CLI 语法。

### 工作区 submodule 与 lock 不一致

按提示运行 `gcpkg workspace update -C ws` 或 `gcpkg workspace submodule sync <repo> -C ws`，然后重新查看 `workspace.lock`。显式 `commit:` 始终优先。
