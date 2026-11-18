import Foundation

/// 战斗核心模块协议与帧快照契约（第 1 步：仅定义 Core <-> Render/UI 解耦接口契约，严格按督工指令暂不实现战斗核心逻辑）
/// 第 2 步将在本目录下实现：均匀空间哈希网格寻敌、双曲护甲与反骑动能破甲结算、阵型弹簧槽位、士气迟滞状态机、断粮三级惩罚与主帅两段式重伤状态机。

/// 战场断粮三阶段状态枚举（对应 DESIGN.md 10.1 边界一）
public enum BattlefieldRationStage: String, Sendable, Codable, Hashable {
    case abundant = "abundant"       // 粮草充沛
    case warning = "warning"         // 余粮 < 15s 红色告警
    case hungry = "hungry"           // 断粮 0~30s（饥饿期：停回士气、每秒 -0.8、移速 -12%）
    case starving = "starving"       // 断粮 > 30s（饥溃期：每秒 -1.8、攻击 -25%、雇佣兵离场）
}

/// 战场胜负与终局边界判定结果枚举
public enum BattleOutcomeReason: String, Sendable, Codable, Hashable {
    case ongoing = "ongoing"                         // 激战进行中
    case enemyBaseDestroyed = "enemy_base_destroyed" // 摧毁敌军本阵大营
    case enemyArmyRouted = "enemy_army_routed"       // 敌军全军溃散
    case siegeDefenseHeld = "siege_defense_held"     // 守城期满成功坚守
    case playerCommanderMartyred = "hero_martyred"   // 主帅二次阵亡或大营失守殉国
    case playerArmyRouted = "player_army_routed"     // 己方全军崩溃战败
    case truceNegotiated = "truce_negotiated"        // 战中停火协议达成
}

/// 节流同步给 SwiftUI 顶部状态栏的轻量战场快照（4Hz / 每 250ms 推送一次，避免每帧触发 SwiftUI 视图树重算）
public struct BattleHudSnapshot: Sendable, Equatable {
    public let elapsedSeconds: Double
    public let isPaused: Bool
    public let controlMode: BattleControlMode
    public let switchCooldownRemaining: Double
    public let garrisonBellActive: Bool
    public let gold: Int
    public let wood: Int
    public let grain: Double
    public let rationStage: BattlefieldRationStage
    public let playerAliveCount: Int
    public let playerPopUsed: Int
    public let playerPopCap: Int
    public let enemyAliveCount: Int
    public let averagePlayerMorale: Double
    public let heroHp: Double
    public let heroMaxHp: Double
    public let heroVitalState: HeroVitalState
    public let heroActiveWeapon: HeroWeaponType
    public let heroRemainingArrows: Int
    public let outcome: BattleOutcomeReason
    public let currentAge: ImperialAge
    public let advancingToAge: ImperialAge?
    public let ageAdvanceProgress: Double
    public let enemyCurrentAge: ImperialAge
    public let meleeForgeLevel: Int
    public let armorTemperLevel: Int
    public let fletchingLevel: Int
    public let idleSapperCount: Int
    public let activeBuildingCount: Int

    public init(
        elapsedSeconds: Double = 0.0,
        isPaused: Bool = false,
        controlMode: BattleControlMode = .rtsCommander,
        switchCooldownRemaining: Double = 0.0,
        garrisonBellActive: Bool = false,
        gold: Int = GameConstants.battleInitGold,
        wood: Int = GameConstants.battleInitWood,
        grain: Double = GameConstants.battleInitGrain,
        rationStage: BattlefieldRationStage = .abundant,
        playerAliveCount: Int = 0,
        playerPopUsed: Int = 0,
        playerPopCap: Int = GameConstants.defaultArmyPopCap,
        enemyAliveCount: Int = 0,
        averagePlayerMorale: Double = GameConstants.moraleBase,
        heroHp: Double = GameConstants.heroBaseHp,
        heroMaxHp: Double = GameConstants.heroBaseHp,
        heroVitalState: HeroVitalState = .healthyActive,
        heroActiveWeapon: HeroWeaponType = .commandSaber,
        heroRemainingArrows: Int = GameConstants.heroWarbowQuiverCap,
        outcome: BattleOutcomeReason = .ongoing,
        currentAge: ImperialAge = .age1Bronze,
        advancingToAge: ImperialAge? = nil,
        ageAdvanceProgress: Double = 0.0,
        enemyCurrentAge: ImperialAge = .age1Bronze,
        meleeForgeLevel: Int = 0,
        armorTemperLevel: Int = 0,
        fletchingLevel: Int = 0,
        idleSapperCount: Int = 0,
        activeBuildingCount: Int = 1
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.isPaused = isPaused
        self.controlMode = controlMode
        self.switchCooldownRemaining = switchCooldownRemaining
        self.garrisonBellActive = garrisonBellActive
        self.gold = gold
        self.wood = wood
        self.grain = grain
        self.rationStage = rationStage
        self.playerAliveCount = playerAliveCount
        self.playerPopUsed = playerPopUsed
        self.playerPopCap = playerPopCap
        self.enemyAliveCount = enemyAliveCount
        self.averagePlayerMorale = averagePlayerMorale
        self.heroHp = heroHp
        self.heroMaxHp = heroMaxHp
        self.heroVitalState = heroVitalState
        self.heroActiveWeapon = heroActiveWeapon
        self.heroRemainingArrows = heroRemainingArrows
        self.outcome = outcome
        self.currentAge = currentAge
        self.advancingToAge = advancingToAge
        self.ageAdvanceProgress = ageAdvanceProgress
        self.enemyCurrentAge = enemyCurrentAge
        self.meleeForgeLevel = meleeForgeLevel
        self.armorTemperLevel = armorTemperLevel
        self.fletchingLevel = fletchingLevel
        self.idleSapperCount = idleSapperCount
        self.activeBuildingCount = activeBuildingCount
    }
}

/// 玩家在 macOS 键鼠下发出的 RTS 战术编队调度请求（支持战术暂停期间预下达与《罗马全面战争》右键拖拽拉阵线）
public struct SquadCommandRequest: Sendable, Equatable {
    public let squadIds: [Int]
    public let formation: FormationType?
    public let order: TacticalOrder?
    public let targetWorldX: Double?
    public let targetWorldY: Double?
    public let appendWaypoint: Bool
    public let explicitFacingRadians: Double?
    public let lineSpreadMultiplier: Double?

    public init(
        squadIds: [Int],
        formation: FormationType? = nil,
        order: TacticalOrder? = nil,
        targetWorldX: Double? = nil,
        targetWorldY: Double? = nil,
        appendWaypoint: Bool = false,
        explicitFacingRadians: Double? = nil,
        lineSpreadMultiplier: Double? = nil
    ) {
        self.squadIds = squadIds
        self.formation = formation
        self.order = order
        self.targetWorldX = targetWorldX
        self.targetWorldY = targetWorldY
        self.appendWaypoint = appendWaypoint
        self.explicitFacingRadians = explicitFacingRadians
        self.lineSpreadMultiplier = lineSpreadMultiplier
    }
}

/// 玩家在英雄模式下通过 WASD + 鼠标瞄准输入的即时操控帧向量
public struct HeroControlInputState: Sendable, Equatable {
    public var moveAxisX: Double
    public var moveAxisY: Double
    public var aimWorldX: Double
    public var aimWorldY: Double
    public var isPrimaryAttackHeld: Bool
    public var isSecondaryBlockHeld: Bool

    public init(
        moveAxisX: Double = 0.0,
        moveAxisY: Double = 0.0,
        aimWorldX: Double = 0.0,
        aimWorldY: Double = 0.0,
        isPrimaryAttackHeld: Bool = false,
        isSecondaryBlockHeld: Bool = false
    ) {
        self.moveAxisX = moveAxisX
        self.moveAxisY = moveAxisY
        self.aimWorldX = aimWorldX
        self.aimWorldY = aimWorldY
        self.isPrimaryAttackHeld = isPrimaryAttackHeld
        self.isSecondaryBlockHeld = isSecondaryBlockHeld
    }
}

/// 确定性战斗模拟引擎抽象协议（供第 2 步核心实现及 XCTest 无头模拟测试对接）
public protocol BattleSimulationEngineProtocol: Sendable {
    /// 当前 HUD 节流快照
    var latestHudSnapshot: BattleHudSnapshot { get }
    /// 推进单步确定性逻辑帧（标准 dt = 1/30 秒）
    mutating func stepLogicTick(deltaTime: Double)
    /// 提交分队阵型与战术指令（允许在空格战术暂停状态下预下令）
    mutating func issueSquadCommand(_ request: SquadCommandRequest)
    /// 切换大营本阵警钟状态（工兵入营协防 <-> 出营复工）
    mutating func toggleGarrisonBell()
}
