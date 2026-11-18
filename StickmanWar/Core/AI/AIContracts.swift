import Foundation

/// 分层 AI 决策模块协议契约（第 1 步：仅定义 L1 战略大地图 / L2 战场黑板指挥官 / L3 攻守城三段式接口契约，不含决策执行逻辑）

/// L2 战场指挥官战术条令枚举（对应 DESIGN.md 9.2）
public enum BattlefieldAiDoctrine: String, Sendable, Codable, Hashable {
    case hammerAndAnvil = "hammer_and_anvil"           // 锤砧包抄（重步正面抗线 + 铁骑南北走廊绕后切弓手投石车）
    case highGroundHedgehog = "high_ground_hedgehog"   // 高地刺猬防反（据守高地桥头强弩拒马，绝不盲追单骑诱饵）
    case feignedRetreatAmbush = "feigned_retreat"      // 诈败诱敌伏击（散兵佯退引敌入密林陷阱袋合围）
    case reserveBreakthrough = "reserve_breakthrough"  // 总预备队关键投入（防线跌破 35 士气堵口或抓住敌动摇全压）
    case antiKiteEscort = "anti_kite_escort"           // 反风筝分兵驱离（仅派 1 队轻骑/神射驱离玩家主帅，严禁全军傻追）
}

/// 攻守城专项三段式战术阶段枚举（对应 DESIGN.md 9.2 第 6 条）
public enum SiegeTacticalPhase: String, Sendable, Codable, Hashable {
    // 攻城方三段式
    case attackerArtilleryPrep = "attacker_artillery_prep"     // 阶段1：重步护投石车/弩车拆箭塔与薄弱墙段
    case attackerMultiLadder = "attacker_multi_ladder"         // 阶段2：刀盾顶箭雨掩护两翼架云梯 + 巨斧破正门
    case attackerBreachExploit = "attacker_breach_exploit"     // 阶段3：城破投入具装重骑/巨熊总预备队凿入瓮城

    // 守城方三段式
    case defenderWallFocusFire = "defender_wall_focus"         // 阶段1：城头强弩优先点杀推云梯工兵与无盾巨斧兵
    case defenderGatePlugPhalanx = "defender_gate_plug"        // 阶段2：城门耐久 <30% 调长枪重步门洞结圆阵/方阵死堵
    case defenderSallyDestroySiege = "defender_sally_raid"     // 阶段3：侧门派轻骑绕后奇袭焚毁攻方投石车
}

/// L2 战场战术黑板态势摘要（每 0.5 秒更新一次）
public struct TacticalBlackboardSummary: Sendable, Equatable {
    public let activeDoctrine: BattlefieldAiDoctrine
    public let siegePhase: SiegeTacticalPhase?
    public let reserveCommitted: Bool
    public let detectedPlayerHeroKiting: Bool

    public init(
        activeDoctrine: BattlefieldAiDoctrine = .hammerAndAnvil,
        siegePhase: SiegeTacticalPhase? = nil,
        reserveCommitted: Bool = false,
        detectedPlayerHeroKiting: Bool = false
    ) {
        self.activeDoctrine = activeDoctrine
        self.siegePhase = siegePhase
        self.reserveCommitted = reserveCommitted
        self.detectedPlayerHeroKiting = detectedPlayerHeroKiting
    }
}

/// L1 战略大地图 AI 决策器协议（第 2/3 阶段实现 7 大 AI 势力独立回合攻伐、两线规避与合纵制衡）
public protocol StrategicCampaignAIProtocol: Sendable {
    func evaluateTurnActions(for factionId: FactionId, personality: AiPersonality) -> [String]
}
