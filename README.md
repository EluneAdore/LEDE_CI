# LEDE x86_64 自动化构建工程 (LEDE_CI)

本项目基于 Lean 的 OpenWrt 源码（[coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)），构建专用于 x86_64 平台的定制固件。支持 **GitHub Actions 云端自动化编译/发布** 与 **本地一键编译**。

---

## 📌 默认网络与登录信息

> [!IMPORTANT]
> 固件首次开机自动完成初始化，核心网络访问参数如下：

| 参数项 | 默认值 | 说明 |
| :--- | :--- | :--- |
| **后台管理地址** | **`http://192.168.2.1`** | **默认 IP 为 `192.168.2.1`**（避免与光猫默认 `192.168.1.1` 产生 IP 冲突） |
| **子网掩码** | `255.255.255.0` | 默认 C 段子网 |
| **默认登录用户名** | `root` | 系统超级管理员 |
| **默认登录密码** | `password` | 首次登录后建议立即在系统管理中修改 |
| **WAN 口协议** | **`PPPoE` 拨号** | 开机预设为拨号模式，可在 Web 界面输入宽带账号密码直接连网 |
| **IPv6 支持** | **默认关闭** | 默认关闭 WAN6、DHCPv6 及 AAAA 解析过滤，保持纯 IPv4 网络环境 |
| **FullCone NAT** | **已启用 (兼容模式)** | 开启通用 FullCone NAT (`fullcone='1'`，非 Broadcom Fullcone NAT1)，提升 NAT 穿透与游戏/P2P 体验 |
| **数据包引导 (RPS)** | **启用 (所有 CPU)** | 跨 CPU 软中断并发分流 (`packet_steering='2'`)，打满多核吞吐，避免单核卡死 |
| **流量导向 (RFS)** | **建议: 128** | 绑定本地服务与监听 CPU 核心 (`steering_flows='128'`)，优化代理插件缓存命中 |
| **SSH (Dropbear)** | **仅限 LAN 且仅限密钥** | 绑定接口至 `lan`；关闭密码验证与 root 凭密码登录（需配置公钥） |

---

## 固件特性说明

| 特性项 | 配置详情 |
| :--- | :--- |
| **目标架构** | x86_64 Generic (物理机 / ESXi / PVE / Hyper-V 通用) |
| **内核版本** | Linux 6.18 |
| **引导方式** | **仅启用 EFI 启动** (`CONFIG_GRUB_EFI_IMAGES=y`)，倒计时 0 秒秒启 |
| **分区规划** | 内核分区 `64 MB`，RootFS 根分区 `2048 MB` (2GB 大空间) |
| **网络驱动** | • **Intel 全系**：板载/千兆/万兆/2.5G (`e1000` / `e1000e` / `igb` / `igc` I225与I226 / `ixgbe` 10G / `i40e` 40G)<br>• **Realtek 瑞昱**：普通千兆 (`r8168`)、多队列并发 RSS (`r8125-rss` 2.5G / `r8126-rss` 5G / `r8127-rss` 10G)<br>• **万兆/高速光口**：Aquantia (`atlantic` AQC107 10G)、Mellanox (`mlx4` / `mlx5` ConnectX 高速光卡)<br>• **虚拟化与服务器**：VMware `vmxnet3`、Broadcom (`tg3` / `bnx2` / `bnx2x`)、AMD `xgbe`<br>• **USB 外接网卡**：亚信 AX88179 千兆、AQC111 5G/2.5G 高速 USB 网卡<br>• **无线网卡**：MediaTek 联发科 MT7920 / MT7921 / MT7922 / MT792x 全系 Wi-Fi 6/6E (`kmod-mt7921e` 驱动 + `wpad-openssl` 完整 AP 发射与中继支持) |
| **内置插件** | • `luci-app-ssr-plus`：科学代理工具（集成 Xray、Mihomo、GeoData 规则；NaiveProxy 可在后台组件更新中一键在线安装）<br>• `luci-app-sqm`：智能队列流量整形（消除 Bufferbloat 缓冲膨胀，大幅降低拥塞延迟）<br>• `luci-app-ttyd`：网页端终端命令行（免客户端直接在浏览器执行 Shell 命令）<br>• `luci-app-package-manager`：软件包管理器（网页端安装/卸载/升级插件）<br>• `luci-app-uhttpd`：Web 服务器配置（管理 LuCI 网页管理后台端口、HTTP/HTTPS 服务） |
| **界面主题** | `luci-theme-design`, `luci-theme-bootstrap` (默认中文界面) |

---

## 目录结构

```text
LEDE_CI/
├── .github/
│   └── workflows/
│       └── build-lede.yml            # GitHub Actions 自动化编译工作流
├── config/
│   └── LEDE.config                   # 核心编译配置文件 (.config)
├── files/
│   └── etc/
│       └── uci-defaults/
│           └── 99-custom-defaults     # Rootfs 覆盖脚本 (首次开机初始化 IP、WAN、IPv6、FullCone NAT 及 SSH)
├── scripts/
│   ├── custom_feeds.sh               # 自定义第三方软件源脚本 (更新 feeds 前执行)
│   ├── diff_manifest.py              # 软件包清单差分比对工具 (生成前后版本变动报告)
│   └── local_build.sh                # 本地环境一键构建脚本
├── .gitignore                        # Git 忽略规则
└── README.md                         # 项目说明文档
```

---

## 使用指南

### 方式一：GitHub Actions 云端编译（推荐）

1. **推送仓库**：
   ```bash
   cd LEDE_CI
   git init
   git add .
   git commit -m "feat: init lede_ci repository"
   git remote add origin <你的 GitHub 仓库地址>
   git branch -M main
   git push -u origin main
   ```
2. **触发编译**：
   * **定时自动触发**：已配置为**每天北京时间凌晨 02:23**（UTC 18:23）自动触发编译。
   * **手动按需触发**：
     * 进入 GitHub 仓库页面 -> **Actions** 标签。
     * 选择 **编译 LEDE 固件** 工作流。
     * 点击 **Run workflow**：
       * `发布固件到 Release`: 发布为 GitHub Release（默认关闭）。
       * `上传固件到 Artifacts`: 保存到 Actions Artifacts（默认开启）。
       * `编译失败时开启 SSH 调试`: 编译失败时启动 SSH 终端远程调试。
3. **获取固件与首次登录**：
   * 编译成功后可在 Releases 页面或 Actions Artifacts 下载形如 `lede-x86-64-generic-squashfs-combined-efi.img.gz` 的固件包及对应的校验文件 `sha256sums`。
   * **版本变动报告**：构建完成后可在 GitHub Actions 运行页面的 **Step Summary** 直接查看相比上次构建的**软件包增减/升级表格**；产物中亦附带 `manifest.diff` 纯文本差异文件。
   * 写入硬盘或导入虚拟机启动后，网线连接 LAN 口，浏览器打开 **`http://192.168.2.1`**（账号: `root`，密码: `password`）即可进入管理后台。

---

### 方式二：本地一键编译

在 Ubuntu / Debian 环境下执行：

```bash
cd LEDE_CI
./scripts/local_build.sh
```

* 脚本会自动检查缺失编译依赖、克隆 Lean 源码、更新 Feeds、加载 `config/LEDE.config` 和 `files/` 目录、并行编译并提取产物到 `output/` 目录。

---

## 维护与配置调整

* **调整软件包/驱动**：
  在本地通过 `make menuconfig` 调整后，将生成的 `.config` 覆盖保存至 `config/LEDE.config` 即可。
* **调整默认网络/首次初始化**：
  所有网络、IP、IPv6、主机名、时区、Banner 等自定义配置，统一在 `files/etc/uci-defaults/99-custom-defaults` 中维护。
* **添加其他第三方 Feed 软件源**：
  在 `scripts/custom_feeds.sh` 中添加对应的 `src-git` 声明。
