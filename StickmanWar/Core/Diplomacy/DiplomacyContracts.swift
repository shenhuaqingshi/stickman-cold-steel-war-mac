import Foundation

/// 外交纵横、媾和估值与背盟铁律模块协议契约（第 1 步：仅定义三档媾和结果与双重同盟豁免契约，不含谈判算法实现）

/// 媾和谈判三档量化评估结果（对应 DESIGN.md 8.3 & 10.4）
public enum PeaceNegotiationOutcome: Sendable, Equatable {
    /// AcceptScore >= 0：签约生效，锁定停战回合数
    case accepted(netScore: Double)
    /// -20 <= AcceptScore < 0：对方提出明确且不超过求方资产上限的反报价单
    case counterOffer(netScore: Double, counterTerms: PeaceOfferTerms)
    /// AcceptScore < -20 或处于 10 回合【血海世仇】锁定期：斥退来使，本回合禁再派使，双边关系 -10
    case rejectedBreakdown(netScore: Double, reason: String)
}

/// 撕毁条约 / 停战期偷袭的背盟后果预览（用于二次确认强阻断弹窗与单元测试断言，含双重同盟防御豁免判定）
public struct BetrayalImpactAssessment: Sendable, Equatable {
    /// 是否触发背盟（若满足“双重同盟互攻时协防被侵略方”铁律，则为 false，零信誉扣除！）
    public let isBetrayalTriggered: Bool
    /// 豁免或触发原因说明
    public let ruleExplanation: String
    /// 自身外交信誉扣除值（标准触发为 -45，防御豁免为 0）
    public let credibilityDelta: Int
    /// 对全图其余第三方存活势力的关系惩罚（标准触发为 -25）
    public let globalRelationDelta: Int
    /// 受害国血海世仇禁谈锁定回合数（标准触发为 10 回合）
    public let vendettaLockTurns: Int
    /// 随后 2 场战斗己方初始士气惩罚（炎龙/铁鹰 -16，血月 -5，常规 -10）
    public let battleMoralePenalty: Double

    public init(
        isBetrayalTriggered: Bool,
        ruleExplanation: String,
        credibilityDelta: Int,
        globalRelationDelta: Int,
        vendettaLockTurns: Int,
        battleMoralePenalty: Double
    ) {
        self.isBetrayalTriggered = isBetrayalTriggered
        self.ruleExplanation = ruleExplanation
        self.credibilityDelta = credibilityDelta
        self.globalRelationDelta = globalRelationDelta
        self.vendettaLockTurns = vendettaLockTurns
        self.battleMoralePenalty = battleMoralePenalty
    }
}

/// 外交状态机与媾和估值引擎协议
public protocol DiplomacyEngineProtocol: Sendable {
    /// 量化评估媾和方案得分并返回三档闭环结果
    func evaluatePeaceOffer(_ offer: PeaceOfferTerms) -> PeaceNegotiationOutcome
    /// 评估宣战或协防动作是否构成背盟（严格落实双重同盟防御优先豁免铁律）
    func assessWarDeclarationImpact(attacker: FactionId, target: FactionId) -> BetrayalImpactAssessment
}
