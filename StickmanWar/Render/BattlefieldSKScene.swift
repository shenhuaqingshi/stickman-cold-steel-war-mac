import AppKit
import SpriteKit

/// 推送给战场底部战术面板的分队轻量状态摘要（4Hz 节流）
public struct SquadUiBrief: Sendable, Equatable, Identifiable {
    public let id: Int
    public let corpsRole: ArmyCorpsRole
    public let unitType: UnitTypeId
    public let unitName: String
    public let aliveCount: Int
    public let initialCount: Int
    public let morale: Double
    public let isRouting: Bool
    public let formation: FormationType
    public let order: TacticalOrder
    public let encirclement: EncirclementState
    public let veterancyStars: Int
    public let totalKills: Int
}

/// 推送给右上/右下交互式雷达小地图的轻量光点
public struct MinimapRadarDot: Sendable, Equatable, Identifiable {
    public let id: Int
    public let normX: Double
    public let normY: Double
    public let isPlayer: Bool
    public let isBuilding: Bool
    public let isResource: Bool
}

/// 推送给外层 `BattlefieldView` 的组合实时帧摘要（4Hz 节流，严防高频刷新 SwiftUI 视图树）
public struct BattlefieldUiSyncPacket: Sendable, Equatable {
    public let hud: BattleHudSnapshot
    public let playerSquads: [SquadUiBrief]
    public let selectedSquadIds: [Int]
    public let trainingQueueCount: Int
    public let trainingQueueItems: [TrainingQueueItem]
    public let aiDoctrine: BattlefieldAiDoctrine
    public let aiSiegePhase: SiegeTacticalPhase?
    public let heroBreakthroughCd: Double
    public let heroBulwarkCd: Double
    public let heroWarCryCd: Double
    public let heroMedicalRemainingSec: Double
    public let heroBowChargeRatio: Double
    public let heroKills: Int
    public let bloodMoonFervorRemaining: Double
    public let simulationSpeed: Double
    public let pendingBuildKind: SiegeStructureKind?
    public let minimapDots: [MinimapRadarDot]
    public let cameraNormCenterX: Double
    public let cameraNormCenterY: Double
    public let cameraNormWidth: Double
    public let cameraNormHeight: Double
}

// MARK: - 预分配重装军团火柴人单兵骨骼关节节点（1.45x 英雄比例 + 盔甲披风 + 脚底选中环 + 负伤血条）

@MainActor
private final class PooledSoldierNode {
    let root = SKNode()
    let selectFootRing: SKSpriteNode
    let shadow: SKSpriteNode
    let mountNode: SKSpriteNode
    let siegeNode: SKSpriteNode
    let capeNode: SKSpriteNode
    let legLeft: SKSpriteNode
    let legRight: SKSpriteNode
    let torso: SKSpriteNode
    let head: SKSpriteNode
    let armMain: SKSpriteNode
    let weaponNode: SKSpriteNode
    let shieldNode: SKSpriteNode
    let bannerPole: SKSpriteNode
    let bannerCloth: SKSpriteNode
    let hpBarBg: SKSpriteNode
    let hpBarFill: SKSpriteNode
    let stateDot: SKSpriteNode

    var cachedUnitType: UnitTypeId?
    var cachedFaction: FactionId?

    init(atlas: StickmanTextureAtlas) {
        selectFootRing = SKSpriteNode(texture: atlas.selectionRingDecal, color: .white, size: CGSize(width: 28, height: 14))
        selectFootRing.position = CGPoint(x: 0, y: -11)
        selectFootRing.zPosition = -0.1
        selectFootRing.isHidden = true

        shadow = SKSpriteNode(texture: atlas.circleFilled, color: NSColor(calibratedWhite: 0.0, alpha: 0.38), size: CGSize(width: 22, height: 9))
        shadow.colorBlendFactor = 1.0
        shadow.position = CGPoint(x: 0, y: -11)
        shadow.zPosition = 0.0

        mountNode = SKSpriteNode(texture: atlas.mountBody, color: .brown, size: CGSize(width: 44, height: 25))
        mountNode.colorBlendFactor = 1.0
        mountNode.position = CGPoint(x: 0, y: -5)
        mountNode.zPosition = 0.1
        mountNode.isHidden = true

        siegeNode = SKSpriteNode(texture: atlas.siegeChassis, color: .brown, size: CGSize(width: 56, height: 38))
        siegeNode.colorBlendFactor = 1.0
        siegeNode.position = CGPoint(x: 0, y: 2)
        siegeNode.zPosition = 0.15
        siegeNode.isHidden = true

        capeNode = SKSpriteNode(texture: atlas.flowingCape, color: .red, size: CGSize(width: 14, height: 18))
        capeNode.colorBlendFactor = 1.0
        capeNode.position = CGPoint(x: -4.5, y: 6.5)
        capeNode.zPosition = 0.18
        capeNode.isHidden = true

        legLeft = SKSpriteNode(texture: atlas.limbSegment, color: .white, size: CGSize(width: 4.6, height: 12.5))
        legLeft.colorBlendFactor = 1.0
        legLeft.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        legLeft.position = CGPoint(x: -2.8, y: 0.0)
        legLeft.zPosition = 0.22

        legRight = SKSpriteNode(texture: atlas.limbSegment, color: .white, size: CGSize(width: 4.6, height: 12.5))
        legRight.colorBlendFactor = 1.0
        legRight.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        legRight.position = CGPoint(x: 2.8, y: 0.0)
        legRight.zPosition = 0.22

        torso = SKSpriteNode(texture: atlas.armoredTorso, color: .red, size: CGSize(width: 11.5, height: 16.5))
        torso.colorBlendFactor = 1.0
        torso.position = CGPoint(x: 0, y: 7.0)
        torso.zPosition = 0.30

        head = SKSpriteNode(texture: atlas.legionCrestHead, color: .white, size: CGSize(width: 15.5, height: 15.5))
        head.colorBlendFactor = 1.0
        head.position = CGPoint(x: 0, y: 19.5)
        head.zPosition = 0.42

        armMain = SKSpriteNode(texture: atlas.limbSegment, color: .white, size: CGSize(width: 11.0, height: 4.2))
        armMain.colorBlendFactor = 1.0
        armMain.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        armMain.position = CGPoint(x: 1.5, y: 10.5)
        armMain.zPosition = 0.46

        weaponNode = SKSpriteNode(texture: atlas.saberBlade, color: NSColor(calibratedWhite: 0.95, alpha: 1.0), size: CGSize(width: 25, height: 8.5))
        weaponNode.colorBlendFactor = 1.0
        weaponNode.anchorPoint = CGPoint(x: 0.15, y: 0.5)
        weaponNode.position = CGPoint(x: 9.0, y: 0.0)
        weaponNode.zPosition = 0.50

        shieldNode = SKSpriteNode(texture: atlas.paviseShield, color: .gray, size: CGSize(width: 13.5, height: 19.5))
        shieldNode.colorBlendFactor = 1.0
        shieldNode.position = CGPoint(x: 6.0, y: 7.5)
        shieldNode.zPosition = 0.56
        shieldNode.isHidden = true

        bannerPole = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 0.90, green: 0.76, blue: 0.40, alpha: 1.0), size: CGSize(width: 2.6, height: 36.0))
        bannerPole.colorBlendFactor = 1.0
        bannerPole.position = CGPoint(x: -5.0, y: 18.0)
        bannerPole.zPosition = 0.60
        bannerPole.isHidden = true

        bannerCloth = SKSpriteNode(texture: atlas.bannerFlag, color: .red, size: CGSize(width: 22, height: 15))
        bannerCloth.colorBlendFactor = 1.0
        bannerCloth.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        bannerCloth.position = CGPoint(x: -4.0, y: 31.0)
        bannerCloth.zPosition = 0.62
        bannerCloth.isHidden = true

        hpBarBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.06, alpha: 0.85), size: CGSize(width: 18, height: 3.0))
        hpBarBg.colorBlendFactor = 1.0
        hpBarBg.position = CGPoint(x: 0, y: 28.5)
        hpBarBg.zPosition = 0.66
        hpBarBg.isHidden = true

        hpBarFill = SKSpriteNode(texture: atlas.whitePixel, color: .systemGreen, size: CGSize(width: 16.5, height: 2.0))
        hpBarFill.colorBlendFactor = 1.0
        hpBarFill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        hpBarFill.position = CGPoint(x: -8.25, y: 28.5)
        hpBarFill.zPosition = 0.67
        hpBarFill.isHidden = true

        stateDot = SKSpriteNode(texture: atlas.circleFilled, color: .white, size: CGSize(width: 6.5, height: 6.5))
        stateDot.colorBlendFactor = 1.0
        stateDot.position = CGPoint(x: 0, y: 33.0)
        stateDot.zPosition = 0.68
        stateDot.isHidden = true

        armMain.addChild(weaponNode)
        root.addChild(selectFootRing)
        root.addChild(shadow)
        root.addChild(mountNode)
        root.addChild(siegeNode)
        root.addChild(capeNode)
        root.addChild(legLeft)
        root.addChild(legRight)
        root.addChild(torso)
        root.addChild(head)
        root.addChild(armMain)
        root.addChild(shieldNode)
        root.addChild(bannerPole)
        root.addChild(bannerCloth)
        root.addChild(hpBarBg)
        root.addChild(hpBarFill)
        root.addChild(stateDot)
        root.isHidden = true
    }
}

// MARK: - 预分配主帅英雄专属骨骼节点

@MainActor
private final class PooledHeroNode {
    let root = SKNode()
    let glowHalo: SKSpriteNode
    let auraRing: SKSpriteNode
    let cape: SKSpriteNode
    let torso: SKSpriteNode
    let crownHead: SKSpriteNode
    let weaponArm: SKSpriteNode
    let weaponSprite: SKSpriteNode
    let shieldSprite: SKSpriteNode
    let hpBg: SKSpriteNode
    let hpFill: SKSpriteNode
    let bowChargeBar: SKSpriteNode
    let titleLabel: SKLabelNode

    init(atlas: StickmanTextureAtlas, primaryColor: NSColor, accentColor: NSColor, title: String) {
        glowHalo = SKSpriteNode(texture: atlas.softGlowHalo, color: accentColor.withAlphaComponent(0.36), size: CGSize(width: 78, height: 78))
        glowHalo.colorBlendFactor = 1.0
        glowHalo.position = CGPoint(x: 0, y: 4)

        auraRing = SKSpriteNode(texture: atlas.circleRing, color: accentColor.withAlphaComponent(0.72), size: CGSize(width: 48, height: 48))
        auraRing.colorBlendFactor = 1.0
        auraRing.position = CGPoint(x: 0, y: -4)

        cape = SKSpriteNode(texture: atlas.flowingCape, color: primaryColor, size: CGSize(width: 24, height: 28))
        cape.colorBlendFactor = 1.0
        cape.anchorPoint = CGPoint(x: 0.85, y: 0.5)
        cape.position = CGPoint(x: -3, y: 9)

        torso = SKSpriteNode(texture: atlas.armoredTorso, color: primaryColor, size: CGSize(width: 16.0, height: 22.0))
        torso.colorBlendFactor = 1.0
        torso.position = CGPoint(x: 0, y: 9)

        crownHead = SKSpriteNode(texture: atlas.heroCrownHead, color: accentColor, size: CGSize(width: 25, height: 25))
        crownHead.colorBlendFactor = 1.0
        crownHead.position = CGPoint(x: 0, y: 26)

        weaponArm = SKSpriteNode(texture: atlas.limbSegment, color: .white, size: CGSize(width: 13, height: 4.5))
        weaponArm.colorBlendFactor = 1.0
        weaponArm.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        weaponArm.position = CGPoint(x: 2, y: 13)

        weaponSprite = SKSpriteNode(texture: atlas.saberBlade, color: accentColor, size: CGSize(width: 34, height: 11))
        weaponSprite.colorBlendFactor = 1.0
        weaponSprite.anchorPoint = CGPoint(x: 0.12, y: 0.5)
        weaponSprite.position = CGPoint(x: 10, y: 0)
        weaponArm.addChild(weaponSprite)

        shieldSprite = SKSpriteNode(texture: atlas.roundShield, color: accentColor, size: CGSize(width: 20, height: 20))
        shieldSprite.colorBlendFactor = 1.0
        shieldSprite.position = CGPoint(x: 9, y: 10)

        hpBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.08, alpha: 0.88), size: CGSize(width: 46, height: 5.5))
        hpBg.colorBlendFactor = 1.0
        hpBg.position = CGPoint(x: 0, y: 41)

        hpFill = SKSpriteNode(texture: atlas.whitePixel, color: NSColor.systemGreen, size: CGSize(width: 44, height: 3.8))
        hpFill.colorBlendFactor = 1.0
        hpFill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        hpFill.position = CGPoint(x: -22, y: 41)

        bowChargeBar = SKSpriteNode(texture: atlas.whitePixel, color: NSColor.systemYellow, size: CGSize(width: 0, height: 3.0))
        bowChargeBar.colorBlendFactor = 1.0
        bowChargeBar.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        bowChargeBar.position = CGPoint(x: -22, y: 36)
        bowChargeBar.isHidden = true

        titleLabel = SKLabelNode(fontNamed: "PingFangSC-Heavy")
        titleLabel.text = title
        titleLabel.fontSize = 12
        titleLabel.fontColor = accentColor
        titleLabel.position = CGPoint(x: 0, y: 48)

        root.addChild(glowHalo)
        root.addChild(auraRing)
        root.addChild(cape)
        root.addChild(torso)
        root.addChild(crownHead)
        root.addChild(weaponArm)
        root.addChild(shieldSprite)
        root.addChild(hpBg)
        root.addChild(hpFill)
        root.addChild(bowChargeBar)
        root.addChild(titleLabel)
    }
}

// MARK: - 预分配帝国建筑（含脚手架施工进度与篝火光晕）与军团鹰旗标牌节点

@MainActor
private final class PooledStructureNode {
    let root = SKNode()
    let brazierGlow: SKSpriteNode
    let body: SKSpriteNode
    let scaffoldOverlay: SKSpriteNode
    let hpBg: SKSpriteNode
    let hpFill: SKSpriteNode
    let label: SKLabelNode
    let maxBarWidth: CGFloat
    let baseTitle: String
    var wasRenderedDestroyed: Bool = false
    var lastProgressBucket: Int = -1

    init(atlas: StickmanTextureAtlas, kind: SiegeStructureKind, width: CGFloat, height: CGFloat, color: NSColor, title: String) {
        baseTitle = title
        maxBarWidth = max(48.0, min(130.0, width))

        brazierGlow = SKSpriteNode(
            texture: atlas.softGlowHalo,
            color: NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.24, alpha: 0.30),
            size: CGSize(width: width * 1.45, height: height * 1.45)
        )
        brazierGlow.colorBlendFactor = 1.0
        brazierGlow.isHidden = (kind == .wallSegment || kind == .woodenCheval || kind == .siegeLadder)

        body = SKSpriteNode(texture: atlas.buildingTexture(for: kind), color: color, size: CGSize(width: width, height: height))
        // 对需要保留原彩细节的农庄/城墙采用适度混色，对帅帐与兵营屋顶染色鲜明
        body.colorBlendFactor = (kind == .imperialFarm || kind == .woodenCheval || kind == .siegeLadder) ? 0.15 : 0.58

        scaffoldOverlay = SKSpriteNode(
            texture: atlas.woodenChevalTextureFallback(atlas),
            color: NSColor(calibratedRed: 0.85, green: 0.68, blue: 0.36, alpha: 0.72),
            size: CGSize(width: width * 0.92, height: height * 0.92)
        )
        scaffoldOverlay.colorBlendFactor = 0.65
        scaffoldOverlay.isHidden = true

        hpBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.06, alpha: 0.88), size: CGSize(width: maxBarWidth + 2, height: 5.5))
        hpBg.colorBlendFactor = 1.0
        hpBg.position = CGPoint(x: 0, y: height * 0.5 + 11)

        hpFill = SKSpriteNode(texture: atlas.whitePixel, color: .systemGreen, size: CGSize(width: maxBarWidth, height: 3.8))
        hpFill.colorBlendFactor = 1.0
        hpFill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        hpFill.position = CGPoint(x: -maxBarWidth * 0.5, y: height * 0.5 + 11)

        label = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        label.text = title
        label.fontSize = 12.5
        label.fontColor = NSColor(calibratedRed: 0.98, green: 0.93, blue: 0.80, alpha: 1.0)
        label.position = CGPoint(x: 0, y: height * 0.5 + 20)

        root.addChild(brazierGlow)
        root.addChild(body)
        root.addChild(scaffoldOverlay)
        root.addChild(hpBg)
        root.addChild(hpFill)
        root.addChild(label)
    }
}

private extension StickmanTextureAtlas {
    func woodenChevalTextureFallback(_ atlas: StickmanTextureAtlas) -> SKTexture {
        atlas.buildingTexture(for: .woodenCheval)
    }
}

@MainActor
private final class PooledSquadMarkerNode {
    let root = SKNode()
    let selectRing: SKSpriteNode
    let moraleBg: SKSpriteNode
    let moraleFill: SKSpriteNode
    let badgeBg: SKSpriteNode
    let badgeLabel: SKLabelNode
    let orderLine: SKSpriteNode
    var cachedBadgeText: String = ""

    init(atlas: StickmanTextureAtlas) {
        selectRing = SKSpriteNode(texture: atlas.selectionRingDecal, color: NSColor.systemYellow.withAlphaComponent(0.82), size: CGSize(width: 108, height: 62))
        selectRing.colorBlendFactor = 0.35
        selectRing.isHidden = true

        moraleBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.06, alpha: 0.88), size: CGSize(width: 54, height: 5.0))
        moraleBg.colorBlendFactor = 1.0
        moraleBg.position = CGPoint(x: 0, y: 40)

        moraleFill = SKSpriteNode(texture: atlas.whitePixel, color: .systemCyan, size: CGSize(width: 52, height: 3.4))
        moraleFill.colorBlendFactor = 1.0
        moraleFill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        moraleFill.position = CGPoint(x: -26, y: 40)

        badgeBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.07, alpha: 0.78), size: CGSize(width: 126, height: 18))
        badgeBg.colorBlendFactor = 1.0
        badgeBg.position = CGPoint(x: 0, y: 52)

        badgeLabel = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        badgeLabel.fontSize = 11.5
        badgeLabel.fontColor = .white
        badgeLabel.verticalAlignmentMode = .center
        badgeLabel.position = CGPoint(x: 0, y: 52)

        orderLine = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.36, alpha: 0.52), size: CGSize(width: 2, height: 2.6))
        orderLine.colorBlendFactor = 1.0
        orderLine.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        orderLine.isHidden = true

        root.addChild(orderLine)
        root.addChild(selectRing)
        root.addChild(moraleBg)
        root.addChild(moraleFill)
        root.addChild(badgeBg)
        root.addChild(badgeLabel)
        root.isHidden = true
    }
}

// MARK: - SpriteKit 真实冷兵器大战场渲染与键鼠操控宿主

@MainActor
public final class BattlefieldSKScene: SKScene {
    public let worldWidth: Double
    public let worldHeight: Double

    /// 确定性战斗物理、RTS 营建、四时代演进与 AI 核心引擎
    public private(set) var engine: BattleSimulationEngine

    /// 当前 RTS 选中的我军分队 ID 列表
    public private(set) var selectedSquadIds: [Int] = []
    /// 6 支快捷编组（Ctrl+1~6 绑定，F1~F6 快速选定，双击居中镜头）
    private var controlGroups: [Int: [Int]] = [:]
    private var lastGroupKeyNumber: Int = -1
    private var lastGroupKeyPressTime: TimeInterval = 0.0

    // 分层渲染树
    private let terrainLayer = SKNode()
    private let corpseDecalLayer = SKNode()
    private let structureLayer = SKNode()
    private let squadOverlayLayer = SKNode()
    private let unitBatchLayer = SKNode()
    private let forestCanopyLayer = SKNode()
    private let projectileLayer = SKNode()
    private let effectLayer = SKNode()
    private let uiOverlayLayer = SKNode()
    private let worldCamera = SKCameraNode()

    // 预分配对象池
    private var soldierPoolNodes: [PooledSoldierNode] = []
    private var projectilePoolNodes: [SKSpriteNode] = []
    private var corpsePoolNodes: [SKSpriteNode] = []
    private var particlePoolNodes: [SKSpriteNode] = []
    private var damageLabelPool: [SKLabelNode] = []
    private var structurePoolNodes: [PooledStructureNode] = []
    private var resourceAmountLabels: [SKLabelNode] = []
    private var trapPoolNodes: [SKSpriteNode] = []
    private var squadMarkerNodes: [PooledSquadMarkerNode] = []
    private var waterRippleNodes: [SKSpriteNode] = []
    private var weatherParticleNodes: [SKSpriteNode] = []
    private var playerHeroNode: PooledHeroNode?
    private var enemyHeroNode: PooledHeroNode?

    /// 框选、右键拉阵线预览、营建蓝图虚影与英雄准星节点
    private let marqueeFillNode = SKSpriteNode(
        color: NSColor(calibratedRed: 0.96, green: 0.82, blue: 0.34, alpha: 0.20),
        size: .zero
    )
    private let marqueeBorderTop = SKSpriteNode(color: NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.42, alpha: 0.85), size: .zero)
    private let deploymentLineNode = SKSpriteNode(
        color: NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.28, alpha: 0.88),
        size: .zero
    )
    private var buildGhostNode: SKSpriteNode?
    private let orderMarkerNode = SKLabelNode(fontNamed: "PingFangSC-Heavy")
    private var orderMarkerFadeTimer: Double = 0.0
    private var heroAimReticleNode: SKSpriteNode?

    /// 帧步进计时器与键鼠输入状态
    private var isSceneConfigured = false
    private var lastUpdateTimestamp: TimeInterval = 0.0
    private var fixedTickAccumulator: Double = 0.0
    private var uiPushAccumulator: Double = 0.0
    private var outcomeNotified = false
    private var lastObservedHeroVitalState: HeroVitalState = .healthyActive
    private var lastRenderedParticleCursorSnapshot: [Bool] = []
    private var lastResourceIntAmounts: [Int] = []
    private var enemySquadVisibleFlags: [Bool] = Array(repeating: false, count: 64)
    private var damageLabelCursor: Int = 0

    private var dragStartScenePoint: CGPoint?
    private var rightDragStartScenePoint: CGPoint?
    private var isOptionPanningDrag = false
    private var pressedKeyCodes = Set<UInt16>()
    private var heroMouseLeftHeld = false
    private var heroMouseRightHeld = false
    private var heroAimLogicPoint: (x: Double, y: Double) = (0.0, 0.0)
    private var mouseHoverScenePoint: CGPoint = .zero
    private var installedTrackingArea: NSTrackingArea?

    /// 当前待选址落盘的 RTS 建筑种类（nil 表示正常选兵指挥模式）
    public private(set) var pendingBuildKind: SiegeStructureKind? = nil
    /// 模拟倍速（支持 0.5x 战术慢镜 / 1.0x 标准 / 1.5x / 2.0x 疾行）
    public var simulationSpeedMultiplier: Double = 1.0 {
        didSet { pushUiSyncNow() }
    }

    // 缓存双方势力颜色
    private var factionPrimaryColors: [FactionId: NSColor] = [:]
    private var factionAccentColors: [FactionId: NSColor] = [:]

    // 用户偏好设置（实时生效）
    public var preferredFps: Int = GameConstants.renderTargetFps {
        didSet { view?.preferredFramesPerSecond = preferredFps }
    }
    public var enableFarLod: Bool = true
    public var invertScrollZoom: Bool = false
    public var keyboardPanSpeed: Double = 560.0
    public var showDamageNumbers: Bool = true
    public var enableEdgeCursorPan: Bool = false

    public var controlMode: BattleControlMode {
        engine.controlMode
    }

    public var onInteractionFeedback: (@MainActor (String) -> Void)?
    public var onUiPacketSynced: (@MainActor (BattlefieldUiSyncPacket) -> Void)?
    public var onRequestToggleEscapeMenu: (@MainActor () -> Void)?
    public var onBattleConcluded: (@MainActor (PostBattleSettlementSummary) -> Void)?

    // MARK: - 初始化

    public convenience init(isSiegeScenario: Bool = false) {
        let ctx = RouteLaunchContext(
            entryMode: .skirmish,
            playerFaction: .yanlong,
            enemyFaction: .canglang,
            scenarioType: isSiegeScenario ? .siegeAssault : .fieldPitched,
            terrain: isSiegeScenario ? .fortWall : .plain,
            weather: .clearDay
        )
        self.init(context: ctx, deployment: BattleDeploymentConfig())
    }

    public init(context: RouteLaunchContext, deployment: BattleDeploymentConfig) {
        let sim = BattleSimulationEngine(context: context, deployment: deployment)
        self.engine = sim
        self.worldWidth = sim.worldWidth
        self.worldHeight = sim.worldHeight
        super.init(size: CGSize(width: 1440, height: 860))
        self.scaleMode = .resizeFill
        self.backgroundColor = Self.groundBaseColor(for: context.terrain, weather: context.weather)

        for cfg in FactionConfig.allFactions {
            factionPrimaryColors[cfg.id] = StickmanTextureAtlas.nsColor(hex: cfg.primaryColorHex)
            factionAccentColors[cfg.id] = StickmanTextureAtlas.nsColor(hex: cfg.accentColorHex)
        }

        setupInitialSelectionAndControlGroups()
        lastObservedHeroVitalState = sim.playerHero.vitalState
        lastResourceIntAmounts = Array(repeating: -1, count: sim.resourceNodes.count)
        heroAimLogicPoint = (sim.playerHero.x + 120.0, sim.playerHero.y)
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool { true }

    // MARK: - 坐标系双向确定性映射

    public func scenePoint(fromLogicX logicX: Double, logicY: Double) -> CGPoint {
        CGPoint(x: logicX, y: worldHeight - logicY)
    }

    public func logicCoordinates(fromScenePoint point: CGPoint) -> (x: Double, y: Double) {
        (Double(point.x), worldHeight - Double(point.y))
    }

    public func currentVisibleSceneRect(margin: CGFloat = CGFloat(GameConstants.viewportCullMargin)) -> CGRect {
        let effectiveScale = worldCamera.xScale
        let halfW = (size.width * 0.5) * effectiveScale + margin
        let halfH = (size.height * 0.5) * effectiveScale + margin
        return CGRect(
            x: worldCamera.position.x - halfW,
            y: worldCamera.position.y - halfH,
            width: halfW * 2.0,
            height: halfH * 2.0
        )
    }

    // MARK: - 场景挂载与高精地貌/对象池一次性预分配

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = preferredFps
        installMouseTracking(on: view)

        guard !isSceneConfigured else {
            focusResponder()
            pushUiSyncNow()
            return
        }
        isSceneConfigured = true

        terrainLayer.zPosition = 0
        corpseDecalLayer.zPosition = 8
        structureLayer.zPosition = 14
        squadOverlayLayer.zPosition = 18
        unitBatchLayer.zPosition = 24
        forestCanopyLayer.zPosition = 30
        projectileLayer.zPosition = 36
        effectLayer.zPosition = 44
        uiOverlayLayer.zPosition = 54

        addChild(terrainLayer)
        addChild(corpseDecalLayer)
        addChild(structureLayer)
        addChild(squadOverlayLayer)
        addChild(unitBatchLayer)
        addChild(forestCanopyLayer)
        addChild(projectileLayer)
        addChild(effectLayer)
        addChild(uiOverlayLayer)

        let atlas = StickmanTextureAtlas.shared
        buildBattlefieldTerrainAndResourceVisuals(atlas: atlas)
        buildPreallocatedEntityPools(atlas: atlas)

        marqueeFillNode.isHidden = true
        marqueeFillNode.zPosition = 58
        uiOverlayLayer.addChild(marqueeFillNode)
        marqueeBorderTop.isHidden = true
        marqueeBorderTop.zPosition = 59
        uiOverlayLayer.addChild(marqueeBorderTop)

        deploymentLineNode.isHidden = true
        deploymentLineNode.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        deploymentLineNode.zPosition = 60
        uiOverlayLayer.addChild(deploymentLineNode)

        let ghost = SKSpriteNode(texture: atlas.buildingTexture(for: .barracks), color: .systemGreen, size: CGSize(width: 118, height: 94))
        ghost.alpha = 0.58
        ghost.zPosition = 56
        ghost.isHidden = true
        uiOverlayLayer.addChild(ghost)
        buildGhostNode = ghost

        orderMarkerNode.text = "⊕ 进军目标"
        orderMarkerNode.fontSize = 18
        orderMarkerNode.fontColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.32, alpha: 0.96)
        orderMarkerNode.isHidden = true
        orderMarkerNode.zPosition = 61
        uiOverlayLayer.addChild(orderMarkerNode)

        let reticle = SKSpriteNode(texture: atlas.circleRing, color: NSColor.systemYellow.withAlphaComponent(0.88), size: CGSize(width: 28, height: 28))
        reticle.colorBlendFactor = 1.0
        reticle.zPosition = 62
        reticle.isHidden = true
        uiOverlayLayer.addChild(reticle)
        heroAimReticleNode = reticle

        let pCamp = engine.baseCampCoordinates(for: .player)
        worldCamera.position = scenePoint(fromLogicX: min(worldWidth * 0.5, pCamp.x + 860.0), logicY: worldHeight * 0.5)
        worldCamera.setScale(1.06)
        addChild(worldCamera)
        self.camera = worldCamera

        BattleAudioEngine.shared.play(.warHorn, volumeScale: 0.72)
        syncAllVisualNodesWithEngine()
        pushUiSyncNow()
        focusResponder()
    }

    public func focusResponder() {
        Task { @MainActor [weak self] in
            guard let self, let view = self.view else { return }
            view.window?.acceptsMouseMovedEvents = true
            view.window?.makeFirstResponder(self)
        }
    }

    private func installMouseTracking(on view: SKView) {
        if let old = installedTrackingArea {
            view.removeTrackingArea(old)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: view,
            userInfo: nil
        )
        view.addTrackingArea(area)
        installedTrackingArea = area
        view.window?.acceptsMouseMovedEvents = true
    }

    // MARK: - 公开指挥、RTS 营建、时代演进、铁匠锻造与小地图跳转 API

    private func setupInitialSelectionAndControlGroups() {
        var allCombatIds: [Int] = []
        let roleOrder: [ArmyCorpsRole] = [
            .vanguardCenter, .leftWing, .rightWing, .rearReserve, .siegeBattery, .supplyEscort
        ]
        for (idx, role) in roleOrder.enumerated() {
            let matching = engine.squads.filter { $0.side == .player && $0.corpsRole == role }.map(\.id)
            controlGroups[idx + 1] = matching
            if role != .supplyEscort {
                allCombatIds.append(contentsOf: matching)
            }
        }
        if let vanguard = controlGroups[1], !vanguard.isEmpty {
            selectedSquadIds = vanguard
        } else {
            selectedSquadIds = allCombatIds
        }
    }

    public func jumpCameraToNormalized(normX: Double, normY: Double) {
        let lx = max(0.0, min(worldWidth, normX * worldWidth))
        let ly = max(0.0, min(worldHeight, normY * worldHeight))
        worldCamera.position = scenePoint(fromLogicX: lx, logicY: ly)
        clampCameraPosition()
        pushUiSyncNow()
    }

    public func focusIdleOrNearestSapper() {
        if let pt = engine.findSapperForFocus(side: .player) {
            worldCamera.position = scenePoint(fromLogicX: pt.x, logicY: pt.y)
            clampCameraPosition()
            onInteractionFeedback?(pt.isIdle ? "🔨 已聚焦空闲民夫：可指派营建兵营/农庄/箭塔，或右键矿脉采集！" : "⛏ 已聚焦前线劳作民夫")
            BattleAudioEngine.shared.play(.uiClick)
            pushUiSyncNow()
        } else {
            onInteractionFeedback?("当前场上暂无存活民夫，可在底部招募【辎重工兵】")
        }
    }

    /// 启动建筑鼠标选址预览（若 `quickAutoPlace == true` 如按住 Shift 点击，则直接在主城周边空地一键落盘！）
    public func beginOrAutoConstructBuilding(_ kind: SiegeStructureKind, quickAutoPlace: Bool = false) {
        guard let cost = kind.buildCost else { return }
        if engine.playerState.currentAge < kind.requiredAge {
            onInteractionFeedback?("🔒 营建【\(kind.displayName)】需先在顶部演进至【\(kind.requiredAge.displayName)】！")
            return
        }
        if engine.playerState.gold < cost.gold || engine.playerState.wood < cost.wood {
            onInteractionFeedback?("资源不足：营建【\(kind.displayName)】需 金 \(cost.gold) / 木 \(cost.wood)")
            return
        }

        if quickAutoPlace {
            if let slot = engine.findAutoBuildLocation(side: .player, kind: kind),
               engine.constructBuilding(side: .player, kind: kind, atX: slot.x, atY: slot.y) {
                pendingBuildKind = nil
                buildGhostNode?.isHidden = true
                syncDynamicStructurePool()
                onInteractionFeedback?("🏗 已在本阵规划营建【\(kind.displayName)】，民夫正赶赴工地夯土筑城！")
                drainAndPlayAudioCues()
                pushUiSyncNow()
            } else {
                onInteractionFeedback?("本阵周边暂无合适空地，请点击按钮后在战场地面手动左键选址")
            }
            return
        }

        if pendingBuildKind == kind {
            cancelPendingBuildPlacement()
            return
        }
        pendingBuildKind = kind
        if let ghost = buildGhostNode {
            let fp = kind.defaultFootprint
            ghost.texture = StickmanTextureAtlas.shared.buildingTexture(for: kind)
            ghost.size = CGSize(width: fp.width, height: fp.height)
            ghost.isHidden = false
        }
        onInteractionFeedback?("📐 营建选址中：【\(kind.displayName)】—— 在己方半场绿框处【左键落盘】，【右键/Esc】取消（Shift+点击按钮可自动选址）")
        BattleAudioEngine.shared.play(.uiClick)
        pushUiSyncNow()
    }

    public func cancelPendingBuildPlacement() {
        pendingBuildKind = nil
        buildGhostNode?.isHidden = true
        pushUiSyncNow()
    }

    public func triggerAgeAdvancement() {
        if engine.startAgeAdvancement(side: .player) {
            let targetName = engine.playerState.advancingToAge?.displayName ?? "新时代"
            onInteractionFeedback?("🏛 主城号角吹响：正在演进至【\(targetName)】！")
            drainAndPlayAudioCues()
            pushUiSyncNow()
        } else if engine.playerState.advancingToAge != nil {
            onInteractionFeedback?("主城正在演进时代中，请稍候")
        } else if let next = engine.playerState.currentAge.nextAge {
            let c = next.advanceCost
            onInteractionFeedback?("演进至【\(next.displayName)】资源不足（需 金\(c.gold) / 木\(c.wood) / 粮\(c.grain)）")
        } else {
            onInteractionFeedback?("已达最高【传世霸业时代 IV】！")
        }
    }

    public func triggerBlacksmithUpgrade(_ track: BlacksmithUpgradeTrack) {
        let hasSmith = engine.structures.contains { !$0.isDestroyed && !$0.isUnderConstruction && $0.side == .player && $0.kind == .blacksmith }
        guard hasSmith else {
            onInteractionFeedback?("⚒ 请先在左下角营建一座【军械铁匠铺】，完工后即可锻造全军锋刃、重甲与羽箭！")
            return
        }
        if engine.upgradeBlacksmithTrack(side: .player, track: track) {
            let lvl: Int = {
                switch track {
                case .meleeForging: return engine.playerState.meleeForgeLevel
                case .armorTempering: return engine.playerState.armorTemperLevel
                case .fletchingcraft: return engine.playerState.fletchingLevel
                }
            }()
            onInteractionFeedback?("🔥 铁匠铺炉火冲霄：【\(track.displayName) Lv.\(lvl)】锻造完成（\(track.summary(atLevel: lvl))）！")
            drainAndPlayAudioCues()
            pushUiSyncNow()
        } else {
            onInteractionFeedback?("无法升级【\(track.displayName)】：请检查金木粮储量或是否需更高时代（Lv.2需时代II，Lv.3需时代III）")
        }
    }

    public func cancelQueueItem(at index: Int) {
        if engine.cancelTrainingQueueItem(side: .player, at: index) {
            onInteractionFeedback?("已取消队列训练并全额退还军费粮饷")
            BattleAudioEngine.shared.play(.uiClick)
            pushUiSyncNow()
        }
    }

    public func selectAllCombatSquads() {
        selectedSquadIds = engine.squads
            .filter { $0.side == .player && $0.aliveCount > 0 && !$0.isRouting && $0.corpsRole != .supplyEscort }
            .map(\.id)
        onInteractionFeedback?("已全选我方场上主力作战编队（共 \(selectedSquadIds.count) 支军团）")
        BattleAudioEngine.shared.play(.uiClick)
        pushUiSyncNow()
    }

    public func selectSingleSquad(_ squadId: Int, centerCamera: Bool = false) {
        guard squadId >= 0 && squadId < engine.squads.count,
              engine.squads[squadId].side == .player else { return }
        selectedSquadIds = [squadId]
        if centerCamera {
            let sq = engine.squads[squadId]
            worldCamera.position = scenePoint(fromLogicX: sq.anchorX, logicY: sq.anchorY)
            clampCameraPosition()
        }
        let uName = UnitConfig.stats(for: engine.squads[squadId].primaryUnitType)?.name ?? "编队"
        onInteractionFeedback?("已选定【\(uName)】（存活 \(engine.squads[squadId].aliveCount) · 士气 \(Int(engine.squads[squadId].morale))）")
        BattleAudioEngine.shared.play(.uiClick)
        pushUiSyncNow()
    }

    public func applyFormationToSelection(_ formation: FormationType) {
        let targets = effectiveTargetSquadIds()
        guard !targets.isEmpty else {
            onInteractionFeedback?("当前无可调度编队（请框选未溃逃的我军分队）")
            return
        }
        engine.issueSquadCommand(SquadCommandRequest(squadIds: targets, formation: formation))
        onInteractionFeedback?("🛡 已命 \(targets.count) 支编队变阵为【\(formation.displayName)】（\(formation.tacticalBrief)）")
        drainAndPlayAudioCues()
        pushUiSyncNow()
    }

    public func applyTacticalOrderToSelection(_ order: TacticalOrder) {
        let targets = effectiveTargetSquadIds()
        guard !targets.isEmpty else {
            onInteractionFeedback?("当前无可调度编队（请框选未溃逃的我军分队）")
            return
        }
        var targetX: Double? = nil
        var targetY: Double? = nil
        if order == .advance || order == .allOutCharge || order == .flank || order == .pincerEncircle {
            if let enemySq = engine.squads.first(where: { $0.side == .enemy && $0.aliveCount > 0 }) {
                targetX = enemySq.anchorX
                targetY = enemySq.anchorY
            } else {
                let eCamp = engine.baseCampCoordinates(for: .enemy)
                targetX = eCamp.x
                targetY = eCamp.y
            }
        } else if order == .retreat {
            let pCamp = engine.baseCampCoordinates(for: .player)
            targetX = pCamp.x + 150.0
            targetY = pCamp.y
        }
        engine.issueSquadCommand(
            SquadCommandRequest(
                squadIds: targets,
                order: order,
                targetWorldX: targetX,
                targetWorldY: targetY
            )
        )
        onInteractionFeedback?("⚔️ 已向 \(targets.count) 支编队下达【\(order.displayName)】军令！")
        drainAndPlayAudioCues()
        pushUiSyncNow()
    }

    public func toggleBattlePause() {
        engine.setPaused(!engine.isPaused)
        onInteractionFeedback?(
            engine.isPaused
                ? "⏸ 战术暂停中：可自由营建、框选多路军团、右键拖拽拉设战线与变阵"
                : "▶️ 战鼓重鸣：全军恢复实时交锋"
        )
        BattleAudioEngine.shared.play(.drumMarch, volumeScale: 0.65)
        pushUiSyncNow()
    }

    public func setBattlePaused(_ paused: Bool) {
        engine.setPaused(paused)
        pushUiSyncNow()
    }

    public func toggleGarrisonBell() {
        engine.toggleGarrisonBell()
        BattleAudioEngine.shared.play(engine.playerState.garrisonBellActive ? .defeatBell : .drumMarch, volumeScale: 0.6)
        onInteractionFeedback?(
            engine.playerState.garrisonBellActive
                ? "🔔 主城警戒钟鸣响：野外民夫紧急退入主城射击孔放箭协防！"
                : "🔔 警戒钟已解除：民夫出城恢复采矿、伐木、收粮与筑城"
        )
        pushUiSyncNow()
    }

    @discardableResult
    public func requestToggleControlMode() -> Bool {
        if engine.playerHero.vitalState == .recoveringInCamp || engine.playerHero.vitalState == .fallenMartyred {
            onInteractionFeedback?(
                String(format: "主帅重伤包扎中（剩余 %.0fs），锁定 RTS 统帅视角调度残军！", engine.playerHero.medicalRecoveryRemainingSec)
            )
            return false
        }
        if engine.switchCooldownRemaining > 0.0 {
            onInteractionFeedback?(
                String(format: "视角切换冷却中（剩余 %.1fs）", engine.switchCooldownRemaining)
            )
            return false
        }
        let switched = engine.toggleControlMode()
        if switched {
            cancelPendingBuildPlacement()
            pressedKeyCodes.removeAll()
            heroMouseLeftHeld = false
            heroMouseRightHeld = false
            engine.updateHeroInput(HeroControlInputState())
            BattleAudioEngine.shared.play(.warHorn, volumeScale: 0.70)
            if engine.controlMode == .heroAction {
                worldCamera.position = scenePoint(fromLogicX: engine.playerHero.x, logicY: engine.playerHero.y)
                worldCamera.setScale(max(0.72, min(0.92, worldCamera.xScale)))
                clampCameraPosition()
                onInteractionFeedback?("⚔️ 主帅提刀亲征！[WASD] 走位 · 鼠标瞄准 · 左键劈刺/蓄射 · 右键举盾0.25s精准弹反 · [Space/E/R] 战技")
            } else {
                worldCamera.setScale(max(1.04, worldCamera.xScale))
                clampCameraPosition()
                onInteractionFeedback?("🗺 已切回 RTS 帝国统帅视角：左键框选 · 右键拖拽拉设阵线 · 左下营建基地与升级铁匠科技")
            }
            pushUiSyncNow()
        }
        return switched
    }

    public func switchHeroWeapon(_ weapon: HeroWeaponType) {
        engine.switchHeroWeapon(weapon)
        BattleAudioEngine.shared.play(.swordClash, volumeScale: 0.55)
        onInteractionFeedback?("主帅切换随身兵刃：【\(weapon.displayName)】")
        pushUiSyncNow()
    }

    public func triggerHeroSkill(_ skill: HeroSkillId) {
        let ok = engine.triggerHeroSkill(skill)
        if ok {
            let title: String = {
                switch skill {
                case .breakthroughCharge: return "【破阵突击】猛冲撞阵！"
                case .ironBulwark: return "【铁壁横戈】2.0s 招架箭雨并蓄势横扫！"
                case .grandWarCry: return "【三军战吼】友军士气 +18，溃军重整归建！"
                }
            }()
            onInteractionFeedback?("🔥 主帅施放绝技：\(title)")
            drainAndPlayAudioCues()
            pushUiSyncNow()
        } else {
            let cd = engine.playerHero.cooldownRemaining(for: skill)
            onInteractionFeedback?(String(format: "战技尚在调息冷却中（剩余 %.1fs）", cd))
        }
    }

    public func recruitReinforcement(unitType: UnitTypeId, useMercenaryGold: Bool = false, batchCount: Int = 1) {
        let role: ArmyCorpsRole = {
            guard let st = UnitConfig.stats(for: unitType) else { return .rearReserve }
            switch st.category {
            case .support: return .supplyEscort
            case .ranged, .siege: return .siegeBattery
            case .cavalry: return .leftWing
            case .infantry, .polearm, .shock: return .vanguardCenter
            }
        }()
        var recruitedCount = 0
        for _ in 0..<max(1, batchCount) {
            let ok = useMercenaryGold
                ? engine.recruitMercenaryUnit(side: .player, unitType: unitType, corpsRole: role)
                : engine.recruitUnit(side: .player, unitType: unitType, corpsRole: role)
            if ok { recruitedCount += 1 } else { break }
        }
        let uName = UnitConfig.stats(for: unitType)?.name ?? unitType.rawValue
        if recruitedCount > 0 {
            BattleAudioEngine.shared.play(.uiClick)
            onInteractionFeedback?(
                useMercenaryGold
                    ? "💰 商盟黄金契约生效：×\(recruitedCount)【\(uName)】已即时投入前线！"
                    : "已下令训练 ×\(recruitedCount)【\(uName)】（队列共 \(engine.playerState.trainingQueue.count) 项，建军营/靶场/马厩可大幅提速）"
            )
            pushUiSyncNow()
        } else {
            onInteractionFeedback?("无法招募【\(uName)】：请检查金木粮储量，或营建【军屯民居】提升人口上限")
        }
    }

    public func deployWulinTrap(_ kind: FieldTrapKind) {
        let anchorX: Double
        let anchorY: Double
        if engine.controlMode == .heroAction {
            anchorX = engine.playerHero.x + cos(engine.playerHero.facingRadians) * 42.0
            anchorY = engine.playerHero.y + sin(engine.playerHero.facingRadians) * 42.0
        } else if let sqId = selectedSquadIds.first, sqId < engine.squads.count {
            anchorX = engine.squads[sqId].anchorX + 60.0
            anchorY = engine.squads[sqId].anchorY
        } else {
            anchorX = worldWidth * 0.45
            anchorY = worldHeight * 0.50
        }
        if engine.deployFieldTrap(side: .player, kind: kind, x: anchorX, y: anchorY) {
            syncTrapVisualPool()
            BattleAudioEngine.shared.play(.buildHammer, volumeScale: 0.65)
            onInteractionFeedback?("🌲 雾林奇谋：已在前沿秘密布设【\(kind == .tripwire ? "绊马索" : "尖刺陷坑")】（耗木 25）")
            pushUiSyncNow()
        } else {
            onInteractionFeedback?("布设陷阱失败：仅雾林猎手可用且需至少 25 木材")
        }
    }

    public func concludeBattleByTruceAndSummarize() -> PostBattleSettlementSummary {
        engine.concludeByTruce()
        pushUiSyncNow()
        return engine.buildPostBattleSummary()
    }

    public func buildCurrentSettlementSummary() -> PostBattleSettlementSummary {
        engine.buildPostBattleSummary()
    }

    private func effectiveTargetSquadIds() -> [Int] {
        let validSelected = selectedSquadIds.filter {
            $0 >= 0 && $0 < engine.squads.count &&
            engine.squads[$0].side == .player &&
            engine.squads[$0].aliveCount > 0 &&
            !engine.squads[$0].isRouting
        }
        if !validSelected.isEmpty {
            return validSelected
        }
        return engine.squads
            .filter { $0.side == .player && $0.aliveCount > 0 && !$0.isRouting && $0.corpsRole != .supplyEscort }
            .map(\.id)
    }

    // MARK: - 30Hz 确定性模拟驱动（支持 0.5x~2.0x 倍速）与 60FPS 视口裁剪合批渲染主循环

    public override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        if lastUpdateTimestamp == 0.0 {
            lastUpdateTimestamp = currentTime
            return
        }
        let rawDt = max(0.0, min(0.08, currentTime - lastUpdateTimestamp))
        lastUpdateTimestamp = currentTime

        updateCameraAndHeroInput(frameDt: rawDt)
        animateEnvironmentRipplesAndWeather(frameDt: rawDt, now: currentTime)

        if orderMarkerFadeTimer > 0.0 {
            orderMarkerFadeTimer -= rawDt
            if orderMarkerFadeTimer <= 0.0 {
                orderMarkerNode.isHidden = true
            }
        }

        let fixedStep = 1.0 / Double(GameConstants.logicTickHz)
        if !engine.isPaused && engine.outcome == .ongoing {
            fixedTickAccumulator += rawDt * max(0.25, min(2.5, simulationSpeedMultiplier))
            var subSteps = 0
            while fixedTickAccumulator >= fixedStep && subSteps < 6 && engine.outcome == .ongoing {
                engine.stepLogicTick(deltaTime: fixedStep)
                fixedTickAccumulator -= fixedStep
                subSteps += 1
            }
            if subSteps == 6 {
                fixedTickAccumulator = 0.0
            }
        }

        drainAndPlayAudioCues()

        let currentVital = engine.playerHero.vitalState
        if currentVital != lastObservedHeroVitalState {
            lastObservedHeroVitalState = currentVital
            if currentVital == .recoveringInCamp {
                heroMouseLeftHeld = false
                heroMouseRightHeld = false
                pressedKeyCodes.removeAll()
                worldCamera.setScale(max(1.12, worldCamera.xScale))
                clampCameraPosition()
                BattleAudioEngine.shared.play(.defeatBell, volumeScale: 0.7)
                onInteractionFeedback?("⚠️ 帅旗倾倒！主帅重伤退入主城医帐包扎 45s（全军士气 -35·上限锁 65），已自动拉回 RTS 视角！")
                pushUiSyncNow()
            } else if currentVital == .woundedWeakened {
                BattleAudioEngine.shared.play(.warHorn, volumeScale: 0.7)
                onInteractionFeedback?("🔥 主帅包扎完毕重返沙场（重创虚弱态），可按 [Tab] 再度披挂上阵！")
                pushUiSyncNow()
            }
        }

        if !selectedSquadIds.isEmpty {
            selectedSquadIds.removeAll { id in
                id < 0 || id >= engine.squads.count || engine.squads[id].aliveCount <= 0
            }
        }

        syncAllVisualNodesWithEngine()

        uiPushAccumulator += rawDt
        if uiPushAccumulator >= 0.25 {
            uiPushAccumulator = 0.0
            pushUiSyncNow()
        }

        if engine.outcome != .ongoing && !outcomeNotified {
            outcomeNotified = true
            let summary = engine.buildPostBattleSummary()
            BattleAudioEngine.shared.play(summary.isVictory ? .victoryFanfare : .defeatBell, volumeScale: 0.90)
            pushUiSyncNow()
            onBattleConcluded?(summary)
        }
    }

    private func drainAndPlayAudioCues() {
        let cues = engine.drainPendingSoundCues()
        for cue in cues {
            BattleAudioEngine.shared.play(cue)
        }
    }

    private func animateEnvironmentRipplesAndWeather(frameDt: Double, now: TimeInterval) {
        for (idx, rip) in waterRippleNodes.enumerated() {
            rip.alpha = 0.20 + 0.16 * CGFloat(sin(now * 2.4 + Double(idx) * 0.9))
            rip.position.x += CGFloat(sin(now * 1.5 + Double(idx))) * 0.15
        }
        guard !weatherParticleNodes.isEmpty else { return }
        let camRect = currentVisibleSceneRect(margin: 80)
        for p in weatherParticleNodes {
            p.position.y -= CGFloat(260.0 * frameDt)
            p.position.x -= CGFloat(65.0 * frameDt)
            if p.position.y < camRect.minY {
                p.position.y = camRect.maxY
                p.position.x = CGFloat.random(in: camRect.minX...max(camRect.minX + 10, camRect.maxX))
            }
        }
    }

    private func updateCameraAndHeroInput(frameDt: Double) {
        if let win = self.view?.window, !win.isKeyWindow {
            if !pressedKeyCodes.isEmpty || heroMouseLeftHeld || heroMouseRightHeld {
                pressedKeyCodes.removeAll()
                heroMouseLeftHeld = false
                heroMouseRightHeld = false
                engine.updateHeroInput(HeroControlInputState())
            }
            return
        }

        if let view = self.view, let win = view.window {
            let winMouse = win.mouseLocationOutsideOfEventStream
            let viewPt = view.convert(winMouse, from: nil)
            if view.bounds.contains(viewPt) {
                let scenePt = convertPoint(fromView: viewPt)
                mouseHoverScenePoint = scenePt
                if let kind = pendingBuildKind, let ghost = buildGhostNode {
                    ghost.position = scenePt
                    let lPt = logicCoordinates(fromScenePoint: scenePt)
                    let valid = engine.canPlaceBuilding(side: .player, kind: kind, atX: lPt.x, atY: lPt.y)
                    ghost.color = valid ? .systemGreen : .systemRed
                    ghost.colorBlendFactor = 0.65
                }
            }
        }

        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: mouseHoverScenePoint)

            var moveX = 0.0
            var moveY = 0.0
            if pressedKeyCodes.contains(0) || pressedKeyCodes.contains(123) { moveX -= 1.0 }
            if pressedKeyCodes.contains(2) || pressedKeyCodes.contains(124) { moveX += 1.0 }
            if pressedKeyCodes.contains(13) || pressedKeyCodes.contains(126) { moveY -= 1.0 }
            if pressedKeyCodes.contains(1) || pressedKeyCodes.contains(125) { moveY += 1.0 }

            engine.updateHeroInput(
                HeroControlInputState(
                    moveAxisX: moveX,
                    moveAxisY: moveY,
                    aimWorldX: heroAimLogicPoint.x,
                    aimWorldY: heroAimLogicPoint.y,
                    isPrimaryAttackHeld: heroMouseLeftHeld,
                    isSecondaryBlockHeld: heroMouseRightHeld
                )
            )

            let heroScenePt = scenePoint(fromLogicX: engine.playerHero.x, logicY: engine.playerHero.y)
            let aimScenePt = scenePoint(fromLogicX: heroAimLogicPoint.x, logicY: heroAimLogicPoint.y)
            let lookAheadX = max(-95.0, min(95.0, (aimScenePt.x - heroScenePt.x) * 0.16))
            let lookAheadY = max(-65.0, min(65.0, (aimScenePt.y - heroScenePt.y) * 0.16))
            let targetCamX = heroScenePt.x + lookAheadX
            let targetCamY = heroScenePt.y + lookAheadY
            let lerpFactor = CGFloat(min(1.0, frameDt * 9.5))
            worldCamera.position.x += (targetCamX - worldCamera.position.x) * lerpFactor
            worldCamera.position.y += (targetCamY - worldCamera.position.y) * lerpFactor

            if engine.cameraShakeIntensity > 0.02 {
                let amp = CGFloat(engine.cameraShakeIntensity * 7.5)
                worldCamera.position.x += CGFloat.random(in: -amp...amp)
                worldCamera.position.y += CGFloat.random(in: -amp...amp)
            }
            clampCameraPosition()

            if let reticle = heroAimReticleNode {
                reticle.isHidden = false
                reticle.position = aimScenePt
            }
        } else {
            heroAimReticleNode?.isHidden = true
            let panVel = CGFloat(keyboardPanSpeed * frameDt) * worldCamera.xScale
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if pressedKeyCodes.contains(123) { dx -= panVel }
            if pressedKeyCodes.contains(124) { dx += panVel }
            if pressedKeyCodes.contains(126) { dy += panVel }
            if pressedKeyCodes.contains(125) { dy -= panVel }

            if enableEdgeCursorPan, let view = self.view, let win = view.window, win.isKeyWindow {
                let vPt = view.convert(win.mouseLocationOutsideOfEventStream, from: nil)
                let margin: CGFloat = 24.0
                if view.bounds.contains(vPt) {
                    if vPt.x < margin { dx -= panVel * 0.85 }
                    else if vPt.x > view.bounds.width - margin { dx += panVel * 0.85 }
                    if vPt.y < margin { dy -= panVel * 0.85 }
                    else if vPt.y > view.bounds.height - margin { dy += panVel * 0.85 }
                }
            }
            if dx != 0 || dy != 0 {
                panCamera(dx: dx, dy: dy)
            }
        }
    }

    private func pushUiSyncNow() {
        let briefs: [SquadUiBrief] = engine.squads
            .filter { $0.side == .player }
            .map { sq in
                SquadUiBrief(
                    id: sq.id,
                    corpsRole: sq.corpsRole,
                    unitType: sq.primaryUnitType,
                    unitName: UnitConfig.stats(for: sq.primaryUnitType)?.name ?? sq.primaryUnitType.rawValue,
                    aliveCount: sq.aliveCount,
                    initialCount: max(1, sq.initialCount),
                    morale: sq.morale,
                    isRouting: sq.isRouting,
                    formation: sq.formation,
                    order: sq.order,
                    encirclement: sq.encirclementState,
                    veterancyStars: sq.veterancyStars,
                    totalKills: sq.totalKills
                )
            }

        var radarDots: [MinimapRadarDot] = []
        radarDots.reserveCapacity(64)
        var dotId = 0
        for res in engine.resourceNodes where res.remainingAmount > 0 {
            radarDots.append(MinimapRadarDot(id: dotId, normX: res.x / worldWidth, normY: res.y / worldHeight, isPlayer: false, isBuilding: false, isResource: true))
            dotId += 1
        }
        for st in engine.structures where !st.isDestroyed && st.kind != .wallSegment && st.kind != .woodenCheval {
            radarDots.append(MinimapRadarDot(id: dotId, normX: st.x / worldWidth, normY: st.y / worldHeight, isPlayer: st.side == .player, isBuilding: true, isResource: false))
            dotId += 1
        }
        for sq in engine.squads where sq.aliveCount > 0 {
            if sq.side == .enemy && sq.id < enemySquadVisibleFlags.count && !enemySquadVisibleFlags[sq.id] {
                continue
            }
            radarDots.append(MinimapRadarDot(id: dotId, normX: sq.anchorX / worldWidth, normY: sq.anchorY / worldHeight, isPlayer: sq.side == .player, isBuilding: false, isResource: false))
            dotId += 1
        }

        let camLogic = logicCoordinates(fromScenePoint: worldCamera.position)
        let visW = min(1.0, Double(size.width * worldCamera.xScale) / worldWidth)
        let visH = min(1.0, Double(size.height * worldCamera.yScale) / worldHeight)

        let hero = engine.playerHero
        let packet = BattlefieldUiSyncPacket(
            hud: engine.latestHudSnapshot,
            playerSquads: briefs,
            selectedSquadIds: selectedSquadIds,
            trainingQueueCount: engine.playerState.trainingQueue.count,
            trainingQueueItems: engine.playerState.trainingQueue,
            aiDoctrine: engine.aiBlackboard.activeDoctrine,
            aiSiegePhase: engine.aiBlackboard.siegePhase,
            heroBreakthroughCd: hero.breakthroughCooldown,
            heroBulwarkCd: hero.ironBulwarkCooldown,
            heroWarCryCd: hero.grandWarCryCooldown,
            heroMedicalRemainingSec: hero.medicalRecoveryRemainingSec,
            heroBowChargeRatio: min(1.0, hero.bowChargeElapsed / 0.90),
            heroKills: hero.killsCount,
            bloodMoonFervorRemaining: engine.playerState.bloodMoonFervorRemainingSec,
            simulationSpeed: simulationSpeedMultiplier,
            pendingBuildKind: pendingBuildKind,
            minimapDots: radarDots,
            cameraNormCenterX: max(0.0, min(1.0, camLogic.x / worldWidth)),
            cameraNormCenterY: max(0.0, min(1.0, camLogic.y / worldHeight)),
            cameraNormWidth: visW,
            cameraNormHeight: visH
        )
        onUiPacketSynced?(packet)
    }

    // MARK: - 战场精美自然地貌、古罗马石道、松林、石桥与矿脉麦田绘制

    private static func groundBaseColor(for terrain: TerrainType, weather: WeatherType) -> NSColor {
        var base: (r: CGFloat, g: CGFloat, b: CGFloat) = {
            switch terrain {
            case .plain: return (0.20, 0.25, 0.14)
            case .highGround: return (0.24, 0.23, 0.17)
            case .riverFord, .bridgePass: return (0.18, 0.25, 0.16)
            case .denseForest: return (0.14, 0.23, 0.14)
            case .desertDune: return (0.42, 0.33, 0.19)
            case .snowfield: return (0.62, 0.68, 0.74)
            case .fortWall: return (0.22, 0.22, 0.18)
            }
        }()
        if weather == .night {
            base.r *= 0.48; base.g *= 0.54; base.b *= 0.74
        } else if weather == .rainMud {
            base.r *= 0.75; base.g *= 0.78; base.b *= 0.84
        }
        return NSColor(calibratedRed: base.r, green: base.g, blue: base.b, alpha: 1.0)
    }

    private func buildBattlefieldTerrainAndResourceVisuals(atlas: StickmanTextureAtlas) {
        let baseCol = Self.groundBaseColor(for: engine.context.terrain, weather: engine.context.weather)
        let baseGround = SKSpriteNode(
            texture: atlas.whitePixel,
            color: baseCol,
            size: CGSize(width: worldWidth, height: worldHeight)
        )
        baseGround.colorBlendFactor = 1.0
        baseGround.position = CGPoint(x: worldWidth * 0.5, y: worldHeight * 0.5)
        terrainLayer.addChild(baseGround)

        // 铺设有机草甸/砂石肌理斑块，彻底消除死板纯色底板
        let patchColor = baseCol.blended(withFraction: 0.25, of: .white) ?? baseCol
        for gx in stride(from: 180.0, through: worldWidth - 180.0, by: 310.0) {
            for gy in stride(from: 160.0, through: worldHeight - 160.0, by: 290.0) {
                let jitterX = Double((Int(gx * 7 + gy * 3) % 90) - 45)
                let jitterY = Double((Int(gx * 5 + gy * 11) % 80) - 40)
                let patch = SKSpriteNode(texture: atlas.terrainNoisePatch, color: patchColor, size: CGSize(width: 260, height: 220))
                patch.colorBlendFactor = 0.85
                patch.alpha = 0.48
                patch.position = scenePoint(fromLogicX: gx + jitterX, logicY: gy + jitterY)
                terrainLayer.addChild(patch)
            }
        }

        // 贯通两军主城的中路古罗马军用石板大道与南北侧翼驿道
        let pCamp = engine.baseCampCoordinates(for: .player)
        let eCamp = engine.baseCampCoordinates(for: .enemy)
        for rx in stride(from: pCamp.x + 80.0, through: eCamp.x - 80.0, by: 152.0) {
            let mainRoad = SKSpriteNode(texture: atlas.cobbleRoadTile, size: CGSize(width: 158, height: 52))
            mainRoad.alpha = 0.72
            mainRoad.position = scenePoint(fromLogicX: rx, logicY: worldHeight * 0.5)
            terrainLayer.addChild(mainRoad)
        }

        // 绘制真实物理地形功能区（碧波河流、石拱桥、悬崖高地、层叠松林）
        waterRippleNodes.removeAll()
        for zone in engine.terrainZones {
            let w = zone.maxX - zone.minX
            let h = zone.maxY - zone.minY
            let center = scenePoint(fromLogicX: (zone.minX + zone.maxX) * 0.5, logicY: (zone.minY + zone.maxY) * 0.5)

            switch zone.terrain {
            case .riverFord:
                let bank = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 0.54, green: 0.46, blue: 0.32, alpha: 0.65), size: CGSize(width: w + 26, height: h + 16))
                bank.colorBlendFactor = 1.0
                bank.position = center
                terrainLayer.addChild(bank)

                let water = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.64, alpha: 0.84), size: CGSize(width: w, height: h))
                water.colorBlendFactor = 1.0
                water.position = center
                terrainLayer.addChild(water)

                for ry in stride(from: zone.minY + 35.0, through: zone.maxY - 35.0, by: 62.0) {
                    let ripple = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.96, alpha: 0.30), size: CGSize(width: w * 0.55, height: 3.5))
                    ripple.colorBlendFactor = 1.0
                    ripple.position = scenePoint(fromLogicX: (zone.minX + zone.maxX) * 0.5, logicY: ry)
                    terrainLayer.addChild(ripple)
                    waterRippleNodes.append(ripple)
                }

            case .bridgePass:
                let bridge = SKSpriteNode(texture: atlas.stoneBridgeSprite, size: CGSize(width: w + 16, height: h + 12))
                bridge.position = center
                terrainLayer.addChild(bridge)

            case .highGround:
                let plateau = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 0.38, green: 0.34, blue: 0.25, alpha: 0.55), size: CGSize(width: w, height: h))
                plateau.colorBlendFactor = 1.0
                plateau.position = center
                terrainLayer.addChild(plateau)
                for rx in stride(from: zone.minX + 55.0, through: zone.maxX - 55.0, by: 110.0) {
                    let ridge = SKSpriteNode(texture: atlas.cliffRockSprite, size: CGSize(width: 112, height: 52))
                    ridge.position = scenePoint(fromLogicX: rx, logicY: zone.maxY - 12.0)
                    terrainLayer.addChild(ridge)
                }

            case .denseForest:
                let floorShade = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.10, alpha: 0.48), size: CGSize(width: w, height: h))
                floorShade.colorBlendFactor = 1.0
                floorShade.position = center
                terrainLayer.addChild(floorShade)
                // 在树冠层散布苍翠松树群落（半透明树冠不遮挡林下潜伏伏兵操控！）
                for tx in stride(from: zone.minX + 42.0, through: zone.maxX - 42.0, by: 86.0) {
                    for ty in stride(from: zone.minY + 42.0, through: zone.maxY - 42.0, by: 84.0) {
                        let ox = Double((Int(tx * 3 + ty * 7) % 28) - 14)
                        let oy = Double((Int(tx * 5 + ty * 3) % 28) - 14)
                        let tree = SKSpriteNode(texture: atlas.pineTreeCanopy, size: CGSize(width: 66, height: 66))
                        tree.alpha = 0.78
                        tree.position = scenePoint(fromLogicX: tx + ox, logicY: ty + oy)
                        forestCanopyLayer.addChild(tree)
                    }
                }

            case .fortWall:
                let rampart = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 0.34, green: 0.33, blue: 0.31, alpha: 0.62), size: CGSize(width: w, height: h))
                rampart.colorBlendFactor = 1.0
                rampart.position = center
                terrainLayer.addChild(rampart)

            default:
                break
            }
        }

        // 绘制 6 处高清金矿洞、伐木林场与黄金麦田地标
        resourceAmountLabels.removeAll()
        for res in engine.resourceNodes {
            let pos = scenePoint(fromLogicX: res.x, logicY: res.y)
            let (tex, rTitle): (SKTexture, String) = {
                switch res.kind {
                case .goldMine: return (atlas.goldMineLandmark, "⛏ 黄金矿脉")
                case .lumberForest: return (atlas.lumberCampLandmark, "🌲 伐木林场")
                case .grainFarm: return (atlas.wheatFarmLandmark, "🌾 丰饶麦庄")
                }
            }()
            let landmark = SKSpriteNode(texture: tex, size: CGSize(width: 84, height: 72))
            landmark.position = pos
            terrainLayer.addChild(landmark)

            let lbl = SKLabelNode(fontNamed: "PingFangSC-Semibold")
            lbl.text = "\(rTitle) (\(Int(res.remainingAmount)))"
            lbl.fontSize = 12
            lbl.fontColor = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.78, alpha: 1.0)
            lbl.position = CGPoint(x: pos.x, y: pos.y + 42)
            terrainLayer.addChild(lbl)
            resourceAmountLabels.append(lbl)
        }

        // 若天气为暴雨或暴雪，初始化环境粒子
        weatherParticleNodes.removeAll()
        if engine.context.weather == .rainMud || engine.context.weather == .blizzard {
            let isSnow = engine.context.weather == .blizzard
            for _ in 0..<56 {
                let drop = SKSpriteNode(
                    texture: isSnow ? atlas.circleFilled : atlas.whitePixel,
                    color: isSnow ? NSColor(calibratedWhite: 0.96, alpha: 0.65) : NSColor(calibratedRed: 0.72, green: 0.85, blue: 1.0, alpha: 0.42),
                    size: isSnow ? CGSize(width: 5, height: 5) : CGSize(width: 1.8, height: 16)
                )
                drop.colorBlendFactor = 1.0
                drop.zRotation = isSnow ? 0 : -0.24
                drop.position = CGPoint(x: CGFloat.random(in: 0...CGFloat(worldWidth)), y: CGFloat.random(in: 0...CGFloat(worldHeight)))
                uiOverlayLayer.addChild(drop)
                weatherParticleNodes.append(drop)
            }
        }
    }

    private func buildPreallocatedEntityPools(atlas: StickmanTextureAtlas) {
        structurePoolNodes.removeAll()
        syncDynamicStructurePool()
        syncTrapVisualPool()

        soldierPoolNodes.reserveCapacity(GameConstants.maxUnitPoolSize)
        for _ in 0..<GameConstants.maxUnitPoolSize {
            let sNode = PooledSoldierNode(atlas: atlas)
            unitBatchLayer.addChild(sNode.root)
            soldierPoolNodes.append(sNode)
        }

        let pPrim = factionPrimaryColors[engine.playerState.faction] ?? .systemRed
        let pAcc = factionAccentColors[engine.playerState.faction] ?? .systemYellow
        let pHero = PooledHeroNode(atlas: atlas, primaryColor: pPrim, accentColor: pAcc, title: "★ 我军统帅")
        pHero.root.zPosition = 3.0
        unitBatchLayer.addChild(pHero.root)
        playerHeroNode = pHero

        let ePrim = factionPrimaryColors[engine.enemyState.faction] ?? .systemBlue
        let eAcc = factionAccentColors[engine.enemyState.faction] ?? .white
        let eHero = PooledHeroNode(atlas: atlas, primaryColor: ePrim, accentColor: eAcc, title: "✦ 敌军统帅")
        eHero.root.zPosition = 3.0
        unitBatchLayer.addChild(eHero.root)
        enemyHeroNode = eHero

        projectilePoolNodes.reserveCapacity(GameConstants.maxProjectilePoolSize)
        for _ in 0..<GameConstants.maxProjectilePoolSize {
            let p = SKSpriteNode(texture: atlas.arrowProjectile, color: .white, size: CGSize(width: 22, height: 6))
            p.colorBlendFactor = 1.0
            p.isHidden = true
            projectileLayer.addChild(p)
            projectilePoolNodes.append(p)
        }

        corpsePoolNodes.reserveCapacity(GameConstants.maxFallenCorpseDecals)
        for _ in 0..<GameConstants.maxFallenCorpseDecals {
            let c = SKSpriteNode(texture: atlas.corpseSilhouette, color: .gray, size: CGSize(width: 28, height: 13))
            c.colorBlendFactor = 1.0
            c.isHidden = true
            corpseDecalLayer.addChild(c)
            corpsePoolNodes.append(c)
        }

        particlePoolNodes.reserveCapacity(GameConstants.maxEffectParticlePoolSize)
        lastRenderedParticleCursorSnapshot = Array(repeating: false, count: GameConstants.maxEffectParticlePoolSize)
        for _ in 0..<GameConstants.maxEffectParticlePoolSize {
            let fx = SKSpriteNode(texture: atlas.sparkStar, color: .yellow, size: CGSize(width: 18, height: 18))
            fx.colorBlendFactor = 1.0
            fx.isHidden = true
            effectLayer.addChild(fx)
            particlePoolNodes.append(fx)
        }

        for _ in 0..<36 {
            let dmgLbl = SKLabelNode(fontNamed: "PingFangSC-Heavy")
            dmgLbl.fontSize = 14
            dmgLbl.isHidden = true
            effectLayer.addChild(dmgLbl)
            damageLabelPool.append(dmgLbl)
        }

        for _ in 0..<40 {
            let m = PooledSquadMarkerNode(atlas: atlas)
            squadOverlayLayer.addChild(m.root)
            squadMarkerNodes.append(m)
        }
    }

    private func syncDynamicStructurePool() {
        let atlas = StickmanTextureAtlas.shared
        while structurePoolNodes.count < engine.structures.count {
            let idx = structurePoolNodes.count
            let st = engine.structures[idx]
            let sideBase = st.side == .player
                ? (factionPrimaryColors[engine.playerState.faction] ?? .systemRed)
                : (factionPrimaryColors[engine.enemyState.faction] ?? .systemBlue)
            let prefix = st.side == .player ? "我方" : "敌方"
            let title: String = {
                switch st.kind {
                case .baseCamp, .arrowTower, .barracks, .archeryRange, .stables, .blacksmith, .siegeWorkshop, .imperialFarm, .houseQuarter:
                    return "\(prefix)\(st.kind.displayName)"
                default:
                    return st.kind.displayName
                }
            }()
            let node = PooledStructureNode(atlas: atlas, kind: st.kind, width: CGFloat(st.width), height: CGFloat(st.height), color: sideBase, title: title)
            node.root.position = scenePoint(fromLogicX: st.x, logicY: st.y)
            structureLayer.addChild(node.root)
            structurePoolNodes.append(node)
        }
    }

    private func syncTrapVisualPool() {
        let atlas = StickmanTextureAtlas.shared
        while trapPoolNodes.count < engine.fieldTraps.count {
            let tNode = SKSpriteNode(texture: atlas.circleRing, color: .systemGreen, size: CGSize(width: 48, height: 48))
            tNode.colorBlendFactor = 1.0
            terrainLayer.addChild(tNode)
            trapPoolNodes.append(tNode)
        }
    }

    // MARK: - 帧同步渲染（含动态营建脚手架、老兵金星、龟甲阵覆盾与选中脚环）

    private func syncAllVisualNodesWithEngine() {
        let atlas = StickmanTextureAtlas.shared
        let visibleRect = currentVisibleSceneRect()
        let isFarLod = enableFarLod && (1.0 / Double(worldCamera.xScale)) < GameConstants.battlefieldFarLodZoomThreshold

        if structurePoolNodes.count < engine.structures.count {
            syncDynamicStructurePool()
        }

        if lastResourceIntAmounts.count < engine.resourceNodes.count {
            lastResourceIntAmounts = Array(repeating: -1, count: engine.resourceNodes.count)
        }
        for i in 0..<min(resourceAmountLabels.count, engine.resourceNodes.count) {
            let res = engine.resourceNodes[i]
            let amt = Int(res.remainingAmount)
            if lastResourceIntAmounts[i] != amt {
                lastResourceIntAmounts[i] = amt
                let rTitle: String = {
                    switch res.kind {
                    case .goldMine: return "⛏ 黄金矿脉"
                    case .lumberForest: return "🌲 伐木林场"
                    case .grainFarm: return "🌾 丰饶麦庄"
                    }
                }()
                resourceAmountLabels[i].text = "\(rTitle) (\(amt))"
            }
            resourceAmountLabels[i].alpha = res.remainingAmount > 0 ? 0.95 : 0.30
        }

        for i in 0..<min(structurePoolNodes.count, engine.structures.count) {
            let st = engine.structures[i]
            let node = structurePoolNodes[i]
            if st.isDestroyed {
                if !node.wasRenderedDestroyed {
                    node.wasRenderedDestroyed = true
                    node.body.alpha = 0.22
                    node.brazierGlow.isHidden = true
                    node.scaffoldOverlay.isHidden = true
                    node.hpBg.isHidden = true
                    node.hpFill.isHidden = true
                    node.label.text = "[\(node.baseTitle)·废墟]"
                    node.label.fontColor = .systemGray
                }
            } else if st.isUnderConstruction {
                let pct = Int((st.constructionProgress * 100.0).rounded())
                node.body.alpha = 0.45 + 0.55 * CGFloat(st.constructionProgress)
                node.scaffoldOverlay.isHidden = false
                let ratio = CGFloat(max(0.05, min(1.0, st.constructionProgress)))
                node.hpFill.size.width = node.maxBarWidth * ratio
                node.hpFill.color = .systemYellow
                if node.lastProgressBucket != pct / 5 {
                    node.lastProgressBucket = pct / 5
                    node.label.text = "🔨 \(node.baseTitle) (\(pct)%)"
                }
            } else {
                if node.lastProgressBucket != 100 {
                    node.lastProgressBucket = 100
                    node.body.alpha = 1.0
                    node.scaffoldOverlay.isHidden = true
                    node.label.text = node.baseTitle
                }
                let ratio = CGFloat(max(0.0, min(1.0, st.hp / max(1.0, st.maxHp))))
                node.hpFill.size.width = node.maxBarWidth * ratio
                node.hpFill.color = ratio > 0.5 ? .systemGreen : (ratio > 0.25 ? .systemOrange : .systemRed)
            }
        }

        if trapPoolNodes.count < engine.fieldTraps.count {
            syncTrapVisualPool()
        }
        for i in 0..<min(trapPoolNodes.count, engine.fieldTraps.count) {
            let tr = engine.fieldTraps[i]
            let node = trapPoolNodes[i]
            if tr.remainingCharges <= 0 {
                node.isHidden = true
            } else if tr.side == .player || tr.isTriggered || engine.playerState.faction == .wulin {
                node.isHidden = false
                node.position = scenePoint(fromLogicX: tr.x, logicY: tr.y)
                node.color = tr.side == .player
                    ? NSColor.systemGreen.withAlphaComponent(0.60)
                    : NSColor.systemRed.withAlphaComponent(0.65)
            } else {
                node.isHidden = true
            }
        }

        if enemySquadVisibleFlags.count < engine.squads.count {
            enemySquadVisibleFlags = Array(repeating: false, count: engine.squads.count + 16)
        } else {
            for idx in 0..<engine.squads.count {
                enemySquadVisibleFlags[idx] = false
            }
        }
        for i in 0..<engine.soldiers.count {
            let s = engine.soldiers[i]
            if s.isActive && s.hp > 0 && s.side == .enemy && s.isVisibleToOpponent,
               s.squadId >= 0 && s.squadId < enemySquadVisibleFlags.count {
                enemySquadVisibleFlags[s.squadId] = true
            }
        }

        let selectedSet = Set(selectedSquadIds)
        for idx in 0..<squadMarkerNodes.count {
            let marker = squadMarkerNodes[idx]
            guard idx < engine.squads.count else {
                marker.root.isHidden = true
                continue
            }
            let sq = engine.squads[idx]
            guard sq.aliveCount > 0 else {
                marker.root.isHidden = true
                continue
            }
            if sq.side == .enemy && !enemySquadVisibleFlags[idx] {
                marker.root.isHidden = true
                continue
            }

            let anchorPt = scenePoint(fromLogicX: sq.anchorX, logicY: sq.anchorY)
            marker.root.isHidden = false
            marker.root.position = anchorPt

            let isSel = (sq.side == .player && selectedSet.contains(sq.id))
            marker.selectRing.isHidden = !isSel

            let mRatio = CGFloat(max(0.0, min(1.0, sq.morale / 100.0)))
            marker.moraleFill.size.width = 52.0 * mRatio
            marker.moraleFill.color = sq.isRouting
                ? .white
                : (sq.morale < 40.0 ? .systemYellow : (sq.side == .player ? .systemGreen : .systemOrange))

            let starsPrefix = sq.veterancyStars > 0 ? String(repeating: "★", count: sq.veterancyStars) + " " : ""
            let nextText: String
            let nextColor: NSColor
            if sq.isRouting {
                nextText = "🏳️ 溃逃 (\(sq.aliveCount))"
                nextColor = .white
            } else if sq.encirclementState == .encircled {
                nextText = "⚠️ 铁桶合围! (\(sq.aliveCount))"
                nextColor = .systemRed
            } else if sq.encirclementState == .pincered {
                nextText = "⚡ 钳形夹击 (\(sq.aliveCount))"
                nextColor = .systemOrange
            } else if isSel || !isFarLod {
                let uShort = UnitConfig.stats(for: sq.primaryUnitType)?.name ?? ""
                nextText = "\(starsPrefix)\(uShort) \(sq.aliveCount) · \(sq.formation.displayName)"
                nextColor = isSel
                    ? NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.42, alpha: 1.0)
                    : NSColor(calibratedWhite: 0.94, alpha: 0.92)
            } else {
                nextText = "\(starsPrefix)\(sq.aliveCount)"
                nextColor = NSColor(calibratedWhite: 0.88, alpha: 0.80)
            }
            if marker.cachedBadgeText != nextText {
                marker.cachedBadgeText = nextText
                marker.badgeLabel.text = nextText
                marker.badgeBg.size.width = max(68, CGFloat(nextText.count) * 10.5 + 16)
            }
            marker.badgeLabel.fontColor = nextColor

            if isSel && !sq.isRouting && sq.order != .holdGround {
                let navLogicX = sq.waypoints.first?.x ?? sq.targetX
                let navLogicY = sq.waypoints.first?.y ?? sq.targetY
                let destScene = scenePoint(fromLogicX: navLogicX, logicY: navLogicY)
                let dx = destScene.x - anchorPt.x
                let dy = destScene.y - anchorPt.y
                let dist = hypot(dx, dy)
                if dist > 28.0 {
                    marker.orderLine.isHidden = false
                    marker.orderLine.size = CGSize(width: dist, height: 2.6)
                    marker.orderLine.zRotation = atan2(dy, dx)
                } else {
                    marker.orderLine.isHidden = true
                }
            } else {
                marker.orderLine.isHidden = true
            }
        }

        // 同步 600 名重装火柴人军团士兵姿态
        for i in 0..<soldierPoolNodes.count {
            let vNode = soldierPoolNodes[i]
            let s = engine.soldiers[i]
            guard s.isActive else {
                vNode.root.isHidden = true
                continue
            }
            if s.side == .enemy && !s.isVisibleToOpponent {
                vNode.root.isHidden = true
                continue
            }
            let pos = scenePoint(fromLogicX: s.x, logicY: s.y)
            if !visibleRect.contains(pos) {
                vNode.root.isHidden = true
                continue
            }

            vNode.root.isHidden = false
            vNode.root.position = pos
            // Y 排序增强前后景遮挡立体感
            vNode.root.zPosition = CGFloat((worldHeight - pos.y) * 0.001)
            vNode.root.alpha = s.isStealthed ? 0.48 : 1.0

            if vNode.cachedUnitType != s.unitType || vNode.cachedFaction != s.faction {
                configureSoldierStaticAppearance(vNode, soldier: s, atlas: atlas)
            }

            let isUnitSelected = s.side == .player && selectedSet.contains(s.squadId)
            vNode.selectFootRing.isHidden = !isUnitSelected || isFarLod

            // 负伤单位实时显示精致微缩血条
            let hpRatio = s.hp / max(1.0, s.maxHp)
            if !isFarLod && hpRatio < 0.97 && hpRatio > 0.0 {
                vNode.hpBarBg.isHidden = false
                vNode.hpBarFill.isHidden = false
                vNode.hpBarFill.size.width = 16.5 * CGFloat(max(0.05, hpRatio))
                vNode.hpBarFill.color = hpRatio > 0.5 ? .systemGreen : (hpRatio > 0.25 ? .systemOrange : .systemRed)
            } else {
                vNode.hpBarBg.isHidden = true
                vNode.hpBarFill.isHidden = true
            }

            let baseScale: CGFloat = s.unitType == .shuangyuanGiantBreaker ? 1.42 : 1.06
            let faceRight = cos(s.facingRadians) >= 0.0
            vNode.root.xScale = faceRight ? baseScale : -baseScale
            vNode.root.yScale = baseScale

            if isFarLod {
                vNode.legLeft.isHidden = true
                vNode.legRight.isHidden = true
                vNode.armMain.isHidden = true
                vNode.shieldNode.isHidden = true
                vNode.bannerPole.isHidden = !s.isBannerBearer
                vNode.bannerCloth.isHidden = !s.isBannerBearer
                continue
            }

            let isSiege = (s.category == .siege)
            vNode.legLeft.isHidden = isSiege
            vNode.legRight.isHidden = isSiege
            vNode.armMain.isHidden = isSiege
            vNode.bannerPole.isHidden = !s.isBannerBearer
            vNode.bannerCloth.isHidden = !s.isBannerBearer

            let inTestudo = s.squadId >= 0 && s.squadId < engine.squads.count && engine.squads[s.squadId].formation == .testudo
            if inTestudo && !isSiege {
                vNode.shieldNode.isHidden = false
                vNode.shieldNode.texture = atlas.paviseShield
                vNode.shieldNode.size = CGSize(width: 15.5, height: 22.0)
                vNode.shieldNode.position = CGPoint(x: 5.5, y: 12.5)
            }

            let phase = CGFloat(s.animPhase)
            let localAimAngle: CGFloat = {
                let dyScene = CGFloat(-sin(s.facingRadians))
                let dxAbs = max(0.15, abs(CGFloat(cos(s.facingRadians))))
                return atan2(dyScene, dxAbs)
            }()

            vNode.torso.zRotation = 0.0
            vNode.root.zRotation = 0.0
            vNode.stateDot.isHidden = true

            switch s.actionState {
            case .idleReady:
                let breath = sin(phase * 0.5) * 0.06
                vNode.legLeft.zRotation = -0.08
                vNode.legRight.zRotation = 0.08
                vNode.armMain.zRotation = localAimAngle + (s.isBraced ? 0.05 : breath)

            case .marchRun:
                let swing = sin(phase * 1.4) * 0.55
                vNode.legLeft.zRotation = swing
                vNode.legRight.zRotation = -swing
                vNode.armMain.zRotation = localAimAngle - swing * 0.35
                vNode.torso.zRotation = -0.08

            case .chargeSprint:
                let gallop = sin(phase * 2.2) * 0.72
                vNode.legLeft.zRotation = gallop
                vNode.legRight.zRotation = -gallop
                vNode.torso.zRotation = -0.26
                vNode.armMain.zRotation = localAimAngle - 0.12
                vNode.stateDot.isHidden = false
                vNode.stateDot.color = .systemOrange

            case .meleeWindup:
                vNode.legLeft.zRotation = -0.22
                vNode.legRight.zRotation = 0.25
                vNode.armMain.zRotation = localAimAngle + 0.95

            case .meleeStrike:
                vNode.legLeft.zRotation = 0.30
                vNode.legRight.zRotation = -0.28
                vNode.torso.zRotation = -0.18
                vNode.armMain.zRotation = localAimAngle - 0.58

            case .rangedDrawFire:
                vNode.legLeft.zRotation = -0.16
                vNode.legRight.zRotation = 0.16
                vNode.armMain.zRotation = localAimAngle + 0.12

            case .shieldBlock:
                vNode.legLeft.zRotation = -0.24
                vNode.legRight.zRotation = 0.24
                vNode.armMain.zRotation = localAimAngle + 0.35
                if s.isReloadingBackShield {
                    vNode.shieldNode.position = CGPoint(x: -5.5, y: 8.0)
                } else if !inTestudo {
                    vNode.shieldNode.position = CGPoint(x: 6.5, y: 8.0)
                }

            case .staggerHit:
                vNode.torso.zRotation = 0.38
                vNode.armMain.zRotation = 0.75
                vNode.stateDot.isHidden = false
                vNode.stateDot.color = .systemYellow

            case .routPanic:
                let panic = sin(phase * 2.5) * 0.68
                vNode.legLeft.zRotation = panic
                vNode.legRight.zRotation = -panic
                vNode.armMain.zRotation = 1.25 + panic * 0.3
                vNode.shieldNode.isHidden = true
                vNode.stateDot.isHidden = false
                vNode.stateDot.color = .white

            case .dyingFall, .fallenCorpse:
                vNode.root.zRotation = .pi * 0.46
                vNode.legLeft.zRotation = 0.1
                vNode.legRight.zRotation = -0.1
            }
        }

        if let pHeroNode = playerHeroNode {
            syncSingleHeroNode(pHeroNode, hero: engine.playerHero, atlas: atlas)
        }
        if let eHeroNode = enemyHeroNode {
            syncSingleHeroNode(eHeroNode, hero: engine.enemyHero, atlas: atlas)
        }

        for i in 0..<projectilePoolNodes.count {
            let pNode = projectilePoolNodes[i]
            let proj = engine.projectiles[i]
            guard proj.isActive else {
                pNode.isHidden = true
                continue
            }
            let t = max(0.0, min(1.0, proj.flightElapsed / max(0.05, proj.flightDuration)))
            let groundPt = scenePoint(fromLogicX: proj.x, logicY: proj.y)
            let loft = CGFloat(4.0 * proj.arcHeight * t * (1.0 - t))
            let visualPt = CGPoint(x: groundPt.x, y: groundPt.y + loft)
            if !visibleRect.contains(visualPt) {
                pNode.isHidden = true
                continue
            }

            pNode.isHidden = false
            pNode.position = visualPt

            switch proj.kind {
            case .trebuchetBoulder:
                pNode.texture = atlas.boulderProjectile
                pNode.size = CGSize(width: 24, height: 24)
                pNode.color = .white
                pNode.zRotation += 0.22
            case .thunderGrenade:
                pNode.texture = atlas.sparkStar
                pNode.size = CGSize(width: 19, height: 19)
                pNode.color = .systemOrange
                pNode.zRotation += 0.30
            default:
                pNode.texture = atlas.arrowProjectile
                let dLoftDt = 4.0 * proj.arcHeight * (1.0 - 2.0 * t)
                let dxScene = proj.vx * proj.flightDuration
                let dyScene = -proj.vy * proj.flightDuration + dLoftDt
                pNode.zRotation = CGFloat(atan2(dyScene, dxScene))

                switch proj.kind {
                case .ballistaBolt:
                    pNode.size = CGSize(width: 30, height: 7.5)
                    pNode.color = .systemYellow
                case .heroHeavyArrow:
                    pNode.size = CGSize(width: 28, height: 7.5)
                    pNode.color = .systemCyan
                case .venomArrow:
                    pNode.size = CGSize(width: 22, height: 6.0)
                    pNode.color = .systemGreen
                case .crossbowBolt:
                    pNode.size = CGSize(width: 21, height: 6.0)
                    pNode.color = NSColor(calibratedWhite: 0.96, alpha: 1.0)
                default:
                    pNode.size = CGSize(width: 20, height: 5.5)
                    pNode.color = proj.side == .player
                        ? NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.56, alpha: 0.98)
                        : NSColor(calibratedRed: 0.80, green: 0.90, blue: 1.0, alpha: 0.98)
                }
            }
        }

        for i in 0..<corpsePoolNodes.count {
            let cNode = corpsePoolNodes[i]
            let dec = engine.corpseDecals[i]
            guard dec.isActive else {
                cNode.isHidden = true
                continue
            }
            let pt = scenePoint(fromLogicX: dec.x, logicY: dec.y)
            if !visibleRect.contains(pt) {
                cNode.isHidden = true
                continue
            }
            cNode.isHidden = false
            cNode.position = pt
            cNode.zRotation = CGFloat(-dec.rotationRadians)
            let baseCol = factionPrimaryColors[dec.faction] ?? .gray
            cNode.color = baseCol.withAlphaComponent(0.45)
        }

        for i in 0..<particlePoolNodes.count {
            let fxNode = particlePoolNodes[i]
            let fx = engine.effectParticles[i]
            let wasActive = lastRenderedParticleCursorSnapshot[i]
            lastRenderedParticleCursorSnapshot[i] = fx.isActive

            guard fx.isActive else {
                fxNode.isHidden = true
                continue
            }
            let pt = scenePoint(fromLogicX: fx.x, logicY: fx.y)
            if !visibleRect.contains(pt) {
                fxNode.isHidden = true
                continue
            }
            fxNode.isHidden = false
            fxNode.position = pt
            let progress = CGFloat(1.0 - max(0.0, min(1.0, fx.lifetime / max(0.05, fx.maxLifetime))))

            switch fx.kind {
            case .shieldSpark:
                fxNode.texture = atlas.sparkStar
                fxNode.color = .systemYellow
                fxNode.size = CGSize(width: 17, height: 17)
                fxNode.alpha = 1.0 - progress
            case .parryFlash:
                fxNode.texture = atlas.sparkStar
                fxNode.color = .white
                let sz = 30.0 + progress * 28.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 1.0 - progress
            case .bloodSlash:
                fxNode.texture = atlas.slashWave
                fxNode.color = fx.isCritical ? .systemOrange : .systemRed
                fxNode.size = CGSize(width: 22, height: 18)
                fxNode.alpha = 0.92 * (1.0 - progress)
                if showDamageNumbers && !wasActive && (fx.isCritical || fx.numericValue >= 32) {
                    spawnFloatingDamageText(value: fx.numericValue, isCritical: fx.isCritical, at: pt)
                }
            case .explosionFire:
                fxNode.texture = atlas.softGlowHalo
                fxNode.color = .systemOrange
                let sz = 46.0 + progress * 115.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 0.88 * (1.0 - progress)
            case .boulderDust:
                fxNode.texture = atlas.softGlowHalo
                fxNode.color = NSColor(calibratedRed: 0.85, green: 0.74, blue: 0.56, alpha: 1.0)
                let sz = 48.0 + progress * 120.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 0.78 * (1.0 - progress)
            case .warCryWave:
                fxNode.texture = atlas.circleRing
                fxNode.color = .systemYellow
                let sz = 52.0 + progress * 600.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 0.88 * (1.0 - progress)
            case .damageNumber:
                fxNode.isHidden = true
            }
        }
    }

    private func spawnFloatingDamageText(value: Int, isCritical: Bool, at point: CGPoint) {
        guard !damageLabelPool.isEmpty else { return }
        let lbl = damageLabelPool[damageLabelCursor % damageLabelPool.count]
        damageLabelCursor += 1
        lbl.removeAllActions()
        lbl.text = isCritical ? "暴击 -\(value)!" : "-\(value)"
        lbl.fontSize = isCritical ? 16 : 12.5
        lbl.fontColor = isCritical ? .systemYellow : .white
        lbl.position = CGPoint(x: point.x, y: point.y + 20)
        lbl.alpha = 1.0
        lbl.isHidden = false
        lbl.run(
            SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: 0, y: 28, duration: 0.50),
                    SKAction.fadeOut(withDuration: 0.50)
                ]),
                SKAction.hide()
            ])
        )
    }

    private func configureSoldierStaticAppearance(
        _ vNode: PooledSoldierNode,
        soldier s: SoldierEntity,
        atlas: StickmanTextureAtlas
    ) {
        vNode.cachedUnitType = s.unitType
        vNode.cachedFaction = s.faction

        let prim = factionPrimaryColors[s.faction] ?? .systemRed
        let acc = factionAccentColors[s.faction] ?? .white
        let limbCol = s.side == .player
            ? NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.86, alpha: 1.0)
            : NSColor(calibratedRed: 0.80, green: 0.78, blue: 0.74, alpha: 1.0)

        vNode.torso.color = prim
        vNode.legLeft.color = limbCol
        vNode.legRight.color = limbCol
        vNode.armMain.color = limbCol
        vNode.bannerCloth.color = prim
        vNode.capeNode.color = prim

        // 按兵种职能选择罗马百夫长羽冠盔、游牧尖盔或王牌统领兜鍪，并为精锐/骑兵挂载飘逸披风
        let isElite = s.unitType.rawValue.contains("_") && s.unitType != .shieldSwordsman && s.unitType != .compositeArcher && s.unitType != .lightCavalry && s.unitType != .greatAxeman
        vNode.capeNode.isHidden = !(isElite || s.category == .cavalry || s.isBannerBearer)
        if isElite || s.isBannerBearer {
            vNode.head.texture = atlas.legionCrestHead
            vNode.head.color = acc
        } else if s.category == .ranged || s.category == .cavalry {
            vNode.head.texture = atlas.nomadHelmHead
            vNode.head.color = limbCol
        } else if s.unitType == .sapper {
            vNode.head.texture = atlas.circleFilled
            vNode.head.color = NSColor(calibratedRed: 0.92, green: 0.80, blue: 0.58, alpha: 1.0)
        } else {
            vNode.head.texture = atlas.legionCrestHead
            vNode.head.color = limbCol
        }

        let isCav = (s.category == .cavalry)
        let isSiege = (s.category == .siege)
        vNode.mountNode.isHidden = !isCav
        vNode.siegeNode.isHidden = !isSiege
        if isCav {
            vNode.mountNode.color = s.unitType == .shamoMamelukeCamel
                ? NSColor(calibratedRed: 0.85, green: 0.70, blue: 0.42, alpha: 1.0)
                : (s.unitType == .xuanjiaCataphract ? (prim.blended(withFraction: 0.45, of: .darkGray) ?? prim) : NSColor(calibratedRed: 0.52, green: 0.36, blue: 0.22, alpha: 1.0))
        }
        if isSiege {
            vNode.siegeNode.color = s.unitType == .trebuchet
                ? NSColor(calibratedRed: 0.68, green: 0.48, blue: 0.26, alpha: 1.0)
                : NSColor(calibratedRed: 0.58, green: 0.54, blue: 0.48, alpha: 1.0)
        }

        switch s.unitType {
        case .pikeman, .yanlongHalberdGrenadier, .xuanjiaCataphract:
            vNode.weaponNode.texture = atlas.pikeShaft
            vNode.weaponNode.size = CGSize(width: 36, height: 7.0)
            vNode.weaponNode.color = acc
        case .greatAxeman, .shuangyuanGiantBreaker, .xueyueWardrumBerserker:
            vNode.weaponNode.texture = atlas.greatAxe
            vNode.weaponNode.size = CGSize(width: 28, height: 16)
            vNode.weaponNode.color = acc
        case .compositeArcher, .canglangKeshigHorseArcher, .wulinShadowSniper:
            vNode.weaponNode.texture = atlas.bowArc
            vNode.weaponNode.size = CGSize(width: 15, height: 21)
            vNode.weaponNode.color = acc
        case .tieyingPaviseCrossbow, .ballista:
            vNode.weaponNode.texture = atlas.crossbowFrame
            vNode.weaponNode.size = CGSize(width: 20, height: 16)
            vNode.weaponNode.color = acc
        default:
            vNode.weaponNode.texture = atlas.saberBlade
            vNode.weaponNode.size = CGSize(width: 25, height: 8.5)
            vNode.weaponNode.color = NSColor(calibratedWhite: 0.96, alpha: 1.0)
        }

        if s.shieldRangedBlock >= 0.28 {
            vNode.shieldNode.isHidden = false
            let usePavise = (s.unitType == .shieldSwordsman || s.unitType == .tieyingPaviseCrossbow || s.unitType == .yanlongHalberdGrenadier)
            vNode.shieldNode.texture = usePavise ? atlas.paviseShield : atlas.roundShield
            vNode.shieldNode.size = usePavise ? CGSize(width: 13.5, height: 19.5) : CGSize(width: 15.0, height: 15.0)
            vNode.shieldNode.position = CGPoint(x: 6.0, y: 7.5)
            vNode.shieldNode.color = acc.blended(withFraction: 0.55, of: prim) ?? prim
        } else {
            vNode.shieldNode.isHidden = true
        }
    }

    private func syncSingleHeroNode(_ node: PooledHeroNode, hero: HeroCommanderEntity, atlas: StickmanTextureAtlas) {
        guard hero.vitalState != .fallenMartyred else {
            node.root.isHidden = true
            return
        }
        node.root.isHidden = false
        node.root.position = scenePoint(fromLogicX: hero.x, logicY: hero.y)
        node.root.alpha = hero.vitalState == .recoveringInCamp ? 0.38 : 1.0

        let faceRight = cos(hero.facingRadians) >= 0.0
        node.torso.xScale = faceRight ? 1.0 : -1.0
        node.cape.xScale = faceRight ? 1.0 : -1.0
        node.weaponArm.xScale = faceRight ? 1.0 : -1.0

        let dyScene = CGFloat(-sin(hero.facingRadians))
        let dxAbs = max(0.15, abs(CGFloat(cos(hero.facingRadians))))
        let localAng = atan2(dyScene, dxAbs)
        node.weaponArm.zRotation = faceRight ? localAng : -localAng

        switch hero.activeWeapon {
        case .commandSaber:
            node.weaponSprite.texture = atlas.saberBlade
            node.weaponSprite.size = CGSize(width: 34, height: 11)
            node.shieldSprite.isHidden = false
            node.shieldSprite.position = CGPoint(x: faceRight ? 9 : -9, y: 10)
            node.shieldSprite.color = hero.isInPerfectParryWindow ? .white : (hero.isBlocking ? .systemCyan : .systemYellow)
        case .breakerSpear:
            node.weaponSprite.texture = atlas.pikeShaft
            node.weaponSprite.size = CGSize(width: 46, height: 8.5)
            node.shieldSprite.isHidden = true
        case .heavyWarbow:
            node.weaponSprite.texture = atlas.bowArc
            node.weaponSprite.size = CGSize(width: 19, height: 26)
            node.shieldSprite.isHidden = true
        }

        let hpRatio = CGFloat(max(0.0, min(1.0, hero.hp / max(1.0, hero.maxHp))))
        node.hpFill.size.width = 44.0 * hpRatio
        node.hpFill.color = hero.vitalState == .woundedWeakened ? .systemOrange : .systemGreen

        if hero.bowChargeElapsed > 0.02 {
            node.bowChargeBar.isHidden = false
            node.bowChargeBar.size.width = 44.0 * CGFloat(min(1.0, hero.bowChargeElapsed / 0.90))
        } else {
            node.bowChargeBar.isHidden = true
        }

        node.auraRing.size = hero.ironBulwarkRemainingSec > 0.0
            ? CGSize(width: 66, height: 66)
            : CGSize(width: 48, height: 48)
    }

    // MARK: - 相机缩放与边界钳制

    public func resetCameraToCenter() {
        if engine.controlMode == .heroAction && engine.playerHero.isActiveOnField {
            worldCamera.position = scenePoint(fromLogicX: engine.playerHero.x, logicY: engine.playerHero.y)
            worldCamera.setScale(0.88)
        } else {
            worldCamera.position = CGPoint(x: worldWidth * 0.5, y: worldHeight * 0.5)
            worldCamera.setScale(1.12)
        }
        clampCameraPosition()
    }

    public func adjustZoom(byFactor deltaFactor: CGFloat) {
        let minScale = CGFloat(1.0 / GameConstants.battlefieldZoomMax)
        let maxScale = CGFloat(1.0 / GameConstants.battlefieldZoomMin)
        let nextScale = max(minScale, min(maxScale, worldCamera.xScale * deltaFactor))
        worldCamera.setScale(nextScale)
        clampCameraPosition()
    }

    private func panCamera(dx: CGFloat, dy: CGFloat) {
        worldCamera.position.x += dx
        worldCamera.position.y += dy
        clampCameraPosition()
    }

    private func clampCameraPosition() {
        worldCamera.position.x = max(0, min(CGFloat(worldWidth), worldCamera.position.x))
        worldCamera.position.y = max(0, min(CGFloat(worldHeight), worldCamera.position.y))
    }

    // MARK: - macOS 原生键鼠、建筑选址落盘与《罗马全面战争》右键拖拽拉阵线交互

    public override func mouseMoved(with event: NSEvent) {
        let pt = event.location(in: self)
        mouseHoverScenePoint = pt
        heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
    }

    public override func mouseDown(with event: NSEvent) {
        view?.window?.makeFirstResponder(self)
        let pt = event.location(in: self)
        mouseHoverScenePoint = pt

        // 若正处于 RTS 建筑选址预览模式：左键落盘建造！
        if let buildKind = pendingBuildKind {
            let lPt = logicCoordinates(fromScenePoint: pt)
            if engine.constructBuilding(side: .player, kind: buildKind, atX: lPt.x, atY: lPt.y) {
                syncDynamicStructurePool()
                if !event.modifierFlags.contains(.shift) {
                    cancelPendingBuildPlacement()
                }
                onInteractionFeedback?("🏗 已落盘营建【\(buildKind.displayName)】，民夫正赶往工地施工！（按住 Shift 可连续选址多座）")
                drainAndPlayAudioCues()
                pushUiSyncNow()
            } else {
                onInteractionFeedback?("❌ 此处无法营建【\(buildKind.displayName)】（需位于己方控制区平整地面，避开河流与已有建筑）")
            }
            return
        }

        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
            heroMouseLeftHeld = true
            return
        }

        if event.modifierFlags.contains(.option) {
            isOptionPanningDrag = true
            dragStartScenePoint = pt
            return
        }

        isOptionPanningDrag = false
        dragStartScenePoint = pt
        marqueeFillNode.position = pt
        marqueeFillNode.size = .zero
        marqueeFillNode.isHidden = false
        marqueeBorderTop.position = pt
        marqueeBorderTop.size = .zero
        marqueeBorderTop.isHidden = false
    }

    public override func mouseDragged(with event: NSEvent) {
        let current = event.location(in: self)
        mouseHoverScenePoint = current
        if pendingBuildKind != nil { return }

        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: current)
            heroMouseLeftHeld = true
            return
        }

        if isOptionPanningDrag {
            let scale = worldCamera.xScale
            panCamera(dx: -event.deltaX * scale, dy: event.deltaY * scale)
            return
        }

        guard let start = dragStartScenePoint else { return }
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        let midX = (start.x + current.x) * 0.5
        let midY = (start.y + current.y) * 0.5
        marqueeFillNode.position = CGPoint(x: midX, y: midY)
        marqueeFillNode.size = CGSize(width: width, height: height)
        marqueeBorderTop.position = CGPoint(x: midX, y: max(start.y, current.y))
        marqueeBorderTop.size = CGSize(width: width, height: 2.0)
    }

    public override func mouseUp(with event: NSEvent) {
        let end = event.location(in: self)
        if pendingBuildKind != nil { return }

        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: end)
            heroMouseLeftHeld = false
            return
        }

        if isOptionPanningDrag {
            isOptionPanningDrag = false
            dragStartScenePoint = nil
            return
        }

        guard let start = dragStartScenePoint else { return }
        marqueeFillNode.isHidden = true
        marqueeBorderTop.isHidden = true
        dragStartScenePoint = nil

        let shiftHeld = event.modifierFlags.contains(.shift)
        let dragDist = hypot(end.x - start.x, end.y - start.y)
        let endLogic = logicCoordinates(fromScenePoint: end)

        if dragDist < 10.0 {
            if let pickedId = engine.pickSquadAtPoint(x: endLogic.x, y: endLogic.y, tolerance: 62.0, side: .player) {
                BattleAudioEngine.shared.play(.uiClick)
                if event.clickCount >= 2 {
                    let targetUnitType = engine.squads[pickedId].primaryUnitType
                    selectedSquadIds = engine.squads
                        .filter { $0.side == .player && $0.aliveCount > 0 && !$0.isRouting && $0.primaryUnitType == targetUnitType }
                        .map(\.id)
                    let uName = UnitConfig.stats(for: targetUnitType)?.name ?? ""
                    onInteractionFeedback?("双击全选同类军团【\(uName)】（共 \(selectedSquadIds.count) 支编队）")
                } else if shiftHeld {
                    if let idx = selectedSquadIds.firstIndex(of: pickedId) {
                        selectedSquadIds.remove(at: idx)
                    } else {
                        selectedSquadIds.append(pickedId)
                    }
                    onInteractionFeedback?("Shift 编队加减选：当前选中 \(selectedSquadIds.count) 支编队")
                } else {
                    selectedSquadIds = [pickedId]
                    let sq = engine.squads[pickedId]
                    let uName = UnitConfig.stats(for: sq.primaryUnitType)?.name ?? ""
                    onInteractionFeedback?("已点选【\(uName)】（存活 \(sq.aliveCount) · 士气 \(Int(sq.morale)) · \(sq.formation.displayName)）")
                }
            }
        } else {
            let startLogic = logicCoordinates(fromScenePoint: start)
            let boxed = engine.selectSquadsInRect(
                minX: startLogic.x,
                minY: startLogic.y,
                maxX: endLogic.x,
                maxY: endLogic.y,
                side: .player
            )
            if !boxed.isEmpty {
                BattleAudioEngine.shared.play(.uiClick)
                if shiftHeld {
                    selectedSquadIds = Set(selectedSquadIds).union(boxed).sorted()
                } else {
                    selectedSquadIds = boxed
                }
                onInteractionFeedback?("已框选 \(selectedSquadIds.count) 支军团 —— 右键点击进军，或【按住右键拖拽】拉设古罗马横列战线！")
            }
        }
        pushUiSyncNow()
    }

    public override func rightMouseDown(with event: NSEvent) {
        if pendingBuildKind != nil {
            cancelPendingBuildPlacement()
            onInteractionFeedback?("已取消建筑选址")
            return
        }

        let pt = event.location(in: self)
        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
            heroMouseRightHeld = true
            if engine.playerHero.activeWeapon == .heavyWarbow {
                heroMouseLeftHeld = false
                onInteractionFeedback?("已收弦取消百石硬弓蓄力")
            } else if engine.playerHero.activeWeapon == .commandSaber {
                BattleAudioEngine.shared.play(.swordClash, volumeScale: 0.45)
                onInteractionFeedback?("🛡 主帅举盾格挡（前 0.25s 精准弹反窗口可零伤震晕近身敌兵 1.5s）！")
            }
            return
        }

        rightDragStartScenePoint = pt
        deploymentLineNode.position = pt
        deploymentLineNode.size = .zero
        deploymentLineNode.isHidden = true
    }

    public override func rightMouseDragged(with event: NSEvent) {
        let pt = event.location(in: self)
        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
            heroMouseRightHeld = true
            return
        }
        guard let start = rightDragStartScenePoint else { return }
        let dx = pt.x - start.x
        let dy = pt.y - start.y
        let len = hypot(dx, dy)
        if len >= 28.0 {
            deploymentLineNode.isHidden = false
            deploymentLineNode.position = start
            deploymentLineNode.size = CGSize(width: len, height: 5.5)
            deploymentLineNode.zRotation = atan2(dy, dx)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        let endPt = event.location(in: self)
        if engine.controlMode == .heroAction {
            heroMouseRightHeld = false
            return
        }

        deploymentLineNode.isHidden = true
        let startPt = rightDragStartScenePoint ?? endPt
        rightDragStartScenePoint = nil

        let targets = effectiveTargetSquadIds()
        guard !targets.isEmpty else {
            onInteractionFeedback?("当前无可调度编队")
            return
        }

        let dragLen = hypot(endPt.x - startPt.x, endPt.y - startPt.y)
        let appendWp = event.modifierFlags.contains(.shift)

        // 《罗马全面战争》式右键拖拽拉阵线：当拖拽长度 >= 36px 时，按拖拽线段均匀排布多支军团并自动设定垂直迎敌朝向与阵宽！
        if dragLen >= 36.0 && !appendWp {
            let startLogic = logicCoordinates(fromScenePoint: startPt)
            let endLogic = logicCoordinates(fromScenePoint: endPt)
            let lineDx = endLogic.x - startLogic.x
            let lineDy = endLogic.y - startLogic.y
            // 战线法向量（朝向最近敌军方向）
            var normalX = -lineDy
            var normalY = lineDx
            let midX = (startLogic.x + endLogic.x) * 0.5
            let midY = (startLogic.y + endLogic.y) * 0.5
            let eCamp = engine.baseCampCoordinates(for: .enemy)
            if normalX * (eCamp.x - midX) + normalY * (eCamp.y - midY) < 0.0 {
                normalX = -normalX
                normalY = -normalY
            }
            let explicitFacing = atan2(normalY, normalX)
            let perSquadSpan = dragLen / CGFloat(max(1, targets.count))
            let spreadMult = max(0.65, min(2.10, Double(perSquadSpan) / 140.0))

            for (idx, sqId) in targets.enumerated() {
                let ratio = targets.count == 1 ? 0.5 : Double(idx) / Double(targets.count - 1)
                let slotX = startLogic.x + lineDx * ratio
                let slotY = startLogic.y + lineDy * ratio
                let needAdvance = engine.squads[sqId].order == .holdGround || engine.squads[sqId].order == .retreat
                engine.issueSquadCommand(
                    SquadCommandRequest(
                        squadIds: [sqId],
                        order: needAdvance ? .advance : nil,
                        targetWorldX: slotX,
                        targetWorldY: slotY,
                        appendWaypoint: false,
                        explicitFacingRadians: explicitFacing,
                        lineSpreadMultiplier: spreadMult
                    )
                )
            }
            orderMarkerNode.text = "⚔️ 战线展开 (\(targets.count) 军团)"
            orderMarkerNode.fontColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.32, alpha: 0.98)
            orderMarkerNode.position = CGPoint(x: (startPt.x + endPt.x) * 0.5, y: (startPt.y + endPt.y) * 0.5)
            orderMarkerNode.isHidden = false
            orderMarkerFadeTimer = 1.8
            onInteractionFeedback?("📐 已按拖拽防线排布 \(targets.count) 支军团横列展开（阵宽倍率 \(String(format: "%.1fx", spreadMult))）！")
            drainAndPlayAudioCues()
            pushUiSyncNow()
            return
        }

        let logicPt = logicCoordinates(fromScenePoint: endPt)
        if let enemyHit = engine.pickEnemyTargetAtPoint(x: logicPt.x, y: logicPt.y, tolerance: 72.0) {
            let hasFlankSelected = targets.contains { engine.squads[$0].order == .flank || engine.squads[$0].order == .pincerEncircle }
            let attackOrder: TacticalOrder? = hasFlankSelected ? nil : .advance
            engine.issueSquadCommand(
                SquadCommandRequest(
                    squadIds: targets,
                    order: attackOrder,
                    targetWorldX: enemyHit.x,
                    targetWorldY: enemyHit.y,
                    appendWaypoint: appendWp
                )
            )
            orderMarkerNode.text = "⚔️ 集火 \(enemyHit.label)"
            orderMarkerNode.fontColor = .systemRed
            orderMarkerNode.position = scenePoint(fromLogicX: enemyHit.x, logicY: enemyHit.y)
            orderMarkerNode.isHidden = false
            orderMarkerFadeTimer = 1.8
            onInteractionFeedback?("🎯 右键锁定进攻目标 -> \(enemyHit.label)")
        } else {
            let needSwitchFromHold = targets.allSatisfy { engine.squads[$0].order == .holdGround || engine.squads[$0].order == .retreat }
            engine.issueSquadCommand(
                SquadCommandRequest(
                    squadIds: targets,
                    order: needSwitchFromHold ? .advance : nil,
                    targetWorldX: logicPt.x,
                    targetWorldY: logicPt.y,
                    appendWaypoint: appendWp
                )
            )
            orderMarkerNode.text = appendWp ? "⊕ 迂回航点" : "⊕ 进军目标"
            orderMarkerNode.fontColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.32, alpha: 0.96)
            orderMarkerNode.position = endPt
            orderMarkerNode.isHidden = false
            orderMarkerFadeTimer = 1.6
            onInteractionFeedback?(
                appendWp
                    ? "Shift+右键追加迂回航点 (\(Int(logicPt.x)), \(Int(logicPt.y)))"
                    : "右键下令 \(targets.count) 支编队向 (\(Int(logicPt.x)), \(Int(logicPt.y))) 列阵推进"
            )
        }
        drainAndPlayAudioCues()
        pushUiSyncNow()
    }

    public override func otherMouseDragged(with event: NSEvent) {
        let scale = worldCamera.xScale
        panCamera(dx: -event.deltaX * scale, dy: event.deltaY * scale)
    }

    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || !event.hasPreciseScrollingDeltas {
            let rawDelta = invertScrollZoom ? -event.scrollingDeltaY : event.scrollingDeltaY
            guard abs(rawDelta) > 0.01 else { return }
            let zoomDelta: CGFloat = rawDelta > 0 ? 0.91 : 1.09
            adjustZoom(byFactor: zoomDelta)
        } else if engine.controlMode == .rtsCommander {
            let scale = worldCamera.xScale
            panCamera(dx: -event.scrollingDeltaX * scale * 1.4, dy: event.scrollingDeltaY * scale * 1.4)
        }
    }

    public override func magnify(with event: NSEvent) {
        let factor = max(0.75, min(1.35, 1.0 - event.magnification))
        adjustZoom(byFactor: factor)
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            if pendingBuildKind != nil {
                cancelPendingBuildPlacement()
                onInteractionFeedback?("已取消建筑选址")
                return
            }
            onRequestToggleEscapeMenu?()
            return
        }
        if event.keyCode == 48 { // Tab
            if !event.isARepeat {
                _ = requestToggleControlMode()
            }
            return
        }

        pressedKeyCodes.insert(event.keyCode)
        guard !event.isARepeat else { return }

        if event.keyCode == 11 { // B -> 警戒钟
            toggleGarrisonBell()
            return
        }
        if event.keyCode == 47 { // `.` -> 查找空闲民夫
            focusIdleOrNearestSapper()
            return
        }

        if event.modifierFlags.contains(.control), let grp = Self.groupNumberForNumberKey(event.keyCode) {
            let valid = effectiveTargetSquadIds()
            controlGroups[grp] = valid
            BattleAudioEngine.shared.play(.uiClick)
            onInteractionFeedback?("已将当前 \(valid.count) 支编队绑定至【第 \(grp) 军团 (F\(grp))】")
            return
        }
        if let fGroup = Self.groupNumberForFunctionKey(event.keyCode) {
            handleRecallControlGroup(fGroup, now: event.timestamp)
            return
        }

        switch engine.controlMode {
        case .rtsCommander:
            if event.modifierFlags.contains(.command) && event.keyCode == 0 {
                selectAllCombatSquads()
                return
            }
            switch event.keyCode {
            case 50: selectAllCombatSquads()
            case 49, 35: toggleBattlePause()
            case 18: applyFormationToSelection(.phalanxRect)
            case 19: applyFormationToSelection(.echelonLine)
            case 20: applyFormationToSelection(.wedgeCharge)
            case 21: applyFormationToSelection(.circleDefense)
            case 23: applyFormationToSelection(.testudo) // 数字键 5 -> 罗马龟甲阵！
            case 4:  beginOrAutoConstructBuilding(.houseQuarter, quickAutoPlace: event.modifierFlags.contains(.shift)) // H -> 快捷造民居
            case 12: applyTacticalOrderToSelection(.advance)
            case 13: applyTacticalOrderToSelection(.holdGround)
            case 14: applyTacticalOrderToSelection(.allOutCharge)
            case 15: applyTacticalOrderToSelection(.retreat)
            case 3:  applyTacticalOrderToSelection(.flank)
            case 5:  applyTacticalOrderToSelection(.pincerEncircle)
            case 6:  applyTacticalOrderToSelection(.feignedRetreat)
            case 7:  applyTacticalOrderToSelection(.ambushHide)
            case 8:  applyTacticalOrderToSelection(.raidSupply)
            case 123, 124, 125, 126: break
            default: super.keyDown(with: event)
            }

        case .heroAction:
            switch event.keyCode {
            case 18: switchHeroWeapon(.commandSaber)
            case 19: switchHeroWeapon(.breakerSpear)
            case 20: switchHeroWeapon(.heavyWarbow)
            case 49: triggerHeroSkill(.breakthroughCharge)
            case 14, 21: triggerHeroSkill(.ironBulwark)
            case 15, 23: triggerHeroSkill(.grandWarCry)
            case 35: toggleBattlePause()
            case 0, 1, 2, 13, 123, 124, 125, 126: break
            default: super.keyDown(with: event)
            }
        }
    }

    public override func keyUp(with event: NSEvent) {
        pressedKeyCodes.remove(event.keyCode)
    }

    private func handleRecallControlGroup(_ groupNumber: Int, now: TimeInterval) {
        let ids = (controlGroups[groupNumber] ?? []).filter {
            $0 >= 0 && $0 < engine.squads.count && engine.squads[$0].aliveCount > 0
        }
        guard !ids.isEmpty else {
            onInteractionFeedback?("第 \(groupNumber) 军团 (F\(groupNumber)) 当前无存活编队")
            return
        }
        selectedSquadIds = ids
        BattleAudioEngine.shared.play(.uiClick)
        let isDoubleTap = (lastGroupKeyNumber == groupNumber) && (now - lastGroupKeyPressTime < 0.38)
        lastGroupKeyNumber = groupNumber
        lastGroupKeyPressTime = now
        if isDoubleTap, let firstId = ids.first {
            let sq = engine.squads[firstId]
            worldCamera.position = scenePoint(fromLogicX: sq.anchorX, logicY: sq.anchorY)
            clampCameraPosition()
            onInteractionFeedback?("已选定并聚焦镜头至【第 \(groupNumber) 军团】")
        } else {
            onInteractionFeedback?("已选定【第 \(groupNumber) 军团 (F\(groupNumber))】（双击聚焦镜头）")
        }
        pushUiSyncNow()
    }

    private static func groupNumberForNumberKey(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        default: return nil
        }
    }

    private static func groupNumberForFunctionKey(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 122: return 1
        case 120: return 2
        case 99:  return 3
        case 118: return 4
        case 96:  return 5
        case 97:  return 6
        default:  return nil
        }
    }
}
