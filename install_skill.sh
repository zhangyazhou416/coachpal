#!/usr/bin/env bash
set -euo pipefail

# 把 coachpal skill 安装到项目级或用户级 skills 目录。
# 用法：
#   ./install_skill.sh                 # 安装到 ./.claude/skills/coachpal
#   ./install_skill.sh ~/.claude/skills # 安装到用户级（所有项目可用）

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$ROOT/.claude/skills}"

mkdir -p "$TARGET"
rm -rf "$TARGET/coachpal"
cp -R "$ROOT/skill/coachpal" "$TARGET/coachpal"

echo "已安装：$TARGET/coachpal"
echo "在 Claude Code 中可直接说「记录体重 77.9」「午饭吃了 150g 鸡胸肉」等。"
