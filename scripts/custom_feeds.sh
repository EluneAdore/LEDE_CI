#!/bin/bash
#
# Description: 自定义第三方软件源配置脚本 (在更新 feeds 前执行)
#

# 1. 确保 feeds.conf.default 中包含 helloworld 源 (提供 luci-app-ssr-plus 及 xray/mihomo 等依赖)
# 注：最新 LEDE 源码默认不再预留 helloworld 注释行，此处兼容处理：存在则解注，缺失则追加
if grep -q "helloworld" feeds.conf.default 2>/dev/null; then
    sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default
else
    echo 'src-git helloworld https://github.com/fw876/helloworld.git' >> feeds.conf.default
fi

# 2. 优化 x86 镜像构建：禁用无用的独立内核 (kernel.bin) 和独立根文件系统 (rootfs.img.gz)
# 注：物理机/虚拟机只需 combined-efi 镜像，禁用独立镜像可节省编译打包耗时与磁盘空间
if [ -f "target/linux/x86/image/Makefile" ]; then
    sed -i 's/KERNEL_INSTALL := 1//' target/linux/x86/image/Makefile
    sed -i 's/IMAGES-y := rootfs.img.gz//' target/linux/x86/image/Makefile
    sed -i 's/IMAGES-y := rootfs.img//' target/linux/x86/image/Makefile
fi

# 3. 如需添加其他第三方 feed 源，可在下方追加：
# echo 'src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main' >> feeds.conf.default
# echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall.git;main' >> feeds.conf.default

