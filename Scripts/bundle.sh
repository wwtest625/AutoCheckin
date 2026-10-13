#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "🔨 正在使用 Swift 6 编译 AutoCheckin (Release 模式)..."
swift build -c release

BIN_PATH="$DIR/.build/release/AutoCheckin"
APP_DIR="$DIR/AutoCheckin.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 正在生成原生 macOS .app 应用包..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/AutoCheckin"
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>AutoCheckin</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.wwtest625.autocheckin</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AutoCheckin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 设置 macOS Bundle 属性（标记目录为官方应用包而非普通文件夹）
SetFile -a B "$APP_DIR" 2>/dev/null || true

# 清理可能存在的资源衍生属性并执行原生 Ad-hoc 代码签名（macOS 识别 App 图标的前提）
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

# 注入 Finder 专用强显自定义图标（确保外接盘与访达即时渲染）
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    swift -e "import AppKit; if let img = NSImage(contentsOfFile: \"$DIR/Resources/AppIcon.icns\") { NSWorkspace.shared.setIcon(img, forFile: \"$APP_DIR\", options: []) }" 2>/dev/null || true
fi

# 注册并强制刷新 LaunchServices 与 Finder 图标
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true
touch "$APP_DIR"

echo "✅ 打包完成！"
echo "👉 应用文件位于: $APP_DIR"

# 制作标准 macOS DMG 安装镜像（带 Applications 快捷拖拽安装入口）
DMG_PATH="$DIR/AutoCheckin-macOS.dmg"
echo "💿 正在生成 DMG 安装镜像: $DMG_PATH ..."
DMG_TMP="$DIR/.dmg_temp"
rm -rf "$DMG_TMP" "$DMG_PATH"
mkdir -p "$DMG_TMP"
cp -R "$APP_DIR" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create -volname "AutoCheckin" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_TMP"
echo "✅ DMG 镜像生成完成: $DMG_PATH"
