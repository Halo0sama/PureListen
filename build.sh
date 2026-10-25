#!/bin/bash
# 净听 PureListen 打包脚本: Release 构建 → 组装 .app → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")"

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

echo "==> Ad-hoc 签名"
codesign --force --sign - "$APP"

# 自动同步: 用户已把 App 放进 /Applications 时, 保持它为最新版。
# 只想检查构建产物、不想替换已安装版本时: PURELISTEN_NO_INSTALL=1 ./build.sh
if [ -d "/Applications/净听.app" ] && [ "${PURELISTEN_NO_INSTALL:-0}" != "1" ]; then
    echo "==> 同步最新版到 /Applications"
    rm -rf "/Applications/净听.app"
    cp -R "$APP" /Applications/
    codesign --force --sign - "/Applications/净听.app" 2>/dev/null
fi

echo "==> 完成: $APP"
echo "    安装: cp -r \"$APP\" /Applications/  然后双击运行(首次需在 Finder 里右键打开)"
