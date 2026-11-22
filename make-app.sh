#!/bin/bash
# 构建 Aura.app：swiftc 直接编译（绕过本机 CLT 的 SwiftPM 清单缺陷与缺失的 SwiftUIMacros 宏插件）
# → 生成图标 → 组装 bundle → ad-hoc 签名 → 启动
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Aura"
BUNDLE_ID="com.aura.mac"
EXEC="Aura"
DIST="dist"
APP="$DIST/$APP_NAME.app"
OUT=".build/Aura.bin"
SHADOW="$HOME/Library/Caches/AIRoleSimShadowSDK"
MCACHE=".build/mcache"
ICON_DIR=".build/AppIcon.iconset"
ICNS=".build/AppIcon.icns"
mkdir -p .build "$DIST"

# SDK 选择：完整 Xcode（含 SwiftUIMacros 宏插件）优先，否则本机 CLT + 影子 SDK
XCODE_SDK="$(xcodebuild -version >/dev/null 2>&1 && xcrun --show-sdk-path 2>/dev/null || true)"
if [ -n "$XCODE_SDK" ] && [ -d "$XCODE_SDK" ]; then
    echo "==> 检测到完整 Xcode，使用系统 SDK：$XCODE_SDK"
    BUILD_SDK="$XCODE_SDK"
    USE_SHADOW=0
else
    SDK_REAL="$(cd /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk && pwd)"
    BUILD_SDK=""
    USE_SHADOW=1
fi

# ---- 1) 影子 SDK ----
# 本机 CLT 未携带 libSwiftUIMacros.dylib，SwiftUI/SwiftUICore 接口中的外部宏无法展开。
# 解决：克隆 SDK 并剥离接口中的 #externalMacro 宏声明，使 @State 等回退到传统 propertyWrapper 实现。
SDK_STAMP="$SHADOW/.sdk-source"
if [ "$USE_SHADOW" = "1" ] && { [ ! -f "$SHADOW/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface" ] \
   || [ ! -f "$SDK_STAMP" ] || [ "$(cat "$SDK_STAMP" 2>/dev/null)" != "$SDK_REAL" ]; }; then
    echo "==> 生成影子 SDK（剥离 SwiftUI 宏声明）→ $SHADOW"
    rm -rf "$SHADOW"
    mkdir -p "$SHADOW"
    cp -cR "$SDK_REAL/" "$SHADOW/"

    cat > .build/strip-macros.awk <<'AWK'
BEGIN { n = 0; drop = 0; mode = 0; closeSeen = 0 }
function flushbuf() { if (!drop) { for (i = 1; i <= n; i++) print buf[i] } n = 0; drop = 0; mode = 0; closeSeen = 0 }
{
    line = $0
    trimmed = line
    gsub(/^[ \t]+|[ \t]+$/, "", trimmed)

    if (mode == 1) {
        if (trimmed ~ /^#if|^#endif|^#elseif|^#else/) { flushbuf(); print line; next }
        n++; buf[n] = line
        if (trimmed ~ /^\)/) { closeSeen = 1; next }
        if (closeSeen) {
            if (trimmed ~ /^where\b/) next
            flushbuf()
            if (trimmed ~ /#externalMacro/) {
                if (trimmed ~ /\)\s*$/) { n = 0; drop = 0; next }
                mode = 1; n = 1; buf[1] = line; drop = 1; closeSeen = 0
                next
            }
            if (trimmed ~ /^@/) { n++; buf[n] = line; next }
            print line
            next
        }
        next
    }

    if (trimmed ~ /#externalMacro/) {
        if (trimmed ~ /\)\s*$/) { n = 0; drop = 0; next }
        mode = 1; n = 1; buf[1] = line; drop = 1
        next
    }

    if (trimmed ~ /^@/) { n++; buf[n] = line; next }

    flushbuf()
    print line
}
END { flushbuf() }
AWK

    find "$SHADOW/System" -name "*.swiftinterface" | while read -r f; do
        if grep -q "SwiftUIMacros" "$f"; then
            cp -c "$f" "$f.orig"
            awk -f .build/strip-macros.awk "$f.orig" > "$f"
        fi
    done
    echo "$SDK_REAL" > "$SDK_STAMP"
    echo "影子 SDK 就绪：$SHADOW"
fi

# ---- 2) 应用图标（CoreGraphics 程序化绘制，一次性生成） ----
if [ ! -f "$ICNS" ]; then
    echo "==> 生成应用图标"
    cat > .build/make_icon.swift <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import AppKit

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 背景：圆角矩形（Apple 图标网格：约 10% 边距，约 22.5% 圆角）
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let radius: CGFloat = 200
let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// 主题渐变：靛蓝 → 紫罗兰
let colors = [
    CGColor(red: 0.357, green: 0.553, blue: 0.937, alpha: 1),   // #5B8DEF
    CGColor(red: 0.486, green: 0.416, blue: 0.941, alpha: 1)    // #7C6AF0
] as CFArray
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: inset, y: CGFloat(size) - inset), end: CGPoint(x: CGFloat(size) - inset, y: inset), options: [])

// 左上柔光
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
ctx.fillEllipse(in: CGRect(x: -100, y: 520, width: 700, height: 700))

// 中央 "A" 字标（圆体，白色，微投影）
let par = NSMutableParagraphStyle()
par.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 560, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: par
]
let str = NSAttributedString(string: "A", attributes: attrs)
let line = CTLineCreateWithAttributedString(str)
let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: CGColor(red: 0, green: 0, blue: 0.3, alpha: 0.35))
ctx.textPosition = CGPoint(x: CGFloat(size)/2 - bounds.width/2, y: CGFloat(size)/2 - bounds.midY)
CTLineDraw(line, ctx)
ctx.restoreGState()

guard let img = ctx.makeImage() else { fatalError("渲染失败") }
// 脚本在 .build 目录内执行（make-app.sh 中 cd .build）
let outURL = URL(fileURLWithPath: "icon_1024.png")
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("icon_1024.png 完成")
SWIFT
    ICON_SDK="${BUILD_SDK:-$SHADOW}"
    swiftc -swift-version 5 -sdk "$ICON_SDK" -module-cache-path "$MCACHE" -target arm64-apple-macos26.0 -o .build/make_icon .build/make_icon.swift
    (cd .build && ./make_icon)
    # 生成全尺寸 iconset
    rm -rf "$ICON_DIR"; mkdir -p "$ICON_DIR"
    for s in 16 32 128 256 512; do
        sips -z $s $s .build/icon_1024.png --out "$ICON_DIR/icon_${s}x${s}.png" >/dev/null
        s2=$((s * 2))
        sips -z $s2 $s2 .build/icon_1024.png --out "$ICON_DIR/icon_${s}x${s}@2x.png" >/dev/null
    done
    sips -z 512 512 .build/icon_1024.png --out "$ICON_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICON_DIR" -o "$ICNS"
    echo "图标就绪：$ICNS"
fi

# ---- 3) 编译 ----
echo "==> swiftc -O 编译（Swift 5 语言模式，target macOS 26.0）"
swiftc -O \
    -swift-version 5 \
    -sdk "${BUILD_SDK:-$SHADOW}" \
    -module-cache-path "$MCACHE" \
    -target arm64-apple-macos26.0 \
    -parse-as-library \
    -o "$OUT" \
    Sources/AIRoleSim/*.swift \
    Sources/AIRoleSim/Views/*.swift

# ---- 4) 组装 bundle ----
echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT" "$APP/Contents/MacOS/$EXEC"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>5</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Aura 需要使用麦克风进行语音输入（听写）。</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Aura 使用系统语音识别将你说的话转为文字。</string>
    <key>NSContactsUsageDescription</key>
    <string>Aura 需要访问通讯录以查找联系人电话号码并发起通话。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Aura 需要控制音乐 App 来播放歌曲。</string>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array><string>iCloud.com.aura.backup</string></array>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array><string>iCloud.com.aura.backup</string></array>
    <key>com.apple.developer.icloud-services</key>
    <array><string>CloudDocuments</string></array>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP/Contents/PkgInfo"

# ---- 5) 签名并启动 ----
echo "==> ad-hoc 签名"
codesign --force --sign - "$APP" 2>/dev/null || true

if [ "${SKIP_LAUNCH:-0}" = "1" ]; then
    echo "SKIP_LAUNCH=1，跳过启动。应用位于 $APP"
else
    echo "==> 启动 $APP"
    open "$APP"
    echo "完成。应用位于 $APP"
fi
