#!/bin/bash
# 重新生成 docs/design/screens 下的全部界面截图。
#
# 这是 Debug 专用的截图模式(--ui-studio): 用假数据把真实的 NSPopover / NSWindow
# 渲染出来, 再用 screencapture 抓图。它不会枚举音频设备、不联网、不播放任何声音。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${1:-docs/design/screens}
mkdir -p "$OUT"

echo "==> 构建 Debug 版"
swift build -c debug --product PureListen

BIN="$(swift build -c debug --show-bin-path)/PureListen"

# 唤醒显示器并保持常亮, 否则窗口截图会失败。
caffeinate -u -t 2 || true

echo "==> 渲染截图 → $OUT"
"$BIN" --ui-studio --out "$OUT"

echo "==> 完成: $(ls -1 "$OUT" | wc -l | tr -d ' ') 张"
