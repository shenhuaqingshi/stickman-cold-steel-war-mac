import AppKit
import SpriteKit

/// 主菜单全屏动态冷兵器史诗会战背景场景（两军火柴人军团对冲、战旗猎猎、篝火火星升腾）
@MainActor
public final class MenuBackdropBattleScene: SKScene {
    private struct DemoActor {
        let root: SKNode
        let body: SKSpriteNode
        let weapon: SKSpriteNode
        var x: CGFloat
        var y: CGFloat
        var speed: CGFloat
        let isLeftSide: Bool
        var phase: CGFloat
    }

    private var actors: [DemoActor] = []
    private var embers: [SKSpriteNode] = []
    private var lastTime: TimeInterval = 0
    private var configured = false

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.06, blue: 0.06, alpha: 1.0)
        guard !configured else { return }
        configured = true

        let atlas = StickmanTextureAtlas.shared
        // 远景烽火红霞光晕
        let leftGlow = SKSpriteNode(texture: atlas.softGlowHalo, color: NSColor(calibratedRed: 0.82, green: 0.22, blue: 0.12, alpha: 0.35), size: CGSize(width: 780, height: 520))
        leftGlow.colorBlendFactor = 1.0
        leftGlow.position = CGPoint(x: 340, y: 260)
        leftGlow.zPosition = 0
        addChild(leftGlow)

        let rightGlow = SKSpriteNode(texture: atlas.softGlowHalo, color: NSColor(calibratedRed: 0.88, green: 0.68, blue: 0.24, alpha: 0.25), size: CGSize(width: 760, height: 500))
        rightGlow.colorBlendFactor = 1.0
        rightGlow.position = CGPoint(x: 1080, y: 300)
        rightGlow.zPosition = 0
        addChild(rightGlow)

        // 古战场石道与松林剪影
        for i in 0..<12 {
            let tree = SKSpriteNode(texture: atlas.pineTreeCanopy, color: NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.13, alpha: 0.55), size: CGSize(width: 84, height: 84))
            tree.colorBlendFactor = 0.6
            tree.position = CGPoint(x: CGFloat(i) * 145.0 + 50.0, y: CGFloat(420 + (i % 3) * 55))
            tree.zPosition = 1
            addChild(tree)
        }

        // 生成左右两支演示交锋军团（左：赤红罗马/炎龙重甲盾枪阵；右：金狼铁骑冲阵）
        for idx in 0..<28 {
            let isLeft = idx < 15
            let root = SKNode()
            let primary = isLeft
                ? NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.18, alpha: 0.90)
                : NSColor(calibratedRed: 0.22, green: 0.58, blue: 0.86, alpha: 0.90)

            let shadow = SKSpriteNode(texture: atlas.circleFilled, color: NSColor(calibratedWhite: 0, alpha: 0.4), size: CGSize(width: 26, height: 10))
            shadow.colorBlendFactor = 1.0
            shadow.position = CGPoint(x: 0, y: -14)
            root.addChild(shadow)

            if !isLeft && idx % 2 == 0 {
                let horse = SKSpriteNode(texture: atlas.mountBody, color: NSColor(calibratedRed: 0.48, green: 0.34, blue: 0.22, alpha: 0.95), size: CGSize(width: 52, height: 30))
                horse.colorBlendFactor = 1.0
                horse.position = CGPoint(x: 0, y: -6)
                root.addChild(horse)
            }

            let cape = SKSpriteNode(texture: atlas.flowingCape, color: primary, size: CGSize(width: 18, height: 22))
            cape.colorBlendFactor = 1.0
            cape.position = CGPoint(x: -5, y: 6)
            root.addChild(cape)

            let body = SKSpriteNode(texture: atlas.armoredTorso, color: primary, size: CGSize(width: 13, height: 19))
            body.colorBlendFactor = 1.0
            body.position = CGPoint(x: 0, y: 6)
            root.addChild(body)

            let head = SKSpriteNode(texture: isLeft ? atlas.legionCrestHead : atlas.nomadHelmHead, color: NSColor(calibratedRed: 0.96, green: 0.84, blue: 0.48, alpha: 1.0), size: CGSize(width: 18, height: 18))
            head.colorBlendFactor = 1.0
            head.position = CGPoint(x: 0, y: 21)
            root.addChild(head)

            let shield = SKSpriteNode(texture: isLeft ? atlas.paviseShield : atlas.roundShield, color: primary, size: isLeft ? CGSize(width: 15, height: 22) : CGSize(width: 16, height: 16))
            shield.colorBlendFactor = 0.85
            shield.position = CGPoint(x: 6, y: 6)
            root.addChild(shield)

            let weapon = SKSpriteNode(texture: idx % 3 == 0 ? atlas.pikeShaft : atlas.saberBlade, color: .white, size: idx % 3 == 0 ? CGSize(width: 38, height: 7) : CGSize(width: 26, height: 9))
            weapon.position = CGPoint(x: 11, y: 9)
            root.addChild(weapon)

            let startX: CGFloat = isLeft ? CGFloat(120 + (idx * 42) % 480) : CGFloat(820 + (idx * 47) % 520)
            let startY: CGFloat = CGFloat(110 + (idx * 37) % 240)
            root.position = CGPoint(x: startX, y: startY)
            root.xScale = isLeft ? 1.15 : -1.15
            root.yScale = 1.15
            root.zPosition = 500 - startY
            addChild(root)

            actors.append(
                DemoActor(
                    root: root,
                    body: body,
                    weapon: weapon,
                    x: startX,
                    y: startY,
                    speed: CGFloat.random(in: 24...46),
                    isLeftSide: isLeft,
                    phase: CGFloat(idx) * 0.7
                )
            )
        }

        // 升腾战火余烬粒子
        for i in 0..<36 {
            let e = SKSpriteNode(texture: atlas.circleFilled, color: NSColor(calibratedRed: 1.0, green: CGFloat.random(in: 0.45...0.82), blue: 0.18, alpha: 0.65), size: CGSize(width: 4.5, height: 4.5))
            e.colorBlendFactor = 1.0
            e.position = CGPoint(x: CGFloat(i * 43 % 1440), y: CGFloat(i * 29 % 860))
            e.zPosition = 600
            addChild(e)
            embers.append(e)
        }
    }

    public override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 {
            lastTime = currentTime
            return
        }
        let dt = CGFloat(min(0.05, max(0.0, currentTime - lastTime)))
        lastTime = currentTime
        let w = max(1200, size.width)
        let h = max(720, size.height)
        let clashCenter = w * 0.52

        for i in 0..<actors.count {
            actors[i].phase += dt * 6.5
            let dir: CGFloat = actors[i].isLeftSide ? 1.0 : -1.0
            let distToClash = abs(actors[i].x - clashCenter)
            if distToClash > 55 {
                actors[i].x += dir * actors[i].speed * dt
                actors[i].weapon.zRotation = sin(actors[i].phase) * 0.18
            } else {
                // 阵前短兵相接挥砍摆动
                actors[i].weapon.zRotation = sin(actors[i].phase * 1.8) * 0.65
                actors[i].x += sin(actors[i].phase * 0.9) * 8.0 * dt
            }
            if actors[i].isLeftSide && actors[i].x > w - 80 { actors[i].x = 60 }
            if !actors[i].isLeftSide && actors[i].x < 80 { actors[i].x = w - 60 }
            actors[i].root.position = CGPoint(x: actors[i].x, y: actors[i].y + abs(sin(actors[i].phase)) * 2.5)
        }

        for e in embers {
            e.position.y += 28.0 * dt
            e.position.x += 12.0 * dt
            if e.position.y > h + 10 { e.position.y = -10 }
            if e.position.x > w + 10 { e.position.x = -10 }
        }
    }
}
