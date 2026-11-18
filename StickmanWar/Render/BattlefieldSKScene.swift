import AppKit
import SpriteKit

/// 推送给战场底部/左侧战术面板的分队轻量状态摘要（4Hz 节流）
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
}

/// 推送给外层 `BattlefieldView` 的组合实时帧摘要（4Hz 节流，严防高频刷新 SwiftUI 视图树）
public struct BattlefieldUiSyncPacket: Sendable, Equatable {
    public let hud: BattleHudSnapshot
    public let playerSquads: [SquadUiBrief]
    public let selectedSquadIds: [Int]
    public let trainingQueueCount: Int
    public let aiDoctrine: BattlefieldAiDoctrine
    public let aiSiegePhase: SiegeTacticalPhase?
    public let heroBreakthroughCd: Double
    public let heroBulwarkCd: Double
    public let heroWarCryCd: Double
    public let heroMedicalRemainingSec: Double
    public let heroBowChargeRatio: Double
    public let heroKills: Int
    public let bloodMoonFervorRemaining: Double
}

// MARK: - 预分配火柴人单兵骨骼关节节点（零 SKShapeNode 路径重建）

@MainActor
private final class PooledSoldierNode {
    let root = SKNode()
    let shadow: SKSpriteNode
    let mountNode: SKSpriteNode
    let siegeNode: SKSpriteNode
    let legLeft: SKSpriteNode
    let legRight: SKSpriteNode
    let torso: SKSpriteNode
    let head: SKSpriteNode
    let armMain: SKSpriteNode
    let weaponNode: SKSpriteNode
    let shieldNode: SKSpriteNode
    let bannerPole: SKSpriteNode
    let bannerCloth: SKSpriteNode
    let stateDot: SKSpriteNode

    var cachedUnitType: UnitTypeId?
    var cachedFaction: FactionId?

    init(atlas: StickmanTextureAtlas) {
        shadow = SKSpriteNode(texture: atlas.circleFilled, color: NSColor(calibratedWhite: 0.0, alpha: 0.32), size: CGSize(width: 16, height: 7))
        shadow.colorBlendFactor = 1.0
        shadow.position = CGPoint(x: 0, y: -9)
        shadow.zPosition = 0.0

        mountNode = SKSpriteNode(texture: atlas.mountBody, color: .brown, size: CGSize(width: 32, height: 18))
        mountNode.colorBlendFactor = 1.0
        mountNode.position = CGPoint(x: 0, y: -4)
        mountNode.zPosition = 0.1
        mountNode.isHidden = true

        siegeNode = SKSpriteNode(texture: atlas.siegeChassis, color: .brown, size: CGSize(width: 42, height: 28))
        siegeNode.colorBlendFactor = 1.0
        siegeNode.position = CGPoint(x: 0, y: 0)
        siegeNode.zPosition = 0.15
        siegeNode.isHidden = true

        legLeft = SKSpriteNode(texture: atlas.whitePixel, color: .white, size: CGSize(width: 2.6, height: 9.5))
        legLeft.colorBlendFactor = 1.0
        legLeft.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        legLeft.position = CGPoint(x: -2.0, y: -1.0)
        legLeft.zPosition = 0.2

        legRight = SKSpriteNode(texture: atlas.whitePixel, color: .white, size: CGSize(width: 2.6, height: 9.5))
        legRight.colorBlendFactor = 1.0
        legRight.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        legRight.position = CGPoint(x: 2.0, y: -1.0)
        legRight.zPosition = 0.2

        torso = SKSpriteNode(texture: atlas.whitePixel, color: .red, size: CGSize(width: 4.5, height: 11.5))
        torso.colorBlendFactor = 1.0
        torso.position = CGPoint(x: 0, y: 4.5)
        torso.zPosition = 0.3

        head = SKSpriteNode(texture: atlas.circleFilled, color: .white, size: CGSize(width: 7.8, height: 7.8))
        head.colorBlendFactor = 1.0
        head.position = CGPoint(x: 0, y: 13.5)
        head.zPosition = 0.4

        armMain = SKSpriteNode(texture: atlas.whitePixel, color: .white, size: CGSize(width: 8.5, height: 2.4))
        armMain.colorBlendFactor = 1.0
        armMain.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        armMain.position = CGPoint(x: 1.0, y: 7.5)
        armMain.zPosition = 0.45

        weaponNode = SKSpriteNode(texture: atlas.saberBlade, color: NSColor(calibratedWhite: 0.90, alpha: 1.0), size: CGSize(width: 18, height: 6))
        weaponNode.colorBlendFactor = 1.0
        weaponNode.anchorPoint = CGPoint(x: 0.15, y: 0.5)
        weaponNode.position = CGPoint(x: 7.5, y: 0.0)
        weaponNode.zPosition = 0.5

        shieldNode = SKSpriteNode(texture: atlas.roundShield, color: .gray, size: CGSize(width: 11, height: 11))
        shieldNode.colorBlendFactor = 1.0
        shieldNode.position = CGPoint(x: 4.5, y: 5.5)
        shieldNode.zPosition = 0.55
        shieldNode.isHidden = true

        bannerPole = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedRed: 0.85, green: 0.72, blue: 0.42, alpha: 1.0), size: CGSize(width: 2.0, height: 28.0))
        bannerPole.colorBlendFactor = 1.0
        bannerPole.position = CGPoint(x: -4.0, y: 14.0)
        bannerPole.zPosition = 0.6
        bannerPole.isHidden = true

        bannerCloth = SKSpriteNode(texture: atlas.bannerFlag, color: .red, size: CGSize(width: 16, height: 11))
        bannerCloth.colorBlendFactor = 1.0
        bannerCloth.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        bannerCloth.position = CGPoint(x: -3.0, y: 24.0)
        bannerCloth.zPosition = 0.62
        bannerCloth.isHidden = true

        stateDot = SKSpriteNode(texture: atlas.circleFilled, color: .white, size: CGSize(width: 5.5, height: 5.5))
        stateDot.colorBlendFactor = 1.0
        stateDot.position = CGPoint(x: 0, y: 20.5)
        stateDot.zPosition = 0.65
        stateDot.isHidden = true

        armMain.addChild(weaponNode)
        root.addChild(shadow)
        root.addChild(mountNode)
        root.addChild(siegeNode)
        root.addChild(legLeft)
        root.addChild(legRight)
        root.addChild(torso)
        root.addChild(head)
        root.addChild(armMain)
        root.addChild(shieldNode)
        root.addChild(bannerPole)
        root.addChild(bannerCloth)
        root.addChild(stateDot)
        root.isHidden = true
    }
}

// MARK: - 预分配主帅英雄专属骨骼节点

@MainActor
private final class PooledHeroNode {
    let root = SKNode()
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
        auraRing = SKSpriteNode(texture: atlas.circleRing, color: accentColor.withAlphaComponent(0.55), size: CGSize(width: 38, height: 38))
        auraRing.colorBlendFactor = 1.0
        auraRing.position = CGPoint(x: 0, y: -4)

        cape = SKSpriteNode(texture: atlas.bannerFlag, color: primaryColor, size: CGSize(width: 18, height: 15))
        cape.colorBlendFactor = 1.0
        cape.anchorPoint = CGPoint(x: 1.0, y: 0.5)
        cape.position = CGPoint(x: -2, y: 6)
        cape.zRotation = .pi * 0.08

        torso = SKSpriteNode(texture: atlas.whitePixel, color: primaryColor, size: CGSize(width: 7.0, height: 16.0))
        torso.colorBlendFactor = 1.0
        torso.position = CGPoint(x: 0, y: 6)

        crownHead = SKSpriteNode(texture: atlas.heroCrownHead, color: accentColor, size: CGSize(width: 17, height: 17))
        crownHead.colorBlendFactor = 1.0
        crownHead.position = CGPoint(x: 0, y: 19)

        weaponArm = SKSpriteNode(texture: atlas.whitePixel, color: .white, size: CGSize(width: 10, height: 3.0))
        weaponArm.colorBlendFactor = 1.0
        weaponArm.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        weaponArm.position = CGPoint(x: 1, y: 10)

        weaponSprite = SKSpriteNode(texture: atlas.saberBlade, color: accentColor, size: CGSize(width: 26, height: 8))
        weaponSprite.colorBlendFactor = 1.0
        weaponSprite.anchorPoint = CGPoint(x: 0.12, y: 0.5)
        weaponSprite.position = CGPoint(x: 8, y: 0)
        weaponArm.addChild(weaponSprite)

        shieldSprite = SKSpriteNode(texture: atlas.roundShield, color: accentColor, size: CGSize(width: 15, height: 15))
        shieldSprite.colorBlendFactor = 1.0
        shieldSprite.position = CGPoint(x: 7, y: 7)

        hpBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.1, alpha: 0.85), size: CGSize(width: 36, height: 4.5))
        hpBg.colorBlendFactor = 1.0
        hpBg.position = CGPoint(x: 0, y: 31)

        hpFill = SKSpriteNode(texture: atlas.whitePixel, color: NSColor.systemGreen, size: CGSize(width: 34, height: 3.0))
        hpFill.colorBlendFactor = 1.0
        hpFill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        hpFill.position = CGPoint(x: -17, y: 31)

        bowChargeBar = SKSpriteNode(texture: atlas.whitePixel, color: NSColor.systemYellow, size: CGSize(width: 0, height: 2.5))
        bowChargeBar.colorBlendFactor = 1.0
        bowChargeBar.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        bowChargeBar.position = CGPoint(x: -17, y: 27)
        bowChargeBar.isHidden = true

        titleLabel = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        titleLabel.text = title
        titleLabel.fontSize = 11
        titleLabel.fontColor = accentColor
        titleLabel.position = CGPoint(x: 0, y: 36)

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

// MARK: - 预分配建筑与军团战术标牌节点

@MainActor
private final class PooledStructureNode {
    let root = SKNode()
    let body: SKSpriteNode
    let hpBg: SKSpriteNode
    let hpFill: SKSpriteNode
    let label: SKLabelNode
    let maxBarWidth: CGFloat
    let baseTitle: String
    var wasRenderedDestroyed: Bool = false

    init(atlas: StickmanTextureAtlas, width: CGFloat, height: CGFloat, color: NSColor, title: String) {
        baseTitle = title
        maxBarWidth = max(44.0, min(120.0, width))
        body = SKSpriteNode(texture: atlas.whitePixel, color: color, size: CGSize(width: width, height: height))
        body.colorBlendFactor = 1.0

        hpBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.08, alpha: 0.85), size: CGSize(width: maxBarWidth + 2, height: 5))
        hpBg.colorBlendFactor = 1.0
        hpBg.position = CGPoint(x: 0, y: height * 0.5 + 10)

        hpFill = SKSpriteNode(texture: atlas.whitePixel, color: .systemGreen, size: CGSize(width: maxBarWidth, height: 3.5))
        hpFill.colorBlendFactor = 1.0
        hpFill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        hpFill.position = CGPoint(x: -maxBarWidth * 0.5, y: height * 0.5 + 10)

        label = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        label.text = title
        label.fontSize = 13
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: height * 0.5 + 18)

        root.addChild(body)
        root.addChild(hpBg)
        root.addChild(hpFill)
        root.addChild(label)
    }
}

@MainActor
private final class PooledSquadMarkerNode {
    let root = SKNode()
    let selectRing: SKSpriteNode
    let moraleBg: SKSpriteNode
    let moraleFill: SKSpriteNode
    let badgeLabel: SKLabelNode
    let orderLine: SKSpriteNode
    var cachedBadgeText: String = ""

    init(atlas: StickmanTextureAtlas) {
        selectRing = SKSpriteNode(texture: atlas.circleRing, color: NSColor.systemGreen.withAlphaComponent(0.70), size: CGSize(width: 84, height: 52))
        selectRing.colorBlendFactor = 1.0
        selectRing.isHidden = true

        moraleBg = SKSpriteNode(texture: atlas.whitePixel, color: NSColor(calibratedWhite: 0.08, alpha: 0.82), size: CGSize(width: 46, height: 4.5))
        moraleBg.colorBlendFactor = 1.0
        moraleBg.position = CGPoint(x: 0, y: 34)

        moraleFill = SKSpriteNode(texture: atlas.whitePixel, color: .systemCyan, size: CGSize(width: 44, height: 3.0))
        moraleFill.colorBlendFactor = 1.0
        moraleFill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        moraleFill.position = CGPoint(x: -22, y: 34)

        badgeLabel = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        badgeLabel.fontSize = 11
        badgeLabel.fontColor = .white
        badgeLabel.position = CGPoint(x: 0, y: 41)

        orderLine = SKSpriteNode(texture: atlas.whitePixel, color: NSColor.systemYellow.withAlphaComponent(0.38), size: CGSize(width: 2, height: 2))
        orderLine.colorBlendFactor = 1.0
        orderLine.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        orderLine.isHidden = true

        root.addChild(orderLine)
        root.addChild(selectRing)
        root.addChild(moraleBg)
        root.addChild(moraleFill)
        root.addChild(badgeLabel)
        root.isHidden = true
    }
}

// MARK: - SpriteKit 真实冷兵器大战场渲染与键鼠操控宿主

/// SpriteKit 大战场原生渲染与实时模拟场景（承载 `BattleSimulationEngine` 30Hz 模拟、600 骨骼火柴人合批渲染、视口裁剪与全套 Mac 键鼠操控）
@MainActor
public final class BattlefieldSKScene: SKScene {
    public let worldWidth: Double
    public let worldHeight: Double

    /// 确定性战斗物理与 AI 核心引擎
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
    private let projectileLayer = SKNode()
    private let effectLayer = SKNode()
    private let uiOverlayLayer = SKNode()
    private let worldCamera = SKCameraNode()

    // 预分配对象池（严禁帧循环动态 new 节点）
    private var soldierPoolNodes: [PooledSoldierNode] = []
    private var projectilePoolNodes: [SKSpriteNode] = []
    private var corpsePoolNodes: [SKSpriteNode] = []
    private var particlePoolNodes: [SKSpriteNode] = []
    private var damageLabelPool: [SKLabelNode] = []
    private var structurePoolNodes: [PooledStructureNode] = []
    private var resourceAmountLabels: [SKLabelNode] = []
    private var trapPoolNodes: [SKSpriteNode] = []
    private var squadMarkerNodes: [PooledSquadMarkerNode] = []
    private var playerHeroNode: PooledHeroNode?
    private var enemyHeroNode: PooledHeroNode?

    /// 鼠标框选、右键路标与英雄瞄准准星节点
    private let marqueeFillNode = SKSpriteNode(
        color: NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.48, alpha: 0.20),
        size: .zero
    )
    private let orderMarkerNode = SKLabelNode(fontNamed: "PingFangSC-Semibold")
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
    private var isOptionPanningDrag = false
    private var pressedKeyCodes = Set<UInt16>()
    private var heroMouseLeftHeld = false
    private var heroMouseRightHeld = false
    private var heroAimLogicPoint: (x: Double, y: Double) = (0.0, 0.0)
    private var installedTrackingArea: NSTrackingArea?

    // 缓存双方势力颜色
    private var factionPrimaryColors: [FactionId: NSColor] = [:]
    private var factionAccentColors: [FactionId: NSColor] = [:]

    // 用户偏好设置（实时生效）
    public var preferredFps: Int = GameConstants.renderTargetFps {
        didSet { view?.preferredFramesPerSecond = preferredFps }
    }
    public var enableFarLod: Bool = true
    public var invertScrollZoom: Bool = false
    public var keyboardPanSpeed: Double = 520.0
    public var showDamageNumbers: Bool = true
    public var enableEdgeCursorPan: Bool = false

    /// 当前双视角操控状态（代理自 `engine.controlMode`）
    public var controlMode: BattleControlMode {
        engine.controlMode
    }

    // 与 SwiftUI `BattlefieldView` 通信回调（全部 `@MainActor` 严格隔离）
    public var onInteractionFeedback: (@MainActor (String) -> Void)?
    public var onUiPacketSynced: (@MainActor (BattlefieldUiSyncPacket) -> Void)?
    public var onRequestToggleEscapeMenu: (@MainActor () -> Void)?
    public var onBattleConcluded: (@MainActor (PostBattleSettlementSummary) -> Void)?

    // MARK: - 初始化（兼容骨架单测无参初始化与完整战局部署初始化）

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
        super.init(size: CGSize(width: 1280, height: 760))
        self.scaleMode = .resizeFill
        self.backgroundColor = Self.groundBaseColor(for: context.terrain, weather: context.weather)

        for cfg in FactionConfig.allFactions {
            factionPrimaryColors[cfg.id] = StickmanTextureAtlas.nsColor(hex: cfg.primaryColorHex)
            factionAccentColors[cfg.id] = StickmanTextureAtlas.nsColor(hex: cfg.accentColorHex)
        }

        // 预绑定 1~6 号军团编组并默认选中我方前锋主力，开场即可直接右键指挥！
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

    // MARK: - 坐标系双向确定性映射（逻辑左上角 0,0 <-> SpriteKit 左下角 0,0）

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

    // MARK: - 场景挂载与对象池一次性预分配

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
        projectileLayer.zPosition = 34
        effectLayer.zPosition = 42
        uiOverlayLayer.zPosition = 52

        addChild(terrainLayer)
        addChild(corpseDecalLayer)
        addChild(structureLayer)
        addChild(squadOverlayLayer)
        addChild(unitBatchLayer)
        addChild(projectileLayer)
        addChild(effectLayer)
        addChild(uiOverlayLayer)

        let atlas = StickmanTextureAtlas.shared
        buildBattlefieldTerrainAndResourceVisuals(atlas: atlas)
        buildPreallocatedEntityPools(atlas: atlas)

        marqueeFillNode.isHidden = true
        marqueeFillNode.zPosition = 58
        uiOverlayLayer.addChild(marqueeFillNode)

        orderMarkerNode.text = "⊕ 进军目标"
        orderMarkerNode.fontSize = 18
        orderMarkerNode.fontColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.32, alpha: 0.96)
        orderMarkerNode.isHidden = true
        orderMarkerNode.zPosition = 59
        uiOverlayLayer.addChild(orderMarkerNode)

        let reticle = SKSpriteNode(texture: atlas.circleRing, color: NSColor.systemYellow.withAlphaComponent(0.82), size: CGSize(width: 24, height: 24))
        reticle.colorBlendFactor = 1.0
        reticle.zPosition = 57
        reticle.isHidden = true
        uiOverlayLayer.addChild(reticle)
        heroAimReticleNode = reticle

        // 初始镜头定位在我军前锋与中线交界处，一眼看见浩荡军阵开拔接战
        let pCamp = engine.baseCampCoordinates(for: .player)
        worldCamera.position = scenePoint(fromLogicX: min(worldWidth * 0.5, pCamp.x + 920.0), logicY: worldHeight * 0.5)
        worldCamera.setScale(1.18)
        addChild(worldCamera)
        self.camera = worldCamera

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

    // MARK: - 公开指挥与操控桥接 API（供 SwiftUI HUD 按钮与快捷键共用）

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

    public func selectAllCombatSquads() {
        selectedSquadIds = engine.squads
            .filter { $0.side == .player && $0.aliveCount > 0 && !$0.isRouting && $0.corpsRole != .supplyEscort }
            .map(\.id)
        onInteractionFeedback?("已全选我方场上主力作战编队（共 \(selectedSquadIds.count) 支军团）")
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
        pushUiSyncNow()
    }

    public func applyFormationToSelection(_ formation: FormationType) {
        let targets = effectiveTargetSquadIds()
        guard !targets.isEmpty else {
            onInteractionFeedback?("当前无可调度编队（请框选未溃逃的我军分队）")
            return
        }
        engine.issueSquadCommand(SquadCommandRequest(squadIds: targets, formation: formation))
        onInteractionFeedback?("已命 \(targets.count) 支编队变阵为【\(formation.displayName)】")
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
            // 若玩家直接按指令快捷键，自动指向最近敌军主力质心发起推进/包抄/合围！
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
        onInteractionFeedback?("已向 \(targets.count) 支编队下达【\(order.displayName)】军令！")
        pushUiSyncNow()
    }

    public func toggleBattlePause() {
        engine.setPaused(!engine.isPaused)
        onInteractionFeedback?(
            engine.isPaused
                ? "⏸ 战术暂停中：可继续框选多线编队预下达包抄与变阵军令"
                : "▶️ 战鼓重鸣：全军恢复实时厮杀"
        )
        pushUiSyncNow()
    }

    public func setBattlePaused(_ paused: Bool) {
        engine.setPaused(paused)
        pushUiSyncNow()
    }

    public func toggleGarrisonBell() {
        engine.toggleGarrisonBell()
        onInteractionFeedback?(
            engine.playerState.garrisonBellActive
                ? "🔔 本阵警钟已鸣响：野外辎重工兵紧急退入大营箭孔协防！"
                : "本阵警钟已解除：辎重工兵出营恢复采金伐木抢粮"
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
            pressedKeyCodes.removeAll()
            heroMouseLeftHeld = false
            heroMouseRightHeld = false
            engine.updateHeroInput(HeroControlInputState())
            if engine.controlMode == .heroAction {
                worldCamera.position = scenePoint(fromLogicX: engine.playerHero.x, logicY: engine.playerHero.y)
                worldCamera.setScale(max(0.76, min(0.98, worldCamera.xScale)))
                clampCameraPosition()
                onInteractionFeedback?("⚔️ 主帅提刀上阵！[WASD/方向键] 走位 · 鼠标瞄准 · 左键劈刺/蓄射 · 右键举盾0.25s弹反 · [Space/E/R] 战技")
            } else {
                worldCamera.setScale(max(1.08, worldCamera.xScale))
                clampCameraPosition()
                onInteractionFeedback?("🗺 已切回 RTS 统帅全局视角：左键框选 · 右键机动/集火 · [1~4] 阵型 · [QWERF/GZXC] 奇正战术")
            }
            pushUiSyncNow()
        }
        return switched
    }

    public func switchHeroWeapon(_ weapon: HeroWeaponType) {
        engine.switchHeroWeapon(weapon)
        onInteractionFeedback?("主帅切换兵刃：【\(weapon.displayName)】")
        pushUiSyncNow()
    }

    public func triggerHeroSkill(_ skill: HeroSkillId) {
        let ok = engine.triggerHeroSkill(skill)
        if ok {
            let title: String = {
                switch skill {
                case .breakthroughCharge: return "【破阵突击】猛冲撞阵！"
                case .ironBulwark: return "【铁壁横戈】2.0s 弹反箭雨并蓄势横扫！"
                case .grandWarCry: return "【三军战吼】友军士气 +18，溃军重整归建！"
                }
            }()
            onInteractionFeedback?("🔥 主帅施放战技：\(title)")
            pushUiSyncNow()
        } else {
            let cd = engine.playerHero.cooldownRemaining(for: skill)
            onInteractionFeedback?(String(format: "战技尚在调息冷却中（剩余 %.1fs）", cd))
        }
    }

    public func recruitReinforcement(unitType: UnitTypeId, useMercenaryGold: Bool = false) {
        let role: ArmyCorpsRole = {
            guard let st = UnitConfig.stats(for: unitType) else { return .rearReserve }
            switch st.category {
            case .support: return .supplyEscort
            case .ranged, .siege: return .siegeBattery
            case .cavalry: return .leftWing
            case .infantry, .polearm, .shock: return .vanguardCenter
            }
        }()
        let ok = useMercenaryGold
            ? engine.recruitMercenaryUnit(side: .player, unitType: unitType, corpsRole: role)
            : engine.recruitUnit(side: .player, unitType: unitType, corpsRole: role)
        let uName = UnitConfig.stats(for: unitType)?.name ?? unitType.rawValue
        if ok {
            onInteractionFeedback?(
                useMercenaryGold
                    ? "💰 商盟黄金契约生效：【\(uName)】已即时投入本阵前线！"
                    : "本阵开始训练增援【\(uName)】（队列 \(engine.playerState.trainingQueue.count)）"
            )
            pushUiSyncNow()
        } else {
            onInteractionFeedback?("无法招募【\(uName)】：请检查金木粮储量、人口上限或本阵状态")
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

    // MARK: - 30Hz 确定性模拟驱动与 60FPS 视口裁剪合批渲染主循环

    public override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        if lastUpdateTimestamp == 0.0 {
            lastUpdateTimestamp = currentTime
            return
        }
        let rawDt = max(0.0, min(0.08, currentTime - lastUpdateTimestamp))
        lastUpdateTimestamp = currentTime

        // 处理相机平滑键盘/边缘平移与英雄视角跟随
        updateCameraAndHeroInput(frameDt: rawDt)

        if orderMarkerFadeTimer > 0.0 {
            orderMarkerFadeTimer -= rawDt
            if orderMarkerFadeTimer <= 0.0 {
                orderMarkerNode.isHidden = true
            }
        }

        // 固定步长 30Hz 推进确定性战斗核心
        let fixedStep = 1.0 / Double(GameConstants.logicTickHz)
        if !engine.isPaused && engine.outcome == .ongoing {
            fixedTickAccumulator += rawDt
            var subSteps = 0
            while fixedTickAccumulator >= fixedStep && subSteps < 3 && engine.outcome == .ongoing {
                engine.stepLogicTick(deltaTime: fixedStep)
                fixedTickAccumulator -= fixedStep
                subSteps += 1
            }
            if subSteps == 3 {
                fixedTickAccumulator = 0.0
            }
        }

        // 检测主帅首次重伤落马自动退回 RTS 视角及医帐包扎复出过渡（DESIGN.md 10.2）
        let currentVital = engine.playerHero.vitalState
        if currentVital != lastObservedHeroVitalState {
            lastObservedHeroVitalState = currentVital
            if currentVital == .recoveringInCamp {
                heroMouseLeftHeld = false
                heroMouseRightHeld = false
                pressedKeyCodes.removeAll()
                worldCamera.setScale(max(1.15, worldCamera.xScale))
                clampCameraPosition()
                onInteractionFeedback?("⚠️ 帅旗倾倒！主帅重伤退入本阵医帐包扎 45s（全军士气 -35·上限锁 65），已自动拉回 RTS 上帝视角调度残军！")
                pushUiSyncNow()
            } else if currentVital == .woundedWeakened {
                onInteractionFeedback?("🔥 主帅包扎完毕重返战场（35% 残血·重创虚弱态，失去二次免死保护），可按 [Tab] 再度披挂上阵！")
                pushUiSyncNow()
            }
        }

        // 自动剔除已全灭的选中编队 ID，避免框选残留空壳分队
        if !selectedSquadIds.isEmpty {
            selectedSquadIds.removeAll { id in
                id < 0 || id >= engine.squads.count || engine.squads[id].aliveCount <= 0
            }
        }

        // 同步全部预分配渲染池节点姿态（含视口裁剪与远景 LOD）
        syncAllVisualNodesWithEngine()

        // 4Hz 节流同步给 SwiftUI 顶部与底部战术面板
        uiPushAccumulator += rawDt
        if uiPushAccumulator >= 0.25 {
            uiPushAccumulator = 0.0
            pushUiSyncNow()
        }

        if engine.outcome != .ongoing && !outcomeNotified {
            outcomeNotified = true
            pushUiSyncNow()
            let summary = engine.buildPostBattleSummary()
            onBattleConcluded?(summary)
        }
    }

    private func updateCameraAndHeroInput(frameDt: Double) {
        // 若窗口失去焦点（如 Cmd+Tab 切出应用），立即清空按键与鼠标长按状态防止粘连卡键
        if let win = self.view?.window, !win.isKeyWindow {
            if !pressedKeyCodes.isEmpty || heroMouseLeftHeld || heroMouseRightHeld {
                pressedKeyCodes.removeAll()
                heroMouseLeftHeld = false
                heroMouseRightHeld = false
                engine.updateHeroInput(HeroControlInputState())
            }
            return
        }

        if engine.controlMode == .heroAction {
            // 实时从窗口光标反算世界坐标，确保按住 WASD 跑动时鼠标准星始终精确锁定屏幕光标位置
            if let view = self.view, let win = view.window {
                let winMouse = win.mouseLocationOutsideOfEventStream
                let viewPt = view.convert(winMouse, from: nil)
                if view.bounds.contains(viewPt) {
                    let scenePt = convertPoint(fromView: viewPt)
                    heroAimLogicPoint = logicCoordinates(fromScenePoint: scenePt)
                }
            }

            var moveX = 0.0
            var moveY = 0.0
            if pressedKeyCodes.contains(0) || pressedKeyCodes.contains(123) { moveX -= 1.0 } // A / Left
            if pressedKeyCodes.contains(2) || pressedKeyCodes.contains(124) { moveX += 1.0 } // D / Right
            if pressedKeyCodes.contains(13) || pressedKeyCodes.contains(126) { moveY -= 1.0 } // W / Up -> 北 (logicY 减小)
            if pressedKeyCodes.contains(1) || pressedKeyCodes.contains(125) { moveY += 1.0 } // S / Down -> 南 (logicY 增大)

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

            // 英雄模式下相机平滑追踪主帅（叠加轻微准星前瞻与重击震屏）
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
                let amp = CGFloat(engine.cameraShakeIntensity * 7.0)
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

            // 可选屏幕边缘光标推镜
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
                    encirclement: sq.encirclementState
                )
            }
        let hero = engine.playerHero
        let packet = BattlefieldUiSyncPacket(
            hud: engine.latestHudSnapshot,
            playerSquads: briefs,
            selectedSquadIds: selectedSquadIds,
            trainingQueueCount: engine.playerState.trainingQueue.count,
            aiDoctrine: engine.aiBlackboard.activeDoctrine,
            aiSiegePhase: engine.aiBlackboard.siegePhase,
            heroBreakthroughCd: hero.breakthroughCooldown,
            heroBulwarkCd: hero.ironBulwarkCooldown,
            heroWarCryCd: hero.grandWarCryCooldown,
            heroMedicalRemainingSec: hero.medicalRecoveryRemainingSec,
            heroBowChargeRatio: min(1.0, hero.bowChargeElapsed / 0.90),
            heroKills: hero.killsCount,
            bloodMoonFervorRemaining: engine.playerState.bloodMoonFervorRemainingSec
        )
        onUiPacketSynced?(packet)
    }

    // MARK: - 战场地形带、功能地形区、野外资源点与预分配节点池初始化

    private static func groundBaseColor(for terrain: TerrainType, weather: WeatherType) -> NSColor {
        var base: (r: CGFloat, g: CGFloat, b: CGFloat) = {
            switch terrain {
            case .plain: return (0.17, 0.16, 0.12)
            case .highGround: return (0.19, 0.17, 0.14)
            case .riverFord, .bridgePass: return (0.15, 0.17, 0.15)
            case .denseForest: return (0.12, 0.18, 0.13)
            case .desertDune: return (0.26, 0.21, 0.13)
            case .snowfield: return (0.24, 0.27, 0.30)
            case .fortWall: return (0.17, 0.16, 0.15)
            }
        }()
        if weather == .night {
            base.r *= 0.58; base.g *= 0.62; base.b *= 0.78
        } else if weather == .rainMud {
            base.r *= 0.78; base.g *= 0.80; base.b *= 0.85
        }
        return NSColor(calibratedRed: base.r, green: base.g, blue: base.b, alpha: 1.0)
    }

    private func buildBattlefieldTerrainAndResourceVisuals(atlas: StickmanTextureAtlas) {
        let baseGround = SKSpriteNode(
            texture: atlas.whitePixel,
            color: Self.groundBaseColor(for: engine.context.terrain, weather: engine.context.weather),
            size: CGSize(width: worldWidth, height: worldHeight)
        )
        baseGround.colorBlendFactor = 1.0
        baseGround.position = CGPoint(x: worldWidth * 0.5, y: worldHeight * 0.5)
        terrainLayer.addChild(baseGround)

        // 三路走廊微底色标识
        addCorridorBand(atlas: atlas, logicMinY: 150, logicMaxY: 680, color: NSColor(calibratedRed: 0.13, green: 0.21, blue: 0.14, alpha: 0.30), title: "北翼迂回走廊 · 密林设伏与轻骑绕后道")
        addCorridorBand(atlas: atlas, logicMinY: 680, logicMaxY: 1720, color: NSColor(calibratedRed: 0.23, green: 0.20, blue: 0.15, alpha: 0.22), title: "中路主决战区 · 百人方阵正面交锋线")
        addCorridorBand(atlas: atlas, logicMinY: 1720, logicMaxY: 2250, color: NSColor(calibratedRed: 0.24, green: 0.20, blue: 0.12, alpha: 0.30), title: "南翼补给走廊 · 农庄抢粮与大回环包抄道")

        // 绘制 `engine.terrainZones` 真实物理地形功能区（浅滩、石桥、高地山脊、密林暗道、城墙带）
        for zone in engine.terrainZones {
            let w = zone.maxX - zone.minX
            let h = zone.maxY - zone.minY
            let center = scenePoint(fromLogicX: (zone.minX + zone.maxX) * 0.5, logicY: (zone.minY + zone.maxY) * 0.5)
            let (zColor, zName): (NSColor, String) = {
                switch zone.terrain {
                case .riverFord:
                    return (NSColor(calibratedRed: 0.12, green: 0.38, blue: 0.56, alpha: 0.52), "河流浅滩（涉水减速·半渡而击易伤+20%）")
                case .bridgePass:
                    return (NSColor(calibratedRed: 0.42, green: 0.39, blue: 0.35, alpha: 0.72), "石桥咽喉（免除合围）")
                case .highGround:
                    return (NSColor(calibratedRed: 0.34, green: 0.29, blue: 0.21, alpha: 0.46), "制高点高地（射程+20%·居高近战+12%）")
                case .denseForest:
                    return (NSColor(calibratedRed: 0.11, green: 0.30, blue: 0.15, alpha: 0.50), "迷雾密林（伏兵隐匿·禁骑冲锋）")
                case .fortWall:
                    return (NSColor(calibratedRed: 0.32, green: 0.31, blue: 0.33, alpha: 0.58), "雄关城防带")
                default:
                    return (NSColor(calibratedWhite: 0.3, alpha: 0.2), zone.terrain.displayName)
                }
            }()
            let rectNode = SKSpriteNode(texture: atlas.whitePixel, color: zColor, size: CGSize(width: w, height: h))
            rectNode.colorBlendFactor = 1.0
            rectNode.position = center
            terrainLayer.addChild(rectNode)

            let tag = SKLabelNode(fontNamed: "PingFangSC-Regular")
            tag.text = zName
            tag.fontSize = 14
            tag.fontColor = NSColor(calibratedWhite: 0.90, alpha: 0.58)
            tag.position = CGPoint(x: center.x, y: center.y - 5)
            terrainLayer.addChild(tag)
        }

        // 绘制 6 处野外金矿、林场与农庄粮垛
        resourceAmountLabels.removeAll()
        for res in engine.resourceNodes {
            let pos = scenePoint(fromLogicX: res.x, logicY: res.y)
            let (rColor, rTitle): (NSColor, String) = {
                switch res.kind {
                case .goldMine: return (NSColor(calibratedRed: 0.95, green: 0.76, blue: 0.18, alpha: 0.88), "⛏ 金矿脉")
                case .lumberForest: return (NSColor(calibratedRed: 0.26, green: 0.62, blue: 0.30, alpha: 0.88), "🌲 伐木林场")
                case .grainFarm: return (NSColor(calibratedRed: 0.88, green: 0.62, blue: 0.22, alpha: 0.88), "🌾 农庄粮垛")
                }
            }()
            let disc = SKSpriteNode(texture: atlas.circleFilled, color: rColor, size: CGSize(width: 42, height: 42))
            disc.colorBlendFactor = 1.0
            disc.position = pos
            terrainLayer.addChild(disc)

            let lbl = SKLabelNode(fontNamed: "PingFangSC-Semibold")
            lbl.text = "\(rTitle) (\(Int(res.remainingAmount)))"
            lbl.fontSize = 12
            lbl.fontColor = .white
            lbl.position = CGPoint(x: pos.x, y: pos.y + 26)
            terrainLayer.addChild(lbl)
            resourceAmountLabels.append(lbl)
        }
    }

    private func addCorridorBand(atlas: StickmanTextureAtlas, logicMinY: Double, logicMaxY: Double, color: NSColor, title: String) {
        let bandH = logicMaxY - logicMinY
        let cScene = scenePoint(fromLogicX: worldWidth * 0.5, logicY: (logicMinY + logicMaxY) * 0.5)
        let band = SKSpriteNode(texture: atlas.whitePixel, color: color, size: CGSize(width: worldWidth - 120, height: bandH - 8))
        band.colorBlendFactor = 1.0
        band.position = cScene
        terrainLayer.addChild(band)

        let lbl = SKLabelNode(fontNamed: "PingFangSC-Medium")
        lbl.text = title
        lbl.fontSize = 16
        lbl.fontColor = NSColor(calibratedWhite: 0.85, alpha: 0.32)
        lbl.position = CGPoint(x: cScene.x, y: cScene.y + CGFloat(bandH * 0.5) - 24)
        terrainLayer.addChild(lbl)
    }

    private func buildPreallocatedEntityPools(atlas: StickmanTextureAtlas) {
        // 1. 建筑池（本阵、正侧城门、城墙、箭塔、拒马、云梯）
        structurePoolNodes.removeAll()
        for st in engine.structures {
            let color: NSColor = {
                let sideBase = st.side == .player
                    ? (factionPrimaryColors[engine.playerState.faction] ?? .systemRed)
                    : (factionPrimaryColors[engine.enemyState.faction] ?? .systemBlue)
                switch st.kind {
                case .baseCamp: return sideBase.withAlphaComponent(0.92)
                case .mainGate: return NSColor(calibratedRed: 0.52, green: 0.33, blue: 0.18, alpha: 0.96)
                case .sideSallyGate: return NSColor(calibratedRed: 0.44, green: 0.30, blue: 0.20, alpha: 0.92)
                case .wallSegment: return NSColor(calibratedRed: 0.42, green: 0.43, blue: 0.46, alpha: 0.96)
                case .arrowTower: return sideBase.blended(withFraction: 0.35, of: .darkGray) ?? sideBase
                case .woodenCheval: return NSColor(calibratedRed: 0.62, green: 0.44, blue: 0.22, alpha: 0.92)
                case .siegeLadder: return NSColor(calibratedRed: 0.76, green: 0.62, blue: 0.34, alpha: 0.88)
                }
            }()
            let title: String = {
                let prefix = st.side == .player ? "我方" : "敌方"
                switch st.kind {
                case .baseCamp: return "\(prefix)本阵大营"
                case .mainGate: return "瓮城正门"
                case .sideSallyGate: return "侧门暗道"
                case .wallSegment: return "城墙"
                case .arrowTower: return "\(prefix)箭塔"
                case .woodenCheval: return "拒马"
                case .siegeLadder: return "登城云梯"
                }
            }()
            let node = PooledStructureNode(atlas: atlas, width: CGFloat(st.width), height: CGFloat(st.height), color: color, title: title)
            node.root.position = scenePoint(fromLogicX: st.x, logicY: st.y)
            structureLayer.addChild(node.root)
            structurePoolNodes.append(node)
        }

        // 2. 陷阱视觉节点
        syncTrapVisualPool()

        // 3. 600 名火柴人士兵骨骼池
        soldierPoolNodes.reserveCapacity(GameConstants.maxUnitPoolSize)
        for _ in 0..<GameConstants.maxUnitPoolSize {
            let sNode = PooledSoldierNode(atlas: atlas)
            unitBatchLayer.addChild(sNode.root)
            soldierPoolNodes.append(sNode)
        }

        // 4. 双方主帅英雄节点
        let pPrim = factionPrimaryColors[engine.playerState.faction] ?? .systemRed
        let pAcc = factionAccentColors[engine.playerState.faction] ?? .systemYellow
        let pHero = PooledHeroNode(atlas: atlas, primaryColor: pPrim, accentColor: pAcc, title: "★ 我方主帅")
        pHero.root.zPosition = 2.0
        unitBatchLayer.addChild(pHero.root)
        playerHeroNode = pHero

        let ePrim = factionPrimaryColors[engine.enemyState.faction] ?? .systemBlue
        let eAcc = factionAccentColors[engine.enemyState.faction] ?? .white
        let eHero = PooledHeroNode(atlas: atlas, primaryColor: ePrim, accentColor: eAcc, title: "✦ 敌军主帅")
        eHero.root.zPosition = 2.0
        unitBatchLayer.addChild(eHero.root)
        enemyHeroNode = eHero

        // 5. 400 支投射物池
        projectilePoolNodes.reserveCapacity(GameConstants.maxProjectilePoolSize)
        for _ in 0..<GameConstants.maxProjectilePoolSize {
            let p = SKSpriteNode(texture: atlas.arrowProjectile, color: .white, size: CGSize(width: 18, height: 5))
            p.colorBlendFactor = 1.0
            p.isHidden = true
            projectileLayer.addChild(p)
            projectilePoolNodes.append(p)
        }

        // 6. 150 具战场遗骸贴花池
        corpsePoolNodes.reserveCapacity(GameConstants.maxFallenCorpseDecals)
        for _ in 0..<GameConstants.maxFallenCorpseDecals {
            let c = SKSpriteNode(texture: atlas.corpseSilhouette, color: .gray, size: CGSize(width: 22, height: 10))
            c.colorBlendFactor = 1.0
            c.isHidden = true
            corpseDecalLayer.addChild(c)
            corpsePoolNodes.append(c)
        }

        // 7. 300 个战斗粒子池 + 32 个高暴击飘字池
        particlePoolNodes.reserveCapacity(GameConstants.maxEffectParticlePoolSize)
        lastRenderedParticleCursorSnapshot = Array(repeating: false, count: GameConstants.maxEffectParticlePoolSize)
        for _ in 0..<GameConstants.maxEffectParticlePoolSize {
            let fx = SKSpriteNode(texture: atlas.sparkStar, color: .yellow, size: CGSize(width: 16, height: 16))
            fx.colorBlendFactor = 1.0
            fx.isHidden = true
            effectLayer.addChild(fx)
            particlePoolNodes.append(fx)
        }

        for _ in 0..<32 {
            let dmgLbl = SKLabelNode(fontNamed: "PingFangSC-Heavy")
            dmgLbl.fontSize = 13
            dmgLbl.isHidden = true
            effectLayer.addChild(dmgLbl)
            damageLabelPool.append(dmgLbl)
        }

        // 8. 军团战术标牌池（预留 32 支分队容量）
        for _ in 0..<32 {
            let m = PooledSquadMarkerNode(atlas: atlas)
            squadOverlayLayer.addChild(m.root)
            squadMarkerNodes.append(m)
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

    // MARK: - 零分配池化同步：视口裁剪 + 远景 LOD + 11 态火柴人骨骼动作

    private func syncAllVisualNodesWithEngine() {
        let atlas = StickmanTextureAtlas.shared
        let visibleRect = currentVisibleSceneRect()
        let isFarLod = enableFarLod && (1.0 / Double(worldCamera.xScale)) < GameConstants.battlefieldFarLodZoomThreshold

        // 1. 同步野外资源剩余储量文字（仅在整数储量变化时更新 SKLabelNode.text，杜绝每帧重绘字体纹理）
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
                    case .goldMine: return "⛏ 金矿脉"
                    case .lumberForest: return "🌲 伐木林场"
                    case .grainFarm: return "🌾 农庄粮垛"
                    }
                }()
                resourceAmountLabels[i].text = "\(rTitle) (\(amt))"
            }
            resourceAmountLabels[i].alpha = res.remainingAmount > 0 ? 0.92 : 0.35
        }

        // 2. 同步城墙、城门、箭塔与本阵耐久条（建筑摧毁文案仅写一次，零字符串重分配）
        for i in 0..<min(structurePoolNodes.count, engine.structures.count) {
            let st = engine.structures[i]
            let node = structurePoolNodes[i]
            if st.isDestroyed {
                if !node.wasRenderedDestroyed {
                    node.wasRenderedDestroyed = true
                    node.body.alpha = 0.22
                    node.hpBg.isHidden = true
                    node.hpFill.isHidden = true
                    node.label.text = "[\(node.baseTitle)·已破]"
                    node.label.fontColor = .systemGray
                }
            } else {
                let ratio = CGFloat(max(0.0, min(1.0, st.hp / max(1.0, st.maxHp))))
                node.hpFill.size.width = node.maxBarWidth * ratio
                node.hpFill.color = ratio > 0.5 ? .systemGreen : (ratio > 0.25 ? .systemOrange : .systemRed)
            }
        }

        // 3. 同步陷阱显隐（敌方未触发陷阱对我方隐蔽，除非我方是雾林猎手）
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

        // 4. O(N) 单遍预标记各敌军分队是否有可见士兵，再同步军团选择光环、阵型/合围/溃逃标牌与进军线
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
            marker.moraleFill.size.width = 44.0 * mRatio
            marker.moraleFill.color = sq.isRouting
                ? .white
                : (sq.morale < 40.0 ? .systemYellow : (sq.side == .player ? .systemGreen : .systemOrange))

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
                nextText = "\(uShort) \(sq.aliveCount) [\(sq.formation.displayName)]"
                nextColor = isSel ? .systemYellow : NSColor(calibratedWhite: 0.92, alpha: 0.85)
            } else {
                nextText = "\(sq.aliveCount)"
                nextColor = NSColor(calibratedWhite: 0.85, alpha: 0.75)
            }
            if marker.cachedBadgeText != nextText {
                marker.cachedBadgeText = nextText
                marker.badgeLabel.text = nextText
            }
            marker.badgeLabel.fontColor = nextColor

            // 选中我军分队时画出指向航点/目标的战术虚线指示杆
            if isSel && !sq.isRouting && sq.order != .holdGround {
                let navLogicX = sq.waypoints.first?.x ?? sq.targetX
                let navLogicY = sq.waypoints.first?.y ?? sq.targetY
                let destScene = scenePoint(fromLogicX: navLogicX, logicY: navLogicY)
                let dx = destScene.x - anchorPt.x
                let dy = destScene.y - anchorPt.y
                let dist = hypot(dx, dy)
                if dist > 28.0 {
                    marker.orderLine.isHidden = false
                    marker.orderLine.size = CGSize(width: dist, height: 2.2)
                    marker.orderLine.zRotation = atan2(dy, dx)
                } else {
                    marker.orderLine.isHidden = true
                }
            } else {
                marker.orderLine.isHidden = true
            }
        }

        // 5. 同步 600 名火柴人骨骼姿态（严格执行视口裁剪 + 远景 LOD）
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
            vNode.root.alpha = s.isStealthed ? 0.45 : 1.0

            // 仅当槽位复用切换兵种或势力时才更新纹理/主色引用，避免每帧重复赋值开销
            if vNode.cachedUnitType != s.unitType || vNode.cachedFaction != s.faction {
                configureSoldierStaticAppearance(vNode, soldier: s, atlas: atlas)
            }

            // 巨熊破阵者 1.35x 巨人比例
            let baseScale: CGFloat = s.unitType == .shuangyuanGiantBreaker ? 1.38 : 1.0
            let faceRight = cos(s.facingRadians) >= 0.0
            vNode.root.xScale = faceRight ? baseScale : -baseScale
            vNode.root.yScale = baseScale

            // 远景鸟瞰 LOD（<0.60x）：隐藏细碎四肢与刀枪，仅保留鲜明躯干、头盔、坐骑与军旗
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

            // 解算 11 种骨骼动作关节旋转角
            let phase = CGFloat(s.animPhase)
            let localAimAngle: CGFloat = {
                // 因 root.xScale 已处理左右镜像翻转，局部朝向角只需映射上下仰俯分量
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
                    vNode.shieldNode.position = CGPoint(x: -4.5, y: 6.0)
                } else {
                    vNode.shieldNode.position = CGPoint(x: 5.5, y: 6.0)
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

        // 6. 同步双方主帅英雄节点
        if let pHeroNode = playerHeroNode {
            syncSingleHeroNode(pHeroNode, hero: engine.playerHero, atlas: atlas)
        }
        if let eHeroNode = enemyHeroNode {
            syncSingleHeroNode(eHeroNode, hero: engine.enemyHero, atlas: atlas)
        }

        // 7. 同步 400 支抛物线箭矢、弩矢、火雷与投石车巨石
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
                pNode.texture = atlas.circleFilled
                pNode.size = CGSize(width: 15, height: 15)
                pNode.color = NSColor(calibratedWhite: 0.78, alpha: 1.0)
                pNode.zRotation += 0.22
            case .thunderGrenade:
                pNode.texture = atlas.sparkStar
                pNode.size = CGSize(width: 15, height: 15)
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
                    pNode.size = CGSize(width: 26, height: 6.5)
                    pNode.color = .systemYellow
                case .heroHeavyArrow:
                    pNode.size = CGSize(width: 25, height: 6.5)
                    pNode.color = .systemCyan
                case .venomArrow:
                    pNode.size = CGSize(width: 19, height: 5.0)
                    pNode.color = .systemGreen
                case .crossbowBolt:
                    pNode.size = CGSize(width: 18, height: 5.2)
                    pNode.color = NSColor(calibratedWhite: 0.95, alpha: 1.0)
                default:
                    pNode.size = CGSize(width: 17, height: 4.5)
                    pNode.color = proj.side == .player
                        ? NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.62, alpha: 0.95)
                        : NSColor(calibratedRed: 0.82, green: 0.90, blue: 1.0, alpha: 0.95)
                }
            }
        }

        // 8. 同步 150 具倒地遗骸贴花
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
            cNode.color = baseCol.withAlphaComponent(0.42)
        }

        // 9. 同步 300 个刀剑火星、血花、爆炸、三军战吼波纹与暴击伤害飘字
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
                fxNode.size = CGSize(width: 14, height: 14)
                fxNode.alpha = 1.0 - progress
            case .parryFlash:
                fxNode.texture = atlas.sparkStar
                fxNode.color = .white
                let sz = 24.0 + progress * 22.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 1.0 - progress
            case .bloodSlash:
                fxNode.texture = atlas.slashWave
                fxNode.color = fx.isCritical ? .systemOrange : .systemRed
                fxNode.size = CGSize(width: 16, height: 13)
                fxNode.alpha = 0.90 * (1.0 - progress)
                if showDamageNumbers && !wasActive && (fx.isCritical || fx.numericValue >= 38) {
                    spawnFloatingDamageText(value: fx.numericValue, isCritical: fx.isCritical, at: pt)
                }
            case .explosionFire:
                fxNode.texture = atlas.circleFilled
                fxNode.color = .systemOrange
                let sz = 36.0 + progress * 90.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 0.78 * (1.0 - progress)
            case .boulderDust:
                fxNode.texture = atlas.circleFilled
                fxNode.color = NSColor(calibratedRed: 0.78, green: 0.70, blue: 0.56, alpha: 1.0)
                let sz = 40.0 + progress * 96.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 0.72 * (1.0 - progress)
            case .warCryWave:
                fxNode.texture = atlas.circleRing
                fxNode.color = .systemYellow
                let sz = 48.0 + progress * 560.0
                fxNode.size = CGSize(width: sz, height: sz)
                fxNode.alpha = 0.85 * (1.0 - progress)
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
        lbl.fontSize = isCritical ? 15 : 12
        lbl.fontColor = isCritical ? .systemYellow : .white
        lbl.position = CGPoint(x: point.x, y: point.y + 16)
        lbl.alpha = 1.0
        lbl.isHidden = false
        lbl.run(
            SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: 0, y: 24, duration: 0.48),
                    SKAction.fadeOut(withDuration: 0.48)
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
            ? NSColor(calibratedWhite: 0.94, alpha: 1.0)
            : NSColor(calibratedWhite: 0.80, alpha: 1.0)

        vNode.torso.color = prim
        vNode.head.color = limbCol
        vNode.legLeft.color = limbCol
        vNode.legRight.color = limbCol
        vNode.armMain.color = limbCol
        vNode.bannerCloth.color = prim

        let isCav = (s.category == .cavalry)
        let isSiege = (s.category == .siege)
        vNode.mountNode.isHidden = !isCav
        vNode.siegeNode.isHidden = !isSiege
        if isCav {
            vNode.mountNode.color = s.unitType == .shamoMamelukeCamel
                ? NSColor(calibratedRed: 0.82, green: 0.68, blue: 0.42, alpha: 1.0)
                : (s.unitType == .xuanjiaCataphract ? (prim.blended(withFraction: 0.4, of: .darkGray) ?? prim) : NSColor(calibratedRed: 0.48, green: 0.34, blue: 0.22, alpha: 1.0))
        }
        if isSiege {
            vNode.siegeNode.color = s.unitType == .trebuchet
                ? NSColor(calibratedRed: 0.64, green: 0.45, blue: 0.24, alpha: 1.0)
                : NSColor(calibratedRed: 0.55, green: 0.52, blue: 0.48, alpha: 1.0)
        }

        // 武器与盾牌匹配 16 兵种真实外观
        switch s.unitType {
        case .pikeman, .yanlongHalberdGrenadier, .xuanjiaCataphract:
            vNode.weaponNode.texture = atlas.pikeShaft
            vNode.weaponNode.size = CGSize(width: 28, height: 5.5)
            vNode.weaponNode.color = acc
        case .greatAxeman, .shuangyuanGiantBreaker, .xueyueWardrumBerserker:
            vNode.weaponNode.texture = atlas.greatAxe
            vNode.weaponNode.size = CGSize(width: 22, height: 13)
            vNode.weaponNode.color = acc
        case .compositeArcher, .canglangKeshigHorseArcher, .wulinShadowSniper:
            vNode.weaponNode.texture = atlas.bowArc
            vNode.weaponNode.size = CGSize(width: 12, height: 17)
            vNode.weaponNode.color = acc
        case .tieyingPaviseCrossbow, .ballista:
            vNode.weaponNode.texture = atlas.crossbowFrame
            vNode.weaponNode.size = CGSize(width: 16, height: 13)
            vNode.weaponNode.color = acc
        default:
            vNode.weaponNode.texture = atlas.saberBlade
            vNode.weaponNode.size = CGSize(width: 19, height: 6)
            vNode.weaponNode.color = NSColor(calibratedWhite: 0.92, alpha: 1.0)
        }

        if s.shieldRangedBlock >= 0.30 {
            vNode.shieldNode.isHidden = false
            let usePavise = (s.unitType == .tieyingPaviseCrossbow || s.unitType == .yanlongHalberdGrenadier)
            vNode.shieldNode.texture = usePavise ? atlas.paviseShield : atlas.roundShield
            vNode.shieldNode.size = usePavise ? CGSize(width: 10, height: 15) : CGSize(width: 11.5, height: 11.5)
            vNode.shieldNode.color = acc.blended(withFraction: 0.45, of: prim) ?? acc
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
            node.weaponSprite.size = CGSize(width: 26, height: 8)
            node.shieldSprite.isHidden = false
            node.shieldSprite.position = CGPoint(x: faceRight ? 8 : -8, y: 8)
            node.shieldSprite.color = hero.isInPerfectParryWindow ? .white : (hero.isBlocking ? .systemCyan : .systemYellow)
        case .breakerSpear:
            node.weaponSprite.texture = atlas.pikeShaft
            node.weaponSprite.size = CGSize(width: 38, height: 7)
            node.shieldSprite.isHidden = true
        case .heavyWarbow:
            node.weaponSprite.texture = atlas.bowArc
            node.weaponSprite.size = CGSize(width: 16, height: 22)
            node.shieldSprite.isHidden = true
        }

        let hpRatio = CGFloat(max(0.0, min(1.0, hero.hp / max(1.0, hero.maxHp))))
        node.hpFill.size.width = 34.0 * hpRatio
        node.hpFill.color = hero.vitalState == .woundedWeakened ? .systemOrange : .systemGreen

        if hero.bowChargeElapsed > 0.02 {
            node.bowChargeBar.isHidden = false
            node.bowChargeBar.size.width = 34.0 * CGFloat(min(1.0, hero.bowChargeElapsed / 0.90))
        } else {
            node.bowChargeBar.isHidden = true
        }

        node.auraRing.size = hero.ironBulwarkRemainingSec > 0.0
            ? CGSize(width: 56, height: 56)
            : CGSize(width: 38, height: 38)
    }

    // MARK: - 相机缩放与边界钳制

    public func resetCameraToCenter() {
        if engine.controlMode == .heroAction && engine.playerHero.isActiveOnField {
            worldCamera.position = scenePoint(fromLogicX: engine.playerHero.x, logicY: engine.playerHero.y)
            worldCamera.setScale(0.92)
        } else {
            worldCamera.position = CGPoint(x: worldWidth * 0.5, y: worldHeight * 0.5)
            worldCamera.setScale(1.22)
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

    // MARK: - macOS 原生键鼠与触控板全功能事件处理

    public override func mouseMoved(with event: NSEvent) {
        let pt = event.location(in: self)
        heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = event.location(in: self)

        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
            heroMouseLeftHeld = true
            return
        }

        // 按住 Option + 左键拖拽支持单手平移战场镜头
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
    }

    public override func mouseDragged(with event: NSEvent) {
        let current = event.location(in: self)
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
        marqueeFillNode.position = CGPoint(x: (start.x + current.x) * 0.5, y: (start.y + current.y) * 0.5)
        marqueeFillNode.size = CGSize(width: width, height: height)
    }

    public override func mouseUp(with event: NSEvent) {
        let end = event.location(in: self)
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
        dragStartScenePoint = nil

        let shiftHeld = event.modifierFlags.contains(.shift)
        let dragDist = hypot(end.x - start.x, end.y - start.y)
        let endLogic = logicCoordinates(fromScenePoint: end)

        if dragDist < 10.0 {
            if let pickedId = engine.pickSquadAtPoint(x: endLogic.x, y: endLogic.y, tolerance: 56.0, side: .player) {
                if event.clickCount >= 2 {
                    // 双击：全选场上同兵种分队！
                    let targetUnitType = engine.squads[pickedId].primaryUnitType
                    selectedSquadIds = engine.squads
                        .filter { $0.side == .player && $0.aliveCount > 0 && !$0.isRouting && $0.primaryUnitType == targetUnitType }
                        .map(\.id)
                    let uName = UnitConfig.stats(for: targetUnitType)?.name ?? ""
                    onInteractionFeedback?("双击全选同类兵种【\(uName)】（共 \(selectedSquadIds.count) 支编队）")
                } else if shiftHeld {
                    if let idx = selectedSquadIds.firstIndex(of: pickedId) {
                        selectedSquadIds.remove(at: idx)
                    } else {
                        selectedSquadIds.append(pickedId)
                    }
                    onInteractionFeedback?("Shift 编队增减选：当前选中 \(selectedSquadIds.count) 支编队")
                } else {
                    selectedSquadIds = [pickedId]
                    let sq = engine.squads[pickedId]
                    let uName = UnitConfig.stats(for: sq.primaryUnitType)?.name ?? ""
                    onInteractionFeedback?("已点选【\(uName)】（人数 \(sq.aliveCount) · 士气 \(Int(sq.morale)) · \(sq.formation.displayName)）")
                }
            } else if !shiftHeld {
                onInteractionFeedback?("点击地面 (\(Int(endLogic.x)), \(Int(endLogic.y))) —— 右键可命令当前选中编队机动至此")
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
                if shiftHeld {
                    let merged = Set(selectedSquadIds).union(boxed)
                    selectedSquadIds = merged.sorted()
                } else {
                    selectedSquadIds = boxed
                }
                onInteractionFeedback?("左键框选成功：已选中 \(selectedSquadIds.count) 支作战编队，右键点击地面/敌军即可下令！")
            } else {
                onInteractionFeedback?("框选区域内未发现未溃逃的我军编队")
            }
        }
        pushUiSyncNow()
    }

    public override func rightMouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        if engine.controlMode == .heroAction {
            heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
            heroMouseRightHeld = true
            if engine.playerHero.activeWeapon == .heavyWarbow {
                heroMouseLeftHeld = false
                onInteractionFeedback?("已收弦取消百石硬弓蓄力")
            } else if engine.playerHero.activeWeapon == .commandSaber {
                onInteractionFeedback?("🛡 主帅举盾格挡（前 0.25s 精准弹反窗口可震晕近身敌兵 1.5s）！")
            }
            return
        }

        let logicPt = logicCoordinates(fromScenePoint: pt)
        let targets = effectiveTargetSquadIds()
        guard !targets.isEmpty else {
            onInteractionFeedback?("当前无可调度编队")
            return
        }

        let appendWp = event.modifierFlags.contains(.shift)
        if let enemyHit = engine.pickEnemyTargetAtPoint(x: logicPt.x, y: logicPt.y, tolerance: 72.0) {
            // 右键点中敌军或敌城防：若当前处于坚守/撤退，自动切为稳步推进/包抄进攻！
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
            orderMarkerNode.text = "⚔️ 进攻 \(enemyHit.label)"
            orderMarkerNode.fontColor = .systemRed
            orderMarkerNode.position = scenePoint(fromLogicX: enemyHit.x, logicY: enemyHit.y)
            orderMarkerNode.isHidden = false
            orderMarkerFadeTimer = 1.8
            onInteractionFeedback?("右键锁定攻击目标 -> \(enemyHit.label)（按 F 可改走大弧线侧翼包抄，按 G 钳形合围）")
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
            orderMarkerNode.text = appendWp ? "⊕ 队列航点" : "⊕ 机动目标"
            orderMarkerNode.fontColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.32, alpha: 0.96)
            orderMarkerNode.position = pt
            orderMarkerNode.isHidden = false
            orderMarkerFadeTimer = 1.6
            onInteractionFeedback?(
                appendWp
                    ? "Shift+右键追加迂回航点 (\(Int(logicPt.x)), \(Int(logicPt.y)))"
                    : "右键下令 \(targets.count) 支编队向 (\(Int(logicPt.x)), \(Int(logicPt.y))) 保持阵型推进"
            )
        }
        pushUiSyncNow()
    }

    public override func rightMouseDragged(with event: NSEvent) {
        if engine.controlMode == .heroAction {
            let pt = event.location(in: self)
            heroAimLogicPoint = logicCoordinates(fromScenePoint: pt)
            heroMouseRightHeld = true
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        if engine.controlMode == .heroAction {
            heroMouseRightHeld = false
        }
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
        // Esc 键：呼出/关闭战场军务菜单
        if event.keyCode == 53 {
            onRequestToggleEscapeMenu?()
            return
        }
        // Tab 键：切换 RTS 上帝视角 <-> 主帅亲自上阵英雄模式
        if event.keyCode == 48 {
            if !event.isARepeat {
                _ = requestToggleControlMode()
            }
            return
        }

        pressedKeyCodes.insert(event.keyCode)
        guard !event.isARepeat else { return }

        // B 键：双视角通用本阵警钟切换
        if event.keyCode == 11 {
            toggleGarrisonBell()
            return
        }

        // Ctrl + 1~6 绑定军团编组；F1~F6 快速选定军团（连按两次镜头居中）
        if event.modifierFlags.contains(.control), let grp = Self.groupNumberForNumberKey(event.keyCode) {
            let valid = effectiveTargetSquadIds()
            controlGroups[grp] = valid
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
            case 50:      // `~` 全选主力
                selectAllCombatSquads()
            case 49, 35:  // Space / P -> 战术暂停
                toggleBattlePause()
            case 18:      // 1
                applyFormationToSelection(.phalanxRect)
            case 19:      // 2
                applyFormationToSelection(.echelonLine)
            case 20:      // 3
                applyFormationToSelection(.wedgeCharge)
            case 21:      // 4
                applyFormationToSelection(.circleDefense)
            case 12:      // Q -> 稳步推进
                applyTacticalOrderToSelection(.advance)
            case 13:      // W -> 原地坚守
                applyTacticalOrderToSelection(.holdGround)
            case 14:      // E -> 全军冲锋
                applyTacticalOrderToSelection(.allOutCharge)
            case 15:      // R -> 交替撤退
                applyTacticalOrderToSelection(.retreat)
            case 3:       // F -> 侧翼包抄
                applyTacticalOrderToSelection(.flank)
            case 5:       // G -> 钳形合围
                applyTacticalOrderToSelection(.pincerEncircle)
            case 6:       // Z -> 诈败诱敌
                applyTacticalOrderToSelection(.feignedRetreat)
            case 7:       // X -> 密林设伏
                applyTacticalOrderToSelection(.ambushHide)
            case 8:       // C -> 奇袭断粮
                applyTacticalOrderToSelection(.raidSupply)
            case 123, 124, 125, 126:
                break // 方向键由 updateCameraAndHeroInput 平滑平移
            default:
                super.keyDown(with: event)
            }

        case .heroAction:
            switch event.keyCode {
            case 18:      // 1 -> 统帅佩刀
                switchHeroWeapon(.commandSaber)
            case 19:      // 2 -> 破阵大枪
                switchHeroWeapon(.breakerSpear)
            case 20:      // 3 -> 百石硬弓
                switchHeroWeapon(.heavyWarbow)
            case 49:      // Space -> 破阵突击冲锋/闪避
                triggerHeroSkill(.breakthroughCharge)
            case 14, 21:  // E 或数字键 4 -> 铁壁横戈
                triggerHeroSkill(.ironBulwark)
            case 15, 23:  // R 或数字键 5 -> 三军战吼
                triggerHeroSkill(.grandWarCry)
            case 35:      // P -> 英雄模式暂停
                toggleBattlePause()
            case 0, 1, 2, 13, 123, 124, 125, 126:
                break // WASD 与方向键由 pressedKeyCodes 连续驱动
            default:
                super.keyDown(with: event)
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
        let isDoubleTap = (lastGroupKeyNumber == groupNumber) && (now - lastGroupKeyPressTime < 0.38)
        lastGroupKeyNumber = groupNumber
        lastGroupKeyPressTime = now
        if isDoubleTap, let firstId = ids.first {
            let sq = engine.squads[firstId]
            worldCamera.position = scenePoint(fromLogicX: sq.anchorX, logicY: sq.anchorY)
            clampCameraPosition()
            onInteractionFeedback?("已选定并居中镜头至【第 \(groupNumber) 军团】（\(ids.count) 支编队）")
        } else {
            onInteractionFeedback?("已选定【第 \(groupNumber) 军团 (F\(groupNumber))】（再按一次居中镜头）")
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
        case 122: return 1 // F1
        case 120: return 2 // F2
        case 99:  return 3 // F3
        case 118: return 4 // F4
        case 96:  return 5 // F5
        case 97:  return 6 // F6
        default:  return nil
        }
    }
}
