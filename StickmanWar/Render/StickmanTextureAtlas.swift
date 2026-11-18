import AppKit
import CoreGraphics
import SpriteKit

/// 预烘焙 Retina 矢量部件纹理图集（`@MainActor` 单例缓存）
/// 设计目的（对应 DESIGN.md 11.2）：
/// 严禁在 SpriteKit 每帧修改 `SKShapeNode.path` 触发 CPU 三角重剖分！
/// 所有火柴人躯干、头盔、盾牌、刀枪弓斧、战马、器械、战旗与箭矢均在启动时通过 CoreGraphics 一次性栅格化为纯白基底 `SKTexture`，
/// 战场同屏数百名士兵全部由 `SKSpriteNode` 关节染色拼装，使 Apple Silicon Metal 后端自动合批（Auto-Batching）。
@MainActor
public final class StickmanTextureAtlas {
    public static let shared = StickmanTextureAtlas()

    public let whitePixel: SKTexture
    public let circleFilled: SKTexture
    public let circleRing: SKTexture
    public let heroCrownHead: SKTexture
    public let roundShield: SKTexture
    public let paviseShield: SKTexture
    public let saberBlade: SKTexture
    public let pikeShaft: SKTexture
    public let greatAxe: SKTexture
    public let bowArc: SKTexture
    public let crossbowFrame: SKTexture
    public let mountBody: SKTexture
    public let siegeChassis: SKTexture
    public let bannerFlag: SKTexture
    public let arrowProjectile: SKTexture
    public let sparkStar: SKTexture
    public let slashWave: SKTexture
    public let corpseSilhouette: SKTexture

    private init() {
        self.whitePixel = Self.makeTexture(width: 8, height: 8) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }

        self.circleFilled = Self.makeTexture(width: 36, height: 36) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
        }

        self.circleRing = Self.makeTexture(width: 64, height: 64) { ctx, w, h in
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(4.0)
            ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: w - 8, height: h - 8))
        }

        self.heroCrownHead = Self.makeTexture(width: 48, height: 48) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            // 统帅兜鍪头颅
            ctx.fillEllipse(in: CGRect(x: 11, y: 8, width: 26, height: 26))
            // 双翎羽冠饰
            ctx.move(to: CGPoint(x: 24, y: 32))
            ctx.addQuadCurve(to: CGPoint(x: 6, y: 45), control: CGPoint(x: 12, y: 44))
            ctx.addQuadCurve(to: CGPoint(x: 21, y: 30), control: CGPoint(x: 13, y: 35))
            ctx.fillPath()

            ctx.move(to: CGPoint(x: 24, y: 32))
            ctx.addQuadCurve(to: CGPoint(x: w - 6, y: 45), control: CGPoint(x: w - 12, y: 44))
            ctx.addQuadCurve(to: CGPoint(x: 27, y: 30), control: CGPoint(x: w - 13, y: 35))
            ctx.fillPath()
        }

        self.roundShield = Self.makeTexture(width: 32, height: 32) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 0.92, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.0)
            ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: w - 8, height: h - 8))
            ctx.fillEllipse(in: CGRect(x: 12, y: 12, width: 8, height: 8))
        }

        self.paviseShield = Self.makeTexture(width: 26, height: 38) { ctx, w, h in
            let rect = CGRect(x: 3, y: 3, width: w - 6, height: h - 6)
            let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.setFillColor(CGColor(gray: 0.92, alpha: 1.0))
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(2.5)
            ctx.addPath(path)
            ctx.strokePath()
        }

        self.saberBlade = Self.makeTexture(width: 44, height: 14) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            // 护手与刀柄
            ctx.fill(CGRect(x: 2, y: 5, width: 9, height: 4))
            ctx.fill(CGRect(x: 9, y: 2, width: 3, height: 10))
            // 微弧雁翎战刀刃口（朝右 +X）
            ctx.move(to: CGPoint(x: 12, y: 5))
            ctx.addLine(to: CGPoint(x: 36, y: 5))
            ctx.addLine(to: CGPoint(x: 42, y: 10))
            ctx.addQuadCurve(to: CGPoint(x: 12, y: 9), control: CGPoint(x: 28, y: 11))
            ctx.closePath()
            ctx.fillPath()
        }

        self.pikeShaft = Self.makeTexture(width: 68, height: 12) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 0.88, alpha: 1.0))
            ctx.fill(CGRect(x: 2, y: 4.5, width: 50, height: 3.0))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            // 菱形破甲枪尖与红缨节
            ctx.fillEllipse(in: CGRect(x: 47, y: 3, width: 6, height: 6))
            ctx.move(to: CGPoint(x: 52, y: 2.5))
            ctx.addLine(to: CGPoint(x: 66, y: 6.0))
            ctx.addLine(to: CGPoint(x: 52, y: 9.5))
            ctx.closePath()
            ctx.fillPath()
        }

        self.greatAxe = Self.makeTexture(width: 48, height: 28) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 0.88, alpha: 1.0))
            ctx.fill(CGRect(x: 2, y: 12, width: 36, height: 4))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            // 双刃重型破甲月牙巨斧头
            ctx.move(to: CGPoint(x: 26, y: 14))
            ctx.addQuadCurve(to: CGPoint(x: 44, y: 2), control: CGPoint(x: 34, y: 3))
            ctx.addQuadCurve(to: CGPoint(x: 44, y: 26), control: CGPoint(x: 47, y: 14))
            ctx.addQuadCurve(to: CGPoint(x: 26, y: 14), control: CGPoint(x: 34, y: 25))
            ctx.fillPath()
        }

        self.bowArc = Self.makeTexture(width: 28, height: 38) { ctx, _, h in
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.2)
            ctx.move(to: CGPoint(x: 7, y: 4))
            ctx.addQuadCurve(to: CGPoint(x: 7, y: h - 4), control: CGPoint(x: 25, y: h * 0.5))
            ctx.strokePath()
            ctx.setLineWidth(1.4)
            ctx.move(to: CGPoint(x: 7, y: 4))
            ctx.addLine(to: CGPoint(x: 7, y: h - 4))
            ctx.strokePath()
        }

        self.crossbowFrame = Self.makeTexture(width: 36, height: 28) { ctx, _, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 4, y: h * 0.5 - 2, width: 26, height: 4))
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.0)
            ctx.move(to: CGPoint(x: 22, y: 3))
            ctx.addQuadCurve(to: CGPoint(x: 22, y: h - 3), control: CGPoint(x: 32, y: h * 0.5))
            ctx.strokePath()
        }

        self.mountBody = Self.makeTexture(width: 56, height: 30) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            // 战马躯干、马颈马首与四蹄剪影（朝右 +X）
            ctx.fillEllipse(in: CGRect(x: 10, y: 9, width: 30, height: 13))
            ctx.move(to: CGPoint(x: 34, y: 15))
            ctx.addLine(to: CGPoint(x: 46, y: 26))
            ctx.addLine(to: CGPoint(x: 53, y: 22))
            ctx.addLine(to: CGPoint(x: 42, y: 11))
            ctx.closePath()
            ctx.fillPath()
            // 四腿与马尾
            ctx.fill(CGRect(x: 13, y: 2, width: 3.5, height: 10))
            ctx.fill(CGRect(x: 20, y: 3, width: 3.5, height: 9))
            ctx.fill(CGRect(x: 31, y: 3, width: 3.5, height: 9))
            ctx.fill(CGRect(x: 37, y: 2, width: 3.5, height: 10))
            ctx.fill(CGRect(x: 4, y: 13, width: 8, height: 3))
        }

        self.siegeChassis = Self.makeTexture(width: 64, height: 44) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 0.90, alpha: 1.0))
            ctx.fill(CGRect(x: 8, y: 12, width: 48, height: 10))
            // 双木轮与投臂支架
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.2)
            ctx.strokeEllipse(in: CGRect(x: 10, y: 3, width: 16, height: 16))
            ctx.strokeEllipse(in: CGRect(x: 38, y: 3, width: 16, height: 16))
            ctx.move(to: CGPoint(x: 18, y: 20))
            ctx.addLine(to: CGPoint(x: 32, y: 40))
            ctx.addLine(to: CGPoint(x: 46, y: 20))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: 12, y: 34))
            ctx.addLine(to: CGPoint(x: 54, y: 26))
            ctx.strokePath()
        }

        self.bannerFlag = Self.makeTexture(width: 38, height: 26) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 2, y: 2))
            ctx.addLine(to: CGPoint(x: w - 2, y: 4))
            ctx.addLine(to: CGPoint(x: w - 10, y: h * 0.5))
            ctx.addLine(to: CGPoint(x: w - 2, y: h - 4))
            ctx.addLine(to: CGPoint(x: 2, y: h - 2))
            ctx.closePath()
            ctx.fillPath()
        }

        self.arrowProjectile = Self.makeTexture(width: 32, height: 10) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 4, y: 4, width: 20, height: 2))
            // 箭簇（朝右 +X）
            ctx.move(to: CGPoint(x: 22, y: 1.5))
            ctx.addLine(to: CGPoint(x: 31, y: 5.0))
            ctx.addLine(to: CGPoint(x: 22, y: 8.5))
            ctx.closePath()
            ctx.fillPath()
            // 箭羽
            ctx.fill(CGRect(x: 2, y: 2.5, width: 5, height: 5))
        }

        self.sparkStar = Self.makeTexture(width: 32, height: 32) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            let cx = w * 0.5
            let cy = h * 0.5
            ctx.move(to: CGPoint(x: cx, y: h - 2))
            ctx.addLine(to: CGPoint(x: cx + 4, y: cy + 4))
            ctx.addLine(to: CGPoint(x: w - 2, y: cy))
            ctx.addLine(to: CGPoint(x: cx + 4, y: cy - 4))
            ctx.addLine(to: CGPoint(x: cx, y: 2))
            ctx.addLine(to: CGPoint(x: cx - 4, y: cy - 4))
            ctx.addLine(to: CGPoint(x: 2, y: cy))
            ctx.addLine(to: CGPoint(x: cx - 4, y: cy + 4))
            ctx.closePath()
            ctx.fillPath()
        }

        self.slashWave = Self.makeTexture(width: 40, height: 32) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 8, y: 3))
            ctx.addQuadCurve(to: CGPoint(x: 8, y: h - 3), control: CGPoint(x: w - 2, y: h * 0.5))
            ctx.addQuadCurve(to: CGPoint(x: 8, y: 3), control: CGPoint(x: w - 12, y: h * 0.5))
            ctx.fillPath()
        }

        self.corpseSilhouette = Self.makeTexture(width: 40, height: 18) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 30, y: 5, width: 8, height: 8))
            ctx.fill(CGRect(x: 14, y: 7, width: 16, height: 3.5))
            ctx.fill(CGRect(x: 4, y: 4, width: 11, height: 2.5))
            ctx.fill(CGRect(x: 4, y: 11, width: 11, height: 2.5))
        }
    }

    /// 零窗口依赖的 CoreGraphics 位图栅格化工具（兼容实机 Retina 与无头 XCTest 环境）
    private static func makeTexture(
        width: Int,
        height: Int,
        draw: (CGContext, CGFloat, CGFloat) -> Void
    ) -> SKTexture {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return SKTexture()
        }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        draw(ctx, CGFloat(width), CGFloat(height))
        guard let cgImage = ctx.makeImage() else {
            return SKTexture()
        }
        let tex = SKTexture(cgImage: cgImage)
        tex.filteringMode = .linear
        return tex
    }

    /// 将势力十六进制主色转换为 AppKit `NSColor`
    public static func nsColor(hex: String, alpha: CGFloat = 1.0) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }
}
