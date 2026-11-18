// ============================================================================
// 文件：ImperialSystemsTests.swift
// 模块：《帝国锋刃》新增核心系统专项单元测试（XCTest）
// 覆盖：四阶文明时代演进（I -> IV）、RTS 基地营建与民夫施工完工、铁匠铺三系锻造（Lv.1~3）、
//       罗马龟甲阵（85% 挡箭 + 35% 护甲）与右键拖拽宽窄拉线、募兵取消全额退费、
//       战役行省赋税国策调控与元老院/王庭三阶段拓土悬赏诏令。
// ============================================================================

import Foundation
import XCTest
@testable import StickmanWar

final class ImperialSystemsTests: XCTestCase {

    // MARK: - 1. 四阶文明时代演进（I -> II -> III -> IV）与人口上限阶梯扩容

    func testFourImperialAgesProgressionAndPopCapScaling() {
        let ctx = RouteLaunchContext(
            entryMode: .skirmish,
            playerFaction: .yanlong,
            enemyFaction: .canglang,
            scenarioType: .fieldPitched,
            aiDifficulty: .veteran
        )
        let deploy = BattleDeploymentConfig(
            playerInitialGold: 1600,
            playerInitialWood: 1200,
            playerInitialGrain: 2000.0
        )
        var engine = BattleSimulationEngine(context: ctx, deployment: deploy)

        XCTAssertEqual(engine.playerState.currentAge, .age1Bronze)
        let initialBasePop = engine.playerState.popCap

        // 启动时代 II 演进（15s）
        XCTAssertTrue(engine.startAgeAdvancement(side: .player))
        XCTAssertEqual(engine.playerState.advancingToAge, .age2IronCity)
        // 演进途中不可重复点击
        XCTAssertFalse(engine.startAgeAdvancement(side: .player))

        for _ in 0..<160 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(engine.playerState.currentAge, .age2IronCity)
        XCTAssertNil(engine.playerState.advancingToAge)
        XCTAssertEqual(engine.playerState.popCap, initialBasePop + ImperialAge.age2IronCity.popCapBonus)

        // 继续演进至时代 III（20s）与时代 IV（25s）
        XCTAssertTrue(engine.startAgeAdvancement(side: .player))
        for _ in 0..<210 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(engine.playerState.currentAge, .age3Imperial)

        XCTAssertTrue(engine.startAgeAdvancement(side: .player))
        for _ in 0..<260 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(engine.playerState.currentAge, .age4Hegemon)
        XCTAssertEqual(engine.playerState.popCap, initialBasePop + ImperialAge.age4Hegemon.popCapBonus)
        // 已达最高传世霸业时代 IV，不可再演进
        XCTAssertFalse(engine.startAgeAdvancement(side: .player))
    }

    // MARK: - 2. RTS 基地营建（民居、农庄、铁匠铺）与铁匠三系锻造科技（Lv.1~3）

    func testRtsBaseConstructionPeasantBuildAndBlacksmithForging() {
        let ctx = RouteLaunchContext(
            entryMode: .customSandbox,
            playerFaction: .yanlong,
            enemyFaction: .tieying,
            scenarioType: .fieldPitched
        )
        let deploy = BattleDeploymentConfig(
            customPlayerRoster: [
                BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 6, initialFormation: .circleDefense),
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 12, initialFormation: .phalanxRect)
            ],
            customEnemyRoster: [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 12, initialFormation: .phalanxRect)
            ],
            playerInitialGold: 1800,
            playerInitialWood: 1400,
            playerInitialGrain: 2200.0
        )
        var engine = BattleSimulationEngine(context: ctx, deployment: deploy)
        let basePop = engine.playerState.popCap

        // 未造铁匠铺前，铁匠锻造必须拒绝
        XCTAssertFalse(engine.upgradeBlacksmithTrack(side: .player, track: .meleeForging))

        // 时代 I 不能提前建造需时代 II 的皇家马厩
        if let earlyLoc = engine.findAutoBuildLocation(side: .player, kind: .stables) {
            XCTAssertFalse(engine.constructBuilding(side: .player, kind: .stables, atX: earlyLoc.x, atY: earlyLoc.y))
        }

        // 时代 I 营建军屯民居与帝国农庄
        guard let houseSite = engine.findAutoBuildLocation(side: .player, kind: .houseQuarter) else {
            return XCTFail("Expected valid auto-build location for houseQuarter")
        }
        XCTAssertTrue(engine.constructBuilding(side: .player, kind: .houseQuarter, atX: houseSite.x, atY: houseSite.y))

        guard let farmSite = engine.findAutoBuildLocation(side: .player, kind: .imperialFarm) else {
            return XCTFail("Expected valid auto-build location for imperialFarm")
        }
        XCTAssertTrue(engine.constructBuilding(side: .player, kind: .imperialFarm, atX: farmSite.x, atY: farmSite.y))

        // 同时推进至时代 III 以便解锁铁匠铺与三阶满锻造
        XCTAssertTrue(engine.startAgeAdvancement(side: .player))
        for _ in 0..<180 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(engine.playerState.currentAge, .age2IronCity)

        // 民居与农庄应已由民夫夯筑完工，人口上限获得民居 +16 与时代 II +20 双重增益
        let builtHouses = engine.structures.filter { $0.side == .player && $0.kind == .houseQuarter && !$0.isUnderConstruction }
        let builtFarms = engine.structures.filter { $0.side == .player && $0.kind == .imperialFarm && !$0.isUnderConstruction }
        XCTAssertEqual(builtHouses.count, 1)
        XCTAssertEqual(builtFarms.count, 1)
        XCTAssertEqual(engine.playerState.popCap, basePop + ImperialAge.age2IronCity.popCapBonus + 16)

        // 时代 II 营建铁匠铺并推进至时代 III
        guard let smithSite = engine.findAutoBuildLocation(side: .player, kind: .blacksmith) else {
            return XCTFail("Expected valid auto-build location for blacksmith")
        }
        XCTAssertTrue(engine.constructBuilding(side: .player, kind: .blacksmith, atX: smithSite.x, atY: smithSite.y))
        XCTAssertTrue(engine.startAgeAdvancement(side: .player))
        for _ in 0..<220 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(engine.playerState.currentAge, .age3Imperial)

        let builtSmith = engine.structures.filter { $0.side == .player && $0.kind == .blacksmith && !$0.isUnderConstruction }
        XCTAssertEqual(builtSmith.count, 1)

        // 连续升级百炼锋刃 Lv.1 -> Lv.2 -> Lv.3
        XCTAssertTrue(engine.upgradeBlacksmithTrack(side: .player, track: .meleeForging))
        XCTAssertTrue(engine.upgradeBlacksmithTrack(side: .player, track: .meleeForging))
        XCTAssertTrue(engine.upgradeBlacksmithTrack(side: .player, track: .meleeForging))
        XCTAssertEqual(engine.playerState.meleeForgeLevel, 3)
        // Lv.3 满级后不可超限升级
        XCTAssertFalse(engine.upgradeBlacksmithTrack(side: .player, track: .meleeForging))

        XCTAssertTrue(engine.upgradeBlacksmithTrack(side: .player, track: .armorTempering))
        XCTAssertTrue(engine.upgradeBlacksmithTrack(side: .player, track: .fletchingcraft))
        XCTAssertEqual(engine.playerState.armorTemperLevel, 1)
        XCTAssertEqual(engine.playerState.fletchingLevel, 1)
    }

    // MARK: - 3. 罗马龟甲阵（85% 挡箭减伤）与右键拖拽拉线宽度、募兵撤单全额退款

    func testRomanTestudoShieldingRightClickLineSpreadAndQueueRefund() {
        // 罗马龟甲阵在正面受远程射击时，即使兵种自身无高盾防亦强制享有至少 85% 挡箭减免与 +35% 护甲
        let normalHit = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 50.0,
                attackerArmorPenetration: 0.10,
                attackerFormationBonusActive: false,
                isMelee: false,
                targetBaseArmor: 40.0,
                targetShieldRangedBlock: 0.20,
                targetFormation: .phalanxRect,
                targetFormationBonusActive: true,
                incomingAngleDifferenceRadians: 0.0
            )
        )
        let testudoHit = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 50.0,
                attackerArmorPenetration: 0.10,
                attackerFormationBonusActive: false,
                isMelee: false,
                targetBaseArmor: 40.0,
                targetShieldRangedBlock: 0.20,
                targetFormation: .testudo,
                targetFormationBonusActive: true,
                incomingAngleDifferenceRadians: 0.0
            )
        )
        XCTAssertTrue(testudoHit.shieldBlocked)
        XCTAssertLessThan(testudoHit.finalDamage, normalHit.finalDamage * 0.35)

        // 右键拖拽拉宽战线（lineSpreadMultiplier = 1.9）应产生比标准战线（1.0）更宽的横向散开排数
        let normalOffsets = (0..<16).map { idx in
            DamageMoraleCalculator.computeFormationSlotOffset(
                slotIndex: idx,
                totalSlots: 16,
                formation: .phalanxRect,
                lineSpreadMultiplier: 1.0
            )
        }
        let wideOffsets = (0..<16).map { idx in
            DamageMoraleCalculator.computeFormationSlotOffset(
                slotIndex: idx,
                totalSlots: 16,
                formation: .phalanxRect,
                lineSpreadMultiplier: 1.9
            )
        }
        let normalSpanY = (normalOffsets.map { $0.lateralY }.max() ?? 0) - (normalOffsets.map { $0.lateralY }.min() ?? 0)
        let wideSpanY = (wideOffsets.map { $0.lateralY }.max() ?? 0) - (wideOffsets.map { $0.lateralY }.min() ?? 0)
        XCTAssertGreaterThan(wideSpanY, normalSpanY * 1.35)

        // 募兵入列与右键取消全额退费校验
        let ctx = RouteLaunchContext(entryMode: .skirmish, playerFaction: .yanlong, enemyFaction: .canglang)
        var engine = BattleSimulationEngine(
            context: ctx,
            deployment: BattleDeploymentConfig(playerInitialGold: 500, playerInitialWood: 300, playerInitialGrain: 800)
        )
        let goldBefore = engine.playerState.gold
        let popBefore = engine.playerState.popUsed
        XCTAssertTrue(engine.recruitUnit(side: .player, unitType: .shieldSwordsman))
        XCTAssertEqual(engine.playerState.trainingQueue.count, 1)
        XCTAssertLessThan(engine.playerState.gold, goldBefore)

        XCTAssertTrue(engine.cancelTrainingQueueItem(side: .player, at: 0))
        XCTAssertEqual(engine.playerState.trainingQueue.count, 0)
        XCTAssertEqual(engine.playerState.gold, goldBefore)
        XCTAssertEqual(engine.playerState.popUsed, popBefore)
    }

    // MARK: - 4. 战役行省赋税国策与元老院拓土悬赏诏令

    func testCampaignTaxEdictsAndImperialMandateRewards() {
        var lowTaxCampaign = CampaignTurnEngine(playerFaction: .yanlong, seed: 20261118)
        lowTaxCampaign.setPlayerTaxPolicy(.benevolentLow)
        let lowReport = lowTaxCampaign.advanceTurn()

        var highTaxCampaign = CampaignTurnEngine(playerFaction: .yanlong, seed: 20261118)
        highTaxCampaign.setPlayerTaxPolicy(.warLevyHigh)
        let highReport = highTaxCampaign.advanceTurn()

        // 军国重敛税金显著高于轻徭薄赋，而轻徭薄赋净粮更高
        XCTAssertGreaterThan(highReport.playerGoldEarned, lowReport.playerGoldEarned)
        XCTAssertGreaterThan(lowReport.playerGrainNetChange, highReport.playerGrainNetChange)

        // 初始 5 城时未满 7 城，阶段 1 悬赏不可领取
        let premature = lowTaxCampaign.claimImperialMandateReward(stage: 1)
        XCTAssertFalse(premature.succeeded)

        // 攻占额外 2 座城关达到 7 城后，成功领受阶段 1 王命赏赐（黄金 +350，木材 +180），且防重复领取
        var snap = lowTaxCampaign.worldState
        let extraNodes = CampaignMapConfig.allNodes.filter { $0.initialOwner != .yanlong }.prefix(2)
        for node in extraNodes {
            snap.nodesById[node.id]?.owner = .yanlong
        }
        var expandedCampaign = CampaignTurnEngine(restoredWorldState: snap)
        let goldBeforeClaim = expandedCampaign.factionState(for: .yanlong).gold
        let claimed = expandedCampaign.claimImperialMandateReward(stage: 1)
        XCTAssertTrue(claimed.succeeded)
        XCTAssertEqual(expandedCampaign.factionState(for: .yanlong).gold, goldBeforeClaim + 350)
        XCTAssertFalse(expandedCampaign.claimImperialMandateReward(stage: 1).succeeded)
    }
}
