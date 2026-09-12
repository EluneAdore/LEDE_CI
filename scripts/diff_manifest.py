#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenWrt / LEDE Manifest 差异对比工具
用途:
1. 对比上一次与本次编译生成的 *.manifest 软件包清单
2. 输出新增、移除、升级/降级的软件包列表
3. 生成 manifest.diff 文件，并输出 Markdown 表格至 $GITHUB_STEP_SUMMARY
"""

import sys
import os
import glob
import argparse


def parse_manifest(filepath):
    """解析 manifest 文件，返回字典 {pkg_name: version}"""
    packages = {}
    if not filepath or not os.path.isfile(filepath):
        return packages

    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if ' - ' in line:
                parts = line.split(' - ', 1)
                packages[parts[0].strip()] = parts[1].strip()
            elif ' ' in line:
                parts = line.split(None, 1)
                packages[parts[0].strip()] = parts[1].strip()
    return packages


def find_file(path_pattern):
    """根据路径模式查找文件，支持通配符"""
    if not path_pattern:
        return None
    matches = glob.glob(path_pattern)
    if matches:
        return sorted(matches)[0]
    return None


def generate_diff(prev_pkgs, curr_pkgs):
    """比对两个版本字典，分类返回差异"""
    all_names = sorted(set(prev_pkgs.keys()) | set(curr_pkgs.keys()))

    added = []       # [(pkg, curr_ver)]
    removed = []     # [(pkg, prev_ver)]
    changed = []     # [(pkg, prev_ver, curr_ver)]
    unchanged = 0

    for name in all_names:
        in_prev = name in prev_pkgs
        in_curr = name in curr_pkgs

        if in_curr and not in_prev:
            added.append((name, curr_pkgs[name]))
        elif in_prev and not in_curr:
            removed.append((name, prev_pkgs[name]))
        else:
            p_ver = prev_pkgs[name]
            c_ver = curr_pkgs[name]
            if p_ver != c_ver:
                changed.append((name, p_ver, c_ver))
            else:
                unchanged += 1

    return added, removed, changed, unchanged


def build_markdown_report(added, removed, changed, unchanged, curr_count, is_first_run=False):
    """构建 Markdown 报告"""
    lines = []
    lines.append("### 📦 固件软件包变动报告 (相比上次构建)")
    lines.append("")

    if is_first_run:
        lines.append("> ℹ️ **首次构建或未检测到上次清单缓存**")
        lines.append(f"> 本次构建共包含 **{curr_count}** 个软件包，已自动保存为下次比对基准。")
        lines.append("")
        return "\n".join(lines)

    total_changes = len(added) + len(removed) + len(changed)
    if total_changes == 0:
        lines.append(f"> ✨ **所有软件包与上次构建完全一致**（共 **{curr_count}** 个组件，无任何版本变动）。")
        lines.append("")
        return "\n".join(lines)

    # 统计概览
    lines.append(f"- **总包数**: {curr_count} | **变动项**: {total_changes} "
                 f"(🔼 升级/变动: {len(changed)} | ➕ 新增: {len(added)} | ➖ 移除: {len(removed)} | ⏸ 保持: {unchanged})")
    lines.append("")
    lines.append("| 变动类型 | 软件包名称 | 上次版本 | 本次版本 |")
    lines.append("| :--- | :--- | :--- | :--- |")

    # 优先展示变更/升级
    for name, p_ver, c_ver in changed:
        lines.append(f"| 🔼 **版本变更** | `{name}` | `{p_ver}` | `{c_ver}` |")

    # 展示新增
    for name, c_ver in added:
        lines.append(f"| ➕ **新增组件** | `{name}` | — | `{c_ver}` |")

    # 展示移除
    for name, p_ver in removed:
        lines.append(f"| ➖ **移除组件** | `{name}` | `{p_ver}` | — |")

    lines.append("")
    return "\n".join(lines)


def build_text_diff(added, removed, changed, unchanged, curr_count, is_first_run=False):
    """构建纯文本 diff"""
    lines = []
    lines.append("=" * 70)
    lines.append("OpenWrt / LEDE Package Manifest Diff Report")
    lines.append("=" * 70)

    if is_first_run:
        lines.append("Status: Initial build (No previous manifest found).")
        lines.append(f"Total packages in this build: {curr_count}")
        lines.append("=" * 70)
        return "\n".join(lines)

    total_changes = len(added) + len(removed) + len(changed)
    lines.append(f"Total packages: {curr_count} (Changes: {total_changes}, Unchanged: {unchanged})")
    lines.append(f"Upgraded/Changed: {len(changed)} | Added: {len(added)} | Removed: {len(removed)}")
    lines.append("-" * 70)

    if total_changes == 0:
        lines.append("No changes detected. All packages are identical to previous build.")
        lines.append("=" * 70)
        return "\n".join(lines)

    if changed:
        lines.append("\n[UPGRADED / CHANGED]")
        for name, p_ver, c_ver in changed:
            lines.append(f"  * {name}: {p_ver} -> {c_ver}")

    if added:
        lines.append("\n[ADDED]")
        for name, c_ver in added:
            lines.append(f"  + {name}: {c_ver}")

    if removed:
        lines.append("\n[REMOVED]")
        for name, p_ver in removed:
            lines.append(f"  - {name}: {p_ver}")

    lines.append("\n" + "=" * 70)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Compare OpenWrt manifest files")
    parser.add_argument("previous", help="Path or glob pattern to previous manifest file")
    parser.add_argument("current", help="Path or glob pattern to current manifest file")
    parser.add_argument("--output-diff", help="Path to write text diff file", default=None)
    parser.add_argument("--summary", action="store_true", help="Append report to $GITHUB_STEP_SUMMARY if available")

    args = parser.parse_args()

    prev_path = find_file(args.previous)
    curr_path = find_file(args.current)

    if not curr_path or not os.path.isfile(curr_path):
        print(f"Error: Current manifest file not found: '{args.current}'", file=sys.stderr)
        sys.exit(1)

    curr_pkgs = parse_manifest(curr_path)
    is_first_run = False

    if not prev_path or not os.path.isfile(prev_path):
        is_first_run = True
        prev_pkgs = {}
    else:
        prev_pkgs = parse_manifest(prev_path)

    added, removed, changed, unchanged = generate_diff(prev_pkgs, curr_pkgs)

    # 1. 终端打印简要摘要
    if is_first_run:
        print(f"[Manifest Diff] 首次记录，本次共纳入 {len(curr_pkgs)} 个软件包。")
    else:
        total_changes = len(added) + len(removed) + len(changed)
        print(f"[Manifest Diff] 比对完成：共 {len(curr_pkgs)} 个包，变动 {total_changes} 项 "
              f"(升级/变更: {len(changed)}, 新增: {len(added)}, 移除: {len(removed)})")

    # 2. 写入文本 diff 文件
    text_diff = build_text_diff(added, removed, changed, unchanged, len(curr_pkgs), is_first_run)
    if args.output_diff:
        os.makedirs(os.path.dirname(os.path.abspath(args.output_diff)), exist_ok=True)
        with open(args.output_diff, "w", encoding="utf-8") as f:
            f.write(text_diff)
        print(f"[Manifest Diff] 文本报告已保存至: {args.output_diff}")

    # 3. 写入 GitHub Actions Step Summary (如果启用)
    if args.summary:
        md_report = build_markdown_report(added, removed, changed, unchanged, len(curr_pkgs), is_first_run)
        summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_file:
            try:
                with open(summary_file, "a", encoding="utf-8") as f:
                    f.write("\n" + md_report + "\n")
                print("[Manifest Diff] 已写入 $GITHUB_STEP_SUMMARY")
            except Exception as e:
                print(f"[Manifest Diff] 写入 Step Summary 失败: {e}", file=sys.stderr)
        else:
            # 本地测试时打印 Markdown
            if not is_first_run and (len(added) + len(removed) + len(changed) > 0):
                print("\n" + md_report)


if __name__ == "__main__":
    main()

