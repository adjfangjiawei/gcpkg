# 磁盘 / 存储信息查询与内核接口 port

这一轮（第七轮）围绕「内核和底层库，尤其磁盘信息查询」新增 34 个 port，
注册表达到 **145 个**。`liburing` 不是新加的：它在第四轮就已纳入并真编译过，
本轮从干净源码**重新复核**（14 条编译命令），并把它声明为 `libnvme` 的依赖，
因此现在 `graph udisks2` 里能直接看到 `liburing → libnvme`。

## 按查询场景找 port

| 想查什么 | 用哪些 port | 说明 |
| --- | --- | --- |
| NVMe 设备 / 命名空间 / 健康日志 | `libnvme`、`nvme-cli` | `libnvme` 是内核 `nvme` ioctl 的封装，`nvme-cli` 是命令行；`libnvme` 依赖 `liburing` |
| 磁盘 SMART / ATA 参数 | `libatasmart`、`smartmontools`、`hdparm` | ATA SMART 健康、SATA 参数 |
| SCSI / SAS 设备 | `sg3_utils`（libsgutils2）、`lsscsi`（未收录，见下） | SCSI 通用命令 |
| 分区表 | `libparted`、`util-linux`（blkid/lsblk/fdisk） | 分区与块设备拓扑 |
| 文件系统信息 | `e2fsprogs`（libext2fs）、`xfsprogs`（libxfs）、`btrfs-progs` | ext/XFS/Btrfs 元数据 |
| RAID / 逻辑卷 / device-mapper | `mdadm`、`lvm2`（libdevmapper） | MD RAID 与 LVM |
| 设备枚举 / 总线 / 固件 | `pciutils`（libpci）、`dmidecode`（SMBIOS/DMI）、`libgudev`、`libusb`、`i2c-tools`、`lm-sensors` | lspci、DMI 表、udev 事件、I2C、硬件监控 |
| D-Bus 统一查询服务 | `udisks2` | 把上面多条链汇成一个 D-Bus 接口，是依赖面最宽的 port |
| 内核追踪 / keyring / GPIO / IIO | `libtraceevent`、`libtracefs`、`keyutils`、`libgpiod`、`libiio`、`hidapi`、`libserialport` | ftrace、内核密钥环、GPIO 字符设备、工业 I/O |

> 两个被剔除的候选：`lsscsi` 的官方镜像在本沙箱全部不可达；`libhugetlbfs`
> 的 GitHub tag 只有 2006 年的 `dev-20061011`。与其写占位 SHA256，不如不收。
> `mdadm` / `libserialport` / `lm-sensors` 则换成了正式 release tarball。

## 最宽的磁盘信息依赖图

```
./build/bin/gcpkg graph udisks2 --ports ./ports
```

15 步，自底向上，把前六轮的 L0 与内核库串起来：

```
libffi → zlib → pcre2 → glib → expat → dbus → libgudev → libatasmart
      → liburing → libnvme → util-linux → libparted → libattr → libacl → udisks2
```

`graph nvme-cli` = `liburing → libnvme → nvme-cli`（3 步），
`graph libtracefs` = `libtraceevent → libtracefs`（2 步）。

## 项目模式：一次编译、跨依赖跳转

`examples/diskinfo/` 是一个真实跑通的项目：它依赖 `libnvme`、
`libatasmart`、`pciutils`，三者的 `build.lua` 各管各的上游源码，项目只写
`gcpkg.lua` + `gcpkg.yaml`，再编译一个 include 了 `nvme/tree.h`、
`atasmart.h`、`pci.h` 的 `src/main.c`：

```bash
./build/bin/gcpkg build examples/diskinfo \
    --store ~/.cache/gcpkg-linux-store --ports ./ports
```

实测输出：

```
[gcpkg:step] compiled 1 project objects; merged compdb written
[gcpkg:step] compile database: examples/diskinfo/compile_commands.json
             (240 compile commands across 21 source directories)
```

`clangd-22 --check=examples/diskinfo/src/main.c
--compile-commands-dir=examples/diskinfo` 退出码 0、0 个 `error:`。
也就是说，从项目文件可以直接跳进 `liburing` / `libnvme` / `libatasmart` /
`pciutils` / `zlib` 的依赖源码，再跳回来 —— 这正是元包管理器相对
「只导出 include/lib」方案的差别。项目只编译不链接（真实磁盘查询需要设备
权限，且静态库传递依赖较多），重点是合并编译数据库。

## 在本机验证

按之前的约定，本沙箱以静态验证为主，你在本机可直接：

```bash
# 纯静态：注册表 / 三张依赖图 / 34 份两文件 / 真实 SHA256 / 依赖解析
./tests/linux-kernel.sh

# 真编译 22 个代表性库（含 liburing 复核），需要 autoconf/automake/libtool/meson
GCPKG_KERNEL_DYNAMIC=1 ./tests/linux-kernel.sh

# 单个磁盘信息库
export GCPKG_STORE=~/.cache/gcpkg-linux-store
./build/bin/gcpkg graph nvme-cli --ports ./ports
./build/bin/gcpkg install nvme-cli --store "$GCPKG_STORE" --ports ./ports -j 4
ls "$GCPKG_STORE"/pkg/nvme-cli-*/sbin/nvme
```

安装后的命令行工具在 `<store>/pkg/<name>-<version>/sbin`（`nvme`、`lspci`、
`smartctl`、`hdparm`、`dmidecode`、`sensors`、`mdadm`…），库与头文件在
`lib/` / `include/`。手写 Makefile 的库用自定义 `build(ctx)` 把产物收进
prefix，因为它们的 `install` 目标原本会写 `/sbin`（非 root 不可用）。

## 验证边界（如实）

- **静态声明、由你本机真编译**：`udisks2`、`libstoragemgmt`、`e2fsprogs`、
  `xfsprogs`、`btrfs-progs`、`lvm2`、`libaudit`、`libmicrohttpd`、
  `libselinux`、`libtirpc`、`i2c-tools`、`lm-sensors` 等 12 个（系统组件多、
  构建时间长，或需要内核头文件/设备）。
- **这里真编译 22 个**：`liburing`（复核）、`libnvme`、`nvme-cli`、
  `libatasmart`、`libtraceevent`、`libtracefs`、`pciutils`、`libconfuse`、
  `libdaemon`、`libserialport`、`hidapi`、`libunwind`、`sg3_utils`、
  `smartmontools`、`libgpiod`、`libparted`、`libiio`，以及 `keyutils`、
  `dmidecode`、`hdparm`、`mdadm`、`rpcsvc-proto`（这 5 个手写 Makefile
  硬编码 `gcc`，编译成功但 compdb 为 0，manifest 如实记录）。
- 34 个 tarball 的 URL/SHA256 全部实测；生成器
  `tools/gen-linux-kernel-ports.py` + `tools/linux-kernel-catalog.tsv`
  可重新生成全部 port，运行时引擎不依赖它们。
- 适配全部落在 `build.lua` 的选项 / `pre_build` / 自定义 `build(ctx)` 与
  `features.yaml` 的 env 里：**上游源码一行未改**。
