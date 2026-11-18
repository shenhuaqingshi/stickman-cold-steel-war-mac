// ============================================================================
// 文件：FullFlowIntegrationTests.swift
// 模块：7 大页面路由、战前整军 -> SpriteKit 大战场 -> 战后结算 -> 战略大地图/外交 -> 本地存档/设置 全流程集成单测
//
// 在 Mac 上的运行方式（当前 Linux 开发机无 Xcode / macOS，未在本机跑过）：
//   方式一（Xcode GUI）：打开 `StickmanWar.xcodeproj`，选择 `StickmanWar` Scheme，按 `Cmd+U`（⌘U）运行全部测试。
//   方式二（命令行）：在工程根目录执行：
//     xcodebuild test \
//       -project StickmanWar.xcodeproj \
//       -scheme StickmanWar \
//       -destination 'platform=macOS,arch=arm64' \
//       -only-testing:StickmanWarTests/FullFlowIntegrationTests
// ============================================================================

import Foundation
import XCTest
@testable import StickmanWar

@MainActor
final class FullFlowIntegrationTests: XCTestCase {

    // MARK: - 1. 主菜单 -> 战前整军 -> SpriteKit 大战场双视角操控 -> 战后结算完整闭环

    func testMainMenuToPreBattleToBattlefieldSceneAndResultClosedLoop() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("StickmanWarFlow_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let router = AppRouter(storageManager: SaveStorageManager(customRootDirectoryURL: tempDir))
        XCTAssertEqual(router.currentRoute, .mainMenu)

        // 1. 从主菜单选择苍狼汗国开启遭遇战 -> 路由跳转至战前整军页
        router.startMode(.skirmish, playerFaction: .canglang)
        XCTAssertEqual(router.currentRoute, .preBattleSetup)
        XCTAssertEqual(router.launchContext.playerFaction, .canglang)
        XCTAssertFalse(router.setupPlayerRoster.contains { $0.unitType == .trebuchet }, "苍狼汗国默认编组严禁包含配重投石车")

        // 2. 从战前整军页开拔进入 SpriteKit 战场宿主
        router.launchBattlefieldFromSetup()
        XCTAssertEqual(router.currentRoute, .battlefield)

        let scene = BattlefieldSKScene(context: router.launchContext, deployment: router.pendingBattleDeployment)
        XCTAssertEqual(scene.worldWidth, GameConstants.battlefieldWidth)
        XCTAssertEqual(scene.worldHeight, GameConstants.battlefieldHeight)
        XCTAssertFalse(scene.selectedSquadIds.isEmpty, "开战应默认选中主力前锋供右键即时指挥")

        // 3. 验证 RTS 阵型/侧翼包抄指令与 Tab 切入主帅亲自上阵释放战技
        scene.applyFormationToSelection(.wedgeCharge)
        scene.applyTacticalOrderToSelection(.flank)
        XCTAssertTrue(scene.requestToggleControlMode())
        XCTAssertEqual(scene.controlMode, .heroAction)
        scene.switchHeroWeapon(.breakerSpear)
        XCTAssertEqual(scene.engine.playerHero.activeWeapon, .breakerSpear)
        scene.triggerHeroSkill(.grandWarCry)
        XCTAssertGreaterThan(scene.engine.playerHero.grandWarCryCooldown, 0.0)

        // 4. 生成真实战后结算摘要并流转至结算页，最后返回主菜单
        let summary = scene.concludeBattleByTruceAndSummarize()
        router.completeBattleAndShowResult(summary)
        XCTAssertEqual(router.currentRoute, .battleResult)
        XCTAssertEqual(router.latestSettlement.outcomeReason, .truceNegotiated)

        router.returnToMainMenu()
        XCTAssertEqual(router.currentRoute, .mainMenu)
    }

    // MARK: - 2. 战役大地图 -> 外交/宣战/行军 -> 战场夺城回写 -> 本地军档存取与偏好设置持久化

    func testCampaignDiplomacyMarchSettlementSaveLoadAndSettingsPersistence() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("StickmanWarCampaignFlow_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = SaveStorageManager(customRootDirectoryURL: tempDir)
        let router = AppRouter(storageManager: storage)

        // 1. 开启炎龙帝国新战役进入 40 城关大地图
        router.startMode(.campaign, playerFaction: .yanlong, forceNewCampaign: true)
        XCTAssertEqual(router.currentRoute, .campaignMap)
        XCTAssertEqual(router.campaignEngine.controlledNodes(of: .yanlong).count, 5)

        // 2. 外交测试：与沙漠商盟馈赠结好并签署丝路通商协定
        XCTAssertTrue(router.campaignEngine.sendDiplomaticGift(from: .yanlong, to: .shamo, gold: 150, grain: 0).succeeded)
        XCTAssertTrue(router.campaignEngine.signTradePact(proposer: .yanlong, target: .shamo).succeeded)

        // 3. 将主力移防至赤壁雄关（yl_pass），向相邻苍狼饮马河营（cl_river）发起进军
        let moveRes = router.campaignEngine.executeMarchOrder(factionId: .yanlong, toNodeId: "yl_pass")
        if case .relocatedPeacefully(let dest, _) = moveRes {
            XCTAssertEqual(dest, "yl_pass")
        } else {
            XCTFail("境内移防至赤壁雄关应成功")
        }

        let attackRes = router.campaignEngine.executeMarchOrder(factionId: .yanlong, toNodeId: "cl_river")
        guard case .battleTriggered(let ctx, let mods) = attackRes else {
            XCTFail("跨境进攻饮马河营应触发会战")
            return
        }
        router.enterCampaignPreBattle(context: ctx, modifiers: mods)
        XCTAssertEqual(router.currentRoute, .preBattleSetup)
        router.launchBattlefieldFromSetup()
        XCTAssertEqual(router.currentRoute, .battlefield)
        XCTAssertFalse(router.pendingBattleDeployment.applySupplyGrainDiscountInEngine, "战役已折算携粮进入战场后不得二次重复扣减")

        // 4. 模拟大捷夺下饮马河营并回写大地图态势（5 城 -> 6 城）
        let winSummary = PostBattleSettlementSummary(
            scenarioType: ctx.scenarioType,
            playerFaction: .yanlong,
            enemyFaction: .canglang,
            isVictory: true,
            outcomeReason: .enemyArmyRouted,
            durationSeconds: 142,
            playerKilled: 9,
            playerWoundedRecovered: 6,
            enemyKilled: 74,
            capturedPrisoners: 16,
            lootedGold: 220,
            lootedWood: 110,
            lootedGrain: 260,
            commanderExpGained: 540
        )
        router.completeBattleAndShowResult(winSummary)
        XCTAssertEqual(router.currentRoute, .battleResult)
        router.applyCampaignSettlementAndReturn(prisonerChoice: .ransomForGoldAndCredibility)
        XCTAssertEqual(router.currentRoute, .campaignMap)
        XCTAssertEqual(router.campaignEngine.nodeState(for: "cl_river")?.owner, .yanlong)
        XCTAssertEqual(router.campaignEngine.controlledNodes(of: .yanlong).count, 6)

        // 5. 本地存档页（路由 6）保存槽位 #2，切换为其它势力后再读档无损恢复 6 城进度
        router.navigate(to: .saveLoad)
        XCTAssertEqual(router.currentRoute, .saveLoad)
        router.saveCurrentCampaignSnapshot(toSlot: 2, customTitle: "炎龙夺取饮马河营")
        XCTAssertFalse(router.saveSlots[2].isEmpty)
        XCTAssertEqual(router.saveSlots[2].controlledNodes, 6)

        router.startMode(.campaign, playerFaction: .shuangyuan, forceNewCampaign: true)
        XCTAssertEqual(router.campaignEngine.worldState.playerFaction, .shuangyuan)

        XCTAssertTrue(router.loadCampaignFromSlot(2))
        XCTAssertEqual(router.currentRoute, .campaignMap)
        XCTAssertEqual(router.campaignEngine.worldState.playerFaction, .yanlong)
        XCTAssertEqual(router.campaignEngine.controlledNodes(of: .yanlong).count, 6)

        // 6. 设置页（路由 7）修改并持久化用户设置，重新构造路由器验证落盘生效
        router.navigate(to: .settings)
        XCTAssertEqual(router.currentRoute, .settings)
        router.userSettings.targetFps = 30
        router.userSettings.invertScrollZoom = true
        router.userSettings.showDamageNumbers = false
        router.persistUserSettings()

        let freshRouter = AppRouter(storageManager: storage)
        XCTAssertEqual(freshRouter.userSettings.targetFps, 30)
        XCTAssertTrue(freshRouter.userSettings.invertScrollZoom)
        XCTAssertFalse(freshRouter.userSettings.showDamageNumbers)
    }
}
