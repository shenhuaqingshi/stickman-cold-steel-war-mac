import Foundation

/// L1 战略大地图效用决策 AI（实现 `StrategicCampaignAIProtocol`，纯值类型 Sendable，零 UI 耦合）
/// 严格兑现 DESIGN.md 第 8.3 / 9.1 / 10.1 / 10.3 / 10.4 节：
/// 1. 7 大 AI 势力每回合按专属 `AiPersonality` 独立计算效用分（Utility Score），不围着玩家单向转，AI 之间真实攻城、结盟、通商与媾和；
/// 2. 两线作战规避：除狂热的血月祭司团（`zealotSwarm`）外，常规 AI 在已与强敌交战且遭第三国压境时，主动向次要战线派使割利求和；
/// 3. `>= 13` 城反霸权合纵制衡：当任一势力（玩家或强盛 AI）占领城关达到 `GameConstants.antiHegemonyNodeThreshold`（13 座）时，
///    相邻非同盟势力之间自动获得 `+25` 共同威胁好感修正，促成反扩张同盟并协同合击霸主；
/// 4. 内置 BFS 粮道跳数安全评估与量化媾和得分评估，严守停战/同盟信誉（双重同盟优先协防被侵略方）。

/// L1 战略行动结构化类别
public enum StrategicActionKind: String, Sendable, Codable, Hashable {
    case launchOffensive = "launch_offensive"           // 发兵攻打接壤敌城
    case proposePeaceSecondary = "propose_peace"        // 两线规避向次要战线求和
    case formAntiHegemonyPact = "anti_hegemony_pact"    // >=13 城反霸权合纵结盟
    case signTradeOrNonAggression = "sign_diplomacy"    // 缔结丝路通商或互不侵犯
    case fortifyAndRecruit = "fortify_recruit"          // 筑垒征兵与补充粮仓
    case nightRaidOrPlunder = "night_raid_plunder"      // 游牧劫掠或血月夜袭
}

/// L1 战略回合单条结构化决策结果
public struct StrategicTurnDecision: Sendable, Codable, Equatable {
    public let actorFaction: FactionId
    public let kind: StrategicActionKind
    public let targetFaction: FactionId?
    public let fromNodeId: String?
    public let targetNodeId: String?
    public let peaceOffer: PeaceOfferTerms?
    public let utilityScore: Double
    public let summaryText: String

    public init(
        actorFaction: FactionId,
        kind: StrategicActionKind,
        targetFaction: FactionId? = nil,
        fromNodeId: String? = nil,
        targetNodeId: String? = nil,
        peaceOffer: PeaceOfferTerms? = nil,
        utilityScore: Double,
        summaryText: String
    ) {
        self.actorFaction = actorFaction
        self.kind = kind
        self.targetFaction = targetFaction
        self.fromNodeId = fromNodeId
        self.targetNodeId = targetNodeId
        self.peaceOffer = peaceOffer
        self.utilityScore = utilityScore
        self.summaryText = summaryText
    }
}

/// 供 L1 战略 AI 评估的大地图态势轻量快照（默认直接从 40 节点静态配置初始化）
public struct StrategicCampaignWorldState: Sendable, Codable, Equatable {
    public var turnNumber: Int
    public var playerFaction: FactionId
    public var nodeOwners: [String: FactionId]
    public var nodeGarrisonStrength: [String: Int]
    public var factionTreasuryGold: [FactionId: Int]
    public var factionTreasuryGrain: [FactionId: Int]
    public var factionCredibility: [FactionId: Int]
    public var factionWarExhaustion: [FactionId: Double]
    public var diplomacyMap: [String: BilateralDiplomacyState]

    public init(
        turnNumber: Int = 1,
        playerFaction: FactionId = .yanlong,
        nodeOwners: [String: FactionId]? = nil,
        nodeGarrisonStrength: [String: Int]? = nil,
        factionTreasuryGold: [FactionId: Int]? = nil,
        factionTreasuryGrain: [FactionId: Int]? = nil,
        factionCredibility: [FactionId: Int]? = nil,
        factionWarExhaustion: [FactionId: Double]? = nil,
        diplomacyMap: [String: BilateralDiplomacyState]? = nil
    ) {
        self.turnNumber = turnNumber
        self.playerFaction = playerFaction

        if let customOwners = nodeOwners {
            self.nodeOwners = customOwners
        } else {
            var owners: [String: FactionId] = [:]
            for node in CampaignMapConfig.allNodes {
                owners[node.id] = node.initialOwner
            }
            self.nodeOwners = owners
        }

        if let customGarrisons = nodeGarrisonStrength {
            self.nodeGarrisonStrength = customGarrisons
        } else {
            var garrisons: [String: Int] = [:]
            for node in CampaignMapConfig.allNodes {
                let basePower = node.nodeType == .capitalCitadel ? 180 : (85 + node.defenseLevel * 18)
                garrisons[node.id] = basePower
            }
            self.nodeGarrisonStrength = garrisons
        }

        var goldDict: [FactionId: Int] = [:]
        var grainDict: [FactionId: Int] = [:]
        var credDict: [FactionId: Int] = [:]
        var exhaustDict: [FactionId: Double] = [:]
        for cfg in FactionConfig.allFactions {
            goldDict[cfg.id] = factionTreasuryGold?[cfg.id] ?? (cfg.id == .shamo ? 920 : 650)
            grainDict[cfg.id] = factionTreasuryGrain?[cfg.id] ?? 1200
            credDict[cfg.id] = factionCredibility?[cfg.id] ?? cfg.startingCredibility
            exhaustDict[cfg.id] = factionWarExhaustion?[cfg.id] ?? 0.0
        }
        self.factionTreasuryGold = goldDict
        self.factionTreasuryGrain = grainDict
        self.factionCredibility = credDict
        self.factionWarExhaustion = exhaustDict

        if let customDip = diplomacyMap {
            self.diplomacyMap = customDip
        } else {
            var dip: [String: BilateralDiplomacyState] = [:]
            let allIds = FactionId.allCases
            for i in 0..<allIds.count {
                for j in (i + 1)..<allIds.count {
                    let fA = allIds[i]
                    let fB = allIds[j]
                    let rel = FactionConfig.initialRelation(between: fA, and: fB)
                    let initialStatus: DiplomaticStatus = (rel <= -15) ? .war : .neutral
                    let key = Self.pairKey(fA, fB)
                    dip[key] = BilateralDiplomacyState(
                        factionA: fA,
                        factionB: fB,
                        relation: rel,
                        status: initialStatus
                    )
                }
            }
            self.diplomacyMap = dip
        }
    }

    public static func pairKey(_ a: FactionId, _ b: FactionId) -> String {
        a.rawValue <= b.rawValue ? "\(a.rawValue)_\(b.rawValue)" : "\(b.rawValue)_\(a.rawValue)"
    }

    public func diplomaticState(between a: FactionId, and b: FactionId) -> BilateralDiplomacyState {
        let key = Self.pairKey(a, b)
        if let existing = diplomacyMap[key] {
            return existing
        }
        return BilateralDiplomacyState(
            factionA: a,
            factionB: b,
            relation: FactionConfig.initialRelation(between: a, and: b),
            status: .neutral
        )
    }

    public func controlledNodeCount(for faction: FactionId) -> Int {
        var count = 0
        for (_, owner) in nodeOwners where owner == faction {
            count += 1
        }
        return count
    }

    public func totalMilitaryStrength(for faction: FactionId) -> Int {
        var sum = 0
        for (nodeId, owner) in nodeOwners where owner == faction {
            sum += nodeGarrisonStrength[nodeId] ?? 100
        }
        return sum
    }

    /// 检索当前占领城关数 >= 13 座的霸权势力（若存在则触发全图合纵警觉 +25 好感修正）
    public func detectHegemonFaction() -> FactionId? {
        var bestFaction: FactionId?
        var bestCount = GameConstants.antiHegemonyNodeThreshold - 1
        for fid in FactionId.allCases {
            let c = controlledNodeCount(for: fid)
            if c > bestCount {
                bestCount = c
                bestFaction = fid
            }
        }
        return bestFaction
    }
}

public struct StrategicCampaignAI: StrategicCampaignAIProtocol, Sendable, Equatable {
    public var worldState: StrategicCampaignWorldState

    public init(worldState: StrategicCampaignWorldState = StrategicCampaignWorldState()) {
        self.worldState = worldState
    }

    // MARK: - 一、StrategicCampaignAIProtocol 标准协议入口

    public func evaluateTurnActions(for factionId: FactionId, personality: AiPersonality) -> [String] {
        let decisions = evaluateStructuredDecisions(for: factionId, personality: personality, in: worldState)
        return decisions.map(\.summaryText)
    }

    // MARK: - 二、完整结构化效用评估核心（独立攻伐 + 两线规避 + >=13 城反霸权合纵）

    public func evaluateStructuredDecisions(
        for factionId: FactionId,
        personality: AiPersonality,
        in state: StrategicCampaignWorldState
    ) -> [StrategicTurnDecision] {
        let ownedNodes = CampaignMapConfig.allNodes.filter { state.nodeOwners[$0.id] == factionId }
        guard !ownedNodes.isEmpty else { return [] }

        let factionName = FactionConfig.config(for: factionId)?.name ?? factionId.rawValue
        let myStrength = max(1, state.totalMilitaryStrength(for: factionId))
        let myCredibility = state.factionCredibility[factionId] ?? GameConstants.credibilityDefaultInit
        let myGold = state.factionTreasuryGold[factionId] ?? 500
        let hegemon = state.detectHegemonFaction()

        var decisions: [StrategicTurnDecision] = []

        // 1. 梳理接壤邻国与当前交战战线数量
        var borderFactions = Set<FactionId>()
        for node in ownedNodes {
            for nbId in node.neighbors {
                if let nbOwner = state.nodeOwners[nbId], nbOwner != factionId {
                    borderFactions.insert(nbOwner)
                }
            }
        }

        var activeWarEnemies: [FactionId] = []
        for other in FactionId.allCases where other != factionId {
            let dip = state.diplomaticState(between: factionId, and: other)
            if dip.status == .war {
                activeWarEnemies.append(other)
            }
        }

        // 2. 【反霸权合纵制衡】：若存在其它势力控城 >= 13 座，优先与其余受威胁邻国获 +25 共同威胁修正缔结同盟/互不侵犯
        if let hegemonId = hegemon, hegemonId != factionId {
            let hegemonName = FactionConfig.config(for: hegemonId)?.name ?? hegemonId.rawValue
            let hegemonCities = state.controlledNodeCount(for: hegemonId)

            for neighbor in borderFactions where neighbor != hegemonId {
                let dip = state.diplomaticState(between: factionId, and: neighbor)
                let effectiveRelation = min(
                    GameConstants.diplomacyRelationMax,
                    dip.relation + 25 // DESIGN.md 8.3 合纵警觉 +25 共同威胁好感修正
                )
                let neighborName = FactionConfig.config(for: neighbor)?.name ?? neighbor.rawValue

                if dip.status == .war && dip.vendettaLockTurns == 0 {
                    let offer = buildAffordablePeaceOffer(
                        proposer: factionId,
                        target: neighbor,
                        proposerGold: myGold,
                        ownedNodes: ownedNodes,
                        state: state
                    )
                    decisions.append(
                        StrategicTurnDecision(
                            actorFaction: factionId,
                            kind: .formAntiHegemonyPact,
                            targetFaction: neighbor,
                            peaceOffer: offer,
                            utilityScore: 96.0,
                            summaryText: "[合纵止戈] \(factionName)鉴于\(hegemonName)坐拥 \(hegemonCities) 城触发合纵警觉(+25好感)，主动与\(neighborName)停火联手抗霸"
                        )
                    )
                } else if dip.status != .alliance
                    && effectiveRelation >= GameConstants.nonAggressionMinRelation
                    && myCredibility >= GameConstants.nonAggressionMinCredibility {
                    let pactLabel = (effectiveRelation >= GameConstants.allianceMinRelation && myCredibility >= GameConstants.allianceMinCredibility)
                        ? "军事攻守同盟"
                        : "反霸互不侵犯盟约"
                    decisions.append(
                        StrategicTurnDecision(
                            actorFaction: factionId,
                            kind: .formAntiHegemonyPact,
                            targetFaction: neighbor,
                            utilityScore: 92.0,
                            summaryText: "[反霸权合纵] \(factionName)与\(neighborName)因\(hegemonName)扩张至 \(hegemonCities) 城(>=13)缔结【\(pactLabel)】(共同威胁修正 +25)"
                        )
                    )
                    break
                }
            }
        }

        // 3. 【两线作战规避】：除狂热的血月祭司团（zealotSwarm）外，同时与 >=2 国交战时向次要战线割利求和
        if personality != .zealotSwarm && activeWarEnemies.count >= 2 {
            // 按威胁与接壤核心度排序：保留头号主敌（优先保留霸权国或接壤最深之敌），向次要敌人议和
            let sortedEnemies = activeWarEnemies.sorted { a, b in
                let aIsHegemon = (a == hegemon) ? 1 : 0
                let bIsHegemon = (b == hegemon) ? 1 : 0
                if aIsHegemon != bIsHegemon { return aIsHegemon > bIsHegemon }
                return state.totalMilitaryStrength(for: a) > state.totalMilitaryStrength(for: b)
            }
            if let secondaryEnemy = sortedEnemies.last {
                let dip = state.diplomaticState(between: factionId, and: secondaryEnemy)
                if dip.vendettaLockTurns == 0 {
                    let offer = buildAffordablePeaceOffer(
                        proposer: factionId,
                        target: secondaryEnemy,
                        proposerGold: myGold,
                        ownedNodes: ownedNodes,
                        state: state
                    )
                    let secName = FactionConfig.config(for: secondaryEnemy)?.name ?? secondaryEnemy.rawValue
                    decisions.append(
                        StrategicTurnDecision(
                            actorFaction: factionId,
                            kind: .proposePeaceSecondary,
                            targetFaction: secondaryEnemy,
                            peaceOffer: offer,
                            utilityScore: 89.0,
                            summaryText: "[两线规避] \(factionName)避免双线受敌，向次要战线\(secName)遣使求和（赔款 \(offer.goldIndemnity) 金 / 纳粮 \(offer.grainTributePerTurn) / 停战 \(offer.truceTurns) 回合）以集中兵力决战主线"
                        )
                    )
                }
            }
        }

        // 4. 外交务实经营（沙漠商盟优先签丝路通商协定，铁鹰王国偏爱防御结盟）
        if personality == .merchantPragmatic || personality == .fortressCounter {
            for other in borderFactions {
                let dip = state.diplomaticState(between: factionId, and: other)
                if dip.status == .neutral && dip.relation >= GameConstants.nonAggressionMinRelation {
                    let otherName = FactionConfig.config(for: other)?.name ?? other.rawValue
                    let treatyName = (personality == .merchantPragmatic && dip.relation >= GameConstants.tradePactMinRelation)
                        ? "丝路通商协定"
                        : "互不侵犯条约"
                    decisions.append(
                        StrategicTurnDecision(
                            actorFaction: factionId,
                            kind: .signTradeOrNonAggression,
                            targetFaction: other,
                            utilityScore: 68.0,
                            summaryText: "[外交纵横] \(factionName)与邻邦\(otherName)签署【\(treatyName)】，稳固侧翼粮道与岁入"
                        )
                    )
                    break
                }
            }
        }

        // 5. 扫描全部接壤敌方/可宣战节点，按性格与粮道连通跳数计算进攻效用分（绝对不限于玩家节点，支撑 AI 互相攻伐！）
        var bestAttackDecision: StrategicTurnDecision?
        let alliedSet = currentAllies(of: factionId, in: state)

        for srcNode in ownedNodes {
            let srcGarrison = state.nodeGarrisonStrength[srcNode.id] ?? 100
            for targetId in srcNode.neighbors {
                guard let targetOwner = state.nodeOwners[targetId],
                      targetOwner != factionId,
                      let targetCfg = CampaignMapConfig.node(byId: targetId) else { continue }

                let dip = state.diplomaticState(between: factionId, and: targetOwner)
                // 守信势力绝不轻易撕毁同盟/停战期背盟（除非是狂热或低信誉机会主义且占压倒优势）
                let hasProtectedTreaty = (dip.status == .alliance || dip.status == .truce || dip.status == .nonAggression || dip.status == .vassal)
                if hasProtectedTreaty {
                    if myCredibility >= 75 || personality == .imperialMethodical || personality == .fortressCounter {
                        continue
                    }
                }

                // 若当前已两线交战且并非对已开战敌国，非狂热 AI 不再开辟第三战线
                if activeWarEnemies.count >= 2 && dip.status != .war && personality != .zealotSwarm {
                    continue
                }

                let targetGarrison = max(30, state.nodeGarrisonStrength[targetId] ?? 90)
                let localForceRatio = Double(srcGarrison) / Double(targetGarrison)
                let globalForceRatio = Double(myStrength) / Double(max(1, state.totalMilitaryStrength(for: targetOwner)))

                // 模拟占领该节点后的 BFS 补给跳数，规避孤军断粮死地
                var simulatedOwners = state.nodeOwners
                simulatedOwners[targetId] = factionId
                let supplyAfterCapture = Self.evaluateSupplyHops(
                    forNodeId: targetId,
                    factionId: factionId,
                    nodeOwners: simulatedOwners,
                    alliedFactions: alliedSet
                )
                if case .severed = supplyAfterCapture, personality != .nomadOpportunist && personality != .zealotSwarm {
                    continue
                }

                var score = 32.0 * localForceRatio + 14.0 * globalForceRatio
                score += Double(targetCfg.totalYield) * 0.08
                score -= Double(targetCfg.defenseLevel) * 4.2

                if dip.status == .war {
                    score += 18.0
                }
                if targetOwner == hegemon {
                    // 反霸权集火加成：全图优先遏制 >=13 城霸主
                    score += 26.0
                }

                // 八大势力性格专属偏好权重（体现苍狼劫掠仓城、铁鹰据守雄关、雾林护林设伏、血月夜袭扩张）
                switch personality {
                case .imperialMethodical:
                    if targetCfg.nodeType == .capitalCitadel || targetCfg.nodeType == .fortressPass { score += 12.0 }
                case .nomadOpportunist:
                    if targetCfg.nodeType == .granaryTown || targetCfg.grainYield >= 120 { score += 18.0 }
                    if targetCfg.defenseLevel >= 5 { score -= 12.0 } // 苍狼无投石车忌惮 5 级坚城
                case .fortressCounter:
                    if targetCfg.terrain == .highGround || targetCfg.nodeType == .fortressPass { score += 14.0 }
                    if localForceRatio < 1.15 { score -= 15.0 }
                case .merchantPragmatic:
                    score += Double(targetCfg.goldYield) * 0.12
                    if localForceRatio < 1.20 { score -= 12.0 }
                case .honorBerserkBear:
                    score += 10.0 // 熊族敢打硬仗
                    if targetCfg.terrain == .snowfield { score += 12.0 }
                case .guerrillaTrapper:
                    if targetCfg.terrain == .denseForest || targetCfg.terrain == .riverFord { score += 16.0 }
                case .ironShockElite:
                    if targetCfg.terrain == .plain { score += 15.0 }
                case .zealotSwarm:
                    score += 16.0
                }

                if score > (bestAttackDecision?.utilityScore ?? 48.0) {
                    let targetOwnerName = FactionConfig.config(for: targetOwner)?.name ?? targetOwner.rawValue
                    let actionKind: StrategicActionKind = (personality == .nomadOpportunist || personality == .zealotSwarm)
                        ? .nightRaidOrPlunder
                        : .launchOffensive
                    let tacticTag = personality == .zealotSwarm ? "夜袭猛攻" : (personality == .nomadOpportunist ? "铁骑劫掠" : "大军进讨")
                    bestAttackDecision = StrategicTurnDecision(
                        actorFaction: factionId,
                        kind: actionKind,
                        targetFaction: targetOwner,
                        fromNodeId: srcNode.id,
                        targetNodeId: targetId,
                        utilityScore: score,
                        summaryText: "[\(tacticTag)] \(factionName)自【\(srcNode.name)】发兵进击\(targetOwnerName)所属【\(targetCfg.name)】(效用分 \(String(format: "%.1f", score)))"
                    )
                }
            }
        }

        if let attack = bestAttackDecision {
            decisions.append(attack)
        } else if let anchorNode = ownedNodes.max(by: { $0.defenseLevel < $1.defenseLevel }) {
            decisions.append(
                StrategicTurnDecision(
                    actorFaction: factionId,
                    kind: .fortifyAndRecruit,
                    fromNodeId: anchorNode.id,
                    targetNodeId: anchorNode.id,
                    utilityScore: 52.0,
                    summaryText: "[整军筑垒] \(factionName)依托【\(anchorNode.name)】深沟高垒、征募精锐并囤积军粮"
                )
            )
        }

        return decisions.sorted { $0.utilityScore > $1.utilityScore }
    }

    // MARK: - 三、大地图 BFS 粮道跳数连通核验与量化媾和估值纯函数

    /// 计算节点经本方或军事同盟节点通往最近 `isSupplyDepot == true` 仓城的 BFS 最短跳数状态
    public static func evaluateSupplyHops(
        forNodeId nodeId: String,
        factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId>,
        priorIsolatedTurns: Int = 0
    ) -> SupplyLineStatus {
        guard let startCfg = CampaignMapConfig.node(byId: nodeId) else {
            return .severed(isolatedTurns: priorIsolatedTurns + 1)
        }
        guard let startOwner = nodeOwners[nodeId],
              startOwner == factionId || alliedFactions.contains(startOwner) else {
            return .severed(isolatedTurns: priorIsolatedTurns + 1)
        }
        if startOwner == factionId && startCfg.isSupplyDepot {
            return .fullSupply(hops: 0)
        }

        var visited: Set<String> = [nodeId]
        var queue: [(id: String, hops: Int)] = [(nodeId, 0)]
        var head = 0

        while head < queue.count {
            let current = queue[head]
            head += 1
            guard let cfg = CampaignMapConfig.node(byId: current.id) else { continue }

            for nbId in cfg.neighbors where !visited.contains(nbId) {
                guard let nbOwner = nodeOwners[nbId],
                      nbOwner == factionId || alliedFactions.contains(nbOwner),
                      let nbCfg = CampaignMapConfig.node(byId: nbId) else { continue }

                let nextHops = current.hops + 1
                if nbOwner == factionId && nbCfg.isSupplyDepot {
                    if nextHops <= GameConstants.supplyFullEfficiencyHops {
                        return .fullSupply(hops: nextHops)
                    } else if nextHops == 3 {
                        return .extendedMarch(hops: nextHops)
                    } else {
                        return .overextended(hops: nextHops)
                    }
                }
                visited.insert(nbId)
                queue.append((nbId, nextHops))
            }
        }
        return .severed(isolatedTurns: priorIsolatedTurns + 1)
    }

    /// 严格按 DESIGN.md 8.3 量化公式评估求和方案净得分 AcceptScore
    public static func computePeaceAcceptScore(
        offer: PeaceOfferTerms,
        in state: StrategicCampaignWorldState
    ) -> Double {
        let dip = state.diplomaticState(between: offer.proposer, and: offer.target)
        if dip.vendettaLockTurns > 0 {
            return -100.0 // 10 回合血海世仇期间拒绝一切停火谈判
        }

        let targetExhaust = min(45.0, max(0.0, state.factionWarExhaustion[offer.target] ?? 12.0))
        let targetPower = Double(max(1, state.totalMilitaryStrength(for: offer.target)))
        let proposerPower = Double(max(1, state.totalMilitaryStrength(for: offer.proposer)))
        let rawAdvantage = ((targetPower - proposerPower) / max(targetPower, proposerPower)) * 40.0
        let targetAdvantage = min(40.0, max(-40.0, rawAdvantage))

        var cededValue = 0.0
        for nodeId in offer.cededNodeIds {
            if let cfg = CampaignMapConfig.node(byId: nodeId) {
                let nodeVal = cfg.nodeType == .capitalCitadel ? 60.0 : min(60.0, max(25.0, Double(cfg.totalYield) * 0.12))
                cededValue += nodeVal
            } else {
                cededValue += 30.0
            }
        }
        let offerValue = Double(offer.goldIndemnity) / 25.0
            + Double(offer.grainTributePerTurn * offer.truceTurns) / 18.0
            + cededValue

        // 第三方背后威胁分 T_third (0 ~ 30)
        var otherWarsCount = 0
        for other in FactionId.allCases where other != offer.target && other != offer.proposer {
            if state.diplomaticState(between: offer.target, and: other).status == .war {
                otherWarsCount += 1
            }
        }
        let hegemonBonus = (state.detectHegemonFaction() != nil && state.detectHegemonFaction() != offer.target && state.detectHegemonFaction() != offer.proposer) ? 12.0 : 0.0
        let thirdPartyThreat = min(30.0, Double(otherWarsCount) * 14.0 + hegemonBonus)

        // 求方低信誉怀疑折价 P_cred
        let proposerCred = state.factionCredibility[offer.proposer] ?? GameConstants.credibilityDefaultInit
        let credPenalty = proposerCred < 80 ? Double(80 - proposerCred) * 0.45 : 0.0

        return targetExhaust - targetAdvantage + offerValue + thirdPartyThreat - credPenalty
    }

    // MARK: - 内部辅助构造

    private func currentAllies(of factionId: FactionId, in state: StrategicCampaignWorldState) -> Set<FactionId> {
        var allies = Set<FactionId>()
        for other in FactionId.allCases where other != factionId {
            if state.diplomaticState(between: factionId, and: other).status == .alliance {
                allies.insert(other)
            }
        }
        return allies
    }

    /// 生成绝不超出求方资产上限的合法停火报价单（符合 DESIGN.md 10.4 防非法报价铁律）
    private func buildAffordablePeaceOffer(
        proposer: FactionId,
        target: FactionId,
        proposerGold: Int,
        ownedNodes: [CampaignNodeConfig],
        state: StrategicCampaignWorldState
    ) -> PeaceOfferTerms {
        let maxAffordableGold = max(0, min(proposerGold, 250))
        let proposerGrain = state.factionTreasuryGrain[proposer] ?? 400
        let perTurnGrain = max(0, min(35, proposerGrain / 16))
        var offer = PeaceOfferTerms(
            proposer: proposer,
            target: target,
            goldIndemnity: maxAffordableGold,
            grainTributePerTurn: perTurnGrain,
            cededNodeIds: [],
            truceTurns: 8
        )
        // 若净得分仍略低于 0 且己方拥有非王都边境城关，可割让 1 座次要前哨换取停火
        if Self.computePeaceAcceptScore(offer: offer, in: state) < 0.0, ownedNodes.count > 2 {
            if let borderOutpost = ownedNodes.first(where: { node in
                node.nodeType != .capitalCitadel && node.neighbors.contains(where: { state.nodeOwners[$0] == target })
            }) {
                offer = PeaceOfferTerms(
                    proposer: proposer,
                    target: target,
                    goldIndemnity: maxAffordableGold / 2,
                    grainTributePerTurn: perTurnGrain,
                    cededNodeIds: [borderOutpost.id],
                    truceTurns: 8
                )
            }
        }
        return offer
    }
}
