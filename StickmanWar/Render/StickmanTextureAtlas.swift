import AppKit
import CoreGraphics
import SpriteKit

/// 次世代高分屏程序化矢量美术纹理图集（`@MainActor` 单例缓存）
/// 全部士兵甲胄、罗马羽冠兜鍪、方盾圆盾、冷兵器、披风、战马、14 类帝国建筑、森林树木、矿脉农庄与光晕均在启动时由 CoreGraphics 高清烘焙（带深色描边与金属高光），
/// 令 SpriteKit Metal 后端自动合批，彻底告别纯色方块感。
@MainActor
public final class StickmanTextureAtlas {
    public static let shared = StickmanTextureAtlas()

    // 基础几何与光效
    public let whitePixel: SKTexture
    public let circleFilled: SKTexture
    public let circleRing: SKTexture
    public let softGlowHalo: SKTexture
    public let selectionRingDecal: SKTexture

    // 英雄与精锐士兵躯干/头盔/披风部件（全带黑曜描边）
    public let heroCrownHead: SKTexture
    public let legionCrestHead: SKTexture
    public let nomadHelmHead: SKTexture
    public let armoredTorso: SKTexture
    public let limbSegment: SKTexture
    public let flowingCape: SKTexture

    // 盾牌、冷兵器与坐骑器械
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

    // 投射物与粒子遗骸
    public let arrowProjectile: SKTexture
    public let boulderProjectile: SKTexture
    public let sparkStar: SKTexture
    public let slashWave: SKTexture
    public let corpseSilhouette: SKTexture

    // 战场自然地貌与资源地标贴图
    public let terrainNoisePatch: SKTexture
    public let cobbleRoadTile: SKTexture
    public let pineTreeCanopy: SKTexture
    public let cliffRockSprite: SKTexture
    public let stoneBridgeSprite: SKTexture
    public let goldMineLandmark: SKTexture
    public let lumberCampLandmark: SKTexture
    public let wheatFarmLandmark: SKTexture

    // 14 类帝国城防与 RTS 基地建筑精细俯视贴图
    private var buildingTextures: [SiegeStructureKind: SKTexture] = [:]

    private init() {
        self.whitePixel = Self.makeTexture(width: 8, height: 8) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }

        self.circleFilled = Self.makeTexture(width: 48, height: 48) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
        }

        self.circleRing = Self.makeTexture(width: 72, height: 72) { ctx, w, h in
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(4.5)
            ctx.strokeEllipse(in: CGRect(x: 5, y: 5, width: w - 10, height: h - 10))
        }

        self.softGlowHalo = Self.makeTexture(width: 96, height: 96) { ctx, w, h in
            let cs = CGColorSpaceCreateDeviceRGB()
            let comps: [CGFloat] = [1, 1, 1, 0.85, 1, 1, 1, 0.28, 1, 1, 1, 0.0]
            let locs: [CGFloat] = [0.0, 0.45, 1.0]
            if let grad = CGGradient(colorSpace: cs, colorComponents: comps, locations: locs, count: 3) {
                let c = CGPoint(x: w * 0.5, y: h * 0.5)
                ctx.drawRadialGradient(grad, startCenter: c, startRadius: 2, endCenter: c, endRadius: w * 0.48, options: [])
            }
        }

        self.selectionRingDecal = Self.makeTexture(width: 84, height: 44) { ctx, w, h in
            ctx.setStrokeColor(CGColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 0.95))
            ctx.setLineWidth(3.2)
            ctx.strokeEllipse(in: CGRect(x: 5, y: 5, width: w - 10, height: h - 10))
            ctx.setFillColor(CGColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 0.16))
            ctx.fillEllipse(in: CGRect(x: 6, y: 6, width: w - 12, height: h - 12))
        }

        self.heroCrownHead = Self.makeTexture(width: 56, height: 56) { ctx, w, _ in
            // 双翎羽黄金统帅兜鍪 + 黑边勾勒
            let headRect = CGRect(x: 13, y: 9, width: 30, height: 30)
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.95))
            ctx.fillEllipse(in: headRect.insetBy(dx: -2.5, dy: -2.5))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fillEllipse(in: headRect)
            // 护目字形面甲纹
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 0.85))
            ctx.fill(CGRect(x: 20, y: 21, width: 16, height: 3.2))
            ctx.fill(CGRect(x: 26.5, y: 14, width: 3.0, height: 10))
            // 双翼冠羽
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 28, y: 37))
            ctx.addQuadCurve(to: CGPoint(x: 6, y: 52), control: CGPoint(x: 13, y: 50))
            ctx.addQuadCurve(to: CGPoint(x: 24, y: 35), control: CGPoint(x: 14, y: 40))
            ctx.fillPath()
            ctx.move(to: CGPoint(x: 28, y: 37))
            ctx.addQuadCurve(to: CGPoint(x: w - 6, y: 52), control: CGPoint(x: w - 13, y: 50))
            ctx.addQuadCurve(to: CGPoint(x: 32, y: 35), control: CGPoint(x: w - 14, y: 40))
            ctx.fillPath()
        }

        self.legionCrestHead = Self.makeTexture(width: 48, height: 48) { ctx, _, _ in
            // 罗马帝国百夫长横向马鬃羽冠头盔（Galea）
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 10, y: 32))
            ctx.addQuadCurve(to: CGPoint(x: 38, y: 32), control: CGPoint(x: 24, y: 47))
            ctx.addLine(to: CGPoint(x: 33, y: 28))
            ctx.addLine(to: CGPoint(x: 15, y: 28))
            ctx.closePath()
            ctx.fillPath()

            let helm = CGRect(x: 12, y: 8, width: 24, height: 24)
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.95))
            ctx.fillEllipse(in: helm.insetBy(dx: -2.2, dy: -2.2))
            ctx.setFillColor(CGColor(gray: 0.96, alpha: 1.0))
            ctx.fillEllipse(in: helm)
            ctx.setFillColor(CGColor(gray: 0.22, alpha: 0.85))
            ctx.fill(CGRect(x: 22, y: 16, width: 13, height: 3.2))
        }

        self.nomadHelmHead = Self.makeTexture(width: 44, height: 44) { ctx, _, _ in
            let helm = CGRect(x: 10, y: 7, width: 24, height: 24)
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.95))
            ctx.fillEllipse(in: helm.insetBy(dx: -2.2, dy: -2.2))
            ctx.setFillColor(CGColor(gray: 0.96, alpha: 1.0))
            ctx.fillEllipse(in: helm)
            // 尖顶盔缨
            ctx.move(to: CGPoint(x: 16, y: 28))
            ctx.addLine(to: CGPoint(x: 22, y: 40))
            ctx.addLine(to: CGPoint(x: 28, y: 28))
            ctx.closePath()
            ctx.fillPath()
        }

        self.armoredTorso = Self.makeTexture(width: 28, height: 38) { ctx, w, h in
            // 倒梯形重装胸甲与护肩轮廓
            let outer = CGPath(roundedRect: CGRect(x: 3, y: 3, width: w - 6, height: h - 6), cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.setFillColor(CGColor(gray: 0.07, alpha: 0.95))
            ctx.addPath(outer)
            ctx.fillPath()

            let inner = CGPath(roundedRect: CGRect(x: 5.2, y: 5.2, width: w - 10.4, height: h - 10.4), cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.addPath(inner)
            ctx.fillPath()

            // 胸甲腰带与甲片横纹
            ctx.setFillColor(CGColor(gray: 0.72, alpha: 0.65))
            ctx.fill(CGRect(x: 6, y: 13, width: w - 12, height: 2.5))
            ctx.fill(CGRect(x: 6, y: 21, width: w - 12, height: 2.2))
        }

        self.limbSegment = Self.makeTexture(width: 14, height: 30) { ctx, w, h in
            let outer = CGPath(roundedRect: CGRect(x: 1.5, y: 1.5, width: w - 3, height: h - 3), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.92))
            ctx.addPath(outer)
            ctx.fillPath()
            let inner = CGPath(roundedRect: CGRect(x: 3.2, y: 3.0, width: w - 6.4, height: h - 6.0), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            ctx.setFillColor(CGColor(gray: 0.96, alpha: 1.0))
            ctx.addPath(inner)
            ctx.fillPath()
        }

        self.flowingCape = Self.makeTexture(width: 30, height: 36) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 0.95, alpha: 0.92))
            ctx.move(to: CGPoint(x: w - 5, y: h - 4))
            ctx.addLine(to: CGPoint(x: 3, y: 5))
            ctx.addQuadCurve(to: CGPoint(x: w - 4, y: 4), control: CGPoint(x: w * 0.5, y: 1))
            ctx.closePath()
            ctx.fillPath()
        }

        self.roundShield = Self.makeTexture(width: 40, height: 40) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.95))
            ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: w - 4, height: h - 4))
            ctx.setFillColor(CGColor(gray: 0.88, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 4.5, y: 4.5, width: w - 9, height: h - 9))
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.2)
            ctx.strokeEllipse(in: CGRect(x: 6, y: 6, width: w - 12, height: h - 12))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 15, y: 15, width: 10, height: 10))
        }

        self.paviseShield = Self.makeTexture(width: 32, height: 46) { ctx, w, h in
            // 罗马军团大盾 Scutum（金边雷霆翼纹）
            let outer = CGPath(roundedRect: CGRect(x: 2, y: 2, width: w - 4, height: h - 4), cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.95))
            ctx.addPath(outer)
            ctx.fillPath()

            let inner = CGPath(roundedRect: CGRect(x: 4.5, y: 4.5, width: w - 9, height: h - 9), cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.setFillColor(CGColor(gray: 0.88, alpha: 1.0))
            ctx.addPath(inner)
            ctx.fillPath()

            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(2.6)
            ctx.addPath(inner)
            ctx.strokePath()
            // 中央盾脐与十字金饰
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: w * 0.5 - 1.5, y: 8, width: 3, height: h - 16))
            ctx.fill(CGRect(x: 7, y: h * 0.5 - 1.5, width: w - 14, height: 3))
            ctx.fillEllipse(in: CGRect(x: w * 0.5 - 5, y: h * 0.5 - 5, width: 10, height: 10))
        }

        self.saberBlade = Self.makeTexture(width: 52, height: 18) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 0.12, alpha: 0.95))
            ctx.fill(CGRect(x: 2, y: 6, width: 11, height: 6))
            ctx.setFillColor(CGColor(red: 0.95, green: 0.80, blue: 0.35, alpha: 1.0))
            ctx.fill(CGRect(x: 10, y: 2.5, width: 4, height: 13))
            // 寒光钢刃
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 0.9))
            ctx.move(to: CGPoint(x: 14, y: 5))
            ctx.addLine(to: CGPoint(x: 42, y: 5))
            ctx.addLine(to: CGPoint(x: 50, y: 11))
            ctx.addQuadCurve(to: CGPoint(x: 14, y: 12), control: CGPoint(x: 32, y: 14))
            ctx.closePath()
            ctx.fillPath()

            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 14, y: 6.2))
            ctx.addLine(to: CGPoint(x: 41, y: 6.2))
            ctx.addLine(to: CGPoint(x: 48, y: 10.5))
            ctx.addQuadCurve(to: CGPoint(x: 14, y: 10.8), control: CGPoint(x: 32, y: 12.2))
            ctx.closePath()
            ctx.fillPath()
        }

        self.pikeShaft = Self.makeTexture(width: 78, height: 14) { ctx, _, _ in
            ctx.setFillColor(CGColor(red: 0.58, green: 0.42, blue: 0.24, alpha: 1.0))
            ctx.fill(CGRect(x: 2, y: 5.0, width: 56, height: 4.0))
            // 猩红枪缨
            ctx.setFillColor(CGColor(red: 0.92, green: 0.22, blue: 0.18, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 53, y: 2.5, width: 8, height: 9))
            // 精钢长枪刃
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 58, y: 2.5))
            ctx.addLine(to: CGPoint(x: 76, y: 7.0))
            ctx.addLine(to: CGPoint(x: 58, y: 11.5))
            ctx.closePath()
            ctx.fillPath()
        }

        self.greatAxe = Self.makeTexture(width: 54, height: 32) { ctx, _, _ in
            ctx.setFillColor(CGColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1.0))
            ctx.fill(CGRect(x: 2, y: 13.5, width: 40, height: 5))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 28, y: 16))
            ctx.addQuadCurve(to: CGPoint(x: 49, y: 2), control: CGPoint(x: 38, y: 3))
            ctx.addQuadCurve(to: CGPoint(x: 49, y: 30), control: CGPoint(x: 52, y: 16))
            ctx.addQuadCurve(to: CGPoint(x: 28, y: 16), control: CGPoint(x: 38, y: 29))
            ctx.fillPath()
        }

        self.bowArc = Self.makeTexture(width: 32, height: 44) { ctx, _, h in
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.8)
            ctx.move(to: CGPoint(x: 8, y: 4))
            ctx.addQuadCurve(to: CGPoint(x: 8, y: h - 4), control: CGPoint(x: 29, y: h * 0.5))
            ctx.strokePath()
            ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 0.9))
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 8, y: 4))
            ctx.addLine(to: CGPoint(x: 8, y: h - 4))
            ctx.strokePath()
        }

        self.crossbowFrame = Self.makeTexture(width: 40, height: 32) { ctx, _, h in
            ctx.setFillColor(CGColor(red: 0.65, green: 0.46, blue: 0.24, alpha: 1.0))
            ctx.fill(CGRect(x: 4, y: h * 0.5 - 2.5, width: 30, height: 5))
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.4)
            ctx.move(to: CGPoint(x: 24, y: 3))
            ctx.addQuadCurve(to: CGPoint(x: 24, y: h - 3), control: CGPoint(x: 36, y: h * 0.5))
            ctx.strokePath()
        }

        self.mountBody = Self.makeTexture(width: 68, height: 38) { ctx, _, _ in
            // 披甲战马剪影（带深色轮廓与马鞍披挂）
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.92))
            ctx.fillEllipse(in: CGRect(x: 10, y: 10, width: 38, height: 18))
            ctx.setFillColor(CGColor(gray: 0.96, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 12, y: 12, width: 34, height: 14))
            // 马颈与马首
            ctx.move(to: CGPoint(x: 40, y: 18))
            ctx.addLine(to: CGPoint(x: 54, y: 33))
            ctx.addLine(to: CGPoint(x: 64, y: 27))
            ctx.addLine(to: CGPoint(x: 49, y: 14))
            ctx.closePath()
            ctx.fillPath()
            // 四蹄与飘逸马尾
            ctx.fill(CGRect(x: 15, y: 2, width: 4.2, height: 12))
            ctx.fill(CGRect(x: 23, y: 3, width: 4.0, height: 11))
            ctx.fill(CGRect(x: 36, y: 3, width: 4.0, height: 11))
            ctx.fill(CGRect(x: 43, y: 2, width: 4.2, height: 12))
            ctx.move(to: CGPoint(x: 13, y: 22))
            ctx.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 4, y: 24))
            ctx.addLine(to: CGPoint(x: 6, y: 10))
            ctx.closePath()
            ctx.fillPath()
        }

        self.siegeChassis = Self.makeTexture(width: 76, height: 52) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 0.10, alpha: 0.92))
            ctx.fill(CGRect(x: 8, y: 13, width: 60, height: 14))
            ctx.setFillColor(CGColor(gray: 0.92, alpha: 1.0))
            ctx.fill(CGRect(x: 10, y: 15, width: 56, height: 10))
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(3.8)
            ctx.strokeEllipse(in: CGRect(x: 11, y: 3, width: 18, height: 18))
            ctx.strokeEllipse(in: CGRect(x: 47, y: 3, width: 18, height: 18))
            ctx.move(to: CGPoint(x: 20, y: 23))
            ctx.addLine(to: CGPoint(x: 38, y: 47))
            ctx.addLine(to: CGPoint(x: 56, y: 23))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: 12, y: 41))
            ctx.addLine(to: CGPoint(x: 66, y: 30))
            ctx.strokePath()
        }

        self.bannerFlag = Self.makeTexture(width: 44, height: 30) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.9))
            ctx.fill(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 3, y: 3))
            ctx.addLine(to: CGPoint(x: w - 3, y: 5))
            ctx.addLine(to: CGPoint(x: w - 12, y: h * 0.5))
            ctx.addLine(to: CGPoint(x: w - 3, y: h - 5))
            ctx.addLine(to: CGPoint(x: 3, y: h - 3))
            ctx.closePath()
            ctx.fillPath()
        }

        self.arrowProjectile = Self.makeTexture(width: 36, height: 10) { ctx, _, _ in
            ctx.setFillColor(CGColor(red: 0.85, green: 0.72, blue: 0.48, alpha: 1.0))
            ctx.fill(CGRect(x: 4, y: 4, width: 22, height: 2.2))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 24, y: 1.2))
            ctx.addLine(to: CGPoint(x: 35, y: 5.0))
            ctx.addLine(to: CGPoint(x: 24, y: 8.8))
            ctx.closePath()
            ctx.fillPath()
            ctx.setFillColor(CGColor(gray: 0.95, alpha: 0.95))
            ctx.fill(CGRect(x: 2, y: 2.2, width: 6, height: 5.6))
        }

        self.boulderProjectile = Self.makeTexture(width: 36, height: 36) { ctx, w, h in
            ctx.setFillColor(CGColor(red: 1.0, green: 0.52, blue: 0.12, alpha: 0.48))
            ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
            ctx.setFillColor(CGColor(gray: 0.36, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 6, y: 6, width: w - 12, height: h - 12))
            ctx.setFillColor(CGColor(gray: 0.58, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 9, y: 11, width: 12, height: 10))
        }

        self.sparkStar = Self.makeTexture(width: 36, height: 36) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            let cx = w * 0.5
            let cy = h * 0.5
            ctx.move(to: CGPoint(x: cx, y: h - 2))
            ctx.addLine(to: CGPoint(x: cx + 4.5, y: cy + 4.5))
            ctx.addLine(to: CGPoint(x: w - 2, y: cy))
            ctx.addLine(to: CGPoint(x: cx + 4.5, y: cy - 4.5))
            ctx.addLine(to: CGPoint(x: cx, y: 2))
            ctx.addLine(to: CGPoint(x: cx - 4.5, y: cy - 4.5))
            ctx.addLine(to: CGPoint(x: 2, y: cy))
            ctx.addLine(to: CGPoint(x: cx - 4.5, y: cy + 4.5))
            ctx.closePath()
            ctx.fillPath()
        }

        self.slashWave = Self.makeTexture(width: 48, height: 38) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.move(to: CGPoint(x: 8, y: 3))
            ctx.addQuadCurve(to: CGPoint(x: 8, y: h - 3), control: CGPoint(x: w - 2, y: h * 0.5))
            ctx.addQuadCurve(to: CGPoint(x: 8, y: 3), control: CGPoint(x: w - 14, y: h * 0.5))
            ctx.fillPath()
        }

        self.corpseSilhouette = Self.makeTexture(width: 44, height: 20) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 0.85))
            ctx.fillEllipse(in: CGRect(x: 32, y: 5, width: 9, height: 9))
            ctx.fill(CGRect(x: 15, y: 7.5, width: 17, height: 4.0))
            ctx.fill(CGRect(x: 3, y: 4.5, width: 12, height: 2.8))
            ctx.fill(CGRect(x: 3, y: 11.5, width: 12, height: 2.8))
        }

        // 自然地貌肌理与树木/石桥/矿脉/麦田地标
        self.terrainNoisePatch = Self.makeTexture(width: 128, height: 128) { ctx, w, h in
            let cs = CGColorSpaceCreateDeviceRGB()
            let comps: [CGFloat] = [1, 1, 1, 0.22, 1, 1, 1, 0.08, 1, 1, 1, 0.0]
            if let grad = CGGradient(colorSpace: cs, colorComponents: comps, locations: [0, 0.55, 1], count: 3) {
                let c = CGPoint(x: w * 0.5, y: h * 0.5)
                ctx.drawRadialGradient(grad, startCenter: c, startRadius: 4, endCenter: c, endRadius: w * 0.48, options: [])
            }
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.30))
            for k in 0..<18 {
                let px = CGFloat((k * 37 + 19) % 108 + 10)
                let py = CGFloat((k * 53 + 11) % 108 + 10)
                ctx.fill(CGRect(x: px, y: py, width: 2.5, height: 6.5))
            }
        }

        self.cobbleRoadTile = Self.makeTexture(width: 160, height: 56) { ctx, w, h in
            ctx.setFillColor(CGColor(red: 0.44, green: 0.38, blue: 0.29, alpha: 0.68))
            ctx.fill(CGRect(x: 0, y: 6, width: w, height: h - 12))
            ctx.setFillColor(CGColor(red: 0.56, green: 0.49, blue: 0.38, alpha: 0.55))
            ctx.fill(CGRect(x: 0, y: 6, width: w, height: 3.5))
            ctx.fill(CGRect(x: 0, y: h - 9.5, width: w, height: 3.5))
            for i in 0..<10 {
                let x = CGFloat(i) * 16.0 + 4.0
                ctx.fill(CGRect(x: x, y: 15, width: 11, height: 9))
                ctx.fill(CGRect(x: x + 6, y: 29, width: 11, height: 9))
            }
        }

        self.pineTreeCanopy = Self.makeTexture(width: 68, height: 68) { ctx, w, h in
            // 地面树影
            ctx.setFillColor(CGColor(gray: 0.0, alpha: 0.32))
            ctx.fillEllipse(in: CGRect(x: 12, y: 6, width: w - 20, height: 22))
            // 三层苍翠松冠
            ctx.setFillColor(CGColor(red: 0.09, green: 0.26, blue: 0.13, alpha: 0.96))
            ctx.fillEllipse(in: CGRect(x: 8, y: 12, width: w - 16, height: h - 20))
            ctx.setFillColor(CGColor(red: 0.15, green: 0.38, blue: 0.19, alpha: 0.96))
            ctx.fillEllipse(in: CGRect(x: 14, y: 19, width: w - 28, height: h - 30))
            ctx.setFillColor(CGColor(red: 0.24, green: 0.50, blue: 0.26, alpha: 0.95))
            ctx.fillEllipse(in: CGRect(x: 21, y: 26, width: w - 42, height: h - 42))
        }

        self.cliffRockSprite = Self.makeTexture(width: 120, height: 64) { ctx, w, h in
            ctx.setFillColor(CGColor(red: 0.24, green: 0.21, blue: 0.17, alpha: 0.78))
            ctx.move(to: CGPoint(x: 6, y: 10))
            ctx.addLine(to: CGPoint(x: 28, y: h - 8))
            ctx.addLine(to: CGPoint(x: 68, y: h - 4))
            ctx.addLine(to: CGPoint(x: w - 8, y: 14))
            ctx.closePath()
            ctx.fillPath()
            ctx.setFillColor(CGColor(red: 0.45, green: 0.40, blue: 0.33, alpha: 0.68))
            ctx.move(to: CGPoint(x: 24, y: 22))
            ctx.addLine(to: CGPoint(x: 34, y: h - 12))
            ctx.addLine(to: CGPoint(x: 66, y: h - 10))
            ctx.addLine(to: CGPoint(x: 88, y: 24))
            ctx.closePath()
            ctx.fillPath()
        }

        self.stoneBridgeSprite = Self.makeTexture(width: 180, height: 110) { ctx, w, h in
            ctx.setFillColor(CGColor(red: 0.38, green: 0.36, blue: 0.33, alpha: 0.96))
            ctx.fill(CGRect(x: 4, y: 8, width: w - 8, height: h - 16))
            // 桥面木石横纹与两侧石护栏垛口
            ctx.setFillColor(CGColor(red: 0.48, green: 0.44, blue: 0.38, alpha: 0.95))
            for i in 0..<9 {
                let x = CGFloat(i) * 19.0 + 8.0
                ctx.fill(CGRect(x: x, y: 18, width: 15, height: h - 36))
            }
            ctx.setFillColor(CGColor(red: 0.62, green: 0.59, blue: 0.54, alpha: 1.0))
            ctx.fill(CGRect(x: 4, y: 8, width: w - 8, height: 9))
            ctx.fill(CGRect(x: 4, y: h - 17, width: w - 8, height: 9))
        }

        self.goldMineLandmark = Self.makeTexture(width: 92, height: 80) { ctx, _, _ in
            // 岩山矿洞 + 璀璨金矿晶簇
            ctx.setFillColor(CGColor(gray: 0.0, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: 8, y: 6, width: 76, height: 32))
            ctx.setFillColor(CGColor(red: 0.34, green: 0.30, blue: 0.25, alpha: 0.98))
            ctx.move(to: CGPoint(x: 10, y: 16))
            ctx.addLine(to: CGPoint(x: 26, y: 66))
            ctx.addLine(to: CGPoint(x: 66, y: 68))
            ctx.addLine(to: CGPoint(x: 82, y: 16))
            ctx.closePath()
            ctx.fillPath()
            // 矿洞木梁门框
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.95))
            ctx.fill(CGRect(x: 33, y: 16, width: 24, height: 24))
            ctx.setStrokeColor(CGColor(red: 0.62, green: 0.42, blue: 0.20, alpha: 1.0))
            ctx.setLineWidth(4.0)
            ctx.stroke(CGRect(x: 33, y: 16, width: 24, height: 24))
            // 耀眼纯金矿石脉
            ctx.setFillColor(CGColor(red: 0.99, green: 0.82, blue: 0.18, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 16, y: 24, width: 14, height: 12))
            ctx.fillEllipse(in: CGRect(x: 61, y: 22, width: 15, height: 13))
            ctx.fillEllipse(in: CGRect(x: 42, y: 48, width: 16, height: 11))
        }

        self.lumberCampLandmark = Self.makeTexture(width: 92, height: 80) { ctx, _, _ in
            ctx.setFillColor(CGColor(gray: 0.0, alpha: 0.30))
            ctx.fillEllipse(in: CGRect(x: 10, y: 8, width: 72, height: 30))
            // 原木堆叠与苍松
            ctx.setFillColor(CGColor(red: 0.56, green: 0.36, blue: 0.18, alpha: 1.0))
            for row in 0..<3 {
                ctx.fill(CGRect(x: 14, y: CGFloat(14 + row * 8), width: 34, height: 6.5))
            }
            ctx.setFillColor(CGColor(red: 0.82, green: 0.66, blue: 0.42, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 45, y: 14, width: 7, height: 7))
            ctx.fillEllipse(in: CGRect(x: 45, y: 22, width: 7, height: 7))
            // 双松树冠
            ctx.setFillColor(CGColor(red: 0.16, green: 0.46, blue: 0.22, alpha: 0.98))
            ctx.fillEllipse(in: CGRect(x: 44, y: 30, width: 36, height: 36))
            ctx.setFillColor(CGColor(red: 0.24, green: 0.58, blue: 0.28, alpha: 0.98))
            ctx.fillEllipse(in: CGRect(x: 20, y: 38, width: 30, height: 30))
        }

        self.wheatFarmLandmark = Self.makeTexture(width: 96, height: 80) { ctx, _, _ in
            // 金黄丰收麦垄与谷仓草垛
            ctx.setFillColor(CGColor(red: 0.36, green: 0.26, blue: 0.15, alpha: 0.92))
            ctx.fill(CGRect(x: 8, y: 10, width: 80, height: 56))
            ctx.setFillColor(CGColor(red: 0.93, green: 0.74, blue: 0.22, alpha: 0.96))
            for r in 0..<5 {
                ctx.fill(CGRect(x: 13, y: CGFloat(14 + r * 10), width: 48, height: 6.5))
            }
            // 圆顶粮囤
            ctx.setFillColor(CGColor(red: 0.78, green: 0.56, blue: 0.24, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: 64, y: 22, width: 22, height: 22))
            ctx.setStrokeColor(CGColor(red: 0.45, green: 0.30, blue: 0.12, alpha: 1.0))
            ctx.setLineWidth(2.0)
            ctx.strokeEllipse(in: CGRect(x: 64, y: 22, width: 22, height: 22))
        }

        for kind in SiegeStructureKind.allCases {
            buildingTextures[kind] = Self.bakeBuildingTexture(for: kind)
        }
    }

    public func buildingTexture(for kind: SiegeStructureKind) -> SKTexture {
        buildingTextures[kind] ?? whitePixel
    }

    // MARK: - 14 类帝国建筑精细 2.5D 俯视屋脊与石砌贴图烘焙

    private static func bakeBuildingTexture(for kind: SiegeStructureKind) -> SKTexture {
        switch kind {
        case .baseCamp:
            return makeTexture(width: 180, height: 280) { ctx, w, h in
                // 宏伟阶梯石基坛 + 重檐帅帐宫殿 + 四角箭楼火盆
                ctx.setFillColor(CGColor(gray: 0.0, alpha: 0.42))
                ctx.fill(CGRect(x: 8, y: 6, width: w - 12, height: h - 12))
                ctx.setFillColor(CGColor(gray: 0.36, alpha: 0.98))
                ctx.fill(CGRect(x: 6, y: 10, width: w - 12, height: h - 20))
                ctx.setStrokeColor(CGColor(red: 0.85, green: 0.72, blue: 0.42, alpha: 0.95))
                ctx.setLineWidth(3.5)
                ctx.stroke(CGRect(x: 9, y: 13, width: w - 18, height: h - 26))
                // 中央帅殿大屋顶（留纯白灰度供势力主色染色）
                ctx.setFillColor(CGColor(gray: 0.92, alpha: 1.0))
                ctx.fill(CGRect(x: 24, y: 48, width: w - 48, height: h - 96))
                // 鎏金正脊与斜脊
                ctx.setStrokeColor(CGColor(red: 1.0, green: 0.88, blue: 0.48, alpha: 1.0))
                ctx.setLineWidth(4.0)
                ctx.stroke(CGRect(x: 32, y: 60, width: w - 64, height: h - 120))
                ctx.move(to: CGPoint(x: w * 0.5, y: 54))
                ctx.addLine(to: CGPoint(x: w * 0.5, y: h - 54))
                ctx.strokePath()
                // 四角石砌角楼与火盆光点
                for (tx, ty) in [(16.0, 20.0), (Double(w) - 38.0, 20.0), (16.0, Double(h) - 42.0), (Double(w) - 38.0, Double(h) - 42.0)] {
                    ctx.setFillColor(CGColor(gray: 0.52, alpha: 1.0))
                    ctx.fill(CGRect(x: tx, y: ty, width: 22, height: 22))
                    ctx.setFillColor(CGColor(red: 1.0, green: 0.62, blue: 0.16, alpha: 1.0))
                    ctx.fillEllipse(in: CGRect(x: tx + 6, y: ty + 6, width: 10, height: 10))
                }
            }

        case .houseQuarter:
            return makeTexture(width: 96, height: 84) { ctx, w, h in
                ctx.setFillColor(CGColor(gray: 0.0, alpha: 0.35))
                ctx.fill(CGRect(x: 8, y: 5, width: w - 12, height: h - 12))
                ctx.setFillColor(CGColor(red: 0.44, green: 0.38, blue: 0.30, alpha: 0.96))
                ctx.fill(CGRect(x: 6, y: 8, width: w - 12, height: h - 16))
                // 双坡瓦顶
                ctx.setFillColor(CGColor(gray: 0.94, alpha: 1.0))
                ctx.fill(CGRect(x: 12, y: 16, width: w - 24, height: h - 32))
                ctx.setStrokeColor(CGColor(gray: 0.25, alpha: 0.85))
                ctx.setLineWidth(2.5)
                ctx.move(to: CGPoint(x: 12, y: h * 0.5))
                ctx.addLine(to: CGPoint(x: w - 12, y: h * 0.5))
                ctx.strokePath()
            }

        case .imperialFarm:
            return makeTexture(width: 128, height: 104) { ctx, w, h in
                ctx.setFillColor(CGColor(red: 0.32, green: 0.23, blue: 0.13, alpha: 0.95))
                ctx.fill(CGRect(x: 4, y: 4, width: w - 8, height: h - 8))
                // 四块井田金黄麦畦
                ctx.setFillColor(CGColor(red: 0.92, green: 0.75, blue: 0.24, alpha: 0.96))
                for (fx, fy) in [(10.0, 10.0), (68.0, 10.0), (10.0, 56.0)] {
                    for row in 0..<4 {
                        ctx.fill(CGRect(x: fx, y: fy + Double(row) * 9.5, width: 48, height: 6.0))
                    }
                }
                // 右上角风车农舍
                ctx.setFillColor(CGColor(gray: 0.92, alpha: 1.0))
                ctx.fill(CGRect(x: 72, y: 58, width: 42, height: 34))
                ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
                ctx.setLineWidth(2.4)
                ctx.stroke(CGRect(x: 72, y: 58, width: 42, height: 34))
            }

        case .barracks, .archeryRange, .stables, .siegeWorkshop, .blacksmith:
            return makeTexture(width: 136, height: 108) { ctx, w, h in
                ctx.setFillColor(CGColor(gray: 0.0, alpha: 0.38))
                ctx.fill(CGRect(x: 8, y: 6, width: w - 12, height: h - 12))
                // 石砌围墙庭院
                ctx.setFillColor(CGColor(red: 0.38, green: 0.35, blue: 0.31, alpha: 0.98))
                ctx.fill(CGRect(x: 6, y: 8, width: w - 12, height: h - 16))
                ctx.setStrokeColor(CGColor(red: 0.78, green: 0.66, blue: 0.38, alpha: 0.92))
                ctx.setLineWidth(2.5)
                ctx.stroke(CGRect(x: 8, y: 10, width: w - 16, height: h - 20))
                // 主营殿屋顶（左半幅）
                ctx.setFillColor(CGColor(gray: 0.94, alpha: 1.0))
                ctx.fill(CGRect(x: 14, y: 16, width: 64, height: h - 32))
                ctx.setStrokeColor(CGColor(gray: 0.20, alpha: 0.8))
                ctx.setLineWidth(2.8)
                ctx.move(to: CGPoint(x: 46, y: 16))
                ctx.addLine(to: CGPoint(x: 46, y: h - 16))
                ctx.strokePath()

                // 右半幅校场特色标识
                switch kind {
                case .barracks:
                    // 演武沙场圆环与刀盾架
                    ctx.setStrokeColor(CGColor(red: 0.92, green: 0.80, blue: 0.48, alpha: 0.9))
                    ctx.strokeEllipse(in: CGRect(x: 86, y: 32, width: 34, height: 42))
                case .archeryRange:
                    // 三座红心箭靶
                    for ty in [24.0, 52.0, 80.0] {
                        ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
                        ctx.fillEllipse(in: CGRect(x: 96, y: ty - 7, width: 14, height: 14))
                        ctx.setFillColor(CGColor(red: 0.90, green: 0.18, blue: 0.16, alpha: 1.0))
                        ctx.fillEllipse(in: CGRect(x: 100, y: ty - 3, width: 6, height: 6))
                    }
                case .stables:
                    // 木栏跑马场
                    ctx.setStrokeColor(CGColor(red: 0.72, green: 0.52, blue: 0.28, alpha: 1.0))
                    ctx.setLineWidth(3.0)
                    ctx.stroke(CGRect(x: 84, y: 20, width: 38, height: h - 40))
                case .blacksmith:
                    // 通红熔炉与铁砧
                    ctx.setFillColor(CGColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 1.0))
                    ctx.fillEllipse(in: CGRect(x: 88, y: 56, width: 26, height: 26))
                    ctx.setFillColor(CGColor(gray: 0.82, alpha: 1.0))
                    ctx.fill(CGRect(x: 92, y: 24, width: 20, height: 12))
                default:
                    // 攻城器械双巨轮组装场
                    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.70, blue: 0.38, alpha: 1.0))
                    ctx.setLineWidth(3.2)
                    ctx.strokeEllipse(in: CGRect(x: 88, y: 24, width: 26, height: 26))
                    ctx.strokeEllipse(in: CGRect(x: 88, y: 58, width: 26, height: 26))
                }
            }

        case .arrowTower:
            return makeTexture(width: 88, height: 88) { ctx, w, h in
                ctx.setFillColor(CGColor(gray: 0.0, alpha: 0.40))
                ctx.fillEllipse(in: CGRect(x: 8, y: 5, width: w - 12, height: h - 12))
                ctx.setFillColor(CGColor(gray: 0.46, alpha: 1.0))
                ctx.fill(CGRect(x: 10, y: 10, width: w - 20, height: h - 20))
                ctx.setFillColor(CGColor(gray: 0.92, alpha: 1.0))
                ctx.fill(CGRect(x: 18, y: 18, width: w - 36, height: h - 36))
                // 四周女墙垛口
                ctx.setFillColor(CGColor(gray: 0.25, alpha: 0.95))
                for off in stride(from: 14.0, through: Double(w - 22), by: 16.0) {
                    ctx.fill(CGRect(x: off, y: Double(h) - 16, width: 8, height: 6))
                    ctx.fill(CGRect(x: off, y: 10, width: 8, height: 6))
                }
            }

        case .wallSegment, .mainGate, .sideSallyGate:
            return makeTexture(width: 84, height: 240) { ctx, w, h in
                ctx.setFillColor(CGColor(gray: 0.38, alpha: 0.98))
                ctx.fill(CGRect(x: 4, y: 2, width: w - 8, height: h - 4))
                ctx.setFillColor(CGColor(gray: 0.56, alpha: 0.98))
                ctx.fill(CGRect(x: 12, y: 4, width: w - 24, height: h - 8))
                // 城墙垛口
                ctx.setFillColor(CGColor(gray: 0.24, alpha: 0.95))
                for y in stride(from: 10.0, through: Double(h - 22), by: 24.0) {
                    ctx.fill(CGRect(x: 4, y: y, width: 9, height: 12))
                    ctx.fill(CGRect(x: Double(w) - 13, y: y, width: 9, height: 12))
                }
                if kind != .wallSegment {
                    // 包铁巨木城门洞
                    ctx.setFillColor(CGColor(red: 0.36, green: 0.21, blue: 0.10, alpha: 1.0))
                    ctx.fill(CGRect(x: 8, y: h * 0.30, width: w - 16, height: h * 0.40))
                    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.72, blue: 0.38, alpha: 1.0))
                    ctx.setLineWidth(3.0)
                    ctx.stroke(CGRect(x: 8, y: h * 0.30, width: w - 16, height: h * 0.40))
                }
            }

        case .woodenCheval, .siegeLadder:
            return makeTexture(width: 56, height: 96) { ctx, w, h in
                ctx.setStrokeColor(CGColor(red: 0.75, green: 0.56, blue: 0.30, alpha: 1.0))
                ctx.setLineWidth(5.0)
                ctx.move(to: CGPoint(x: 12, y: 6))
                ctx.addLine(to: CGPoint(x: 12, y: h - 6))
                ctx.move(to: CGPoint(x: w - 12, y: 6))
                ctx.addLine(to: CGPoint(x: w - 12, y: h - 6))
                for y in stride(from: 14.0, through: Double(h - 14), by: 16.0) {
                    ctx.move(to: CGPoint(x: 8, y: y))
                    ctx.addLine(to: CGPoint(x: Double(w) - 8, y: kind == .woodenCheval ? y + 10 : y))
                }
                ctx.strokePath()
            }
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
