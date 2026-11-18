// ============================================================================
// 文件：CampaignEngineTests.swift
// 模块：Core/Campaign 战役回合引擎与 BFS 粮道补给服务专用单元测试（XCTest）
// 覆盖：40 节点初始态势与 [1415, 1510] 公平经济窗口一致性、
//       BFS 粮道跳数（<=2 满额 / 3 跳远征 / >=4 跳悬远 / 断绝）与同盟借道、
//       苍狼汗国远征惩罚 -35% 减免、大地图断粮第 1 回合干粮预警与第 2 回合 8% 饥疲逃亡减员、
//       非对称征兵成本与三阶科技研发、行军背盟阻断、围点打援（孤城 -25 士气）、
//       战后结算回写（夺城、俘虏处置、主帅重伤休养 2 回合、统一王都胜利）及存档原子读写回环。
//
// 在 Mac 上的运行方式（当前 Linux 开发机无 Xcode / macOS，未在本机跑过）：
//   方式一（Xcode GUI）：打开 `StickmanWar.xcodeproj`，选择 `StickmanWar` Scheme，按 `Cmd+U`（⌘U）运行全部测试。
//   方式二（命令行）：在工程根目录执行：
//     xcodebuild test \
//       -project StickmanWar.xcodeproj \
//       -scheme StickmanWar \
//       -destination 'platform=macOS,arch=arm64' \
//       -only-testing:StickmanWarTests/CampaignEngineTests
// ============================================================================

import Foundation
import XCTest
@testable import StickmanWar

final class CampaignEngineTests: XCTestCase {

    // MARK: - 1. 战役开局 40 城关态势、本土无损补给与 [1415, 1510] 经济公平窗口验证

    func testInitialWorldStateEconomyWindowAndFullHomeSupply() {
        let engine = CampaignTurnEngine(playerFaction: .yanlong, seed: 2026)
        XCTAssertEqual(engine.worldState.turnNumber, 1)
        XCTAssertEqual(engine.worldState.nodesById.count, 40)
        XCTAssertEqual(engine.worldState.nodesById.count, GameConstants.campaignNodeCount)
        XCTAssertEqual(CampaignMapConfig.allRoadEdges.count, 78, "战役引擎依赖的大地图无向道路总数必须精确等于 78")
        XCTAssertEqual(engine.worldState.factions.count, 8)
        XCTAssertEqual(engine.worldState.victoryStatus, .ongoing)

        // 统一口径验证：实际开局总产出 1425–1490，全部落在 [1415, 1510] 公平窗口内
        let fairnessWindow = 1415...1510
        var factionYields: [Int] = []
        for faction in FactionId.allCases {
            let nodes = engine.controlledNodes(of: faction)
            XCTAssertEqual(nodes.count, 5)
            let sumYield = nodes.reduce(0) { acc, nd in
                acc + (CampaignMapConfig.node(byId: nd.id)?.totalYield ?? 0)
            }
            factionYields.append(sumYield)
            XCTAssertTrue(fairnessWindow.contains(sumYield), "\(faction.rawValue) 开局经济 \(sumYield) 超出 [1415, 1510] 窗口")

            for nd in nodes {
                XCTAssertNotNil(nd.cachedSupplyHops)
                XCTAssertLessThanOrEqual(nd.cachedSupplyHops ?? 99, GameConstants.supplyFullEfficiencyHops)
                XCTAssertEqual(nd.isolatedTurns, 0)
            }
        }
        XCTAssertEqual(factionYields.min(), 1425)
        XCTAssertEqual(factionYields.max(), 1490)
    }

    // MARK: - 2. BFS 粮道跳数分级、苍狼远征惩罚 -35% 减免与军事同盟借道补给

    func testBFSSupplyHopsCanglangReliefAndAlliedTransit() {
        let service = CampaignSupplyService()
        var owners = CampaignSupplyService.initialNodeOwners()

        // 构造北伐长链：yl_capital (0跳仓城) -> yl_pass (1跳) -> cl_river (2跳) -> cl_fort (3跳) -> xj_beacon (4跳)
        owners["cl_river"] = .yanlong
        owners["cl_fort"] = .yanlong
        owners["xj_beacon"] = .yanlong

        let hop0 = service.evaluateSupplyStatus(forNodeId: "yl_capital", factionId: .yanlong, nodeOwners: owners, alliedFactions: [], priorIsolatedTurns: 0)
        let hop2 = service.evaluateSupplyStatus(forNodeId: "cl_river", factionId: .yanlong, nodeOwners: owners, alliedFactions: [], priorIsolatedTurns: 0)
        let hop3 = service.evaluateSupplyStatus(forNodeId: "cl_fort", factionId: .yanlong, nodeOwners: owners, alliedFactions: [], priorIsolatedTurns: 0)
        let hop4 = service.evaluateSupplyStatus(forNodeId: "xj_beacon", factionId: .yanlong, nodeOwners: owners, alliedFactions: [], priorIsolatedTurns: 0)

        XCTAssertEqual(hop0, .fullSupply(hops: 0))
        XCTAssertEqual(hop2, .fullSupply(hops: 2))
        XCTAssertEqual(hop3, .extendedMarch(hops: 3))
        XCTAssertEqual(hop4, .overextended(hops: 4))

        // 验证常规势力 vs 苍狼汗国（远征惩罚减免 35%）的维持耗粮与携粮上限倍率
        let yanlongMod3 = service.supplyModifiers(for: hop3, factionId: .yanlong)
        let canglangMod3 = service.supplyModifiers(for: hop3, factionId: .canglang)
        XCTAssertEqual(yanlongMod3.upkeepGrainMultiplier, 1.25, accuracy: 1e-6)
        XCTAssertEqual(yanlongMod3.battleCarryGrainMultiplier, 0.85, accuracy: 1e-6)
        XCTAssertEqual(canglangMod3.upkeepGrainMultiplier, 1.0 + 0.25 * 0.65, accuracy: 1e-6)
        XCTAssertEqual(canglangMod3.battleCarryGrainMultiplier, 1.0 - 0.15 * 0.65, accuracy: 1e-6)

        // 敌军夺回咽喉 cl_river 截断归路：无同盟时 cl_fort 立即陷入粮道断绝
        owners["cl_river"] = .canglang
        let severedTurn1 = service.evaluateSupplyStatus(forNodeId: "cl_fort", factionId: .yanlong, nodeOwners: owners, alliedFactions: [], priorIsolatedTurns: 0)
        XCTAssertEqual(severedTurn1, .severed(isolatedTurns: 1))
        let modTurn1 = service.supplyModifiers(for: severedTurn1, factionId: .yanlong)
        XCTAssertTrue(modTurn1.isEmergencyRationWarning)
        XCTAssertFalse(modTurn1.isStarvingExhausted)
        XCTAssertEqual(modTurn1.nonCombatAttritionRate, 0.0, accuracy: 1e-6)

        let severedTurn2 = service.evaluateSupplyStatus(forNodeId: "cl_fort", factionId: .yanlong, nodeOwners: owners, alliedFactions: [], priorIsolatedTurns: 1)
        XCTAssertEqual(severedTurn2, .severed(isolatedTurns: 2))
        let modTurn2 = service.supplyModifiers(for: severedTurn2, factionId: .yanlong)
        XCTAssertTrue(modTurn2.isStarvingExhausted)
        XCTAssertEqual(modTurn2.nonCombatAttritionRate, 0.08, accuracy: 1e-6)
        XCTAssertEqual(modTurn2.campaignMovementMultiplier, 0.75, accuracy: 1e-6)
        XCTAssertEqual(modTurn2.battleInitialMoraleCap, 65.0, accuracy: 1e-6)

        // 若与苍狼汗国缔结正式军事同盟，借道盟友 cl_river 立即恢复 3 跳补给连通
        let alliedRestored = service.evaluateSupplyStatus(
            forNodeId: "cl_fort",
            factionId: .yanlong,
            nodeOwners: owners,
            alliedFactions: [.canglang],
            priorIsolatedTurns: 1
        )
        XCTAssertEqual(alliedRestored, .extendedMarch(hops: 3))
    }

    // MARK: - 3. 回合推进：税收、断粮第 1 回合干粮红字预警与第 2 回合 8% 饥疲非战斗逃亡减员

    func testAdvanceTurnEconomyAndTwoStageSeveredStarvationAttrition() {
        var initialState = CampaignTurnEngine.buildInitialWorldState(
            playerFaction: .yanlong,
            seed: 99,
            supplyService: CampaignSupplyService()
        )
        // 将极北非仓城节点 sy_altar（被霜原与铁鹰包围，中立无战事）设为炎龙孤立飞地，驻军 50 人
        initialState.nodesById["sy_altar"]?.owner = .yanlong
        initialState.nodesById["sy_altar"]?.garrisonUnits = [CampaignUnitStack(unitId: .shieldSwordsman, count: 50)]
        initialState.nodesById["sy_altar"]?.isolatedTurns = 0

        var engine = CampaignTurnEngine(restoredWorldState: initialState)

        // 第 1 回合结算：消耗应急干粮，触发红字预警，不发生逃亡减员
        let report1 = engine.advanceTurn()
        XCTAssertEqual(report1.resolvedTurnNumber, 1)
        XCTAssertEqual(report1.newTurnNumber, 2)
        XCTAssertGreaterThan(report1.playerGoldEarned, 0)
        XCTAssertTrue(report1.warningSeveredNodeIds.contains("sy_altar"))
        XCTAssertNil(report1.starvationAttritionByNode["sy_altar"])
        XCTAssertEqual(engine.nodeState(for: "sy_altar")?.isolatedTurns, 1)
        XCTAssertEqual(engine.nodeState(for: "sy_altar")?.totalGarrisonTroops, 50)

        // 第 2 回合仍未打通粮道：正式陷入【饥疲】，发生 8% 非战斗逃亡减员（50 * 0.08 = 4 人）
        let report2 = engine.advanceTurn()
        XCTAssertEqual(report2.newTurnNumber, 3)
        XCTAssertEqual(report2.starvationAttritionByNode["sy_altar"], 4)
        XCTAssertEqual(engine.nodeState(for: "sy_altar")?.isolatedTurns, 2)
        XCTAssertEqual(engine.nodeState(for: "sy_altar")?.totalGarrisonTroops, 46)
    }

    // MARK: - 4. 非对称募兵法则、三阶科技研发与本地存档完整快照原子回环

    func testAsymmetricRecruitmentTechResearchAndSaveLoadRoundTrip() throws {
        var engine = CampaignTurnEngine(playerFaction: .yanlong, seed: 777)

        // 炎龙帝国攻城器械造价 -20%（投石车原价 240/210/60 -> 192/168/60），苍狼汗国禁造投石车
        let yanlongTrebuchetCost = engine.effectiveRecruitmentCost(for: .trebuchet, factionId: .yanlong)
        XCTAssertEqual(yanlongTrebuchetCost, ResourceCost(gold: 192, wood: 168, grain: 60))
        XCTAssertNil(engine.effectiveRecruitmentCost(for: .trebuchet, factionId: .canglang))
        XCTAssertFalse(engine.recruitUnits(factionId: .canglang, unitId: .trebuchet, count: 1).succeeded)

        // 沙漠商盟纯金币即时征召外邦雇佣军（免木粮消耗）
        let mercCost = engine.effectiveRecruitmentCost(
            for: .shieldSwordsman,
            factionId: .shamo,
            count: 2,
            useInstantMercenaryGold: true
        )
        XCTAssertNotNil(mercCost)
        XCTAssertEqual(mercCost?.wood, 0)
        XCTAssertEqual(mercCost?.grain, 0)

        // 研发炎龙专属科技《玄铁札甲》，且防重复研发
        let goldBeforeTech = engine.factionState(for: .yanlong).gold
        let techRes = engine.researchTechnology(factionId: .yanlong, techId: "yl_tech_armor")
        XCTAssertTrue(techRes.succeeded)
        XCTAssertEqual(engine.factionState(for: .yanlong).gold, goldBeforeTech - 260)
        XCTAssertTrue(engine.factionState(for: .yanlong).unlockedTechIds.contains("yl_tech_armor"))
        XCTAssertFalse(engine.researchTechnology(factionId: .yanlong, techId: "yl_tech_armor").succeeded)

        // 临时沙箱目录完整战役快照保存与无损恢复测试
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CampaignEngineTests_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let storage = SaveStorageManager(customRootDirectoryURL: tempDir)
        let summary = try engine.saveToStorage(
            using: storage,
            slotIndex: 1,
            customTitle: "炎龙第1回合军档",
            updatedAtIso: "2026-11-17T22:00:00Z"
        )
        XCTAssertEqual(summary.slotIndex, 1)
        XCTAssertEqual(summary.controlledNodes, 5)

        let restored = try CampaignTurnEngine.loadFromStorage(using: storage, slotIndex: 1)
        XCTAssertEqual(restored.worldState, engine.worldState)
    }

    // MARK: - 5. 行军背盟强阻断、围点打援（孤城 -25 士气）、战后结算夺城与统一八王都胜利

    func testMarchBetrayalGuardReliefAmbushSettlementAndVictory() {
        var engine = CampaignTurnEngine(playerFaction: .yanlong, seed: 1024)

        // 5.1 与铁鹰王国签署互不侵犯（先送礼提升关系 >= 15），行军进攻时若未确认背盟则触发强阻断确认
        _ = engine.sendDiplomaticGift(from: .yanlong, to: .tieying, gold: 200, grain: 0)
        XCTAssertTrue(engine.signNonAggressionPact(proposer: .yanlong, target: .tieying).succeeded)

        let moveToGranary = engine.executeMarchOrder(factionId: .yanlong, toNodeId: "yl_granary")
        if case .relocatedPeacefully(let dest, _) = moveToGranary {
            XCTAssertEqual(dest, "yl_granary")
        } else {
            XCTFail("境内移防至丰穗仓城应和平完成")
        }

        let blockedMarch = engine.executeMarchOrder(
            factionId: .yanlong,
            toNodeId: "ty_fort",
            confirmBetrayalIfNeeded: false
        )
        if case .requiresWarConfirmation(let assessment, let target) = blockedMarch {
            XCTAssertTrue(assessment.isBetrayalTriggered)
            XCTAssertEqual(target, .tieying)
        } else {
            XCTFail("撕毁互不侵犯条约进军应先返回二次确认阻断提示")
        }

        // 5.2 向苍狼汗国正式宣战，实施【围点打援】：围困牧马滩（cl_pasture），于白狼山口（cl_pass）设伏打援
        let warImpact = engine.declareWar(attacker: .yanlong, target: .canglang)
        XCTAssertFalse(warImpact.isBetrayalTriggered)

        let ambushSetup = engine.setupReliefAmbush(
            factionId: .yanlong,
            ambushNodeId: "cl_pass",
            besiegedTargetNodeId: "cl_pasture"
        )
        XCTAssertTrue(ambushSetup.succeeded)
        XCTAssertEqual(engine.nodeState(for: "cl_pasture")?.underSiegeBy, .yanlong)

        // 打援伏击大捷后，被围孤城 cl_pasture 守军士气直接暴跌 -25
        let ambushWin = PostBattleSettlementSummary(
            scenarioType: .ambush,
            playerFaction: .yanlong,
            enemyFaction: .canglang,
            isVictory: true,
            outcomeReason: .enemyArmyRouted,
            playerKilled: 8,
            playerWoundedRecovered: 5,
            enemyKilled: 65,
            capturedPrisoners: 15,
            lootedGold: 120,
            lootedWood: 60,
            lootedGrain: 150,
            commanderExpGained: 520
        )
        let credBeforeRansom = engine.factionState(for: .yanlong).credibility
        engine.applyPostBattleSettlement(
            ambushWin,
            prisonerDisposition: .ransomForGoldAndCredibility,
            explicitTargetNodeId: "cl_pass"
        )
        XCTAssertEqual(engine.nodeState(for: "cl_pasture")?.garrisonMoraleModifier, -25.0, accuracy: 1e-6)
        XCTAssertEqual(engine.factionState(for: .yanlong).credibility, min(100, credBeforeRansom + 2))
        XCTAssertEqual(engine.factionState(for: .yanlong).commanderLevel, 2, "满 500 EXP 应晋升主帅统御等级")

        // 5.3 主帅二次阵亡战败结算 -> 挂 2 回合【重伤休养】
        let martyrDefeat = PostBattleSettlementSummary(
            scenarioType: .fieldPitched,
            playerFaction: .yanlong,
            enemyFaction: .canglang,
            isVictory: false,
            outcomeReason: .playerCommanderMartyred,
            playerKilled: 12,
            playerWoundedRecovered: 4,
            enemyKilled: 20,
            capturedPrisoners: 0,
            lootedGold: 0,
            lootedWood: 0,
            lootedGrain: 0,
            commanderExpGained: 80
        )
        engine.applyPostBattleSettlement(martyrDefeat)
        XCTAssertEqual(engine.factionState(for: .yanlong).commanderWoundedTurns, 2)

        // 5.4 当玩家夺取全部 8 座初始王都巨城时触发【统一王都胜利】
        var unifyState = engine.worldState
        for capId in FactionConfig.allFactions.map(\.capitalNodeId) {
            unifyState.nodesById[capId]?.owner = .yanlong
        }
        var unifyEngine = CampaignTurnEngine(restoredWorldState: unifyState)
        unifyEngine.evaluateEliminationsAndVictoryStatus()
        XCTAssertEqual(unifyEngine.worldState.victoryStatus, .capitalUnificationVictory(winner: .yanlong))
    }
}
