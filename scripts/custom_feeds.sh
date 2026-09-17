#!/bin/bash
set -euo pipefail

# ==============================================================================
# Description: 自定义第三方软件源与镜像构建配置脚本 (在更新 feeds 前执行)
# ==============================================================================

echo "=== [custom_feeds.sh] 开始配置自定义 Feeds 与构建参数 ==="

# 1. 确保 feeds.conf.default 中包含 helloworld 源 (提供 luci-app-ssr-plus 及 xray/mihomo 等依赖)
# 存在注释行则解除注释；不存在则追加；已存在未注释则跳过（保证完全幂等）
if [ -f "feeds.conf.default" ]; then
    if grep -qE '^[[:space:]]*#[[:space:]]*src-git[[:space:]]+helloworld' feeds.conf.default; then
        echo ">> 正在解除 feeds.conf.default 中的 helloworld 注释..."
        sed -i -E 's/^[[:space:]]*#[[:space:]]*(src-git[[:space:]]+helloworld.*)/\1/' feeds.conf.default
    elif grep -qE '^[[:space:]]*src-git[[:space:]]+helloworld' feeds.conf.default; then
        echo ">> helloworld 源已存在且已启用，跳过修改。"
    else
        echo ">> 正在追加 helloworld 源至 feeds.conf.default..."
        echo 'src-git helloworld https://github.com/fw876/helloworld.git' >> feeds.conf.default
    fi
else
    echo "⚠️ 警告: 未找到 feeds.conf.default 文件，跳过 feeds 源配置。"
fi

# 2. 优化 x86 镜像构建：禁用无用的独立内核 (kernel.bin) 和独立根文件系统 (rootfs.img / rootfs.img.gz)
# 物理机/虚拟机只需 combined-efi 镜像，禁用独立镜像可节省编译打包耗时与磁盘空间
# 使用前置 grep 检查确保幂等与安全，避免空匹配静默或重复修改
IMAGE_MAKEFILE="target/linux/x86/image/Makefile"
if [ -f "$IMAGE_MAKEFILE" ]; then
    echo ">> 正在优化 x86 镜像生成规则 (${IMAGE_MAKEFILE})..."
    if grep -qF "KERNEL_INSTALL := 1" "$IMAGE_MAKEFILE"; then
        sed -i '/KERNEL_INSTALL := 1/d' "$IMAGE_MAKEFILE"
        echo "   - 已移除独立内核镜像构建 (KERNEL_INSTALL := 1)"
    else
        echo "   - KERNEL_INSTALL := 1 已不存在或已优化，跳过。"
    fi

    if grep -qF "IMAGES-y := rootfs.img.gz" "$IMAGE_MAKEFILE"; then
        sed -i '/IMAGES-y := rootfs.img.gz/d' "$IMAGE_MAKEFILE"
        echo "   - 已移除独立压缩根文件系统构建 (rootfs.img.gz)"
    else
        echo "   - rootfs.img.gz 已不存在或已优化，跳过。"
    fi

    if grep -qF "IMAGES-y := rootfs.img" "$IMAGE_MAKEFILE"; then
        sed -i '/IMAGES-y := rootfs.img/d' "$IMAGE_MAKEFILE"
        echo "   - 已移除独立根文件系统构建 (rootfs.img)"
    else
        echo "   - rootfs.img 已不存在或已优化，跳过。"
    fi
fi

echo "=== [custom_feeds.sh] 配置完成 ==="
