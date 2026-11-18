// ============================================================================
// 文件：StickmanWarSkeletonTests.swift
// 模块：工程骨架、静态配置、40 节点 / 78 道路拓扑、开局经济 [1415, 1510] 配平与离线存档单测
//
// 在 Mac 上的运行方式（当前 Linux 开发机无 Xcode / macOS，未在本机跑过）：
//   方式一（Xcode GUI）：打开 `StickmanWar.xcodeproj`，选择 `StickmanWar` Scheme，按 `Cmd+U`（⌘U）运行全部单元测试。
//   方式二（命令行）：在工程根目录执行：
//     xcodebuild test \
//       -project StickmanWar.xcodeproj \
//       -scheme StickmanWar \
//       -destination 'platform=macOS,arch=arm64'
//     （若仅运行本测试类，可追加 `-only-testing:StickmanWarTests/StickmanWarSkeletonTests`）
// ============================================================================

import Foundation
import XCTest
@testable import StickmanWar

/// 工程骨架、16 兵种、8 势力、40 城关 / 78 道路拓扑、边界常量与离线存档一致性单元测试（XCTest）
final class StickmanWarSkeletonTests: XCTestCase {

    // MARK: - 1. 战场与大地图尺寸及 7 大路由完备性断言

    func testBattlefieldAndCampaignDimensionsMeetSpec() {
        XCTAssertGreaterThanOrEqual(GameConstants.battlefieldWidth, 4000.0)
        XCTAssertGreaterThanOrEqual(GameConstants.battlefieldHeight, 2000.0)
        XCTAssertEqual(GameConstants.battlefieldWidth, 4800.0)
        XCTAssertEqual(GameConstants.battlefieldHeight, 2400.0)
        XCTAssertEqual(GameConstants.siegeBattlefieldWidth, 5600.0)
        XCTAssertEqual(GameConstants.siegeBattlefieldHeight, 2600.0)

        XCTAssertEqual(GameConstants.campaignMapWidth, 3600.0)
        XCTAssertEqual(GameConstants.campaignMapHeight, 2400.0)
        XCTAssertEqual(GameConstants.campaignRegionCount, 8)
        XCTAssertEqual(GameConstants.campaignNodeCount, 40)
        XCTAssertEqual(GameConstants.campaignRoadCount, 78, "战役大地图权威道路数必须精确等于 78 条")
        XCTAssertEqual(CampaignMapConfig.allRoadEdges.count, 78, "CampaignMapConfig 实际去重无向道路数必须精确等于 78 条，防止与常量脱节")
        XCTAssertEqual(AppRoute.allCases.count, 7, "核心业务路由必须严格包含 7 个页面")
    }

    // MARK: - 2. 八大势力非对称配置、专属兵种双向映射与初始外交规则断言

    func testEightFactionsIntegrityAndBidirectionalExclusiveUnits() {
        XCTAssertEqual(FactionConfig.allFactions.count, 8)
        var seenColors = Set<String>()
        var seenCapitals = Set<String>()

        for faction in FactionConfig.allFactions {
            XCTAssertNotNil(FactionConfig.config(for: faction.id))
            XCTAssertTrue(seenColors.insert(faction.primaryColorHex).inserted, "势力主色不可重复：\(faction.name)")
            XCTAssertTrue(seenCapitals.insert(faction.capitalNodeId).inserted, "势力王都不可重复：\(faction.name)")
            XCTAssertEqual(faction.uniqueTechs.count, 3, "\(faction.name) 必须拥有三阶专属科技")
            XCTAssertTrue((0...100).contains(faction.startingCredibility))

            // 专属王牌兵种双向唯一绑定验证
            guard let exclusiveUnit = UnitConfig.stats(for: faction.exclusiveUnitId) else {
                XCTFail("找不到 \(faction.name) 的专属王牌兵种 \(faction.exclusiveUnitId)")
                continue
            }
            XCTAssertEqual(exclusiveUnit.exclusiveFaction, faction.id)

            // 王都必须真实存在于大地图且初始归属本势力、具备核心仓城资格
            guard let capitalNode = CampaignMapConfig.node(byId: faction.capitalNodeId) else {
                XCTFail("找不到王都节点 \(faction.capitalNodeId)")
                continue
            }
            XCTAssertEqual(capitalNode.initialOwner, faction.id)
            XCTAssertEqual(capitalNode.nodeType, .capitalCitadel)
            XCTAssertTrue(capitalNode.isSupplyDepot)
        }

        // 验证血月祭司团与正统诸侯初始关系 -15
        XCTAssertEqual(FactionConfig.initialRelation(between: .xueyue, and: .yanlong), -15)
        XCTAssertEqual(FactionConfig.initialRelation(between: .xueyue, and: .tieying), -15)
    }

    // MARK: - 3. 16 种兵种（8 通用 + 8 专属）数值正定性与苍狼禁投石车法则断言

    func testSixteenUnitsPositiveStatsAndCanglangRestriction() {
        XCTAssertEqual(UnitConfig.allUnits.count, 16)
        let universalCount = UnitConfig.allUnits.filter { $0.exclusiveFaction == nil }.count
        let exclusiveCount = UnitConfig.allUnits.filter { $0.exclusiveFaction != nil }.count
        XCTAssertEqual(universalCount, 8)
        XCTAssertEqual(exclusiveCount, 8)

        for unit in UnitConfig.allUnits {
            XCTAssertGreaterThan(unit.hp, 0)
            XCTAssertGreaterThan(unit.attack, 0)
            XCTAssertGreaterThan(unit.armorPenetration, 0.0)
            XCTAssertLessThan(unit.armorPenetration, 1.0)
            XCTAssertGreaterThanOrEqual(unit.armor, 0)
            XCTAssertGreaterThanOrEqual(unit.shieldRangedBlock, 0.0)
            XCTAssertLessThanOrEqual(unit.shieldRangedBlock, 0.85)
            XCTAssertGreaterThan(unit.attackRange, unit.minRange)
            XCTAssertGreaterThan(unit.attackIntervalSec, 0.0)
            XCTAssertGreaterThan(unit.moveSpeed, 0.0)
            XCTAssertGreaterThanOrEqual(unit.popCap, 1)
            XCTAssertGreaterThan(unit.grainUpkeepPerSec, 0.0)
        }

        // 苍狼汗国禁造配重投石车：可募 7 通用 + 1 专属 = 8 种；其余 7 大势力可募 8 通用 + 1 专属 = 9 种
        let canglangUnits = UnitConfig.recruitableUnits(for: .canglang)
        XCTAssertEqual(canglangUnits.count, 8)
        XCTAssertFalse(canglangUnits.contains { $0.id == .trebuchet })

        let yanlongUnits = UnitConfig.recruitableUnits(for: .yanlong)
        XCTAssertEqual(yanlongUnits.count, 9)
        XCTAssertTrue(yanlongUnits.contains { $0.id == .trebuchet })
    }

    // MARK: - 4. 40 节点与 78 条道路无向对称性、全图连通性、无悬空交叉及开局经济配平断言

    func testCampaignFortyNodesSeventyEightRoadsSymmetryAndBalance() {
        let nodes = CampaignMapConfig.allNodes
        XCTAssertEqual(nodes.count, GameConstants.campaignNodeCount)
        XCTAssertEqual(CampaignMapConfig.byId.count, 40)

        // 4.1 无向图邻接表严格对称、无自环、无重复边
        for nodeA in nodes {
            XCTAssertTrue((0.0...GameConstants.campaignMapWidth).contains(nodeA.x))
            XCTAssertTrue((0.0...GameConstants.campaignMapHeight).contains(nodeA.y))
            XCTAssertFalse(nodeA.neighbors.contains(nodeA.id), "节点 \(nodeA.id) 存在非法自环")
            XCTAssertEqual(Set(nodeA.neighbors).count, nodeA.neighbors.count, "节点 \(nodeA.id) 存在重复邻接边")
            XCTAssertTrue((3...5).contains(nodeA.neighbors.count), "节点 \(nodeA.id) 度数 \(nodeA.neighbors.count) 超出 [3, 5] 均衡区间")

            for neighborId in nodeA.neighbors {
                guard let nodeB = CampaignMapConfig.node(byId: neighborId) else {
                    XCTFail("节点 \(nodeA.id) 引用了不存在的邻居 \(neighborId)")
                    continue
                }
                XCTAssertTrue(
                    nodeB.neighbors.contains(nodeA.id),
                    "无向图不对称：\(nodeA.id) -> \(neighborId) 存在，但反向缺失"
                )
            }
        }

        // 4.2 精确 78 条无向道路（156 条有向邻接引用）断言与零平面交叉（无悬空飞线）几何验证
        let totalDirectedNeighborRefs = nodes.reduce(0) { $0 + $1.neighbors.count }
        XCTAssertEqual(totalDirectedNeighborRefs, 78 * 2, "40 节点邻接表有向引用总数必须精确等于 156（78 条双向道路 × 2）")

        var rawCanonicalEdgePairs = Set<String>()
        for node in nodes {
            for nb in node.neighbors {
                let key = node.id < nb ? "\(node.id)--\(nb)" : "\(nb)--\(node.id)"
                rawCanonicalEdgePairs.insert(key)
            }
        }
        XCTAssertEqual(rawCanonicalEdgePairs.count, 78, "直接遍历 40 节点邻接表统计的无向边数必须精确等于 78")

        let roadEdges = CampaignMapConfig.allRoadEdges
        XCTAssertEqual(roadEdges.count, 78)
        XCTAssertEqual(roadEdges.count, GameConstants.campaignRoadCount)

        func isCounterClockwise(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double) -> Bool {
            (cy - ay) * (bx - ax) > (by - ay) * (cx - ax)
        }
        func segmentsStrictlyCross(_ a: CampaignNodeConfig, _ b: CampaignNodeConfig, _ c: CampaignNodeConfig, _ d: CampaignNodeConfig) -> Bool {
            isCounterClockwise(a.x, a.y, c.x, c.y, d.x, d.y) != isCounterClockwise(b.x, b.y, c.x, c.y, d.x, d.y) &&
            isCounterClockwise(a.x, a.y, b.x, b.y, c.x, c.y) != isCounterClockwise(a.x, a.y, b.x, b.y, d.x, d.y)
        }

        for i in 0..<roadEdges.count {
            guard let u1 = CampaignMapConfig.node(byId: roadEdges[i].fromNodeId),
                  let v1 = CampaignMapConfig.node(byId: roadEdges[i].toNodeId) else { continue }
            for j in (i + 1)..<roadEdges.count {
                let e2 = roadEdges[j]
                let endpointSet: Set<String> = [u1.id, v1.id, e2.fromNodeId, e2.toNodeId]
                guard endpointSet.count == 4,
                      let u2 = CampaignMapConfig.node(byId: e2.fromNodeId),
                      let v2 = CampaignMapConfig.node(byId: e2.toNodeId) else { continue }
                XCTAssertFalse(
                    segmentsStrictlyCross(u1, v1, u2, v2),
                    "大地图道路出现悬空交叉：\(u1.id)-\(v1.id) 与 \(u2.id)-\(v2.id)"
                )
            }
        }

        // 4.3 全图 BFS 连通性断言（40 座城关必须同属单一连通分量，无孤岛）
        var visited: Set<String> = [nodes[0].id]
        var queue: [String] = [nodes[0].id]
        var head = 0
        while head < queue.count {
            let currentId = queue[head]
            head += 1
            if let current = CampaignMapConfig.node(byId: currentId) {
                for nb in current.neighbors where !visited.contains(nb) {
                    visited.insert(nb)
                    queue.append(nb)
                }
            }
        }
        XCTAssertEqual(visited.count, 40, "战略大地图存在无法到达的孤岛节点")

        // 4.4 每势力均衡 5 城、开局经济公平窗口 [1415, 1510]（实际开局总产出 1425–1490，留容差）、本土距王都 BFS <= 2 跳无损补给
        let economyFairnessWindow = 1415...1510
        var economySums: [Int] = []
        for faction in FactionConfig.allFactions {
            let owned = CampaignMapConfig.initialNodes(for: faction.id)
            XCTAssertEqual(owned.count, GameConstants.campaignNodesPerFaction, "\(faction.name) 开局必须均衡拥有 5 座城关")

            let totalEconomy = owned.reduce(0) { $0 + $1.totalYield }
            economySums.append(totalEconomy)
            XCTAssertTrue(
                economyFairnessWindow.contains(totalEconomy),
                "\(faction.name) 开局总产出 \(totalEconomy) 超出 [1415, 1510] 公平配平窗口"
            )

            let depotCount = owned.filter(\.isSupplyDepot).count
            XCTAssertGreaterThanOrEqual(depotCount, 2, "\(faction.name) 本土至少应有 2 座补给仓城支撑前线")

            // 本土内部连通且距王都跳数 <= 2
            let ownedIds = Set(owned.map(\.id))
            var dist: [String: Int] = [faction.capitalNodeId: 0]
            var fQueue: [String] = [faction.capitalNodeId]
            while !fQueue.isEmpty {
                let u = fQueue.removeFirst()
                for v in (CampaignMapConfig.node(byId: u)?.neighbors ?? []) {
                    if ownedIds.contains(v), dist[v] == nil {
                        dist[v] = (dist[u] ?? 0) + 1
                        fQueue.append(v)
                    }
                }
            }
            XCTAssertEqual(dist.count, 5, "\(faction.name) 开局 5 座城池内部不连通")
            XCTAssertLessThanOrEqual(dist.values.max() ?? 99, GameConstants.supplyFullEfficiencyHops)
        }
        XCTAssertEqual(economySums.min(), 1425, "实际开局最低三项总产出应为 1425（血月祭司团）")
        XCTAssertEqual(economySums.max(), 1490, "实际开局最高三项总产出应为 1490（炎龙帝国）")
    }

    // MARK: - 5. 士气迟滞防抖、主帅重伤、断粮与外交边界阈值不变量断言

    func testMoraleHeroStarvationAndDiplomacyBoundaryInvariants() {
        XCTAssertLessThan(GameConstants.moraleRoutThreshold, GameConstants.moraleRallyThreshold, "溃逃恢复必须高于溃逃触发以构成迟滞防抖环")
        XCTAssertLessThan(GameConstants.moraleRallyThreshold, GameConstants.moraleWaveringThreshold)
        XCTAssertLessThan(GameConstants.moraleWaveringThreshold, GameConstants.moraleBase)
        XCTAssertLessThan(GameConstants.moraleBase, GameConstants.moraleHighThreshold)
        XCTAssertLessThan(GameConstants.moraleHighThreshold, GameConstants.moraleMax)

        XCTAssertEqual(GameConstants.heroWarbowQuiverCap, 24)
        XCTAssertEqual(GameConstants.heroFirstDownMoraleShock, 35.0)
        XCTAssertEqual(GameConstants.heroDownMoraleCap, 65.0)
        XCTAssertLessThan(GameConstants.rationWarningSeconds, GameConstants.starvationSevereSeconds)
        XCTAssertEqual(GameConstants.betrayalCredibilityPenalty, 45)
        XCTAssertEqual(GameConstants.betrayalVendettaLockTurns, 10)
        XCTAssertEqual(GameConstants.antiHegemonyNodeThreshold, 13)
    }

    // MARK: - 6. Application Support 本地离线存档管理器原子读写回环测试

    func testSaveStorageManagerIsolatedReadWriteRoundTrip() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("StickmanWarTests_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let manager = SaveStorageManager(customRootDirectoryURL: tempDir)
        let initialSlots = manager.loadAllSlotSummaries()
        XCTAssertEqual(initialSlots.count, SaveStorageManager.slotCount)
        XCTAssertTrue(initialSlots.allSatisfy(\.isEmpty))

        let sample = SaveSlotSummary(
            slotIndex: 2,
            title: "炎龙北伐测试军档",
            factionId: .yanlong,
            turnNumber: 9,
            controlledNodes: 8,
            totalBattlesWon: 5,
            totalEnemiesDefeated: 640,
            updatedAtIso: "2026-11-17T21:00:00Z",
            isEmpty: false
        )
        try manager.writeSlotSummary(sample)

        let reloaded = manager.loadAllSlotSummaries()
        XCTAssertFalse(reloaded[2].isEmpty)
        XCTAssertEqual(reloaded[2].title, "炎龙北伐测试军档")
        XCTAssertEqual(reloaded[2].turnNumber, 9)
        XCTAssertEqual(reloaded[2].controlledNodes, 8)

        var customSettings = GameUserSettings()
        customSettings.targetFps = 30
        customSettings.appearance = .lightParchment
        try manager.saveSettings(customSettings)
        XCTAssertEqual(manager.loadSettings(), customSettings)

        try manager.deleteSlot(at: 2)
        XCTAssertTrue(manager.loadAllSlotSummaries()[2].isEmpty)
    }
}
