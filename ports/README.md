# Port registry

每个目录代表一个库，固定包含：

```text
<name>/build.lua
<name>/features.yaml
```

使用与完整清单见 [../docs/PORTS.md](../docs/PORTS.md)，编写方式见 [../docs/EXTENDING.md](../docs/EXTENDING.md)。

```bash
gcpkg check --ports ./ports
gcpkg ports --ports ./ports
gcpkg graph PORT --ports ./ports
gcpkg install PORT --ports ./ports
```

`gcpkg port new NAME` 可生成新的两文件模板。项目私有 port 放在 `<project>/gcpkg-ports/`，用户级 port 放在 `$GCPKG_HOME/ports/`。
