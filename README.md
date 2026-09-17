# LEDE x86_64 自动化构建工程 (LEDE_CI)

本项目基于 Lean 的 OpenWrt 源码（[coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)），专为 x86_64 平台打造。支持 **GitHub Actions 云端自动化编译** 与 **本地一键编译**。

---

## 📌 默认登录与网络预设

> [!IMPORTANT]
> 首次开机将自动应用以下预设网络与安全参数：

| 参数项 | 预设值 | 说明 |
| :--- | :--- | :--- |
| **后台管理地址** | **`http://192.168.2.1`** | 避开光猫常见的 `192.168.1.1` 地址冲突 |
| **默认登录账号** | 用户名: `root` / 密码: `password` | 首次登录后建议在【系统 -> 管理权】中修改密码 |
| **WAN 联网模式** | **`PPPoE` 拨号** | 进入 Web 界面填入宽带账号密码即可直接上网 |
| **IPv6 网络** | **全局关闭** | 关闭 WAN6、DHCPv6 及 AAAA 解析过滤，保持纯净稳定的 IPv4 环境 |
| **SSH 安全策略** | **仅限 LAN 且仅限密钥** | 仅绑定 LAN 接口并禁用密码登录，保障暴露风险可控 |
| **计划任务** | **预置定时重启任务** | 默认未启用，可在【系统 -> 计划任务】中按需开启 |

---

## 🚀 固件特性与组件清单

| 类别 | 说明 |
| :--- | :--- |
| **系统底座** | • **架构与内核**：x86_64 Generic，Linux 6.18 LTS 内核（物理机 / ESXi / PVE / Hyper-V 通用）<br>• **引导与分区**：纯 UEFI 引导（GRUB 倒计时 0 秒秒启），内核分区 64MB，系统根分区 2048MB<br>• **文件系统**：SquashFS（只读断电防损坏）+ Ext4 / F2FS 固态友好支持<br>• **CPU 微码**：内置 Intel / AMD 官方微码补丁 (`intel-microcode` / `amd64-microcode`) |
| **全能网卡驱动** | • **Intel**：千兆 (`e1000e` / `igb`)、2.5G (`igc` I225/I226)、万兆及 40G (`ixgbe` / `i40e`)<br>• **Realtek 瑞昱**：官方千兆 `r8168`，多队列并发 RSS（`r8125-rss` 2.5G / `r8126-rss` 5G / `r8127-rss` 10G）<br>• **高速光卡与虚拟网卡**：Aquantia AQC107、Mellanox ConnectX-3/4/5 (`mlx4`/`mlx5`)、VMware `vmxnet3` 等<br>• **USB 网卡**：亚信 AX88179/A 千兆、AQC111 等<br>• **Wi-Fi 6/6E**：联发科 MT7921 / MT7922 / MT7920 (`kmod-mt7921e` 驱动与固件微码，搭配 `wpad-openssl` 完整支持 WPA3 与 AP/STA 模式) |
| **核心功能与插件** | • `luci-app-ssr-plus`：网络代理与分流工具（集成 Xray、Mihomo、GeoIP/GeoSite 规则与 TProxy 透明代理）<br>• `luci-app-sqm`：智能队列流量整形（CAKE 调度算法，消除 Bufferbloat 缓冲膨胀）<br>• `luci-app-ttyd`：网页终端（免客户端，浏览器直接使用 Shell）<br>• `luci-app-package-manager`：软件包管理器（Web 端在线安装与管理 ipk 插件）<br>• `luci-app-firewall`：防火墙管理，内置 **FullCone NAT (NAT1)** 优化游戏与 P2P 穿透<br>• `luci-app-uhttpd`：Web 服务器与 SSL 证书管理<br>• **系统监控助手**：`autocore-x86` + `lm-sensors`（首页实时 CPU 温度与主频）、`nlbwmon`（带宽统计）、`ethtool`、`cfdisk` |
| **界面主题** | `luci-theme-design`（现代化自适应深色主题）、`luci-theme-bootstrap`（经典主题） |
| **轻量精简设计** | ❌ **剔除 GPU 显卡微码与 DRM 驱动**：主机接显示器走标准 Framebuffer 纯字符终端<br>❌ **剔除 NaiveProxy 源码编译**：大幅缩短 CI 构建耗时，需用时可在 Web 后台在线一键安装<br>❌ **剔除 block-mount**：保持界面简洁，不自动挂载非必要外接存储设备 |

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
│           └── 99-custom-defaults     # 开机网络与安全初始化脚本
├── scripts/
│   ├── custom_feeds.sh               # 自定义第三方软件源脚本
│   ├── diff_manifest.py              # 软件包清单差分比对工具
│   └── local_build.sh                # 本地环境一键构建脚本
├── .gitignore                        # Git 忽略规则
└── README.md                         # 项目说明文档
```

---

## 使用指南

### 方式一：GitHub Actions 云端编译（推荐）

1. **Fork 本仓库**：点击右上角 **`Fork`**，复制到个人账号。
2. **启用工作流**：进入 Fork 后的仓库，切换到 **`Actions`** 选项卡并启用工作流。
3. **触发编译**：
   * **手动触发**：在 Actions 页面选择 **编译 LEDE 固件** -> 点击右侧 **Run workflow**。
   * **定时构建**：预置每天凌晨自动拉取 Lean 最新源码定时构建。
4. **下载与查看产物**：
   * 在 Actions 运行结果的 Artifacts 中下载固件压缩包（`LEDE-x86_64-EFI-*.zip`），内含：
     * `*.img.gz`：带有精准构建时间戳的 EFI 主固件镜像
     * `sha256sums.txt`：SHA256 哈希校验文件
     * `packages-manifest.txt`：全量已安装软件包清单
     * `manifest-diff.txt`：与上一次构建的软件包变动对比报告
     * `*.buildinfo`：固件配置 (`config.buildinfo`)、软件源快照 (`feeds.buildinfo`) 与版本信息 (`version.buildinfo`) 可追溯文件
   * 构建完成后，在 Actions 页面的 **Step Summary** 可直接查看软件包变动的可视化表格。

---

### 方式二：本地一键编译

在 Ubuntu / Debian 环境下克隆本仓库并执行：

```bash
./scripts/local_build.sh
```

脚本将自动检查依赖、同步源码与 Feeds、载入预设配置并编译输出至 `output/` 目录。

---

## 💡 联动私有 DNS / AdGuard Home（设备行为审计与去广告）

如果内网部署了独立的私有 DNS 服务器（如 AdGuard Home、Pi-hole 等），可在 LEDE 的 Web 界面中通过 **DHCP Option 6** 将该 DNS 广播给局域网所有设备，实现设备行为审计与全网广告过滤。

> [!TIP]
> **安全与隐私规范**：为保护家庭内网拓扑隐私，本固件**默认保持通用纯净**，严禁在固件源码中硬编码私有 IP。本固件已修复 LuCI 选项隐藏缺陷，直接在 LEDE 的 Web 界面配置即可：

### Web 界面设置步骤：

1. **进入 LAN 接口配置**：
   - 登录 LEDE 后台，进入 **【网络】 -> 【接口】**；
   - 在 **LAN** 接口右侧点击 **【修改】**。
2. **配置 DHCP Option 6**：
   - 滑动至下方 **【DHCP 服务器】** 区域，切换至 **【高级设置】** 选项卡；
   - 找到 **【DHCP 选项】** 输入框，输入：
     ```text
     6,<AdGuard服务器IP>
     ```
     *（注：开头的 `6,` 为 DHCP Option 6 规范标识，后接你的 AdGuard 服务器实际 IP 地址）*；
   - 点击输入框右侧的 **【➕】** 添加该条目。
3. **生效配置**：
   - 点击对话框右下角的 **【保存】**，随后在页面右上角点击 **【保存并应用】**。

> [!IMPORTANT]
> **与代理分流服务联动提醒**：局域网客户端通过 Option 6 直连 AdGuard Home 后，请在 **AdGuard Home Web 后台** 的【设置】->【DNS 设置】->【上游 DNS 服务器】中填入 **`<LEDE后台IP>:53`**。由 AdGuard Home 负责各设备去广告与行为审计，再由 LEDE 负责境外分流与解析，避免境外网站无法解析。

---

## 维护与配置调整

* **调整软件包/驱动**：
  在本地通过 `make menuconfig` 调整后，将生成的 `.config` 覆盖保存至 `config/LEDE.config` 即可。
* **调整默认网络与预设**：
  所有网络、IP、IPv6、主机名、时区等自定义配置，统一在 `files/etc/uci-defaults/99-custom-defaults` 中维护。
* **添加第三方 Feed 软件源**：
  在 `scripts/custom_feeds.sh` 中添加对应的 `src-git` 声明。
