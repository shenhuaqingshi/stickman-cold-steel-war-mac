import Foundation

// MARK: - 外交引擎配套可编码值类型定义

/// 单一势力的外交信誉、战略实力与国库资产快照（供媾和估值与反报价上限校验使用）
public struct FactionDiplomaticProfile: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let factionId: FactionId
    /// 全局外交信誉 [0, 100]
    public var credibility: Int
    /// 当前是否已被灭国（0 城关）
    public var isEliminated: Bool
    /// 当前实际国库金币（反报价索赔上限）
    public var availableGold: Int
    /// 当前实际库存粮草（反报价纳粮上限）
    public var availableGrain: Int
    /// 当前实际占领的城关 ID 集合（反报价割城合法集合）
    public var ownedNodeIds: [String]
    /// 综合军力估值（用于衡量战场态势优势）
    public var militaryStrengthScore: Double
    /// 累积厌战度 [0.0, 45.0]
    public var warExhaustion: Double
    /// 背盟后剩余受罚战斗场次（触发背盟时置为 2）
    public var betrayalMoralePenaltyBattles: Int
    /// 背盟战斗初始士气惩罚值（炎龙/铁鹰 -16，血月 -5，其余 -10）
    public var betrayalMoralePenaltyDelta: Double
    /// 斥退敌方屈辱求和获得的下场战斗士气激励（+8.0）
    public var nextBattleMoraleBonus: Double
    /// 已解锁科技 ID 列表（用于识别商盟《丝路商队》加成）
    public var unlockedTechIds: [String]

    public var id: FactionId { factionId }

    public init(
        factionId: FactionId,
        credibility: Int,
        isEliminated: Bool = false,
        availableGold: Int = 900,
        availableGrain: Int = 1400,
        ownedNodeIds: [String] = [],
        militaryStrengthScore: Double = 1000.0,
        warExhaustion: Double = 0.0,
        betrayalMoralePenaltyBattles: Int = 0,
        betrayalMoralePenaltyDelta: Double = 0.0,
        nextBattleMoraleBonus: Double = 0.0,
        unlockedTechIds: [String] = []
    ) {
        self.factionId = factionId
        self.credibility = max(0, min(100, credibility))
        self.isEliminated = isEliminated
        self.availableGold = max(0, availableGold)
        self.availableGrain = max(0, availableGrain)
        self.ownedNodeIds = ownedNodeIds
        self.militaryStrengthScore = max(0.0, militaryStrengthScore)
        self.warExhaustion = max(0.0, min(45.0, warExhaustion))
        self.betrayalMoralePenaltyBattles = max(0, betrayalMoralePenaltyBattles)
        self.betrayalMoralePenaltyDelta = betrayalMoralePenaltyDelta
        self.nextBattleMoraleBonus = nextBattleMoraleBonus
        self.unlockedTechIds = unlockedTechIds
    }
}

/// 活跃战争侵略责任与战场态势记录（支撑双重同盟防御优先豁免与 W_adv 计算）
public struct ActiveWarRecord: Sendable, Codable, Equatable, Hashable {
    public let pairKey: String
    /// 主动挑起战争的侵略方
    public let aggressor: FactionId
    /// 被迫应战的受侵略方
    public let defender: FactionId
    /// 战争已持续回合数
    public var warTurnsElapsed: Int
    /// 侵略方相对受侵略方的累积战场胜势分 [-40.0, +40.0]
    public var aggressorBattleScore: Double

    public init(
        pairKey: String,
        aggressor: FactionId,
        defender: FactionId,
        warTurnsElapsed: Int = 0,
        aggressorBattleScore: Double = 0.0
    ) {
        self.pairKey = pairKey
        self.aggressor = aggressor
        self.defender = defender
        self.warTurnsElapsed = max(0, warTurnsElapsed)
        self.aggressorBattleScore = max(-40.0, min(40.0, aggressorBattleScore))
    }
}

/// 分期纳粮或附庸岁币义务记录
public struct TributeObligationRecord: Sendable, Codable, Equatable, Hashable {
    public let payer: FactionId
    public let recipient: FactionId
    public var goldPerTurn: Int
    public var grainPerTurn: Int
    /// 剩余履行回合数（若为附庸长期纳贡则为 -1，直至附庸关系解除）
    public var remainingTurns: Int

    public init(
        payer: FactionId,
        recipient: FactionId,
        goldPerTurn: Int,
        grainPerTurn: Int,
        remainingTurns: Int
    ) {
        self.payer = payer
        self.recipient = recipient
        self.goldPerTurn = max(0, goldPerTurn)
        self.grainPerTurn = max(0, grainPerTurn)
        self.remainingTurns = remainingTurns
    }
}

/// 宗主国与朝贡附庸绑定记录
public struct VassalBondRecord: Sendable, Codable, Equatable, Hashable {
    public let suzerain: FactionId
    public let vassal: FactionId

    public init(suzerain: FactionId, vassal: FactionId) {
        self.suzerain = suzerain
        self.vassal = vassal
    }
}

/// 单回合送礼递减防刷计数器记录
public struct GiftCounterRecord: Sendable, Codable, Equatable, Hashable {
    public let sender: FactionId
    public let receiver: FactionId
    public var countThisTurn: Int

    public init(sender: FactionId, receiver: FactionId, countThisTurn: Int) {
        self.sender = sender
        self.receiver = receiver
        self.countThisTurn = max(0, countThisTurn)
    }
}

/// 外交行动执行反馈结果
public struct DiplomaticActionResult: Sendable, Equatable {
    public let succeeded: Bool
    public let message: String
    public let relationDelta: Int
    public let credibilityDelta: Int

    public init(
        succeeded: Bool,
        message: String,
        relationDelta: Int = 0,
        credibilityDelta: Int = 0
    ) {
        self.succeeded = succeeded
        self.message = message
        self.relationDelta = relationDelta
        self.credibilityDelta = credibilityDelta
    }
}

// MARK: - 外交状态机与媾和/背盟估值引擎核心实现

/// 八大势力合纵连横、量化媾和谈判、双重同盟防御豁免与反霸权制衡引擎
/// 纯值类型实现，严格遵循 Swift 6 `Sendable`、`Codable`、`Equatable`，零 UI 依赖。
public struct DiplomacyEngine: DiplomacyEngineProtocol, Sendable, Codable, Equatable {

    // MARK: - 静态规则常量（严格对齐 DESIGN.md 第 8 节与 10.3~10.4 节）

    /// 低信誉触发禁绝结盟与求和赔款溢价 +80% 的临界线
    public static let lowCredibilityThreshold: Int = 40
    /// 低信誉（C < 40）求和赔款溢价倍率（+80%）
    public static let lowCredibilityIndemnityMultiplier: Double = 1.80
    /// 沙漠商盟丝路通商收益加成倍率（+35%）
    public static let shamoTradeBonusMultiplier: Double = 1.35
    /// 每份丝路通商协定基础每回合金币收益
    public static let baseTradeIncomePerPact: Int = 65
    /// 沙漠商盟《丝路商队》科技每份商约额外金币加成
    public static let shamoCaravanTechBonusPerPact: Int = 45
    /// 反霸权【合纵警觉】相邻非同盟势力共同威胁好感修正值（+25）
    public static let antiHegemonySolidarityBonus: Int = 25
    /// 严守停战或互不侵犯条约自然届满时的守约信誉奖励（+3）
    public static let treatyFulfilledCredibilityBonus: Int = 3
    /// 挑拨离间成功对目标双边关系造成的裂痕值（-20）
    public static let instigateDiscordRelationPenalty: Int = -20
    /// 挑拨离间最低密使经费门槛
    public static let instigateDiscordMinGold: Int = 180

    // MARK: - 可序列化核心状态存储

    /// 全部 28 组无向双边外交状态（按字典序规范化存储 `factionA.rawValue < factionB.rawValue`）
    public private(set) var bilateralStates: [BilateralDiplomacyState]
    /// 八大势力外交档案与战略资产快照（按 `FactionId.allCases` 顺序存储）
    public private(set) var factionProfiles: [FactionDiplomaticProfile]
    /// 当前活跃战争及挑衅方记录
    public private(set) var activeWars: [ActiveWarRecord]
    /// 当前生效的停战纳粮与附庸纳贡记录
    public private(set) var tributeObligations: [TributeObligationRecord]
    /// 当前生效的宗主—附庸从属关系
    public private(set) var vassalBonds: [VassalBondRecord]
    /// 已激活丝路通商收益的规范化双边键集合（允许与军事同盟或联姻并存）
    public private(set) var activeTradePairKeys: [String]
    /// 已缔结政治联姻的规范化双边键集合
    public private(set) var royalMarriagePairKeys: [String]
    /// 本回合因谈判破裂被锁定的单向派使键集合（`"proposer->target"`）
    public private(set) var envoyLockedThisTurn: [String]
    /// 本回合已执行的送礼次数统计（单回合递减防无限刷好感）
    public private(set) var giftCountersThisTurn: [GiftCounterRecord]
    /// 当前已应用反霸权【合纵警觉】+25 好感修正的双边键集合（防止跨回合无限叠加）
    public private(set) var antiHegemonyBoostedPairKeys: [String]

    // MARK: - 初始化

    public init() {
        let allFactions = FactionId.allCases
        var initialPairs: [BilateralDiplomacyState] = []
        initialPairs.reserveCapacity(28)

        for i in 0..<allFactions.count {
            for j in (i + 1)..<allFactions.count {
                let ordered = Self.orderedPair(allFactions[i], allFactions[j])
                let initRel = FactionConfig.initialRelation(between: ordered.0, and: ordered.1)
                initialPairs.append(
                    BilateralDiplomacyState(
                        factionA: ordered.0,
                        factionB: ordered.1,
                        relation: Self.clampRelation(initRel),
                        status: .neutral,
                        remainingTurns: 0,
                        vendettaLockTurns: 0
                    )
                )
            }
        }
        initialPairs.sort { $0.id < $1.id }

        let profiles: [FactionDiplomaticProfile] = allFactions.map { fid in
            let cfg = FactionConfig.config(for: fid)
            let startCred = cfg?.startingCredibility ?? GameConstants.credibilityDefaultInit
            let initialNodes = CampaignMapConfig.initialNodes(for: fid).map(\.id)
            let startGold = (fid == .shamo) ? 1150 : 900
            return FactionDiplomaticProfile(
                factionId: fid,
                credibility: startCred,
                isEliminated: false,
                availableGold: startGold,
                availableGrain: 1400,
                ownedNodeIds: initialNodes,
                militaryStrengthScore: 1000.0
            )
        }

        self.bilateralStates = initialPairs
        self.factionProfiles = profiles
        self.activeWars = []
        self.tributeObligations = []
        self.vassalBonds = []
        self.activeTradePairKeys = []
        self.royalMarriagePairKeys = []
        self.envoyLockedThisTurn = []
        self.giftCountersThisTurn = []
        self.antiHegemonyBoostedPairKeys = []
    }

    // MARK: - 查询接口（关系、条约、信誉、同盟集、通商收入）

    /// 查询两势力间的双边外交状态（同一势力返回满好感中立占位）
    public func bilateralState(between factionA: FactionId, and factionB: FactionId) -> BilateralDiplomacyState {
        if factionA == factionB {
            return BilateralDiplomacyState(
                factionA: factionA,
                factionB: factionB,
                relation: GameConstants.diplomacyRelationMax,
                status: .alliance,
                remainingTurns: 0,
                vendettaLockTurns: 0
            )
        }
        let ordered = Self.orderedPair(factionA, factionB)
        if let found = bilateralStates.first(where: { $0.factionA == ordered.0 && $0.factionB == ordered.1 }) {
            return found
        }
        return BilateralDiplomacyState(
            factionA: ordered.0,
            factionB: ordered.1,
            relation: FactionConfig.initialRelation(between: ordered.0, and: ordered.1),
            status: .neutral
        )
    }

    /// 查询双边关系值 [-100, +100]
    public func relation(between factionA: FactionId, and factionB: FactionId) -> Int {
        bilateralState(between: factionA, and: factionB).relation
    }

    /// 查询双边条约状态
    public func status(between factionA: FactionId, and factionB: FactionId) -> DiplomaticStatus {
        bilateralState(between: factionA, and: factionB).status
    }

    /// 查询指定势力当前全局外交信誉 [0, 100]
    public func credibility(of factionId: FactionId) -> Int {
        profile(for: factionId).credibility
    }

    /// 查询指定势力完整外交档案
    public func profile(for factionId: FactionId) -> FactionDiplomaticProfile {
        if let found = factionProfiles.first(where: { $0.factionId == factionId }) {
            return found
        }
        let startCred = FactionConfig.config(for: factionId)?.startingCredibility ?? GameConstants.credibilityDefaultInit
        return FactionDiplomaticProfile(factionId: factionId, credibility: startCred)
    }

    /// 获取与指定势力缔结正式军事攻守同盟（`.alliance`）的所有盟友集合（供 BFS 粮道借道严格调用）
    public func alliedFactions(of factionId: FactionId) -> Set<FactionId> {
        var allies = Set<FactionId>()
        for other in FactionId.allCases where other != factionId {
            if status(between: factionId, and: other) == .alliance {
                allies.insert(other)
            }
        }
        return allies
    }

    /// 获取包含正式军事同盟（`.alliance`）与从属附庸（`.vassal`）在内的阵营成员集合（供霸权联盟胜利判定使用）
    public func coalitionPartners(of factionId: FactionId) -> Set<FactionId> {
        var members = alliedFactions(of: factionId)
        for bond in vassalBonds {
            if bond.suzerain == factionId {
                members.insert(bond.vassal)
            } else if bond.vassal == factionId {
                members.insert(bond.suzerain)
            }
        }
        return members
    }

    /// 查询求方在媾和谈判中适用的赔款要求溢价倍率（信誉 < 40 时强制溢价 +80%，即 1.80 倍）
    public func requiredIndemnityPremiumMultiplier(for proposer: FactionId) -> Double {
        credibility(of: proposer) < Self.lowCredibilityThreshold ? Self.lowCredibilityIndemnityMultiplier : 1.0
    }

    /// 判断两势力当前是否存在有效丝路通商关系
    public func hasTradeAgreement(between factionA: FactionId, and factionB: FactionId) -> Bool {
        guard factionA != factionB else { return false }
        let st = status(between: factionA, and: factionB)
        if st == .war { return false }
        if st == .tradePact { return true }
        let key = Self.pairKey(factionA, factionB)
        return activeTradePairKeys.contains(key)
    }

    /// 计算指定势力当前每回合丝路通商总收入（严格兑现沙漠商盟 +35% 贸易收益与《丝路商队》科技加成）
    public func calculateTradeIncome(for factionId: FactionId, unlockedTechs: Set<String>? = nil) -> Int {
        let prof = profile(for: factionId)
        guard !prof.isEliminated else { return 0 }
        let techs = unlockedTechs ?? Set(prof.unlockedTechIds)

        var partnerCount = 0
        var rawGold = 0
        for other in FactionId.allCases where other != factionId {
            guard !profile(for: other).isEliminated,
                  hasTradeAgreement(between: factionId, and: other) else {
                continue
            }
            partnerCount += 1
            // 与沙漠商盟通商的伙伴亦可共享丝路繁荣红利 +15 金
            let partnerBonus = (other == .shamo) ? 15 : 0
            rawGold += Self.baseTradeIncomePerPact + partnerBonus
        }

        guard partnerCount > 0 else { return 0 }

        var total = Double(rawGold)
        if factionId == .shamo {
            total *= Self.shamoTradeBonusMultiplier
            if techs.contains("sm_tech_caravan") {
                total += Double(partnerCount * Self.shamoCaravanTechBonusPerPact)
            }
        }
        return Int(total.rounded())
    }

    /// 检查本回合求方向目标方派使是否已被锁定
    public func isEnvoyLockedThisTurn(from proposer: FactionId, to target: FactionId) -> Bool {
        envoyLockedThisTurn.contains(Self.envoyKey(from: proposer, to: target))
    }

    /// 查询某场战争的主动挑衅侵略方（若未交战则返回 nil）
    public func warAggressor(between factionA: FactionId, and factionB: FactionId) -> FactionId? {
        let key = Self.pairKey(factionA, factionB)
        return activeWars.first(where: { $0.pairKey == key })?.aggressor
    }

    /// 计算单座城关用于外交割让谈判的量化战略价值（严格落在 DESIGN.md 8.3 规定的 [25, 60] 区间）
    public func strategicNodeValue(forNodeId nodeId: String) -> Double {
        guard let node = CampaignMapConfig.node(byId: nodeId) else {
            return 30.0
        }
        let typeBase: Double
        switch node.nodeType {
        case .capitalCitadel:
            typeBase = 56.0
        case .fortressPass:
            typeBase = 42.0
        case .granaryTown:
            typeBase = 40.0
        case .resourceHub:
            typeBase = 36.0
        case .crossingOutpost:
            typeBase = 28.0
        }
        let yieldAdjust = Double(node.totalYield - 250) / 18.0
        let depotBonus = node.isSupplyDepot ? 5.0 : 0.0
        let defenseBonus = Double(max(0, node.defenseLevel - 2)) * 1.5
        let rawValue = typeBase + yieldAdjust + depotBonus + defenseBonus
        return max(25.0, min(60.0, rawValue))
    }

    // MARK: - 战略态势同步接口（供 CampaignTurnEngine 与单元测试注入实时国力资产）

    /// 更新指定势力的国库资产、占城列表、军力估值与厌战度
    public mutating func syncFactionStrategicSnapshot(
        factionId: FactionId,
        availableGold: Int,
        availableGrain: Int,
        ownedNodeIds: [String],
        militaryStrengthScore: Double,
        warExhaustion: Double? = nil,
        unlockedTechIds: [String]? = nil
    ) {
        mutateProfile(for: factionId) { prof in
            prof.availableGold = max(0, availableGold)
            prof.availableGrain = max(0, availableGrain)
            prof.ownedNodeIds = ownedNodeIds
            prof.isEliminated = ownedNodeIds.isEmpty
            prof.militaryStrengthScore = max(0.0, militaryStrengthScore)
            if let exhaustion = warExhaustion {
                prof.warExhaustion = max(0.0, min(45.0, exhaustion))
            }
            if let techs = unlockedTechIds {
                prof.unlockedTechIds = techs
            }
        }
    }

    /// 更新指定势力的厌战度与交战双边战场胜势分
    public mutating func recordBattleImpactOnWar(
        winner: FactionId,
        loser: FactionId,
        winnerCasualties: Int,
        loserCasualties: Int,
        cityCaptured: Bool
    ) {
        let swing = min(22.0, (cityCaptured ? 12.0 : 6.0) + Double(max(0, loserCasualties - winnerCasualties)) * 0.04)
        let key = Self.pairKey(winner, loser)
        if let idx = activeWars.firstIndex(where: { $0.pairKey == key }) {
            if activeWars[idx].aggressor == winner {
                activeWars[idx].aggressorBattleScore = max(-40.0, min(40.0, activeWars[idx].aggressorBattleScore + swing))
            } else {
                activeWars[idx].aggressorBattleScore = max(-40.0, min(40.0, activeWars[idx].aggressorBattleScore - swing))
            }
        }

        mutateProfile(for: loser) { prof in
            let delta = (cityCaptured ? 9.5 : 5.5) + Double(loserCasualties) * 0.03
            prof.warExhaustion = min(45.0, prof.warExhaustion + delta)
        }
        mutateProfile(for: winner) { prof in
            let delta = 1.5 + Double(winnerCasualties) * 0.025
            prof.warExhaustion = min(45.0, prof.warExhaustion + delta)
        }
    }

    /// 调整指定势力的全局外交信誉（严格钳制在 [0, 100]，如释放战俘赎回信誉 +2）
    @discardableResult
    public mutating func adjustCredibility(of factionId: FactionId, delta: Int) -> Int {
        var updated = credibility(of: factionId)
        mutateProfile(for: factionId) { prof in
            prof.credibility = max(0, min(100, prof.credibility + delta))
            updated = prof.credibility
        }
        return updated
    }

    /// 消耗一场战斗的背盟初始士气惩罚或求和被拒士气激励，返回本场战斗我方初始士气修正值
    public mutating func consumePreBattleMoraleAdjustment(for factionId: FactionId) -> Double {
        var adjustment = 0.0
        mutateProfile(for: factionId) { prof in
            if prof.betrayalMoralePenaltyBattles > 0 {
                adjustment += prof.betrayalMoralePenaltyDelta
                prof.betrayalMoralePenaltyBattles -= 1
                if prof.betrayalMoralePenaltyBattles == 0 {
                    prof.betrayalMoralePenaltyDelta = 0.0
                }
            }
            if prof.nextBattleMoraleBonus != 0.0 {
                adjustment += prof.nextBattleMoraleBonus
                prof.nextBattleMoraleBonus = 0.0
            }
        }
        return adjustment
    }

    // MARK: - DiplomacyEngineProtocol：1. 背盟后果与双重同盟防御优先豁免评估

    /// 评估宣战或协防动作是否构成背盟（严格落实 DESIGN.md 10.3 双重同盟防御优先豁免铁律）
    public func assessWarDeclarationImpact(attacker: FactionId, target: FactionId) -> BetrayalImpactAssessment {
        guard attacker != target else {
            return BetrayalImpactAssessment(
                isBetrayalTriggered: false,
                ruleExplanation: "目标不可为本势力自身",
                credibilityDelta: 0,
                globalRelationDelta: 0,
                vendettaLockTurns: 0,
                battleMoralePenalty: 0.0
            )
        }

        let currentState = bilateralState(between: attacker, and: target)
        if currentState.status == .war {
            return BetrayalImpactAssessment(
                isBetrayalTriggered: false,
                ruleExplanation: "双方已处于交战状态，无需重复宣战",
                credibilityDelta: 0,
                globalRelationDelta: 0,
                vendettaLockTurns: 0,
                battleMoralePenalty: 0.0
            )
        }

        // 检查是否存在受国际信誉保护的和平/同盟/停战/联姻/宗藩契约
        let hasBindingPeaceTreaty: Bool
        switch currentState.status {
        case .alliance, .royalMarriage, .vassal:
            hasBindingPeaceTreaty = true
        case .truce, .nonAggression:
            hasBindingPeaceTreaty = currentState.remainingTurns > 0
        case .neutral, .tradePact, .war:
            hasBindingPeaceTreaty = false
        }

        guard hasBindingPeaceTreaty else {
            return BetrayalImpactAssessment(
                isBetrayalTriggered: false,
                ruleExplanation: "双方无互不侵犯、停战或同盟条约约束，正式宣战不扣除外交信誉（仅双边关系降至 -80）",
                credibilityDelta: 0,
                globalRelationDelta: 0,
                vendettaLockTurns: 0,
                battleMoralePenalty: 0.0
            )
        }

        // 【核心铁律】：双重同盟互攻时的防御优先保护豁免检查
        // 若 attacker 同时与 target(B) 及另一盟友 C 结有正式军事同盟（.alliance），且 B 主动侵略了 C，
        // 则 attacker 响应防御同盟向挑衅侵略方 B 宣战协防 C 时，完全豁免背盟惩罚！
        if let defendedAlly = findDefendedAllyAgainstAggressor(defenderHelper: attacker, aggressorTarget: target) {
            let targetName = FactionConfig.config(for: target)?.name ?? target.rawValue
            let allyName = FactionConfig.config(for: defendedAlly)?.name ?? defendedAlly.rawValue
            return BetrayalImpactAssessment(
                isBetrayalTriggered: false,
                ruleExplanation: "触发【双重同盟防御优先豁免铁律】：\(targetName)主动向我方同盟国\(allyName)挑起侵略战争，履行防御同盟义务出兵协防受侵略方不构成背盟，零信誉扣除",
                credibilityDelta: 0,
                globalRelationDelta: 0,
                vendettaLockTurns: 0,
                battleMoralePenalty: 0.0
            )
        }

        // 构成真实背盟：按势力正邪守序性格确定连续 2 场战斗士气惩罚
        let moralePenalty = Self.betrayalBattleMoralePenalty(for: attacker)
        let targetName = FactionConfig.config(for: target)?.name ?? target.rawValue
        return BetrayalImpactAssessment(
            isBetrayalTriggered: true,
            ruleExplanation: "撕毁与\(targetName)尚在有效期内的【\(currentState.status.displayName)】条约发动背盟突袭：信誉 -\(GameConstants.betrayalCredibilityPenalty)，受害国锁死 -100 关系并激活 \(GameConstants.betrayalVendettaLockTurns) 回合血海世仇，全图其余诸侯关系 -\(GameConstants.betrayalGlobalRelationPenalty)，随后 2 场战斗初始士气 \(Int(moralePenalty))",
            credibilityDelta: -GameConstants.betrayalCredibilityPenalty,
            globalRelationDelta: -GameConstants.betrayalGlobalRelationPenalty,
            vendettaLockTurns: GameConstants.betrayalVendettaLockTurns,
            battleMoralePenalty: moralePenalty
        )
    }

    // MARK: - DiplomacyEngineProtocol：2. 媾和报价量化评估与三档反报价闭环

    /// 严格按照 DESIGN.md 8.3 & 10.4 公式计算媾和净得分并返回三档谈判结果（纯函数无副作用）
    public func evaluatePeaceOffer(_ offer: PeaceOfferTerms) -> PeaceNegotiationOutcome {
        guard offer.proposer != offer.target else {
            return .rejectedBreakdown(netScore: -100.0, reason: "不可向本势力自身发起议和")
        }

        let state = bilateralState(between: offer.proposer, and: offer.target)

        // 1. 血海世仇锁定期强制斥退
        if state.vendettaLockTurns > 0 {
            return .rejectedBreakdown(
                netScore: -100.0,
                reason: "处于【血海世仇】禁谈锁定期（剩余 \(state.vendettaLockTurns) 回合），受害国拒绝一切停火谈判"
            )
        }

        // 2. 本回合已被斥退锁定防穷举刷数值
        if isEnvoyLockedThisTurn(from: offer.proposer, to: offer.target) {
            return .rejectedBreakdown(
                netScore: -50.0,
                reason: "本回合来使已被对方斥退，不可在同一回合内反复派使试探底线"
            )
        }

        let breakdown = computePeaceScoreBreakdown(for: offer)
        let netScore = breakdown.netScore

        // 三档闭环分支判定
        if netScore >= 0.0 {
            return .accepted(netScore: netScore)
        } else if netScore >= -20.0 {
            let counterTerms = generateBoundedCounterOffer(for: offer, scoreBreakdown: breakdown)
            return .counterOffer(netScore: netScore, counterTerms: counterTerms)
        } else {
            let formatted = String(format: "%.1f", netScore)
            return .rejectedBreakdown(
                netScore: netScore,
                reason: "议和筹码与战场态势差距悬殊（量化净分 \(formatted) < -20），对方盛怒斥退来使"
            )
        }
    }

    // MARK: - 外交行动执行接口（宣战、签约、通商、结盟、附庸、联姻、送礼、挑拨、调停）

    /// 执行正式宣战或协防参战（自动应用 `assessWarDeclarationImpact` 的背盟惩罚或防御同盟豁免）
    @discardableResult
    public mutating func declareWar(attacker: FactionId, target: FactionId) -> BetrayalImpactAssessment {
        let assessment = assessWarDeclarationImpact(attacker: attacker, target: target)
        guard attacker != target, status(between: attacker, and: target) != .war else {
            return assessment
        }

        let defendedAlly = findDefendedAllyAgainstAggressor(defenderHelper: attacker, aggressorTarget: target)
        let key = Self.pairKey(attacker, target)

        // 终止双方任何通商、联姻、宗藩与纳贡协定
        activeTradePairKeys.removeAll { $0 == key }
        royalMarriagePairKeys.removeAll { $0 == key }
        vassalBonds.removeAll {
            ($0.suzerain == attacker && $0.vassal == target) ||
            ($0.suzerain == target && $0.vassal == attacker)
        }
        tributeObligations.removeAll {
            ($0.payer == attacker && $0.recipient == target) ||
            ($0.payer == target && $0.recipient == attacker)
        }

        if assessment.isBetrayalTriggered {
            // 1. 扣除背盟方信誉 -45
            mutateProfile(for: attacker) { prof in
                prof.credibility = max(0, min(100, prof.credibility + assessment.credibilityDelta))
                prof.betrayalMoralePenaltyBattles = 2
                prof.betrayalMoralePenaltyDelta = assessment.battleMoralePenalty
            }

            // 2. 受害国关系直接锁死 -100 并激活 10 回合血海世仇
            mutateBilateralState(between: attacker, and: target) { st in
                st.status = .war
                st.remainingTurns = 0
                st.relation = GameConstants.diplomacyRelationMin
                st.vendettaLockTurns = assessment.vendettaLockTurns
            }

            // 3. 天下共愤：全图其余所有存活势力对背盟方关系立即 -25
            for thirdFaction in FactionId.allCases where thirdFaction != attacker && thirdFaction != target {
                guard !profile(for: thirdFaction).isEliminated else { continue }
                adjustRelation(between: attacker, and: thirdFaction, delta: assessment.globalRelationDelta)
            }
        } else {
            // 正常宣战或双重同盟防御优先豁免参战
            mutateBilateralState(between: attacker, and: target) { st in
                st.status = .war
                st.remainingTurns = 0
                st.relation = min(st.relation, -80)
            }

            // 若属于协防受侵略盟友，并肩作战立即提升与受保护盟友的关系 +15
            if let ally = defendedAlly {
                adjustRelation(between: attacker, and: ally, delta: 15)
            }
        }

        // 记录战争挑衅责任（若为协防参战，真正的挑衅源头仍是原侵略方 target；若主动开战，则 attacker 为挑衅方）
        activeWars.removeAll { $0.pairKey == key }
        if defendedAlly != nil {
            activeWars.append(ActiveWarRecord(pairKey: key, aggressor: target, defender: attacker))
        } else {
            activeWars.append(ActiveWarRecord(pairKey: key, aggressor: attacker, defender: target))
        }

        return assessment
    }

    /// 双重同盟居中调停：当 A 同时与 B、C 结盟且 B 攻 C 时，A 可促成 B、C 立即签署 3 回合缓冲停火，零信誉损失
    @discardableResult
    public mutating func mediateAlliedConflict(
        mediator: FactionId,
        belligerentA: FactionId,
        belligerentB: FactionId
    ) -> DiplomaticActionResult {
        guard mediator != belligerentA, mediator != belligerentB, belligerentA != belligerentB else {
            return DiplomaticActionResult(succeeded: false, message: "调停目标势力参数无效")
        }
        guard status(between: mediator, and: belligerentA) == .alliance,
              status(between: mediator, and: belligerentB) == .alliance,
              status(between: belligerentA, and: belligerentB) == .war else {
            return DiplomaticActionResult(succeeded: false, message: "仅当与交战双方均缔结有军事同盟时方可执行居中调停")
        }

        let warKey = Self.pairKey(belligerentA, belligerentB)
        activeWars.removeAll { $0.pairKey == warKey }
        mutateBilateralState(between: belligerentA, and: belligerentB) { st in
            st.status = .truce
            st.remainingTurns = 3
            st.relation = max(st.relation, -35)
        }
        return DiplomaticActionResult(
            succeeded: true,
            message: "居中斡旋成功：促成两大盟友签署 3 回合停战协议，避免同盟体系撕裂"
        )
    }

    /// 正式提交媾和报价并落地状态变更（签约停火 / 返回可负担反报价 / 破裂扣关系锁使者）
    public mutating func submitPeaceOffer(_ offer: PeaceOfferTerms) -> PeaceNegotiationOutcome {
        let outcome = evaluatePeaceOffer(offer)

        switch outcome {
        case .accepted:
            applyAcceptedPeaceTerms(offer)

        case .counterOffer:
            // 反报价阶段保持谈判通道开启，交由求方决定是否调用 `acceptCounterOffer` 成交
            break

        case .rejectedBreakdown:
            let wasAtWar = (status(between: offer.proposer, and: offer.target) == .war)
            adjustRelation(between: offer.proposer, and: offer.target, delta: -10)
            let lockKey = Self.envoyKey(from: offer.proposer, to: offer.target)
            if !envoyLockedThisTurn.contains(lockKey) {
                envoyLockedThisTurn.append(lockKey)
            }
            if wasAtWar {
                // DESIGN.md 10.4：战中屈辱求和被拒，敌军获下场战斗士气 +8
                mutateProfile(for: offer.target) { prof in
                    prof.nextBattleMoraleBonus = 8.0
                }
            } else if offer.goldIndemnity < 0 || offer.grainTributePerTurn < 0 || computePeaceScoreBreakdown(for: offer).rawOfferValue < 0.0 {
                // DESIGN.md 10.4：战前边缘讹诈（索金/索粮/索城）破裂，对方当回合直接宣战压境
                _ = declareWar(attacker: offer.target, target: offer.proposer)
            }
        }

        return outcome
    }

    /// 接受对方开出的反报价单并立即落地停火条约
    @discardableResult
    public mutating func acceptCounterOffer(_ counterTerms: PeaceOfferTerms) -> DiplomaticActionResult {
        guard status(between: counterTerms.proposer, and: counterTerms.target) != .alliance else {
            return DiplomaticActionResult(succeeded: false, message: "双方已是同盟关系")
        }
        let state = bilateralState(between: counterTerms.proposer, and: counterTerms.target)
        guard state.vendettaLockTurns == 0 else {
            return DiplomaticActionResult(succeeded: false, message: "处于血海世仇锁定期，无法签约")
        }
        applyAcceptedPeaceTerms(counterTerms)
        return DiplomaticActionResult(
            succeeded: true,
            message: "已接受反报价条件，双方正式停火 \(Self.normalizeTruceTurns(counterTerms.truceTurns)) 回合"
        )
    }

    /// 缔结互不侵犯条约（门槛：`R >= 15` 且双方 `C >= 40`，默认有效期 8 回合）
    public mutating func signNonAggressionPact(
        proposer: FactionId,
        target: FactionId,
        durationTurns: Int = 8
    ) -> DiplomaticActionResult {
        guard proposer != target else {
            return DiplomaticActionResult(succeeded: false, message: "不可与自身签约")
        }
        let st = bilateralState(between: proposer, and: target)
        guard st.vendettaLockTurns == 0, st.status != .war else {
            return DiplomaticActionResult(succeeded: false, message: "交战或世仇状态下无法直接签署互不侵犯条约")
        }
        guard st.status != .alliance else {
            return DiplomaticActionResult(succeeded: false, message: "双方已缔结更高级别的军事攻守同盟")
        }
        guard st.relation >= GameConstants.nonAggressionMinRelation else {
            return DiplomaticActionResult(
                succeeded: false,
                message: "双边关系不足（需 ≥ +\(GameConstants.nonAggressionMinRelation)，当前 \(st.relation)）"
            )
        }
        let proposerCred = credibility(of: proposer)
        let targetCred = credibility(of: target)
        guard proposerCred >= GameConstants.nonAggressionMinCredibility,
              targetCred >= GameConstants.nonAggressionMinCredibility else {
            return DiplomaticActionResult(
                succeeded: false,
                message: "外交信誉过低（需双方信誉 ≥ \(GameConstants.nonAggressionMinCredibility)）"
            )
        }

        let turns = max(4, durationTurns)
        mutateBilateralState(between: proposer, and: target) { state in
            state.status = .nonAggression
            state.remainingTurns = turns
            state.relation = Self.clampRelation(state.relation + 8)
        }
        return DiplomaticActionResult(
            succeeded: true,
            message: "签署【互不侵犯条约】成功（有效期 \(turns) 回合，消除边境接壤摩擦）",
            relationDelta: 8
        )
    }

    /// 签署丝路通商协定（门槛：`R >= 25`；沙漠商盟享 +35% 通商收益加成）
    public mutating func signTradePact(proposer: FactionId, target: FactionId) -> DiplomaticActionResult {
        guard proposer != target else {
            return DiplomaticActionResult(succeeded: false, message: "不可与自身通商")
        }
        let st = bilateralState(between: proposer, and: target)
        guard st.vendettaLockTurns == 0, st.status != .war else {
            return DiplomaticActionResult(succeeded: false, message: "交战或血海世仇期间禁绝通商往来")
        }
        guard st.relation >= GameConstants.tradePactMinRelation else {
            return DiplomaticActionResult(
                succeeded: false,
                message: "双边关系不足（需 ≥ +\(GameConstants.tradePactMinRelation)，当前 \(st.relation)）"
            )
        }
        let key = Self.pairKey(proposer, target)
        if hasTradeAgreement(between: proposer, and: target) {
            return DiplomaticActionResult(succeeded: false, message: "双方已开通丝路商道，无需重复签署")
        }

        activeTradePairKeys.append(key)
        activeTradePairKeys.sort()

        mutateBilateralState(between: proposer, and: target) { state in
            // 若当前仅为中立，则主状态升级为通商协定；若已为互不侵犯/联姻/同盟则保留原高级条约并叠加通商收益
            if state.status == .neutral {
                state.status = .tradePact
            }
            state.relation = Self.clampRelation(state.relation + 6)
        }
        return DiplomaticActionResult(
            succeeded: true,
            message: "开通【丝路通商协定】成功，每回合稳定获取贸易税赋并改善双边关系",
            relationDelta: 6
        )
    }

    /// 缔结正式军事攻守同盟（门槛：`R >= 55` 且双方 `C >= 50`；当 `C < 40` 时全图禁绝结盟）
    public mutating func formMilitaryAlliance(proposer: FactionId, target: FactionId) -> DiplomaticActionResult {
        guard proposer != target else {
            return DiplomaticActionResult(succeeded: false, message: "不可与自身结盟")
        }
        let st = bilateralState(between: proposer, and: target)
        guard st.vendettaLockTurns == 0, st.status != .war else {
            return DiplomaticActionResult(succeeded: false, message: "交战或世仇状态下不可结盟")
        }
        if st.status == .alliance {
            return DiplomaticActionResult(succeeded: false, message: "双方已处于军事同盟状态")
        }

        let proposerCred = credibility(of: proposer)
        let targetCred = credibility(of: target)
        if proposerCred < Self.lowCredibilityThreshold || targetCred < Self.lowCredibilityThreshold {
            return DiplomaticActionResult(
                succeeded: false,
                message: "信誉跌破 \(Self.lowCredibilityThreshold) 红线，天下诸侯禁绝与其缔结同盟"
            )
        }
        guard proposerCred >= GameConstants.allianceMinCredibility,
              targetCred >= GameConstants.allianceMinCredibility else {
            return DiplomaticActionResult(
                succeeded: false,
                message: "外交信誉未达标（缔结军事同盟需双方信誉 ≥ \(GameConstants.allianceMinCredibility)）"
            )
        }
        guard st.relation >= GameConstants.allianceMinRelation else {
            return DiplomaticActionResult(
                succeeded: false,
                message: "双边好感不足（需 ≥ +\(GameConstants.allianceMinRelation)，当前 \(st.relation)）"
            )
        }

        let key = Self.pairKey(proposer, target)
        if !activeTradePairKeys.contains(key) {
            activeTradePairKeys.append(key)
            activeTradePairKeys.sort()
        }

        mutateBilateralState(between: proposer, and: target) { state in
            state.status = .alliance
            state.remainingTurns = 0
            state.relation = Self.clampRelation(state.relation + 15)
        }

        return DiplomaticActionResult(
            succeeded: true,
            message: "缔结【军事攻守同盟】成功！已互相开放 BFS 粮道补给借道权与战略视野共享",
            relationDelta: 15
        )
    }

    /// 缔结政治联姻结好（门槛：`R >= 35` 且双方 `C >= 45`，大幅巩固双边关系 `+25`）
    public mutating func arrangeRoyalMarriage(proposer: FactionId, target: FactionId) -> DiplomaticActionResult {
        guard proposer != target else {
            return DiplomaticActionResult(succeeded: false, message: "不可与自身联姻")
        }
        let st = bilateralState(between: proposer, and: target)
        guard st.vendettaLockTurns == 0, st.status != .war else {
            return DiplomaticActionResult(succeeded: false, message: "交战或世仇状态下无法联姻")
        }
        let key = Self.pairKey(proposer, target)
        if royalMarriagePairKeys.contains(key) {
            return DiplomaticActionResult(succeeded: false, message: "双方王室已缔有姻亲盟誓")
        }
        guard credibility(of: proposer) >= 45, credibility(of: target) >= 45 else {
            return DiplomaticActionResult(succeeded: false, message: "联姻需双方信誉 ≥ 45")
        }
        let minRel = (proposer == .xueyue || target == .xueyue) ? 50 : 35
        guard st.relation >= minRel else {
            return DiplomaticActionResult(succeeded: false, message: "双边关系不足（联姻需关系 ≥ +\(minRel)）")
        }

        royalMarriagePairKeys.append(key)
        royalMarriagePairKeys.sort()

        mutateBilateralState(between: proposer, and: target) { state in
            if state.status != .alliance {
                state.status = .royalMarriage
                state.remainingTurns = 0
            }
            state.relation = Self.clampRelation(state.relation + 25)
        }
        return DiplomaticActionResult(
            succeeded: true,
            message: "缔结【政治联姻】成功，双方关系跃升 +25 并建立长期姻亲纽带",
            relationDelta: 25
        )
    }

    /// 建立朝贡附庸关系（残存 <= 2 城的弱小势力纳贡求存，宗主国享补给借道与每回合岁币纳粮）
    public mutating func establishVassalage(
        suzerain: FactionId,
        vassal: FactionId,
        tributeGoldPerTurn: Int = 50,
        tributeGrainPerTurn: Int = 60
    ) -> DiplomaticActionResult {
        guard suzerain != vassal else {
            return DiplomaticActionResult(succeeded: false, message: "不可收自身为附庸")
        }
        let vassalProfile = profile(for: vassal)
        guard !vassalProfile.isEliminated else {
            return DiplomaticActionResult(succeeded: false, message: "目标势力已覆灭")
        }
        guard vassalProfile.ownedNodeIds.count <= 2 else {
            return DiplomaticActionResult(
                succeeded: false,
                message: "对方尚拥 \(vassalProfile.ownedNodeIds.count) 座城关，国力未衰，拒绝屈膝称臣（需城池 ≤ 2）"
            )
        }
        guard credibility(of: suzerain) >= Self.lowCredibilityThreshold else {
            return DiplomaticActionResult(succeeded: false, message: "宗主国信誉低于 40，弱国宁死不降")
        }
        let st = bilateralState(between: suzerain, and: vassal)
        guard st.vendettaLockTurns == 0 else {
            return DiplomaticActionResult(succeeded: false, message: "双方存在血海世仇，对方誓死不降")
        }

        let warKey = Self.pairKey(suzerain, vassal)
        activeWars.removeAll { $0.pairKey == warKey }
        vassalBonds.removeAll { $0.vassal == vassal }
        vassalBonds.append(VassalBondRecord(suzerain: suzerain, vassal: vassal))

        tributeObligations.removeAll { $0.payer == vassal }
        tributeObligations.append(
            TributeObligationRecord(
                payer: vassal,
                recipient: suzerain,
                goldPerTurn: max(0, tributeGoldPerTurn),
                grainPerTurn: max(0, tributeGrainPerTurn),
                remainingTurns: -1
            )
        )

        mutateBilateralState(between: suzerain, and: vassal) { state in
            state.status = .vassal
            state.remainingTurns = 0
            state.relation = max(state.relation, 25)
        }

        return DiplomaticActionResult(
            succeeded: true,
            message: "受降纳贡成功：已册封朝贡附庸，停息干戈并每回合收取岁币粮饷"
        )
    }

    /// 馈赠金粮改善关系（严格执行单回合递减防无限刷：第 1 次 100%，第 2 次 50%，第 3 次 25%，第 4 次起归零）
    public mutating func sendDiplomaticGift(
        from sender: FactionId,
        to receiver: FactionId,
        gold: Int,
        grain: Int
    ) -> DiplomaticActionResult {
        guard sender != receiver else {
            return DiplomaticActionResult(succeeded: false, message: "不可向自身馈赠礼金")
        }
        guard gold > 0 || grain > 0 else {
            return DiplomaticActionResult(succeeded: false, message: "馈赠金粮数额必须大于 0")
        }
        let st = bilateralState(between: sender, and: receiver)
        guard st.vendettaLockTurns == 0 else {
            return DiplomaticActionResult(succeeded: false, message: "处于血海世仇锁定期，对方拒收一切馈赠")
        }
        guard st.status != .war else {
            return DiplomaticActionResult(succeeded: false, message: "交战期间请通过正式【媾和谈判】渠道报价")
        }

        let priorCount = giftCountThisTurn(from: sender, to: receiver)
        let diminishingFactor: Double
        switch priorCount {
        case 0:
            diminishingFactor = 1.00
        case 1:
            diminishingFactor = 0.50
        case 2:
            diminishingFactor = 0.25
        default:
            return DiplomaticActionResult(
                succeeded: false,
                message: "本回合对该国馈赠次数已达上限（单回合防刷保护），请待下回合再行联络",
                relationDelta: 0
            )
        }

        var rawPoints = min(22.0, Double(max(0, gold)) / 20.0 + Double(max(0, grain)) / 30.0)
        let senderProf = profile(for: sender)
        if sender == .shamo && senderProf.unlockedTechIds.contains("sm_tech_caravan") {
            rawPoints *= 1.25
        }

        let gainedRelation = max(1, Int((rawPoints * diminishingFactor).rounded()))
        incrementGiftCountThisTurn(from: sender, to: receiver)
        let actualDelta = adjustRelation(between: sender, and: receiver, delta: gainedRelation)

        return DiplomaticActionResult(
            succeeded: true,
            message: "使团呈递厚礼（金 \(max(0, gold)) / 粮 \(max(0, grain))），双边关系提升 +\(actualDelta)",
            relationDelta: actualDelta
        )
    }

    /// 密使挑拨离间（耗费重金离间目标两国关系 `-20`，若同盟关系跌破临界值将直接瓦解同盟）
    public mutating func instigateDiscord(
        actor: FactionId,
        targetA: FactionId,
        targetB: FactionId,
        goldSpent: Int
    ) -> DiplomaticActionResult {
        guard targetA != targetB, actor != targetA, actor != targetB else {
            return DiplomaticActionResult(succeeded: false, message: "挑拨离间须指定两个不同的第三方势力")
        }
        guard goldSpent >= Self.instigateDiscordMinGold else {
            return DiplomaticActionResult(
                succeeded: false,
                message: "密使经费不足（挑拨离间至少需投入 \(Self.instigateDiscordMinGold) 金币）"
            )
        }

        // 投入经费越高，离间深度越稳（基础 -20，重金最高 -28）
        let extraDepth = min(8, (goldSpent - Self.instigateDiscordMinGold) / 80)
        let penalty = Self.instigateDiscordRelationPenalty - extraDepth
        let delta = adjustRelation(between: targetA, and: targetB, delta: penalty)

        var allianceBrokenNote = ""
        let updated = bilateralState(between: targetA, and: targetB)
        if updated.status == .alliance && updated.relation < GameConstants.tradePactMinRelation {
            mutateBilateralState(between: targetA, and: targetB) { st in
                st.status = .nonAggression
                st.remainingTurns = 3
            }
            allianceBrokenNote = "，成功令双方猜忌瓦解【军事同盟】！"
        }

        return DiplomaticActionResult(
            succeeded: true,
            message: "流言密计奏效：目标两国双边关系下降 \(delta)\(allianceBrokenNote)",
            relationDelta: delta
        )
    }

    // MARK: - 反霸权【合纵警觉】制衡（>= 13 座城关触发相邻非同盟势力 +25 共同威胁修正）

    /// 根据当前 40 城关归属重算反霸权【合纵警觉】（`GameConstants.antiHegemonyNodeThreshold == 13`）
    /// - Returns: 本次新激活 +25 共同威胁好感修正的双边势力对数量
    @discardableResult
    public mutating func recalculateAntiHegemonyAlert(nodeOwners: [String: FactionId]) -> Int {
        var countsByFaction: [FactionId: Int] = [:]
        for owner in nodeOwners.values {
            countsByFaction[owner, default: 0] += 1
        }

        let hegemons: Set<FactionId> = Set(
            countsByFaction.compactMap { faction, count in
                count >= GameConstants.antiHegemonyNodeThreshold ? faction : nil
            }
        )

        var qualifyingKeys = Set<String>()
        if !hegemons.isEmpty {
            let allFactions = FactionId.allCases
            for i in 0..<allFactions.count {
                for j in (i + 1)..<allFactions.count {
                    let fA = allFactions[i]
                    let fB = allFactions[j]
                    // 霸权扩张国自身不享受合纵好感
                    guard !hegemons.contains(fA), !hegemons.contains(fB) else { continue }
                    guard (countsByFaction[fA] ?? 0) > 0, (countsByFaction[fB] ?? 0) > 0 else { continue }

                    let current = bilateralState(between: fA, and: fB)
                    guard current.status != .alliance, current.vendettaLockTurns == 0 else { continue }
                    guard Self.areTerritoriesAdjacent(fA, fB, nodeOwners: nodeOwners) else { continue }
                    qualifyingKeys.insert(Self.pairKey(fA, fB))
                }
            }
        }

        // 对已失效（例如霸权国衰落至 <13 城、或其中一方自身变成霸权国）但未升格为同盟的组合回收临时修正，防跨回合反复刷分
        for existingKey in antiHegemonyBoostedPairKeys where !qualifyingKeys.contains(existingKey) {
            let parts = existingKey.split(separator: "_")
            if parts.count == 2,
               let fA = FactionId(rawValue: String(parts[0])),
               let fB = FactionId(rawValue: String(parts[1])),
               status(between: fA, and: fB) != .alliance {
                _ = adjustRelation(between: fA, and: fB, delta: -Self.antiHegemonySolidarityBonus)
            }
        }

        var newlyBoostedCount = 0
        for key in qualifyingKeys where !antiHegemonyBoostedPairKeys.contains(key) {
            let parts = key.split(separator: "_")
            if parts.count == 2,
               let fA = FactionId(rawValue: String(parts[0])),
               let fB = FactionId(rawValue: String(parts[1])) {
                _ = adjustRelation(between: fA, and: fB, delta: Self.antiHegemonySolidarityBonus)
                newlyBoostedCount += 1
            }
        }

        antiHegemonyBoostedPairKeys = qualifyingKeys.sorted()
        return newlyBoostedCount
    }

    // MARK: - 回合推进外交状态演化

    /// 推进一回合全局外交演化（接壤摩擦 -2、通商升温 +2、停战届满守约信誉 +3、世仇倒计时、解锁当回合派使与送礼上限）
    public mutating func advanceDiplomacyTurn(nodeOwners: [String: FactionId]) {
        // 1. 清空单回合临时锁与送礼递减计数
        envoyLockedThisTurn.removeAll()
        giftCountersThisTurn.removeAll()

        // 2. 更新活跃战争持续回合数与自然厌战度增长
        for idx in activeWars.indices {
            activeWars[idx].warTurnsElapsed += 1
            let agg = activeWars[idx].aggressor
            let def = activeWars[idx].defender
            mutateProfile(for: agg) { $0.warExhaustion = min(45.0, $0.warExhaustion + 2.0) }
            mutateProfile(for: def) { $0.warExhaustion = min(45.0, $0.warExhaustion + 2.2) }
        }

        // 3. 演进全部 28 组双边关系、条约倒计时与世仇锁定期
        for idx in bilateralStates.indices {
            let fA = bilateralStates[idx].factionA
            let fB = bilateralStates[idx].factionB

            // 血海世仇倒计时递减（锁定期内关系强制钉死 -100）
            if bilateralStates[idx].vendettaLockTurns > 0 {
                bilateralStates[idx].vendettaLockTurns -= 1
                bilateralStates[idx].relation = GameConstants.diplomacyRelationMin
            }

            let currentStatus = bilateralStates[idx].status

            // 通商协定每回合 +2 好感
            if hasTradeAgreement(between: fA, and: fB), bilateralStates[idx].vendettaLockTurns == 0 {
                bilateralStates[idx].relation = Self.clampRelation(bilateralStates[idx].relation + 2)
            }

            // 领土接壤摩擦：无互不侵犯/停战/同盟/联姻/宗藩约束且领土直接接壤，每回合 -2 好感
            if (currentStatus == .neutral || currentStatus == .tradePact),
               bilateralStates[idx].vendettaLockTurns == 0,
               Self.areTerritoriesAdjacent(fA, fB, nodeOwners: nodeOwners) {
                bilateralStates[idx].relation = Self.clampRelation(bilateralStates[idx].relation - 2)
            }

            // 有期限条约（停战期、互不侵犯）自然倒计时与届满信誉 +3 奖励
            if (currentStatus == .truce || currentStatus == .nonAggression),
               bilateralStates[idx].remainingTurns > 0 {
                bilateralStates[idx].remainingTurns -= 1
                if bilateralStates[idx].remainingTurns == 0 {
                    let key = Self.pairKey(fA, fB)
                    bilateralStates[idx].status = activeTradePairKeys.contains(key) ? .tradePact : .neutral
                    mutateProfile(for: fA) {
                        $0.credibility = min(100, $0.credibility + Self.treatyFulfilledCredibilityBonus)
                    }
                    mutateProfile(for: fB) {
                        $0.credibility = min(100, $0.credibility + Self.treatyFulfilledCredibilityBonus)
                    }
                }
            }
        }

        // 4. 递减有期限的停战分期纳粮义务
        for idx in tributeObligations.indices.reversed() {
            if tributeObligations[idx].remainingTurns > 0 {
                tributeObligations[idx].remainingTurns -= 1
                if tributeObligations[idx].remainingTurns == 0 {
                    tributeObligations.remove(at: idx)
                }
            }
        }

        // 5. 和平状态下厌战度缓慢自然消退
        for fid in FactionId.allCases {
            let isAtWar = FactionId.allCases.contains { other in
                other != fid && status(between: fid, and: other) == .war
            }
            if !isAtWar {
                mutateProfile(for: fid) { prof in
                    prof.warExhaustion = max(0.0, prof.warExhaustion - 4.0)
                }
            }
        }

        // 6. 检查反霸权【合纵警觉】（>= 13 座城关）
        _ = recalculateAntiHegemonyAlert(nodeOwners: nodeOwners)
    }

    // MARK: - 私有量化计算与状态修改辅助

    private struct PeaceScoreBreakdown {
        let warExhaustionScore: Double
        let targetBattlefieldAdvantage: Double
        let rawOfferValue: Double
        let effectiveOfferValue: Double
        let thirdPartyThreatScore: Double
        let credibilityDiscount: Double
        let proposerCredibility: Int

        var netScore: Double {
            warExhaustionScore - targetBattlefieldAdvantage + effectiveOfferValue + thirdPartyThreatScore - credibilityDiscount
        }
    }

    private func computePeaceScoreBreakdown(for offer: PeaceOfferTerms) -> PeaceScoreBreakdown {
        let proposerProf = profile(for: offer.proposer)
        let targetProf = profile(for: offer.target)
        let evalTurns = max(1, min(20, offer.truceTurns))

        // 1. W_exhaust: 目标势力厌战度 [0, 45]
        let warKey = Self.pairKey(offer.proposer, offer.target)
        let warRecord = activeWars.first(where: { $0.pairKey == warKey })
        let warTurnFactor = Double(warRecord?.warTurnsElapsed ?? 0) * 2.2
        var personalityExhaustionBias = 0.0
        if let targetCfg = FactionConfig.config(for: offer.target) {
            switch targetCfg.aiPersonality {
            case .merchantPragmatic:
                personalityExhaustionBias = 4.0
            case .nomadOpportunist:
                let hasConcession = offer.goldIndemnity > 0 || offer.grainTributePerTurn > 0 || !offer.cededNodeIds.isEmpty
                personalityExhaustionBias = hasConcession ? 3.5 : 0.0
            case .ironShockElite:
                personalityExhaustionBias = -5.0
            case .imperialMethodical:
                // 炎龙帝国若核心王都被夺则死战不退
                if !targetProf.ownedNodeIds.contains(targetCfg.capitalNodeId) {
                    personalityExhaustionBias = -12.0
                }
            default:
                personalityExhaustionBias = 0.0
            }
        }
        let wExhaust = max(0.0, min(45.0, targetProf.warExhaustion + warTurnFactor + personalityExhaustionBias))

        // 2. W_adv: 目标势力对求方的战场优势 [-40, +40]
        var recordedAdv = 0.0
        if let rec = warRecord {
            recordedAdv = (rec.aggressor == offer.target) ? rec.aggressorBattleScore : -rec.aggressorBattleScore
        }
        let totalPower = max(200.0, targetProf.militaryStrengthScore + proposerProf.militaryStrengthScore)
        let powerRatioAdv = ((targetProf.militaryStrengthScore - proposerProf.militaryStrengthScore) / totalPower) * 30.0
        let nodeDiffAdv = Double(targetProf.ownedNodeIds.count - proposerProf.ownedNodeIds.count) * 1.8
        let wAdv = max(-40.0, min(40.0, recordedAdv + powerRatioAdv + nodeDiffAdv))

        // 3. V_offer: 筹码折算分（正数表示求方割让赔付，负数表示求方索取城下之盟）
        let goldScore = Double(offer.goldIndemnity) / 25.0
        let grainScore = Double(offer.grainTributePerTurn * evalTurns) / 18.0
        let proposerOwnedSet = Set(proposerProf.ownedNodeIds)
        let targetOwnedSet = Set(targetProf.ownedNodeIds)

        var cededCityScore = 0.0
        var seenNodes = Set<String>()
        for nodeId in offer.cededNodeIds where seenNodes.insert(nodeId).inserted {
            let val = strategicNodeValue(forNodeId: nodeId)
            if proposerOwnedSet.contains(nodeId) {
                cededCityScore += val
            } else if targetOwnedSet.contains(nodeId) {
                cededCityScore -= val
            }
        }
        let rawOffer = goldScore + grainScore + cededCityScore

        // 4. 低信誉折价与 C < 40 求和赔款要求溢价 +80%
        let proposerCred = proposerProf.credibility
        let credDiscount: Double
        if proposerCred >= 75 {
            credDiscount = 0.0
        } else if proposerCred >= Self.lowCredibilityThreshold {
            credDiscount = Double(75 - proposerCred) * 0.35
        } else {
            credDiscount = Double(75 - Self.lowCredibilityThreshold) * 0.35 + Double(Self.lowCredibilityThreshold - proposerCred) * 0.30
        }

        let effectiveOffer: Double
        if proposerCred < Self.lowCredibilityThreshold && rawOffer > 0.0 {
            // 求方信誉跌破 40 时，所付正向赔款效用按 1 / 1.80 折算（等价于对方要求的赔款总额溢价 +80%！）
            effectiveOffer = rawOffer / Self.lowCredibilityIndemnityMultiplier
        } else {
            effectiveOffer = rawOffer
        }

        // 5. T_third: 目标势力面临的第三方背后威胁 [0, 30]
        var thirdThreat = 0.0
        let ownerMap = buildCurrentOwnerMap()
        for other in FactionId.allCases where other != offer.target && other != offer.proposer {
            let otherProf = profile(for: other)
            guard !otherProf.isEliminated else { continue }
            let relState = bilateralState(between: offer.target, and: other)
            if relState.status == .war {
                thirdThreat += 14.0
            } else if relState.relation <= -30 && Self.areTerritoriesAdjacent(offer.target, other, nodeOwners: ownerMap) {
                thirdThreat += 6.0
            }
        }
        let tThird = max(0.0, min(30.0, thirdThreat))

        return PeaceScoreBreakdown(
            warExhaustionScore: wExhaust,
            targetBattlefieldAdvantage: wAdv,
            rawOfferValue: rawOffer,
            effectiveOfferValue: effectiveOffer,
            thirdPartyThreatScore: tThird,
            credibilityDiscount: credDiscount,
            proposerCredibility: proposerCred
        )
    }

    /// 生成严格非负且绝不超出求方实际金币、粮草、城池上限的反报价单（DESIGN.md 10.4）
    private func generateBoundedCounterOffer(
        for originalOffer: PeaceOfferTerms,
        scoreBreakdown: PeaceScoreBreakdown
    ) -> PeaceOfferTerms {
        let proposerProf = profile(for: originalOffer.proposer)
        let targetProf = profile(for: originalOffer.target)
        let truceTurns = Self.normalizeTruceTurns(originalOffer.truceTurns)

        let maxGoldCap = max(0, proposerProf.availableGold)
        let maxGrainPerTurnCap = max(0, proposerProf.availableGrain / max(1, truceTurns))

        // 计算在无筹码状态下的基准分：baseDisposition = W_exhaust - W_adv + T_third - P_cred
        let baseDisposition = scoreBreakdown.warExhaustionScore
            - scoreBreakdown.targetBattlefieldAdvantage
            + scoreBreakdown.thirdPartyThreatScore
            - scoreBreakdown.credibilityDiscount

        // 为使反报价再次评估时必满足 AcceptScore >= 0，目标有效筹码分需达到 max(0, -baseDisposition + 0.5)
        let neededEffectiveOffer = max(0.0, -baseDisposition + 0.5)
        let premiumFactor = (scoreBreakdown.proposerCredibility < Self.lowCredibilityThreshold)
            ? Self.lowCredibilityIndemnityMultiplier
            : 1.0
        var remainingRawValueNeeded = neededEffectiveOffer * premiumFactor

        // 若求方原本具备优势只是索取过度导致得分落在 [-20, 0)，对方反报无条件白和（全部非负 0）
        if remainingRawValueNeeded <= 1e-6 {
            return PeaceOfferTerms(
                proposer: originalOffer.proposer,
                target: originalOffer.target,
                goldIndemnity: 0,
                grainTributePerTurn: 0,
                cededNodeIds: [],
                truceTurns: truceTurns
            )
        }

        // 第 1 优先级：索取求方国库可负担的金币赔款
        let idealGold = Int(ceil(remainingRawValueNeeded * 25.0))
        var counterGold = max(0, min(maxGoldCap, idealGold))
        remainingRawValueNeeded -= Double(counterGold) / 25.0

        // 第 2 优先级：若金币不足，自动转索分期每回合纳粮（严禁超过求方实际粮草上限）
        var counterGrainPerTurn = 0
        if remainingRawValueNeeded > 1e-6 && maxGrainPerTurnCap > 0 {
            let neededTotalGrain = Int(ceil(remainingRawValueNeeded * 18.0))
            let idealPerTurn = Int(ceil(Double(neededTotalGrain) / Double(truceTurns)))
            counterGrainPerTurn = max(0, min(maxGrainPerTurnCap, idealPerTurn))
            remainingRawValueNeeded -= Double(counterGrainPerTurn * truceTurns) / 18.0
        }

        // 第 3 优先级：若金粮仍不足以填平差距，自动改索求方实际拥有的非王都边境城池
        var counterCededNodes: [String] = []
        if remainingRawValueNeeded > 1e-6 && proposerProf.ownedNodeIds.count > 1 {
            let proposerCapId = FactionConfig.config(for: originalOffer.proposer)?.capitalNodeId
            let targetOwnedSet = Set(targetProf.ownedNodeIds)

            let candidateNodes = proposerProf.ownedNodeIds.filter { $0 != proposerCapId }
            let sortedCandidates = candidateNodes.sorted { nodeA, nodeB in
                let adjA = (CampaignMapConfig.node(byId: nodeA)?.neighbors ?? []).contains { targetOwnedSet.contains($0) }
                let adjB = (CampaignMapConfig.node(byId: nodeB)?.neighbors ?? []).contains { targetOwnedSet.contains($0) }
                if adjA != adjB {
                    return adjA && !adjB
                }
                return strategicNodeValue(forNodeId: nodeA) < strategicNodeValue(forNodeId: nodeB)
            }

            for candidateId in sortedCandidates where remainingRawValueNeeded > 1e-6 {
                let cityVal = strategicNodeValue(forNodeId: candidateId)
                counterCededNodes.append(candidateId)
                remainingRawValueNeeded -= cityVal
            }

            // 若割让边境城池后筹码大幅溢出，依次回调现金与分期纳粮索赔，确保反报价既必过线又不趁火敲诈全部家底
            if remainingRawValueNeeded < -2.0 && counterGold > 0 {
                let reducibleGold = min(counterGold, Int(floor((-remainingRawValueNeeded - 1.0) * 25.0)))
                if reducibleGold > 0 {
                    counterGold -= reducibleGold
                    remainingRawValueNeeded += Double(reducibleGold) / 25.0
                }
            }
            if remainingRawValueNeeded < -2.0 && counterGrainPerTurn > 0 {
                let maxReduciblePerTurn = Int(floor(((-remainingRawValueNeeded - 1.0) * 18.0) / Double(truceTurns)))
                let reduciblePerTurn = min(counterGrainPerTurn, max(0, maxReduciblePerTurn))
                if reduciblePerTurn > 0 {
                    counterGrainPerTurn -= reduciblePerTurn
                    remainingRawValueNeeded += Double(reduciblePerTurn * truceTurns) / 18.0
                }
            }
        }

        // 终局硬性边界防御钳制：严禁任何负数或超出求方真实持有上限
        let proposerOwnedSet = Set(proposerProf.ownedNodeIds)
        let safeGold = max(0, min(maxGoldCap, counterGold))
        let safeGrain = max(0, min(maxGrainPerTurnCap, counterGrainPerTurn))
        let safeNodes = counterCededNodes.filter { proposerOwnedSet.contains($0) }

        return PeaceOfferTerms(
            proposer: originalOffer.proposer,
            target: originalOffer.target,
            goldIndemnity: safeGold,
            grainTributePerTurn: safeGrain,
            cededNodeIds: safeNodes,
            truceTurns: truceTurns
        )
    }

    private mutating func applyAcceptedPeaceTerms(_ offer: PeaceOfferTerms) {
        let truceTurns = Self.normalizeTruceTurns(offer.truceTurns)
        let key = Self.pairKey(offer.proposer, offer.target)
        activeWars.removeAll { $0.pairKey == key }

        mutateBilateralState(between: offer.proposer, and: offer.target) { st in
            st.status = .truce
            st.remainingTurns = truceTurns
            st.relation = Self.clampRelation(max(st.relation, -30) + 12)
        }

        // 登记停战期分期纳粮义务（支持双向：正数为 proposer 付给 target，负数为 target 付给 proposer）
        tributeObligations.removeAll {
            ($0.payer == offer.proposer && $0.recipient == offer.target) ||
            ($0.payer == offer.target && $0.recipient == offer.proposer)
        }
        if offer.grainTributePerTurn > 0 {
            tributeObligations.append(
                TributeObligationRecord(
                    payer: offer.proposer,
                    recipient: offer.target,
                    goldPerTurn: 0,
                    grainPerTurn: offer.grainTributePerTurn,
                    remainingTurns: truceTurns
                )
            )
        } else if offer.grainTributePerTurn < 0 {
            tributeObligations.append(
                TributeObligationRecord(
                    payer: offer.target,
                    recipient: offer.proposer,
                    goldPerTurn: 0,
                    grainPerTurn: abs(offer.grainTributePerTurn),
                    remainingTurns: truceTurns
                )
            )
        }

        // 更新内部快照中的金城划转（若由 CampaignTurnEngine 驱动，CampaignTurnEngine 会同步权威大地图城池与国库）
        if offer.goldIndemnity > 0 {
            let transfer = min(profile(for: offer.proposer).availableGold, offer.goldIndemnity)
            mutateProfile(for: offer.proposer) { $0.availableGold = max(0, $0.availableGold - transfer) }
            mutateProfile(for: offer.target) { $0.availableGold += transfer }
        } else if offer.goldIndemnity < 0 {
            let transfer = min(profile(for: offer.target).availableGold, abs(offer.goldIndemnity))
            mutateProfile(for: offer.target) { $0.availableGold = max(0, $0.availableGold - transfer) }
            mutateProfile(for: offer.proposer) { $0.availableGold += transfer }
        }

        if !offer.cededNodeIds.isEmpty {
            let proposerSet = Set(profile(for: offer.proposer).ownedNodeIds)
            let targetSet = Set(profile(for: offer.target).ownedNodeIds)
            for nodeId in Set(offer.cededNodeIds) {
                if proposerSet.contains(nodeId) {
                    mutateProfile(for: offer.proposer) { $0.ownedNodeIds.removeAll { $0 == nodeId } }
                    mutateProfile(for: offer.target) {
                        if !$0.ownedNodeIds.contains(nodeId) { $0.ownedNodeIds.append(nodeId) }
                    }
                } else if targetSet.contains(nodeId) {
                    mutateProfile(for: offer.target) { $0.ownedNodeIds.removeAll { $0 == nodeId } }
                    mutateProfile(for: offer.proposer) {
                        if !$0.ownedNodeIds.contains(nodeId) { $0.ownedNodeIds.append(nodeId) }
                    }
                }
            }
        }
    }

    /// 查找是否存在受侵略的我方同盟国 C（满足：我方同时与 target 及 C 缔有正式军事同盟 `.alliance`，且 target 主动侵略了 C）
    private func findDefendedAllyAgainstAggressor(
        defenderHelper: FactionId,
        aggressorTarget: FactionId
    ) -> FactionId? {
        guard status(between: defenderHelper, and: aggressorTarget) == .alliance else {
            return nil
        }
        for candidateAlly in FactionId.allCases where candidateAlly != defenderHelper && candidateAlly != aggressorTarget {
            guard status(between: defenderHelper, and: candidateAlly) == .alliance else {
                continue
            }
            guard status(between: aggressorTarget, and: candidateAlly) == .war else {
                continue
            }
            if warAggressor(between: aggressorTarget, and: candidateAlly) == aggressorTarget {
                return candidateAlly
            }
        }
        return nil
    }

    @discardableResult
    public mutating func adjustRelation(between factionA: FactionId, and factionB: FactionId, delta: Int) -> Int {
        guard factionA != factionB else { return 0 }
        var actualDelta = 0
        mutateBilateralState(between: factionA, and: factionB) { st in
            let before = st.relation
            if st.vendettaLockTurns > 0 {
                st.relation = GameConstants.diplomacyRelationMin
            } else {
                st.relation = Self.clampRelation(st.relation + delta)
            }
            actualDelta = st.relation - before
        }
        return actualDelta
    }

    private mutating func mutateBilateralState(
        between factionA: FactionId,
        and factionB: FactionId,
        _ body: (inout BilateralDiplomacyState) -> Void
    ) {
        guard factionA != factionB else { return }
        let ordered = Self.orderedPair(factionA, factionB)
        if let idx = bilateralStates.firstIndex(where: { $0.factionA == ordered.0 && $0.factionB == ordered.1 }) {
            body(&bilateralStates[idx])
        }
    }

    private mutating func mutateProfile(
        for factionId: FactionId,
        _ body: (inout FactionDiplomaticProfile) -> Void
    ) {
        if let idx = factionProfiles.firstIndex(where: { $0.factionId == factionId }) {
            body(&factionProfiles[idx])
        }
    }

    private func giftCountThisTurn(from sender: FactionId, to receiver: FactionId) -> Int {
        giftCountersThisTurn.first(where: { $0.sender == sender && $0.receiver == receiver })?.countThisTurn ?? 0
    }

    private mutating func incrementGiftCountThisTurn(from sender: FactionId, to receiver: FactionId) {
        if let idx = giftCountersThisTurn.firstIndex(where: { $0.sender == sender && $0.receiver == receiver }) {
            giftCountersThisTurn[idx].countThisTurn += 1
        } else {
            giftCountersThisTurn.append(GiftCounterRecord(sender: sender, receiver: receiver, countThisTurn: 1))
        }
    }

    private func buildCurrentOwnerMap() -> [String: FactionId] {
        var map: [String: FactionId] = [:]
        for prof in factionProfiles {
            for nid in prof.ownedNodeIds {
                map[nid] = prof.factionId
            }
        }
        if map.isEmpty {
            return CampaignSupplyService.initialNodeOwners()
        }
        return map
    }

    // MARK: - 纯静态工具函数

    public static func orderedPair(_ a: FactionId, _ b: FactionId) -> (FactionId, FactionId) {
        a.rawValue <= b.rawValue ? (a, b) : (b, a)
    }

    public static func pairKey(_ a: FactionId, _ b: FactionId) -> String {
        let ordered = orderedPair(a, b)
        return "\(ordered.0.rawValue)_\(ordered.1.rawValue)"
    }

    public static func envoyKey(from proposer: FactionId, to target: FactionId) -> String {
        "\(proposer.rawValue)->\(target.rawValue)"
    }

    public static func clampRelation(_ value: Int) -> Int {
        max(GameConstants.diplomacyRelationMin, min(GameConstants.diplomacyRelationMax, value))
    }

    /// 规范化停战回合档位（标准 5 / 8 / 12 回合）
    public static func normalizeTruceTurns(_ rawTurns: Int) -> Int {
        if rawTurns <= 6 {
            return 5
        } else if rawTurns <= 10 {
            return 8
        } else {
            return 12
        }
    }

    /// 按势力性格确定背盟后 2 场战斗的己方初始士气惩罚（炎龙/铁鹰 -16，血月 -5，其余 -10）
    public static func betrayalBattleMoralePenalty(for factionId: FactionId) -> Double {
        switch factionId {
        case .yanlong, .tieying:
            return -16.0
        case .xueyue:
            return -5.0
        default:
            return -10.0
        }
    }

    /// 判定两势力在 40 城关大地图上是否直接领土接壤
    public static func areTerritoriesAdjacent(
        _ factionA: FactionId,
        _ factionB: FactionId,
        nodeOwners: [String: FactionId]
    ) -> Bool {
        guard factionA != factionB else { return false }
        for node in CampaignMapConfig.allNodes where nodeOwners[node.id] == factionA {
            for neighborId in node.neighbors {
                if nodeOwners[neighborId] == factionB {
                    return true
                }
            }
        }
        return false
    }
}
