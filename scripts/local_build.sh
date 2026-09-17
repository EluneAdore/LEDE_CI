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

# 2. 清理环境变量（在 WSL/混合环境下剔除带有空格的 /mnt/ Windows 路径，避免 find -execdir 报错）
export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':' | sed 's/:$//')"

# 3. 依赖工具快速检查
MISSING_TOOLS=()
for tool in git gcc g++ make python3 gawk bzip2 tar unzip wget curl xz; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "⚠️ 警告: 检测到系统缺少以下关键工具: ${MISSING_TOOLS[*]}"
    echo "请先在宿主机执行以下命令安装依赖:"
    echo "  sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget curl subversion swig time libelf-dev xz-utils"
    exit 1
fi

# 4. 准备构建目录与源码
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

# 8. 生成依赖配置并预下载软件包（带完整性检测与重试）
echo ">> 执行 make defconfig ..."
make defconfig

echo ">> 执行 make download (预下载依赖包并校验完整性) ..."
MAX_RETRIES=3
DOWNLOAD_OK=0
for attempt in $(seq 1 $MAX_RETRIES); do
    echo ">> [下载尝试 ${attempt}/${MAX_RETRIES}] 执行 make download ..."
    DL_OK=0
    if make download -j16 || make download -j1; then
        DL_OK=1
    else
        echo "⚠️ make download 返回非零退出码。"
    fi

    # 清理 0 字节空文件和临时锁文件
    find dl -type f -size 0c -exec rm -vf {} + 2>/dev/null || true
    find dl -type f \( -name '*.dl' -o -name '*.hash' \) -exec rm -vf {} + 2>/dev/null || true

    CORRUPTED=0

    # 1. 重点检测 linux-firmware 归档完整性
    for lf in $(find dl -type f -name 'linux-firmware-*.tar.xz' 2>/dev/null); do
        if ! xz -t "$lf" >/dev/null 2>&1; then
            echo "❌ 发现损坏的 linux-firmware: ${lf}，立即清除..."
            rm -f "$lf"
            CORRUPTED=1
        fi
    done

    # 2. 检测通用压缩包完整性
    for f in $(find dl -type f \( -name '*.xz' -o -name '*.txz' \) 2>/dev/null); do
        if ! xz -t "$f" >/dev/null 2>&1; then
            echo "⚠️ 损坏的 XZ 压缩包: ${f}，已清除"
            rm -f "$f"
            CORRUPTED=1
        fi
    done

    for f in $(find dl -type f \( -name '*.gz' -o -name '*.tgz' \) 2>/dev/null); do
        if ! gzip -t "$f" >/dev/null 2>&1; then
            echo "⚠️ 损坏的 GZ 压缩包: ${f}，已清除"
            rm -f "$f"
            CORRUPTED=1
        fi
    done

    for f in $(find dl -type f \( -name '*.bz2' -o -name '*.tbz2' \) 2>/dev/null); do
        if ! bzip2 -t "$f" >/dev/null 2>&1; then
            echo "⚠️ 损坏的 BZ2 压缩包: ${f}，已清除"
            rm -f "$f"
            CORRUPTED=1
        fi
    done

    for f in $(find dl -type f -name '*.zip' 2>/dev/null); do
        if ! unzip -t -q "$f" >/dev/null 2>&1; then
            echo "⚠️ 损坏的 ZIP 压缩包: ${f}，已清除"
            rm -f "$f"
            CORRUPTED=1
        fi
    done

    if [ "$DL_OK" -eq 1 ] && [ "$CORRUPTED" -eq 0 ]; then
        echo "✅ make download 退出成功且所有下载依赖包完整性校验通过！"
        DOWNLOAD_OK=1
        break
    else
        if [ "$attempt" -eq "$MAX_RETRIES" ]; then
            echo "❌ 经过 ${MAX_RETRIES} 次尝试仍存在下载失败或损坏包，终止构建。"
            exit 1
        fi
        echo "⚠️ 检测到下载失败或部分文件损坏并已清除，准备重新下载..."
        sleep 2
    fi
done

if [ "$DOWNLOAD_OK" -ne 1 ]; then
    echo "❌ 依赖下载未成功完成，终止构建。"
    exit 1
fi

# 9. 编译固件
CPU_CORES="$(nproc)"
echo ">> 开始编译固件 (并发核心数: ${CPU_CORES}) ..."
if ! make -j"${CPU_CORES}"; then
    echo "⚠️ 多线程编译失败，自动回退单线程排查详细错误 (V=s) ..."
    make -j1 V=s 2>&1 | tee "${PROJECT_ROOT}/build_error.log"
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
            --output-diff "${OUTPUT_DIR}/manifest-diff.txt"
    fi

    # 复制主固件、软件包清单、配置文件与可追溯信息
    find "${TARGET_BIN_DIR}" -type f -name "*generic-squashfs-combined-efi.img.gz" -exec cp {} "${OUTPUT_DIR}/" \;
    find "${TARGET_BIN_DIR}" -type f -name "*.manifest" -exec cp {} "${OUTPUT_DIR}/" \;
    find "${TARGET_BIN_DIR}" -type f -name "*.buildinfo" -exec cp {} "${OUTPUT_DIR}/" \; || true
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
