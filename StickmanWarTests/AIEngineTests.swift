// ============================================================================
// 文件：AIEngineTests.swift
// 模块：Core/AI 分层战术与战略 AI 引擎专用单元测试（XCTest）
// 覆盖：L2 战场黑板 AI 锤砧两翼包抄、反风筝单队驱离（主力绝不盲追）、
//       防线危急/敌动摇时总预备队决胜投入、敌帅落马 15s 指挥瘫痪冻结、
//       铁鹰高地刺猬防反、雾林诈败诱敌设伏、攻守城专项三段式状态机（含无投石防死锁）、
//       L1 战略大地图 AI 两线作战规避求和（血月狂热例外）与 >=13 城反霸权合纵制衡。
//
// 在 Mac 上的运行方式（当前 Linux 开发机无 Xcode / macOS，未在本机跑过）：
//   方式一（Xcode GUI）：打开 `StickmanWar.xcodeproj`，选择 `StickmanWar` Scheme，按 `Cmd+U`（⌘U）运行全部测试。
//   方式二（命令行）：在工程根目录执行：
//     xcodebuild test \
//       -project StickmanWar.xcodeproj \
//       -scheme StickmanWar \
//       -destination 'platform=macOS,arch=arm64' \
//       -only-testing:StickmanWarTests/AIEngineTests
// ============================================================================

import Foundation
import XCTest
@testable import StickmanWar

final class AIEngineTests: XCTestCase {

    // MARK: - 辅助构造：标准敌我多军团测试战场列表

    private func makeTestSquad(
        id: Int,
        side: BattleSide,
        faction: FactionId,
        role: ArmyCorpsRole,
        unitType: UnitTypeId,
        x: Double,
        y: Double,
        aliveCount: Int = 12,
        morale: Double = GameConstants.moraleBase
    ) -> BattleSquadState {
        var sq = BattleSquadState(
            id: id,
            side: side,
            faction: faction,
            corpsRole: role,
            primaryUnitType: unitType,
            formation: .phalanxRect,
            order: .holdGround,
            anchorX: x,
            anchorY: y,
            facingRadians: side == .player ? 0.0 : Double.pi,
            morale: morale
        )
        sq.initialCount = aliveCount
        sq.aliveCount = aliveCount
        return sq
    }

    // MARK: - 1. L2 锤砧包抄协同与反风筝单队驱离纪律（主力前锋绝不跟追单骑主帅）

    func testL2BattleTacticalAIHammerAnvilAndAntiKiteDiscipline() {
        var ai = BattleTacticalAI()
        var squads: [BattleSquadState] = [
            makeTestSquad(id: 0, side: .player, faction: .yanlong, role: .vanguardCenter, unitType: .shieldSwordsman, x: 1400.0, y: 1200.0),
            makeTestSquad(id: 1, side: .player, faction: .yanlong, role: .siegeBattery, unitType: .compositeArcher, x: 1150.0, y: 1200.0),
            makeTestSquad(id: 2, side: .enemy, faction: .xuanjia, role: .vanguardCenter, unitType: .shieldSwordsman, x: 3400.0, y: 1200.0),
            makeTestSquad(id: 3, side: .enemy, faction: .xuanjia, role: .leftWing, unitType: .xuanjiaCataphract, x: 3450.0, y: 500.0),
            makeTestSquad(id: 4, side: .enemy, faction: .xuanjia, role: .rightWing, unitType: .lightCavalry, x: 3450.0, y: 1900.0),
            makeTestSquad(id: 5, side: .enemy, faction: .xuanjia, role: .rearReserve, unitType: .xuanjiaCataphract, x: 3800.0, y: 1200.0)
        ]

        let farPlayerHero = HeroCommanderEntity(side: .player, faction: .yanlong, spawnX: 1350.0, spawnY: 1200.0, facingRadians: 0.0)
        let aiHero = HeroCommanderEntity(side: .enemy, faction: .xuanjia, spawnX: 3600.0, spawnY: 1200.0, facingRadians: Double.pi)

        // 1.1 常规会战：前锋稳步抗线（砧），两翼骑兵大弧线钳形合围（锤），总预备队扣留按兵不动
        ai.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .xuanjia,
            scenarioType: .fieldPitched,
            elapsedSeconds: 8.0,
            worldWidth: 4800.0,
            worldHeight: 2400.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: farPlayerHero,
            aiHero: aiHero,
            squads: &squads,
            soldiers: [],
            structures: [],
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertEqual(ai.blackboard.activeDoctrine, .hammerAndAnvil)
        XCTAssertFalse(ai.blackboard.reserveCommitted)
        XCTAssertEqual(squads[2].order, .advance)
        XCTAssertEqual(squads[3].order, .pincerEncircle)
        XCTAssertEqual(squads[4].order, .pincerEncircle)
        XCTAssertFalse(squads[3].waypoints.isEmpty, "北翼骑兵应生成北走廊大弧线迂回航点")
        XCTAssertEqual(squads[5].order, .holdGround, "未到决胜时刻总预备队必须扣留待命")

        // 1.2 玩家主帅孤身越线风筝（距友军 >240px 且逼近 AI <520px）：仅单派 1 支侧翼驱离，前锋与另一翼绝不跟着跑
        let kitingHero = HeroCommanderEntity(side: .player, faction: .yanlong, spawnX: 3050.0, spawnY: 920.0, facingRadians: 0.0)
        ai.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .xuanjia,
            scenarioType: .fieldPitched,
            elapsedSeconds: 10.0,
            worldWidth: 4800.0,
            worldHeight: 2400.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: kitingHero,
            aiHero: aiHero,
            squads: &squads,
            soldiers: [],
            structures: [],
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertTrue(ai.blackboard.detectedPlayerHeroKiting)
        XCTAssertEqual(ai.blackboard.activeDoctrine, .antiKiteEscort)

        let squadsChasingHero = squads.filter {
            $0.side == .enemy && abs($0.targetX - kitingHero.x) < 1.0 && abs($0.targetY - kitingHero.y) < 1.0
        }
        XCTAssertEqual(squadsChasingHero.count, 1, "反风筝机制仅允许单支机动侧翼驱离玩家主帅，严禁全军傻追")
        XCTAssertNotEqual(squads[2].targetX, kitingHero.x, "AI 中军前锋必须继续压迫玩家主力阵线")
    }

    // MARK: - 2. 总预备队关键投入、敌帅落马 15s 指挥瘫痪、铁鹰刺猬防反与雾林诈败设伏

    func testL2ReserveCommitmentParalysisHedgehogAndFeignedRetreat() {
        var ai = BattleTacticalAI()
        var squads: [BattleSquadState] = [
            makeTestSquad(id: 0, side: .player, faction: .yanlong, role: .vanguardCenter, unitType: .shieldSwordsman, x: 2000.0, y: 1200.0),
            makeTestSquad(id: 1, side: .enemy, faction: .yanlong, role: .vanguardCenter, unitType: .shieldSwordsman, x: 2400.0, y: 1200.0, morale: 30.0),
            makeTestSquad(id: 2, side: .enemy, faction: .yanlong, role: .rearReserve, unitType: .yanlongHalberdGrenadier, x: 3100.0, y: 1200.0)
        ]
        let pHero = HeroCommanderEntity(side: .player, faction: .yanlong, spawnX: 1900.0, spawnY: 1200.0, facingRadians: 0.0)
        let eHero = HeroCommanderEntity(side: .enemy, faction: .yanlong, spawnX: 3000.0, spawnY: 1200.0, facingRadians: Double.pi)

        // 2.1 敌帅落马 15s 指挥瘫痪期间：无法切换条令，也无法投入总预备队
        ai.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .yanlong,
            scenarioType: .fieldPitched,
            elapsedSeconds: 20.0,
            worldWidth: 4800.0,
            worldHeight: 2400.0,
            commandParalysisTimer: 12.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &squads,
            soldiers: [],
            structures: [],
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertFalse(ai.blackboard.reserveCommitted, "指挥瘫痪期内 AI 不得投入总预备队")
        XCTAssertEqual(squads[2].order, .holdGround)

        // 2.2 指挥瘫痪结束后，检测到己方前锋士气 30 < 35 -> 立即投入总预备队堵口
        ai.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .yanlong,
            scenarioType: .fieldPitched,
            elapsedSeconds: 21.0,
            worldWidth: 4800.0,
            worldHeight: 2400.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &squads,
            soldiers: [],
            structures: [],
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertTrue(ai.blackboard.reserveCommitted)
        XCTAssertEqual(ai.blackboard.activeDoctrine, .reserveBreakthrough)
        XCTAssertEqual(squads[2].order, .advance)
        XCTAssertEqual(squads[2].targetX, squads[1].anchorX, accuracy: 1e-6)

        // 2.3 铁鹰王国存在制高点时采用高地刺猬防反（highGroundHedgehog）
        var tieyingAI = BattleTacticalAI()
        var tieyingSquads = [
            makeTestSquad(id: 0, side: .player, faction: .canglang, role: .vanguardCenter, unitType: .lightCavalry, x: 1500.0, y: 1200.0),
            makeTestSquad(id: 1, side: .enemy, faction: .tieying, role: .vanguardCenter, unitType: .pikeman, x: 3300.0, y: 1200.0),
            makeTestSquad(id: 2, side: .enemy, faction: .tieying, role: .siegeBattery, unitType: .tieyingPaviseCrossbow, x: 3450.0, y: 1200.0)
        ]
        let hillZones = [TerrainZoneRect(id: 1, terrain: .highGround, minX: 3100.0, maxX: 3500.0, minY: 950.0, maxY: 1450.0, elevationLevel: 2)]
        tieyingAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .tieying,
            scenarioType: .fieldPitched,
            elapsedSeconds: 6.0,
            worldWidth: 4800.0,
            worldHeight: 2400.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &tieyingSquads,
            soldiers: [],
            structures: [],
            terrainZones: hillZones,
            resourceNodes: []
        )
        XCTAssertEqual(tieyingAI.blackboard.activeDoctrine, .highGroundHedgehog)
        XCTAssertEqual(tieyingSquads[1].order, .holdGround)
        XCTAssertEqual(tieyingSquads[2].order, .holdGround)

        // 2.4 雾林猎手开战 20s 触发诈败诱敌入林伏击（feignedRetreatAmbush）
        var wulinAI = BattleTacticalAI()
        var wulinSquads = [
            makeTestSquad(id: 0, side: .player, faction: .yanlong, role: .vanguardCenter, unitType: .shieldSwordsman, x: 1600.0, y: 1200.0),
            makeTestSquad(id: 1, side: .enemy, faction: .wulin, role: .vanguardCenter, unitType: .pikeman, x: 3000.0, y: 1200.0),
            makeTestSquad(id: 2, side: .enemy, faction: .wulin, role: .leftWing, unitType: .wulinShadowSniper, x: 3200.0, y: 500.0)
        ]
        let forestZones = [TerrainZoneRect(id: 2, terrain: .denseForest, minX: 2900.0, maxX: 3500.0, minY: 200.0, maxY: 800.0, elevationLevel: 1)]
        wulinAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .wulin,
            scenarioType: .fieldPitched,
            elapsedSeconds: 20.0,
            worldWidth: 4800.0,
            worldHeight: 2400.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &wulinSquads,
            soldiers: [],
            structures: [],
            terrainZones: forestZones,
            resourceNodes: []
        )
        XCTAssertEqual(wulinAI.blackboard.activeDoctrine, .feignedRetreatAmbush)
        XCTAssertEqual(wulinSquads[1].order, .feignedRetreat)
        XCTAssertEqual(wulinSquads[2].order, .ambushHide)
    }

    // MARK: - 3. 攻城与守城三段式专项战术状态机（含投石车全毁防卡死切换）

    func testL2SiegeThreePhaseStateMachineForAttackerAndDefender() {
        let pHero = HeroCommanderEntity(side: .player, faction: .tieying, spawnX: 900.0, spawnY: 1300.0, facingRadians: 0.0)
        let eHero = HeroCommanderEntity(side: .enemy, faction: .yanlong, spawnX: 4400.0, spawnY: 1300.0, facingRadians: Double.pi)

        // 3.1 AI 作为攻城方（scenarioType = .siegeDefense，玩家守城，enemy 攻城）
        var attackerAI = BattleTacticalAI()
        var attackerSquads = [
            makeTestSquad(id: 0, side: .player, faction: .tieying, role: .vanguardCenter, unitType: .shieldSwordsman, x: 1100.0, y: 1300.0),
            makeTestSquad(id: 1, side: .enemy, faction: .yanlong, role: .vanguardCenter, unitType: .greatAxeman, x: 2400.0, y: 1300.0),
            makeTestSquad(id: 2, side: .enemy, faction: .yanlong, role: .siegeBattery, unitType: .trebuchet, x: 2600.0, y: 1300.0, aliveCount: 3),
            makeTestSquad(id: 3, side: .enemy, faction: .yanlong, role: .rearReserve, unitType: .yanlongHalberdGrenadier, x: 2800.0, y: 1300.0)
        ]
        var siegeStructures = [
            SiegeStructureEntity(id: 0, side: .player, kind: .mainGate, x: 1620.0, y: 1300.0, width: 72.0, height: 220.0, hp: 1850.0),
            SiegeStructureEntity(id: 1, side: .player, kind: .arrowTower, x: 1620.0, y: 1100.0, width: 76.0, height: 76.0, hp: 1100.0),
            SiegeStructureEntity(id: 2, side: .player, kind: .sideSallyGate, x: 1620.0, y: 2200.0, width: 68.0, height: 150.0, hp: 1150.0)
        ]

        // 阶段 1：投石车与敌方箭塔/城门健在 -> 炮火准备拆塔
        attackerAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .yanlong,
            scenarioType: .siegeDefense,
            elapsedSeconds: 5.0,
            worldWidth: 5600.0,
            worldHeight: 2600.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &attackerSquads,
            soldiers: [],
            structures: siegeStructures,
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertEqual(attackerAI.blackboard.siegePhase, .attackerArtilleryPrep)

        // 阶段 2（防死锁边界）：投石车全部被毁而城门未破 -> 立即转入多点云梯登城 + 巨斧劈门
        attackerSquads[2].aliveCount = 0
        attackerAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .yanlong,
            scenarioType: .siegeDefense,
            elapsedSeconds: 12.0,
            worldWidth: 5600.0,
            worldHeight: 2600.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &attackerSquads,
            soldiers: [],
            structures: siegeStructures,
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertEqual(attackerAI.blackboard.siegePhase, .attackerMultiLadder)
        XCTAssertEqual(attackerSquads[1].order, .advance)

        // 阶段 3：正门轰破 -> 投入总预备队全军突击瓮城
        siegeStructures[0].isDestroyed = true
        siegeStructures[0].hp = 0.0
        attackerAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .yanlong,
            scenarioType: .siegeDefense,
            elapsedSeconds: 25.0,
            worldWidth: 5600.0,
            worldHeight: 2600.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &attackerSquads,
            soldiers: [],
            structures: siegeStructures,
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertEqual(attackerAI.blackboard.siegePhase, .attackerBreachExploit)
        XCTAssertTrue(attackerAI.blackboard.reserveCommitted)
        XCTAssertEqual(attackerSquads[3].order, .allOutCharge)

        // 3.2 AI 作为守城方（scenarioType = .siegeAssault，玩家攻城，enemy 守城）
        var defenderAI = BattleTacticalAI()
        var defenderSquads = [
            makeTestSquad(id: 0, side: .player, faction: .yanlong, role: .vanguardCenter, unitType: .shieldSwordsman, x: 2400.0, y: 1300.0),
            makeTestSquad(id: 1, side: .player, faction: .yanlong, role: .siegeBattery, unitType: .trebuchet, x: 2200.0, y: 1300.0, aliveCount: 3),
            makeTestSquad(id: 2, side: .enemy, faction: .tieying, role: .vanguardCenter, unitType: .pikeman, x: 4100.0, y: 1300.0),
            makeTestSquad(id: 3, side: .enemy, faction: .tieying, role: .rightWing, unitType: .lightCavalry, x: 4150.0, y: 2100.0),
            makeTestSquad(id: 4, side: .enemy, faction: .tieying, role: .rearReserve, unitType: .shieldSwordsman, x: 4300.0, y: 1300.0)
        ]
        var enemyWallStructures = [
            SiegeStructureEntity(id: 0, side: .enemy, kind: .mainGate, x: 3980.0, y: 1300.0, width: 72.0, height: 220.0, hp: 1850.0),
            SiegeStructureEntity(id: 1, side: .enemy, kind: .sideSallyGate, x: 3980.0, y: 2300.0, width: 68.0, height: 150.0, hp: 1150.0)
        ]

        // 守城阶段 1：攻方尚远 -> 城头集火
        defenderAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .tieying,
            scenarioType: .siegeAssault,
            elapsedSeconds: 5.0,
            worldWidth: 5600.0,
            worldHeight: 2600.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &defenderSquads,
            soldiers: [],
            structures: enemyWallStructures,
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertEqual(defenderAI.blackboard.siegePhase, .defenderWallFocusFire)

        // 守城阶段 3：攻方携投石车逼近城下且城门尚稳 -> 侧门派轻骑出击奇袭投石车
        defenderSquads[0].anchorX = 3700.0
        defenderSquads[1].anchorX = 3550.0
        defenderAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .tieying,
            scenarioType: .siegeAssault,
            elapsedSeconds: 15.0,
            worldWidth: 5600.0,
            worldHeight: 2600.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &defenderSquads,
            soldiers: [],
            structures: enemyWallStructures,
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertEqual(defenderAI.blackboard.siegePhase, .defenderSallyDestroySiege)
        XCTAssertEqual(defenderSquads[3].order, .raidSupply)

        // 守城阶段 2：城门耐久跌破 30% -> 调预备队门洞结圆阵/方阵死堵缺口
        enemyWallStructures[0].hp = 400.0
        defenderAI.stepAI(
            deltaTime: 0.55,
            aiSide: .enemy,
            aiFaction: .tieying,
            scenarioType: .siegeAssault,
            elapsedSeconds: 30.0,
            worldWidth: 5600.0,
            worldHeight: 2600.0,
            commandParalysisTimer: 0.0,
            opponentGarrisonBellActive: false,
            opponentHero: pHero,
            aiHero: eHero,
            squads: &defenderSquads,
            soldiers: [],
            structures: enemyWallStructures,
            terrainZones: [],
            resourceNodes: []
        )
        XCTAssertEqual(defenderAI.blackboard.siegePhase, .defenderGatePlugPhalanx)
        XCTAssertEqual(defenderSquads[4].formation, .circleDefense)
    }

    // MARK: - 4. L1 战略大地图 AI 两线作战规避（血月狂热例外）与 >=13 城反霸权合纵

    func testL1StrategicCampaignAITwoFrontAvoidanceAndAntiHegemony() {
        var world = StrategicCampaignWorldState()

        // 令炎龙帝国同时与苍狼汗国、铁鹰王国处于两线交战
        let keyYanlongCanglang = StrategicCampaignWorldState.pairKey(.yanlong, .canglang)
        let keyYanlongTieying = StrategicCampaignWorldState.pairKey(.yanlong, .tieying)
        world.diplomacyMap[keyYanlongCanglang] = BilateralDiplomacyState(factionA: .canglang, factionB: .yanlong, relation: -65, status: .war)
        world.diplomacyMap[keyYanlongTieying] = BilateralDiplomacyState(factionA: .tieying, factionB: .yanlong, relation: -55, status: .war)

        let strategicAI = StrategicCampaignAI(worldState: world)
        let yanlongDecisions = strategicAI.evaluateStructuredDecisions(
            for: .yanlong,
            personality: .imperialMethodical,
            in: world
        )
        XCTAssertTrue(
            yanlongDecisions.contains { $0.kind == .proposePeaceSecondary },
            "常规理性 AI 在双线受敌时必须主动向次要战线派使求和"
        )

        // 血月祭司团（zealotSwarm）初始即与多方交战，狂热性格不触发两线退缩求和
        let xueyueDecisions = strategicAI.evaluateStructuredDecisions(
            for: .xueyue,
            personality: .zealotSwarm,
            in: world
        )
        XCTAssertFalse(
            xueyueDecisions.contains { $0.kind == .proposePeaceSecondary },
            "狂热扩张型血月祭司团不应触发常规两线规避求和"
        )

        // 反霸权合纵制衡：令炎龙扩张至 13 座城关（达到 antiHegemonyNodeThreshold = 13）
        var hegemonWorld = StrategicCampaignWorldState()
        let extraNodesForYanlong = ["cl_river", "cl_pasture", "xj_plain", "xj_pass", "xy_ferry", "wl_sentry", "sm_post", "ty_bridge"]
        for nid in extraNodesForYanlong {
            hegemonWorld.nodeOwners[nid] = .yanlong
        }
        XCTAssertEqual(hegemonWorld.controlledNodeCount(for: .yanlong), 13)
        XCTAssertEqual(hegemonWorld.detectHegemonFaction(), .yanlong)

        // 铁鹰王国与接壤邻国霜原熊族（初始关系 0，获 +25 共同威胁修正后达 +25 >= 15）触发反霸权合纵缔约
        let tieyingAntiHegemon = strategicAI.evaluateStructuredDecisions(
            for: .tieying,
            personality: .fortressCounter,
            in: hegemonWorld
        )
        XCTAssertTrue(
            tieyingAntiHegemon.contains { $0.kind == .formAntiHegemonyPact },
            "存在 >=13 城霸权势力时，受威胁邻国应优先触发反霸权合纵缔盟"
        )
    }
}
