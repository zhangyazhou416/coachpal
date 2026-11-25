#!/usr/bin/env bash
# 命令行构建 CoachPal 鸿蒙 HAP（无需打开 DevEco GUI）。
# 用法：bash app/build.sh [hvigor 任务，默认 assembleHap]
#
# 说明：
#   - hvigor 工具链全部来自本机 DevEco Studio 安装目录（下方 DEVECO 按需修改）。
#   - @ohos/hvigor-ohos-plugin 通过 app/node_modules junction 挂接，
#     @ohos/hvigor 引擎通过 app/.hvigor-deps junction + NODE_PATH 挂接
#     （junction 用 PowerShell 创建：
#      New-Item -ItemType Junction -Path 'app\node_modules\@ohos\hvigor-ohos-plugin' -Target '<DEVECO>\tools\hvigor\hvigor-ohos-plugin'
#      New-Item -ItemType Junction -Path 'app\.hvigor-deps\@ohos\hvigor' -Target '<DEVECO>\tools\hvigor\hvigor'）。
#   - 打包工具需要 java，使用 DevEco 自带 JBR。
#   - 产物：app/entry/build/default/outputs/default/entry-default-unsigned.hap
#     （安装到真机/模拟器需先在 DevEco 里做一次自动签名）。
set -euo pipefail

DEVECO_POSIX="/d/Program Files/Huawei/DevEco Studio"   # DevEco Studio 安装目录（Git Bash 形式）
DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"   # hvigor 以 cwd 定位工程，必须在 app/ 下运行
NODE_PATH="$(cygpath -w "$APP_DIR")\\.hvigor-deps"
export NODE_PATH DEVECO_SDK_HOME
export PATH="$DEVECO_POSIX/jbr/bin:$PATH"

TASK="${1:-assembleHap}"
"$DEVECO_POSIX/tools/node/node.exe" \
  "$DEVECO_POSIX/tools/hvigor/hvigor/bin/hvigor.js" \
  --mode module -p product=default -p buildMode=debug "$TASK" --no-daemon
