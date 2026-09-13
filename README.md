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
| **定时重启** | **预置防死循环示例** | 预置于 `/etc/crontabs/root`（包含 `sleep 70` 跨分钟安全防死循环逻辑，默认注释，需用时解注即可） |

---

## 固件特性说明

| 特性项 | 配置详情 |
| :--- | :--- |
| **目标架构** | x86_64 Generic (物理机 / ESXi / PVE / Hyper-V 通用) |
| **内核版本** | Linux 6.18 LTS |
| **引导方式** | **仅启用 EFI 启动** (`CONFIG_GRUB_EFI_IMAGES=y`)，GRUB 倒计时 0 秒秒启 |
| **分区规划** | 内核分区 `64 MB`，RootFS 根分区 `2048 MB` (2GB 大空间，留足插件与日志余量) |
| **文件系统** | 工业级只读 SquashFS 根系统（防断电损坏变砖）+ 兼容 Ext4 与 F2FS 固态硬盘友好读写 |
| **硬件安全** | 内置 **Intel / AMD 官方 CPU 微码安全更新** (`intel-microcode` / `amd64-microcode`)，修复幽灵/熔断漏洞 |
| **网络驱动** | • **Intel 全系**：板载千兆与服务器网卡 (`e1000e` / `igb` / `igbvf` I210/I211/I350)、2.5G (`igc` 完美支持 I225/I226 全步进)、万兆与40G (`ixgbe` / `ixgbevf` X520/X540/X550、`i40e` / `iavf` XL710/X710)<br>• **Realtek 瑞昱**：官方千兆 (`r8168` 杜绝原厂开源断流)、多队列并发 RSS (`r8125-rss` 2.5G / `r8126-rss` 5G / `r8127-rss` 10G 并发跑满)<br>• **万兆/高速光口**：Aquantia (`atlantic` AQC107 10G 电口)、Mellanox (`mlx4` / `mlx5` ConnectX-3/4/5 高速光卡)<br>• **虚拟化与服务器**：VMware `vmxnet3` 半虚拟化万兆网卡、Broadcom (`tg3` / `bnx2` / `bnx2x` 含微码固件)、AMD `xgbe`<br>• **USB 外接网卡**：亚信 AX88179/A 千兆、AQC111 5G/2.5G、Realtek RTL8150 百兆<br>• **无线网卡**：MediaTek 联发科 MT7920 / MT7921 / MT7922 / MT792x 全系 Wi-Fi 6/6E (`kmod-mt7921e` 驱动 + `mt7921/mt7922-firmware` 官方微码 + `wpad-openssl` 完整支持 WPA2/WPA3 加密认证、AP 热点发射与 Client 无线中继) |
| **内置插件** | • `luci-app-ssr-plus`：科学代理工具（集成 Xray、Mihomo、全球 GeoIP/GeoSite 规则与 TProxy 透明代理；NaiveProxy 支持后台在线一键安装）<br>• `luci-app-sqm`：智能队列流量整形（集成 CAKE 最强抗延迟调度算法，彻底消除 Bufferbloat 缓冲膨胀，游戏防跳 ping）<br>• `luci-app-ttyd`：网页端命令行终端（免客户端直接在浏览器执行 Shell 命令）<br>• `luci-app-package-manager`：软件包管理器（Web 端在线搜索、安装、卸载、升级 ipk 插件）<br>• `luci-app-firewall`：防火墙管理（端口转发、NAT 规则与全功能通信区域设置）<br>• `luci-app-uhttpd`：Web 服务器配置（管理 LuCI 网页后台端口、HTTP/HTTPS 服务与 SSL 证书） |
| **系统与运维工具** | • `autocore-x86` + `lm-sensors`：LEDE 专有助手，在后台首页实时显示 CPU 架构、主频与各核心温度<br>• `nlbwmon`：内网设备实时网络带宽与历史流量用量统计<br>• `ethtool`：物理网卡链路速率、双工状态诊断与高级特性调校<br>• `cfdisk` + `e2fsprogs`：终端交互式磁盘分区与无损扩容维护工具<br>• `kmod-ipt-fullconenat`：Full Cone NAT (NAT1) 扩展（大幅优化联机游戏与 P2P 穿透质量） |
| **极简精简特性** | ❌ **已彻底剔除 GPU 显卡微码与 DRM 3D 渲染驱动** (`amdgpu` / `i915`)，软路由接显示器走标准 Framebuffer 纯字符控制台终端<br>❌ **已剔除耗时的 NaiveProxy 源码编译**（支持后续在后台组件更新中一键在线安装）<br>❌ **已彻底剔除 `block-mount`**，保持后台菜单极简，不自动挂载外接硬盘 |
| **界面主题** | `luci-theme-design`（现代渐变高颜值主题，自适应暗黑模式）、`luci-theme-bootstrap`（经典自适应主题） |

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
   * **固件下载**：构建成功后可在 Actions Artifacts（或 GitHub Releases）下载形如 `LEDE-x86_64-EFI-YYYY.MM.DD-HHMM.zip` 的压缩包（经 `pigz -9` 全核极限压实）。
   * **压缩包内包含 4 个核心文件**：
     * `lede-x86-64-generic-squashfs-combined-efi-YYYYMMDD-HHMM.img.gz`：带有精准构建时间戳的 EFI 主固件镜像
     * `sha256sums.txt`：固件镜像的 SHA256 哈希校验文件
     * `packages-manifest.txt`：当前构建的 371 个已启用软件包全量清单
     * `manifest-diff.txt`：与上一次构建的软件包变动对照差分报告
   * **版本变动报告**：构建完成后可在 GitHub Actions 运行页面的 **Step Summary** 直接查看相比上次构建的**软件包增减/升级可视化表格**。
   * **首次登录**：写入硬盘或导入虚拟机启动后，网线连接 LAN 口，浏览器打开 **`http://192.168.2.1`**（账号: `root`，密码: `password`）即可进入管理后台。

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
