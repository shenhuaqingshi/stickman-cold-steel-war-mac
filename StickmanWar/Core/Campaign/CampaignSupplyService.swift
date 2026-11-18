import Foundation

/// 补给线跳数与断粮综合修正系数（严格对齐 DESIGN.md 6、7.3 与 10.1 节数值法则）
public struct SupplyPenaltyModifiers: Sendable, Codable, Equatable {
    /// 大地图每回合维持耗粮倍率（近境 1.0，d=3 标准 1.25 / 苍狼 1.1625，d>=4 标准 1.50 / 苍狼 1.325）
    public let upkeepGrainMultiplier: Double
    /// 进入实时大战场时的初始携行军粮上限倍率（标准基准 1200；d=3 标准 0.85 / 苍狼 0.9025）
    public let battleCarryGrainMultiplier: Double
    /// 大地图每回合非战斗饥疲逃亡减员比例（断粮第 1 回合 0%，第 2 回合起固定 8%）
    public let nonCombatAttritionRate: Double
    /// 大地图主力行军力倍率（断粮第 2 回合起 -25%，即 0.75）
    public let campaignMovementMultiplier: Double
    /// 进入战场时全军初始士气封顶上限（正常 100.0，断粮第 2 回合起锁死 65.0）
    public let battleInitialMoraleCap: Double
    /// 是否处于断粮第 1 回合红色干粮预警态
    public let isEmergencyRationWarning: Bool
    /// 是否已陷入断粮第 2+ 回合【饥疲】逃亡减员态
    public let isStarvingExhausted: Bool

    public init(
        upkeepGrainMultiplier: Double,
        battleCarryGrainMultiplier: Double,
        nonCombatAttritionRate: Double,
        campaignMovementMultiplier: Double,
        battleInitialMoraleCap: Double,
        isEmergencyRationWarning: Bool,
        isStarvingExhausted: Bool
    ) {
        self.upkeepGrainMultiplier = upkeepGrainMultiplier
        self.battleCarryGrainMultiplier = battleCarryGrainMultiplier
        self.nonCombatAttritionRate = nonCombatAttritionRate
        self.campaignMovementMultiplier = campaignMovementMultiplier
        self.battleInitialMoraleCap = battleInitialMoraleCap
        self.isEmergencyRationWarning = isEmergencyRationWarning
        self.isStarvingExhausted = isStarvingExhausted
    }
}

/// 单座城关补给线完整诊断报告（同时供回合结算与 SwiftUI 大地图粮道高亮层消费）
public struct CampaignSupplyRouteEvaluation: Sendable, Equatable {
    public let nodeId: String
    public let factionId: FactionId
    public let status: SupplyLineStatus
    /// 自目标节点至最近本方补给仓城的最短路径节点序列（`first == nodeId`, `last == depotId`；断绝时为空数组）
    public let shortestPathNodeIds: [String]
    /// 命中的最近本方仓城节点 ID（断绝时为 nil）
    public let nearestDepotNodeId: String?
    /// 结合势力远征特性的最终惩罚/维持系数
    public let modifiers: SupplyPenaltyModifiers

    public init(
        nodeId: String,
        factionId: FactionId,
        status: SupplyLineStatus,
        shortestPathNodeIds: [String],
        nearestDepotNodeId: String?,
        modifiers: SupplyPenaltyModifiers
    ) {
        self.nodeId = nodeId
        self.factionId = factionId
        self.status = status
        self.shortestPathNodeIds = shortestPathNodeIds
        self.nearestDepotNodeId = nearestDepotNodeId
        self.modifiers = modifiers
    }
}

/// 战役 40 城关、78 条对称双向道路 BFS 补给线与远征损耗计算引擎
/// 纯值类型无副作用服务，遵循 Swift 6 `Sendable`、`Codable`、`Equatable`，零 UI 框架耦合。
public struct CampaignSupplyService: CampaignSupplyServiceProtocol, Sendable, Codable, Equatable {

    // MARK: - 静态设计常数（对应 DESIGN.md 6、7.3、10.1）

    /// 苍狼汗国远征补给跳数惩罚减免比例（-35%）
    public static let canglangExpeditionPenaltyReduction: Double = 0.35
    /// 长途远征（d == 3）基础维持耗粮附加比例（+25%）
    public static let extendedMarchBaseUpkeepSurcharge: Double = 0.25
    /// 长途远征（d == 3）战前携行粮草上限扣减比例（-15%）
    public static let extendedMarchBaseCarryPenalty: Double = 0.15
    /// 孤军悬远（d >= 4）基础维持耗粮附加比例（+50%）
    public static let overextendedBaseUpkeepSurcharge: Double = 0.50
    /// 孤军悬远（d >= 4）战前携行粮草上限扣减比例（-25%）
    public static let overextendedBaseCarryPenalty: Double = 0.25
    /// 粮道断绝第 2 回合起每回合非战斗逃亡减员率（8%）
    public static let severedStarvationAttritionRate: Double = 0.08
    /// 粮道断绝第 2 回合起大地图行军力折损率（-25%）
    public static let severedMovementPenalty: Double = 0.25
    /// 粮道断绝第 2 回合起进入战斗初始士气上限（65.0）
    public static let severedBattleMoraleCap: Double = 65.0

    public init() {}

    // MARK: - 初始归属快照构建

    /// 生成标准开局 40 座城关的初始势力归属字典
    public static func initialNodeOwners() -> [String: FactionId] {
        Dictionary(uniqueKeysWithValues: CampaignMapConfig.allNodes.map { ($0.id, $0.initialOwner) })
    }

    // MARK: - 苍狼汗国远征惩罚减免系数

    /// 计算指定势力的远征补给惩罚保留系数（苍狼汗国享 -35% 远征惩罚减免，即保留 0.65；其余势力为 1.0）
    public func expeditionPenaltyRetentionFactor(for factionId: FactionId) -> Double {
        if factionId == .canglang {
            return 1.0 - Self.canglangExpeditionPenaltyReduction
        }
        return 1.0
    }

    /// 计算经苍狼汗国 -35% 远征减免修正后的实际惩罚幅度（例如 +25% 耗粮惩罚折算为 +16.25%）
    public func canglangAdjustedExpeditionPenalty(basePenalty: Double, factionId: FactionId) -> Double {
        max(0.0, basePenalty) * expeditionPenaltyRetentionFactor(for: factionId)
    }

    /// 提取 `SupplyLineStatus` 对应的连通跳数（若处于 `.severed` 断粮态则返回 `nil`）
    public static func reachableHops(from status: SupplyLineStatus) -> Int? {
        switch status {
        case .fullSupply(let hops), .extendedMarch(let hops), .overextended(let hops):
            return hops
        case .severed:
            return nil
        }
    }

    // MARK: - BFS 最短粮道路径检索（供大地图高亮绘制补给干道与跳数判定）

    /// 计算目标节点仅经由本方或正式军事同盟国（`.alliance`）控制节点通往本方任一 `isSupplyDepot == true` 仓城的 BFS 最短路径。
    /// - Returns: `[nodeId, ..., depotNodeId]`，跳数 `d = path.count - 1`；若起点非本方/盟友控制或归路被阻断，返回 `[]`。
    public func shortestSupplyPath(
        forNodeId nodeId: String,
        factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId> = []
    ) -> [String] {
        guard let startConfig = CampaignMapConfig.node(byId: nodeId),
              let startOwner = nodeOwners[nodeId],
              startOwner == factionId || alliedFactions.contains(startOwner) else {
            return []
        }

        // 起点本身即为本方直接控制的补给仓城（d == 0）
        if startOwner == factionId && startConfig.isSupplyDepot {
            return [nodeId]
        }

        // 双指针游标队列实现 O(V + E) 零移位开销 BFS（V = 40, E = 78）
        var queue: [String] = []
        queue.reserveCapacity(GameConstants.campaignNodeCount)
        queue.append(nodeId)

        var visited: Set<String> = [nodeId]
        var parentByNode: [String: String] = [:]
        var head = 0

        while head < queue.count {
            let currentId = queue[head]
            head += 1

            guard let currentConfig = CampaignMapConfig.node(byId: currentId) else {
                continue
            }

            // 同跳数等距平局下优先走本方直辖领土（其次才是盟友借道领土），并优先连通王都级大仓城，增强补给干道抗截断稳健性
            let prioritizedNeighbors = currentConfig.neighbors.sorted { lhs, rhs in
                let lhsOwn = (nodeOwners[lhs] == factionId)
                let rhsOwn = (nodeOwners[rhs] == factionId)
                if lhsOwn != rhsOwn {
                    return lhsOwn && !rhsOwn
                }
                let lhsCap = (CampaignMapConfig.node(byId: lhs)?.nodeType == .capitalCitadel)
                let rhsCap = (CampaignMapConfig.node(byId: rhs)?.nodeType == .capitalCitadel)
                if lhsCap != rhsCap {
                    return lhsCap && !rhsCap
                }
                return false
            }

            for neighborId in prioritizedNeighbors {
                guard !visited.contains(neighborId),
                      let neighborConfig = CampaignMapConfig.node(byId: neighborId),
                      let neighborOwner = nodeOwners[neighborId],
                      neighborOwner == factionId || alliedFactions.contains(neighborOwner) else {
                    continue
                }

                visited.insert(neighborId)
                parentByNode[neighborId] = currentId

                // 抵达本方直接控制的核心补给仓城/王都，立即回溯最短路径
                if neighborOwner == factionId && neighborConfig.isSupplyDepot {
                    return reconstructPath(from: nodeId, to: neighborId, parentByNode: parentByNode)
                }

                queue.append(neighborId)
            }
        }

        return []
    }

    // MARK: - CampaignSupplyServiceProtocol 核心实现

    /// 计算目标节点经由本方或正式军事同盟国节点通往本方最近仓城的 BFS 最短路径补给状态
    public func evaluateSupplyStatus(
        forNodeId nodeId: String,
        factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId>,
        priorIsolatedTurns: Int
    ) -> SupplyLineStatus {
        let path = shortestSupplyPath(
            forNodeId: nodeId,
            factionId: factionId,
            nodeOwners: nodeOwners,
            alliedFactions: alliedFactions
        )

        guard !path.isEmpty else {
            let nextIsolatedTurns = max(0, priorIsolatedTurns) + 1
            return .severed(isolatedTurns: nextIsolatedTurns)
        }

        let hops = path.count - 1
        return classifyReachableHops(hops)
    }

    // MARK: - 行军跨境出击补给预判与数值修正

    /// 评估主力自本方/盟友出发节点（`stagingNodeId`）向相邻敌占目标节点（`targetNodeId`）发起进攻时的前线补给状态
    public func evaluateMarchSupplyStatus(
        fromStagingNodeId stagingNodeId: String,
        targetNodeId: String,
        factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId> = [],
        stagingPriorIsolatedTurns: Int = 0
    ) -> SupplyLineStatus {
        // 若目标节点原本已受本方或同盟控制，直接按目标节点实测
        if let targetOwner = nodeOwners[targetNodeId],
           targetOwner == factionId || alliedFactions.contains(targetOwner) {
            return evaluateSupplyStatus(
                forNodeId: targetNodeId,
                factionId: factionId,
                nodeOwners: nodeOwners,
                alliedFactions: alliedFactions,
                priorIsolatedTurns: stagingPriorIsolatedTurns
            )
        }

        // 校核出发节点与目标节点道路邻接性及出发节点自身粮道
        guard let stagingNode = CampaignMapConfig.node(byId: stagingNodeId),
              stagingNode.neighbors.contains(targetNodeId) else {
            return .severed(isolatedTurns: max(0, stagingPriorIsolatedTurns) + 1)
        }

        let stagingPath = shortestSupplyPath(
            forNodeId: stagingNodeId,
            factionId: factionId,
            nodeOwners: nodeOwners,
            alliedFactions: alliedFactions
        )
        guard !stagingPath.isEmpty else {
            return .severed(isolatedTurns: max(0, stagingPriorIsolatedTurns) + 1)
        }

        let marchHops = (stagingPath.count - 1) + 1
        return classifyReachableHops(marchHops)
    }

    /// 根据补给状态与势力法则计算耗粮、初始携粮、逃亡减员与士气封顶系数
    public func supplyModifiers(
        for status: SupplyLineStatus,
        factionId: FactionId
    ) -> SupplyPenaltyModifiers {
        let penaltyFactor = expeditionPenaltyRetentionFactor(for: factionId)

        switch status {
        case .fullSupply:
            return SupplyPenaltyModifiers(
                upkeepGrainMultiplier: 1.0,
                battleCarryGrainMultiplier: 1.0,
                nonCombatAttritionRate: 0.0,
                campaignMovementMultiplier: 1.0,
                battleInitialMoraleCap: GameConstants.moraleMax,
                isEmergencyRationWarning: false,
                isStarvingExhausted: false
            )

        case .extendedMarch:
            let upkeepSurcharge = Self.extendedMarchBaseUpkeepSurcharge * penaltyFactor
            let carryPenalty = Self.extendedMarchBaseCarryPenalty * penaltyFactor
            return SupplyPenaltyModifiers(
                upkeepGrainMultiplier: 1.0 + upkeepSurcharge,
                battleCarryGrainMultiplier: max(0.50, 1.0 - carryPenalty),
                nonCombatAttritionRate: 0.0,
                campaignMovementMultiplier: 1.0,
                battleInitialMoraleCap: GameConstants.moraleMax,
                isEmergencyRationWarning: false,
                isStarvingExhausted: false
            )

        case .overextended:
            let upkeepSurcharge = Self.overextendedBaseUpkeepSurcharge * penaltyFactor
            let carryPenalty = Self.overextendedBaseCarryPenalty * penaltyFactor
            return SupplyPenaltyModifiers(
                upkeepGrainMultiplier: 1.0 + upkeepSurcharge,
                battleCarryGrainMultiplier: max(0.45, 1.0 - carryPenalty),
                nonCombatAttritionRate: 0.0,
                campaignMovementMultiplier: 1.0,
                battleInitialMoraleCap: GameConstants.moraleMax,
                isEmergencyRationWarning: false,
                isStarvingExhausted: false
            )

        case .severed(let isolatedTurns):
            let clampedTurns = max(1, isolatedTurns)
            if clampedTurns == 1 {
                // 第 1 回合消耗随军应急干粮：红字预警，暂不触发逃亡减员与士气锁死
                let upkeepSurcharge = Self.overextendedBaseUpkeepSurcharge * penaltyFactor
                let carryPenalty = Self.overextendedBaseCarryPenalty * penaltyFactor
                return SupplyPenaltyModifiers(
                    upkeepGrainMultiplier: 1.0 + upkeepSurcharge,
                    battleCarryGrainMultiplier: max(0.50, 1.0 - carryPenalty),
                    nonCombatAttritionRate: 0.0,
                    campaignMovementMultiplier: 1.0,
                    battleInitialMoraleCap: GameConstants.moraleMax,
                    isEmergencyRationWarning: true,
                    isStarvingExhausted: false
                )
            } else {
                // 第 2 回合起陷入【饥疲】：每回合非战斗逃亡减员 8%、行军力 -25%、开战士气封顶 65
                return SupplyPenaltyModifiers(
                    upkeepGrainMultiplier: 1.0 + Self.overextendedBaseUpkeepSurcharge * penaltyFactor,
                    battleCarryGrainMultiplier: 0.55,
                    nonCombatAttritionRate: Self.severedStarvationAttritionRate,
                    campaignMovementMultiplier: 1.0 - Self.severedMovementPenalty,
                    battleInitialMoraleCap: Self.severedBattleMoraleCap,
                    isEmergencyRationWarning: false,
                    isStarvingExhausted: true
                )
            }
        }
    }

    /// 计算战前实际可携行进入 4800×2400 战场的初始军粮数（基准 `GameConstants.battleInitGrain = 1200.0`）
    public func calculateBattleInitialGrain(
        for status: SupplyLineStatus,
        factionId: FactionId,
        availableFactionGrain: Int? = nil
    ) -> Double {
        let mods = supplyModifiers(for: status, factionId: factionId)
        let cap = GameConstants.battleInitGrain * mods.battleCarryGrainMultiplier
        guard let reserve = availableFactionGrain else {
            return cap
        }
        // 保底应急干粮 240，确保即便国库粮草吃紧也不至于 0 秒直接饥溃
        let affordable = max(240.0, Double(max(0, reserve)))
        return min(cap, affordable)
    }

    /// 输出单节点的完整补给评估快照（路径 + 状态 + 惩罚系数）
    public func evaluateNodeSupplyDetail(
        forNodeId nodeId: String,
        factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId> = [],
        priorIsolatedTurns: Int = 0
    ) -> CampaignSupplyRouteEvaluation {
        let path = shortestSupplyPath(
            forNodeId: nodeId,
            factionId: factionId,
            nodeOwners: nodeOwners,
            alliedFactions: alliedFactions
        )
        let status: SupplyLineStatus
        if path.isEmpty {
            status = .severed(isolatedTurns: max(0, priorIsolatedTurns) + 1)
        } else {
            status = classifyReachableHops(path.count - 1)
        }
        let mods = supplyModifiers(for: status, factionId: factionId)
        return CampaignSupplyRouteEvaluation(
            nodeId: nodeId,
            factionId: factionId,
            status: status,
            shortestPathNodeIds: path,
            nearestDepotNodeId: path.last,
            modifiers: mods
        )
    }

    /// 批量评估指定势力当前控制的全部城关补给状态
    public func evaluateAllControlledNodes(
        for factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId> = [],
        priorIsolatedTurnsByNode: [String: Int] = [:]
    ) -> [String: CampaignSupplyRouteEvaluation] {
        var results: [String: CampaignSupplyRouteEvaluation] = [:]
        for node in CampaignMapConfig.allNodes where nodeOwners[node.id] == factionId {
            let priorTurns = priorIsolatedTurnsByNode[node.id] ?? 0
            results[node.id] = evaluateNodeSupplyDetail(
                forNodeId: node.id,
                factionId: factionId,
                nodeOwners: nodeOwners,
                alliedFactions: alliedFactions,
                priorIsolatedTurns: priorTurns
            )
        }
        return results
    }

    /// 汇总本方所有受控城关在最短粮道树上激活的无向道路边（供 SwiftUI 大地图绿色/琥珀色补给干道高亮渲染）
    public func highlightedSupplyRoadEdges(
        for factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId> = []
    ) -> [CampaignRoadEdge] {
        var activeEdges = Set<CampaignRoadEdge>()
        for node in CampaignMapConfig.allNodes where nodeOwners[node.id] == factionId {
            let path = shortestSupplyPath(
                forNodeId: node.id,
                factionId: factionId,
                nodeOwners: nodeOwners,
                alliedFactions: alliedFactions
            )
            guard path.count >= 2 else { continue }
            for idx in 0..<(path.count - 1) {
                activeEdges.insert(CampaignRoadEdge(nodeA: path[idx], nodeB: path[idx + 1]))
            }
        }
        return activeEdges.sorted { $0.id < $1.id }
    }

    // MARK: - 私有辅助函数

    private func classifyReachableHops(_ hops: Int) -> SupplyLineStatus {
        let normalizedHops = max(0, hops)
        if normalizedHops <= GameConstants.supplyFullEfficiencyHops {
            return .fullSupply(hops: normalizedHops)
        } else if normalizedHops == 3 {
            return .extendedMarch(hops: 3)
        } else {
            return .overextended(hops: normalizedHops)
        }
    }

    private func reconstructPath(
        from startNodeId: String,
        to depotNodeId: String,
        parentByNode: [String: String]
    ) -> [String] {
        var reversedPath: [String] = [depotNodeId]
        var cursor = depotNodeId
        while cursor != startNodeId {
            guard let parent = parentByNode[cursor] else {
                return []
            }
            reversedPath.append(parent)
            cursor = parent
        }
        return reversedPath.reversed()
    }
}
