import Foundation

// MARK: - 一、确定性伪随机数发生器（Swift 6 Sendable & Codable 可重放种子）

/// 基于 SplitMix64 的纯值类型确定性随机数生成器（确保战役推演与单元测试 100% 可重现且并发安全）
public struct CampaignDeterministicRNG: Sendable, Codable, Equatable, Hashable {
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

    /// 返回 [0.0, 1.0) 区间的确定性浮点数
    public mutating func nextUnitDouble() -> Double {
        Double(nextUInt64() >> 11) / Double(1 << 53)
    }

    /// 返回闭区间 [lower, upper] 内的确定性整数
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(nextUInt64() % span)
    }
}

// MARK: - 二、战役世界快照核心数据模型（Sendable, Codable, Equatable）

/// 军队或守军单兵种编制栈（避免非 String 字典键在 JSON 序列化时退化为数组）
public struct CampaignUnitStack: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let unitId: UnitTypeId
    public var count: Int

    public var id: UnitTypeId { unitId }

    public init(unitId: UnitTypeId, count: Int) {
        self.unitId = unitId
        self.count = max(0, count)
    }
}

/// 大地图【围点打援】预设伏兵标记（对应 DESIGN.md 4.4 节）
public struct ReliefAmbushMarker: Sendable, Codable, Equatable, Hashable {
    /// 设伏方势力
    public let ambusherFaction: FactionId
    /// 所围困的目标孤城节点 ID（打援大捷后该孤城守军士气直接 -25）
    public let besiegedTargetNodeId: String
    /// 潜伏于此咽喉节点的伏兵分队编制
    public var ambushUnits: [CampaignUnitStack]
    /// 伏兵潜伏剩余持续回合数
    public var remainingTurns: Int

    public init(
        ambusherFaction: FactionId,
        besiegedTargetNodeId: String,
        ambushUnits: [CampaignUnitStack],
        remainingTurns: Int = 3
    ) {
        self.ambusherFaction = ambusherFaction
        self.besiegedTargetNodeId = besiegedTargetNodeId
        self.ambushUnits = ambushUnits.filter { $0.count > 0 }
        self.remainingTurns = max(1, remainingTurns)
    }
}

/// 单座城关运行时动态状态（40 座城关全量持久化）
public struct CampaignNodeState: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public var owner: FactionId
    /// 城防驻军编制
    public var garrisonUnits: [CampaignUnitStack]
    /// 当前城墙耐久值
    public var wallIntegrity: Int
    /// 最大城墙耐久上限（炎龙帝国享 +20% 城防耐久加成）
    public var maxWallIntegrity: Int
    /// 最近一次 BFS 计算所得的最近仓城跳数（nil 表示粮道断绝）
    public var cachedSupplyHops: Int?
    /// 连续粮道断绝回合计数（0=正常，1=干粮红字预警，>=2=饥疲每回合逃亡减员 8%）
    public var isolatedTurns: Int
    /// 当前围困该城的敌方势力（nil 表示未被围困）
    public var underSiegeBy: FactionId?
    /// 守军士气战略修正（如遭遇【围点打援】援军覆灭后直接锐减 -25.0）
    public var garrisonMoraleModifier: Double
    /// 预设于该交通咽喉节点的【围点打援】伏兵标记
    public var reliefAmbush: ReliefAmbushMarker?

    /// 实时映射回 `CampaignContracts.swift` 定义的 `SupplyLineStatus`（无需给外部枚举强加 Codable）
    public var supplyStatus: SupplyLineStatus {
        guard let hops = cachedSupplyHops else {
            return .severed(isolatedTurns: max(1, isolatedTurns))
        }
        if hops <= GameConstants.supplyFullEfficiencyHops {
            return .fullSupply(hops: hops)
        } else if hops == 3 {
            return .extendedMarch(hops: 3)
        } else {
            return .overextended(hops: hops)
        }
    }

    public var totalGarrisonTroops: Int {
        garrisonUnits.reduce(0) { $0 + $1.count }
    }

    public init(
        id: String,
        owner: FactionId,
        garrisonUnits: [CampaignUnitStack],
        wallIntegrity: Int,
        maxWallIntegrity: Int,
        cachedSupplyHops: Int? = 0,
        isolatedTurns: Int = 0,
        underSiegeBy: FactionId? = nil,
        garrisonMoraleModifier: Double = 0.0,
        reliefAmbush: ReliefAmbushMarker? = nil
    ) {
        self.id = id
        self.owner = owner
        self.garrisonUnits = garrisonUnits.filter { $0.count > 0 }
        self.maxWallIntegrity = max(100, maxWallIntegrity)
        self.wallIntegrity = max(0, min(self.maxWallIntegrity, wallIntegrity))
        self.cachedSupplyHops = cachedSupplyHops
        self.isolatedTurns = max(0, isolatedTurns)
        self.underSiegeBy = underSiegeBy
        self.garrisonMoraleModifier = garrisonMoraleModifier
        self.reliefAmbush = reliefAmbush
    }
}

/// 八大势力战役动态运营状态
public struct CampaignFactionState: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let factionId: FactionId
    public var isEliminated: Bool
    public var gold: Int
    public var wood: Int
    public var grain: Int
    /// 外交信誉镜像 [0, 100]（与 `DiplomacyEngine` 保持强一致）
    public var credibility: Int
    /// 已研发解锁的势力专属三阶科技 ID 列表
    public var unlockedTechIds: [String]
    /// 主帅统御等级（1 ~ 10）
    public var commanderLevel: Int
    /// 主帅当前累计历练值
    public var commanderExp: Int
    /// 主帅二次阵亡后挂【重伤休养】全属性折损剩余回合数（DESIGN.md 10.2：2 回合）
    public var commanderWoundedTurns: Int
    /// 主力野战军团当前驻扎城关 ID
    public var mainArmyNodeId: String
    /// 本回合剩余战略行军点数
    public var mainArmyActionPoints: Double
    /// 主力远征借道盟友领土时的独立断粮回合计数
    public var mainArmyIsolatedTurns: Int
    /// 主力野战军团 16 兵种编制
    public var mainArmyRoster: [CampaignUnitStack]

    public var id: FactionId { factionId }

    public var totalMainArmyTroops: Int {
        mainArmyRoster.reduce(0) { $0 + $1.count }
    }

    public var usedMainArmyPop: Int {
        mainArmyRoster.reduce(0) { acc, stack in
            let pop = UnitConfig.stats(for: stack.unitId)?.popCap ?? 1
            return acc + pop * stack.count
        }
    }

    public init(
        factionId: FactionId,
        isEliminated: Bool = false,
        gold: Int,
        wood: Int,
        grain: Int,
        credibility: Int,
        unlockedTechIds: [String] = [],
        commanderLevel: Int = 1,
        commanderExp: Int = 0,
        commanderWoundedTurns: Int = 0,
        mainArmyNodeId: String,
        mainArmyActionPoints: Double = 2.0,
        mainArmyIsolatedTurns: Int = 0,
        mainArmyRoster: [CampaignUnitStack]
    ) {
        self.factionId = factionId
        self.isEliminated = isEliminated
        self.gold = max(0, gold)
        self.wood = max(0, wood)
        self.grain = max(0, grain)
        self.credibility = max(0, min(100, credibility))
        self.unlockedTechIds = unlockedTechIds
        self.commanderLevel = max(1, commanderLevel)
        self.commanderExp = max(0, commanderExp)
        self.commanderWoundedTurns = max(0, commanderWoundedTurns)
        self.mainArmyNodeId = mainArmyNodeId
        self.mainArmyActionPoints = max(0.0, mainArmyActionPoints)
        self.mainArmyIsolatedTurns = max(0, mainArmyIsolatedTurns)
        self.mainArmyRoster = mainArmyRoster.filter { $0.count > 0 }
    }
}

/// 战役胜利与终局判定状态枚举
public enum CampaignVictoryStatus: Sendable, Codable, Equatable, Hashable {
    /// 群雄逐鹿进行中
    case ongoing
    /// 统一王都胜利：玩家控制全部 8 座初始王都巨城
    case capitalUnificationVictory(winner: FactionId)
    /// 同盟霸权胜利：玩家及正式军事同盟/附庸共控 >= 32 座城关（>=80%）且控制全部 8 座王都
    case hegemonyAllianceVictory(winner: FactionId, allies: [FactionId])
    /// 战役败北：玩家势力丧失全部城关覆灭
    case playerDefeated(reason: String)
}

/// 战役战报与重大外交/粮道事件日志条目
public struct CampaignEventLogEntry: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let turnNumber: Int
    public let category: String
    public let summary: String

    public init(id: String, turnNumber: Int, category: String, summary: String) {
        self.id = id
        self.turnNumber = turnNumber
        self.category = category
        self.summary = summary
    }
}

/// 待结算的前线战斗上下文记录（衔接大地图行军触发与 `applyPostBattleSettlement`）
public struct PendingCampaignBattle: Sendable, Codable, Equatable, Hashable {
    public let attackerFaction: FactionId
    public let defenderFaction: FactionId
    public let stagingNodeId: String
    public let contestedNodeId: String
    public let scenarioType: BattleScenarioType
    public let isReliefAmbushInterception: Bool
    public let besiegedTargetNodeIdForAmbush: String?

    public init(
        attackerFaction: FactionId,
        defenderFaction: FactionId,
        stagingNodeId: String,
        contestedNodeId: String,
        scenarioType: BattleScenarioType,
        isReliefAmbushInterception: Bool = false,
        besiegedTargetNodeIdForAmbush: String? = nil
    ) {
        self.attackerFaction = attackerFaction
        self.defenderFaction = defenderFaction
        self.stagingNodeId = stagingNodeId
        self.contestedNodeId = contestedNodeId
        self.scenarioType = scenarioType
        self.isReliefAmbushInterception = isReliefAmbushInterception
        self.besiegedTargetNodeIdForAmbush = besiegedTargetNodeIdForAmbush
    }
}

/// 战前战役态势注入战场的修正参数包
public struct CampaignBattleLaunchModifiers: Sendable, Codable, Equatable, Hashable {
    /// 结合粮道跳数与苍狼 -35% 减免后的开局携行粮草
    public let initialCarryGrain: Double
    /// 玩家军团初始士气封顶上限（饥疲态为 65.0，正常 100.0）
    public let playerInitialMoraleCap: Double
    /// 玩家军团初始士气增减修正（背盟惩罚、商盟欠饷、行军遇伏等）
    public let playerInitialMoraleDelta: Double
    /// 敌方军团初始士气增减修正（围点打援孤城绝望 -25、驰援纵队遇伏 -10 等）
    public let enemyInitialMoraleDelta: Double
    /// 玩家主帅是否处于战役重伤休养虚弱期（2 回合属性折损）
    public let isPlayerCommanderWeakened: Bool

    public init(
        initialCarryGrain: Double = GameConstants.battleInitGrain,
        playerInitialMoraleCap: Double = GameConstants.moraleMax,
        playerInitialMoraleDelta: Double = 0.0,
        enemyInitialMoraleDelta: Double = 0.0,
        isPlayerCommanderWeakened: Bool = false
    ) {
        self.initialCarryGrain = initialCarryGrain
        self.playerInitialMoraleCap = playerInitialMoraleCap
        self.playerInitialMoraleDelta = playerInitialMoraleDelta
        self.enemyInitialMoraleDelta = enemyInitialMoraleDelta
        self.isPlayerCommanderWeakened = isPlayerCommanderWeakened
    }
}

/// 战俘处置三选一策略（严格对齐 `BattleResultView.swift` 的 3 个选项）
public enum CampaignPrisonerDisposition: Int, CaseIterable, Sendable, Codable, Hashable {
    /// 0：劝降收编补充轻步兵（消耗少量口粮）
    case incorporateInfantry = 0
    /// 1：遣返索取赎金并微增外交信誉（+2）
    case ransomForGoldAndCredibility = 1
    /// 2：押充随军民夫搬运辎重（补充工兵与军粮）
    case conscriptSupplyPorters = 2
}

/// 完整可编码战役全局世界快照（支持 `Codable` 直接对接 `SaveStorageManager` 本地 JSON 持久化）
public struct CampaignWorldState: Sendable, Codable, Equatable {
    public static let currentSchemaVersion: Int = SaveSlotSummary.currentSchemaVersion

    public var schemaVersion: Int
    public var campaignId: String
    public var turnNumber: Int
    public var playerFaction: FactionId
    public var victoryStatus: CampaignVictoryStatus
    /// 40 座城关动态状态字典（键为 `CampaignNodeConfig.id` String，JSON 编码原生为对象字典）
    public var nodesById: [String: CampaignNodeState]
    /// 8 大势力动态运营列表（按 `FactionId.allCases` 顺序排列）
    public var factions: [CampaignFactionState]
    /// 完整双边外交、信誉、世仇与反霸权引擎快照
    public var diplomacy: DiplomacyEngine
    /// 当前挂起待结算的前线战斗上下文
    public var pendingBattle: PendingCampaignBattle?
    /// 玩家如有 AI 敌军主动攻打本方城池，挂起待响应的守城战斗请求
    public var pendingDefensivePrompt: RouteLaunchContext?
    /// 历史累计胜场数
    public var totalBattlesWon: Int
    /// 历史累计交战场次
    public var totalBattlesFought: Int
    /// 历史累计歼敌总数
    public var totalEnemiesDefeated: Int
    /// 自增日志序号（确保日志 ID 确定性唯一，不依赖随机 UUID）
    public var nextLogSequence: Int
    /// 环形上限战报与战略事件日志（最多保留最近 120 条）
    public var eventLogs: [CampaignEventLogEntry]
    /// 确定性随机数状态
    public var rng: CampaignDeterministicRNG

    /// 便捷读取全部 28 组双边外交数组
    public var bilateralDiplomacyStates: [BilateralDiplomacyState] {
        diplomacy.bilateralStates
    }

    public init(
        schemaVersion: Int = CampaignWorldState.currentSchemaVersion,
        campaignId: String = "campaign_default",
        turnNumber: Int = 1,
        playerFaction: FactionId = .yanlong,
        victoryStatus: CampaignVictoryStatus = .ongoing,
        nodesById: [String: CampaignNodeState],
        factions: [CampaignFactionState],
        diplomacy: DiplomacyEngine,
        pendingBattle: PendingCampaignBattle? = nil,
        pendingDefensivePrompt: RouteLaunchContext? = nil,
        totalBattlesWon: Int = 0,
        totalBattlesFought: Int = 0,
        totalEnemiesDefeated: Int = 0,
        nextLogSequence: Int = 1,
        eventLogs: [CampaignEventLogEntry] = [],
        rng: CampaignDeterministicRNG = CampaignDeterministicRNG()
    ) {
        self.schemaVersion = schemaVersion
        self.campaignId = campaignId
        self.turnNumber = max(1, turnNumber)
        self.playerFaction = playerFaction
        self.victoryStatus = victoryStatus
        self.nodesById = nodesById
        self.factions = factions
        self.diplomacy = diplomacy
        self.pendingBattle = pendingBattle
        self.pendingDefensivePrompt = pendingDefensivePrompt
        self.totalBattlesWon = max(0, totalBattlesWon)
        self.totalBattlesFought = max(0, totalBattlesFought)
        self.totalEnemiesDefeated = max(0, totalEnemiesDefeated)
        self.nextLogSequence = max(1, nextLogSequence)
        self.eventLogs = eventLogs
        self.rng = rng
    }

    /// 导出供 `SaveStorageManager.writeSlotSummary` 使用的轻量槽位摘要
    public func makeSaveSlotSummary(
        slotIndex: Int,
        customTitle: String? = nil,
        updatedAtIso: String = "2026-11-18T00:00:00Z"
    ) -> SaveSlotSummary {
        let factionName = FactionConfig.config(for: playerFaction)?.name ?? playerFaction.rawValue
        let controlled = nodesById.values.filter { $0.owner == playerFaction }.count
        let resolvedTitle = customTitle ?? "\(factionName) · 第 \(turnNumber) 回合战略军档"
        return SaveSlotSummary(
            schemaVersion: schemaVersion,
            slotIndex: slotIndex,
            title: resolvedTitle,
            factionId: playerFaction,
            turnNumber: turnNumber,
            controlledNodes: controlled,
            totalBattlesWon: totalBattlesWon,
            totalEnemiesDefeated: totalEnemiesDefeated,
            updatedAtIso: updatedAtIso,
            isEmpty: false
        )
    }
}

// MARK: - 三、战役指令返回结果与回合结算报告类型

/// 内政、征募、科研与设伏操作通用执行反馈
public struct CampaignOperationResult: Sendable, Equatable {
    public let succeeded: Bool
    public let message: String

    public init(succeeded: Bool, message: String) {
        self.succeeded = succeeded
        self.message = message
    }
}

/// 大地图行军指令分支结果
public enum CampaignMarchResolution: Sendable, Equatable {
    /// 指令不合法（如道路不连通、行军力不足或军团为空）
    case invalidOrder(reason: String)
    /// 本方或同盟国境内和平移防驻扎
    case relocatedPeacefully(destinationNodeId: String, supplyStatus: SupplyLineStatus)
    /// 目标方存在有效和平/同盟条约，需二次确认是否承担背盟后果宣战（对应 DESIGN.md 10.3 强阻断弹窗）
    case requiresWarConfirmation(assessment: BetrayalImpactAssessment, targetFaction: FactionId)
    /// 正式接敌开战：生成可直接传给 `AppRouter.launchContext` 的 `RouteLaunchContext` 与战场修正包
    case battleTriggered(launchContext: RouteLaunchContext, modifiers: CampaignBattleLaunchModifiers)
}

/// 回合推进结算详报
public struct CampaignTurnResolutionReport: Sendable, Equatable {
    public let resolvedTurnNumber: Int
    public let newTurnNumber: Int
    public let playerGoldEarned: Int
    public let playerWoodEarned: Int
    public let playerGrainNetChange: Int
    public let playerTradeGoldEarned: Int
    /// 本回合处于断粮第 1 回合红字预警的玩家城关 ID 列表
    public let warningSeveredNodeIds: [String]
    /// 本回合陷入断粮第 2+ 回合【饥疲】并发生 8% 逃亡减员的玩家城关及减员人数
    public let starvationAttritionByNode: [String: Int]
    /// 本回合 AI 势力间发生的攻城易手与重大外交简报
    public let aiWorldHeadlines: [String]
    /// 若 AI 主动进犯玩家城关，返回待玩家接战的守城上下文
    public let triggeredDefensiveBattle: RouteLaunchContext?
    public let victoryStatus: CampaignVictoryStatus

    public init(
        resolvedTurnNumber: Int,
        newTurnNumber: Int,
        playerGoldEarned: Int,
        playerWoodEarned: Int,
        playerGrainNetChange: Int,
        playerTradeGoldEarned: Int,
        warningSeveredNodeIds: [String],
        starvationAttritionByNode: [String: Int],
        aiWorldHeadlines: [String],
        triggeredDefensiveBattle: RouteLaunchContext?,
        victoryStatus: CampaignVictoryStatus
    ) {
        self.resolvedTurnNumber = resolvedTurnNumber
        self.newTurnNumber = newTurnNumber
        self.playerGoldEarned = playerGoldEarned
        self.playerWoodEarned = playerWoodEarned
        self.playerGrainNetChange = playerGrainNetChange
        self.playerTradeGoldEarned = playerTradeGoldEarned
        self.warningSeveredNodeIds = warningSeveredNodeIds
        self.starvationAttritionByNode = starvationAttritionByNode
        self.aiWorldHeadlines = aiWorldHeadlines
        self.triggeredDefensiveBattle = triggeredDefensiveBattle
        self.victoryStatus = victoryStatus
    }
}

// MARK: - 四、40 城关战役全局状态机与战略 AI 回合推演引擎

/// 战役战略大地图全局推演引擎（纯值语义，Swift 6 `Sendable` & `Codable`，零 UI 依赖）
public struct CampaignTurnEngine: Sendable, Codable, Equatable {

    public static let maxEventLogEntries: Int = 120

    public private(set) var worldState: CampaignWorldState
    public let supplyService: CampaignSupplyService

    // MARK: - 初始化与标准 40 城关开局构建

    public init(
        playerFaction: FactionId = .yanlong,
        seed: UInt64 = 0x5354_4943_4B57_4152,
        supplyService: CampaignSupplyService = CampaignSupplyService()
    ) {
        self.supplyService = supplyService
        self.worldState = Self.buildInitialWorldState(
            playerFaction: playerFaction,
            seed: seed,
            supplyService: supplyService
        )
    }

    public init(
        restoredWorldState: CampaignWorldState,
        supplyService: CampaignSupplyService = CampaignSupplyService()
    ) {
        self.supplyService = supplyService
        self.worldState = restoredWorldState
    }

    /// 构建公平配平的 8 大势力 × 5 座城关 = 40 节点初始战役快照
    public static func buildInitialWorldState(
        playerFaction: FactionId,
        seed: UInt64,
        supplyService: CampaignSupplyService
    ) -> CampaignWorldState {
        let initialOwners = CampaignSupplyService.initialNodeOwners()
        var nodesMap: [String: CampaignNodeState] = [:]
        nodesMap.reserveCapacity(GameConstants.campaignNodeCount)

        for nodeCfg in CampaignMapConfig.allNodes {
            let maxWall = calculateMaxWallIntegrity(for: nodeCfg, owner: nodeCfg.initialOwner)
            let garrison = buildInitialGarrison(for: nodeCfg)
            let path = supplyService.shortestSupplyPath(
                forNodeId: nodeCfg.id,
                factionId: nodeCfg.initialOwner,
                nodeOwners: initialOwners
            )
            let hops = path.isEmpty ? nil : (path.count - 1)
            nodesMap[nodeCfg.id] = CampaignNodeState(
                id: nodeCfg.id,
                owner: nodeCfg.initialOwner,
                garrisonUnits: garrison,
                wallIntegrity: maxWall,
                maxWallIntegrity: maxWall,
                cachedSupplyHops: hops,
                isolatedTurns: path.isEmpty ? 1 : 0
            )
        }

        let diplomacy = DiplomacyEngine()
        let factions: [CampaignFactionState] = FactionId.allCases.map { fid in
            let cfg = FactionConfig.config(for: fid)
            let capId = cfg?.capitalNodeId ?? "yl_capital"
            let startCred = cfg?.startingCredibility ?? GameConstants.credibilityDefaultInit
            let startGold = (fid == .shamo) ? 1150 : 900
            let startWood = (fid == .wulin || fid == .tieying) ? 750 : 650
            let startGrain = (fid == .yanlong || fid == .canglang) ? 1500 : 1380
            let baseAp = baseCampaignActionPoints(for: fid, unlockedTechs: [])
            return CampaignFactionState(
                factionId: fid,
                isEliminated: false,
                gold: startGold,
                wood: startWood,
                grain: startGrain,
                credibility: startCred,
                unlockedTechIds: [],
                commanderLevel: 1,
                commanderExp: 0,
                commanderWoundedTurns: 0,
                mainArmyNodeId: capId,
                mainArmyActionPoints: baseAp,
                mainArmyRoster: buildStartingMainArmy(for: fid)
            )
        }

        var state = CampaignWorldState(
            playerFaction: playerFaction,
            nodesById: nodesMap,
            factions: factions,
            diplomacy: diplomacy,
            rng: CampaignDeterministicRNG(seed: seed)
        )
        let pName = FactionConfig.config(for: playerFaction)?.name ?? playerFaction.rawValue
        state.eventLogs.append(
            CampaignEventLogEntry(
                id: "log_1",
                turnNumber: 1,
                category: "战役开启",
                summary: "【\(pName)】于王都誓师出征，八大势力四十城关合纵连横正式拉开帷幕。"
            )
        )
        state.nextLogSequence = 2

        var engine = CampaignTurnEngine(restoredWorldState: state, supplyService: supplyService)
        engine.synchronizeDiplomacySnapshots()
        return engine.worldState
    }

    // MARK: - SaveStorageManager 本地存档无缝读写接口

    /// 将当前完整 `CampaignWorldState` 与 `SaveSlotSummary` 原子化持久化至 `SaveStorageManager` 指定槽位
    @discardableResult
    public func saveToStorage(
        using storageManager: SaveStorageManager,
        slotIndex: Int,
        customTitle: String? = nil,
        updatedAtIso: String? = nil
    ) throws -> SaveSlotSummary {
        try storageManager.ensureDirectoriesExist()
        let iso = updatedAtIso ?? ISO8601DateFormatter().string(from: Date())
        let summary = worldState.makeSaveSlotSummary(
            slotIndex: slotIndex,
            customTitle: customTitle,
            updatedAtIso: iso
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let worldData = try encoder.encode(worldState)
        let worldURL = Self.campaignStateFileURL(using: storageManager, slotIndex: slotIndex)
        try worldData.write(to: worldURL, options: [.atomic])
        try storageManager.writeSlotSummary(summary)
        return summary
    }

    /// 从 `SaveStorageManager` 指定槽位恢复完整战役推演引擎
    public static func loadFromStorage(
        using storageManager: SaveStorageManager,
        slotIndex: Int,
        supplyService: CampaignSupplyService = CampaignSupplyService()
    ) throws -> CampaignTurnEngine {
        let worldURL = campaignStateFileURL(using: storageManager, slotIndex: slotIndex)
        let data = try Data(contentsOf: worldURL)
        let decoded = try JSONDecoder().decode(CampaignWorldState.self, from: data)
        return CampaignTurnEngine(restoredWorldState: decoded, supplyService: supplyService)
    }

    public static func campaignStateFileURL(using storageManager: SaveStorageManager, slotIndex: Int) -> URL {
        let filename = slotIndex == 0
            ? "campaign_world_autosave_0.json"
            : "campaign_world_slot_\(slotIndex).json"
        return storageManager.savesDirectoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: - 常用状态查询辅助

    public func currentNodeOwners() -> [String: FactionId] {
        var map: [String: FactionId] = [:]
        map.reserveCapacity(worldState.nodesById.count)
        for (nid, node) in worldState.nodesById {
            map[nid] = node.owner
        }
        return map
    }

    public func factionState(for factionId: FactionId) -> CampaignFactionState {
        if let found = worldState.factions.first(where: { $0.factionId == factionId }) {
            return found
        }
        let capId = FactionConfig.config(for: factionId)?.capitalNodeId ?? "yl_capital"
        return CampaignFactionState(
            factionId: factionId,
            gold: 0,
            wood: 0,
            grain: 0,
            credibility: 60,
            mainArmyNodeId: capId,
            mainArmyRoster: []
        )
    }

    public func nodeState(for nodeId: String) -> CampaignNodeState? {
        worldState.nodesById[nodeId]
    }

    public func controlledNodes(of factionId: FactionId) -> [CampaignNodeState] {
        worldState.nodesById.values
            .filter { $0.owner == factionId }
            .sorted { $0.id < $1.id }
    }

    /// 计算指定节点当前的实时 BFS 补给路径与惩罚详情
    public func supplyRouteDetail(forNodeId nodeId: String, factionId: FactionId? = nil) -> CampaignSupplyRouteEvaluation {
        let owner = factionId ?? (worldState.nodesById[nodeId]?.owner ?? worldState.playerFaction)
        let priorTurns = worldState.nodesById[nodeId]?.isolatedTurns ?? 0
        let allies = worldState.diplomacy.alliedFactions(of: owner)
        return supplyService.evaluateNodeSupplyDetail(
            forNodeId: nodeId,
            factionId: owner,
            nodeOwners: currentNodeOwners(),
            alliedFactions: allies,
            priorIsolatedTurns: max(0, priorTurns - 1)
        )
    }

    /// 计算单位针对特定势力的非对称招募三维成本（落实炎龙器械-20%/骑兵+15%、铁鹰突击金+10%、商盟纯金雇佣军）
    public func effectiveRecruitmentCost(
        for unitId: UnitTypeId,
        factionId: FactionId,
        count: Int = 1,
        useInstantMercenaryGold: Bool = false
    ) -> ResourceCost? {
        guard count > 0, let stats = UnitConfig.stats(for: unitId) else { return nil }
        let fState = factionState(for: factionId)
        let techs = Set(fState.unlockedTechIds)

        // 苍狼汗国铁律禁造配重投石车
        if factionId == .canglang && unitId == .trebuchet {
            return nil
        }

        // 检查专属兵种合法性（沙漠商盟解锁《黄金契约》后允许用纯金雇佣盟友专属兵种）
        if let exclusiveOwner = stats.exclusiveFaction, exclusiveOwner != factionId {
            let canHireAlliedElite = factionId == .shamo
                && useInstantMercenaryGold
                && techs.contains("sm_tech_mercenary")
                && worldState.diplomacy.alliedFactions(of: .shamo).contains(exclusiveOwner)
            if !canHireAlliedElite {
                return nil
            }
        }

        var goldPerUnit = Double(stats.cost.gold)
        var woodPerUnit = Double(stats.cost.wood)
        var grainPerUnit = Double(stats.cost.grain)

        switch factionId {
        case .yanlong:
            if stats.category == .siege {
                goldPerUnit *= 0.80
                woodPerUnit *= 0.80
            } else if stats.category == .cavalry {
                goldPerUnit *= 1.15
                grainPerUnit *= 1.15
            }
        case .tieying:
            if stats.category == .shock {
                goldPerUnit *= 1.10
            }
        case .shamo:
            if useInstantMercenaryGold {
                // 沙漠商盟纯金即时征召外邦雇佣军：将木材与口粮折算为纯金币
                var pureGold = goldPerUnit + woodPerUnit * 1.15 + grainPerUnit * 0.90
                if techs.contains("sm_tech_mercenary") {
                    pureGold *= 0.80
                }
                return ResourceCost(
                    gold: Int((pureGold * Double(count)).rounded()),
                    wood: 0,
                    grain: 0
                )
            }
        default:
            break
        }

        return ResourceCost(
            gold: Int((goldPerUnit * Double(count)).rounded()),
            wood: Int((woodPerUnit * Double(count)).rounded()),
            grain: Int((grainPerUnit * Double(count)).rounded())
        )
    }

    // MARK: - 内政操作 1：征募兵员（主力军团或城防驻军）

    @discardableResult
    public mutating func recruitUnits(
        factionId: FactionId,
        unitId: UnitTypeId,
        count: Int,
        intoMainArmy: Bool = true,
        atNodeId: String? = nil,
        useInstantMercenaryGold: Bool = false
    ) -> CampaignOperationResult {
        guard count > 0 else {
            return CampaignOperationResult(succeeded: false, message: "征募数量必须大于 0")
        }
        guard let unitStats = UnitConfig.stats(for: unitId) else {
            return CampaignOperationResult(succeeded: false, message: "未知兵种标识")
        }
        let fState = factionState(for: factionId)
        guard !fState.isEliminated else {
            return CampaignOperationResult(succeeded: false, message: "该势力已覆灭，无法征兵")
        }
        if useInstantMercenaryGold && factionId != .shamo {
            return CampaignOperationResult(succeeded: false, message: "仅【沙漠商盟】享有纯金币即时征召外邦雇佣军特权")
        }
        guard let totalCost = effectiveRecruitmentCost(
            for: unitId,
            factionId: factionId,
            count: count,
            useInstantMercenaryGold: useInstantMercenaryGold
        ) else {
            return CampaignOperationResult(succeeded: false, message: "当前势力法则禁止招募【\(unitStats.name)】")
        }

        let targetNode = atNodeId ?? fState.mainArmyNodeId
        guard let node = worldState.nodesById[targetNode], node.owner == factionId else {
            return CampaignOperationResult(succeeded: false, message: "必须在己方实际控制的城关内征募兵员")
        }

        if intoMainArmy {
            let neededPop = unitStats.popCap * count
            if fState.usedMainArmyPop + neededPop > GameConstants.defaultArmyPopCap {
                return CampaignOperationResult(
                    succeeded: false,
                    message: "超出主力军团人口编制上限（\(fState.usedMainArmyPop + neededPop)/\(GameConstants.defaultArmyPopCap)）"
                )
            }
        }

        guard fState.gold >= totalCost.gold,
              fState.wood >= totalCost.wood,
              fState.grain >= totalCost.grain else {
            return CampaignOperationResult(
                succeeded: false,
                message: "军资不足：需 金\(totalCost.gold)/木\(totalCost.wood)/粮\(totalCost.grain)"
            )
        }

        mutateFaction(factionId) { fac in
            fac.gold -= totalCost.gold
            fac.wood -= totalCost.wood
            fac.grain -= totalCost.grain
            if intoMainArmy {
                Self.addUnits(unitId: unitId, count: count, to: &fac.mainArmyRoster)
            }
        }

        if !intoMainArmy {
            mutateNode(targetNode) { nd in
                Self.addUnits(unitId: unitId, count: count, to: &nd.garrisonUnits)
            }
        }

        synchronizeDiplomacySnapshots()
        appendLog(
            category: "军备征募",
            summary: "\(factionDisplayName(factionId))于【\(nodeDisplayName(targetNode))】征召 \(count) 队\(unitStats.name)。"
        )
        return CampaignOperationResult(succeeded: true, message: "成功征募 \(count) 名【\(unitStats.name)】")
    }

    // MARK: - 内政操作 2：研发势力专属三阶科技

    @discardableResult
    public mutating func researchTechnology(
        factionId: FactionId,
        techId: String
    ) -> CampaignOperationResult {
        guard let factionCfg = FactionConfig.config(for: factionId),
              let techItem = factionCfg.uniqueTechs.first(where: { $0.id == techId }) else {
            return CampaignOperationResult(succeeded: false, message: "该科技不属于本势力专属科技树")
        }

        let fState = factionState(for: factionId)
        if fState.unlockedTechIds.contains(techId) {
            return CampaignOperationResult(succeeded: false, message: "科技《\(techItem.name)》已研发完成，无需重复投入")
        }

        guard fState.gold >= techItem.cost.gold,
              fState.wood >= techItem.cost.wood,
              fState.grain >= techItem.cost.grain else {
            return CampaignOperationResult(
                succeeded: false,
                message: "研发《\(techItem.name)》资源不足：需 金\(techItem.cost.gold)/木\(techItem.cost.wood)/粮\(techItem.cost.grain)"
            )
        }

        mutateFaction(factionId) { fac in
            fac.gold -= techItem.cost.gold
            fac.wood -= techItem.cost.wood
            fac.grain -= techItem.cost.grain
            fac.unlockedTechIds.append(techId)
            if techId == "cl_tech_remount" {
                fac.mainArmyActionPoints += 0.5
            }
        }

        synchronizeDiplomacySnapshots()
        appendLog(
            category: "科技突破",
            summary: "\(factionDisplayName(factionId))完成专属军制科技《\(techItem.name)》研发！"
        )
        return CampaignOperationResult(succeeded: true, message: "成功解锁专属科技《\(techItem.name)》：\(techItem.effectSummary)")
    }

    // MARK: - 战术操作 3：大地图【围点打援】预设伏兵（打援大捷令孤城守军士气 -25）

    /// 在通往被围敌城（`besiegedTargetNodeId`）的咽喉要道节点（`ambushNodeId`）预设打援伏兵
    @discardableResult
    public mutating func setupReliefAmbush(
        factionId: FactionId,
        ambushNodeId: String,
        besiegedTargetNodeId: String,
        assignedUnits: [CampaignUnitStack]? = nil,
        durationTurns: Int = 3
    ) -> CampaignOperationResult {
        guard ambushNodeId != besiegedTargetNodeId,
              let ambushCfg = CampaignMapConfig.node(byId: ambushNodeId),
              let besiegedNode = worldState.nodesById[besiegedTargetNodeId] else {
            return CampaignOperationResult(succeeded: false, message: "设伏节点或围困目标城池无效")
        }

        guard besiegedNode.owner != factionId else {
            return CampaignOperationResult(succeeded: false, message: "围点打援目标必须为敌占城关")
        }
        guard worldState.diplomacy.status(between: factionId, and: besiegedNode.owner) == .war else {
            return CampaignOperationResult(succeeded: false, message: "须先与目标城池所属势力处于交战状态方可实施围点打援")
        }
        guard ambushCfg.neighbors.contains(besiegedTargetNodeId) else {
            return CampaignOperationResult(succeeded: false, message: "打援伏兵必须预设在直接连通目标孤城的咽喉邻接节点上")
        }

        let fState = factionState(for: factionId)
        let detachment: [CampaignUnitStack]
        if let custom = assignedUnits, !custom.filter({ $0.count > 0 }).isEmpty {
            detachment = custom.filter { $0.count > 0 }
        } else {
            // 默认从主力分拨约 25% 机动精锐设伏，若主力编制过小则直接用城关驻军协防设伏
            let extracted = fState.mainArmyRoster.compactMap { stack -> CampaignUnitStack? in
                let sub = max(1, stack.count / 4)
                return sub > 0 ? CampaignUnitStack(unitId: stack.unitId, count: sub) : nil
            }
            detachment = extracted.isEmpty ? [CampaignUnitStack(unitId: .lightCavalry, count: 6)] : extracted
        }

        mutateNode(besiegedTargetNodeId) { targetNode in
            targetNode.underSiegeBy = factionId
        }
        mutateNode(ambushNodeId) { ambushNode in
            ambushNode.reliefAmbush = ReliefAmbushMarker(
                ambusherFaction: factionId,
                besiegedTargetNodeId: besiegedTargetNodeId,
                ambushUnits: detachment,
                remainingTurns: durationTurns
            )
        }

        appendLog(
            category: "围点打援",
            summary: "\(factionDisplayName(factionId))围困【\(nodeDisplayName(besiegedTargetNodeId))】，并于咽喉【\(ambushCfg.name)】悄然布下打援伏兵！"
        )
        return CampaignOperationResult(
            succeeded: true,
            message: "已在【\(ambushCfg.name)】布设围点打援伏兵：敌方驰援纵队途经将遭伏击（初始士气 -10），打援大捷将令【\(nodeDisplayName(besiegedTargetNodeId))】守军士气直接锐减 -25！"
        )
    }

    // MARK: - 战略操作 4：主力行军与触发 6 类战场上下文 `RouteLaunchContext`

    /// 调度主力军团沿 78 条道路行军或发起进攻（自动构建野战/攻城/守城/伏击/护粮/夜袭 `RouteLaunchContext`）
    public mutating func executeMarchOrder(
        factionId: FactionId,
        toNodeId targetNodeId: String,
        preferredScenario: BattleScenarioType? = nil,
        confirmBetrayalIfNeeded: Bool = false
    ) -> CampaignMarchResolution {
        let fState = factionState(for: factionId)
        guard !fState.isEliminated, fState.totalMainArmyTroops > 0 else {
            return .invalidOrder(reason: "主力军团无可用兵力，请先在城关内征募整补")
        }
        guard fState.mainArmyActionPoints >= 0.5 else {
            return .invalidOrder(reason: "本回合主力行军力已耗尽，请推进下一回合休整")
        }

        let originNodeId = fState.mainArmyNodeId
        guard originNodeId != targetNodeId else {
            return .invalidOrder(reason: "主力军团已驻扎于目标城关")
        }
        guard let originCfg = CampaignMapConfig.node(byId: originNodeId),
              let targetCfg = CampaignMapConfig.node(byId: targetNodeId),
              let targetNodeState = worldState.nodesById[targetNodeId] else {
            return .invalidOrder(reason: "目标城关节点不存在")
        }

        let allies = worldState.diplomacy.alliedFactions(of: factionId)
        let owners = currentNodeOwners()

        // 情况 A：目标为本方或正式同盟国领土 -> 支持多跳战略机动移防（消耗对应行军点）
        if targetNodeState.owner == factionId || allies.contains(targetNodeState.owner) {
            guard let hopDistance = friendlyHopDistance(
                from: originNodeId,
                to: targetNodeId,
                factionId: factionId,
                alliedFactions: allies,
                nodeOwners: owners
            ) else {
                return .invalidOrder(reason: "目标城关与当前驻地之间缺乏连通的本方/同盟道路")
            }
            let apCost = max(0.5, Double(hopDistance) * 0.75)
            guard fState.mainArmyActionPoints + 1e-6 >= apCost else {
                return .invalidOrder(reason: "行军力不足以跨越 \(hopDistance) 跳路程（剩余 \(String(format: "%.1f", fState.mainArmyActionPoints))）")
            }

            mutateFaction(factionId) { fac in
                fac.mainArmyNodeId = targetNodeId
                fac.mainArmyActionPoints = max(0.0, fac.mainArmyActionPoints - apCost)
            }
            let status = supplyService.evaluateSupplyStatus(
                forNodeId: targetNodeId,
                factionId: factionId,
                nodeOwners: owners,
                alliedFactions: allies,
                priorIsolatedTurns: max(0, targetNodeState.isolatedTurns - 1)
            )
            return .relocatedPeacefully(destinationNodeId: targetNodeId, supplyStatus: status)
        }

        // 情况 B：目标为非友方领土 -> 必须从相邻道路节点发起跨境进军
        guard originCfg.neighbors.contains(targetNodeId) else {
            return .invalidOrder(reason: "跨境进攻必须从与【\(targetCfg.name)】直接道路相邻的前线城关发起")
        }

        let defenderFaction = targetNodeState.owner
        if worldState.diplomacy.status(between: factionId, and: defenderFaction) != .war {
            let impact = worldState.diplomacy.assessWarDeclarationImpact(attacker: factionId, target: defenderFaction)
            if impact.isBetrayalTriggered && !confirmBetrayalIfNeeded {
                return .requiresWarConfirmation(assessment: impact, targetFaction: defenderFaction)
            }
            _ = declareWar(attacker: factionId, target: defenderFaction)
        }

        // 扣除出征行军力
        mutateFaction(factionId) { fac in
            fac.mainArmyActionPoints = max(0.0, fac.mainArmyActionPoints - 1.0)
        }

        // 判定是否踏入敌方预设的【围点打援】伏击圈
        var isAmbushInterception = false
        var ambushBesiegedCityId: String? = nil
        if let marker = targetNodeState.reliefAmbush, marker.ambusherFaction != factionId {
            isAmbushInterception = true
            ambushBesiegedCityId = marker.besiegedTargetNodeId
        }

        let resolvedScenario = determineBattleScenario(
            attacker: factionId,
            targetConfig: targetCfg,
            targetState: targetNodeState,
            preferredScenario: preferredScenario,
            isAmbushTriggered: isAmbushInterception
        )
        let resolvedWeather = determineBattleWeather(
            scenario: resolvedScenario,
            terrain: targetCfg.terrain,
            attacker: factionId
        )

        // 计算前线补给与双方初始士气修正
        let originPriorIsolated = worldState.nodesById[originNodeId]?.isolatedTurns ?? 0
        let marchSupply = supplyService.evaluateMarchSupplyStatus(
            fromStagingNodeId: originNodeId,
            targetNodeId: targetNodeId,
            factionId: factionId,
            nodeOwners: owners,
            alliedFactions: worldState.diplomacy.alliedFactions(of: factionId),
            stagingPriorIsolatedTurns: max(0, originPriorIsolated - 1)
        )
        let supplyMods = supplyService.supplyModifiers(for: marchSupply, factionId: factionId)
        let initialGrain = supplyService.calculateBattleInitialGrain(
            for: marchSupply,
            factionId: factionId,
            availableFactionGrain: factionState(for: factionId).grain
        )

        var attackerMoraleDelta = worldState.diplomacy.consumePreBattleMoraleAdjustment(for: factionId)
        var defenderMoraleDelta = targetNodeState.garrisonMoraleModifier + worldState.diplomacy.consumePreBattleMoraleAdjustment(for: defenderFaction)

        if factionId == .shamo && factionState(for: .shamo).gold <= 0 {
            attackerMoraleDelta -= 8.0
        }
        if isAmbushInterception {
            // 驰援纵队行军态遭遇围点打援伏击：初始士气 -10
            attackerMoraleDelta -= 10.0
        } else if resolvedScenario == .ambush && preferredScenario == .ambush {
            // 玩家主动密林设伏奇袭敌哨：敌军初始士气 -10
            defenderMoraleDelta -= 10.0
        } else if resolvedScenario == .nightRaid {
            // 夜袭首轮震慑：血月祭司团解锁《永夜狂热》额外加深震慑
            let extraNightShock = factionState(for: factionId).unlockedTechIds.contains("xy_tech_eternalnight") ? -6.0 : 0.0
            defenderMoraleDelta += (-12.0 + extraNightShock)
        }

        let launchContext = RouteLaunchContext(
            entryMode: .campaign,
            playerFaction: factionId,
            enemyFaction: defenderFaction,
            scenarioType: resolvedScenario,
            terrain: targetCfg.terrain,
            weather: resolvedWeather,
            targetNodeId: targetNodeId
        )

        let modifiers = CampaignBattleLaunchModifiers(
            initialCarryGrain: initialGrain,
            playerInitialMoraleCap: supplyMods.battleInitialMoraleCap,
            playerInitialMoraleDelta: attackerMoraleDelta,
            enemyInitialMoraleDelta: defenderMoraleDelta,
            isPlayerCommanderWeakened: factionState(for: factionId).commanderWoundedTurns > 0
        )

        worldState.pendingBattle = PendingCampaignBattle(
            attackerFaction: factionId,
            defenderFaction: defenderFaction,
            stagingNodeId: originNodeId,
            contestedNodeId: targetNodeId,
            scenarioType: resolvedScenario,
            isReliefAmbushInterception: isAmbushInterception,
            besiegedTargetNodeIdForAmbush: ambushBesiegedCityId
        )

        return .battleTriggered(launchContext: launchContext, modifiers: modifiers)
    }

    // MARK: - 战后结算回写：`applyPostBattleSettlement(_ summary: PostBattleSettlementSummary)`

    /// 将实时大战场的战后结算摘要回写至 40 城关大地图态势（伤亡、战俘处置、缴获、主帅晋升/重伤、围点打援士气暴击与夺城胜负）
    public mutating func applyPostBattleSettlement(
        _ summary: PostBattleSettlementSummary,
        prisonerDisposition: CampaignPrisonerDisposition = .ransomForGoldAndCredibility,
        explicitTargetNodeId: String? = nil
    ) {
        let pFaction = summary.playerFaction
        let eFaction = summary.enemyFaction

        worldState.totalBattlesFought += 1
        worldState.totalEnemiesDefeated += max(0, summary.enemyKilled)
        if summary.isVictory {
            worldState.totalBattlesWon += 1
        }

        // 1. 结算我军永久阵亡（医帐救治恢复部分 `playerWoundedRecovered` 已免于永久减员，仅扣除 `playerKilled`）
        mutateFaction(pFaction) { fac in
            Self.applyCasualties(max(0, summary.playerKilled), to: &fac.mainArmyRoster, keepMinimumGuard: true)

            // 2. 累加缴获金木粮（苍狼《草原劫掠》科技额外获得战利品加成）
            let forageBonusGold = (pFaction == .canglang && fac.unlockedTechIds.contains("cl_tech_forage") && summary.isVictory) ? 60 : 0
            let forageBonusGrain = (pFaction == .canglang && fac.unlockedTechIds.contains("cl_tech_forage") && summary.isVictory) ? 110 : 0
            fac.gold += max(0, summary.lootedGold) + forageBonusGold
            fac.wood += max(0, summary.lootedWood)
            fac.grain += max(0, summary.lootedGrain) + forageBonusGrain

            // 3. 主帅历练晋升与二次阵亡【重伤休养】2 回合 Debuff（DESIGN.md 10.2）
            fac.commanderExp += max(0, summary.commanderExpGained)
            while fac.commanderExp >= fac.commanderLevel * 500 && fac.commanderLevel < 10 {
                fac.commanderExp -= fac.commanderLevel * 500
                fac.commanderLevel += 1
            }
            if summary.outcomeReason == .playerCommanderMartyred {
                fac.commanderWoundedTurns = 2
            }
        }

        // 4. 结算战俘处置三分支（对齐 BattleResultView）
        let prisoners = max(0, summary.capturedPrisoners)
        if prisoners > 0 {
            switch prisonerDisposition {
            case .incorporateInfantry:
                let pState = factionState(for: pFaction)
                let availPop = max(0, GameConstants.defaultArmyPopCap - pState.usedMainArmyPop)
                let recruitableCount = min(availPop, max(1, Int((Double(prisoners) * 0.60).rounded())))
                let grainNeeded = recruitableCount * 10
                if recruitableCount > 0 && pState.grain >= grainNeeded {
                    mutateFaction(pFaction) { fac in
                        fac.grain -= grainNeeded
                        Self.addUnits(unitId: .shieldSwordsman, count: recruitableCount, to: &fac.mainArmyRoster)
                    }
                }

            case .ransomForGoldAndCredibility:
                let ransomGold = prisoners * 12
                let updatedCred = worldState.diplomacy.adjustCredibility(of: pFaction, delta: 2)
                mutateFaction(pFaction) { fac in
                    fac.gold += ransomGold
                    fac.credibility = updatedCred
                }

            case .conscriptSupplyPorters:
                let pState = factionState(for: pFaction)
                let availPop = max(0, GameConstants.defaultArmyPopCap - pState.usedMainArmyPop)
                let sapperCount = min(availPop, max(1, prisoners / 2))
                mutateFaction(pFaction) { fac in
                    fac.grain += prisoners * 4
                    if sapperCount > 0 {
                        Self.addUnits(unitId: .sapper, count: sapperCount, to: &fac.mainArmyRoster)
                    }
                }
            }
        }

        // 5. 扣减敌军主力或城防兵力损耗
        let totalEnemyLoss = max(0, summary.enemyKilled + summary.capturedPrisoners)
        mutateFaction(eFaction) { fac in
            Self.applyCasualties(totalEnemyLoss / 2, to: &fac.mainArmyRoster, keepMinimumGuard: false)
        }

        // 6. 定位战场关联的目标城关并落地版图归属变更 / 围点打援孤城士气暴击
        let pending = worldState.pendingBattle
        worldState.pendingBattle = nil
        worldState.pendingDefensivePrompt = nil

        let contestedNodeId = explicitTargetNodeId ?? pending?.contestedNodeId

        // 检查是否完成了【围点打援】伏击歼灭敌方援军
        if summary.isVictory, let contestedId = contestedNodeId,
           let ambushMarker = worldState.nodesById[contestedId]?.reliefAmbush,
           ambushMarker.ambusherFaction == pFaction {
            let besiegedId = ambushMarker.besiegedTargetNodeId
            mutateNode(besiegedId) { besiegedNode in
                besiegedNode.garrisonMoraleModifier = max(-50.0, besiegedNode.garrisonMoraleModifier - 25.0)
            }
            mutateNode(contestedId) { ambushNode in
                ambushNode.reliefAmbush = nil
            }
            appendLog(
                category: "打援大捷",
                summary: "【围点打援】全歼驰援敌军！【\(nodeDisplayName(besiegedId))】城内守军闻讯绝望，初始士气暴跌 -25！"
            )
        } else if summary.isVictory,
                  let pendingBattle = pending,
                  pendingBattle.isReliefAmbushInterception,
                  let besiegedId = pendingBattle.besiegedTargetNodeIdForAmbush {
            // 若玩家冲破敌方打援伏兵成功会师解围
            mutateNode(pendingBattle.contestedNodeId) { $0.reliefAmbush = nil }
            mutateNode(besiegedId) {
                $0.underSiegeBy = nil
                $0.garrisonMoraleModifier = 0.0
            }
        }

        var cityChangedHands = false
        if summary.outcomeReason != .truceNegotiated, let targetId = contestedNodeId,
           let currentNode = worldState.nodesById[targetId] {
            if summary.isVictory {
                if currentNode.owner != pFaction {
                    // 攻克敌方城关！
                    cityChangedHands = true
                    transferNodeOwnership(
                        nodeId: targetId,
                        newOwner: pFaction,
                        previousOwner: currentNode.owner,
                        wallRatioAfterCapture: 0.68
                    )
                    mutateFaction(pFaction) { fac in
                        fac.mainArmyNodeId = targetId
                    }
                    appendLog(
                        category: "攻城拔寨",
                        summary: "\(factionDisplayName(pFaction))大破\(factionDisplayName(eFaction))，成功占领【\(nodeDisplayName(targetId))】！"
                    )
                } else {
                    // 成功坚守本方城池
                    mutateNode(targetId) { nd in
                        nd.underSiegeBy = nil
                    }
                    appendLog(
                        category: "守城大捷",
                        summary: "\(factionDisplayName(pFaction))死守【\(nodeDisplayName(targetId))】击退强敌围攻！"
                    )
                }
            } else {
                // 战败分支
                if currentNode.owner == pFaction && summary.scenarioType == .siegeDefense {
                    cityChangedHands = true
                    transferNodeOwnership(
                        nodeId: targetId,
                        newOwner: eFaction,
                        previousOwner: pFaction,
                        wallRatioAfterCapture: 0.55
                    )
                    appendLog(
                        category: "城池失守",
                        summary: "【\(nodeDisplayName(targetId))】在\(factionDisplayName(eFaction))猛攻下陷落，守军退往后方重整。"
                    )
                } else if summary.outcomeReason == .playerCommanderMartyred {
                    retreatMainArmyToSafety(for: pFaction)
                    appendLog(
                        category: "主帅重创",
                        summary: "\(factionDisplayName(pFaction))主帅阵前重伤由亲卫拼死抢回后方，进入 2 回合【重伤休养】。"
                    )
                }
            }
        }

        // 7. 同步外交厌战度、战场胜势、BFS 补给跳数、反霸权警觉与终局胜利检查
        let winner = summary.isVictory ? pFaction : eFaction
        let loser = summary.isVictory ? eFaction : pFaction
        let winCas = summary.isVictory ? summary.playerKilled : summary.enemyKilled
        let loseCas = summary.isVictory ? summary.enemyKilled : summary.playerKilled
        worldState.diplomacy.recordBattleImpactOnWar(
            winner: winner,
            loser: loser,
            winnerCasualties: winCas,
            loserCasualties: loseCas,
            cityCaptured: cityChangedHands
        )

        refreshSupplyHopsWithoutTurnTick()
        synchronizeDiplomacySnapshots()
        _ = worldState.diplomacy.recalculateAntiHegemonyAlert(nodeOwners: currentNodeOwners())
        evaluateEliminationsAndVictoryStatus()
    }

    // MARK: - 外交桥接接口（确保金粮赔款、割让城池与世界状态 100% 原子同步）

    @discardableResult
    public mutating func declareWar(attacker: FactionId, target: FactionId) -> BetrayalImpactAssessment {
        synchronizeDiplomacySnapshots()
        let impact = worldState.diplomacy.declareWar(attacker: attacker, target: target)
        syncCredibilityFromDiplomacy()
        refreshSupplyHopsWithoutTurnTick()
        appendLog(
            category: impact.isBetrayalTriggered ? "背盟讨伐" : "正式宣战",
            summary: "\(factionDisplayName(attacker))向\(factionDisplayName(target))开战（\(impact.ruleExplanation)）"
        )
        return impact
    }

    public mutating func proposePeaceOffer(_ offer: PeaceOfferTerms) -> PeaceNegotiationOutcome {
        synchronizeDiplomacySnapshots()
        let outcome = worldState.diplomacy.submitPeaceOffer(offer)
        if case .accepted = outcome {
            applyPeaceAssetTransfersToWorld(offer)
            appendLog(
                category: "停火媾和",
                summary: "\(factionDisplayName(offer.proposer))与\(factionDisplayName(offer.target))达成停战协议（\(DiplomacyEngine.normalizeTruceTurns(offer.truceTurns)) 回合）。"
            )
        } else if case .rejectedBreakdown(_, let reason) = outcome {
            appendLog(
                category: "谈判破裂",
                summary: "\(factionDisplayName(offer.proposer))派往\(factionDisplayName(offer.target))的议和使者被斥退：\(reason)"
            )
        }
        syncCredibilityFromDiplomacy()
        synchronizeDiplomacySnapshots()
        return outcome
    }

    @discardableResult
    public mutating func acceptPeaceCounterOffer(_ counterTerms: PeaceOfferTerms) -> DiplomaticActionResult {
        synchronizeDiplomacySnapshots()
        let res = worldState.diplomacy.acceptCounterOffer(counterTerms)
        if res.succeeded {
            applyPeaceAssetTransfersToWorld(counterTerms)
            appendLog(
                category: "接受反报价",
                summary: "\(factionDisplayName(counterTerms.proposer))接受反报价，与\(factionDisplayName(counterTerms.target))正式停战。"
            )
        }
        syncCredibilityFromDiplomacy()
        synchronizeDiplomacySnapshots()
        return res
    }

    @discardableResult
    public mutating func formAlliance(proposer: FactionId, target: FactionId) -> DiplomaticActionResult {
        synchronizeDiplomacySnapshots()
        let res = worldState.diplomacy.formMilitaryAlliance(proposer: proposer, target: target)
        if res.succeeded {
            refreshSupplyHopsWithoutTurnTick()
            evaluateEliminationsAndVictoryStatus()
            appendLog(
                category: "缔结同盟",
                summary: "\(factionDisplayName(proposer))与\(factionDisplayName(target))结为【军事攻守同盟】，共享粮道借道权！"
            )
        }
        return res
    }

    @discardableResult
    public mutating func signTradePact(proposer: FactionId, target: FactionId) -> DiplomaticActionResult {
        synchronizeDiplomacySnapshots()
        return worldState.diplomacy.signTradePact(proposer: proposer, target: target)
    }

    @discardableResult
    public mutating func signNonAggressionPact(proposer: FactionId, target: FactionId) -> DiplomaticActionResult {
        synchronizeDiplomacySnapshots()
        return worldState.diplomacy.signNonAggressionPact(proposer: proposer, target: target)
    }

    @discardableResult
    public mutating func arrangeRoyalMarriage(proposer: FactionId, target: FactionId, marriageDowryGold: Int = 150) -> DiplomaticActionResult {
        let pState = factionState(for: proposer)
        guard pState.gold >= max(0, marriageDowryGold) else {
            return DiplomaticActionResult(succeeded: false, message: "国库礼金不足（需 \(marriageDowryGold) 金币备办王室聘礼）")
        }
        synchronizeDiplomacySnapshots()
        let res = worldState.diplomacy.arrangeRoyalMarriage(proposer: proposer, target: target)
        if res.succeeded && marriageDowryGold > 0 {
            mutateFaction(proposer) { $0.gold = max(0, $0.gold - marriageDowryGold) }
            synchronizeDiplomacySnapshots()
        }
        return res
    }

    @discardableResult
    public mutating func establishVassalage(suzerain: FactionId, vassal: FactionId) -> DiplomaticActionResult {
        synchronizeDiplomacySnapshots()
        let res = worldState.diplomacy.establishVassalage(suzerain: suzerain, vassal: vassal)
        if res.succeeded {
            refreshSupplyHopsWithoutTurnTick()
            evaluateEliminationsAndVictoryStatus()
            appendLog(
                category: "册封附庸",
                summary: "\(factionDisplayName(vassal))向\(factionDisplayName(suzerain))称臣纳贡，受宗主国庇护。"
            )
        }
        return res
    }

    @discardableResult
    public mutating func sendDiplomaticGift(
        from sender: FactionId,
        to receiver: FactionId,
        gold: Int,
        grain: Int
    ) -> DiplomaticActionResult {
        let sState = factionState(for: sender)
        let safeGold = max(0, gold)
        let safeGrain = max(0, grain)
        guard sState.gold >= safeGold, sState.grain >= safeGrain else {
            return DiplomaticActionResult(succeeded: false, message: "国库金粮不足以支付本次外交馈赠")
        }
        synchronizeDiplomacySnapshots()
        let res = worldState.diplomacy.sendDiplomaticGift(from: sender, to: receiver, gold: safeGold, grain: safeGrain)
        if res.succeeded {
            mutateFaction(sender) {
                $0.gold -= safeGold
                $0.grain -= safeGrain
            }
            mutateFaction(receiver) {
                $0.gold += safeGold
                $0.grain += safeGrain
            }
            synchronizeDiplomacySnapshots()
        }
        return res
    }

    @discardableResult
    public mutating func instigateDiscord(
        actor: FactionId,
        targetA: FactionId,
        targetB: FactionId,
        goldSpent: Int = DiplomacyEngine.instigateDiscordMinGold
    ) -> DiplomaticActionResult {
        let aState = factionState(for: actor)
        guard aState.gold >= goldSpent else {
            return DiplomaticActionResult(succeeded: false, message: "国库金币不足（需 \(goldSpent) 金币派遣离间密使）")
        }
        synchronizeDiplomacySnapshots()
        let res = worldState.diplomacy.instigateDiscord(actor: actor, targetA: targetA, targetB: targetB, goldSpent: goldSpent)
        if res.succeeded {
            mutateFaction(actor) { $0.gold = max(0, $0.gold - goldSpent) }
            synchronizeDiplomacySnapshots()
            appendLog(
                category: "密使离间",
                summary: "\(factionDisplayName(actor))暗派说客离间\(factionDisplayName(targetA))与\(factionDisplayName(targetB))。"
            )
        }
        return res
    }

    /// 双重同盟互攻居中调停：促成两大盟友停火 3 回合，零信誉扣除（DESIGN.md 10.3）
    @discardableResult
    public mutating func mediateAlliedConflict(
        mediator: FactionId,
        belligerentA: FactionId,
        belligerentB: FactionId
    ) -> DiplomaticActionResult {
        synchronizeDiplomacySnapshots()
        let res = worldState.diplomacy.mediateAlliedConflict(
            mediator: mediator,
            belligerentA: belligerentA,
            belligerentB: belligerentB
        )
        if res.succeeded {
            syncCredibilityFromDiplomacy()
            appendLog(
                category: "盟主调停",
                summary: "\(factionDisplayName(mediator))居中斡旋，促成盟友\(factionDisplayName(belligerentA))与\(factionDisplayName(belligerentB))停火 3 回合！"
            )
        }
        return res
    }

    // MARK: - 战役军队向大战场 6 军团部署转换桥接

    /// 将当前战役军团编制、城防驻军、BFS 粮道补给状态与外交/夜袭/围点打援士气修正打包为 `BattleDeploymentConfig`
    public func buildBattleDeploymentConfig(
        for context: RouteLaunchContext,
        modifiers: CampaignBattleLaunchModifiers? = nil
    ) -> BattleDeploymentConfig {
        let pFaction = context.playerFaction
        let eFaction = context.enemyFaction
        let pState = factionState(for: pFaction)
        let eState = factionState(for: eFaction)
        let contestedId = context.targetNodeId ?? worldState.pendingBattle?.contestedNodeId

        // 1. 组装我军参战栈：若为守城战且主力不在该城，则以该城驻军为主；若主力在场或主动进攻，则使用主力编制（守城时叠加本城驻军）
        var playerStacks = pState.mainArmyRoster
        if let cid = contestedId, let cNode = worldState.nodesById[cid], cNode.owner == pFaction {
            if pState.mainArmyNodeId == cid {
                for g in cNode.garrisonUnits {
                    Self.addUnits(unitId: g.unitId, count: max(1, g.count / 2), to: &playerStacks)
                }
            } else if context.scenarioType == .siegeDefense {
                playerStacks = cNode.garrisonUnits
                for m in pState.mainArmyRoster {
                    Self.addUnits(unitId: m.unitId, count: max(1, m.count / 3), to: &playerStacks)
                }
            }
        }

        // 2. 组装敌军参战栈：若为打援伏击或敌军主动来袭则取敌主力编制；若进攻敌城则取敌城驻军（敌主力在场则合流）
        var enemyStacks: [CampaignUnitStack] = []
        if worldState.pendingBattle?.isReliefAmbushInterception == true {
            enemyStacks = eState.mainArmyRoster
        } else if let cid = contestedId, let cNode = worldState.nodesById[cid], cNode.owner == eFaction {
            enemyStacks = cNode.garrisonUnits
            if eState.mainArmyNodeId == cid {
                for m in eState.mainArmyRoster {
                    Self.addUnits(unitId: m.unitId, count: max(1, m.count / 2), to: &enemyStacks)
                }
            }
        } else {
            enemyStacks = eState.mainArmyRoster
        }

        let pRoster = Self.convertStacksToSixCorpsRoster(playerStacks, faction: pFaction, scenario: context.scenarioType, isPlayer: true)
        let eRoster = Self.convertStacksToSixCorpsRoster(enemyStacks, faction: eFaction, scenario: context.scenarioType, isPlayer: false)

        let stagingId = worldState.pendingBattle?.stagingNodeId ?? pState.mainArmyNodeId
        let supplyStatus: SupplyLineStatus
        if let targetId = contestedId, targetId != stagingId {
            let prior = worldState.nodesById[stagingId]?.isolatedTurns ?? 0
            supplyStatus = supplyService.evaluateMarchSupplyStatus(
                fromStagingNodeId: stagingId,
                targetNodeId: targetId,
                factionId: pFaction,
                nodeOwners: currentNodeOwners(),
                alliedFactions: worldState.diplomacy.alliedFactions(of: pFaction),
                stagingPriorIsolatedTurns: max(0, prior - 1)
            )
        } else {
            supplyStatus = worldState.nodesById[stagingId]?.supplyStatus ?? .fullSupply(hops: 0)
        }

        let carryGrain: Double
        let alreadyDiscounted: Bool
        if let mods = modifiers {
            carryGrain = mods.initialCarryGrain
            alreadyDiscounted = true
        } else {
            carryGrain = supplyService.calculateBattleInitialGrain(
                for: supplyStatus,
                factionId: pFaction,
                availableFactionGrain: pState.grain
            )
            alreadyDiscounted = true
        }

        let seedMix = UInt64(worldState.turnNumber) &* 0x9E37_79B9_7F4A_7C15 ^ worldState.rng.state
        return BattleDeploymentConfig(
            customPlayerRoster: pRoster,
            customEnemyRoster: eRoster,
            playerInitialGold: min(900, max(320, pState.gold / 2)),
            playerInitialWood: min(650, max(240, pState.wood / 2)),
            playerInitialGrain: carryGrain,
            enemyInitialGrain: GameConstants.battleInitGrain,
            playerSupplyStatus: supplyStatus,
            playerBetrayalMoralePenalty: modifiers?.playerInitialMoraleDelta ?? 0.0,
            enemyInitialMoraleDelta: modifiers?.enemyInitialMoraleDelta ?? (contestedId.flatMap { worldState.nodesById[$0]?.garrisonMoraleModifier } ?? 0.0),
            isPlayerCommanderWeakened: modifiers?.isPlayerCommanderWeakened ?? (pState.commanderWoundedTurns > 0),
            applySupplyGrainDiscountInEngine: !alreadyDiscounted,
            siegeHoldTargetSeconds: 150.0,
            randomSeed: seedMix == 0 ? 0x2026_1118 : seedMix
        )
    }

    /// 将战役兵种栈智能整编为 6 大战场军团（确保前锋、两翼、总预备队、远程攻城群与辎重工兵齐全且不超单方上限）
    public static func convertStacksToSixCorpsRoster(
        _ stacks: [CampaignUnitStack],
        faction: FactionId,
        scenario: BattleScenarioType,
        isPlayer: Bool
    ) -> [BattleArmyRosterEntry] {
        let nonZero = stacks.filter { $0.count > 0 }
        guard !nonZero.isEmpty else {
            return BattleSimulationEngine.defaultSixCorpsRoster(for: faction, scenario: scenario, isPlayer: isPlayer)
        }

        var supportCount = 0
        var rangedEntries: [(UnitTypeId, Int)] = []
        var cavalryEntries: [(UnitTypeId, Int)] = []
        var frontlineEntries: [(UnitTypeId, Int)] = []

        for item in nonZero {
            let safeType: UnitTypeId = (faction == .canglang && item.unitId == .trebuchet) ? .ballista : item.unitId
            guard let st = UnitConfig.stats(for: safeType) else { continue }
            switch st.category {
            case .support:
                supportCount += item.count
            case .ranged, .siege:
                rangedEntries.append((safeType, item.count))
            case .cavalry:
                cavalryEntries.append((safeType, item.count))
            case .infantry, .polearm, .shock:
                frontlineEntries.append((safeType, item.count))
            }
        }

        var result: [BattleArmyRosterEntry] = []

        // 1. 中军前锋 & 右翼 & 总预备队分配前排与机动步骑
        if let mainFront = frontlineEntries.first {
            let half = max(4, (mainFront.1 + 1) / 2)
            result.append(BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: mainFront.0, count: min(32, half), initialFormation: .phalanxRect))
            let rest = mainFront.1 - half
            if rest >= 3 {
                result.append(BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: mainFront.0, count: min(24, rest), initialFormation: .phalanxRect))
            }
        } else if let cavFirst = cavalryEntries.first {
            result.append(BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: cavFirst.0, count: min(20, max(4, cavFirst.1 / 2)), initialFormation: .wedgeCharge))
        } else {
            result.append(BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 12, initialFormation: .phalanxRect))
        }

        if frontlineEntries.count >= 2 {
            let sec = frontlineEntries[1]
            result.append(BattleArmyRosterEntry(corpsRole: .rightWing, unitType: sec.0, count: min(24, sec.1), initialFormation: .phalanxRect))
        }

        if let cav = cavalryEntries.first {
            result.append(BattleArmyRosterEntry(corpsRole: .leftWing, unitType: cav.0, count: min(20, cav.1), initialFormation: .wedgeCharge))
            if cavalryEntries.count >= 2 && !result.contains(where: { $0.corpsRole == .rightWing }) {
                result.append(BattleArmyRosterEntry(corpsRole: .rightWing, unitType: cavalryEntries[1].0, count: min(18, cavalryEntries[1].1), initialFormation: .wedgeCharge))
            }
        } else if frontlineEntries.count >= 3 {
            let third = frontlineEntries[2]
            result.append(BattleArmyRosterEntry(corpsRole: .leftWing, unitType: third.0, count: min(20, third.1), initialFormation: .wedgeCharge))
        }

        if !result.contains(where: { $0.corpsRole == .rearReserve }) {
            if frontlineEntries.count >= 3 {
                result.append(BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: frontlineEntries[2].0, count: min(18, frontlineEntries[2].1), initialFormation: .phalanxRect))
            } else if cavalryEntries.count >= 2 {
                result.append(BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: cavalryEntries[1].0, count: min(14, cavalryEntries[1].1), initialFormation: .wedgeCharge))
            }
        }

        // 2. 远程与攻城群
        if let rngFirst = rangedEntries.first {
            result.append(BattleArmyRosterEntry(corpsRole: .siegeBattery, unitType: rngFirst.0, count: min(24, rngFirst.1), initialFormation: .echelonLine))
            if rangedEntries.count >= 2 && !result.contains(where: { $0.corpsRole == .rightWing }) {
                result.append(BattleArmyRosterEntry(corpsRole: .rightWing, unitType: rangedEntries[1].0, count: min(18, rangedEntries[1].1), initialFormation: .echelonLine))
            }
        }

        // 3. 辎重工兵队（保底至少 3 名工兵采矿抢粮）
        result.append(BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: min(8, max(3, supportCount)), initialFormation: .circleDefense))

        return result
    }

    // MARK: - 回合推进核心引擎：`advanceTurn()`（税收、通商、BFS 断粮 8% 减员、AI 混战与终局判定）

    @discardableResult
    public mutating func advanceTurn() -> CampaignTurnResolutionReport {
        let resolvingTurn = worldState.turnNumber
        worldState.pendingDefensivePrompt = nil

        var playerGoldTax = 0
        var playerWoodHarvest = 0
        var playerTradeGold = 0
        var playerGrainDelta = 0
        var playerWarningNodes: [String] = []
        var playerStarvationAttrition: [String: Int] = [:]
        var aiHeadlines: [String] = []

        // ==================== 阶段 1：八大势力城池税赋、林粮产出、丝路通商与岁币结算 ====================
        for fid in FactionId.allCases {
            let fState = factionState(for: fid)
            guard !fState.isEliminated else { continue }
            let ownedNodes = controlledNodes(of: fid)
            guard !ownedNodes.isEmpty else { continue }

            var rawGold = 0
            var rawWood = 0
            var rawGrain = 0
            for nd in ownedNodes {
                guard let cfg = CampaignMapConfig.node(byId: nd.id) else { continue }
                rawGold += cfg.goldYield
                rawWood += cfg.woodYield
                rawGrain += cfg.grainYield
            }

            // 沙漠商盟金矿与商业税赋 +35%
            if fid == .shamo {
                rawGold = Int((Double(rawGold) * 1.35).rounded())
            }

            let tradeGold = worldState.diplomacy.calculateTradeIncome(
                for: fid,
                unlockedTechs: Set(fState.unlockedTechIds)
            )

            // 军队每回合战略口粮维持消耗
            let mainArmyNodeStatus = worldState.nodesById[fState.mainArmyNodeId]?.supplyStatus ?? .fullSupply(hops: 0)
            let supplyMods = supplyService.supplyModifiers(for: mainArmyNodeStatus, factionId: fid)
            var upkeepFactor = supplyMods.upkeepGrainMultiplier
            if fid == .shuangyuan && !fState.unlockedTechIds.contains("sy_tech_winterhunt") {
                // 霜原熊族未研发《雪原冬猎》前全军日常耗粮 +15%
                upkeepFactor *= 1.15
            }

            let totalTroopPop = fState.usedMainArmyPop + ownedNodes.reduce(0) { acc, nd in
                acc + nd.totalGarrisonTroops / 2
            }
            let grainUpkeep = Int((Double(totalTroopPop) * 1.8 * upkeepFactor).rounded())
            let netGrain = rawGrain - grainUpkeep

            mutateFaction(fid) { fac in
                fac.gold += rawGold + tradeGold
                fac.wood += rawWood
                fac.grain = max(0, fac.grain + netGrain)
            }

            if fid == worldState.playerFaction {
                playerGoldTax = rawGold
                playerWoodHarvest = rawWood
                playerTradeGold = tradeGold
                playerGrainDelta = netGrain
            }
        }

        // 履行停战分期纳粮与附庸岁币义务
        for obligation in worldState.diplomacy.tributeObligations {
            let payerState = factionState(for: obligation.payer)
            guard !payerState.isEliminated else { continue }
            let actualGold = min(payerState.gold, obligation.goldPerTurn)
            let actualGrain = min(payerState.grain, obligation.grainPerTurn)
            if actualGold > 0 || actualGrain > 0 {
                mutateFaction(obligation.payer) {
                    $0.gold -= actualGold
                    $0.grain -= actualGrain
                }
                mutateFaction(obligation.recipient) {
                    $0.gold += actualGold
                    $0.grain += actualGrain
                }
                if obligation.payer == worldState.playerFaction {
                    playerGrainDelta -= actualGrain
                } else if obligation.recipient == worldState.playerFaction {
                    playerGrainDelta += actualGrain
                }
            }
        }

        // ==================== 阶段 2：全图 40 城关 BFS 粮道核验与断粮第 2 回合起 8% 逃亡减员 ====================
        let snapshotOwners = currentNodeOwners()
        let sortedNodeIds = worldState.nodesById.keys.sorted()

        for nodeId in sortedNodeIds {
            guard let nd = worldState.nodesById[nodeId] else { continue }
            let owner = nd.owner
            let allies = worldState.diplomacy.alliedFactions(of: owner)
            let status = supplyService.evaluateSupplyStatus(
                forNodeId: nodeId,
                factionId: owner,
                nodeOwners: snapshotOwners,
                alliedFactions: allies,
                priorIsolatedTurns: nd.isolatedTurns
            )

            switch status {
            case .fullSupply(let hops), .extendedMarch(let hops), .overextended(let hops):
                mutateNode(nodeId) {
                    $0.cachedSupplyHops = hops
                    $0.isolatedTurns = 0
                }

            case .severed(let isolatedTurns):
                mutateNode(nodeId) {
                    $0.cachedSupplyHops = nil
                    $0.isolatedTurns = isolatedTurns
                }

                if isolatedTurns == 1 {
                    if owner == worldState.playerFaction {
                        playerWarningNodes.append(nodeId)
                        appendLog(
                            category: "粮道告警",
                            summary: "⚠️【\(nodeDisplayName(nodeId))】归路粮道被截断（第 1 回合消耗应急干粮，若下回合仍未打通将发生饥疲逃亡）！"
                        )
                    }
                } else if isolatedTurns >= 2 {
                    // 第 2 回合起触发【饥疲】：每回合非战斗逃亡减员 8%
                    var totalDeserted = 0
                    mutateNode(nodeId) { starvingNode in
                        totalDeserted += Self.applyPercentageAttrition(
                            rate: CampaignSupplyService.severedStarvationAttritionRate,
                            to: &starvingNode.garrisonUnits,
                            minimumRemaining: 2
                        )
                    }
                    if factionState(for: owner).mainArmyNodeId == nodeId {
                        mutateFaction(owner) { fac in
                            totalDeserted += Self.applyPercentageAttrition(
                                rate: CampaignSupplyService.severedStarvationAttritionRate,
                                to: &fac.mainArmyRoster,
                                minimumRemaining: 4
                            )
                        }
                    }
                    if owner == worldState.playerFaction && totalDeserted > 0 {
                        playerStarvationAttrition[nodeId] = totalDeserted
                        appendLog(
                            category: "饥疲减员",
                            summary: "🚨【\(nodeDisplayName(nodeId))】连续断粮 \(isolatedTurns) 回合陷入饥疲，非战斗逃亡减员 \(totalDeserted) 人（8%）！"
                        )
                    }
                }
            }

            // 递减围点打援伏兵持续回合
            if let ambush = worldState.nodesById[nodeId]?.reliefAmbush {
                if ambush.remainingTurns <= 1 {
                    mutateNode(nodeId) { $0.reliefAmbush = nil }
                } else {
                    mutateNode(nodeId) { $0.reliefAmbush?.remainingTurns = ambush.remainingTurns - 1 }
                }
            }
        }

        // 额外核验借道驻扎于同盟国领土内的远征主力军团通往本国仓城的独立粮道
        for fid in FactionId.allCases {
            let fState = factionState(for: fid)
            guard !fState.isEliminated else { continue }
            if worldState.nodesById[fState.mainArmyNodeId]?.owner == fid {
                let syncedTurns = worldState.nodesById[fState.mainArmyNodeId]?.isolatedTurns ?? 0
                mutateFaction(fid) { $0.mainArmyIsolatedTurns = syncedTurns }
                continue
            }
            let allies = worldState.diplomacy.alliedFactions(of: fid)
            let armyStatus = supplyService.evaluateSupplyStatus(
                forNodeId: fState.mainArmyNodeId,
                factionId: fid,
                nodeOwners: snapshotOwners,
                alliedFactions: allies,
                priorIsolatedTurns: fState.mainArmyIsolatedTurns
            )
            switch armyStatus {
            case .fullSupply, .extendedMarch, .overextended:
                mutateFaction(fid) { $0.mainArmyIsolatedTurns = 0 }
            case .severed(let turns):
                mutateFaction(fid) { fac in
                    fac.mainArmyIsolatedTurns = turns
                    if turns >= 2 {
                        let lost = Self.applyPercentageAttrition(
                            rate: CampaignSupplyService.severedStarvationAttritionRate,
                            to: &fac.mainArmyRoster,
                            minimumRemaining: 4
                        )
                        if fid == worldState.playerFaction && lost > 0 {
                            playerStarvationAttrition[fState.mainArmyNodeId, default: 0] += lost
                        }
                    }
                }
                if turns == 1 && fid == worldState.playerFaction && !playerWarningNodes.contains(fState.mainArmyNodeId) {
                    playerWarningNodes.append(fState.mainArmyNodeId)
                }
            }
        }

        // ==================== 阶段 3：主帅重伤恢复、城防修缮与行军点重置 ====================
        for fid in FactionId.allCases {
            let fState = factionState(for: fid)
            guard !fState.isEliminated else { continue }
            let armyNodeSupply: SupplyLineStatus
            if worldState.nodesById[fState.mainArmyNodeId]?.owner == fid {
                armyNodeSupply = worldState.nodesById[fState.mainArmyNodeId]?.supplyStatus ?? .fullSupply(hops: 0)
            } else if fState.mainArmyIsolatedTurns > 0 {
                armyNodeSupply = .severed(isolatedTurns: fState.mainArmyIsolatedTurns)
            } else {
                armyNodeSupply = supplyService.evaluateSupplyStatus(
                    forNodeId: fState.mainArmyNodeId,
                    factionId: fid,
                    nodeOwners: snapshotOwners,
                    alliedFactions: worldState.diplomacy.alliedFactions(of: fid),
                    priorIsolatedTurns: 0
                )
            }
            let supplyMods = supplyService.supplyModifiers(for: armyNodeSupply, factionId: fid)
            let baseAp = Self.baseCampaignActionPoints(for: fid, unlockedTechs: Set(fState.unlockedTechIds))

            mutateFaction(fid) { fac in
                if fac.commanderWoundedTurns > 0 {
                    fac.commanderWoundedTurns -= 1
                }
                fac.mainArmyActionPoints = baseAp * supplyMods.campaignMovementMultiplier
            }
        }

        for nodeId in sortedNodeIds {
            mutateNode(nodeId) { nd in
                if nd.underSiegeBy == nil {
                    let repairAmount = max(20, nd.maxWallIntegrity / 10)
                    nd.wallIntegrity = min(nd.maxWallIntegrity, nd.wallIntegrity + repairAmount)
                    if nd.garrisonMoraleModifier < 0.0 {
                        nd.garrisonMoraleModifier = min(0.0, nd.garrisonMoraleModifier + 8.0)
                    }
                }
            }
        }

        // ==================== 阶段 4：外交回合推进与反霸权【合纵警觉】检查 ====================
        synchronizeDiplomacySnapshots()
        worldState.diplomacy.advanceDiplomacyTurn(nodeOwners: currentNodeOwners())
        syncCredibilityFromDiplomacy()

        // ==================== 阶段 5：7 大 AI 势力独立战略演化（募兵、科研、合纵媾和、攻城易手） ====================
        let aiHeadlinesGenerated = runAutonomousAiStrategicPhase()
        aiHeadlines.append(contentsOf: aiHeadlinesGenerated)

        // ==================== 阶段 6：淘汰灭国检定与统一王都/同盟霸权胜利判定 ====================
        refreshSupplyHopsWithoutTurnTick()
        synchronizeDiplomacySnapshots()
        _ = worldState.diplomacy.recalculateAntiHegemonyAlert(nodeOwners: currentNodeOwners())
        evaluateEliminationsAndVictoryStatus()

        // ==================== 阶段 7：回合号递增并输出结构化报告 ====================
        worldState.turnNumber += 1

        return CampaignTurnResolutionReport(
            resolvedTurnNumber: resolvingTurn,
            newTurnNumber: worldState.turnNumber,
            playerGoldEarned: playerGoldTax,
            playerWoodEarned: playerWoodHarvest,
            playerGrainNetChange: playerGrainDelta,
            playerTradeGoldEarned: playerTradeGold,
            warningSeveredNodeIds: playerWarningNodes,
            starvationAttritionByNode: playerStarvationAttrition,
            aiWorldHeadlines: aiHeadlines,
            triggeredDefensiveBattle: worldState.pendingDefensivePrompt,
            victoryStatus: worldState.victoryStatus
        )
    }

    // MARK: - 五、L1 战略 AI 独立回合决策实现（不围着玩家转，真实演化天下大势）

    private mutating func runAutonomousAiStrategicPhase() -> [String] {
        var headlines: [String] = []

        for aiFaction in FactionId.allCases where aiFaction != worldState.playerFaction {
            let aiState = factionState(for: aiFaction)
            guard !aiState.isEliminated else { continue }
            guard let aiCfg = FactionConfig.config(for: aiFaction) else { continue }

            // 5.1 AI 科技研发（国库宽裕时优先解锁本族三阶科技）
            for tech in aiCfg.uniqueTechs where !aiState.unlockedTechIds.contains(tech.id) {
                let current = factionState(for: aiFaction)
                if current.gold >= tech.cost.gold + 220 &&
                   current.wood >= tech.cost.wood + 80 &&
                   current.grain >= tech.cost.grain + 250 {
                    _ = researchTechnology(factionId: aiFaction, techId: tech.id)
                    break
                }
            }

            // 5.2 AI 兵员扩编（结合自身性格与专属王牌兵种）
            aiRecruitReinforcements(for: aiFaction, personality: aiCfg.aiPersonality, exclusiveUnit: aiCfg.exclusiveUnitId)

            // 5.3 AI 外交博弈：两线作战规避求和（血月狂热除外）、通商与反霸权合纵
            let diploNews = aiPerformDiplomacy(for: aiFaction, personality: aiCfg.aiPersonality)
            headlines.append(contentsOf: diploNews)

            // 5.4 AI 军事进取：评估接壤敌方目标并发起攻城或遭遇打援伏兵
            if let warHeadline = aiExecuteOffensiveIfViable(for: aiFaction, personality: aiCfg.aiPersonality) {
                headlines.append(warHeadline)
            }
        }

        return headlines
    }

    private mutating func aiRecruitReinforcements(
        for aiFaction: FactionId,
        personality: AiPersonality,
        exclusiveUnit: UnitTypeId
    ) {
        let current = factionState(for: aiFaction)
        guard current.usedMainArmyPop <= GameConstants.defaultArmyPopCap - 12 else { return }
        guard worldState.nodesById[current.mainArmyNodeId]?.owner == aiFaction else { return }

        // 优先补充 2~3 队本国专属王牌精锐
        if current.gold >= 380 && current.grain >= 320 {
            _ = recruitUnits(factionId: aiFaction, unitId: exclusiveUnit, count: 2, intoMainArmy: true)
        }

        // 补充基础抗线与远程兵力
        let secondaryUnit: UnitTypeId
        switch personality {
        case .imperialMethodical:
            secondaryUnit = .trebuchet
        case .nomadOpportunist, .ironShockElite:
            secondaryUnit = .lightCavalry
        case .fortressCounter, .guerrillaTrapper:
            secondaryUnit = .pikeman
        case .honorBerserkBear, .zealotSwarm:
            secondaryUnit = .greatAxeman
        case .merchantPragmatic:
            secondaryUnit = .compositeArcher
        }
        let refreshed = factionState(for: aiFaction)
        if refreshed.gold >= 260 && refreshed.wood >= 220 && refreshed.grain >= 240 {
            let count = (secondaryUnit == .trebuchet) ? 1 : 2
            _ = recruitUnits(
                factionId: aiFaction,
                unitId: secondaryUnit,
                count: count,
                intoMainArmy: true,
                useInstantMercenaryGold: aiFaction == .shamo && refreshed.wood < 100
            )
        }
    }

    private mutating func aiPerformDiplomacy(
        for aiFaction: FactionId,
        personality: AiPersonality
    ) -> [String] {
        var news: [String] = []
        let activeEnemies = FactionId.allCases.filter { other in
            other != aiFaction &&
            !factionState(for: other).isEliminated &&
            worldState.diplomacy.status(between: aiFaction, and: other) == .war
        }

        // 1. 两线作战规避（DESIGN.md 9.1：除狂热扩张型血月祭司团外，同时与 >=2 国交战时主动向次要战线割利议和）
        if personality != .zealotSwarm && activeEnemies.count >= 2 {
            let sortedByStrength = activeEnemies.sorted {
                estimateFactionCombatPower($0) < estimateFactionCombatPower($1)
            }
            if let secondaryTarget = sortedByStrength.first {
                let aiProf = factionState(for: aiFaction)
                let offerGold = min(aiProf.gold / 2, 350)
                let offerGrain = min(max(0, aiProf.grain / 16), 30)
                let peaceTerms = PeaceOfferTerms(
                    proposer: aiFaction,
                    target: secondaryTarget,
                    goldIndemnity: offerGold,
                    grainTributePerTurn: offerGrain,
                    cededNodeIds: [],
                    truceTurns: 8
                )
                synchronizeDiplomacySnapshots()
                let outcome = worldState.diplomacy.submitPeaceOffer(peaceTerms)
                switch outcome {
                case .accepted:
                    applyPeaceAssetTransfersToWorld(peaceTerms)
                    let msg = "\(factionDisplayName(aiFaction))为避免两线受敌，向\(factionDisplayName(secondaryTarget))赔款停火。"
                    news.append(msg)
                    appendLog(category: "诸侯议和", summary: msg)
                case .counterOffer(_, let counter) where secondaryTarget != worldState.playerFaction:
                    if counter.cededNodeIds.isEmpty && counter.goldIndemnity <= aiProf.gold {
                        _ = acceptPeaceCounterOffer(counter)
                        let msg = "\(factionDisplayName(aiFaction))接受反报价，与\(factionDisplayName(secondaryTarget))停战止戈。"
                        news.append(msg)
                    }
                default:
                    break
                }
            }
        }

        // 2. 通商与合纵缔盟演化（AI 之间真实结盟与通商）
        for other in FactionId.allCases where other != aiFaction && other != worldState.playerFaction {
            guard !factionState(for: other).isEliminated else { continue }
            let rel = worldState.diplomacy.relation(between: aiFaction, and: other)
            let st = worldState.diplomacy.status(between: aiFaction, and: other)

            if st == .neutral && rel >= GameConstants.tradePactMinRelation {
                if personality == .merchantPragmatic || rel >= 32 {
                    let res = signTradePact(proposer: aiFaction, target: other)
                    if res.succeeded {
                        news.append("\(factionDisplayName(aiFaction))与\(factionDisplayName(other))开通丝路商约。")
                    }
                }
            } else if st != .alliance && st != .war && rel >= GameConstants.allianceMinRelation {
                let res = formAlliance(proposer: aiFaction, target: other)
                if res.succeeded {
                    news.append("\(factionDisplayName(aiFaction))与\(factionDisplayName(other))正式缔结军事同盟！")
                }
            }
        }

        // 3. 若当前无战事且兵强粮足，机会主义/扩张型 AI 向接壤弱国或死敌宣战
        if activeEnemies.isEmpty {
            let myPower = estimateFactionCombatPower(aiFaction)
            let owners = currentNodeOwners()
            let borderCandidates = FactionId.allCases.filter { candidate in
                guard candidate != aiFaction, !factionState(for: candidate).isEliminated else { return false }
                guard DiplomacyEngine.areTerritoriesAdjacent(aiFaction, candidate, nodeOwners: owners) else { return false }
                let st = worldState.diplomacy.status(between: aiFaction, and: candidate)
                guard st == .neutral || st == .tradePact else { return false }
                let rel = worldState.diplomacy.relation(between: aiFaction, and: candidate)
                let aggressionThreshold: Int = (personality == .zealotSwarm || personality == .nomadOpportunist) ? -5 : -18
                return rel <= aggressionThreshold && myPower >= estimateFactionCombatPower(candidate) * 0.92
            }

            if let chosenTarget = borderCandidates.min(by: { estimateFactionCombatPower($0) < estimateFactionCombatPower($1) }) {
                _ = declareWar(attacker: aiFaction, target: chosenTarget)
                news.append("\(factionDisplayName(aiFaction))陈兵边境，正式向\(factionDisplayName(chosenTarget))宣战！")
            }
        }

        return news
    }

    private mutating func aiExecuteOffensiveIfViable(
        for aiFaction: FactionId,
        personality: AiPersonality
    ) -> String? {
        let aiState = factionState(for: aiFaction)
        guard aiState.totalMainArmyTroops >= 18 else { return nil }

        let owners = currentNodeOwners()
        let myNodes = controlledNodes(of: aiFaction)

        // 搜集所有与本国领土相邻且已处于交战状态的敌占城关
        var attackTargets: [CampaignNodeState] = []
        var seenTargetIds = Set<String>()
        for myNode in myNodes {
            guard let cfg = CampaignMapConfig.node(byId: myNode.id) else { continue }
            for nbId in cfg.neighbors where seenTargetIds.insert(nbId).inserted {
                guard let nbState = worldState.nodesById[nbId],
                      nbState.owner != aiFaction,
                      worldState.diplomacy.status(between: aiFaction, and: nbState.owner) == .war else {
                    continue
                }
                attackTargets.append(nbState)
            }
        }

        guard !attackTargets.isEmpty else { return nil }

        // 按效用分挑选最薄弱或战略价值最高的城关
        let chosenTarget = attackTargets.max { a, b in
            aiTargetUtility(node: a, attacker: aiFaction, personality: personality, owners: owners) <
            aiTargetUtility(node: b, attacker: aiFaction, personality: personality, owners: owners)
        }!

        // 检查目标路线上是否存在玩家或敌方预设的【围点打援】伏兵拦截
        if let ambush = chosenTarget.reliefAmbush, ambush.ambusherFaction != aiFaction {
            if ambush.ambusherFaction == worldState.playerFaction && worldState.pendingDefensivePrompt == nil {
                let targetCfg = CampaignMapConfig.node(byId: chosenTarget.id)
                let prompt = RouteLaunchContext(
                    entryMode: .campaign,
                    playerFaction: worldState.playerFaction,
                    enemyFaction: aiFaction,
                    scenarioType: .ambush,
                    terrain: targetCfg?.terrain ?? .denseForest,
                    weather: .heavyFog,
                    targetNodeId: chosenTarget.id
                )
                worldState.pendingDefensivePrompt = prompt
                worldState.pendingBattle = PendingCampaignBattle(
                    attackerFaction: worldState.playerFaction,
                    defenderFaction: aiFaction,
                    stagingNodeId: chosenTarget.id,
                    contestedNodeId: chosenTarget.id,
                    scenarioType: .ambush,
                    isReliefAmbushInterception: true,
                    besiegedTargetNodeIdForAmbush: ambush.besiegedTargetNodeId
                )
                let msg = "🎯 敌军中计！\(factionDisplayName(aiFaction))驰援纵队踏入我军于【\(nodeDisplayName(chosenTarget.id))】预设的打援伏击圈！"
                appendLog(category: "伏击触发", summary: msg)
                return msg
            }
        }

        // 若进攻目标为玩家城关且本回合尚未挂起玩家守城战，则生成守城响应请求交由玩家接战或裁决
        if chosenTarget.owner == worldState.playerFaction {
            if worldState.pendingDefensivePrompt == nil {
                let targetCfg = CampaignMapConfig.node(byId: chosenTarget.id)
                let scenario: BattleScenarioType = (personality == .zealotSwarm && worldState.rng.nextUnitDouble() < 0.45)
                    ? .nightRaid
                    : .siegeDefense
                let weather: WeatherType = (scenario == .nightRaid) ? .night : .clearDay
                let prompt = RouteLaunchContext(
                    entryMode: .campaign,
                    playerFaction: worldState.playerFaction,
                    enemyFaction: aiFaction,
                    scenarioType: scenario,
                    terrain: targetCfg?.terrain ?? .fortWall,
                    weather: weather,
                    targetNodeId: chosenTarget.id
                )
                mutateNode(chosenTarget.id) { $0.underSiegeBy = aiFaction }
                worldState.pendingDefensivePrompt = prompt
                worldState.pendingBattle = PendingCampaignBattle(
                    attackerFaction: aiFaction,
                    defenderFaction: worldState.playerFaction,
                    stagingNodeId: aiState.mainArmyNodeId,
                    contestedNodeId: chosenTarget.id,
                    scenarioType: scenario
                )
                let msg = "⚔️ 敌军压境！\(factionDisplayName(aiFaction))主力猛攻我方【\(nodeDisplayName(chosenTarget.id))】！"
                appendLog(category: "敌军攻城", summary: msg)
                return msg
            }
            return nil
        }

        // AI vs AI 大地图确定性攻城会战推演
        let defender = chosenTarget.owner
        let attackPower = stackCombatPower(aiState.mainArmyRoster, factionId: aiFaction)
            * (aiState.commanderWoundedTurns > 0 ? 0.80 : 1.0)
            * (0.92 + worldState.rng.nextUnitDouble() * 0.18)

        let wallBonus = 1.0 + Double(chosenTarget.wallIntegrity) / 1400.0
        let moraleFactor = max(0.65, 1.0 + chosenTarget.garrisonMoraleModifier / 100.0)
        var defensePower = stackCombatPower(chosenTarget.garrisonUnits, factionId: defender) * wallBonus * moraleFactor
        if factionState(for: defender).mainArmyNodeId == chosenTarget.id {
            defensePower += stackCombatPower(factionState(for: defender).mainArmyRoster, factionId: defender) * 0.85
        }

        if attackPower > defensePower * 1.12 {
            // 攻方破城夺取节点
            mutateFaction(aiFaction) { fac in
                _ = Self.applyPercentageAttrition(rate: 0.16, to: &fac.mainArmyRoster, minimumRemaining: 6)
                fac.mainArmyNodeId = chosenTarget.id
            }
            if factionState(for: defender).mainArmyNodeId == chosenTarget.id {
                mutateFaction(defender) { fac in
                    _ = Self.applyPercentageAttrition(rate: 0.28, to: &fac.mainArmyRoster, minimumRemaining: 4)
                }
            }
            transferNodeOwnership(
                nodeId: chosenTarget.id,
                newOwner: aiFaction,
                previousOwner: defender,
                wallRatioAfterCapture: 0.60
            )
            worldState.diplomacy.recordBattleImpactOnWar(
                winner: aiFaction,
                loser: defender,
                winnerCasualties: 18,
                loserCasualties: 36,
                cityCaptured: true
            )
            let headline = "\(factionDisplayName(aiFaction))攻破\(factionDisplayName(defender))重镇【\(nodeDisplayName(chosenTarget.id))】！"
            appendLog(category: "天下战报", summary: headline)
            return headline
        } else {
            // 守方击退进攻，消耗城墙与双方兵力
            mutateFaction(aiFaction) { fac in
                _ = Self.applyPercentageAttrition(rate: 0.22, to: &fac.mainArmyRoster, minimumRemaining: 5)
            }
            mutateNode(chosenTarget.id) { nd in
                _ = Self.applyPercentageAttrition(rate: 0.14, to: &nd.garrisonUnits, minimumRemaining: 3)
                nd.wallIntegrity = max(80, nd.wallIntegrity - 140)
            }
            worldState.diplomacy.recordBattleImpactOnWar(
                winner: defender,
                loser: aiFaction,
                winnerCasualties: 14,
                loserCasualties: 26,
                cityCaptured: false
            )
            return nil
        }
    }

    private func aiTargetUtility(
        node: CampaignNodeState,
        attacker: FactionId,
        personality: AiPersonality,
        owners: [String: FactionId]
    ) -> Double {
        guard let cfg = CampaignMapConfig.node(byId: node.id) else { return 0.0 }
        var score = Double(cfg.totalYield) * 0.35 + (cfg.isSupplyDepot ? 35.0 : 0.0)
        score -= Double(node.totalGarrisonTroops) * 2.2
        score -= Double(cfg.defenseLevel) * 9.0

        // 评估咽喉断粮价值：若夺下该城可令防守方至少一座邻城陷入 BFS 粮道断绝，赋予 +22 战术咽喉权重
        var simulatedOwners = owners
        simulatedOwners[node.id] = attacker
        let defenderAllies = worldState.diplomacy.alliedFactions(of: node.owner)
        let cutsEnemySupply = cfg.neighbors.contains { nbId in
            guard simulatedOwners[nbId] == node.owner else { return false }
            let pathAfter = supplyService.shortestSupplyPath(
                forNodeId: nbId,
                factionId: node.owner,
                nodeOwners: simulatedOwners,
                alliedFactions: defenderAllies
            )
            return pathAfter.isEmpty
        }
        if cutsEnemySupply {
            score += 22.0
        }

        if personality == .nomadOpportunist && cfg.nodeType == .granaryTown {
            score += 28.0
        } else if personality == .merchantPragmatic && cfg.nodeType == .resourceHub {
            score += 25.0
        } else if personality == .imperialMethodical && cfg.nodeType == .capitalCitadel {
            score += 22.0
        }
        return score
    }

    // MARK: - 六、私有状态维护、所有权移交与胜利条件检验

    private mutating func transferNodeOwnership(
        nodeId: String,
        newOwner: FactionId,
        previousOwner: FactionId,
        wallRatioAfterCapture: Double
    ) {
        guard let cfg = CampaignMapConfig.node(byId: nodeId) else { return }
        let newMaxWall = Self.calculateMaxWallIntegrity(for: cfg, owner: newOwner)
        let restoredWall = max(120, Int((Double(newMaxWall) * wallRatioAfterCapture).rounded()))
        let newGarrison = [
            CampaignUnitStack(unitId: .shieldSwordsman, count: 6),
            CampaignUnitStack(unitId: .compositeArcher, count: 4)
        ]

        mutateNode(nodeId) { nd in
            nd.owner = newOwner
            nd.maxWallIntegrity = newMaxWall
            nd.wallIntegrity = min(newMaxWall, restoredWall)
            nd.garrisonUnits = newGarrison
            nd.isolatedTurns = 0
            nd.underSiegeBy = nil
            nd.garrisonMoraleModifier = 0.0
            nd.reliefAmbush = nil
        }

        // 若原属势力的主力恰在此城，自动撤往最近友城
        if factionState(for: previousOwner).mainArmyNodeId == nodeId {
            retreatMainArmyToSafety(for: previousOwner)
        }
    }

    private mutating func retreatMainArmyToSafety(for factionId: FactionId) {
        let remaining = controlledNodes(of: factionId)
        guard !remaining.isEmpty else { return }
        let capId = FactionConfig.config(for: factionId)?.capitalNodeId
        let fallbackId = remaining.first(where: { $0.id == capId })?.id ?? remaining[0].id
        mutateFaction(factionId) { fac in
            fac.mainArmyNodeId = fallbackId
        }
    }

    private mutating func applyPeaceAssetTransfersToWorld(_ offer: PeaceOfferTerms) {
        if offer.goldIndemnity > 0 {
            let actual = min(factionState(for: offer.proposer).gold, offer.goldIndemnity)
            mutateFaction(offer.proposer) { $0.gold -= actual }
            mutateFaction(offer.target) { $0.gold += actual }
        } else if offer.goldIndemnity < 0 {
            let actual = min(factionState(for: offer.target).gold, abs(offer.goldIndemnity))
            mutateFaction(offer.target) { $0.gold -= actual }
            mutateFaction(offer.proposer) { $0.gold += actual }
        }

        for nodeId in Set(offer.cededNodeIds) {
            guard let currentOwner = worldState.nodesById[nodeId]?.owner else { continue }
            if currentOwner == offer.proposer {
                transferNodeOwnership(
                    nodeId: nodeId,
                    newOwner: offer.target,
                    previousOwner: offer.proposer,
                    wallRatioAfterCapture: 0.85
                )
            } else if currentOwner == offer.target {
                transferNodeOwnership(
                    nodeId: nodeId,
                    newOwner: offer.proposer,
                    previousOwner: offer.target,
                    wallRatioAfterCapture: 0.85
                )
            }
        }
        refreshSupplyHopsWithoutTurnTick()
        evaluateEliminationsAndVictoryStatus()
    }

    private mutating func refreshSupplyHopsWithoutTurnTick() {
        let owners = currentNodeOwners()
        for nodeId in worldState.nodesById.keys.sorted() {
            guard let nd = worldState.nodesById[nodeId] else { continue }
            let allies = worldState.diplomacy.alliedFactions(of: nd.owner)
            let path = supplyService.shortestSupplyPath(
                forNodeId: nodeId,
                factionId: nd.owner,
                nodeOwners: owners,
                alliedFactions: allies
            )
            mutateNode(nodeId) { state in
                if path.isEmpty {
                    // 回合中途仅清除连通跳数缓存，不提前递增 isolatedTurns，确保回合末严格先走第 1 回合干粮预警再进第 2 回合饥疲
                    state.cachedSupplyHops = nil
                } else {
                    state.cachedSupplyHops = path.count - 1
                    state.isolatedTurns = 0
                }
            }
        }
    }

    private mutating func synchronizeDiplomacySnapshots() {
        for fid in FactionId.allCases {
            let fac = factionState(for: fid)
            let ownedIds = controlledNodes(of: fid).map(\.id)
            let power = estimateFactionCombatPower(fid)
            worldState.diplomacy.syncFactionStrategicSnapshot(
                factionId: fid,
                availableGold: fac.gold,
                availableGrain: fac.grain,
                ownedNodeIds: ownedIds,
                militaryStrengthScore: power,
                unlockedTechIds: fac.unlockedTechIds
            )
        }
        syncCredibilityFromDiplomacy()
    }

    private mutating func syncCredibilityFromDiplomacy() {
        for fid in FactionId.allCases {
            let cred = worldState.diplomacy.credibility(of: fid)
            mutateFaction(fid) { $0.credibility = cred }
        }
    }

    /// 检查势力覆灭、王都大一统胜利与同盟霸权胜利（DESIGN.md 第 1 节）
    public mutating func evaluateEliminationsAndVictoryStatus() {
        let owners = currentNodeOwners()
        var countByFaction: [FactionId: Int] = [:]
        for owner in owners.values {
            countByFaction[owner, default: 0] += 1
        }

        for fid in FactionId.allCases {
            let count = countByFaction[fid] ?? 0
            let wasEliminated = factionState(for: fid).isEliminated
            if count == 0 && !wasEliminated {
                mutateFaction(fid) {
                    $0.isEliminated = true
                    $0.mainArmyRoster.removeAll()
                }
                appendLog(category: "势力覆灭", summary: "【\(factionDisplayName(fid))】尽失全境城关，退出天下逐鹿！")
            } else if count > 0 && wasEliminated {
                mutateFaction(fid) { $0.isEliminated = false }
            }
        }

        let player = worldState.playerFaction
        let playerNodeCount = countByFaction[player] ?? 0
        if playerNodeCount == 0 {
            worldState.victoryStatus = .playerDefeated(reason: "我方全境城关尽数失守，大业未竟。")
            return
        }

        let allCapitalIds = FactionConfig.allFactions.map(\.capitalNodeId)
        let playerOwnsAllCapitals = allCapitalIds.allSatisfy { owners[$0] == player }
        if playerOwnsAllCapitals {
            worldState.victoryStatus = .capitalUnificationVictory(winner: player)
            return
        }

        // 同盟霸权胜利：玩家亲自控制 >= 16 座城关，且玩家与正式军事同盟/附庸共控 >= 32 座城关（80%）及全部 8 座王都
        let coalitionPartners = worldState.diplomacy.coalitionPartners(of: player)
        let coalitionSet = coalitionPartners.union([player])
        let coalitionNodeCount = owners.values.filter { coalitionSet.contains($0) }.count
        let coalitionOwnsAllCapitals = allCapitalIds.allSatisfy { capId in
            guard let capOwner = owners[capId] else { return false }
            return coalitionSet.contains(capOwner)
        }
        if playerNodeCount >= 16 && coalitionNodeCount >= 32 && coalitionOwnsAllCapitals {
            let sortedAllies = coalitionPartners.sorted { $0.rawValue < $1.rawValue }
            worldState.victoryStatus = .hegemonyAllianceVictory(winner: player, allies: sortedAllies)
            return
        }

        worldState.victoryStatus = .ongoing
    }

    // MARK: - 七、纯计算与内部变更辅助方法

    private func estimateFactionCombatPower(_ factionId: FactionId) -> Double {
        let fac = factionState(for: factionId)
        let armyPower = stackCombatPower(fac.mainArmyRoster, factionId: factionId)
        let garrisonPower = controlledNodes(of: factionId).reduce(0.0) { acc, nd in
            acc + stackCombatPower(nd.garrisonUnits, factionId: factionId) * 0.55
        }
        return armyPower + garrisonPower
    }

    private func stackCombatPower(_ stacks: [CampaignUnitStack], factionId: FactionId) -> Double {
        let techs = Set(factionState(for: factionId).unlockedTechIds)
        var total = 0.0
        for stack in stacks where stack.count > 0 {
            guard let st = UnitConfig.stats(for: stack.unitId) else { continue }
            var hpVal = Double(st.hp)
            var atkVal = Double(st.attack)
            var armorVal = Double(st.armor)

            // 落实 DESIGN.md 第 6 节八大势力非对称法则与三阶专属科技战力修正
            switch factionId {
            case .yanlong:
                if st.category == .infantry || st.category == .polearm {
                    armorVal *= 1.15
                    if techs.contains("yl_tech_armor") { armorVal += 8.0 }
                }
                if st.category == .siege {
                    atkVal *= 1.25
                    if techs.contains("yl_tech_thunder") { atkVal *= 1.12 }
                }
            case .canglang:
                if st.category == .cavalry {
                    atkVal *= 1.10
                }
                if techs.contains("cl_tech_whistle") && (st.category == .ranged || st.id == .canglangKeshigHorseArcher) {
                    atkVal *= 1.15
                }
            case .tieying:
                if st.category == .ranged {
                    atkVal *= 1.12
                    if techs.contains("ty_tech_arbalest") { atkVal *= 1.15 }
                }
            case .shamo:
                if st.id == .shamoMamelukeCamel && techs.contains("sm_tech_camel") {
                    hpVal *= 1.12
                }
            case .shuangyuan:
                hpVal *= 1.15
                if techs.contains("sy_tech_frostaxe") && st.category == .shock {
                    atkVal *= 1.15
                }
            case .wulin:
                if st.category == .ranged && techs.contains("wl_tech_venom") {
                    atkVal *= 1.16
                }
            case .xuanjia:
                if st.category == .cavalry {
                    armorVal *= 1.25
                    atkVal *= 1.18
                    if techs.contains("xj_tech_barding") { hpVal *= 1.12 }
                }
            case .xueyue:
                if st.category == .shock {
                    atkVal *= 1.12
                    if techs.contains("xy_tech_wardrum") { hpVal *= 1.15 }
                }
            }

            let unitScore = hpVal * 0.18 + atkVal * 1.4 + armorVal * 0.7 + st.armorPenetration * 28.0
            total += unitScore * Double(stack.count)
        }
        return total
    }

    private func friendlyHopDistance(
        from startId: String,
        to targetId: String,
        factionId: FactionId,
        alliedFactions: Set<FactionId>,
        nodeOwners: [String: FactionId]
    ) -> Int? {
        if startId == targetId { return 0 }
        var queue: [(String, Int)] = [(startId, 0)]
        var visited: Set<String> = [startId]
        var head = 0
        while head < queue.count {
            let (curr, dist) = queue[head]
            head += 1
            guard let cfg = CampaignMapConfig.node(byId: curr) else { continue }
            for nb in cfg.neighbors where !visited.contains(nb) {
                guard let nbOwner = nodeOwners[nb],
                      nbOwner == factionId || alliedFactions.contains(nbOwner) else {
                    continue
                }
                if nb == targetId {
                    return dist + 1
                }
                visited.insert(nb)
                queue.append((nb, dist + 1))
            }
        }
        return nil
    }

    private func determineBattleScenario(
        attacker: FactionId,
        targetConfig: CampaignNodeConfig,
        targetState: CampaignNodeState,
        preferredScenario: BattleScenarioType?,
        isAmbushTriggered: Bool
    ) -> BattleScenarioType {
        if isAmbushTriggered {
            return .ambush
        }
        if let preferred = preferredScenario {
            switch preferred {
            case .nightRaid, .convoyEscort, .ambush:
                return preferred
            default:
                break
            }
        }
        if targetConfig.nodeType == .capitalCitadel ||
           targetConfig.nodeType == .fortressPass ||
           targetConfig.defenseLevel >= 4 ||
           targetState.wallIntegrity >= 850 {
            return .siegeAssault
        }
        if targetConfig.nodeType == .granaryTown && attacker == .canglang {
            return .convoyEscort
        }
        return .fieldPitched
    }

    private func determineBattleWeather(
        scenario: BattleScenarioType,
        terrain: TerrainType,
        attacker: FactionId
    ) -> WeatherType {
        if scenario == .nightRaid {
            return .night
        }
        if scenario == .ambush && terrain == .denseForest {
            return .heavyFog
        }
        switch terrain {
        case .snowfield:
            return .blizzard
        case .denseForest:
            return attacker == .wulin ? .heavyFog : .clearDay
        case .riverFord:
            return .clearDay
        default:
            return .clearDay
        }
    }

    private mutating func mutateFaction(_ factionId: FactionId, _ body: (inout CampaignFactionState) -> Void) {
        if let idx = worldState.factions.firstIndex(where: { $0.factionId == factionId }) {
            body(&worldState.factions[idx])
        }
    }

    private mutating func mutateNode(_ nodeId: String, _ body: (inout CampaignNodeState) -> Void) {
        if var node = worldState.nodesById[nodeId] {
            body(&node)
            worldState.nodesById[nodeId] = node
        }
    }

    private mutating func appendLog(category: String, summary: String) {
        let entry = CampaignEventLogEntry(
            id: "log_\(worldState.nextLogSequence)",
            turnNumber: worldState.turnNumber,
            category: category,
            summary: summary
        )
        worldState.nextLogSequence += 1
        worldState.eventLogs.append(entry)
        if worldState.eventLogs.count > Self.maxEventLogEntries {
            let overflow = worldState.eventLogs.count - Self.maxEventLogEntries
            worldState.eventLogs.removeFirst(overflow)
        }
    }

    private func factionDisplayName(_ factionId: FactionId) -> String {
        FactionConfig.config(for: factionId)?.name ?? factionId.rawValue
    }

    private func nodeDisplayName(_ nodeId: String) -> String {
        CampaignMapConfig.node(byId: nodeId)?.name ?? nodeId
    }

    // MARK: - 静态初始化配表工具

    public static func calculateMaxWallIntegrity(for nodeCfg: CampaignNodeConfig, owner: FactionId) -> Int {
        let baseWall = max(1, nodeCfg.defenseLevel) * 240
        if owner == .yanlong {
            // 炎龙帝国势力特性：城防耐久 +20%
            return Int((Double(baseWall) * 1.20).rounded())
        }
        return baseWall
    }

    public static func baseCampaignActionPoints(for factionId: FactionId, unlockedTechs: Set<String>) -> Double {
        var ap = 2.0
        if factionId == .yanlong {
            // 炎龙重装行军移速 -5%
            ap *= 0.95
        } else if factionId == .canglang {
            ap *= 1.10
            if unlockedTechs.contains("cl_tech_remount") {
                // 《双马换乘》大地图行军力 +25%
                ap *= 1.25
            }
        }
        return ap
    }

    private static func buildInitialGarrison(for nodeCfg: CampaignNodeConfig) -> [CampaignUnitStack] {
        switch nodeCfg.nodeType {
        case .capitalCitadel:
            let exclusive = FactionConfig.config(for: nodeCfg.initialOwner)?.exclusiveUnitId ?? .shieldSwordsman
            return [
                CampaignUnitStack(unitId: .shieldSwordsman, count: 14),
                CampaignUnitStack(unitId: .pikeman, count: 10),
                CampaignUnitStack(unitId: .compositeArcher, count: 12),
                CampaignUnitStack(unitId: exclusive, count: 6)
            ]
        case .fortressPass:
            return [
                CampaignUnitStack(unitId: .shieldSwordsman, count: 10),
                CampaignUnitStack(unitId: .pikeman, count: 8),
                CampaignUnitStack(unitId: .compositeArcher, count: 8)
            ]
        case .granaryTown, .resourceHub:
            return [
                CampaignUnitStack(unitId: .shieldSwordsman, count: 7),
                CampaignUnitStack(unitId: .pikeman, count: 5),
                CampaignUnitStack(unitId: .compositeArcher, count: 6)
            ]
        case .crossingOutpost:
            return [
                CampaignUnitStack(unitId: .shieldSwordsman, count: 6),
                CampaignUnitStack(unitId: .compositeArcher, count: 5)
            ]
        }
    }

    private static func buildStartingMainArmy(for factionId: FactionId) -> [CampaignUnitStack] {
        switch factionId {
        case .yanlong:
            return [
                CampaignUnitStack(unitId: .sapper, count: 4),
                CampaignUnitStack(unitId: .shieldSwordsman, count: 16),
                CampaignUnitStack(unitId: .pikeman, count: 12),
                CampaignUnitStack(unitId: .compositeArcher, count: 10),
                CampaignUnitStack(unitId: .yanlongHalberdGrenadier, count: 8),
                CampaignUnitStack(unitId: .trebuchet, count: 2)
            ]
        case .canglang:
            return [
                CampaignUnitStack(unitId: .sapper, count: 3),
                CampaignUnitStack(unitId: .lightCavalry, count: 12),
                CampaignUnitStack(unitId: .canglangKeshigHorseArcher, count: 12),
                CampaignUnitStack(unitId: .compositeArcher, count: 8)
            ]
        case .tieying:
            return [
                CampaignUnitStack(unitId: .sapper, count: 5),
                CampaignUnitStack(unitId: .shieldSwordsman, count: 14),
                CampaignUnitStack(unitId: .pikeman, count: 12),
                CampaignUnitStack(unitId: .tieyingPaviseCrossbow, count: 14),
                CampaignUnitStack(unitId: .ballista, count: 2)
            ]
        case .shamo:
            return [
                CampaignUnitStack(unitId: .sapper, count: 5),
                CampaignUnitStack(unitId: .shieldSwordsman, count: 12),
                CampaignUnitStack(unitId: .compositeArcher, count: 10),
                CampaignUnitStack(unitId: .shamoMamelukeCamel, count: 10),
                CampaignUnitStack(unitId: .lightCavalry, count: 6)
            ]
        case .shuangyuan:
            return [
                CampaignUnitStack(unitId: .sapper, count: 4),
                CampaignUnitStack(unitId: .shieldSwordsman, count: 12),
                CampaignUnitStack(unitId: .greatAxeman, count: 14),
                CampaignUnitStack(unitId: .shuangyuanGiantBreaker, count: 6),
                CampaignUnitStack(unitId: .compositeArcher, count: 6)
            ]
        case .wulin:
            return [
                CampaignUnitStack(unitId: .sapper, count: 4),
                CampaignUnitStack(unitId: .pikeman, count: 12),
                CampaignUnitStack(unitId: .compositeArcher, count: 12),
                CampaignUnitStack(unitId: .wulinShadowSniper, count: 14),
                CampaignUnitStack(unitId: .lightCavalry, count: 4)
            ]
        case .xuanjia:
            return [
                CampaignUnitStack(unitId: .sapper, count: 3),
                CampaignUnitStack(unitId: .pikeman, count: 10),
                CampaignUnitStack(unitId: .lightCavalry, count: 10),
                CampaignUnitStack(unitId: .xuanjiaCataphract, count: 8),
                CampaignUnitStack(unitId: .ballista, count: 2)
            ]
        case .xueyue:
            return [
                CampaignUnitStack(unitId: .sapper, count: 4),
                CampaignUnitStack(unitId: .xueyueWardrumBerserker, count: 22),
                CampaignUnitStack(unitId: .greatAxeman, count: 12),
                CampaignUnitStack(unitId: .compositeArcher, count: 8)
            ]
        }
    }

    private static func addUnits(unitId: UnitTypeId, count: Int, to stacks: inout [CampaignUnitStack]) {
        guard count > 0 else { return }
        if let idx = stacks.firstIndex(where: { $0.unitId == unitId }) {
            stacks[idx].count += count
        } else {
            stacks.append(CampaignUnitStack(unitId: unitId, count: count))
        }
    }

    private static func applyCasualties(
        _ casualties: Int,
        to stacks: inout [CampaignUnitStack],
        keepMinimumGuard: Bool
    ) {
        guard casualties > 0, !stacks.isEmpty else { return }
        let total = stacks.reduce(0) { $0 + $1.count }
        guard total > 0 else { return }

        let maxRemovable = keepMinimumGuard ? max(0, total - 4) : total
        let toRemove = min(casualties, maxRemovable)
        guard toRemove > 0 else { return }

        // 按各兵种占比均匀分摊阵亡人数
        var remaining = toRemove
        for idx in stacks.indices {
            let share = min(stacks[idx].count, Int((Double(toRemove) * Double(stacks[idx].count) / Double(total)).rounded(.down)))
            stacks[idx].count -= share
            remaining -= share
        }
        var cursor = 0
        while remaining > 0 && stacks.contains(where: { $0.count > 0 }) {
            if stacks[cursor % stacks.count].count > 0 {
                stacks[cursor % stacks.count].count -= 1
                remaining -= 1
            }
            cursor += 1
        }
        stacks.removeAll { $0.count <= 0 }
    }

    private static func applyPercentageAttrition(
        rate: Double,
        to stacks: inout [CampaignUnitStack],
        minimumRemaining: Int
    ) -> Int {
        let total = stacks.reduce(0) { $0 + $1.count }
        guard total > minimumRemaining else { return 0 }
        let rawLoss = max(1, Int((Double(total) * rate).rounded()))
        let actualLoss = min(rawLoss, total - minimumRemaining)
        applyCasualties(actualLoss, to: &stacks, keepMinimumGuard: false)
        return actualLoss
    }
}
