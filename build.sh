#!/bin/bash
# 净听 PureListen 打包脚本: Release 构建 → 组装 .app → 签名
#
# 签名:
#   默认尝试用稳定身份 "PureListen Dev"（tools/setup-dev-signing.sh 生成的自签名证书）。
#   用固定证书签名后，App 的 designated requirement 只跟 bundle id + 证书根哈希有关，
#   重新构建不会让 macOS 把旧的「辅助功能」等 TCC 授权判为失效。
#   找不到该身份时自动回退 ad-hoc（`-`），但那样每次重建都要重新授权。
#   可用 PURELISTEN_SIGN_IDENTITY=... 覆盖身份名。
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${PURELISTEN_SIGN_IDENTITY:-PureListen Dev}"

sign_app() {
    local app="$1"
    if [ -n "$SIGN_IDENTITY" ] && codesign --force --sign "$SIGN_IDENTITY" \
        --identifier com.purelisten.app "$app" >/dev/null 2>&1; then
        echo "    已签名: $SIGN_IDENTITY"
    else
        codesign --force --sign - --identifier com.purelisten.app "$app"
        echo "    ⚠ 未找到稳定签名身份 \"$SIGN_IDENTITY\"，已回退 ad-hoc。"
        echo "      重建后系统授权（辅助功能）会失效；可运行 tools/setup-dev-signing.sh 创建稳定身份。"
    fi
}

echo "==> Release 构建"
swift build -c release --product PureListen

BIN=.build/out/Products/Release/PureListen
APP=dist/净听.app

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PureListen"

# 应用图标(macOS 27 分层玻璃风格), 由 tools/make_icon.swift 生成
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>净听</string>
    <key>CFBundleDisplayName</key>
    <string>净听</string>
    <key>CFBundleIdentifier</key>
    <string>com.purelisten.app</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleExecutable</key>
    <string>PureListen</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License · Halo0sama</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

echo "==> 签名"
sign_app "$APP"

# 自动同步: 用户已把 App 放进 /Applications 时, 保持它为最新版。
# 只想检查构建产物、不想替换已安装版本时: PURELISTEN_NO_INSTALL=1 ./build.sh
if [ -d "/Applications/净听.app" ] && [ "${PURELISTEN_NO_INSTALL:-0}" != "1" ]; then
    echo "==> 同步最新版到 /Applications"
    rm -rf "/Applications/净听.app"
    cp -R "$APP" /Applications/
    sign_app "/Applications/净听.app"
fi

echo "==> 完成: $APP"
echo "    安装: cp -r \"$APP\" /Applications/  然后双击运行(首次需在 Finder 里右键打开)"
