#!/bin/bash
# 构建 Aura.app：swiftc 直接编译（绕过本机 CLT 的 SwiftPM 清单缺陷与缺失的 SwiftUIMacros 宏插件）
# → 生成图标 → 组装 bundle → ad-hoc 签名 → 启动
set -euo pipefail
cd "$(dirname "$0")"

# 单一版本源：VERSION 文件（避免 bundle/源码/Release 版本号错位导致反复提示更新）
APP_VERSION="$(cat VERSION 2>/dev/null || echo '1.2.3')"
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

// Aura 图标：深邃夜空渐变 + 柔光 + 轨道环 + 极简星芒 A
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 背景圆角方（Apple 图标网格）
let inset: CGFloat = 96
let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let bgPath = CGPath(roundedRect: rect, cornerWidth: 224, cornerHeight: 224, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// 深空主渐变：深靛蓝 → 紫罗兰
let bgColors = [
    CGColor(red: 0.055, green: 0.086, blue: 0.208, alpha: 1),
    CGColor(red: 0.16, green: 0.13, blue: 0.38, alpha: 1),
    CGColor(red: 0.36, green: 0.30, blue: 0.72, alpha: 1)
] as CFArray
let bgGrad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: inset, y: S - inset), end: CGPoint(x: S - inset, y: inset), options: [])

// 中心柔光（发光核心）
let glow = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.45, green: 0.62, blue: 1.0, alpha: 0.42),
    CGColor(red: 0.45, green: 0.62, blue: 1.0, alpha: 0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow,
    startCenter: CGPoint(x: S/2, y: S/2), startRadius: 40,
    endCenter: CGPoint(x: S/2, y: S/2), endRadius: 440, options: [])
// 左下冷光点缀
let glow2 = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.72, green: 0.45, blue: 1.0, alpha: 0.22),
    CGColor(red: 0.72, green: 0.45, blue: 1.0, alpha: 0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow2,
    startCenter: CGPoint(x: 220, y: 120), startRadius: 10,
    endCenter: CGPoint(x: 220, y: 120), endRadius: 380, options: [])

let cx = S / 2
let cy = S / 2

// 轨道环：两道细椭圆弧，暗示"围绕角色的思维轨迹"
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
ctx.setLineWidth(5)
let ring1 = CGRect(x: cx - 300, y: cy - 300, width: 600, height: 600)
ctx.addEllipse(in: ring1)
ctx.strokePath()
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
ctx.setLineWidth(3)
let ring2 = CGRect(x: cx - 385, y: cy - 235, width: 770, height: 470)
ctx.addEllipse(in: ring2)
ctx.strokePath()

// 星芒：四点光芒（线性渐变三角）
func spike(center: CGPoint, length: CGFloat, width: CGFloat, rotation: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: alpha),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: length), options: [])
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: length))
    ctx.addLine(to: CGPoint(x: -width, y: 0))
    ctx.addLine(to: CGPoint(x: width, y: 0))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}
for r in stride(from: 0, to: CGFloat.pi * 2, by: CGFloat.pi / 4) {
    spike(center: CGPoint(x: cx, y: cy), length: 420, width: 18, rotation: r, alpha: 0.16)
}

// 极简 A 字标：圆体 + 微光
let par = NSMutableParagraphStyle()
par.alignment = .center
let font = NSFont.systemFont(ofSize: 500, weight: .semibold)
let str = NSAttributedString(string: "A", attributes: [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: par
])
let line = CTLineCreateWithAttributedString(str)
let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 30, color: CGColor(red: 0.55, green: 0.65, blue: 1, alpha: 0.55))
ctx.textPosition = CGPoint(x: cx - b.width / 2, y: cy - b.midY - 10)
CTLineDraw(line, ctx)
ctx.restoreGState()

// 顶部高光描边
ctx.saveGState()
ctx.addPath(bgPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

guard let img = ctx.makeImage() else { fatalError("渲染失败") }
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
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>6</string>
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
