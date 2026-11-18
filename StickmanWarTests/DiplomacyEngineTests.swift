// ============================================================================
// 文件：DiplomacyEngineTests.swift
// 模块：Core/Diplomacy 外交纵横、背盟铁律与量化媾和引擎专用单元测试（XCTest）
// 覆盖：无约正式宣战 vs 撕毁条约背盟雪崩（信誉 -45、受害国 -100 锁死、10 回合世仇禁谈、
//       全图诸侯 -25、连续 2 场战斗初始士气惩罚）、
//       双重同盟互攻“防御同盟优先保护受侵略方”零信誉扣除豁免铁律与 3 回合居中调停、
//       媾和谈判三档量化估值（>=0 签约 / [-20,0) 可负担反报价 / <-20 破裂锁使者）、
//       战败方仅余唯一王都时的孤城防灭国保护、低信誉 <40 禁结盟与 +80% 求和溢价、
//       沙漠商盟通商加成、单回合送礼递减防刷与 >=13 城反霸权【合纵警觉】+25 好感修正。
//
// 在 Mac 上的运行方式（当前 Linux 开发机无 Xcode / macOS，未在本机跑过）：
//   方式一（Xcode GUI）：打开 `StickmanWar.xcodeproj`，选择 `StickmanWar` Scheme，按 `Cmd+U`（⌘U）运行全部测试。
//   方式二（命令行）：在工程根目录执行：
//     xcodebuild test \
//       -project StickmanWar.xcodeproj \
//       -scheme StickmanWar \
//       -destination 'platform=macOS,arch=arm64' \
//       -only-testing:StickmanWarTests/DiplomacyEngineTests
// ============================================================================

import Foundation
import XCTest
@testable import StickmanWar

final class DiplomacyEngineTests: XCTestCase {

    // MARK: - 1. 正式宣战无损信誉 vs 撕毁条约背盟雪崩（-45 信誉、10 回合世仇、全图 -25、2 战降士气）

    func testFormalWarVsTreatyBetrayalAvalancheAndVendettaLock() {
        var diplo = DiplomacyEngine()

        // 1.1 对无条约约束的苍狼汗国正式宣战：零信誉扣除，关系降至 -80
        let startYanlongCred = diplo.credibility(of: .yanlong)
        let normalWar = diplo.declareWar(attacker: .yanlong, target: .canglang)
        XCTAssertFalse(normalWar.isBetrayalTriggered)
        XCTAssertEqual(normalWar.credibilityDelta, 0)
        XCTAssertEqual(diplo.credibility(of: .yanlong), startYanlongCred)
        XCTAssertEqual(diplo.status(between: .yanlong, and: .canglang), .war)
        XCTAssertLessThanOrEqual(diplo.relation(between: .yanlong, and: .canglang), -80)

        // 1.2 与铁鹰王国签署互不侵犯条约后背信突袭 -> 触发完整背盟重罚
        diplo.adjustRelation(between: .yanlong, and: .tieying, delta: 20)
        XCTAssertTrue(diplo.signNonAggressionPact(proposer: .yanlong, target: .tieying).succeeded)
        let shamoRelBefore = diplo.relation(between: .yanlong, and: .shamo)

        let betrayal = diplo.declareWar(attacker: .yanlong, target: .tieying)
        XCTAssertTrue(betrayal.isBetrayalTriggered)
        XCTAssertEqual(betrayal.credibilityDelta, -GameConstants.betrayalCredibilityPenalty)
        XCTAssertEqual(diplo.credibility(of: .yanlong), startYanlongCred - 45)
        XCTAssertEqual(diplo.relation(between: .yanlong, and: .tieying), GameConstants.diplomacyRelationMin)
        XCTAssertEqual(diplo.bilateralState(between: .yanlong, and: .tieying).vendettaLockTurns, 10)
        XCTAssertEqual(diplo.relation(between: .yanlong, and: .shamo), shamoRelBefore - GameConstants.betrayalGlobalRelationPenalty)

        // 炎龙帝国背盟后连续 2 场战斗承受 -16.0 初始士气惩罚，第 3 场归零
        XCTAssertEqual(diplo.consumePreBattleMoraleAdjustment(for: .yanlong), -16.0, accuracy: 1e-6)
        XCTAssertEqual(diplo.consumePreBattleMoraleAdjustment(for: .yanlong), -16.0, accuracy: 1e-6)
        XCTAssertEqual(diplo.consumePreBattleMoraleAdjustment(for: .yanlong), 0.0, accuracy: 1e-6)

        // 10 回合【血海世仇】锁定期内，受害国铁鹰拒绝一切停火谈判（即便倒贴 1000 金币）
        let generousOffer = PeaceOfferTerms(
            proposer: .yanlong,
            target: .tieying,
            goldIndemnity: 1000,
            grainTributePerTurn: 80,
            cededNodeIds: [],
            truceTurns: 8
        )
        if case .rejectedBreakdown(let score, _) = diplo.evaluatePeaceOffer(generousOffer) {
            XCTAssertEqual(score, -100.0, accuracy: 1e-6)
        } else {
            XCTFail("血海世仇锁定期内必须无条件斥退求和来使")
        }
    }

    // MARK: - 2. 双重同盟互攻“防御优先保护受侵略方”豁免铁律与居中调停

    func testDualAllianceMutualDefenseExemptionAndMediation() {
        var diplo = DiplomacyEngine()

        // 炎龙帝国同时与铁鹰王国（盟友 C）、沙漠商盟（盟友 B）缔结正式军事同盟
        diplo.adjustRelation(between: .yanlong, and: .tieying, delta: 60)
        diplo.adjustRelation(between: .yanlong, and: .shamo, delta: 60)
        XCTAssertTrue(diplo.formMilitaryAlliance(proposer: .yanlong, target: .tieying).succeeded)
        XCTAssertTrue(diplo.formMilitaryAlliance(proposer: .yanlong, target: .shamo).succeeded)

        // 沙漠商盟（挑衅方 B）主动向铁鹰王国（受侵略方 C）宣战
        _ = diplo.declareWar(attacker: .shamo, target: .tieying)
        XCTAssertEqual(diplo.warAggressor(between: .shamo, and: .tieying), .shamo)

        // 验证分支一：炎龙选择居中调停两大盟友，促成 3 回合停火，零信誉损失
        var mediatedCopy = diplo
        let medRes = mediatedCopy.mediateAlliedConflict(mediator: .yanlong, belligerentA: .shamo, belligerentB: .tieying)
        XCTAssertTrue(medRes.succeeded)
        XCTAssertEqual(mediatedCopy.status(between: .shamo, and: .tieying), .truce)
        XCTAssertEqual(mediatedCopy.bilateralState(between: .shamo, and: .tieying).remainingTurns, 3)

        // 验证分支二：若炎龙反而助纣为虐攻打被侵略者铁鹰 -> 判定为真实背盟（信誉 -45）
        let attackVictim = diplo.assessWarDeclarationImpact(attacker: .yanlong, target: .tieying)
        XCTAssertTrue(attackVictim.isBetrayalTriggered)
        XCTAssertEqual(attackVictim.credibilityDelta, -45)

        // 验证分支三：炎龙履行防御同盟义务向挑衅方沙漠商盟宣战协防铁鹰 -> 豁免背盟，零信誉扣除且铁鹰好感 +15
        let credBefore = diplo.credibility(of: .yanlong)
        let allyRelBefore = diplo.relation(between: .yanlong, and: .tieying)
        let defendAlly = diplo.declareWar(attacker: .yanlong, target: .shamo)
        XCTAssertFalse(defendAlly.isBetrayalTriggered, "协防被侵略同盟国绝不可判定为背盟")
        XCTAssertEqual(defendAlly.credibilityDelta, 0)
        XCTAssertEqual(diplo.credibility(of: .yanlong), credBefore)
        XCTAssertEqual(diplo.relation(between: .yanlong, and: .tieying), min(100, allyRelBefore + 15))
    }

    // MARK: - 3. 媾和三档量化闭环、可负担反报价边界与“唯一王都禁割让”孤城防灭国保护

    func testPeaceNegotiationThreeTiersAndLastCapitalProtection() {
        var diplo = DiplomacyEngine()
        _ = diplo.declareWar(attacker: .yanlong, target: .canglang)

        // 注入确定性态势：炎龙拥 5 城（军力 1200，厌战 8.0），苍狼仅剩最后 1 座王都 cl_capital（军力 600，金 40，粮 80）
        // 基准无筹码净分 = 8.0 (厌战) - 17.2 (优势) - 1.05 (信誉折价) = -10.25，精准落在 [-20, 0) 反报价档
        diplo.syncFactionStrategicSnapshot(
            factionId: .yanlong,
            availableGold: 900,
            availableGrain: 1400,
            ownedNodeIds: CampaignMapConfig.initialNodes(for: .yanlong).map(\.id),
            militaryStrengthScore: 1200.0,
            warExhaustion: 8.0
        )
        diplo.syncFactionStrategicSnapshot(
            factionId: .canglang,
            availableGold: 40,
            availableGrain: 80,
            ownedNodeIds: ["cl_capital"],
            militaryStrengthScore: 600.0,
            warExhaustion: 22.0
        )

        // 3.1 档位二（-20 <= AcceptScore < 0）+ 孤城保护：苍狼仅剩唯一王都且金粮匮乏，反报价严禁索要 cl_capital
        let whitePeaceOffer = PeaceOfferTerms(
            proposer: .canglang,
            target: .yanlong,
            goldIndemnity: 0,
            grainTributePerTurn: 0,
            cededNodeIds: [],
            truceTurns: 8
        )
        let counterOutcome = diplo.evaluatePeaceOffer(whitePeaceOffer)
        if case .counterOffer(let score, let counter) = counterOutcome {
            XCTAssertEqual(score, -10.25, accuracy: 1e-4)
            XCTAssertTrue(counter.cededNodeIds.isEmpty, "孤城防灭国保护：严禁反报价索取求方仅剩的最后 1 座王都")
            XCTAssertLessThanOrEqual(counter.goldIndemnity, 40, "反报价金币不得超过求方国库上限")
            XCTAssertLessThanOrEqual(counter.grainTributePerTurn * counter.truceTurns, 80, "反报价总纳粮不得超过求方库存上限")
        } else {
            XCTFail("净得分 -10.25 应进入 [-20, 0) 反报价分支")
        }

        // 3.2 档位三（AcceptScore < -20）：劣势方反而倒索 300 金（-10.25 - 12.0 = -22.25）-> 斥退来使、锁本回合派使、敌获 +8 士气
        let insolentDemand = PeaceOfferTerms(
            proposer: .canglang,
            target: .yanlong,
            goldIndemnity: -300,
            grainTributePerTurn: 0,
            cededNodeIds: [],
            truceTurns: 8
        )
        let rejected = diplo.submitPeaceOffer(insolentDemand)
        if case .rejectedBreakdown(let score, _) = rejected {
            XCTAssertLessThan(score, -20.0)
        } else {
            XCTFail("劣势讹诈净分 < -20 应触发谈判破裂")
        }
        XCTAssertTrue(diplo.isEnvoyLockedThisTurn(from: .canglang, to: .yanlong))
        XCTAssertEqual(diplo.consumePreBattleMoraleAdjustment(for: .yanlong), 8.0, accuracy: 1e-6)

        // 推进一回合解除单回合派使锁，苍狼获充足金币后奉上 350 金赔款 -> 档位一（AcceptScore >= 0）当场签约停战
        diplo.advanceDiplomacyTurn(nodeOwners: CampaignSupplyService.initialNodeOwners())
        XCTAssertFalse(diplo.isEnvoyLockedThisTurn(from: .canglang, to: .yanlong))
        diplo.syncFactionStrategicSnapshot(
            factionId: .canglang,
            availableGold: 500,
            availableGrain: 600,
            ownedNodeIds: ["cl_capital"],
            militaryStrengthScore: 600.0,
            warExhaustion: 24.0
        )
        let sincereOffer = PeaceOfferTerms(
            proposer: .canglang,
            target: .yanlong,
            goldIndemnity: 350,
            grainTributePerTurn: 20,
            cededNodeIds: [],
            truceTurns: 8
        )
        let accepted = diplo.submitPeaceOffer(sincereOffer)
        if case .accepted(let netScore) = accepted {
            XCTAssertGreaterThanOrEqual(netScore, 0.0)
        } else {
            XCTFail("足额赔款应触发 AcceptScore >= 0 签约成功")
        }
        XCTAssertEqual(diplo.status(between: .canglang, and: .yanlong), .truce)
        XCTAssertEqual(diplo.bilateralState(between: .canglang, and: .yanlong).remainingTurns, 8)
    }

    // MARK: - 4. 低信誉禁结盟与 +80% 求和溢价、商盟通商加成、送礼递减防刷及 >=13 城合纵警觉

    func testLowCredibilityTradeBonusGiftDiminishingAndAntiHegemonyAlert() {
        var diplo = DiplomacyEngine()

        // 4.1 信誉跌破 40 时禁绝全图结盟，且求和赔款溢价 +80%（1.80x）
        diplo.adjustCredibility(of: .xueyue, delta: -30) // 65 - 30 = 35 < 40
        diplo.adjustRelation(between: .xueyue, and: .wulin, delta: 90)
        XCTAssertEqual(diplo.requiredIndemnityPremiumMultiplier(for: .xueyue), 1.80, accuracy: 1e-6)
        XCTAssertFalse(diplo.formMilitaryAlliance(proposer: .xueyue, target: .wulin).succeeded)

        // 4.2 沙漠商盟丝路通商 +35% 收益与《丝路商队》+45 金科技验证
        diplo.adjustRelation(between: .shamo, and: .yanlong, delta: 25)
        XCTAssertTrue(diplo.signTradePact(proposer: .shamo, target: .yanlong).succeeded)
        let baseShamoTrade = diplo.calculateTradeIncome(for: .shamo, unlockedTechs: [])
        let caravanShamoTrade = diplo.calculateTradeIncome(for: .shamo, unlockedTechs: ["sm_tech_caravan"])
        XCTAssertEqual(baseShamoTrade, Int((Double(DiplomacyEngine.baseTradeIncomePerPact) * 1.35).rounded()))
        XCTAssertEqual(caravanShamoTrade, baseShamoTrade + DiplomacyEngine.shamoCaravanTechBonusPerPact)

        // 4.3 单回合送礼递减防刷：100% -> 50% -> 25% -> 第 4 次拒绝
        let g1 = diplo.sendDiplomaticGift(from: .yanlong, to: .shuangyuan, gold: 200, grain: 0)
        let g2 = diplo.sendDiplomaticGift(from: .yanlong, to: .shuangyuan, gold: 200, grain: 0)
        let g3 = diplo.sendDiplomaticGift(from: .yanlong, to: .shuangyuan, gold: 200, grain: 0)
        let g4 = diplo.sendDiplomaticGift(from: .yanlong, to: .shuangyuan, gold: 200, grain: 0)
        XCTAssertTrue(g1.succeeded)
        XCTAssertTrue(g2.succeeded)
        XCTAssertTrue(g3.succeeded)
        XCTAssertFalse(g4.succeeded, "同一回合第 4 次送礼应触发防刷拦截")
        XCTAssertGreaterThan(g1.relationDelta, g2.relationDelta)
        XCTAssertGreaterThan(g2.relationDelta, g3.relationDelta)

        // 4.4 反霸权【合纵警觉】：任一势力占城 >= 13 座时，相邻非同盟诸侯获得一次性 +25 共同威胁好感（重复重算幂等）
        var owners = CampaignSupplyService.initialNodeOwners()
        let relTieyingShamoBefore = diplo.relation(between: .tieying, and: .shamo)
        let capturedByYanlong = ["cl_river", "cl_pasture", "xj_plain", "xj_pass", "xy_ferry", "wl_sentry", "wl_bridge", "xy_camp"]
        for nid in capturedByYanlong {
            owners[nid] = .yanlong
        }
        let boostedPairs = diplo.recalculateAntiHegemonyAlert(nodeOwners: owners)
        XCTAssertGreaterThan(boostedPairs, 0)
        XCTAssertEqual(diplo.relation(between: .tieying, and: .shamo), relTieyingShamoBefore + 25)

        let repeatBoost = diplo.recalculateAntiHegemonyAlert(nodeOwners: owners)
        XCTAssertEqual(repeatBoost, 0, "合纵警觉 +25 好感修正不得在同一态势下重复累加")
    }
}
