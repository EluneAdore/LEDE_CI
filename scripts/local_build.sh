#!/bin/bash
set -euo pipefail

# ==============================================================================
# LEDE x86_64 本地自动化编译脚本
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build_dir"
LEDE_SRC_DIR="${BUILD_DIR}/lede"
OUTPUT_DIR="${PROJECT_ROOT}/output"
LEDE_REPO="https://github.com/coolsnowwolf/lede.git"
LEDE_BRANCH="master"

echo "=== LEDE 本地编译自动化脚本 ==="
echo "项目路径: ${PROJECT_ROOT}"
echo "构建工作区: ${BUILD_DIR}"
echo "产物目录: ${OUTPUT_DIR}"

# 1. 权限检查（禁止 root 直接编译）
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ 错误: 请勿使用 root 用户直接编译 OpenWrt/LEDE！请切换至普通用户执行。"
    exit 1
fi

# 2. 依赖工具快速检查
MISSING_TOOLS=()
for tool in git gcc g++ make python3 gawk bzip2 tar unzip wget curl; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "⚠️ 警告: 检测到系统缺少以下关键工具: ${MISSING_TOOLS[*]}"
    echo "请先在宿主机执行以下命令安装依赖:"
    echo "  sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget curl subversion swig time libelf-dev"
    exit 1
fi

# 3. 准备构建目录与源码
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"
if [ ! -d "${LEDE_SRC_DIR}/.git" ]; then
    echo ">> 正在克隆 coolsnowwolf/lede 源码仓库 (分支: ${LEDE_BRANCH}) ..."
    git clone --depth 1 -b "${LEDE_BRANCH}" "${LEDE_REPO}" "${LEDE_SRC_DIR}"
else
    echo ">> 已存在源码，更新最新提交 ..."
    cd "${LEDE_SRC_DIR}"
    git pull || true
fi

cd "${LEDE_SRC_DIR}"

# 4. 配置自定义软件源 (更新 feeds 前)
echo ">> 执行 scripts/custom_feeds.sh ..."
if [ -f "${PROJECT_ROOT}/scripts/custom_feeds.sh" ]; then
    bash "${PROJECT_ROOT}/scripts/custom_feeds.sh"
fi

# 5. 更新并安装 Feeds
echo ">> 更新并安装 Feeds ..."
./scripts/feeds update -a
./scripts/feeds install -a

# 6. 同步配置文件
echo ">> 注入 config/LEDE.config ..."
if [ ! -f "${PROJECT_ROOT}/config/LEDE.config" ]; then
    echo "❌ 错误: 未找到 ${PROJECT_ROOT}/config/LEDE.config !"
    exit 1
fi
cp "${PROJECT_ROOT}/config/LEDE.config" .config

# 7. 同步 files/ 覆盖目录 (首次开机配置均集中于 files/etc/uci-defaults/99-custom-defaults)
echo ">> 注入 files/ 目录 ..."
if [ -d "${PROJECT_ROOT}/files" ]; then
    mkdir -p files
    cp -r "${PROJECT_ROOT}/files/"* files/
fi

# 8. 生成依赖配置并预下载软件包
echo ">> 执行 make defconfig ..."
make defconfig

echo ">> 执行 make download (预下载依赖包) ..."
make download -j16 || make download -j1

# 9. 编译固件
CPU_CORES="$(nproc)"
echo ">> 开始编译固件 (并发核心数: ${CPU_CORES}) ..."
if ! make -j"${CPU_CORES}"; then
    echo "⚠️ 多线程编译失败，自动回退单线程排查详细错误 (V=s) ..."
    make -j1 V=s
fi

# 10. 收集产物
echo ">> 整理固件产物至 ${OUTPUT_DIR} ..."
TARGET_BIN_DIR="${LEDE_SRC_DIR}/bin/targets/x86/64"
if [ -d "${TARGET_BIN_DIR}" ]; then
    # 清单差异对比 (如果 output/ 目录下已有上次构建留存的 manifest)
    PREV_MANIFEST="$(find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.manifest" 2>/dev/null | head -n 1)"
    CURR_MANIFEST="$(find "${TARGET_BIN_DIR}" -maxdepth 1 -type f -name "*.manifest" 2>/dev/null | head -n 1)"
    if [ -n "${PREV_MANIFEST}" ] && [ -n "${CURR_MANIFEST}" ] && [ -f "${PROJECT_ROOT}/scripts/diff_manifest.py" ]; then
        echo ">> 对比上次编译清单差异 ..."
        python3 "${PROJECT_ROOT}/scripts/diff_manifest.py" \
            "${PREV_MANIFEST}" \
            "${CURR_MANIFEST}" \
            --output-diff "${OUTPUT_DIR}/manifest.diff" || true
    fi

    find "${TARGET_BIN_DIR}" -type f -name "*generic-squashfs-combined-efi.img.gz" -exec cp {} "${OUTPUT_DIR}/" \;
    find "${TARGET_BIN_DIR}" -type f -name "*.manifest" -exec cp {} "${OUTPUT_DIR}/" \;
    find "${TARGET_BIN_DIR}" -type f -name "profiles.json" -exec cp {} "${OUTPUT_DIR}/" \; || true

    cd "${OUTPUT_DIR}"
    # 将输出固件与清单文件统一重命名为以 lede 开头
    for file in openwrt-*; do
        [ -f "$file" ] && mv -f "$file" "${file/openwrt/lede}"
    done
    sha256sum *.img.gz > sha256sums 2>/dev/null || true
    echo "✅ 编译完成！输出固件列表:"
    ls -lh "${OUTPUT_DIR}"
else
    echo "❌ 未在 ${TARGET_BIN_DIR} 找到编译产物，请检查编译日志。"
    exit 1
fi
