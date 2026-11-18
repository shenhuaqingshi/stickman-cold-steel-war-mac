import Foundation

/// 战役战略大地图与 BFS 粮道模块协议契约（第 1 步：仅定义补给跳数状态与回合接口契约，不含推演实现逻辑）

/// 大地图节点 BFS 补给线连通等级（对应 DESIGN.md 7.3 & 10.1）
public enum SupplyLineStatus: Sendable, Equatable {
    /// 近境作战（跳数 d <= 2）：补给效率 100%，无额外损耗
    case fullSupply(hops: Int)
    /// 长途远征（跳数 d == 3）：维持耗粮 +25%，战前携粮上限 -15%（苍狼汗国减免 35% 惩罚）
    case extendedMarch(hops: Int)
    /// 孤军悬远（跳数 d >= 4）：维持耗粮 +50%，亟需攻占仓城或结盟借道
    case overextended(hops: Int)
    /// 粮道断绝（跳数 d == ∞）：第 1 回合消耗应急干粮红字预警；第 2 回合起进入【饥疲】逃亡减员 8%/回合、初始士气封顶 65
    case severed(isolatedTurns: Int)
}

/// 战后结算摘要数据契约（伤兵救治、俘虏收编/赎金、粮械缴获、主帅晋升）
public struct PostBattleSettlementSummary: Sendable, Codable, Equatable {
    public let scenarioType: BattleScenarioType
    public let playerFaction: FactionId
    public let enemyFaction: FactionId
    public let isVictory: Bool
    public let outcomeReason: BattleOutcomeReason
    public let durationSeconds: Int
    public let playerKilled: Int
    public let playerWoundedRecovered: Int
    public let enemyKilled: Int
    public let capturedPrisoners: Int
    public let lootedGold: Int
    public let lootedWood: Int
    public let lootedGrain: Int
    public let commanderExpGained: Int

    public init(
        scenarioType: BattleScenarioType = .fieldPitched,
        playerFaction: FactionId = .yanlong,
        enemyFaction: FactionId = .canglang,
        isVictory: Bool = true,
        outcomeReason: BattleOutcomeReason = .enemyArmyRouted,
        durationSeconds: Int = 215,
        playerKilled: Int = 28,
        playerWoundedRecovered: Int = 19,
        enemyKilled: Int = 112,
        capturedPrisoners: Int = 24,
        lootedGold: Int = 260,
        lootedWood: Int = 140,
        lootedGrain: Int = 320,
        commanderExpGained: Int = 450
    ) {
        self.scenarioType = scenarioType
        self.playerFaction = playerFaction
        self.enemyFaction = enemyFaction
        self.isVictory = isVictory
        self.outcomeReason = outcomeReason
        self.durationSeconds = durationSeconds
        self.playerKilled = playerKilled
        self.playerWoundedRecovered = playerWoundedRecovered
        self.enemyKilled = enemyKilled
        self.capturedPrisoners = capturedPrisoners
        self.lootedGold = lootedGold
        self.lootedWood = lootedWood
        self.lootedGrain = lootedGrain
        self.commanderExpGained = commanderExpGained
    }
}

/// 战役补给线与回合推进服务协议
public protocol CampaignSupplyServiceProtocol: Sendable {
    /// 计算目标节点经由本方或正式军事同盟国节点通往最近仓城（isSupplyDepot == true）的 BFS 最短路径状态
    func evaluateSupplyStatus(
        forNodeId nodeId: String,
        factionId: FactionId,
        nodeOwners: [String: FactionId],
        alliedFactions: Set<FactionId>,
        priorIsolatedTurns: Int
    ) -> SupplyLineStatus
}
