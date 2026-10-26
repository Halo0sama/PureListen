#!/bin/bash
# 保留数据升级：暂存验证 → 备份旧包 → 正常退出 → 替换 → 验证；失败时恢复旧包。
set -euo pipefail
umask 077

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$PROJECT_DIR/dist/净听.app}"
TARGET="/Applications/净听.app"
APP_ID="com.purelisten.app"
RUNNING_PATTERN='^/Applications/净听\.app/Contents/MacOS/PureListen([[:space:]]|$)'

fail() { echo "安装失败: $*" >&2; exit 1; }
bundle_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist"; }

[ -d "$SOURCE" ] && [ ! -L "$SOURCE" ] || fail "找不到应用包: $SOURCE"
[ "$(bundle_id "$SOURCE")" = "$APP_ID" ] || fail "新版应用标识不匹配"
codesign --verify --deep --strict "$SOURCE"
[ ! -L "$TARGET" ] || fail "安装位置是符号链接，请先检查 $TARGET"
if [ -e "$TARGET" ]; then
    [ -d "$TARGET" ] && [ "$(bundle_id "$TARGET")" = "$APP_ID" ] || fail "安装位置不是净听应用"
fi

BACKUP_ROOT="$HOME/Library/Application Support/PureListen Upgrades"
mkdir -p "$BACKUP_ROOT"
chmod 700 "$BACKUP_ROOT"
BACKUP="$(mktemp -d "$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXX")"
STAGING="$(mktemp -d '/Applications/.purelisten-install.XXXXXX')"
COMMITTED=0
WAS_RUNNING=0

cleanup() {
    local status=$?
    trap - EXIT
    if [ "$COMMITTED" != 1 ] && [ -d "$STAGING/previous.app" ]; then
        echo "==> 恢复旧版"
        if { [ ! -e "$TARGET" ] || mv "$TARGET" "$STAGING/failed.app"; } &&
            mv "$STAGING/previous.app" "$TARGET"; then
            :
        else
            echo "旧版保留在 $STAGING/previous.app，未清理暂存目录。" >&2
            exit 1
        fi
    fi
    # 旧包与失败的候选包都移入升级备份，只移除已空的暂存目录。
    for name in previous.app 净听.app failed.app; do
        if [ -e "$STAGING/$name" ]; then
            local saved_name="$name"
            if [ "$name" = previous.app ]; then saved_name='净听.app'; fi
            if [ "$name" = 净听.app ]; then saved_name='uninstalled.app'; fi
            if ! mv "$STAGING/$name" "$BACKUP/$saved_name"; then
                echo "应用包保留在 $STAGING/$name，未清理暂存目录。" >&2
                exit 1
            fi
        fi
    done
    rmdir "$STAGING"
    if [ "$status" != 0 ] && [ "$WAS_RUNNING" = 1 ] && [ -d "$TARGET" ]; then
        open -a "$TARGET" || true
    fi
    exit "$status"
}
trap cleanup EXIT

echo "==> 暂存并验证新版"
ditto "$SOURCE" "$STAGING/净听.app"
codesign --verify --deep --strict "$STAGING/净听.app"
cmp "$SOURCE/Contents/MacOS/PureListen" "$STAGING/净听.app/Contents/MacOS/PureListen"

if [ -d "$TARGET" ]; then
    echo "==> 准备旧版备份: $BACKUP/净听.app"
    codesign -d -r- "$TARGET" > "$BACKUP/previous-signature.txt" 2>&1
fi
codesign -d -r- "$STAGING/净听.app" > "$BACKUP/new-signature.txt" 2>&1

if pgrep -f "$RUNNING_PATTERN" >/dev/null; then
    WAS_RUNNING=1
    echo "==> 正常退出净听，保存设置并释放音频设备"
    osascript -e 'tell application "/Applications/净听.app" to quit'
    for ((attempt = 0; attempt < 150; attempt++)); do
        if ! pgrep -f "$RUNNING_PATTERN" >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -f "$RUNNING_PATTERN" >/dev/null; then fail "净听尚未退出，保留原安装"; fi
fi

# 偏好包含登录信息，只复制到当前用户可访问的备份目录；不修改原文件。
PREFERENCES="$HOME/Library/Preferences/$APP_ID.plist"
if [ -f "$PREFERENCES" ]; then cp -p "$PREFERENCES" "$BACKUP/preferences-before.plist"; fi

echo "==> 替换 /Applications/净听.app（保留 ~/Library 中的全部应用数据）"
if [ -d "$TARGET" ]; then mv "$TARGET" "$STAGING/previous.app"; fi
mv "$STAGING/净听.app" "$TARGET"
codesign --verify --deep --strict "$TARGET"
[ "$(bundle_id "$TARGET")" = "$APP_ID" ] || fail "安装后的应用标识不匹配"
cmp "$SOURCE/Contents/MacOS/PureListen" "$TARGET/Contents/MacOS/PureListen"
cmp "$SOURCE/Contents/Info.plist" "$TARGET/Contents/Info.plist"
COMMITTED=1

echo "==> 已安装: $TARGET"
echo "    设置、账号、网页登录资料与歌曲缓存均保留。"
echo "    升级备份: $BACKUP"
if [ "$WAS_RUNNING" = 1 ]; then open -a "$TARGET"; fi
