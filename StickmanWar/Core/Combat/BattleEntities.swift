import Foundation

/// 战斗核心实体、预分配对象池槽位与战场环境数据结构（纯值类型 Sendable，零 UI / SpriteKit 耦合）
/// 严格对齐 DESIGN.md、GameTypes.swift、GameConstants.swift 与 CombatContracts.swift。

// MARK: - 一、阵营、确定性随机数与战前编成配置

/// 战场对阵双方标识
public enum BattleSide: Int, CaseIterable, Sendable, Codable, Hashable {
    case player = 0
    case enemy = 1

    public var opponent: BattleSide {
        self == .player ? .enemy : .player
    }
}

/// 确定性无锁伪随机数发生器（SplitMix64 值类型，保证逻辑帧复现与 XCTest 断言完全确定）
public struct DeterministicRNG: Sendable, Codable, Equatable, Hashable {
    public private(set) var state: UInt64

    public init(seed: UInt64 = 0x5354_4943_4B57_4152) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 返回 [0.0, 1.0) 区间的确定性双精度浮点数
    public mutating func nextUnitDouble() -> Double {
        let upper53 = nextUInt64() >> 11
        return Double(upper53) * (1.0 / 9007199254740992.0)
    }

    /// 返回 [min, max] 区间的确定性浮点数
    public mutating func nextRange(min: Double, max: Double) -> Double {
        guard max > min else { return min }
        return min + (max - min) * nextUnitDouble()
    }
}

/// 战前自定义军团兵表条目
public struct BattleArmyRosterEntry: Sendable, Codable, Equatable, Hashable {
    public let corpsRole: ArmyCorpsRole
    public let unitType: UnitTypeId
    public let count: Int
    public let initialFormation: FormationType

    public init(
        corpsRole: ArmyCorpsRole,
        unitType: UnitTypeId,
        count: Int,
        initialFormation: FormationType = .phalanxRect
    ) {
        self.corpsRole = corpsRole
        self.unitType = unitType
        self.count = max(1, count)
        self.initialFormation = initialFormation
    }
}

/// 开战扩展部署配置（支持战役粮道跳数修正、背盟士气惩罚、围点打援敌军士气暴跌、主帅战役虚弱态、自定义演武兵表与确定性随机种子）
public struct BattleDeploymentConfig: Sendable, Equatable {
    public var customPlayerRoster: [BattleArmyRosterEntry]?
    public var customEnemyRoster: [BattleArmyRosterEntry]?
    public var playerInitialGold: Int
    public var playerInitialWood: Int
    public var playerInitialGrain: Double
    public var enemyInitialGrain: Double
    public var playerSupplyStatus: SupplyLineStatus
    public var playerBetrayalMoralePenalty: Double
    public var enemyInitialMoraleDelta: Double
    public var isPlayerCommanderWeakened: Bool
    public var applySupplyGrainDiscountInEngine: Bool
    public var siegeHoldTargetSeconds: Double
    public var randomSeed: UInt64

    public init(
        customPlayerRoster: [BattleArmyRosterEntry]? = nil,
        customEnemyRoster: [BattleArmyRosterEntry]? = nil,
        playerInitialGold: Int = GameConstants.battleInitGold,
        playerInitialWood: Int = GameConstants.battleInitWood,
        playerInitialGrain: Double = GameConstants.battleInitGrain,
        enemyInitialGrain: Double = GameConstants.battleInitGrain,
        playerSupplyStatus: SupplyLineStatus = .fullSupply(hops: 1),
        playerBetrayalMoralePenalty: Double = 0.0,
        enemyInitialMoraleDelta: Double = 0.0,
        isPlayerCommanderWeakened: Bool = false,
        applySupplyGrainDiscountInEngine: Bool = true,
        siegeHoldTargetSeconds: Double = 180.0,
        randomSeed: UInt64 = 0x2026_1118_5357_4152
    ) {
        self.customPlayerRoster = customPlayerRoster
        self.customEnemyRoster = customEnemyRoster
        self.playerInitialGold = playerInitialGold
        self.playerInitialWood = playerInitialWood
        self.playerInitialGrain = playerInitialGrain
        self.enemyInitialGrain = enemyInitialGrain
        self.playerSupplyStatus = playerSupplyStatus
        self.playerBetrayalMoralePenalty = playerBetrayalMoralePenalty
        self.enemyInitialMoraleDelta = enemyInitialMoraleDelta
        self.isPlayerCommanderWeakened = isPlayerCommanderWeakened
        self.applySupplyGrainDiscountInEngine = applySupplyGrainDiscountInEngine
        self.siegeHoldTargetSeconds = siegeHoldTargetSeconds
        self.randomSeed = randomSeed
    }
}

// MARK: - 二、地形功能区、野外资源点、陷阱与攻城建筑实体

/// 战场矩形地形功能区（支持河流浅滩、高地山脊、密林伏击区、桥梁窄口与城墙掩体）
public struct TerrainZoneRect: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let terrain: TerrainType
    public let minX: Double
    public let maxX: Double
    public let minY: Double
    public let maxY: Double
    /// 海拔层级：0 涉水低谷，1 标准平原，2 制高点 / 城头
    public let elevationLevel: Int

    public init(
        id: Int,
        terrain: TerrainType,
        minX: Double,
        maxX: Double,
        minY: Double,
        maxY: Double,
        elevationLevel: Int = 1
    ) {
        self.id = id
        self.terrain = terrain
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
        self.elevationLevel = elevationLevel
    }

    @inline(__always)
    public func contains(x: Double, y: Double) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }
}

/// 野外可采集资源点类别
public enum ResourceNodeKind: String, CaseIterable, Sendable, Codable, Hashable {
    case goldMine = "gold_mine"
    case lumberForest = "lumber_forest"
    case grainFarm = "grain_farm"
}

/// 战场野外资源点实体（金矿脉、林木区、农庄粮垛）
public struct BattleResourceNode: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let kind: ResourceNodeKind
    public let x: Double
    public let y: Double
    public var remainingAmount: Double
    public let yieldPerTrip: Double
    public let gatherDurationSec: Double

    public init(
        id: Int,
        kind: ResourceNodeKind,
        x: Double,
        y: Double,
        remainingAmount: Double,
        yieldPerTrip: Double,
        gatherDurationSec: Double
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.remainingAmount = remainingAmount
        self.yieldPerTrip = yieldPerTrip
        self.gatherDurationSec = gatherDurationSec
    }
}

/// 战场战术陷阱种类（雾林猎手等可布设）
public enum FieldTrapKind: String, CaseIterable, Sendable, Codable, Hashable {
    case spikePit = "spike_pit"   // 尖刺陷坑：范围穿刺伤 + 减速
    case tripwire = "tripwire"    // 绊马索：强制终止骑兵冲锋并坠马眩晕 3s
}

/// 战场陷阱实体
public struct BattleFieldTrap: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let side: BattleSide
    public let kind: FieldTrapKind
    public let x: Double
    public let y: Double
    public let radius: Double
    public var remainingCharges: Int
    public var isTriggered: Bool

    public init(
        id: Int,
        side: BattleSide,
        kind: FieldTrapKind,
        x: Double,
        y: Double,
        radius: Double = 36.0,
        remainingCharges: Int = 2,
        isTriggered: Bool = false
    ) {
        self.id = id
        self.side = side
        self.kind = kind
        self.x = x
        self.y = y
        self.radius = radius
        self.remainingCharges = remainingCharges
        self.isTriggered = isTriggered
    }
}

/// 战场大营、攻防城工事与《指尖帝国》RTS 可营建基地建筑类别
public enum SiegeStructureKind: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case baseCamp = "base_camp"           // 主城议政厅 / 本阵大营（含随军粮仓、时代演进与医帐）
    case mainGate = "main_gate"           // 瓮城正门（可被巨斧破甲劈砍或投石轰击）
    case sideSallyGate = "side_sally"     // 侧门暗道（守军轻骑出城烧投石车通道）
    case wallSegment = "wall_segment"     // 城墙段（投石车可轰塌制造缺口）
    case arrowTower = "arrow_tower"       // 警戒箭塔（自动索敌抛射箭矢，玩家亦可在前线营建！）
    case woodenCheval = "wooden_cheval"   // 拒马木栅（反制冲锋铁骑）
    case siegeLadder = "siege_ladder"     // 登城云梯（步兵攀城通道）
    // 《指尖帝国》×《罗马帝国》RTS 基地营建扩展建筑
    case houseQuarter = "house_quarter"   // 军屯民居（人口上限 +16，微量民税）
    case imperialFarm = "imperial_farm"   // 屯田农庄（持续产出粮草 +3.4/s，彻底支撑持久大战）
    case barracks = "barracks"            // 步兵军营（步兵/长柄训练提速 +35% 并可前推集结）
    case archeryRange = "archery_range"   // 神机靶场（远程弓弩训练提速 +35%）
    case stables = "stables"              // 皇家马厩（时代 II 解锁，铁骑训练提速 +35%）
    case blacksmith = "blacksmith"        // 军械铁匠铺（解锁锋刃/重甲/羽箭三系 1~3 级锻造）
    case siegeWorkshop = "siege_workshop" // 攻城器械所（时代 III 解锁，器械建造提速 +40%、拆城 +15%）

    public var id: String { rawValue }

    /// 玩家在 RTS 面板可主动点击建造的 8 类帝国建筑列表
    public static let constructibleBuildings: [SiegeStructureKind] = [
        .houseQuarter, .imperialFarm, .barracks, .archeryRange,
        .blacksmith, .stables, .arrowTower, .siegeWorkshop
    ]

    public var displayName: String {
        switch self {
        case .baseCamp: return "军政主城"
        case .mainGate: return "瓮城正门"
        case .sideSallyGate: return "侧门暗道"
        case .wallSegment: return "巨石城墙"
        case .arrowTower: return "警戒箭塔"
        case .woodenCheval: return "拒马木栅"
        case .siegeLadder: return "登城云梯"
        case .houseQuarter: return "军屯民居"
        case .imperialFarm: return "屯田农庄"
        case .barracks: return "步兵军营"
        case .archeryRange: return "神机靶场"
        case .stables: return "皇家马厩"
        case .blacksmith: return "军械铁匠铺"
        case .siegeWorkshop: return "攻城器械所"
        }
    }

    public var requiredAge: ImperialAge {
        switch self {
        case .stables, .arrowTower:
            return .age2IronCity
        case .siegeWorkshop:
            return .age3Imperial
        default:
            return .age1Bronze
        }
    }

    public var buildCost: ResourceCost? {
        switch self {
        case .houseQuarter: return ResourceCost(gold: 0, wood: 50, grain: 0)
        case .imperialFarm: return ResourceCost(gold: 15, wood: 70, grain: 0)
        case .barracks: return ResourceCost(gold: 40, wood: 110, grain: 0)
        case .archeryRange: return ResourceCost(gold: 50, wood: 115, grain: 0)
        case .blacksmith: return ResourceCost(gold: 70, wood: 95, grain: 0)
        case .stables: return ResourceCost(gold: 75, wood: 125, grain: 0)
        case .arrowTower: return ResourceCost(gold: 85, wood: 110, grain: 0)
        case .siegeWorkshop: return ResourceCost(gold: 110, wood: 160, grain: 0)
        default: return nil
        }
    }

    public var buildTimeSec: Double {
        switch self {
        case .houseQuarter: return 6.0
        case .imperialFarm: return 7.5
        case .barracks, .archeryRange, .blacksmith: return 10.0
        case .stables, .arrowTower: return 12.0
        case .siegeWorkshop: return 15.0
        default: return 8.0
        }
    }

    public var defaultFootprint: (width: Double, height: Double, hp: Double, armor: Double) {
        switch self {
        case .baseCamp: return (168.0, 290.0, 2800.0, 44.0)
        case .houseQuarter: return (78.0, 68.0, 680.0, 22.0)
        case .imperialFarm: return (112.0, 90.0, 720.0, 16.0)
        case .barracks: return (118.0, 94.0, 1400.0, 32.0)
        case .archeryRange: return (116.0, 90.0, 1250.0, 28.0)
        case .stables: return (124.0, 96.0, 1450.0, 32.0)
        case .blacksmith: return (98.0, 84.0, 1300.0, 36.0)
        case .siegeWorkshop: return (130.0, 102.0, 1550.0, 36.0)
        case .arrowTower: return (78.0, 78.0, 1150.0, 40.0)
        case .mainGate: return (72.0, 220.0, 1850.0, 32.0)
        case .sideSallyGate: return (68.0, 150.0, 1150.0, 36.0)
        case .wallSegment: return (72.0, 660.0, 2300.0, 58.0)
        case .woodenCheval: return (42.0, 95.0, 460.0, 18.0)
        case .siegeLadder: return (44.0, 80.0, 900.0, 20.0)
        }
    }

    public var roleSummary: String {
        switch self {
        case .houseQuarter: return "人口上限 +16 · 民税 +0.35金/s"
        case .imperialFarm: return "持续产粮 +3.4粮/s · 永续后勤"
        case .barracks: return "步兵/长枪训练提速 +35% · 前推兵站"
        case .archeryRange: return "弓弩远程训练提速 +35%"
        case .blacksmith: return "解锁百炼锋刃/重甲/羽箭 1~3 级锻造"
        case .stables: return "机动铁骑训练提速 +35%（需时代 II）"
        case .arrowTower: return "自动射杀 390px 内来犯敌军（需时代 II）"
        case .siegeWorkshop: return "重器建造提速 +40% · 破城 +15%（需时代 III）"
        default: return displayName
        }
    }
}

/// 本阵大营、城门、城墙、箭塔与 RTS 基地建筑实体
public struct SiegeStructureEntity: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let side: BattleSide
    public let kind: SiegeStructureKind
    public var x: Double
    public var y: Double
    public let width: Double
    public let height: Double
    public var hp: Double
    public var maxHp: Double
    public let armor: Double
    public var attackCooldown: Double
    public var isDestroyed: Bool
    /// 本阵大营随军粮车是否已被奇袭劫掠（单次可夺取 150 应急粮草，苍狼翻倍）
    public var granaryLooted: Bool
    /// 是否正在夯土施工建造中（0.0 ~ 1.0 进度）
    public var isUnderConstruction: Bool
    public var constructionProgress: Double
    public var totalBuildTimeSec: Double

    public init(
        id: Int,
        side: BattleSide,
        kind: SiegeStructureKind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        hp: Double,
        armor: Double = 35.0,
        attackCooldown: Double = 0.0,
        isDestroyed: Bool = false,
        granaryLooted: Bool = false,
        isUnderConstruction: Bool = false,
        constructionProgress: Double = 1.0,
        totalBuildTimeSec: Double = 8.0
    ) {
        self.id = id
        self.side = side
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.hp = hp
        self.maxHp = isUnderConstruction ? max(hp, kind.defaultFootprint.hp) : hp
        self.armor = armor
        self.attackCooldown = attackCooldown
        self.isDestroyed = isDestroyed
        self.granaryLooted = granaryLooted
        self.isUnderConstruction = isUnderConstruction
        self.constructionProgress = constructionProgress
        self.totalBuildTimeSec = max(1.0, totalBuildTimeSec)
    }
}

// MARK: - 三、分队建制与战术航点状态

/// 分队机动航点结构
public struct SquadWaypoint: Sendable, Codable, Equatable, Hashable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 独立作战分队 / 军团建制实时状态
public struct BattleSquadState: Sendable, Equatable, Identifiable {
    public let id: Int
    public let side: BattleSide
    public let faction: FactionId
    public let corpsRole: ArmyCorpsRole
    public let primaryUnitType: UnitTypeId
    public var formation: FormationType
    public var order: TacticalOrder

    public var anchorX: Double
    public var anchorY: Double
    public var facingRadians: Double
    public var targetX: Double
    public var targetY: Double
    public var waypoints: [SquadWaypoint]

    /// 当前士气 [0, 100]
    public var morale: Double
    /// 四阶士气档位（含 20 溃逃 -> 32 重整迟滞环）
    public var moraleBracket: MoraleBracket
    /// 是否处于失控溃逃态
    public var isRouting: Bool
    /// 八象限受围态势（每 0.5s 刷新）
    public var encirclementState: EncirclementState
    /// 周围 160px 内受敌八象限位掩码
    public var engagedOctantMask: UInt8
    /// 正在交战的不同敌军分队数
    public var engagedEnemySquadCount: Int
    /// 当前分队成员涉水比例 [0, 1]（30%~80% 触发半渡而击易伤）
    public var riverWadingRatio: Double
    /// 本次渡河是否已结算过一次性 -12 士气半渡震慑
    public var halfFordShockApplied: Bool

    /// 本军团执旗官在士兵池中的下标（-1 表示已阵亡）
    public var bannerUnitIndex: Int
    /// 执旗官被斩后的阵型失效倒计时（12s）
    public var bannerLostPenaltyTimer: Double
    /// 主帅【三军战吼】攻移速 +15% 增益倒计时（8s）
    public var warCryBuffTimer: Double
    /// 【诈败诱敌】阶段计时器
    public var feignedRetreatTimer: Double

    public var initialCount: Int
    public var aliveCount: Int
    /// 是否为沙漠商盟纯金币雇佣军团
    public var isMercenary: Bool
    /// 军团实战老兵星级（0 新锐 -> 1 百战 ★ -> 2 精锐 ★★ -> 3 传奇鹰旗卫 ★★★）
    public var veterancyStars: Int
    public var totalKills: Int
    /// 《罗马全面战争》右键拉阵线横向展开系数 (0.55 ~ 2.20)
    public var lineSpreadMultiplier: Double

    public init(
        id: Int,
        side: BattleSide,
        faction: FactionId,
        corpsRole: ArmyCorpsRole,
        primaryUnitType: UnitTypeId,
        formation: FormationType,
        order: TacticalOrder,
        anchorX: Double,
        anchorY: Double,
        facingRadians: Double,
        morale: Double = GameConstants.moraleBase,
        isMercenary: Bool = false,
        veterancyStars: Int = 0
    ) {
        self.id = id
        self.side = side
        self.faction = faction
        self.corpsRole = corpsRole
        self.primaryUnitType = primaryUnitType
        self.formation = formation
        self.order = order
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.facingRadians = facingRadians
        self.targetX = anchorX
        self.targetY = anchorY
        self.waypoints = []
        self.morale = morale
        self.moraleBracket = .steady
        self.isRouting = false
        self.encirclementState = .clear
        self.engagedOctantMask = 0
        self.engagedEnemySquadCount = 0
        self.riverWadingRatio = 0.0
        self.halfFordShockApplied = false
        self.bannerUnitIndex = -1
        self.bannerLostPenaltyTimer = 0.0
        self.warCryBuffTimer = 0.0
        self.feignedRetreatTimer = 0.0
        self.initialCount = 0
        self.aliveCount = 0
        self.isMercenary = isMercenary
        self.veterancyStars = max(0, min(3, veterancyStars))
        self.totalKills = 0
        self.lineSpreadMultiplier = 1.0
    }

    /// 阵型属性修正是否生效（执旗官被斩 12s 内或处于溃逃态时阵型加成失效）
    public var isFormationBonusActive: Bool {
        !isRouting && bannerLostPenaltyTimer <= 0.0
    }
}

// MARK: - 四、预分配连续实体池结构（600 士兵 / 400 投射物 / 150 遗骸 / 300 粒子）

/// 单名火柴人士兵实体槽位（预分配定长 600 槽位复用，帧内零堆内存分配）
public struct SoldierEntity: Sendable, Equatable {
    public let index: Int
    public var isActive: Bool
    public var side: BattleSide
    public var faction: FactionId
    public var squadId: Int
    public var corpsRole: ArmyCorpsRole
    public var unitType: UnitTypeId
    public var category: UnitCategory

    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var facingRadians: Double
    public var slotOffsetX: Double
    public var slotOffsetY: Double
    public var collisionRadius: Double

    public var hp: Double
    public var maxHp: Double
    public var baseAttack: Double
    public var baseArmor: Double
    public var armorPenetration: Double
    public var shieldRangedBlock: Double
    public var attackRange: Double
    public var minRange: Double
    public var attackInterval: Double
    public var baseMoveSpeed: Double
    public var chargeMultiplier: Double
    public var antiCavalryMultiplier: Double

    public var actionState: UnitActionState
    public var actionTimer: Double
    public var attackCooldown: Double
    /// 供第 3 步 8 关节骨骼动画渲染直接采样的连续相位
    public var animPhase: Double

    /// 连续高速直线助跑时长（满 2.5s 激活冲锋首击倍率）
    public var straightSprintDuration: Double
    public var isChargeReady: Bool
    public var chargeCooldown: Double
    /// 长枪/戟兵停步正面架枪迎骑状态
    public var isBraced: Bool
    /// 铁鹰神弩手换弹转身背大盾状态（减免 60% 箭伤）
    public var isReloadingBackShield: Bool

    /// 炎龙神机重卫剩余震天火雷投掷次数
    public var grenadeCharges: Int
    /// 雾林影袭神射密林/脱战潜行状态
    public var isStealthed: Bool
    public var outOfCombatTimer: Double
    /// 中毒减速与持续流血计时器
    public var poisonSlowTimer: Double
    public var poisonDotTimer: Double
    /// 弹反/破阵/绊马索眩晕硬直计时器
    public var stunTimer: Double
    /// 黄金马穆鲁克骆驼惊马光环受扰计时器（移速与冲锋伤 -25%）
    public var camelSpookedTimer: Double

    /// 是否为本军团高辨识度执旗官
    public var isBannerBearer: Bool
    /// 工兵鸣响警钟退入本阵营寨箭孔协防态
    public var isGarrisonedInCamp: Bool
    public var gatherTargetNodeId: Int
    public var carryingResourceKind: ResourceNodeKind?
    public var carryingAmount: Double
    public var gatherProgressTimer: Double
    /// 工兵当前奉命前往夯土建造的目标建筑下标（-1 表示无营建任务）
    public var buildTargetStructureId: Int
    /// 单兵累积斩获与老兵星级（0~3）
    public var killsCount: Int
    public var veterancyStars: Int
    /// 是否处于对方战争迷雾可见视野内
    public var isVisibleToOpponent: Bool

    public static func inactiveSlot(index: Int) -> SoldierEntity {
        SoldierEntity(
            index: index,
            isActive: false,
            side: .player,
            faction: .yanlong,
            squadId: -1,
            corpsRole: .vanguardCenter,
            unitType: .shieldSwordsman,
            category: .infantry,
            x: 0.0,
            y: 0.0,
            vx: 0.0,
            vy: 0.0,
            facingRadians: 0.0,
            slotOffsetX: 0.0,
            slotOffsetY: 0.0,
            collisionRadius: 8.0,
            hp: 0.0,
            maxHp: 1.0,
            baseAttack: 0.0,
            baseArmor: 0.0,
            armorPenetration: 0.0,
            shieldRangedBlock: 0.0,
            attackRange: 26.0,
            minRange: 0.0,
            attackInterval: 1.0,
            baseMoveSpeed: 60.0,
            chargeMultiplier: 1.0,
            antiCavalryMultiplier: 1.0,
            actionState: .idleReady,
            actionTimer: 0.0,
            attackCooldown: 0.0,
            animPhase: 0.0,
            straightSprintDuration: 0.0,
            isChargeReady: false,
            chargeCooldown: 0.0,
            isBraced: false,
            isReloadingBackShield: false,
            grenadeCharges: 0,
            isStealthed: false,
            outOfCombatTimer: 0.0,
            poisonSlowTimer: 0.0,
            poisonDotTimer: 0.0,
            stunTimer: 0.0,
            camelSpookedTimer: 0.0,
            isBannerBearer: false,
            isGarrisonedInCamp: false,
            gatherTargetNodeId: -1,
            carryingResourceKind: nil,
            carryingAmount: 0.0,
            gatherProgressTimer: 0.0,
            buildTargetStructureId: -1,
            killsCount: 0,
            veterancyStars: 0,
            isVisibleToOpponent: true
        )
    }
}

/// 战场投射物种类
public enum ProjectileKind: String, CaseIterable, Sendable, Codable, Hashable {
    case arrow = "arrow"                       // 复合弓箭 / 骑射箭 / 营寨协防箭
    case crossbowBolt = "crossbow_bolt"        // 铁鹰踏张重弩矢
    case venomArrow = "venom_arrow"            // 雾林破隐毒箭
    case ballistaBolt = "ballista_bolt"        // 破甲连弩车巨箭（直线贯穿 3 人）
    case trebuchetBoulder = "boulder"          // 配重投石车巨石（面杀伤 + 350% 拆建筑 + 崩士气）
    case thunderGrenade = "thunder_grenade"    // 炎龙神机火雷（破甲爆炸 + 敌士气 -12）
    case heroHeavyArrow = "hero_heavy_arrow"   // 主帅百石硬弓重箭（贯穿 2 人）
    case towerArrow = "tower_arrow"            // 守城箭塔箭矢
}

/// 投射物实体槽位（预分配定长 400 槽位复用，采用定长三元组记录贯穿去重，零堆分配）
public struct ProjectileEntity: Sendable, Equatable {
    public let index: Int
    public var isActive: Bool
    public var kind: ProjectileKind
    public var side: BattleSide
    /// 发射单位下标（-1 为城防箭塔，-2 为主帅英雄）
    public var sourceUnitIndex: Int

    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var originX: Double
    public var originY: Double
    public var targetX: Double
    public var targetY: Double

    public var flightElapsed: Double
    public var flightDuration: Double
    public var arcHeight: Double

    public var damage: Double
    public var armorPenetration: Double
    public var aoeRadius: Double
    public var remainingPierces: Int
    public var appliesPoison: Bool
    public var moraleShock: Double
    public var structureBonusMultiplier: Double

    /// 记录已贯穿命中的最多 3 个单位下标，杜绝同一支穿透箭多帧重复结算同一士兵
    public var piercedUnit0: Int
    public var piercedUnit1: Int
    public var piercedUnit2: Int

    public static func inactiveSlot(index: Int) -> ProjectileEntity {
        ProjectileEntity(
            index: index,
            isActive: false,
            kind: .arrow,
            side: .player,
            sourceUnitIndex: -1,
            x: 0.0,
            y: 0.0,
            vx: 0.0,
            vy: 0.0,
            originX: 0.0,
            originY: 0.0,
            targetX: 0.0,
            targetY: 0.0,
            flightElapsed: 0.0,
            flightDuration: 1.0,
            arcHeight: 0.0,
            damage: 0.0,
            armorPenetration: 0.0,
            aoeRadius: 0.0,
            remainingPierces: 1,
            appliesPoison: false,
            moraleShock: 0.0,
            structureBonusMultiplier: 1.0,
            piercedUnit0: -1,
            piercedUnit1: -1,
            piercedUnit2: -1
        )
    }

    @inline(__always)
    public func hasAlreadyHit(unitIndex: Int) -> Bool {
        piercedUnit0 == unitIndex || piercedUnit1 == unitIndex || piercedUnit2 == unitIndex
    }

    @inline(__always)
    public mutating func recordHit(unitIndex: Int) {
        if piercedUnit0 == -1 {
            piercedUnit0 = unitIndex
        } else if piercedUnit1 == -1 {
            piercedUnit1 = unitIndex
        } else if piercedUnit2 == -1 {
            piercedUnit2 = unitIndex
        }
    }
}

/// 倒地遗骸与折断旌旗环形贴花槽位（定长 150 环形覆盖，烘托古战场惨烈感）
public struct CorpseDecalEntity: Sendable, Equatable {
    public let index: Int
    public var isActive: Bool
    public var side: BattleSide
    public var faction: FactionId
    public var unitType: UnitTypeId
    public var x: Double
    public var y: Double
    public var rotationRadians: Double
    public var isBrokenBanner: Bool
    public var spawnTime: Double

    public static func inactiveSlot(index: Int) -> CorpseDecalEntity {
        CorpseDecalEntity(
            index: index,
            isActive: false,
            side: .player,
            faction: .yanlong,
            unitType: .shieldSwordsman,
            x: 0.0,
            y: 0.0,
            rotationRadians: 0.0,
            isBrokenBanner: false,
            spawnTime: 0.0
        )
    }
}

/// 战场受击特效与飘字粒子类别
public enum EffectParticleKind: String, CaseIterable, Sendable, Codable, Hashable {
    case shieldSpark = "shield_spark"     // 举盾格挡火星迸溅
    case bloodSlash = "blood_slash"       // 刀枪命中残影血花
    case parryFlash = "parry_flash"       // 主帅精准弹反金光
    case explosionFire = "explosion_fire" // 震天火雷破阵火光
    case boulderDust = "boulder_dust"     // 投石巨石砸地烟尘
    case warCryWave = "warcry_wave"       // 三军战吼声浪环
    case damageNumber = "damage_number"   // 高暴击/反骑伤害飘字
}

/// 受击粒子对象池槽位（定长 300 环形覆盖复用）
public struct EffectParticleEntity: Sendable, Equatable {
    public let index: Int
    public var isActive: Bool
    public var kind: EffectParticleKind
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var lifetime: Double
    public var maxLifetime: Double
    public var numericValue: Int
    public var isCritical: Bool

    public static func inactiveSlot(index: Int) -> EffectParticleEntity {
        EffectParticleEntity(
            index: index,
            isActive: false,
            kind: .shieldSpark,
            x: 0.0,
            y: 0.0,
            vx: 0.0,
            vy: 0.0,
            lifetime: 0.0,
            maxLifetime: 0.5,
            numericValue: 0,
            isCritical: false
        )
    }
}

// MARK: - 五、单方战场后勤经济、训练队列与伤亡统计容器

/// 本阵大营训练队列项
public struct TrainingQueueItem: Sendable, Codable, Equatable, Hashable {
    public let unitType: UnitTypeId
    public let corpsRole: ArmyCorpsRole
    public var remainingSeconds: Double
    public let isMercenary: Bool

    public init(
        unitType: UnitTypeId,
        corpsRole: ArmyCorpsRole,
        remainingSeconds: Double,
        isMercenary: Bool = false
    ) {
        self.unitType = unitType
        self.corpsRole = corpsRole
        self.remainingSeconds = remainingSeconds
        self.isMercenary = isMercenary
    }
}

/// 单方战场经济、断粮递进、血月充能与伤亡统计状态
public struct SideEconomyAndMoraleState: Sendable, Equatable {
    public let side: BattleSide
    public let faction: FactionId
    public var gold: Int
    public var wood: Int
    public var grain: Double
    public var passiveGoldAccumulator: Double
    public var passiveWoodAccumulator: Double

    /// 当前断粮阶段（充沛 / <15s告警 / 0~30s饥饿 / >30s饥溃）
    public var rationStage: BattlefieldRationStage
    /// 余粮归零后的累计断粮秒数
    public var zeroGrainElapsedSec: Double
    /// 零工兵且金币 < 35 时的 25s 免费应急民夫倒计时
    public var emergencySapperTimerSec: Double
    /// 本阵警钟是否敲响（工兵入营协防）
    public var garrisonBellActive: Bool

    /// 血月祭司团【血月狂热】伤亡充能池 (0 ~ 100) 与激活剩余时长
    public var bloodMoonFervorGauge: Double
    public var bloodMoonFervorRemainingSec: Double

    /// 战役断粮 >= 2 回合传入的开局士气硬上限（正常为 100）
    public var supplyMoraleCeiling: Double
    /// 敌帅落马触发的 15s 指挥瘫痪倒计时
    public var commandParalysisTimer: Double

    public var popUsed: Int
    public var popCap: Int
    public var basePopCap: Int
    public var trainingQueue: [TrainingQueueItem]

    /// 《指尖帝国》×《罗马帝国》四时代演进与铁匠铺三系锻造等级
    public var currentAge: ImperialAge
    public var advancingToAge: ImperialAge?
    public var ageAdvanceRemainingSec: Double
    public var ageAdvanceTotalSec: Double
    public var meleeForgeLevel: Int
    public var armorTemperLevel: Int
    public var fletchingLevel: Int

    /// 战后结算精确统计项
    public var totalInitialSoldiers: Int
    public var killedCount: Int
    public var mercenaryDesertedCount: Int
    public var lootedGoldTotal: Int
    public var lootedWoodTotal: Int
    public var lootedGrainTotal: Double

    public init(
        side: BattleSide,
        faction: FactionId,
        gold: Int = GameConstants.battleInitGold,
        wood: Int = GameConstants.battleInitWood,
        grain: Double = GameConstants.battleInitGrain,
        popCap: Int = GameConstants.defaultArmyPopCap,
        supplyMoraleCeiling: Double = GameConstants.moraleMax,
        initialAge: ImperialAge = .age1Bronze
    ) {
        self.side = side
        self.faction = faction
        self.gold = gold
        self.wood = wood
        self.grain = grain
        self.passiveGoldAccumulator = 0.0
        self.passiveWoodAccumulator = 0.0
        self.rationStage = .abundant
        self.zeroGrainElapsedSec = 0.0
        self.emergencySapperTimerSec = 0.0
        self.garrisonBellActive = false
        self.bloodMoonFervorGauge = 0.0
        self.bloodMoonFervorRemainingSec = 0.0
        self.supplyMoraleCeiling = supplyMoraleCeiling
        self.commandParalysisTimer = 0.0
        self.popUsed = 0
        self.basePopCap = popCap
        self.popCap = popCap + initialAge.popCapBonus
        self.trainingQueue = []
        self.currentAge = initialAge
        self.advancingToAge = nil
        self.ageAdvanceRemainingSec = 0.0
        self.ageAdvanceTotalSec = 1.0
        self.meleeForgeLevel = 0
        self.armorTemperLevel = 0
        self.fletchingLevel = 0
        self.totalInitialSoldiers = 0
        self.killedCount = 0
        self.mercenaryDesertedCount = 0
        self.lootedGoldTotal = 0
        self.lootedWoodTotal = 0
        self.lootedGrainTotal = 0.0
    }
}
