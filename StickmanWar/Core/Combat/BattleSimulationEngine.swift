import Foundation

/// 冷兵器大战场确定性物理模拟核心引擎（Swift 6 纯值类型 `Sendable`，实现 `BattleSimulationEngineProtocol`，零 UI/SpriteKit 依赖）
/// 完整承载：
/// 1. 4800×2400 / 5600×2600 三路走廊战场、功能地形区、野外资源矿脉、攻城城墙/正侧门/箭塔/拒马/云梯初始化；
/// 2. 600 士兵 / 400 投射物 / 150 遗骸贴花 / 300 粒子预分配定长连续池 + 120px 均匀空间哈希网格零分配寻敌；
/// 3. 双曲护甲、侧背包抄、八象限钳形夹击/铁桶合围、渡河半渡而击、8 大势力王牌独有机制；
/// 4. 士气 20->32 迟滞防抖、三级断粮与劫敌粮车夺 150 粮、零金零工兵 25s 保底民夫、主帅双视角 1.5s 切换与两段式落马重伤闭环。
public struct BattleSimulationEngine: BattleSimulationEngineProtocol, Sendable {
    // MARK: - 一、公开只读战场状态（供 SpriteKit 批量渲染层与 XCTest 断言直接读取）

    public let context: RouteLaunchContext
    public let deployment: BattleDeploymentConfig
    public let worldWidth: Double
    public let worldHeight: Double

    public private(set) var elapsedSeconds: Double = 0.0
    public private(set) var isPaused: Bool = false
    public private(set) var controlMode: BattleControlMode = .rtsCommander
    public private(set) var switchCooldownRemaining: Double = 0.0
    public private(set) var outcome: BattleOutcomeReason = .ongoing

    public private(set) var hitStopRemainingSec: Double = 0.0
    public private(set) var cameraShakeIntensity: Double = 0.0

    /// 预分配连续对象池
    public private(set) var soldiers: [SoldierEntity]
    public private(set) var projectiles: [ProjectileEntity]
    public private(set) var corpseDecals: [CorpseDecalEntity]
    public private(set) var effectParticles: [EffectParticleEntity]

    public private(set) var squads: [BattleSquadState] = []
    public private(set) var structures: [SiegeStructureEntity] = []
    public private(set) var terrainZones: [TerrainZoneRect] = []
    public private(set) var resourceNodes: [BattleResourceNode] = []
    public private(set) var fieldTraps: [BattleFieldTrap] = []

    public private(set) var playerHero: HeroCommanderEntity
    public private(set) var enemyHero: HeroCommanderEntity
    public private(set) var playerState: SideEconomyAndMoraleState
    public private(set) var enemyState: SideEconomyAndMoraleState

    public private(set) var spatialGrid: SpatialHashGrid
    public private(set) var tacticalAI: BattleTacticalAI
    public private(set) var latestHudSnapshot: BattleHudSnapshot
    public private(set) var rng: DeterministicRNG

    public var aiBlackboard: TacticalBlackboardSummary {
        tacticalAI.blackboard
    }

    // MARK: - 内部预分配零堆开销工作游标与节流计时器

    private var heroInput: HeroControlInputState = HeroControlInputState()
    private var hudSyncAccumulator: Double = 0.0
    private var encirclementScanAccumulator: Double = 0.0
    private var corpseRingCursor: Int = 0
    private var particleRingCursor: Int = 0

    /// 预分配分队帧聚合工作数组（杜绝每 0.5s 合围扫描产生堆分配）
    private var scratchSquadSumX: [Double] = []
    private var scratchSquadSumY: [Double] = []
    private var scratchSquadAlive: [Int] = []
    private var scratchSquadWading: [Int] = []

    // MARK: - 二、开战完整初始化

    public init(
        context: RouteLaunchContext = RouteLaunchContext(),
        deployment: BattleDeploymentConfig = BattleDeploymentConfig()
    ) {
        self.context = context
        self.deployment = deployment

        let isSiege = context.scenarioType == .siegeAssault || context.scenarioType == .siegeDefense
        let width = isSiege ? GameConstants.siegeBattlefieldWidth : GameConstants.battlefieldWidth
        let height = isSiege ? GameConstants.siegeBattlefieldHeight : GameConstants.battlefieldHeight
        self.worldWidth = width
        self.worldHeight = height
        self.rng = DeterministicRNG(seed: deployment.randomSeed)

        // 1. 一次性预分配四大定长对象池
        var soldierPool: [SoldierEntity] = []
        soldierPool.reserveCapacity(GameConstants.maxUnitPoolSize)
        for i in 0..<GameConstants.maxUnitPoolSize {
            soldierPool.append(.inactiveSlot(index: i))
        }
        self.soldiers = soldierPool

        var projectilePool: [ProjectileEntity] = []
        projectilePool.reserveCapacity(GameConstants.maxProjectilePoolSize)
        for i in 0..<GameConstants.maxProjectilePoolSize {
            projectilePool.append(.inactiveSlot(index: i))
        }
        self.projectiles = projectilePool

        var corpsePool: [CorpseDecalEntity] = []
        corpsePool.reserveCapacity(GameConstants.maxFallenCorpseDecals)
        for i in 0..<GameConstants.maxFallenCorpseDecals {
            corpsePool.append(.inactiveSlot(index: i))
        }
        self.corpseDecals = corpsePool

        var particlePool: [EffectParticleEntity] = []
        particlePool.reserveCapacity(GameConstants.maxEffectParticlePoolSize)
        for i in 0..<GameConstants.maxEffectParticlePoolSize {
            particlePool.append(.inactiveSlot(index: i))
        }
        self.effectParticles = particlePool

        self.spatialGrid = SpatialHashGrid(
            worldWidth: width,
            worldHeight: height,
            cellSize: GameConstants.spatialGridCellSize,
            maxUnits: GameConstants.maxUnitPoolSize
        )

        // 2. 计算战役粮道跳数对初始携粮与士气封顶的修正
        let canglangSupplyRelief = context.playerFaction == .canglang ? 0.65 : 1.0
        var adjustedPlayerGrain = deployment.playerInitialGrain
        var playerMoraleCap = GameConstants.moraleMax
        switch deployment.playerSupplyStatus {
        case .fullSupply:
            break
        case .extendedMarch:
            if deployment.applySupplyGrainDiscountInEngine {
                adjustedPlayerGrain *= (1.0 - 0.15 * canglangSupplyRelief)
            }
        case .overextended:
            if deployment.applySupplyGrainDiscountInEngine {
                adjustedPlayerGrain *= (1.0 - 0.25 * canglangSupplyRelief)
            }
        case .severed(let isolatedTurns):
            if deployment.applySupplyGrainDiscountInEngine {
                adjustedPlayerGrain *= (1.0 - 0.35 * canglangSupplyRelief)
            }
            if isolatedTurns >= 2 {
                playerMoraleCap = GameConstants.heroDownMoraleCap
            }
        }

        self.playerState = SideEconomyAndMoraleState(
            side: .player,
            faction: context.playerFaction,
            gold: deployment.playerInitialGold,
            wood: deployment.playerInitialWood,
            grain: adjustedPlayerGrain,
            supplyMoraleCeiling: playerMoraleCap
        )
        self.enemyState = SideEconomyAndMoraleState(
            side: .enemy,
            faction: context.enemyFaction,
            gold: GameConstants.battleInitGold,
            wood: GameConstants.battleInitWood,
            grain: deployment.enemyInitialGrain,
            supplyMoraleCeiling: GameConstants.moraleMax
        )

        let leftCampX = (width - GameConstants.baseCampHorizontalSpan) * 0.5
        let rightCampX = width - leftCampX
        let centerY = height * 0.5

        var builtPlayerHero = HeroCommanderEntity(
            side: .player,
            faction: context.playerFaction,
            spawnX: leftCampX + 220.0,
            spawnY: centerY,
            facingRadians: 0.0
        )
        if deployment.isPlayerCommanderWeakened {
            // 战役模式主帅重伤休养虚弱期（2回合）：开战即带重创虚弱态（攻防移速 0.75x，失去首次落马免死）
            builtPlayerHero.vitalState = .woundedWeakened
            builtPlayerHero.hp = builtPlayerHero.maxHp * 0.75
        }
        self.playerHero = builtPlayerHero
        self.enemyHero = HeroCommanderEntity(
            side: .enemy,
            faction: context.enemyFaction,
            spawnX: rightCampX - 220.0,
            spawnY: centerY,
            facingRadians: Double.pi
        )

        self.tacticalAI = BattleTacticalAI()
        self.latestHudSnapshot = BattleHudSnapshot()

        // 3. 构建战场三路地形区、野外资源点、本阵/城防建筑与双方 6 大军团
        setupTerrainAndResources(leftCampX: leftCampX, rightCampX: rightCampX)
        setupBaseCampsAndSiegeWorks(leftCampX: leftCampX, rightCampX: rightCampX)
        setupInitialArmies(leftCampX: leftCampX, rightCampX: rightCampX)

        // 预分配分队聚合工作区
        let squadTotal = squads.count + 16
        scratchSquadSumX = Array(repeating: 0.0, count: squadTotal)
        scratchSquadSumY = Array(repeating: 0.0, count: squadTotal)
        scratchSquadAlive = Array(repeating: 0, count: squadTotal)
        scratchSquadWading = Array(repeating: 0, count: squadTotal)

        spatialGrid.rebuild(from: soldiers, terrainZones: terrainZones)
        refreshHudSnapshotNow()
    }

    // MARK: - 三、BattleSimulationEngineProtocol 协议实现与键鼠操控公开 API

    public mutating func issueSquadCommand(_ request: SquadCommandRequest) {
        var pincerBranchToggle = false
        for sqId in request.squadIds {
            guard sqId >= 0 && sqId < squads.count else { continue }
            guard squads[sqId].side == .player && squads[sqId].aliveCount > 0 && !squads[sqId].isRouting else { continue }

            if let newFormation = request.formation {
                squads[sqId].formation = newFormation
                assignFormationSlotsForSquad(squadId: sqId)
            }
            if let newOrder = request.order {
                squads[sqId].order = newOrder
                if newOrder == .feignedRetreat {
                    let camp = baseCampCoordinates(for: .player)
                    squads[sqId].feignedRetreatTimer = 6.5
                    squads[sqId].waypoints.removeAll(keepingCapacity: true)
                    squads[sqId].targetX = clamp(squads[sqId].anchorX - 360.0, minVal: camp.x + 120.0, maxVal: worldWidth - 120.0)
                } else if newOrder == .raidSupply && request.targetWorldX == nil {
                    // 奇袭断粮：若未点选具体坐标，自动沿外侧走廊寻路扑杀敌方采集工兵或敌本阵随军粮车
                    let raidTarget = findPlayerRaidSupplyTarget(fromY: squads[sqId].anchorY)
                    let corridorY = squads[sqId].anchorY <= worldHeight * 0.5 ? 260.0 : (worldHeight - 260.0)
                    squads[sqId].waypoints = [SquadWaypoint(x: (squads[sqId].anchorX + raidTarget.x) * 0.5, y: corridorY)]
                    squads[sqId].targetX = raidTarget.x
                    squads[sqId].targetY = raidTarget.y
                }
            }

            if let tx = request.targetWorldX, let ty = request.targetWorldY {
                let clampedX = clamp(tx, minVal: 40.0, maxVal: worldWidth - 40.0)
                let clampedY = clamp(ty, minVal: 40.0, maxVal: worldHeight - 40.0)
                let activeOrder = squads[sqId].order

                if request.appendWaypoint {
                    squads[sqId].waypoints.append(SquadWaypoint(x: clampedX, y: clampedY))
                } else {
                    squads[sqId].waypoints.removeAll(keepingCapacity: true)
                    let dx = clampedX - squads[sqId].anchorX
                    let dy = clampedY - squads[sqId].anchorY
                    let dist = hypot(dx, dy)

                    if activeOrder == .flank && dist > 160.0 {
                        // 侧翼包抄：自动向外侧偏移 220px 大弧线迂回绕过正面枪盾墙直插侧后
                        let perpSign: Double = (squads[sqId].corpsRole == .leftWing || squads[sqId].anchorY <= worldHeight * 0.5) ? -1.0 : 1.0
                        let nx = -dy / dist
                        let ny = dx / dist
                        let arcX = clamp((squads[sqId].anchorX + clampedX) * 0.5 + nx * 220.0 * perpSign, minVal: 60.0, maxVal: worldWidth - 60.0)
                        let arcY = clamp((squads[sqId].anchorY + clampedY) * 0.5 + ny * 220.0 * perpSign, minVal: 60.0, maxVal: worldHeight - 60.0)
                        squads[sqId].waypoints = [SquadWaypoint(x: arcX, y: arcY)]
                    } else if activeOrder == .pincerEncircle && dist > 160.0 {
                        // 钳形合围：多编队自动分左右双路（±240px）包夹并封堵目标后撤退路
                        let sideSign: Double = pincerBranchToggle ? 1.0 : -1.0
                        pincerBranchToggle.toggle()
                        let nx = -dy / dist
                        let ny = dx / dist
                        let arcX = clamp((squads[sqId].anchorX + clampedX) * 0.5 + nx * 240.0 * sideSign, minVal: 60.0, maxVal: worldWidth - 60.0)
                        let arcY = clamp((squads[sqId].anchorY + clampedY) * 0.5 + ny * 240.0 * sideSign, minVal: 60.0, maxVal: worldHeight - 60.0)
                        squads[sqId].waypoints = [SquadWaypoint(x: arcX, y: arcY)]
                    } else if activeOrder == .raidSupply && dist > 260.0 {
                        let corridorY = squads[sqId].anchorY <= worldHeight * 0.5 ? 250.0 : (worldHeight - 250.0)
                        squads[sqId].waypoints = [SquadWaypoint(x: (squads[sqId].anchorX + clampedX) * 0.5, y: corridorY)]
                    }

                    squads[sqId].targetX = clampedX
                    squads[sqId].targetY = clampedY
                    let firstDest = squads[sqId].waypoints.first
                    let fdx = (firstDest?.x ?? clampedX) - squads[sqId].anchorX
                    let fdy = (firstDest?.y ?? clampedY) - squads[sqId].anchorY
                    if fdx * fdx + fdy * fdy > 16.0 {
                        squads[sqId].facingRadians = atan2(fdy, fdx)
                    }
                }
            }
        }
    }

    private func findPlayerRaidSupplyTarget(fromY: Double) -> (x: Double, y: Double) {
        if !enemyState.garrisonBellActive {
            var bestSapper: (x: Double, y: Double)?
            var bestDist = Double.greatestFiniteMagnitude
            for u in soldiers where u.isActive && u.hp > 0.0 && u.side == .enemy && u.unitType == .sapper {
                let d = abs(u.y - fromY)
                if d < bestDist {
                    bestDist = d
                    bestSapper = (u.x, u.y)
                }
            }
            if let found = bestSapper {
                return found
            }
        }
        return baseCampCoordinates(for: .enemy)
    }

    public mutating func toggleGarrisonBell() {
        playerState.garrisonBellActive.toggle()
        let active = playerState.garrisonBellActive
        let campPos = baseCampCoordinates(for: .player)
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 {
            if soldiers[i].side == .player && soldiers[i].unitType == .sapper {
                if !active {
                    soldiers[i].isGarrisonedInCamp = false
                    soldiers[i].x = campPos.x + 65.0
                }
            }
        }
        refreshHudSnapshotNow()
    }

    public mutating func setPaused(_ paused: Bool) {
        isPaused = paused
        refreshHudSnapshotNow()
    }

    public mutating func updateHeroInput(_ input: HeroControlInputState) {
        self.heroInput = input
    }

    /// 切换 RTS 上帝视角 <-> 主帅亲自上阵视角（遵守 1.5s 冷却且重伤包扎/殉国时禁止切入英雄视角）
    @discardableResult
    public mutating func toggleControlMode() -> Bool {
        guard switchCooldownRemaining <= 0.0 else { return false }
        if controlMode == .rtsCommander {
            guard playerHero.isActiveOnField else { return false }
            controlMode = .heroAction
        } else {
            controlMode = .rtsCommander
        }
        switchCooldownRemaining = GameConstants.heroViewSwitchCooldownSec
        refreshHudSnapshotNow()
        return true
    }

    public mutating func switchHeroWeapon(_ weapon: HeroWeaponType) {
        HeroCombatController.switchWeapon(hero: &playerHero, to: weapon)
        refreshHudSnapshotNow()
    }

    @discardableResult
    public mutating func triggerHeroSkill(_ skill: HeroSkillId) -> Bool {
        var events = HeroStepEvents()
        let ok = HeroCombatController.triggerSkill(
            skill,
            hero: &playerHero,
            squads: &squads,
            events: &events
        )
        if ok {
            cameraShakeIntensity = min(1.0, cameraShakeIntensity + events.cameraShakeDelta)
            if skill == .grandWarCry {
                spawnParticle(kind: .warCryWave, x: playerHero.x, y: playerHero.y, lifetime: 0.65)
            }
            refreshHudSnapshotNow()
        }
        return ok
    }

    /// 战场大营招募常规/专属兵种（严格校验势力专属合法性、苍狼禁造投石车、人口上限与势力造价修正）
    @discardableResult
    public mutating func recruitUnit(
        side: BattleSide,
        unitType: UnitTypeId,
        corpsRole: ArmyCorpsRole = .rearReserve
    ) -> Bool {
        let faction = side == .player ? playerState.faction : enemyState.faction
        let legalUnits = UnitConfig.recruitableUnits(for: faction)
        guard let stats = legalUnits.first(where: { $0.id == unitType }) else { return false }
        guard !isBaseCampDestroyed(for: side) else { return false }

        let adjustedCost = computeAdjustedRecruitmentCost(baseCost: stats.cost, category: stats.category, faction: faction)
        if side == .player {
            guard playerState.popUsed + stats.popCap <= playerState.popCap,
                  playerState.gold >= adjustedCost.gold,
                  playerState.wood >= adjustedCost.wood,
                  playerState.grain >= Double(adjustedCost.grain) else { return false }
            playerState.gold -= adjustedCost.gold
            playerState.wood -= adjustedCost.wood
            playerState.grain -= Double(adjustedCost.grain)
            playerState.popUsed += stats.popCap
            playerState.trainingQueue.append(
                TrainingQueueItem(unitType: unitType, corpsRole: corpsRole, remainingSeconds: stats.buildTimeSec)
            )
            refreshHudSnapshotNow()
            return true
        } else {
            guard enemyState.popUsed + stats.popCap <= enemyState.popCap,
                  enemyState.gold >= adjustedCost.gold,
                  enemyState.wood >= adjustedCost.wood,
                  enemyState.grain >= Double(adjustedCost.grain) else { return false }
            enemyState.gold -= adjustedCost.gold
            enemyState.wood -= adjustedCost.wood
            enemyState.grain -= Double(adjustedCost.grain)
            enemyState.popUsed += stats.popCap
            enemyState.trainingQueue.append(
                TrainingQueueItem(unitType: unitType, corpsRole: corpsRole, remainingSeconds: stats.buildTimeSec)
            )
            return true
        }
    }

    /// 沙漠商盟特色：耗纯金币即时征召外邦雇佣兵（免木材与训练等待时间）
    @discardableResult
    public mutating func recruitMercenaryUnit(
        side: BattleSide,
        unitType: UnitTypeId,
        corpsRole: ArmyCorpsRole = .rearReserve
    ) -> Bool {
        let faction = side == .player ? playerState.faction : enemyState.faction
        guard faction == .shamo,
              let stats = UnitConfig.stats(for: unitType),
              stats.exclusiveFaction == nil || stats.exclusiveFaction == .shamo,
              !isBaseCampDestroyed(for: side) else { return false }

        let pureGoldPrice = stats.cost.gold + stats.cost.wood + (stats.cost.grain / 2)
        if side == .player {
            guard playerState.popUsed + stats.popCap <= playerState.popCap,
                  playerState.gold >= pureGoldPrice else { return false }
            playerState.gold -= pureGoldPrice
            playerState.popUsed += stats.popCap
            spawnTrainedSoldier(side: .player, unitType: unitType, corpsRole: corpsRole, isMercenary: true)
            refreshHudSnapshotNow()
            return true
        } else {
            guard enemyState.popUsed + stats.popCap <= enemyState.popCap,
                  enemyState.gold >= pureGoldPrice else { return false }
            enemyState.gold -= pureGoldPrice
            enemyState.popUsed += stats.popCap
            spawnTrainedSoldier(side: .enemy, unitType: unitType, corpsRole: corpsRole, isMercenary: true)
            return true
        }
    }

    /// 雾林猎手等在战场布设尖刺陷坑或绊马索
    @discardableResult
    public mutating func deployFieldTrap(
        side: BattleSide,
        kind: FieldTrapKind,
        x: Double,
        y: Double
    ) -> Bool {
        let faction = side == .player ? playerState.faction : enemyState.faction
        guard faction == .wulin else { return false }
        let woodCost = 25
        if side == .player {
            guard playerState.wood >= woodCost else { return false }
            playerState.wood -= woodCost
        } else {
            guard enemyState.wood >= woodCost else { return false }
            enemyState.wood -= woodCost
        }
        let nextId = fieldTraps.count
        fieldTraps.append(
            BattleFieldTrap(
                id: nextId,
                side: side,
                kind: kind,
                x: clamp(x, minVal: 60.0, maxVal: worldWidth - 60.0),
                y: clamp(y, minVal: 60.0, maxVal: worldHeight - 60.0)
            )
        )
        return true
    }

    public mutating func concludeByTruce() {
        guard outcome == .ongoing else { return }
        outcome = .truceNegotiated
        refreshHudSnapshotNow()
    }

    /// 供 SpriteKit 鼠标左键拖拽框选检索矩形内的分队 ID
    public func selectSquadsInRect(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        side: BattleSide = .player
    ) -> [Int] {
        let loX = min(minX, maxX)
        let hiX = max(minX, maxX)
        let loY = min(minY, maxY)
        let hiY = max(minY, maxY)
        var selected: [Int] = []
        for sq in squads where sq.side == side && sq.aliveCount > 0 && !sq.isRouting {
            if sq.anchorX >= loX && sq.anchorX <= hiX && sq.anchorY >= loY && sq.anchorY <= hiY {
                selected.append(sq.id)
            }
        }
        return selected
    }

    /// 供 SpriteKit 鼠标左键点选最近分队 ID（容差默认 44px）
    public func pickSquadAtPoint(
        x: Double,
        y: Double,
        tolerance: Double = 44.0,
        side: BattleSide = .player
    ) -> Int? {
        let tolSq = tolerance * tolerance
        var bestId: Int?
        var bestDistSq = tolSq
        for sq in squads where sq.side == side && sq.aliveCount > 0 {
            let dx = sq.anchorX - x
            let dy = sq.anchorY - y
            let dSq = dx * dx + dy * dy
            if dSq <= bestDistSq {
                bestDistSq = dSq
                bestId = sq.id
            }
        }
        return bestId
    }

    /// 供 SpriteKit 鼠标右键情境下令判定是否点中敌方编队、敌帅或敌方城防建筑
    public func pickEnemyTargetAtPoint(
        x: Double,
        y: Double,
        tolerance: Double = 68.0
    ) -> (x: Double, y: Double, label: String)? {
        let tolSq = tolerance * tolerance
        var bestSq: BattleSquadState?
        var bestDistSq = tolSq
        for sq in squads where sq.side == .enemy && sq.aliveCount > 0 {
            let dx = sq.anchorX - x
            let dy = sq.anchorY - y
            let dSq = dx * dx + dy * dy
            if dSq <= bestDistSq {
                bestDistSq = dSq
                bestSq = sq
            }
        }
        if let sq = bestSq {
            let uName = UnitConfig.stats(for: sq.primaryUnitType)?.name ?? "敌军分队"
            return (sq.anchorX, sq.anchorY, "敌军【\(uName)】")
        }
        if enemyHero.isActiveOnField {
            let hdx = enemyHero.x - x
            let hdy = enemyHero.y - y
            if hdx * hdx + hdy * hdy <= tolSq {
                return (enemyHero.x, enemyHero.y, "敌方【督战主帅】")
            }
        }
        for st in structures where !st.isDestroyed && st.side == .enemy && st.kind != .siegeLadder {
            if abs(x - st.x) <= st.width * 0.65 && abs(y - st.y) <= st.height * 0.65 {
                let stLabel: String = {
                    switch st.kind {
                    case .baseCamp: return "敌军【本阵大营/粮仓】"
                    case .mainGate: return "敌方【瓮城正门】"
                    case .sideSallyGate: return "敌方【侧门暗道】"
                    case .wallSegment: return "敌方【城墙段】"
                    case .arrowTower: return "敌方【守御箭塔】"
                    case .woodenCheval: return "敌方【拒马木栅】"
                    case .siegeLadder: return "登城云梯"
                    }
                }()
                return (st.x, st.y, stLabel)
            }
        }
        return nil
    }

    /// 生成战后军功伤亡、医帐救治恢复、俘虏与缴获结算摘要（精准对接 `CampaignContracts.swift`）
    public func buildPostBattleSummary() -> PostBattleSettlementSummary {
        let victory = (outcome == .enemyBaseDestroyed || outcome == .enemyArmyRouted || outcome == .siegeDefenseHeld)
        let resolvedOutcome = outcome == .ongoing ? (victory ? .enemyArmyRouted : .truceNegotiated) : outcome

        let pCasualties = playerState.killedCount
        // 医帐包扎可救回约 35% 战损重伤员（胜利方打扫战场救治率更高达 42%）
        let recoveryRate = victory ? 0.42 : 0.25
        let woundedRecovered = Int((Double(pCasualties) * recoveryRate).rounded(.down))
        let permanentPlayerDead = max(0, pCasualties - woundedRecovered)

        var enemyRoutingLeft = 0
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 && soldiers[i].side == .enemy {
            if soldiers[i].squadId >= 0 && soldiers[i].squadId < squads.count && squads[soldiers[i].squadId].isRouting {
                enemyRoutingLeft += 1
            }
        }

        let captured = victory ? max(4, enemyRoutingLeft / 2 + enemyState.killedCount / 6) : 0
        let baseGoldLoot = victory ? (180 + enemyState.killedCount * 3 + playerState.lootedGoldTotal) : playerState.lootedGoldTotal
        let baseWoodLoot = victory ? (95 + enemyState.killedCount * 2 + playerState.lootedWoodTotal) : playerState.lootedWoodTotal
        let baseGrainLoot = victory
            ? (160 + Int(enemyState.grain * 0.25) + Int(playerState.lootedGrainTotal))
            : Int(playerState.lootedGrainTotal)
        let expGained = (victory ? 260 : 90) + enemyState.killedCount * 4 + playerHero.killsCount * 12 + playerHero.bannersSlainCount * 35

        return PostBattleSettlementSummary(
            scenarioType: context.scenarioType,
            playerFaction: context.playerFaction,
            enemyFaction: context.enemyFaction,
            isVictory: victory,
            outcomeReason: resolvedOutcome,
            durationSeconds: max(1, Int(elapsedSeconds.rounded())),
            playerKilled: permanentPlayerDead,
            playerWoundedRecovered: woundedRecovered,
            enemyKilled: enemyState.killedCount,
            capturedPrisoners: captured,
            lootedGold: baseGoldLoot,
            lootedWood: baseWoodLoot,
            lootedGrain: baseGrainLoot,
            commanderExpGained: expGained
        )
    }

    // MARK: - 四、单步确定性战斗模拟主循环（标准 30Hz，dt = 1/30s）

    public mutating func stepLogicTick(deltaTime: Double) {
        let clampedDt = min(0.10, max(0.0, deltaTime))
        guard clampedDt > 0.0, outcome == .ongoing else { return }

        switchCooldownRemaining = max(0.0, switchCooldownRemaining - clampedDt)
        cameraShakeIntensity = max(0.0, cameraShakeIntensity - clampedDt * 2.5)

        if isPaused {
            return
        }

        // 主帅重劈 / 弹反 40ms 卡肉顿帧处理
        var simDt = clampedDt
        if hitStopRemainingSec > 0.0 {
            if simDt <= hitStopRemainingSec {
                hitStopRemainingSec -= simDt
                stepParticlesOnly(deltaTime: simDt)
                return
            } else {
                simDt -= hitStopRemainingSec
                hitStopRemainingSec = 0.0
            }
        }

        elapsedSeconds += simDt

        // 1. 重建 120px 均匀空间哈希网格
        spatialGrid.rebuild(from: soldiers, terrainZones: terrainZones)

        // 2. 结算双方粮草消耗、三级断粮惩罚、大营保底军饷、25s 应急民夫防死锁与训练队列
        stepSideEconomyAndLogistics(side: .player, deltaTime: simDt)
        stepSideEconomyAndLogistics(side: .enemy, deltaTime: simDt)

        // 3. 刷新各军团坐标质心、涉水比例，并每 0.5s 执行八象限包抄/合围与半渡而击判定
        stepSquadCentroidsAndMorale(deltaTime: simDt)

        // 4. 驱动 L2 战场指挥官战术黑板 AI（每 0.5s 刷新）
        tacticalAI.stepAI(
            deltaTime: simDt,
            aiSide: .enemy,
            aiFaction: enemyState.faction,
            scenarioType: context.scenarioType,
            elapsedSeconds: elapsedSeconds,
            worldWidth: worldWidth,
            worldHeight: worldHeight,
            commandParalysisTimer: enemyState.commandParalysisTimer,
            opponentGarrisonBellActive: playerState.garrisonBellActive,
            opponentHero: playerHero,
            aiHero: enemyHero,
            squads: &squads,
            soldiers: soldiers,
            structures: structures,
            terrainZones: terrainZones,
            resourceNodes: resourceNodes
        )

        // 5. 推进敌我双方主帅移动、格挡、蓄力射击、近战劈刺与落马重伤状态机
        stepBothCommanders(deltaTime: simDt)

        // 6. 推进分队锚点机动、单兵弹簧槽位转向、工兵采集/警钟入营、陷阱与近远交战
        stepSquadAnchors(deltaTime: simDt)
        stepSoldiersAndCombat(deltaTime: simDt)

        // 7. 推进守城箭塔索敌与全场 400 投射物弹道碰撞
        stepDefensiveTowers(deltaTime: simDt)
        stepProjectiles(deltaTime: simDt)

        // 8. 更新受击粒子与战争迷雾侦察视野显形
        stepParticlesOnly(deltaTime: simDt)
        updateFogOfWarVisibility()

        // 9. 终局胜负边界判定与 4Hz (每 250ms) HUD 节流快照同步
        evaluateBattleOutcome()
        hudSyncAccumulator += simDt
        let syncInterval = 1.0 / Double(max(1, GameConstants.hudSyncThrottleHz))
        if outcome != .ongoing || hudSyncAccumulator >= syncInterval {
            hudSyncAccumulator = 0.0
            refreshHudSnapshotNow()
        }
    }

    // MARK: - 五、战场后勤经济、断粮三级递进与 25s 应急工兵保底

    private mutating func stepSideEconomyAndLogistics(side: BattleSide, deltaTime: Double) {
        let campDestroyed = isBaseCampDestroyed(for: side)
        let faction = side == .player ? playerState.faction : enemyState.faction

        // 统计总耗粮与存活工兵数
        var upkeepPerSec = 0.0
        var aliveSappers = 0
        var activePop = 0

        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 && soldiers[i].side == side {
            let unit = soldiers[i]
            if let stats = UnitConfig.stats(for: unit.unitType) {
                var u = stats.grainUpkeepPerSec
                if faction == .shuangyuan { u *= 1.15 }
                let t = terrainAt(x: unit.x, y: unit.y)
                if t == .desertDune && faction != .shamo { u *= 1.30 }
                if (t == .snowfield || context.weather == .blizzard) && faction != .shuangyuan { u *= 1.25 }
                upkeepPerSec += u
                activePop += stats.popCap
            }
            if unit.unitType == .sapper {
                aliveSappers += 1
            }
        }

        // 战役远征补给跳数附加维持耗粮（苍狼减免 35%）
        if side == .player {
            let relief = faction == .canglang ? 0.65 : 1.0
            switch deployment.playerSupplyStatus {
            case .fullSupply:
                break
            case .extendedMarch:
                upkeepPerSec *= (1.0 + 0.25 * relief)
            case .overextended, .severed:
                upkeepPerSec *= (1.0 + 0.50 * relief)
            }
        }

        // 值拷贝出单方状态并在生成士兵前写回，严格杜绝 `self.mutatingFunc(&self.playerState)` 重叠访问冲突
        var state = side == .player ? playerState : enemyState
        var completedSpawns: [TrainingQueueItem] = []
        var spawnEmergencySapper = false

        state.commandParalysisTimer = max(0.0, state.commandParalysisTimer - deltaTime)
        if state.bloodMoonFervorRemainingSec > 0.0 {
            state.bloodMoonFervorRemainingSec = max(0.0, state.bloodMoonFervorRemainingSec - deltaTime)
        }

        // 本阵大营每秒微量保底军饷（+1.2 金/s，商盟 +35%；+0.5 木/s）
        if !campDestroyed {
            let goldMult = state.faction == .shamo ? 1.35 : 1.0
            state.passiveGoldAccumulator += GameConstants.basePassiveGoldPerSec * goldMult * deltaTime
            state.passiveWoodAccumulator += GameConstants.basePassiveWoodPerSec * deltaTime
            if state.passiveGoldAccumulator >= 1.0 {
                let gained = Int(state.passiveGoldAccumulator.rounded(.down))
                state.gold += gained
                state.passiveGoldAccumulator -= Double(gained)
            }
            if state.passiveWoodAccumulator >= 1.0 {
                let gained = Int(state.passiveWoodAccumulator.rounded(.down))
                state.wood += gained
                state.passiveWoodAccumulator -= Double(gained)
            }
        }

        // 粮草消耗与断粮计时
        state.grain = max(0.0, state.grain - upkeepPerSec * deltaTime)
        if state.grain <= 0.0 {
            state.zeroGrainElapsedSec += deltaTime
        } else {
            state.zeroGrainElapsedSec = 0.0
        }
        let rationEval = DamageMoraleCalculator.evaluateRationStage(
            remainingGrain: state.grain,
            upkeepPerSec: upkeepPerSec,
            zeroGrainElapsedSec: state.zeroGrainElapsedSec
        )
        state.rationStage = rationEval.stage

        // 零金币 + 零工兵经济死锁保底：工兵全灭且金币 < 35 时每 25s 免费征召 1 名应急民夫
        let sapperQueued = state.trainingQueue.contains(where: { $0.unitType == .sapper })
        if !campDestroyed && aliveSappers == 0 && !sapperQueued && state.gold < 35 {
            state.emergencySapperTimerSec += deltaTime
            if state.emergencySapperTimerSec >= GameConstants.emergencySapperRespawnSec {
                state.emergencySapperTimerSec = 0.0
                spawnEmergencySapper = true
            }
        } else {
            state.emergencySapperTimerSec = 0.0
        }

        // 推进本阵训练队列
        var queuedPop = 0
        var idx = 0
        while idx < state.trainingQueue.count {
            state.trainingQueue[idx].remainingSeconds -= deltaTime
            if state.trainingQueue[idx].remainingSeconds <= 0.0 {
                let done = state.trainingQueue.remove(at: idx)
                if !campDestroyed {
                    completedSpawns.append(done)
                }
            } else {
                if let st = UnitConfig.stats(for: state.trainingQueue[idx].unitType) {
                    queuedPop += st.popCap
                }
                idx += 1
            }
        }

        // 沙漠商盟断粮期外籍雇佣兵需折银发放应急军饷（0.35 金/人·秒），金尽且进入饥溃（>30s）时集体离场
        if state.faction == .shamo && state.grain <= 0.0 {
            var activeMercs = 0
            for sIdx in 0..<squads.count where squads[sIdx].side == side && squads[sIdx].isMercenary && squads[sIdx].aliveCount > 0 {
                activeMercs += squads[sIdx].aliveCount
            }
            if activeMercs > 0 {
                state.passiveGoldAccumulator -= Double(activeMercs) * 0.35 * deltaTime
                if state.passiveGoldAccumulator <= -1.0 {
                    let silverCost = Int((-state.passiveGoldAccumulator).rounded(.down))
                    state.passiveGoldAccumulator += Double(silverCost)
                    state.gold = max(0, state.gold - silverCost)
                }
            }
        }
        if state.faction == .shamo && state.gold <= 0 && state.rationStage == .starving {
            var desertedPop = 0
            for sIdx in 0..<squads.count where squads[sIdx].side == side && squads[sIdx].isMercenary && squads[sIdx].aliveCount > 0 {
                let unitPop = UnitConfig.stats(for: squads[sIdx].unitType)?.popCap ?? 1
                for uIdx in 0..<soldiers.count where soldiers[uIdx].isActive && soldiers[uIdx].squadId == sIdx && soldiers[uIdx].hp > 0.0 {
                    soldiers[uIdx].isActive = false
                    soldiers[uIdx].hp = 0.0
                    state.mercenaryDesertedCount += 1
                    desertedPop += unitPop
                }
                squads[sIdx].aliveCount = 0
            }
            activePop = max(0, activePop - desertedPop)
        }

        state.popUsed = activePop + queuedPop
        if side == .player {
            playerState = state
        } else {
            enemyState = state
        }

        if spawnEmergencySapper {
            spawnTrainedSoldier(side: side, unitType: .sapper, corpsRole: .supplyEscort, isMercenary: false)
            if let st = UnitConfig.stats(for: .sapper) {
                if side == .player {
                    playerState.popUsed += st.popCap
                } else {
                    enemyState.popUsed += st.popCap
                }
            }
        }
        for done in completedSpawns {
            spawnTrainedSoldier(
                side: side,
                unitType: done.unitType,
                corpsRole: done.corpsRole,
                isMercenary: done.isMercenary
            )
            if let st = UnitConfig.stats(for: done.unitType) {
                if side == .player {
                    playerState.popUsed += st.popCap
                } else {
                    enemyState.popUsed += st.popCap
                }
            }
        }
    }

    // MARK: - 六、军团质心、涉水比例、八象限合围与士气迟滞更新

    private mutating func stepSquadCentroidsAndMorale(deltaTime: Double) {
        if scratchSquadAlive.count < squads.count {
            let needed = squads.count + 8
            scratchSquadSumX = Array(repeating: 0.0, count: needed)
            scratchSquadSumY = Array(repeating: 0.0, count: needed)
            scratchSquadAlive = Array(repeating: 0, count: needed)
            scratchSquadWading = Array(repeating: 0, count: needed)
        } else {
            for i in 0..<squads.count {
                scratchSquadSumX[i] = 0.0
                scratchSquadSumY[i] = 0.0
                scratchSquadAlive[i] = 0
                scratchSquadWading[i] = 0
            }
        }

        // 统计各分队存活人数、质心与涉水比例，同时刷新骆驼惊马光环
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 {
            let sqId = soldiers[i].squadId
            if sqId >= 0 && sqId < squads.count {
                scratchSquadSumX[sqId] += soldiers[i].x
                scratchSquadSumY[sqId] += soldiers[i].y
                scratchSquadAlive[sqId] += 1
                if terrainAt(x: soldiers[i].x, y: soldiers[i].y) == .riverFord {
                    scratchSquadWading[sqId] += 1
                }
            }
            // 黄金马穆鲁克披甲骆驼气味惊马光环：160px 内敌方战马移速与冲锋伤 -25%
            if soldiers[i].unitType == .shamoMamelukeCamel {
                let enemySide = soldiers[i].side.opponent
                let cx = soldiers[i].x
                let cy = soldiers[i].y
                let spookHits = spatialGrid.queryInRadius(centerX: cx, centerY: cy, radius: 160.0, sideFilter: enemySide)
                for h in 0..<spookHits.count {
                    let eIdx = spookHits[h].unitIndex
                    if soldiers[eIdx].category == .cavalry {
                        soldiers[eIdx].camelSpookedTimer = 0.60
                    }
                }
            }
        }

        for sIdx in 0..<squads.count {
            let cnt = scratchSquadAlive[sIdx]
            squads[sIdx].aliveCount = cnt
            squads[sIdx].bannerLostPenaltyTimer = max(0.0, squads[sIdx].bannerLostPenaltyTimer - deltaTime)
            squads[sIdx].warCryBuffTimer = max(0.0, squads[sIdx].warCryBuffTimer - deltaTime)

            if cnt > 0 {
                let inv = 1.0 / Double(cnt)
                squads[sIdx].anchorX = scratchSquadSumX[sIdx] * inv
                squads[sIdx].anchorY = scratchSquadSumY[sIdx] * inv
                let wadeRatio = Double(scratchSquadWading[sIdx]) * inv
                squads[sIdx].riverWadingRatio = wadeRatio
                if wadeRatio < 0.15 || wadeRatio > 0.90 {
                    squads[sIdx].halfFordShockApplied = false
                }
            } else {
                squads[sIdx].riverWadingRatio = 0.0
            }
        }

        // 每 0.5s 执行八象限受围判定与半渡而击震慑检测
        encirclementScanAccumulator += deltaTime
        let runOctantScan = encirclementScanAccumulator >= 0.50
        if runOctantScan {
            encirclementScanAccumulator = 0.0
        }

        let pHeroDown = playerHero.vitalState == .recoveringInCamp
        let eHeroDown = enemyHero.vitalState == .recoveringInCamp
        let pFervor = playerState.bloodMoonFervorRemainingSec > 0.0
        let eFervor = enemyState.bloodMoonFervorRemainingSec > 0.0

        for sIdx in 0..<squads.count where squads[sIdx].aliveCount > 0 {
            let side = squads[sIdx].side
            let enemySide = side.opponent
            let campPos = baseCampCoordinates(for: side)
            let retreatAngle = atan2(campPos.y - squads[sIdx].anchorY, campPos.x - squads[sIdx].anchorX)
            let retreatOctant = DamageMoraleCalculator.octantIndex(
                forRelativeAngle: retreatAngle - squads[sIdx].facingRadians
            )

            if runOctantScan {
                var mask: UInt8 = 0
                var firstEnemySq = -1
                var secondEnemySq = -1
                let ax = squads[sIdx].anchorX
                let ay = squads[sIdx].anchorY
                let facing = squads[sIdx].facingRadians

                let octantHits = spatialGrid.queryInRadius(centerX: ax, centerY: ay, radius: 160.0, sideFilter: enemySide)
                for h in 0..<octantHits.count {
                    let eIdx = octantHits[h].unitIndex
                    let angleToEnemy = atan2(soldiers[eIdx].y - ay, soldiers[eIdx].x - ax)
                    let oct = DamageMoraleCalculator.octantIndex(forRelativeAngle: angleToEnemy - facing)
                    mask |= (1 << oct)
                    let eSq = soldiers[eIdx].squadId
                    if firstEnemySq == -1 {
                        firstEnemySq = eSq
                    } else if eSq != firstEnemySq {
                        secondEnemySq = eSq
                    }
                }

                let distinctSqCount = firstEnemySq == -1 ? 0 : (secondEnemySq == -1 ? 1 : 2)
                let escapeBlocked = (mask & (1 << retreatOctant)) != 0
                let sqTerrain = terrainAt(x: ax, y: ay)
                let eval = DamageMoraleCalculator.evaluateEncirclement(
                    occupiedOctantMask: mask,
                    distinctEnemySquadCount: distinctSqCount,
                    retreatOctantBlocked: escapeBlocked,
                    formation: squads[sIdx].formation,
                    formationBonusActive: squads[sIdx].isFormationBonusActive,
                    terrain: sqTerrain
                )
                squads[sIdx].engagedOctantMask = mask
                squads[sIdx].engagedEnemySquadCount = distinctSqCount
                squads[sIdx].encirclementState = eval.state

                // 半渡而击一次性 -12 士气震慑：涉水占比 30%~80% 且交战圈内遭袭
                if mask != 0
                    && !squads[sIdx].halfFordShockApplied
                    && squads[sIdx].riverWadingRatio >= 0.30
                    && squads[sIdx].riverWadingRatio <= 0.80 {
                    squads[sIdx].halfFordShockApplied = true
                    squads[sIdx].morale = max(0.0, squads[sIdx].morale - 12.0)
                }
            }

            // 连续士气涨落汇总
            var moraleRatePerSec = 0.0
            let stateRef = side == .player ? playerState : enemyState
            let heroRef = side == .player ? playerHero : enemyHero
            let inCloseContact = squads[sIdx].engagedOctantMask != 0

            // 1) 包抄 / 钳形夹击 (-2.2/s) / 铁桶合围 (-4.8/s，圆阵减半)
            switch squads[sIdx].encirclementState {
            case .clear:
                break
            case .flanked:
                moraleRatePerSec -= 0.6
            case .pincered:
                if !(squads[sIdx].formation == .circleDefense && squads[sIdx].isFormationBonusActive) {
                    moraleRatePerSec -= GameConstants.pincerMoraleDrainPerSec
                }
            case .encircled:
                let circleHalf = (squads[sIdx].formation == .circleDefense && squads[sIdx].isFormationBonusActive) ? 0.5 : 1.0
                moraleRatePerSec -= GameConstants.encirclementMoraleDrainPerSec * circleHalf
            }

            // 方阵减缓 25% 士气流失
            if moraleRatePerSec < 0.0
                && squads[sIdx].formation == .phalanxRect
                && squads[sIdx].isFormationBonusActive
                && squads[sIdx].encirclementState != .pincered {
                moraleRatePerSec *= 0.75
            }

            // 2) 断粮士气衰减（饥饿 -0.8/s，饥溃 -1.8/s）
            if stateRef.rationStage == .hungry {
                moraleRatePerSec -= 0.8
            } else if stateRef.rationStage == .starving {
                moraleRatePerSec -= 1.8
                if stateRef.faction == .shamo && squads[sIdx].isMercenary && stateRef.gold <= 0 {
                    moraleRatePerSec -= 3.5
                }
            }

            // 3) 暴风雪非霜原熊族微降士气
            if context.weather == .blizzard && squads[sIdx].faction != .shuangyuan {
                moraleRatePerSec -= 0.25
            }

            // 4) 主帅帅旗光环（350px 内 +1.25/s）与脱离接触自然重整回升（断粮期禁自然回士气）
            if stateRef.rationStage == .abundant || stateRef.rationStage == .warning {
                if heroRef.isActiveOnField {
                    let hdx = squads[sIdx].anchorX - heroRef.x
                    let hdy = squads[sIdx].anchorY - heroRef.y
                    if hdx * hdx + hdy * hdy <= 350.0 * 350.0 {
                        moraleRatePerSec += 1.25
                    }
                }
                if !inCloseContact && squads[sIdx].morale < GameConstants.moraleBase {
                    moraleRatePerSec += 1.65
                }
            }

            let isFearless = squads[sIdx].primaryUnitType == .xueyueWardrumBerserker
                || (squads[sIdx].faction == .xueyue && (side == .player ? pFervor : eFervor))

            let updated = DamageMoraleCalculator.updateMoraleAndBracket(
                currentMorale: squads[sIdx].morale,
                wasRouting: squads[sIdx].isRouting,
                moraleDelta: moraleRatePerSec * deltaTime,
                commanderRecoveringInCamp: side == .player ? pHeroDown : eHeroDown,
                encirclementCap: squads[sIdx].encirclementState == .encircled ? 45.0 : nil,
                supplyCap: stateRef.supplyMoraleCeiling,
                isFearlessBerserker: isFearless,
                inCloseEnemyContact: inCloseContact
            )
            squads[sIdx].morale = updated.morale
            squads[sIdx].moraleBracket = updated.bracket
            squads[sIdx].isRouting = updated.isRouting
        }
    }

    // MARK: - 七、主帅双端动作、近战挥砍/挑骑、百石硬弓与两段式重伤结算

    private mutating func stepBothCommanders(deltaTime: Double) {
        let pCamp = baseCampCoordinates(for: .player)
        let eCamp = baseCampCoordinates(for: .enemy)

        let pNearSupply = isHeroNearFriendlySupply(hero: playerHero)
        let eNearSupply = isHeroNearFriendlySupply(hero: enemyHero)

        // 1. 推进玩家主帅（RTS 视角下由自主护阵 AI 生成平滑输入）
        let effectivePlayerInput: HeroControlInputState
        if controlMode == .heroAction {
            effectivePlayerInput = heroInput
        } else {
            effectivePlayerInput = buildAutonomousCommanderInput(for: playerHero, campPos: pCamp)
        }

        var pEvents = HeroStepEvents()
        HeroCombatController.stepHero(
            hero: &playerHero,
            input: effectivePlayerInput,
            isManualControl: true,
            deltaTime: deltaTime,
            worldWidth: worldWidth,
            worldHeight: worldHeight,
            campPosition: pCamp,
            nearSupplyUnit: pNearSupply,
            events: &pEvents
        )
        processHeroActionEffects(
            side: .player,
            input: effectivePlayerInput,
            events: &pEvents
        )

        // 2. 推进敌方 AI 主帅（完全对等规则）
        let aiInput = buildAutonomousCommanderInput(for: enemyHero, campPos: eCamp)
        var eEvents = HeroStepEvents()
        // AI 主帅在周围友军动摇时自动释放三军战吼激励战线
        if enemyHero.isActiveOnField && enemyHero.grandWarCryCooldown <= 0.0 {
            let hasWaveringAlly = squads.contains { sq in
                sq.side == .enemy && sq.aliveCount > 0 && sq.morale < 42.0
                    && hypot(sq.anchorX - enemyHero.x, sq.anchorY - enemyHero.y) <= 300.0
            }
            if hasWaveringAlly {
                _ = HeroCombatController.triggerSkill(.grandWarCry, hero: &enemyHero, squads: &squads, events: &eEvents)
            }
        }
        HeroCombatController.stepHero(
            hero: &enemyHero,
            input: aiInput,
            isManualControl: true,
            deltaTime: deltaTime,
            worldWidth: worldWidth,
            worldHeight: worldHeight,
            campPosition: eCamp,
            nearSupplyUnit: eNearSupply,
            events: &eEvents
        )
        processHeroActionEffects(
            side: .enemy,
            input: aiInput,
            events: &eEvents
        )
    }

    private mutating func processHeroActionEffects(
        side: BattleSide,
        input: HeroControlInputState,
        events: inout HeroStepEvents
    ) {
        let enemySide = side.opponent
        var heroCopy = side == .player ? playerHero : enemyHero
        guard heroCopy.isActiveOnField else { return }

        // 1) 破阵突击沿途冲撞与挑飞判定
        if heroCopy.dashRemainingSec > 0.0 {
            let spearBonus = heroCopy.activeWeapon == .breakerSpear ? 1.40 : 1.0
            let dashDmg = 85.0 * spearBonus * heroCopy.attributeScale
            let hx = heroCopy.x
            let hy = heroCopy.y
            let dirX = heroCopy.dashDirX
            let dirY = heroCopy.dashDirY

            let dashHits = spatialGrid.queryInRadius(centerX: hx, centerY: hy, radius: 34.0, sideFilter: enemySide, maxResults: 8)
            for h in 0..<dashHits.count {
                let eIdx = dashHits[h].unitIndex
                guard !heroCopy.hasDashHit(eIdx) else { continue }
                heroCopy.recordDashHit(eIdx)
                applyDirectDamageToSoldier(
                    targetIndex: eIdx,
                    rawDamage: dashDmg,
                    armorPen: 0.50,
                    attackerX: hx,
                    attackerY: hy,
                    knockbackX: dirX * 26.0,
                    knockbackY: dirY * 26.0,
                    stunDuration: 0.85,
                    forceGiantStagger: true,
                    byHeroSide: side
                )
                events.triggeredHitStopSec = Double(GameConstants.heroHitStopMilliseconds) / 1000.0
            }
        }

        // 2) 铁壁横戈结束旋身 55px 横扫
        if events.ironBulwarkFinisherSweep {
            let hx = heroCopy.x
            let hy = heroCopy.y
            let sweepDmg = 70.0 * heroCopy.attributeScale
            let sweepHits = spatialGrid.queryInRadius(centerX: hx, centerY: hy, radius: 55.0, sideFilter: enemySide, maxResults: 12)
            for h in 0..<sweepHits.count {
                let eIdx = sweepHits[h].unitIndex
                let dx = soldiers[eIdx].x - hx
                let dy = soldiers[eIdx].y - hy
                let len = max(1.0, hypot(dx, dy))
                applyDirectDamageToSoldier(
                    targetIndex: eIdx,
                    rawDamage: sweepDmg,
                    armorPen: 0.40,
                    attackerX: hx,
                    attackerY: hy,
                    knockbackX: (dx / len) * 20.0,
                    knockbackY: (dy / len) * 20.0,
                    stunDuration: 0.45,
                    forceGiantStagger: false,
                    byHeroSide: side
                )
            }
        }

        // 3) 百石硬弓重箭发射
        if events.spawnedHeavyArrow {
            spawnProjectile(
                kind: .heroHeavyArrow,
                side: side,
                sourceUnitIndex: -2,
                originX: events.arrowOriginX,
                originY: events.arrowOriginY,
                targetX: events.arrowTargetX,
                targetY: events.arrowTargetY,
                speed: 520.0,
                arcHeight: 16.0,
                damage: events.arrowDamage,
                armorPen: 0.50,
                aoeRadius: 0.0,
                pierceCount: 2,
                appliesPoison: false,
                moraleShock: 2.5,
                structureBonus: 0.5
            )
        }

        // 4) 统帅佩刀（0.75s 120° 挥砍 3 人）与破阵大枪（1.05s 68px 直线穿透 2 人 + 2.2x 反骑挑落）
        if input.isPrimaryAttackHeld
            && heroCopy.dashRemainingSec <= 0.0
            && !heroCopy.isBlocking
            && heroCopy.attackCooldown <= 0.0
            && heroCopy.activeWeapon != .heavyWarbow {
            let hx = heroCopy.x
            let hy = heroCopy.y
            let facing = heroCopy.facingRadians

            if heroCopy.activeWeapon == .commandSaber {
                heroCopy.attackCooldown = 0.75
                heroCopy.outOfCombatTimer = 0.0
                var hits = 0
                let halfCone = Double.pi / 3.0 // 120° 总扇角 = 左右各 60°
                let saberCandidates = spatialGrid.queryInRadius(centerX: hx, centerY: hy, radius: 48.0, sideFilter: enemySide, maxResults: 12)
                for h in 0..<saberCandidates.count {
                    guard hits < 3 else { break }
                    let eIdx = saberCandidates[h].unitIndex
                    let ang = atan2(soldiers[eIdx].y - hy, soldiers[eIdx].x - hx)
                    if DamageMoraleCalculator.absoluteAngleBetween(facing, ang) <= halfCone {
                        hits += 1
                        applyDirectDamageToSoldier(
                            targetIndex: eIdx,
                            rawDamage: 48.0 * heroCopy.attributeScale,
                            armorPen: 0.25,
                            attackerX: hx,
                            attackerY: hy,
                            knockbackX: cos(facing) * 14.0,
                            knockbackY: sin(facing) * 14.0,
                            stunDuration: 0.15,
                            forceGiantStagger: false,
                            byHeroSide: side
                        )
                    }
                }
                // 同时检测是否劈中敌方主帅
                let otherHero = side == .player ? enemyHero : playerHero
                if hits < 3 && otherHero.isActiveOnField {
                    let d = hypot(otherHero.x - hx, otherHero.y - hy)
                    let ang = atan2(otherHero.y - hy, otherHero.x - hx)
                    if d <= 48.0 && DamageMoraleCalculator.absoluteAngleBetween(facing, ang) <= halfCone {
                        hits += 1
                        damageCommander(targetSide: enemySide, rawAttack: 48.0 * heroCopy.attributeScale, armorPen: 0.25, attackerX: hx, attackerY: hy, isMelee: true, byHero: true)
                    }
                }
                if hits > 0 && side == .player {
                    events.triggeredHitStopSec = Double(GameConstants.heroHitStopMilliseconds) / 1000.0
                }
            } else if heroCopy.activeWeapon == .breakerSpear {
                heroCopy.attackCooldown = 1.05
                heroCopy.outOfCombatTimer = 0.0
                var hits = 0
                let dirX = cos(facing)
                let dirY = sin(facing)
                let spearCandidates = spatialGrid.queryInRadius(centerX: hx + dirX * 34.0, centerY: hy + dirY * 34.0, radius: 40.0, sideFilter: enemySide, maxResults: 12)
                for h in 0..<spearCandidates.count {
                    guard hits < 2 else { break }
                    let eIdx = spearCandidates[h].unitIndex
                    let relX = soldiers[eIdx].x - hx
                    let relY = soldiers[eIdx].y - hy
                    let forwardProj = relX * dirX + relY * dirY
                    let lateralProj = abs(-relX * dirY + relY * dirX)
                    if forwardProj >= -4.0 && forwardProj <= 68.0 && lateralProj <= 18.0 {
                        hits += 1
                        let isCav = soldiers[eIdx].category == .cavalry
                        let cavMult = isCav ? 2.20 : 1.0
                        if isCav {
                            soldiers[eIdx].isChargeReady = false
                            soldiers[eIdx].straightSprintDuration = 0.0
                        }
                        applyDirectDamageToSoldier(
                            targetIndex: eIdx,
                            rawDamage: 62.0 * cavMult * heroCopy.attributeScale,
                            armorPen: 0.55,
                            attackerX: hx,
                            attackerY: hy,
                            knockbackX: dirX * (isCav ? 24.0 : 14.0),
                            knockbackY: dirY * (isCav ? 24.0 : 14.0),
                            stunDuration: isCav ? 1.20 : 0.20,
                            forceGiantStagger: false,
                            byHeroSide: side
                        )
                    }
                }
                let otherHero = side == .player ? enemyHero : playerHero
                if hits < 2 && otherHero.isActiveOnField {
                    let relX = otherHero.x - hx
                    let relY = otherHero.y - hy
                    let forwardProj = relX * dirX + relY * dirY
                    let lateralProj = abs(-relX * dirY + relY * dirX)
                    if forwardProj >= -4.0 && forwardProj <= 68.0 && lateralProj <= 20.0 {
                        hits += 1
                        damageCommander(targetSide: enemySide, rawAttack: 62.0 * heroCopy.attributeScale, armorPen: 0.55, attackerX: hx, attackerY: hy, isMelee: true, byHero: true)
                    }
                }
                if hits > 0 && side == .player {
                    events.triggeredHitStopSec = Double(GameConstants.heroHitStopMilliseconds) / 1000.0
                    events.cameraShakeDelta = max(events.cameraShakeDelta, 0.25)
                }
            }
        }

        if side == .player {
            playerHero = heroCopy
            if events.triggeredHitStopSec > 0.0 {
                hitStopRemainingSec = max(hitStopRemainingSec, events.triggeredHitStopSec)
            }
            cameraShakeIntensity = min(1.0, cameraShakeIntensity + events.cameraShakeDelta)
        } else {
            enemyHero = heroCopy
        }
    }

    // MARK: - 八、分队锚点推进与单兵 L3 弹簧槽位、工兵采运、陷阱与近远交战

    private mutating func stepSquadAnchors(deltaTime: Double) {
        for idx in 0..<squads.count where squads[idx].aliveCount > 0 {
            if squads[idx].isRouting {
                let camp = baseCampCoordinates(for: squads[idx].side)
                squads[idx].targetX = camp.x
                squads[idx].targetY = camp.y
                squads[idx].facingRadians = atan2(camp.y - squads[idx].anchorY, camp.x - squads[idx].anchorX)
                continue
            }

            if squads[idx].order == .feignedRetreat {
                squads[idx].feignedRetreatTimer -= deltaTime
                if squads[idx].feignedRetreatTimer <= 0.0 {
                    // 诈败诱敌时间届满，反身转入全军冲锋反扑！
                    squads[idx].order = .allOutCharge
                    let oppSide = squads[idx].side.opponent
                    if let nearestEnemySq = squads.first(where: { $0.side == oppSide && $0.aliveCount > 0 }) {
                        squads[idx].targetX = nearestEnemySq.anchorX
                        squads[idx].targetY = nearestEnemySq.anchorY
                    }
                }
            }

            if let firstWp = squads[idx].waypoints.first {
                let dist = hypot(firstWp.x - squads[idx].anchorX, firstWp.y - squads[idx].anchorY)
                if dist <= 65.0 {
                    squads[idx].waypoints.removeFirst()
                }
            }

            let destX = squads[idx].waypoints.first?.x ?? squads[idx].targetX
            let destY = squads[idx].waypoints.first?.y ?? squads[idx].targetY
            let dx = destX - squads[idx].anchorX
            let dy = destY - squads[idx].anchorY
            if dx * dx + dy * dy > 36.0 && squads[idx].order != .retreat {
                squads[idx].facingRadians = atan2(dy, dx)
            } else if squads[idx].order == .retreat {
                // 交替撤退：面向敌人举盾边退边挡，绝不背身裸奔！
                let enemyCamp = baseCampCoordinates(for: squads[idx].side.opponent)
                squads[idx].facingRadians = atan2(enemyCamp.y - squads[idx].anchorY, enemyCamp.x - squads[idx].anchorX)
            }
        }
    }

    private mutating func stepSoldiersAndCombat(deltaTime: Double) {
        let pFervor = playerState.bloodMoonFervorRemainingSec > 0.0
        let eFervor = enemyState.bloodMoonFervorRemainingSec > 0.0

        for i in 0..<soldiers.count {
            guard soldiers[i].isActive else { continue }

            // 致命倾倒过渡至战场遗骸
            if soldiers[i].actionState == .dyingFall {
                soldiers[i].actionTimer -= deltaTime
                if soldiers[i].actionTimer <= 0.0 {
                    recordCorpseDecal(from: soldiers[i])
                    soldiers[i].isActive = false
                }
                continue
            }

            guard soldiers[i].hp > 0.0 else {
                soldiers[i].isActive = false
                continue
            }

            // 递减各类状态计时器
            soldiers[i].attackCooldown = max(0.0, soldiers[i].attackCooldown - deltaTime)
            soldiers[i].chargeCooldown = max(0.0, soldiers[i].chargeCooldown - deltaTime)
            soldiers[i].camelSpookedTimer = max(0.0, soldiers[i].camelSpookedTimer - deltaTime)
            soldiers[i].poisonSlowTimer = max(0.0, soldiers[i].poisonSlowTimer - deltaTime)
            soldiers[i].outOfCombatTimer += deltaTime
            soldiers[i].animPhase += deltaTime * 6.0

            // 雾林毒箭持续流血毒伤结算
            if soldiers[i].poisonDotTimer > 0.0 {
                soldiers[i].poisonDotTimer = max(0.0, soldiers[i].poisonDotTimer - deltaTime)
                soldiers[i].hp -= 6.5 * deltaTime
                if soldiers[i].hp <= 0.0 {
                    killSoldier(at: i, killerSide: soldiers[i].side.opponent, byHeroSide: nil)
                    continue
                }
            }

            // 眩晕硬直期无法移动或攻击
            if soldiers[i].stunTimer > 0.0 {
                soldiers[i].stunTimer = max(0.0, soldiers[i].stunTimer - deltaTime)
                soldiers[i].actionState = .staggerHit
                soldiers[i].straightSprintDuration = 0.0
                soldiers[i].isChargeReady = false
                continue
            }

            let side = soldiers[i].side
            let enemySide = side.opponent
            let sqId = soldiers[i].squadId
            let hasValidSquad = sqId >= 0 && sqId < squads.count
            let sqOrder = hasValidSquad ? squads[sqId].order : .advance
            let sqFormation = hasValidSquad ? squads[sqId].formation : .phalanxRect
            let sqFormationActive = hasValidSquad ? squads[sqId].isFormationBonusActive : false
            let sqMoraleBracket = hasValidSquad ? squads[sqId].moraleBracket : .steady
            let sqIsRouting = hasValidSquad ? squads[sqId].isRouting : false
            let sqWarCry = hasValidSquad ? (squads[sqId].warCryBuffTimer > 0.0) : false
            let rationStage = side == .player ? playerState.rationStage : enemyState.rationStage
            let fervorActive = side == .player ? pFervor : eFervor

            // 1. 辎重工兵专属采集与本阵警钟入营箭孔协防逻辑
            if soldiers[i].unitType == .sapper && !sqIsRouting {
                stepSapperBehavior(unitIndex: i, deltaTime: deltaTime)
                continue
            }

            let currentTerrain = terrainAt(x: soldiers[i].x, y: soldiers[i].y)

            // 2. 雾林影袭神射潜行状态更新（密林 1.5s 或脱战 4.0s 进入潜行隐身）
            if soldiers[i].unitType == .wulinShadowSniper {
                let stealthThreshold = currentTerrain == .denseForest ? 1.5 : 4.0
                if soldiers[i].outOfCombatTimer >= stealthThreshold && !sqIsRouting {
                    soldiers[i].isStealthed = true
                }
            } else if sqOrder == .ambushHide && currentTerrain == .denseForest && soldiers[i].outOfCombatTimer >= 1.5 {
                soldiers[i].isStealthed = true
            } else {
                soldiers[i].isStealthed = false
            }

            // 3. 铁鹰重装神弩手换弹期自动转身背大盾减免 60% 箭伤
            soldiers[i].isReloadingBackShield = (soldiers[i].unitType == .tieyingPaviseCrossbow && soldiers[i].attackCooldown > 0.35)

            // 4. 计算当前单位实际最大移速与有效射程
            let maxMoveSpeed = DamageMoraleCalculator.effectiveUnitMoveSpeed(
                baseMoveSpeed: soldiers[i].baseMoveSpeed,
                category: soldiers[i].category,
                armor: soldiers[i].baseArmor,
                faction: soldiers[i].faction,
                terrain: currentTerrain,
                weather: context.weather,
                formation: sqFormation,
                formationBonusActive: sqFormationActive,
                moraleBracket: sqMoraleBracket,
                rationStage: rationStage,
                warCryActive: sqWarCry,
                bloodMoonFervorActive: fervorActive,
                poisonSlowActive: soldiers[i].poisonSlowTimer > 0.0,
                camelSpooked: soldiers[i].camelSpookedTimer > 0.0
            )

            let effAttackRange = computeEffectiveAttackRange(for: soldiers[i], terrain: currentTerrain)

            // 5. 溃逃士兵：丢盾举白旗狂奔逃回本阵，无法攻击
            if sqIsRouting {
                let camp = baseCampCoordinates(for: side)
                let dx = camp.x - soldiers[i].x
                let dy = camp.y - soldiers[i].y
                let dist = hypot(dx, dy)
                if dist > 35.0 {
                    let ux = dx / dist
                    let uy = dy / dist
                    soldiers[i].vx = ux * maxMoveSpeed
                    soldiers[i].vy = uy * maxMoveSpeed
                    soldiers[i].facingRadians = atan2(uy, ux)
                    moveSoldierWithWallAndTrapCheck(unitIndex: i, deltaTime: deltaTime)
                }
                soldiers[i].actionState = .routPanic
                soldiers[i].isBraced = false
                soldiers[i].isChargeReady = false
                soldiers[i].straightSprintDuration = 0.0
                continue
            }

            // 6. L3 本能反应：长枪方阵兵 / 神机重卫检测到 140px 内敌骑冲来且非冲锋命令时自动停步架枪！
            var autoBraceDetected = false
            if soldiers[i].antiCavalryMultiplier >= 2.0 && sqOrder != .allOutCharge && sqOrder != .retreat {
                let px = soldiers[i].x
                let py = soldiers[i].y
                let braceScan = spatialGrid.queryInRadius(centerX: px, centerY: py, radius: 140.0, sideFilter: enemySide, maxResults: 12)
                for h in 0..<braceScan.count {
                    let eIdx = braceScan[h].unitIndex
                    if soldiers[eIdx].category == .cavalry {
                        autoBraceDetected = true
                        soldiers[i].facingRadians = atan2(soldiers[eIdx].y - py, soldiers[eIdx].x - px)
                        break
                    }
                }
            }
            soldiers[i].isBraced = (soldiers[i].antiCavalryMultiplier > 1.0)
                && (autoBraceDetected || sqOrder == .holdGround || sqFormation == .circleDefense || hypot(soldiers[i].vx, soldiers[i].vy) < maxMoveSpeed * 0.45)

            // 7. 索敌（利用 120px 均匀空间哈希网格检索最近合法敌军）
            let searchRadius = max(effAttackRange + 24.0, sqOrder == .holdGround ? effAttackRange + 30.0 : 240.0)
            let nearestEnemyIdx = spatialGrid.findNearestEnemy(
                fromX: soldiers[i].x,
                fromY: soldiers[i].y,
                enemySide: enemySide,
                maxRange: searchRadius,
                minRange: soldiers[i].minRange,
                viewerFaction: soldiers[i].faction,
                viewerIsCavalryScout: soldiers[i].unitType == .lightCavalry
            )

            // 密林设伏未暴露前屏息按兵不动，直到敌军踏入 150px 伏击圈暴起！
            if sqOrder == .ambushHide && soldiers[i].isStealthed {
                if nearestEnemyIdx == -1 || hypot(soldiers[nearestEnemyIdx].x - soldiers[i].x, soldiers[nearestEnemyIdx].y - soldiers[i].y) > 155.0 {
                    soldiers[i].vx = 0.0
                    soldiers[i].vy = 0.0
                    soldiers[i].actionState = .idleReady
                    continue
                }
            }

            // 8. 炎龙神机重卫接敌前（45~135px）自动投掷震天火雷破阵并炸降敌军士气 -12！
            if soldiers[i].unitType == .yanlongHalberdGrenadier
                && soldiers[i].grenadeCharges > 0
                && nearestEnemyIdx != -1 {
                let edx = soldiers[nearestEnemyIdx].x - soldiers[i].x
                let edy = soldiers[nearestEnemyIdx].y - soldiers[i].y
                let eDist = hypot(edx, edy)
                if eDist >= 44.0 && eDist <= 135.0 {
                    soldiers[i].grenadeCharges -= 1
                    soldiers[i].outOfCombatTimer = 0.0
                    soldiers[i].facingRadians = atan2(edy, edx)
                    spawnProjectile(
                        kind: .thunderGrenade,
                        side: side,
                        sourceUnitIndex: i,
                        originX: soldiers[i].x,
                        originY: soldiers[i].y,
                        targetX: soldiers[nearestEnemyIdx].x,
                        targetY: soldiers[nearestEnemyIdx].y,
                        speed: 250.0,
                        arcHeight: 42.0,
                        damage: 46.0,
                        armorPen: 0.55,
                        aoeRadius: 64.0,
                        pierceCount: 1,
                        appliesPoison: false,
                        moraleShock: 12.0,
                        structureBonus: 1.5
                    )
                }
            }

            // 9. 苍狼怯薛骑射“曼古歹”边退边射无盲区风筝重步逻辑
            let isMangudaiHorseArcher = soldiers[i].unitType == .canglangKeshigHorseArcher
            if isMangudaiHorseArcher && nearestEnemyIdx != -1 {
                let ex = soldiers[nearestEnemyIdx].x
                let ey = soldiers[nearestEnemyIdx].y
                let dist = hypot(ex - soldiers[i].x, ey - soldiers[i].y)
                let enemySqRouting = soldiers[nearestEnemyIdx].squadId >= 0
                    && soldiers[nearestEnemyIdx].squadId < squads.count
                    && squads[soldiers[nearestEnemyIdx].squadId].morale < 38.0

                if !enemySqRouting && dist < 175.0 && soldiers[nearestEnemyIdx].category != .cavalry {
                    // 敌步兵逼近 175px：策马后撤拉开距离的同时回头挽弓齐射！
                    let awayX = (soldiers[i].x - ex) / max(1.0, dist)
                    let awayY = (soldiers[i].y - ey) / max(1.0, dist)
                    soldiers[i].vx = awayX * maxMoveSpeed * 0.90
                    soldiers[i].vy = awayY * maxMoveSpeed * 0.90
                    soldiers[i].facingRadians = atan2(ey - soldiers[i].y, ex - soldiers[i].x)
                    moveSoldierWithWallAndTrapCheck(unitIndex: i, deltaTime: deltaTime)
                    if dist <= effAttackRange && soldiers[i].attackCooldown <= 0.0 {
                        executeRangedFire(attackerIndex: i, targetX: ex, targetY: ey)
                    } else {
                        soldiers[i].actionState = .marchRun
                    }
                    continue
                }
            }

            // 10. 敌军士兵或敌方主帅进入有效射程/近战距离 -> 执行攻击结算
            let oppHero = enemySide == .player ? playerHero : enemyHero
            let heroDist = oppHero.isActiveOnField ? hypot(oppHero.x - soldiers[i].x, oppHero.y - soldiers[i].y) : Double.greatestFiniteMagnitude
            let canTargetOppHero = oppHero.isActiveOnField
                && heroDist <= searchRadius
                && heroDist >= soldiers[i].minRange
                && sqOrder != .feignedRetreat
                && sqOrder != .retreat
            let nearestSoldierDist = nearestEnemyIdx != -1
                ? hypot(soldiers[nearestEnemyIdx].x - soldiers[i].x, soldiers[nearestEnemyIdx].y - soldiers[i].y)
                : Double.greatestFiniteMagnitude

            if canTargetOppHero && heroDist < nearestSoldierDist && heroDist <= effAttackRange + 10.0 {
                soldiers[i].facingRadians = atan2(oppHero.y - soldiers[i].y, oppHero.x - soldiers[i].x)
                let isRangedUnit = soldiers[i].category == .ranged || soldiers[i].category == .siege
                    || (isMangudaiHorseArcher && heroDist > 42.0)
                if isRangedUnit {
                    soldiers[i].vx = 0.0
                    soldiers[i].vy = 0.0
                    if soldiers[i].attackCooldown <= 0.0 {
                        executeRangedFire(attackerIndex: i, targetX: oppHero.x, targetY: oppHero.y)
                    } else {
                        soldiers[i].actionState = soldiers[i].isReloadingBackShield ? .shieldBlock : .idleReady
                    }
                } else {
                    soldiers[i].vx *= 0.25
                    soldiers[i].vy *= 0.25
                    if soldiers[i].attackCooldown <= 0.0 {
                        executeMeleeStrikeAgainstCommander(attackerIndex: i, targetSide: enemySide)
                    } else {
                        soldiers[i].actionState = soldiers[i].shieldRangedBlock >= 0.35 ? .shieldBlock : .meleeWindup
                    }
                }
                continue
            }

            if nearestEnemyIdx != -1 {
                let ex = soldiers[nearestEnemyIdx].x
                let ey = soldiers[nearestEnemyIdx].y
                let dist = nearestSoldierDist
                let isRangedUnit = soldiers[i].category == .ranged || soldiers[i].category == .siege
                    || (isMangudaiHorseArcher && dist > 42.0)

                if dist <= effAttackRange && dist >= soldiers[i].minRange && sqOrder != .feignedRetreat && sqOrder != .retreat {
                    soldiers[i].facingRadians = atan2(ey - soldiers[i].y, ex - soldiers[i].x)
                    if isRangedUnit {
                        soldiers[i].vx = 0.0
                        soldiers[i].vy = 0.0
                        if soldiers[i].attackCooldown <= 0.0 {
                            executeRangedFire(attackerIndex: i, targetX: ex, targetY: ey)
                        } else {
                            soldiers[i].actionState = soldiers[i].isReloadingBackShield ? .shieldBlock : .idleReady
                        }
                    } else {
                        soldiers[i].vx *= 0.25
                        soldiers[i].vy *= 0.25
                        if soldiers[i].attackCooldown <= 0.0 {
                            executeMeleeStrike(attackerIndex: i, targetIndex: nearestEnemyIdx)
                        } else {
                            soldiers[i].actionState = soldiers[i].shieldRangedBlock >= 0.35 ? .shieldBlock : .meleeWindup
                        }
                    }
                    continue
                }
            }

            // 11. 检查是否攻击敌方本阵大营、城门、城墙或箭塔（含劫掠敌营粮车夺 150 粮！）
            if sqOrder != .retreat && sqOrder != .feignedRetreat {
                if let stIdx = findAttackableStructure(for: soldiers[i], effectiveRange: effAttackRange) {
                    let st = structures[stIdx]
                    soldiers[i].facingRadians = atan2(st.y - soldiers[i].y, st.x - soldiers[i].x)
                    soldiers[i].vx = 0.0
                    soldiers[i].vy = 0.0
                    if soldiers[i].attackCooldown <= 0.0 {
                        executeStructureAttack(attackerIndex: i, structureIndex: stIdx)
                    } else {
                        soldiers[i].actionState = .meleeWindup
                    }
                    continue
                }
            }

            // 12. 弹簧阵型槽位机动与局部同阵营碰撞排斥
            var goalX = soldiers[i].x
            var goalY = soldiers[i].y

            if nearestEnemyIdx != -1 && sqOrder != .holdGround && sqOrder != .feignedRetreat && sqOrder != .retreat && soldiers[i].category != .ranged && soldiers[i].category != .siege {
                goalX = soldiers[nearestEnemyIdx].x
                goalY = soldiers[nearestEnemyIdx].y
            } else if canTargetOppHero && sqOrder != .holdGround && soldiers[i].category != .ranged && soldiers[i].category != .siege {
                goalX = oppHero.x
                goalY = oppHero.y
            } else if hasValidSquad {
                let sq = squads[sqId]
                let navX = sq.waypoints.first?.x ?? sq.targetX
                let navY = sq.waypoints.first?.y ?? sq.targetY
                let cosF = cos(sq.facingRadians)
                let sinF = sin(sq.facingRadians)
                let worldOffX = soldiers[i].slotOffsetX * cosF - soldiers[i].slotOffsetY * sinF
                let worldOffY = soldiers[i].slotOffsetX * sinF + soldiers[i].slotOffsetY * cosF
                goalX = navX + worldOffX
                goalY = navY + worldOffY
            }

            let toGoalX = goalX - soldiers[i].x
            let toGoalY = goalY - soldiers[i].y
            let goalDist = hypot(toGoalX, toGoalY)

            if goalDist > 6.0 && !autoBraceDetected {
                var dirX = toGoalX / goalDist
                var dirY = toGoalY / goalDist

                // 叠加邻域友军轻度软排斥力防火柴人完全重叠成一点
                var sepX = 0.0
                var sepY = 0.0
                let ux = soldiers[i].x
                let uy = soldiers[i].y
                let myR = soldiers[i].collisionRadius
                let neighborHits = spatialGrid.queryInRadius(centerX: ux, centerY: uy, radius: myR * 2.2, sideFilter: side, excludeUnitIndex: i, maxResults: 8)
                for h in 0..<neighborHits.count {
                    let entry = neighborHits[h]
                    if entry.distanceSquared > 0.001 {
                        let d = sqrt(entry.distanceSquared)
                        let overlap = (myR * 2.0 - d) / (myR * 2.0)
                        if overlap > 0.0 {
                            let pos = spatialGrid.cachedPositionAndRadius(of: entry.unitIndex)
                            sepX += ((ux - pos.x) / d) * overlap * 0.55
                            sepY += ((uy - pos.y) / d) * overlap * 0.55
                        }
                    }
                }
                dirX += sepX
                dirY += sepY
                let norm = max(0.001, hypot(dirX, dirY))
                dirX /= norm
                dirY /= norm

                let desiredSpeed = min(maxMoveSpeed, goalDist * 3.5)
                let prevHeading = atan2(soldiers[i].vy, soldiers[i].vx)
                let nextHeading = atan2(dirY, dirX)
                soldiers[i].vx = dirX * desiredSpeed
                soldiers[i].vy = dirY * desiredSpeed
                if sqOrder != .retreat {
                    soldiers[i].facingRadians = nextHeading
                }

                // 骑兵 / 突击兵连续直线高速加速满 2.5s 激活冲锋首击倍率（涉水与密林禁冲锋）
                let canChargeTerrain = currentTerrain != .riverFord && currentTerrain != .denseForest
                let straightEnough = DamageMoraleCalculator.absoluteAngleBetween(prevHeading, nextHeading) <= 0.42
                if canChargeTerrain
                    && soldiers[i].chargeMultiplier > 1.0
                    && soldiers[i].chargeCooldown <= 0.0
                    && desiredSpeed >= maxMoveSpeed * 0.85
                    && straightEnough {
                    soldiers[i].straightSprintDuration += deltaTime
                    if soldiers[i].straightSprintDuration >= GameConstants.chargeWindupSeconds {
                        soldiers[i].isChargeReady = true
                    }
                } else if !canChargeTerrain {
                    soldiers[i].straightSprintDuration = 0.0
                    soldiers[i].isChargeReady = false
                }

                soldiers[i].actionState = soldiers[i].isChargeReady ? .chargeSprint : .marchRun
                moveSoldierWithWallAndTrapCheck(unitIndex: i, deltaTime: deltaTime)
            } else {
                soldiers[i].vx = 0.0
                soldiers[i].vy = 0.0
                soldiers[i].straightSprintDuration = max(0.0, soldiers[i].straightSprintDuration - deltaTime * 0.5)
                soldiers[i].actionState = soldiers[i].shieldRangedBlock >= 0.35 ? .shieldBlock : .idleReady
            }
        }
    }

    // MARK: - 九、近战刀枪碰撞、反骑动能停马、铁浮图凿穿与狂战吸血结算

    /// 普通士兵近战劈刺敌我主帅英雄（联动主帅 0.25s 精准弹反、铁壁横戈减伤与两段式落马重伤机制）
    private mutating func executeMeleeStrikeAgainstCommander(attackerIndex: Int, targetSide: BattleSide) {
        guard soldiers[attackerIndex].isActive, soldiers[attackerIndex].hp > 0.0 else { return }
        let oppHero = targetSide == .player ? playerHero : enemyHero
        guard oppHero.isActiveOnField else { return }

        var attacker = soldiers[attackerIndex]
        var interval = attacker.attackInterval
        if attacker.squadId >= 0 && attacker.squadId < squads.count && squads[attacker.squadId].warCryBuffTimer > 0.0 {
            interval /= 1.15
        }
        if attacker.unitType == .xueyueWardrumBerserker {
            let missingRatio = max(0.0, (attacker.maxHp - attacker.hp) / max(1.0, attacker.maxHp))
            interval /= (1.0 + 0.06 * floor(missingRatio * 10.0))
        }
        attacker.attackCooldown = max(0.28, interval)
        attacker.actionState = .meleeStrike
        attacker.outOfCombatTimer = 0.0
        attacker.isStealthed = false

        let aSq = (attacker.squadId >= 0 && attacker.squadId < squads.count) ? squads[attacker.squadId] : nil
        let aRation = attacker.side == .player ? playerState.rationStage : enemyState.rationStage
        var rawAtk = attacker.baseAttack

        if attacker.isChargeReady {
            attacker.isChargeReady = false
            attacker.straightSprintDuration = 0.0
            let hungerCdMult = (aRation == .hungry || aRation == .starving) ? 1.50 : 1.0
            attacker.chargeCooldown = GameConstants.chargeCooldownSeconds * hungerCdMult
            var cMult = attacker.chargeMultiplier
            if attacker.faction == .xuanjia && attacker.category == .cavalry {
                cMult *= 1.30
            }
            if aSq?.formation == .wedgeCharge && (aSq?.isFormationBonusActive ?? false) {
                cMult *= 1.25
            }
            if attacker.camelSpookedTimer > 0.0 {
                cMult *= 0.75
            }
            rawAtk *= cMult
        }
        soldiers[attackerIndex] = attacker

        if aSq?.moraleBracket == .high {
            rawAtk *= 1.12
        } else if aSq?.moraleBracket == .wavering {
            rawAtk *= 0.80
        }
        if aRation == .starving {
            rawAtk *= 0.75
        }
        if context.weather == .night && attacker.faction == .xueyue {
            rawAtk *= 1.15
        }

        damageCommander(
            targetSide: targetSide,
            rawAttack: rawAtk,
            armorPen: attacker.armorPenetration,
            attackerX: attacker.x,
            attackerY: attacker.y,
            isMelee: true,
            byHero: false
        )

        if attacker.unitType == .xueyueWardrumBerserker && soldiers[attackerIndex].hp > 0.0 {
            soldiers[attackerIndex].hp = min(soldiers[attackerIndex].maxHp, soldiers[attackerIndex].hp + rawAtk * 0.10)
        }
    }

    private mutating func executeMeleeStrike(attackerIndex: Int, targetIndex: Int) {
        guard soldiers[attackerIndex].isActive,
              soldiers[targetIndex].isActive,
              soldiers[targetIndex].hp > 0.0 else { return }

        var attacker = soldiers[attackerIndex]
        let target = soldiers[targetIndex]

        // 计算攻击间隔（含三军战吼 +15% 攻速，血月狂战士每损血 10% 攻速 +6%）
        var interval = attacker.attackInterval
        if attacker.squadId >= 0 && attacker.squadId < squads.count && squads[attacker.squadId].warCryBuffTimer > 0.0 {
            interval /= 1.15
        }
        if attacker.unitType == .xueyueWardrumBerserker {
            let missingRatio = max(0.0, (attacker.maxHp - attacker.hp) / max(1.0, attacker.maxHp))
            let missingDeciles = floor(missingRatio * 10.0)
            interval /= (1.0 + 0.06 * missingDeciles)
        }
        attacker.attackCooldown = max(0.28, interval)
        attacker.actionState = .meleeStrike
        attacker.outOfCombatTimer = 0.0
        attacker.isStealthed = false

        let aSq = (attacker.squadId >= 0 && attacker.squadId < squads.count) ? squads[attacker.squadId] : nil
        let tSq = (target.squadId >= 0 && target.squadId < squads.count) ? squads[target.squadId] : nil
        let aTerrain = terrainAt(x: attacker.x, y: attacker.y)
        let tTerrain = terrainAt(x: target.x, y: target.y)
        let aRation = attacker.side == .player ? playerState.rationStage : enemyState.rationStage

        let incAngle = DamageMoraleCalculator.incomingAttackAngle(
            targetX: target.x,
            targetY: target.y,
            targetFacingRadians: target.facingRadians,
            attackerX: attacker.x,
            attackerY: attacker.y
        )

        // 若冲锋铁骑正撞非溃逃架枪长枪/戟兵正面：长枪先手触发 3.2x 反骑 + 30% 动能破甲并当场停马！
        let targetDirection = DamageMoraleCalculator.classifyHitDirection(
            incomingAngleRadians: incAngle,
            targetFormation: tSq?.formation ?? .phalanxRect,
            targetFormationBonusActive: tSq?.isFormationBonusActive ?? false,
            targetTerrain: tTerrain
        )
        if attacker.category == .cavalry
            && attacker.isChargeReady
            && target.antiCavalryMultiplier >= 1.8
            && target.isBraced
            && !(tSq?.isRouting ?? false)
            && targetDirection == .front {
            // 强制清空骑兵冲锋动量，并结算架枪反噬穿刺
            attacker.isChargeReady = false
            attacker.straightSprintDuration = 0.0
            let hungerCdMult = aRation == .hungry || aRation == .starving ? 1.50 : 1.0
            attacker.chargeCooldown = GameConstants.chargeCooldownSeconds * hungerCdMult
            soldiers[attackerIndex] = attacker

            let counterOut = DamageMoraleCalculator.calculateDamage(
                DamageCalculationInput(
                    baseAttack: target.baseAttack,
                    attackerArmorPenetration: target.armorPenetration,
                    attackerChargeMultiplier: target.chargeMultiplier,
                    attackerAntiCavMultiplier: target.antiCavalryMultiplier,
                    attackerFaction: target.faction,
                    attackerTerrain: tTerrain,
                    attackerWeather: context.weather,
                    attackerMoraleBracket: tSq?.moraleBracket ?? .steady,
                    attackerRationStage: target.side == .player ? playerState.rationStage : enemyState.rationStage,
                    attackerFormation: tSq?.formation ?? .phalanxRect,
                    attackerFormationBonusActive: tSq?.isFormationBonusActive ?? true,
                    attackerIsCharging: false,
                    attackerIsBraced: true,
                    attackerIsRouting: false,
                    isMelee: true,
                    targetBaseArmor: attacker.baseArmor,
                    targetShieldRangedBlock: attacker.shieldRangedBlock,
                    targetCategory: attacker.category,
                    targetFaction: attacker.faction,
                    targetTerrain: aTerrain,
                    targetMoraleBracket: aSq?.moraleBracket ?? .steady,
                    targetFormation: aSq?.formation ?? .phalanxRect,
                    targetFormationBonusActive: aSq?.isFormationBonusActive ?? true,
                    targetEncirclement: aSq?.encirclementState ?? .clear,
                    targetIsChargingCavalry: true,
                    targetSquadRiverWadingRatio: aSq?.riverWadingRatio ?? 0.0,
                    incomingAngleDifferenceRadians: 0.0
                )
            )
            applyResolvedDamage(
                toSoldierAt: attackerIndex,
                damage: counterOut.finalDamage,
                moraleHit: counterOut.moraleShockToTarget * 1.4,
                killerSide: target.side,
                causedByCharge: false,
                attackerFaction: target.faction,
                attackerSquadId: target.squadId
            )
            if !soldiers[attackerIndex].isActive || soldiers[attackerIndex].hp <= 0.0 {
                return
            }
            attacker = soldiers[attackerIndex]
        }

        let usedCharge = attacker.isChargeReady
        if usedCharge {
            attacker.isChargeReady = false
            attacker.straightSprintDuration = 0.0
            let hungerCdMult = (aRation == .hungry || aRation == .starving) ? 1.50 : 1.0
            attacker.chargeCooldown = GameConstants.chargeCooldownSeconds * hungerCdMult
        }
        soldiers[attackerIndex] = attacker

        let dmgOut = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: attacker.baseAttack,
                attackerArmorPenetration: attacker.armorPenetration,
                attackerChargeMultiplier: attacker.chargeMultiplier,
                attackerAntiCavMultiplier: attacker.antiCavalryMultiplier,
                attackerFaction: attacker.faction,
                attackerTerrain: aTerrain,
                attackerWeather: context.weather,
                attackerMoraleBracket: aSq?.moraleBracket ?? .steady,
                attackerRationStage: aRation,
                attackerFormation: aSq?.formation ?? .phalanxRect,
                attackerFormationBonusActive: aSq?.isFormationBonusActive ?? true,
                attackerIsCharging: usedCharge,
                attackerIsBraced: attacker.isBraced,
                attackerIsRouting: aSq?.isRouting ?? false,
                attackerCamelSpooked: attacker.camelSpookedTimer > 0.0,
                isMelee: true,
                targetBaseArmor: target.baseArmor,
                targetShieldRangedBlock: target.shieldRangedBlock,
                targetCategory: target.category,
                targetFaction: target.faction,
                targetTerrain: tTerrain,
                targetMoraleBracket: tSq?.moraleBracket ?? .steady,
                targetFormation: tSq?.formation ?? .phalanxRect,
                targetFormationBonusActive: tSq?.isFormationBonusActive ?? true,
                targetEncirclement: tSq?.encirclementState ?? .clear,
                targetIsChargingCavalry: target.category == .cavalry && (target.isChargeReady || target.actionState == .chargeSprint),
                targetIsBracedPolearm: target.isBraced && target.category == .polearm && !(tSq?.isRouting ?? false),
                targetSquadRiverWadingRatio: tSq?.riverWadingRatio ?? 0.0,
                incomingAngleDifferenceRadians: incAngle
            )
        )

        // 若我方长枪正面命中冲锋敌骑，强制打断敌骑冲锋动量
        if dmgOut.triggeredBracedAntiCav {
            soldiers[targetIndex].isChargeReady = false
            soldiers[targetIndex].straightSprintDuration = 0.0
            soldiers[targetIndex].chargeCooldown = GameConstants.chargeCooldownSeconds
        }

        // 血月狂战祭团近战吸血 (18%)
        if attacker.unitType == .xueyueWardrumBerserker && soldiers[attackerIndex].hp > 0.0 {
            soldiers[attackerIndex].hp = min(soldiers[attackerIndex].maxHp, soldiers[attackerIndex].hp + dmgOut.finalDamage * 0.18)
        }

        applyResolvedDamage(
            toSoldierAt: targetIndex,
            damage: dmgOut.finalDamage,
            moraleHit: dmgOut.moraleShockToTarget,
            killerSide: attacker.side,
            causedByCharge: usedCharge,
            attackerFaction: attacker.faction,
            attackerSquadId: attacker.squadId
        )

        // 重型巨斧兵半圆横扫溅射 & 霜原巨熊破阵者重锤扇形震飞前排
        if attacker.unitType == .greatAxeman || attacker.unitType == .shuangyuanGiantBreaker {
            let splashFactor = attacker.unitType == .shuangyuanGiantBreaker ? 0.55 : 0.45
            let knockForce = attacker.unitType == .shuangyuanGiantBreaker ? 22.0 : 8.0
            var extraHits = 0
            let ax = attacker.x
            let ay = attacker.y
            let facing = attacker.facingRadians
            let cleaveHits = spatialGrid.queryInRadius(centerX: ax, centerY: ay, radius: 42.0, sideFilter: attacker.side.opponent, excludeUnitIndex: targetIndex, maxResults: 8)
            for h in 0..<cleaveHits.count {
                guard extraHits < 2 else { break }
                let sIdx = cleaveHits[h].unitIndex
                let ang = atan2(soldiers[sIdx].y - ay, soldiers[sIdx].x - ax)
                if DamageMoraleCalculator.absoluteAngleBetween(facing, ang) <= (Double.pi * 0.5) {
                    extraHits += 1
                    applyDirectDamageToSoldier(
                        targetIndex: sIdx,
                        rawDamage: dmgOut.finalDamage * splashFactor,
                        armorPen: attacker.armorPenetration,
                        attackerX: ax,
                        attackerY: ay,
                        knockbackX: cos(facing) * knockForce,
                        knockbackY: sin(facing) * knockForce,
                        stunDuration: attacker.unitType == .shuangyuanGiantBreaker ? 0.35 : 0.0,
                        forceGiantStagger: false,
                        byHeroSide: nil
                    )
                }
            }
        }

        // 玄甲具装铁浮图冲锋凿穿：首层非长枪薄弱步兵被推开，铁骑直踏后排
        if usedCharge && attacker.unitType == .xuanjiaCataphract && target.category != .polearm {
            let pushX = cos(attacker.facingRadians) * 26.0
            let pushY = sin(attacker.facingRadians) * 26.0
            soldiers[attackerIndex].x = clamp(soldiers[attackerIndex].x + pushX, minVal: 20.0, maxVal: worldWidth - 20.0)
            soldiers[attackerIndex].y = clamp(soldiers[attackerIndex].y + pushY, minVal: 20.0, maxVal: worldHeight - 20.0)
            if soldiers[targetIndex].isActive && soldiers[targetIndex].hp > 0.0 && soldiers[targetIndex].unitType != .shuangyuanGiantBreaker {
                soldiers[targetIndex].x = clamp(soldiers[targetIndex].x - pushY * 0.6, minVal: 20.0, maxVal: worldWidth - 20.0)
                soldiers[targetIndex].y = clamp(soldiers[targetIndex].y + pushX * 0.6, minVal: 20.0, maxVal: worldHeight - 20.0)
            }
        }
    }

    // MARK: - 十、远程齐射、投石攻城、箭塔与弹道碰撞结算

    private mutating func executeRangedFire(attackerIndex: Int, targetX: Double, targetY: Double) {
        var attacker = soldiers[attackerIndex]
        var interval = attacker.attackInterval
        if attacker.squadId >= 0 && attacker.squadId < squads.count && squads[attacker.squadId].warCryBuffTimer > 0.0 {
            interval /= 1.15
        }
        attacker.attackCooldown = interval
        attacker.actionState = .rangedDrawFire
        attacker.outOfCombatTimer = 0.0

        let brokeStealth = attacker.isStealthed && attacker.unitType == .wulinShadowSniper
        attacker.isStealthed = false
        soldiers[attackerIndex] = attacker

        // 密林树木遮挡造成 30% 散布偏折（雾林猎手无视林雾偏折）
        var aimX = targetX
        var aimY = targetY
        if terrainAt(x: targetX, y: targetY) == .denseForest && attacker.faction != .wulin {
            aimX += rng.nextRange(min: -34.0, max: 34.0)
            aimY += rng.nextRange(min: -34.0, max: 34.0)
        }

        let baseDmg = attacker.baseAttack * (brokeStealth ? 1.80 : 1.0)
        switch attacker.unitType {
        case .ballista:
            spawnProjectile(
                kind: .ballistaBolt,
                side: attacker.side,
                sourceUnitIndex: attackerIndex,
                originX: attacker.x,
                originY: attacker.y,
                targetX: aimX,
                targetY: aimY,
                speed: 560.0,
                arcHeight: 8.0,
                damage: baseDmg,
                armorPen: attacker.armorPenetration,
                aoeRadius: 0.0,
                pierceCount: 3, // 破甲连弩车直线贯穿 3 人
                appliesPoison: false,
                moraleShock: 1.8,
                structureBonus: 1.25
            )
        case .trebuchet:
            let yanlongSiegeMult = attacker.faction == .yanlong ? 1.25 : 1.0
            spawnProjectile(
                kind: .trebuchetBoulder,
                side: attacker.side,
                sourceUnitIndex: attackerIndex,
                originX: attacker.x,
                originY: attacker.y,
                targetX: aimX,
                targetY: aimY,
                speed: 235.0,
                arcHeight: 130.0,
                damage: baseDmg,
                armorPen: attacker.armorPenetration,
                aoeRadius: 72.0,
                pierceCount: 1,
                appliesPoison: false,
                moraleShock: 8.5,
                structureBonus: 3.50 * yanlongSiegeMult // 对城防建筑 350% 结构伤害
            )
        case .tieyingPaviseCrossbow:
            spawnProjectile(
                kind: .crossbowBolt,
                side: attacker.side,
                sourceUnitIndex: attackerIndex,
                originX: attacker.x,
                originY: attacker.y,
                targetX: aimX,
                targetY: aimY,
                speed: 480.0,
                arcHeight: 14.0,
                damage: baseDmg,
                armorPen: attacker.armorPenetration,
                aoeRadius: 0.0,
                pierceCount: 1,
                appliesPoison: false,
                moraleShock: 1.0,
                structureBonus: 0.35
            )
        case .wulinShadowSniper:
            spawnProjectile(
                kind: .venomArrow,
                side: attacker.side,
                sourceUnitIndex: attackerIndex,
                originX: attacker.x,
                originY: attacker.y,
                targetX: aimX,
                targetY: aimY,
                speed: 440.0,
                arcHeight: 28.0,
                damage: baseDmg,
                armorPen: attacker.armorPenetration,
                aoeRadius: 0.0,
                pierceCount: 1,
                appliesPoison: brokeStealth || attacker.faction == .wulin,
                moraleShock: brokeStealth ? 3.0 : 0.8,
                structureBonus: 0.25
            )
        default:
            spawnProjectile(
                kind: .arrow,
                side: attacker.side,
                sourceUnitIndex: attackerIndex,
                originX: attacker.x,
                originY: attacker.y,
                targetX: aimX,
                targetY: aimY,
                speed: 380.0,
                arcHeight: 56.0,
                damage: baseDmg,
                armorPen: attacker.armorPenetration,
                aoeRadius: 0.0,
                pierceCount: 1,
                appliesPoison: false,
                moraleShock: 0.6,
                structureBonus: 0.25
            )
        }
    }

    private mutating func stepDefensiveTowers(deltaTime: Double) {
        for idx in 0..<structures.count {
            guard !structures[idx].isDestroyed else { continue }

            // 拒马木栅被动反伤并强制停马附近 36px 内的敌方冲锋铁骑
            if structures[idx].kind == .woodenCheval {
                let stSide = structures[idx].side
                let sx = structures[idx].x
                let sy = structures[idx].y
                var chevalDmgTaken = 0.0
                let chevalHits = spatialGrid.queryInRadius(centerX: sx, centerY: sy, radius: 36.0, sideFilter: stSide.opponent, maxResults: 8)
                for h in 0..<chevalHits.count {
                    let eIdx = chevalHits[h].unitIndex
                    if soldiers[eIdx].category == .cavalry && (soldiers[eIdx].isChargeReady || soldiers[eIdx].actionState == .chargeSprint) {
                        soldiers[eIdx].isChargeReady = false
                        soldiers[eIdx].straightSprintDuration = 0.0
                        soldiers[eIdx].stunTimer = max(soldiers[eIdx].stunTimer, 0.9)
                        applyDirectDamageToSoldier(
                            targetIndex: eIdx,
                            rawDamage: 85.0,
                            armorPen: 0.60,
                            attackerX: sx,
                            attackerY: sy,
                            knockbackX: 0.0,
                            knockbackY: 0.0,
                            stunDuration: 0.9,
                            forceGiantStagger: false,
                            byHeroSide: nil
                        )
                        chevalDmgTaken += 65.0
                    }
                }
                if chevalDmgTaken > 0.0 {
                    damageStructure(at: idx, amount: chevalDmgTaken, attackerSide: stSide.opponent)
                }
                continue
            }

            guard structures[idx].kind == .arrowTower else { continue }
            structures[idx].attackCooldown = max(0.0, structures[idx].attackCooldown - deltaTime)
            guard structures[idx].attackCooldown <= 0.0 else { continue }

            let enemySide = structures[idx].side.opponent
            let targetIdx = spatialGrid.findNearestEnemy(
                fromX: structures[idx].x,
                fromY: structures[idx].y,
                enemySide: enemySide,
                maxRange: 490.0,
                minRange: 0.0,
                viewerFaction: structures[idx].side == .player ? playerState.faction : enemyState.faction
            )
            if targetIdx != -1 {
                structures[idx].attackCooldown = 1.65
                spawnProjectile(
                    kind: .towerArrow,
                    side: structures[idx].side,
                    sourceUnitIndex: -1,
                    originX: structures[idx].x,
                    originY: structures[idx].y,
                    targetX: soldiers[targetIdx].x,
                    targetY: soldiers[targetIdx].y,
                    speed: 430.0,
                    arcHeight: 45.0,
                    damage: 28.0,
                    armorPen: 0.30,
                    aoeRadius: 0.0,
                    pierceCount: 1,
                    appliesPoison: false,
                    moraleShock: 0.8,
                    structureBonus: 0.2
                )
            }
        }
    }

    private mutating func stepProjectiles(deltaTime: Double) {
        for pIdx in 0..<projectiles.count {
            guard projectiles[pIdx].isActive else { continue }

            projectiles[pIdx].flightElapsed += deltaTime
            projectiles[pIdx].x += projectiles[pIdx].vx * deltaTime
            projectiles[pIdx].y += projectiles[pIdx].vy * deltaTime

            let proj = projectiles[pIdx]
            let enemySide = proj.side.opponent

            // 1) 范围爆炸类弹道（配重投石巨石 / 炎龙震天火雷）：抵达目标飞行时长时落地轰击！
            if proj.aoeRadius > 0.0 {
                if proj.flightElapsed >= proj.flightDuration {
                    detonateAreaProjectile(proj)
                    projectiles[pIdx].isActive = false
                }
                continue
            }

            // 2) 直线/曲射单体与贯穿类箭矢（复合弓、神弩、毒箭、连弩车贯穿 3 人、主帅硬弓贯穿 2 人）
            var remainingPierces = proj.remainingPierces
            var hitRec = proj
            let projHits = spatialGrid.queryInRadius(centerX: proj.x, centerY: proj.y, radius: 14.0, sideFilter: enemySide, maxResults: 6)
            for h in 0..<projHits.count {
                guard remainingPierces > 0 else { break }
                let uIdx = projHits[h].unitIndex
                guard !hitRec.hasAlreadyHit(unitIndex: uIdx) else { continue }
                hitRec.recordHit(unitIndex: uIdx)
                remainingPierces -= 1
                resolveProjectileHitOnSoldier(projectile: hitRec, targetIndex: uIdx)
            }
            hitRec.remainingPierces = remainingPierces

            // 检测是否命中敌方主帅
            let oppHero = enemySide == .player ? playerHero : enemyHero
            if remainingPierces > 0 && oppHero.isActiveOnField {
                let hDistSq = (oppHero.x - proj.x) * (oppHero.x - proj.x) + (oppHero.y - proj.y) * (oppHero.y - proj.y)
                if hDistSq <= 16.0 * 16.0 && !hitRec.hasAlreadyHit(unitIndex: -99) {
                    hitRec.recordHit(unitIndex: -99)
                    remainingPierces -= 1
                    hitRec.remainingPierces = remainingPierces
                    damageCommander(
                        targetSide: enemySide,
                        rawAttack: proj.damage,
                        armorPen: proj.armorPenetration,
                        attackerX: proj.originX,
                        attackerY: proj.originY,
                        isMelee: false,
                        byHero: proj.sourceUnitIndex == -2
                    )
                }
            }

            if remainingPierces <= 0 || hitRec.flightElapsed >= hitRec.flightDuration * 1.15
                || hitRec.x < 0.0 || hitRec.x > worldWidth || hitRec.y < 0.0 || hitRec.y > worldHeight {
                // 若飞行终点落在敌方建筑矩形内，结算器械/箭矢对建筑伤害
                if remainingPierces > 0 {
                    for sIdx in 0..<structures.count where !structures[sIdx].isDestroyed && structures[sIdx].side == enemySide {
                        if abs(hitRec.x - structures[sIdx].x) <= structures[sIdx].width * 0.55
                            && abs(hitRec.y - structures[sIdx].y) <= structures[sIdx].height * 0.55 {
                            damageStructure(
                                at: sIdx,
                                amount: max(2.0, hitRec.damage * hitRec.structureBonusMultiplier * 0.65),
                                attackerSide: hitRec.side
                            )
                            break
                        }
                    }
                }
                hitRec.isActive = false
            }
            projectiles[pIdx] = hitRec
        }
    }

    private mutating func detonateAreaProjectile(_ proj: ProjectileEntity) {
        let enemySide = proj.side.opponent
        let particleKind: EffectParticleKind = proj.kind == .thunderGrenade ? .explosionFire : .boulderDust
        spawnParticle(kind: particleKind, x: proj.x, y: proj.y, lifetime: 0.55)

        let aFaction = proj.side == .player ? playerState.faction : enemyState.faction
        let aRation = proj.side == .player ? playerState.rationStage : enemyState.rationStage

        // 杀伤爆炸半径内敌兵并冲击其所属军团士气（神机火雷直扣 -12 士气；投石巨石砸崩密集方阵士气）
        var shockedSquad0 = -1
        var shockedSquad1 = -1
        let aoeHits = spatialGrid.queryInRadius(centerX: proj.x, centerY: proj.y, radius: proj.aoeRadius, sideFilter: enemySide, maxResults: 32)
        for h in 0..<aoeHits.count {
            let uIdx = aoeHits[h].unitIndex
            let distSq = aoeHits[h].distanceSquared
            let falloff = max(0.45, 1.0 - sqrt(distSq) / max(1.0, proj.aoeRadius) * 0.50)
            let target = soldiers[uIdx]
            let tSq = (target.squadId >= 0 && target.squadId < squads.count) ? squads[target.squadId] : nil
            let tTerrain = terrainAt(x: target.x, y: target.y)

            let out = DamageMoraleCalculator.calculateDamage(
                DamageCalculationInput(
                    baseAttack: proj.damage * falloff,
                    attackerArmorPenetration: proj.armorPenetration,
                    attackerFaction: aFaction,
                    attackerWeather: context.weather,
                    attackerRationStage: aRation,
                    isMelee: false,
                    isExplosiveArea: true,
                    targetBaseArmor: target.baseArmor,
                    targetShieldRangedBlock: target.shieldRangedBlock,
                    targetCategory: target.category,
                    targetFaction: target.faction,
                    targetTerrain: tTerrain,
                    targetMoraleBracket: tSq?.moraleBracket ?? .steady,
                    targetFormation: tSq?.formation ?? .phalanxRect,
                    targetFormationBonusActive: tSq?.isFormationBonusActive ?? true,
                    targetEncirclement: tSq?.encirclementState ?? .clear,
                    targetSquadRiverWadingRatio: tSq?.riverWadingRatio ?? 0.0
                )
            )
            let sqId = target.squadId
            var extraShock = out.moraleShockToTarget
            if sqId >= 0 && sqId != shockedSquad0 && sqId != shockedSquad1 {
                extraShock = max(extraShock, proj.moraleShock)
                if shockedSquad0 == -1 { shockedSquad0 = sqId }
                else if shockedSquad1 == -1 { shockedSquad1 = sqId }
            }
            applyResolvedDamage(
                toSoldierAt: uIdx,
                damage: out.finalDamage,
                moraleHit: extraShock,
                killerSide: proj.side,
                causedByCharge: false,
                attackerFaction: aFaction,
                attackerSquadId: -1
            )
        }

        // 若敌方主帅处于爆炸杀伤圈内，同步承受衰减破甲轰击
        let oppHero = enemySide == .player ? playerHero : enemyHero
        if oppHero.isActiveOnField {
            let hDist = hypot(oppHero.x - proj.x, oppHero.y - proj.y)
            if hDist <= proj.aoeRadius {
                let falloff = max(0.45, 1.0 - (hDist / max(1.0, proj.aoeRadius)) * 0.50)
                damageCommander(
                    targetSide: enemySide,
                    rawAttack: proj.damage * falloff,
                    armorPen: proj.armorPenetration,
                    attackerX: proj.x,
                    attackerY: proj.y,
                    isMelee: false,
                    byHero: false
                )
            }
        }

        // 轰击爆炸范围内的敌方城墙、箭塔、城门与本阵（投石车享 350% 结构伤害）
        for sIdx in 0..<structures.count where !structures[sIdx].isDestroyed && structures[sIdx].side == enemySide {
            let dx = max(0.0, abs(proj.x - structures[sIdx].x) - structures[sIdx].width * 0.5)
            let dy = max(0.0, abs(proj.y - structures[sIdx].y) - structures[sIdx].height * 0.5)
            if dx * dx + dy * dy <= proj.aoeRadius * proj.aoeRadius {
                let effStArmor = DamageMoraleCalculator.computeEffectiveArmor(
                    targetArmor: structures[sIdx].armor,
                    armorPenetration: proj.armorPenetration
                )
                let mit = DamageMoraleCalculator.computeArmorMitigation(effectiveArmor: effStArmor)
                let stDmg = proj.damage * proj.structureBonusMultiplier * (1.0 - mit)
                damageStructure(at: sIdx, amount: stDmg, attackerSide: proj.side)
            }
        }
    }

    private mutating func resolveProjectileHitOnSoldier(projectile: ProjectileEntity, targetIndex: Int) {
        guard soldiers[targetIndex].isActive && soldiers[targetIndex].hp > 0.0 else { return }
        let target = soldiers[targetIndex]
        let tSq = (target.squadId >= 0 && target.squadId < squads.count) ? squads[target.squadId] : nil
        let aFaction = projectile.side == .player ? playerState.faction : enemyState.faction
        let aRation = projectile.side == .player ? playerState.rationStage : enemyState.rationStage
        let tTerrain = terrainAt(x: target.x, y: target.y)

        let incAngle = DamageMoraleCalculator.incomingAttackAngle(
            targetX: target.x,
            targetY: target.y,
            targetFacingRadians: target.facingRadians,
            attackerX: projectile.originX,
            attackerY: projectile.originY
        )

        let out = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: projectile.damage,
                attackerArmorPenetration: projectile.armorPenetration,
                attackerFaction: aFaction,
                attackerWeather: context.weather,
                attackerRationStage: aRation,
                isMelee: false,
                isExplosiveArea: false,
                targetBaseArmor: target.baseArmor,
                targetShieldRangedBlock: target.shieldRangedBlock,
                targetCategory: target.category,
                targetFaction: target.faction,
                targetTerrain: tTerrain,
                targetMoraleBracket: tSq?.moraleBracket ?? .steady,
                targetFormation: tSq?.formation ?? .phalanxRect,
                targetFormationBonusActive: tSq?.isFormationBonusActive ?? true,
                targetEncirclement: tSq?.encirclementState ?? .clear,
                targetIsReloadingBackShield: target.isReloadingBackShield,
                targetSquadRiverWadingRatio: tSq?.riverWadingRatio ?? 0.0,
                incomingAngleDifferenceRadians: incAngle
            )
        )

        if out.shieldBlocked {
            spawnParticle(kind: .shieldSpark, x: target.x, y: target.y, lifetime: 0.25)
        }
        if projectile.appliesPoison {
            soldiers[targetIndex].poisonSlowTimer = 3.0
            soldiers[targetIndex].poisonDotTimer = 3.0
        }

        applyResolvedDamage(
            toSoldierAt: targetIndex,
            damage: out.finalDamage,
            moraleHit: max(out.moraleShockToTarget, projectile.moraleShock * 0.4),
            killerSide: projectile.side,
            causedByCharge: false,
            attackerFaction: aFaction,
            attackerSquadId: -1,
            byHeroSide: projectile.sourceUnitIndex == -2 ? projectile.side : nil
        )
    }

    // MARK: - 十一、工兵采矿伐木抢粮、大营警钟协防、劫掠粮车与建筑破拆

    private mutating func stepSapperBehavior(unitIndex: Int, deltaTime: Double) {
        let side = soldiers[unitIndex].side
        let enemySide = side.opponent
        let bellActive = side == .player ? playerState.garrisonBellActive : enemyState.garrisonBellActive
        let camp = baseCampCoordinates(for: side)
        let faction = soldiers[unitIndex].faction

        if bellActive {
            let dx = camp.x - soldiers[unitIndex].x
            let dy = camp.y - soldiers[unitIndex].y
            let dist = hypot(dx, dy)
            if dist <= 75.0 {
                // 已退入大营围栏：通过营寨射击孔向 300px 内偷家敌骑发射协防箭石！
                soldiers[unitIndex].isGarrisonedInCamp = true
                soldiers[unitIndex].vx = 0.0
                soldiers[unitIndex].vy = 0.0
                soldiers[unitIndex].actionState = .rangedDrawFire
                if soldiers[unitIndex].attackCooldown <= 0.0 {
                    let targetIdx = spatialGrid.findNearestEnemy(
                        fromX: camp.x,
                        fromY: camp.y,
                        enemySide: enemySide,
                        maxRange: 310.0,
                        viewerFaction: faction
                    )
                    if targetIdx != -1 {
                        soldiers[unitIndex].attackCooldown = 1.60
                        spawnProjectile(
                            kind: .arrow,
                            side: side,
                            sourceUnitIndex: unitIndex,
                            originX: camp.x,
                            originY: camp.y,
                            targetX: soldiers[targetIdx].x,
                            targetY: soldiers[targetIdx].y,
                            speed: 340.0,
                            arcHeight: 35.0,
                            damage: 14.0,
                            armorPen: 0.15,
                            aoeRadius: 0.0,
                            pierceCount: 1,
                            appliesPoison: false,
                            moraleShock: 0.5,
                            structureBonus: 0.1
                        )
                    }
                }
            } else {
                soldiers[unitIndex].isGarrisonedInCamp = false
                let spd = soldiers[unitIndex].baseMoveSpeed
                soldiers[unitIndex].vx = (dx / dist) * spd
                soldiers[unitIndex].vy = (dy / dist) * spd
                soldiers[unitIndex].facingRadians = atan2(dy, dx)
                soldiers[unitIndex].actionState = .marchRun
                moveSoldierWithWallAndTrapCheck(unitIndex: unitIndex, deltaTime: deltaTime)
            }
            return
        }

        soldiers[unitIndex].isGarrisonedInCamp = false

        // 若背包已装满采集资源，运回本阵大营入库
        if let carriedKind = soldiers[unitIndex].carryingResourceKind, soldiers[unitIndex].carryingAmount > 0.0 {
            let dx = camp.x - soldiers[unitIndex].x
            let dy = camp.y - soldiers[unitIndex].y
            let dist = hypot(dx, dy)
            if dist <= 72.0 {
                let amount = soldiers[unitIndex].carryingAmount
                soldiers[unitIndex].carryingResourceKind = nil
                soldiers[unitIndex].carryingAmount = 0.0
                depositGatheredResource(side: side, kind: carriedKind, amount: amount)
            } else {
                let spd = soldiers[unitIndex].baseMoveSpeed * 0.92
                soldiers[unitIndex].vx = (dx / dist) * spd
                soldiers[unitIndex].vy = (dy / dist) * spd
                soldiers[unitIndex].facingRadians = atan2(dy, dx)
                soldiers[unitIndex].actionState = .marchRun
                moveSoldierWithWallAndTrapCheck(unitIndex: unitIndex, deltaTime: deltaTime)
            }
            return
        }

        // 寻找最近的半场野外资源点开采
        var nodeIdx = soldiers[unitIndex].gatherTargetNodeId
        if nodeIdx < 0 || nodeIdx >= resourceNodes.count || resourceNodes[nodeIdx].remainingAmount <= 0.0 {
            nodeIdx = pickBestResourceNode(for: side, fromX: soldiers[unitIndex].x, fromY: soldiers[unitIndex].y)
            soldiers[unitIndex].gatherTargetNodeId = nodeIdx
        }

        guard nodeIdx >= 0 && nodeIdx < resourceNodes.count else {
            soldiers[unitIndex].actionState = .idleReady
            return
        }

        let node = resourceNodes[nodeIdx]
        let dx = node.x - soldiers[unitIndex].x
        let dy = node.y - soldiers[unitIndex].y
        let dist = hypot(dx, dy)
        if dist <= 34.0 {
            soldiers[unitIndex].vx = 0.0
            soldiers[unitIndex].vy = 0.0
            soldiers[unitIndex].actionState = .meleeStrike
            soldiers[unitIndex].gatherProgressTimer += deltaTime
            if soldiers[unitIndex].gatherProgressTimer >= node.gatherDurationSec {
                soldiers[unitIndex].gatherProgressTimer = 0.0
                let harvested = min(resourceNodes[nodeIdx].remainingAmount, node.yieldPerTrip)
                resourceNodes[nodeIdx].remainingAmount -= harvested
                soldiers[unitIndex].carryingResourceKind = node.kind
                soldiers[unitIndex].carryingAmount = harvested
            }
        } else {
            let spd = soldiers[unitIndex].baseMoveSpeed
            soldiers[unitIndex].vx = (dx / dist) * spd
            soldiers[unitIndex].vy = (dy / dist) * spd
            soldiers[unitIndex].facingRadians = atan2(dy, dx)
            soldiers[unitIndex].actionState = .marchRun
            moveSoldierWithWallAndTrapCheck(unitIndex: unitIndex, deltaTime: deltaTime)
        }
    }

    private mutating func depositGatheredResource(side: BattleSide, kind: ResourceNodeKind, amount: Double) {
        let faction = side == .player ? playerState.faction : enemyState.faction
        switch kind {
        case .goldMine:
            let goldBonus = faction == .shamo ? 1.35 : 1.0
            let val = Int((amount * goldBonus).rounded())
            if side == .player { playerState.gold += val } else { enemyState.gold += val }
        case .lumberForest:
            let val = Int(amount.rounded())
            if side == .player { playerState.wood += val } else { enemyState.wood += val }
        case .grainFarm:
            let val = amount * (faction == .canglang ? 1.35 : 1.0)
            if side == .player { playerState.grain += val } else { enemyState.grain += val }
        }
    }

    private func findAttackableStructure(for unit: SoldierEntity, effectiveRange: Double) -> Int? {
        let enemySide = unit.side.opponent
        var bestIdx: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for idx in 0..<structures.count {
            let st = structures[idx]
            guard !st.isDestroyed, st.side == enemySide, st.kind != .siegeLadder else { continue }
            let dx = max(0.0, abs(unit.x - st.x) - st.width * 0.5)
            let dy = max(0.0, abs(unit.y - st.y) - st.height * 0.5)
            let edgeDist = hypot(dx, dy)
            if edgeDist <= effectiveRange + 10.0 && edgeDist >= unit.minRange && edgeDist < bestDist {
                bestDist = edgeDist
                bestIdx = idx
            }
        }
        return bestIdx
    }

    private mutating func executeStructureAttack(attackerIndex: Int, structureIndex: Int) {
        let attacker = soldiers[attackerIndex]
        if attacker.category == .ranged || attacker.category == .siege {
            executeRangedFire(attackerIndex: attackerIndex, targetX: structures[structureIndex].x, targetY: structures[structureIndex].y)
            return
        }

        soldiers[attackerIndex].attackCooldown = attacker.attackInterval
        soldiers[attackerIndex].actionState = .meleeStrike
        soldiers[attackerIndex].outOfCombatTimer = 0.0

        // 重型巨斧兵对木质城门享 2.25x 破拆加成；攻城防卡死：普通步兵亦可火把劈烧慢拆城门
        var structMult = 1.0
        if structures[structureIndex].kind == .mainGate || structures[structureIndex].kind == .woodenCheval {
            if attacker.unitType == .greatAxeman || attacker.unitType == .shuangyuanGiantBreaker {
                structMult = 2.25
            } else {
                structMult = 0.85
            }
        }
        if attacker.faction == .yanlong {
            structMult *= 1.25
        }

        let effArmor = DamageMoraleCalculator.computeEffectiveArmor(
            targetArmor: structures[structureIndex].armor,
            armorPenetration: attacker.armorPenetration
        )
        let mit = DamageMoraleCalculator.computeArmorMitigation(effectiveArmor: effArmor)
        let dmg = max(GameConstants.minimumHitDamage, attacker.baseAttack * structMult * (1.0 - mit))

        // 奇袭敌方本阵大营粮车：首次突袭敌本阵当场夺取 150 应急粮草（苍狼汗国双倍获 300 粮）解除断粮！
        if structures[structureIndex].kind == .baseCamp && !structures[structureIndex].granaryLooted {
            structures[structureIndex].granaryLooted = true
            let canglangDouble = attacker.faction == .canglang ? 2.0 : 1.0
            let looted = GameConstants.raidEnemyGranaryLootGrain * canglangDouble
            if attacker.side == .player {
                playerState.grain += looted
                playerState.zeroGrainElapsedSec = 0.0
                playerState.lootedGrainTotal += looted
                playerState.lootedGoldTotal += 45
                playerState.gold += 45
            } else {
                enemyState.grain += looted
                enemyState.zeroGrainElapsedSec = 0.0
                enemyState.lootedGrainTotal += looted
            }
            if structures[structureIndex].side == .player {
                playerState.grain = max(0.0, playerState.grain - GameConstants.raidEnemyGranaryLootGrain * 0.5)
            } else {
                enemyState.grain = max(0.0, enemyState.grain - GameConstants.raidEnemyGranaryLootGrain * 0.5)
            }
        }

        damageStructure(at: structureIndex, amount: dmg, attackerSide: attacker.side)
    }

    private mutating func damageStructure(at index: Int, amount: Double, attackerSide: BattleSide) {
        guard index >= 0 && index < structures.count && !structures[index].isDestroyed else { return }
        structures[index].hp -= amount
        if structures[index].hp <= 0.0 {
            structures[index].hp = 0.0
            structures[index].isDestroyed = true
            spawnParticle(kind: .boulderDust, x: structures[index].x, y: structures[index].y, lifetime: 0.75)

            // 若本阵大营被毁且对方主帅正在医帐包扎，直接触发无处抢救殉国！
            if structures[index].kind == .baseCamp {
                if structures[index].side == .player && playerHero.vitalState == .recoveringInCamp {
                    playerHero.vitalState = .fallenMartyred
                } else if structures[index].side == .enemy && enemyHero.vitalState == .recoveringInCamp {
                    enemyHero.vitalState = .fallenMartyred
                }
            }
        }
    }

    // MARK: - 十二、伤害落地、斩旗夺帅、玄甲刷冲锋 CD、血月充能与终局判定

    private mutating func applyDirectDamageToSoldier(
        targetIndex: Int,
        rawDamage: Double,
        armorPen: Double,
        attackerX: Double,
        attackerY: Double,
        knockbackX: Double,
        knockbackY: Double,
        stunDuration: Double,
        forceGiantStagger: Bool,
        byHeroSide: BattleSide?
    ) {
        guard soldiers[targetIndex].isActive && soldiers[targetIndex].hp > 0.0 else { return }
        let target = soldiers[targetIndex]
        let effArmor = DamageMoraleCalculator.computeEffectiveArmor(
            targetArmor: target.baseArmor,
            armorPenetration: armorPen
        )
        let mit = DamageMoraleCalculator.computeArmorMitigation(effectiveArmor: effArmor)
        let finalDmg = max(GameConstants.minimumHitDamage, rawDamage * (1.0 - mit))

        // 霜原巨熊破阵者免疫普通击退与微硬直（仅主帅破阵突击与绊马索可强制撼动）
        let isImmuneGiant = target.unitType == .shuangyuanGiantBreaker && !forceGiantStagger
        if !isImmuneGiant {
            let phalanxKnockResist: Double = {
                guard target.squadId >= 0 && target.squadId < squads.count else { return 1.0 }
                let sq = squads[target.squadId]
                return (sq.formation == .phalanxRect && sq.isFormationBonusActive) ? 0.50 : 1.0
            }()
            soldiers[targetIndex].x = clamp(soldiers[targetIndex].x + knockbackX * phalanxKnockResist, minVal: 16.0, maxVal: worldWidth - 16.0)
            soldiers[targetIndex].y = clamp(soldiers[targetIndex].y + knockbackY * phalanxKnockResist, minVal: 16.0, maxVal: worldHeight - 16.0)
            if stunDuration > 0.0 {
                soldiers[targetIndex].stunTimer = max(soldiers[targetIndex].stunTimer, stunDuration)
            }
        }

        let killerSide = target.side.opponent
        applyResolvedDamage(
            toSoldierAt: targetIndex,
            damage: finalDmg,
            moraleHit: min(3.5, finalDmg / 55.0),
            killerSide: killerSide,
            causedByCharge: false,
            attackerFaction: killerSide == .player ? playerState.faction : enemyState.faction,
            attackerSquadId: -1,
            byHeroSide: byHeroSide
        )
    }

    private mutating func applyResolvedDamage(
        toSoldierAt targetIndex: Int,
        damage: Double,
        moraleHit: Double,
        killerSide: BattleSide,
        causedByCharge: Bool,
        attackerFaction: FactionId,
        attackerSquadId: Int,
        byHeroSide: BattleSide? = nil
    ) {
        guard soldiers[targetIndex].isActive && soldiers[targetIndex].hp > 0.0 else { return }
        soldiers[targetIndex].hp -= damage
        soldiers[targetIndex].outOfCombatTimer = 0.0
        spawnParticle(
            kind: .bloodSlash,
            x: soldiers[targetIndex].x,
            y: soldiers[targetIndex].y,
            lifetime: 0.22,
            numericValue: Int(damage.rounded()),
            isCritical: damage >= 65.0
        )

        let sqId = soldiers[targetIndex].squadId
        let wasRoutingBefore = (sqId >= 0 && sqId < squads.count) ? squads[sqId].isRouting : false

        if sqId >= 0 && sqId < squads.count && moraleHit > 0.0 {
            applyInstantSquadMoraleDelta(squadId: sqId, delta: -moraleHit)
        }

        if soldiers[targetIndex].hp <= 0.0 {
            killSoldier(at: targetIndex, killerSide: killerSide, byHeroSide: byHeroSide)
        }

        // 玄甲重骑法则：冲锋击溃敌队重置 50% 冲锋冷却并回升士气 +12
        if sqId >= 0 && sqId < squads.count && !wasRoutingBefore && squads[sqId].isRouting {
            if attackerFaction == .xuanjia && causedByCharge && attackerSquadId >= 0 && attackerSquadId < squads.count {
                applyInstantSquadMoraleDelta(squadId: attackerSquadId, delta: 12.0)
                for uIdx in 0..<soldiers.count where soldiers[uIdx].isActive && soldiers[uIdx].squadId == attackerSquadId && soldiers[uIdx].category == .cavalry {
                    soldiers[uIdx].chargeCooldown *= 0.50
                }
            }
            // 击溃敌队鼓舞周边友军士气 +6
            for aSq in 0..<squads.count where squads[aSq].side == killerSide && squads[aSq].aliveCount > 0 {
                if hypot(squads[aSq].anchorX - squads[sqId].anchorX, squads[aSq].anchorY - squads[sqId].anchorY) <= 280.0 {
                    applyInstantSquadMoraleDelta(squadId: aSq, delta: 6.0)
                }
            }
        }
    }

    private mutating func killSoldier(at index: Int, killerSide: BattleSide, byHeroSide: BattleSide?) {
        soldiers[index].hp = 0.0
        soldiers[index].actionState = .dyingFall
        soldiers[index].actionTimer = 0.35
        soldiers[index].vx = 0.0
        soldiers[index].vy = 0.0

        let victimSide = soldiers[index].side
        if victimSide == .player {
            playerState.killedCount += 1
        } else {
            enemyState.killedCount += 1
        }

        if byHeroSide == .player {
            playerHero.killsCount += 1
        } else if byHeroSide == .enemy {
            enemyHero.killsCount += 1
        }

        // 血月祭司团【血月狂热】：敌我双方阵亡均充能战鼓祭坛，满 100 激活 12s 全军加速免溃！
        chargeBloodMoonFervorOnDeath()

        let sqId = soldiers[index].squadId
        if sqId >= 0 && sqId < squads.count {
            // 阵亡伤亡士气冲击（伤亡过半时惩罚加剧）
            let lossShock = squads[sqId].aliveCount <= max(1, squads[sqId].initialCount / 2) ? -3.4 : -1.8
            applyInstantSquadMoraleDelta(squadId: sqId, delta: lossShock)

            // 斩旗夺帅机制：砍倒军团执旗官令该军团瞬间 -15 士气且阵型加成失效 12s！
            if soldiers[index].isBannerBearer {
                soldiers[index].isBannerBearer = false
                squads[sqId].bannerUnitIndex = -1
                squads[sqId].bannerLostPenaltyTimer = 12.0
                applyInstantSquadMoraleDelta(squadId: sqId, delta: -15.0)
                if byHeroSide == .player {
                    playerHero.bannersSlainCount += 1
                } else if byHeroSide == .enemy {
                    enemyHero.bannersSlainCount += 1
                }
            }
        }
    }

    private mutating func chargeBloodMoonFervorOnDeath() {
        if playerState.faction == .xueyue && playerState.bloodMoonFervorRemainingSec <= 0.0 {
            playerState.bloodMoonFervorGauge += 7.0
            if playerState.bloodMoonFervorGauge >= 100.0 {
                playerState.bloodMoonFervorGauge = 0.0
                playerState.bloodMoonFervorRemainingSec = 12.0
            }
        }
        if enemyState.faction == .xueyue && enemyState.bloodMoonFervorRemainingSec <= 0.0 {
            enemyState.bloodMoonFervorGauge += 7.0
            if enemyState.bloodMoonFervorGauge >= 100.0 {
                enemyState.bloodMoonFervorGauge = 0.0
                enemyState.bloodMoonFervorRemainingSec = 12.0
            }
        }
    }

    /// 对主帅结算伤害（公用入口，自动联动精准弹反震晕、首次落马全军 -35 士气锁 65、敌帅落马 15s 瘫痪及二次殉国判负）
    public mutating func damageCommander(
        targetSide: BattleSide,
        rawAttack: Double,
        armorPen: Double,
        attackerX: Double,
        attackerY: Double,
        isMelee: Bool,
        byHero: Bool = false
    ) {
        let campDestroyed = isBaseCampDestroyed(for: targetSide)
        let nonRoutingRatio = computeNonRoutingArmyRatio(for: targetSide)
        let hasReserve = (targetSide == .player ? !playerState.trainingQueue.isEmpty : !enemyState.trainingQueue.isEmpty)
        var events = HeroStepEvents()

        if targetSide == .player {
            let res = HeroCombatController.applyDamageToHero(
                hero: &playerHero,
                rawAttack: rawAttack,
                armorPenetration: armorPen,
                attackerX: attackerX,
                attackerY: attackerY,
                isMelee: isMelee,
                friendlyCampDestroyed: campDestroyed,
                nonRoutingFriendlyRatio: nonRoutingRatio,
                hasReserveTroops: hasReserve,
                events: &events
            )
            if res.triggeredPerfectParry {
                hitStopRemainingSec = max(hitStopRemainingSec, events.triggeredHitStopSec)
                spawnParticle(kind: .parryFlash, x: playerHero.x, y: playerHero.y, lifetime: 0.30)
                // 精准弹反震退周围 55px 敌兵并眩晕 1.5s！
                let hx = playerHero.x
                let hy = playerHero.y
                let parryHits = spatialGrid.queryInRadius(centerX: hx, centerY: hy, radius: 55.0, sideFilter: .enemy, maxResults: 12)
                for h in 0..<parryHits.count {
                    let eIdx = parryHits[h].unitIndex
                    let dx = soldiers[eIdx].x - hx
                    let dy = soldiers[eIdx].y - hy
                    let len = max(1.0, hypot(dx, dy))
                    soldiers[eIdx].x = clamp(soldiers[eIdx].x + (dx / len) * 22.0, minVal: 16.0, maxVal: worldWidth - 16.0)
                    soldiers[eIdx].y = clamp(soldiers[eIdx].y + (dy / len) * 22.0, minVal: 16.0, maxVal: worldHeight - 16.0)
                    soldiers[eIdx].stunTimer = max(soldiers[eIdx].stunTimer, 1.50)
                }
            }
            if events.firstDownTriggered {
                // 首次落马重伤：镜头自动切回 RTS 统帅视角，全军瞬间 -35 士气且上限锁死 65！
                controlMode = .rtsCommander
                applyArmyWideMoraleShock(side: .player, delta: -GameConstants.heroFirstDownMoraleShock)
                refreshHudSnapshotNow()
            } else if events.martyredTriggered {
                applyArmyWideMoraleShock(side: .player, delta: -100.0)
                outcome = .playerCommanderMartyred
                refreshHudSnapshotNow()
            }
        } else {
            _ = HeroCombatController.applyDamageToHero(
                hero: &enemyHero,
                rawAttack: rawAttack,
                armorPenetration: armorPen,
                attackerX: attackerX,
                attackerY: attackerY,
                isMelee: isMelee,
                friendlyCampDestroyed: campDestroyed,
                nonRoutingFriendlyRatio: nonRoutingRatio,
                hasReserveTroops: hasReserve,
                events: &events
            )
            if events.firstDownTriggered || events.martyredTriggered {
                // 斩倒敌军主帅：敌军全线瞬间 -35 士气并陷入 15s 指挥瘫痪，我军士气沸腾 +20！
                enemyState.commandParalysisTimer = 15.0
                applyArmyWideMoraleShock(side: .enemy, delta: -GameConstants.heroFirstDownMoraleShock)
                applyArmyWideMoraleShock(side: .player, delta: byHero ? 20.0 : 14.0)
                if byHero {
                    hitStopRemainingSec = Double(GameConstants.heroHitStopMilliseconds) / 1000.0
                    cameraShakeIntensity = 0.85
                }
            }
        }
    }

    private mutating func evaluateBattleOutcome() {
        guard outcome == .ongoing else { return }

        if playerHero.vitalState == .fallenMartyred || isBaseCampDestroyed(for: .player) {
            outcome = .playerCommanderMartyred
            return
        }
        if isBaseCampDestroyed(for: .enemy) {
            outcome = .enemyBaseDestroyed
            return
        }
        if context.scenarioType == .siegeDefense && elapsedSeconds >= deployment.siegeHoldTargetSeconds {
            outcome = .siegeDefenseHeld
            return
        }

        // 检查敌我双方是否全军崩溃（场上无非溃逃作战兵且训练队列为空）
        var playerActiveCombat = 0
        var enemyActiveCombat = 0
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 {
            let sqId = soldiers[i].squadId
            let routing = (sqId >= 0 && sqId < squads.count) ? squads[sqId].isRouting : false
            if !routing {
                if soldiers[i].side == .player {
                    playerActiveCombat += 1
                } else {
                    enemyActiveCombat += 1
                }
            }
        }

        if enemyActiveCombat == 0 && enemyState.trainingQueue.isEmpty && enemyState.totalInitialSoldiers > 0 {
            outcome = .enemyArmyRouted
        } else if playerActiveCombat == 0 && playerState.trainingQueue.isEmpty && playerState.totalInitialSoldiers > 0 {
            outcome = .playerArmyRouted
        }
    }

    // MARK: - 十三、地形、城墙碰撞、陷阱触发与预分配池辅助方法

    private mutating func moveSoldierWithWallAndTrapCheck(unitIndex: Int, deltaTime: Double) {
        let oldX = soldiers[unitIndex].x
        let oldY = soldiers[unitIndex].y
        var nextX = clamp(oldX + soldiers[unitIndex].vx * deltaTime, minVal: 18.0, maxVal: worldWidth - 18.0)
        var nextY = clamp(oldY + soldiers[unitIndex].vy * deltaTime, minVal: 18.0, maxVal: worldHeight - 18.0)

        // 城墙与城门物理阻挡：未轰塌城墙段不可直接穿过（步兵可通过云梯攀越，骑兵禁登城墙；守方可通过侧门通行）
        let side = soldiers[unitIndex].side
        let isCav = soldiers[unitIndex].category == .cavalry || soldiers[unitIndex].category == .siege
        for st in structures where !st.isDestroyed {
            guard st.kind == .wallSegment || st.kind == .mainGate || st.kind == .sideSallyGate else { continue }
            if st.kind == .sideSallyGate && st.side == side {
                continue // 守军可自由进出己方侧门暗道
            }
            let halfW = st.width * 0.5 + soldiers[unitIndex].collisionRadius
            let halfH = st.height * 0.5 + soldiers[unitIndex].collisionRadius
            if abs(nextX - st.x) < halfW && abs(nextY - st.y) < halfH {
                // 检查旁边 65px 是否有可用云梯供步兵攀登
                let hasLadder = !isCav && structures.contains { lad in
                    lad.kind == .siegeLadder && !lad.isDestroyed && hypot(lad.x - nextX, lad.y - nextY) <= 72.0
                }
                if !hasLadder {
                    nextX = oldX
                    // 允许沿墙面纵向滑动寻找云梯或城门缺口
                    if abs(oldX - st.x) < halfW {
                        nextY = oldY
                    }
                    break
                }
            }
        }

        soldiers[unitIndex].x = nextX
        soldiers[unitIndex].y = nextY

        // 雾林猎手尖刺陷坑与绊马索碰撞触发检查
        for tIdx in 0..<fieldTraps.count where fieldTraps[tIdx].remainingCharges > 0 && fieldTraps[tIdx].side != side {
            let trap = fieldTraps[tIdx]
            let dx = nextX - trap.x
            let dy = nextY - trap.y
            if dx * dx + dy * dy <= trap.radius * trap.radius {
                fieldTraps[tIdx].isTriggered = true
                fieldTraps[tIdx].remainingCharges -= 1
                if trap.kind == .tripwire && soldiers[unitIndex].category == .cavalry {
                    soldiers[unitIndex].isChargeReady = false
                    soldiers[unitIndex].straightSprintDuration = 0.0
                    applyDirectDamageToSoldier(
                        targetIndex: unitIndex,
                        rawDamage: 58.0,
                        armorPen: 0.45,
                        attackerX: trap.x,
                        attackerY: trap.y,
                        knockbackX: 0.0,
                        knockbackY: 0.0,
                        stunDuration: 3.0, // 绊马索令骑兵坠马眩晕 3s
                        forceGiantStagger: true,
                        byHeroSide: nil
                    )
                } else {
                    soldiers[unitIndex].poisonSlowTimer = max(soldiers[unitIndex].poisonSlowTimer, 2.5)
                    applyDirectDamageToSoldier(
                        targetIndex: unitIndex,
                        rawDamage: 42.0,
                        armorPen: 0.55,
                        attackerX: trap.x,
                        attackerY: trap.y,
                        knockbackX: 0.0,
                        knockbackY: 0.0,
                        stunDuration: 0.4,
                        forceGiantStagger: false,
                        byHeroSide: nil
                    )
                }
                break
            }
        }
    }

    public func terrainAt(x: Double, y: Double) -> TerrainType {
        for z in terrainZones where z.contains(x: x, y: y) {
            return z.terrain
        }
        return context.terrain
    }

    private func computeEffectiveAttackRange(for unit: SoldierEntity, terrain: TerrainType) -> Double {
        guard unit.category == .ranged || unit.category == .siege || unit.unitType == .canglangKeshigHorseArcher else {
            return unit.attackRange
        }
        var range = unit.attackRange
        if unit.faction == .tieying {
            range *= 1.12
        } else if unit.faction == .shuangyuan && unit.category == .ranged {
            range *= 0.90
        }
        if terrain == .fortWall {
            range *= 1.25
        } else if terrain == .highGround {
            range *= 1.20
        }
        if context.weather == .rainMud && unit.unitType != .trebuchet && unit.unitType != .ballista {
            range *= 0.80
        }
        if (context.weather == .heavyFog || context.weather == .night)
            && !(context.weather == .night && unit.faction == .xueyue) {
            let visionCap = GameConstants.visionRadiusInfantry * 0.65
            range = min(range, max(160.0, visionCap))
        }
        return range
    }

    private func computeAdjustedRecruitmentCost(
        baseCost: ResourceCost,
        category: UnitCategory,
        faction: FactionId
    ) -> ResourceCost {
        var g = Double(baseCost.gold)
        var w = Double(baseCost.wood)
        let gr = baseCost.grain

        if faction == .yanlong {
            if category == .siege {
                g *= 0.80
                w *= 0.80
            } else if category == .cavalry {
                g *= 1.15
            }
        } else if faction == .tieying && category == .shock {
            g *= 1.10
        }
        return ResourceCost(gold: Int(g.rounded()), wood: Int(w.rounded()), grain: gr)
    }

    private mutating func applyInstantSquadMoraleDelta(squadId: Int, delta: Double) {
        guard squadId >= 0 && squadId < squads.count, squads[squadId].aliveCount > 0 else { return }
        let side = squads[squadId].side
        let heroDown = side == .player ? (playerHero.vitalState == .recoveringInCamp) : (enemyHero.vitalState == .recoveringInCamp)
        let fervor = side == .player ? (playerState.bloodMoonFervorRemainingSec > 0.0) : (enemyState.bloodMoonFervorRemainingSec > 0.0)
        let supplyCap = side == .player ? playerState.supplyMoraleCeiling : enemyState.supplyMoraleCeiling
        let fearless = squads[squadId].primaryUnitType == .xueyueWardrumBerserker
            || (squads[squadId].faction == .xueyue && fervor)

        let updated = DamageMoraleCalculator.updateMoraleAndBracket(
            currentMorale: squads[squadId].morale,
            wasRouting: squads[squadId].isRouting,
            moraleDelta: delta,
            commanderRecoveringInCamp: heroDown,
            encirclementCap: squads[squadId].encirclementState == .encircled ? 45.0 : nil,
            supplyCap: supplyCap,
            isFearlessBerserker: fearless,
            inCloseEnemyContact: squads[squadId].engagedOctantMask != 0
        )
        squads[squadId].morale = updated.morale
        squads[squadId].moraleBracket = updated.bracket
        squads[squadId].isRouting = updated.isRouting
    }

    private mutating func applyArmyWideMoraleShock(side: BattleSide, delta: Double) {
        for idx in 0..<squads.count where squads[idx].side == side && squads[idx].aliveCount > 0 {
            applyInstantSquadMoraleDelta(squadId: idx, delta: delta)
        }
    }

    private func computeNonRoutingArmyRatio(for side: BattleSide) -> Double {
        let totalInit = max(1, side == .player ? playerState.totalInitialSoldiers : enemyState.totalInitialSoldiers)
        var nonRoutingAlive = 0
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 && soldiers[i].side == side {
            let sqId = soldiers[i].squadId
            let routing = (sqId >= 0 && sqId < squads.count) ? squads[sqId].isRouting : false
            if !routing {
                nonRoutingAlive += 1
            }
        }
        return Double(nonRoutingAlive) / Double(totalInit)
    }

    private func isBaseCampDestroyed(for side: BattleSide) -> Bool {
        for st in structures where st.side == side && st.kind == .baseCamp {
            return st.isDestroyed
        }
        return false
    }

    public func baseCampCoordinates(for side: BattleSide) -> (x: Double, y: Double) {
        for st in structures where st.side == side && st.kind == .baseCamp {
            return (st.x, st.y)
        }
        let leftX = (worldWidth - GameConstants.baseCampHorizontalSpan) * 0.5
        return side == .player ? (leftX, worldHeight * 0.5) : (worldWidth - leftX, worldHeight * 0.5)
    }

    private func isHeroNearFriendlySupply(hero: HeroCommanderEntity) -> Bool {
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 && soldiers[i].side == hero.side {
            if soldiers[i].unitType == .sapper || soldiers[i].corpsRole == .supplyEscort {
                let dx = soldiers[i].x - hero.x
                let dy = soldiers[i].y - hero.y
                if dx * dx + dy * dy <= 140.0 * 140.0 {
                    return true
                }
            }
        }
        return false
    }

    private func buildAutonomousCommanderInput(
        for hero: HeroCommanderEntity,
        campPos: (x: Double, y: Double)
    ) -> HeroControlInputState {
        guard hero.isActiveOnField else { return HeroControlInputState() }
        let enemySide = hero.side.opponent

        // 若周围 190px 有逼近敌兵，主帅拔佩刀迎战护卫战线
        let nearEnemyIdx = spatialGrid.findNearestEnemy(
            fromX: hero.x,
            fromY: hero.y,
            enemySide: enemySide,
            maxRange: 190.0,
            viewerFaction: hero.faction
        )
        if nearEnemyIdx != -1 && hero.hp > hero.maxHp * 0.28 {
            let ex = soldiers[nearEnemyIdx].x
            let ey = soldiers[nearEnemyIdx].y
            let dx = ex - hero.x
            let dy = ey - hero.y
            let dist = max(1.0, hypot(dx, dy))
            return HeroControlInputState(
                moveAxisX: dist > 36.0 ? (dx / dist) : 0.0,
                moveAxisY: dist > 36.0 ? (dy / dist) : 0.0,
                aimWorldX: ex,
                aimWorldY: ey,
                isPrimaryAttackHeld: dist <= 48.0,
                isSecondaryBlockHeld: false
            )
        }

        // 否则跟随己方中军前锋后侧 90px 督战，提供 350px 帅旗士气光环
        var guardX = campPos.x + (hero.side == .player ? 260.0 : -260.0)
        var guardY = campPos.y
        if let vanguard = squads.first(where: { $0.side == hero.side && $0.corpsRole == .vanguardCenter && $0.aliveCount > 0 && !$0.isRouting }) {
            let backOffset = hero.side == .player ? -95.0 : 95.0
            guardX = vanguard.anchorX + backOffset
            guardY = vanguard.anchorY
        }
        let dx = guardX - hero.x
        let dy = guardY - hero.y
        let dist = hypot(dx, dy)
        return HeroControlInputState(
            moveAxisX: dist > 24.0 ? (dx / dist) : 0.0,
            moveAxisY: dist > 24.0 ? (dy / dist) : 0.0,
            aimWorldX: hero.side == .player ? worldWidth : 0.0,
            aimWorldY: guardY,
            isPrimaryAttackHeld: false,
            isSecondaryBlockHeld: false
        )
    }

    private func pickBestResourceNode(for side: BattleSide, fromX: Double, fromY: Double) -> Int {
        var bestIdx = -1
        var bestScore = Double.greatestFiniteMagnitude
        let camp = baseCampCoordinates(for: side)
        for idx in 0..<resourceNodes.count where resourceNodes[idx].remainingAmount > 0.0 {
            let dUnit = hypot(resourceNodes[idx].x - fromX, resourceNodes[idx].y - fromY)
            let dCamp = hypot(resourceNodes[idx].x - camp.x, resourceNodes[idx].y - camp.y)
            let score = dUnit * 0.4 + dCamp * 0.6
            if score < bestScore {
                bestScore = score
                bestIdx = idx
            }
        }
        return bestIdx
    }

    private mutating func spawnProjectile(
        kind: ProjectileKind,
        side: BattleSide,
        sourceUnitIndex: Int,
        originX: Double,
        originY: Double,
        targetX: Double,
        targetY: Double,
        speed: Double,
        arcHeight: Double,
        damage: Double,
        armorPen: Double,
        aoeRadius: Double,
        pierceCount: Int,
        appliesPoison: Bool,
        moraleShock: Double,
        structureBonus: Double
    ) {
        var slotIdx = -1
        for i in 0..<projectiles.count where !projectiles[i].isActive {
            slotIdx = i
            break
        }
        guard slotIdx != -1 else { return }

        let dx = targetX - originX
        let dy = targetY - originY
        let dist = max(12.0, hypot(dx, dy))
        let safeSpeed = max(80.0, speed)
        let duration = dist / safeSpeed

        projectiles[slotIdx].isActive = true
        projectiles[slotIdx].kind = kind
        projectiles[slotIdx].side = side
        projectiles[slotIdx].sourceUnitIndex = sourceUnitIndex
        projectiles[slotIdx].x = originX
        projectiles[slotIdx].y = originY
        projectiles[slotIdx].vx = (dx / dist) * safeSpeed
        projectiles[slotIdx].vy = (dy / dist) * safeSpeed
        projectiles[slotIdx].originX = originX
        projectiles[slotIdx].originY = originY
        projectiles[slotIdx].targetX = targetX
        projectiles[slotIdx].targetY = targetY
        projectiles[slotIdx].flightElapsed = 0.0
        projectiles[slotIdx].flightDuration = duration
        projectiles[slotIdx].arcHeight = arcHeight
        projectiles[slotIdx].damage = damage
        projectiles[slotIdx].armorPenetration = armorPen
        projectiles[slotIdx].aoeRadius = aoeRadius
        projectiles[slotIdx].remainingPierces = max(1, pierceCount)
        projectiles[slotIdx].appliesPoison = appliesPoison
        projectiles[slotIdx].moraleShock = moraleShock
        projectiles[slotIdx].structureBonusMultiplier = structureBonus
        projectiles[slotIdx].piercedUnit0 = -1
        projectiles[slotIdx].piercedUnit1 = -1
        projectiles[slotIdx].piercedUnit2 = -1
    }

    private mutating func recordCorpseDecal(from soldier: SoldierEntity) {
        let slot = corpseRingCursor % GameConstants.maxFallenCorpseDecals
        corpseRingCursor += 1
        corpseDecals[slot].isActive = true
        corpseDecals[slot].side = soldier.side
        corpseDecals[slot].faction = soldier.faction
        corpseDecals[slot].unitType = soldier.unitType
        corpseDecals[slot].x = soldier.x
        corpseDecals[slot].y = soldier.y
        corpseDecals[slot].rotationRadians = soldier.facingRadians
        corpseDecals[slot].isBrokenBanner = soldier.isBannerBearer
        corpseDecals[slot].spawnTime = elapsedSeconds
    }

    private mutating func spawnParticle(
        kind: EffectParticleKind,
        x: Double,
        y: Double,
        lifetime: Double,
        numericValue: Int = 0,
        isCritical: Bool = false
    ) {
        let slot = particleRingCursor % GameConstants.maxEffectParticlePoolSize
        particleRingCursor += 1
        effectParticles[slot].isActive = true
        effectParticles[slot].kind = kind
        effectParticles[slot].x = x
        effectParticles[slot].y = y
        effectParticles[slot].vx = 0.0
        effectParticles[slot].vy = -18.0
        effectParticles[slot].lifetime = lifetime
        effectParticles[slot].maxLifetime = lifetime
        effectParticles[slot].numericValue = numericValue
        effectParticles[slot].isCritical = isCritical
    }

    private mutating func stepParticlesOnly(deltaTime: Double) {
        for idx in 0..<effectParticles.count where effectParticles[idx].isActive {
            effectParticles[idx].lifetime -= deltaTime
            effectParticles[idx].x += effectParticles[idx].vx * deltaTime
            effectParticles[idx].y += effectParticles[idx].vy * deltaTime
            if effectParticles[idx].lifetime <= 0.0 {
                effectParticles[idx].isActive = false
            }
        }
    }

    private mutating func updateFogOfWarVisibility() {
        let nightOrFogPenalty = (context.weather == .heavyFog || context.weather == .night) ? 0.60 : 1.0
        let playerLosslessNight = context.weather == .night && playerState.faction == .xueyue
        let pVisionMult = playerLosslessNight ? 1.0 : nightOrFogPenalty

        for eIdx in 0..<soldiers.count where soldiers[eIdx].isActive && soldiers[eIdx].hp > 0.0 {
            if soldiers[eIdx].side == .player {
                soldiers[eIdx].isVisibleToOpponent = true
                continue
            }
            if playerState.faction == .wulin && terrainAt(x: soldiers[eIdx].x, y: soldiers[eIdx].y) == .denseForest {
                soldiers[eIdx].isVisibleToOpponent = true
                continue
            }

            let inForestHidden = soldiers[eIdx].isStealthed
                || (terrainAt(x: soldiers[eIdx].x, y: soldiers[eIdx].y) == .denseForest && soldiers[eIdx].outOfCombatTimer >= 1.5)
            let ex = soldiers[eIdx].x
            let ey = soldiers[eIdx].y

            var spotted = false
            if playerHero.isActiveOnField {
                let hRange = (inForestHidden ? GameConstants.forestStealthRevealRadius : GameConstants.visionRadiusCavalry) * pVisionMult
                if (playerHero.x - ex) * (playerHero.x - ex) + (playerHero.y - ey) * (playerHero.y - ey) <= hRange * hRange {
                    spotted = true
                }
            }
            if !spotted {
                let queryR = (inForestHidden ? (GameConstants.forestStealthRevealRadius * 1.5) : GameConstants.visionRadiusCavalry) * pVisionMult
                let visionHits = spatialGrid.queryInRadius(centerX: ex, centerY: ey, radius: queryR, sideFilter: .player, maxResults: 16)
                for h in 0..<visionHits.count {
                    let pIdx = visionHits[h].unitIndex
                    let dSq = visionHits[h].distanceSquared
                    let baseV = soldiers[pIdx].category == .cavalry ? GameConstants.visionRadiusCavalry : GameConstants.visionRadiusInfantry
                    let hillBoost = terrainAt(x: soldiers[pIdx].x, y: soldiers[pIdx].y) == .highGround ? 1.25 : 1.0
                    let effV: Double
                    if inForestHidden {
                        effV = soldiers[pIdx].unitType == .lightCavalry ? (GameConstants.forestStealthRevealRadius * 1.5) : GameConstants.forestStealthRevealRadius
                    } else {
                        effV = baseV * hillBoost * pVisionMult
                    }
                    if dSq <= effV * effV {
                        spotted = true
                        break
                    }
                }
            }
            soldiers[eIdx].isVisibleToOpponent = spotted
        }
    }

    private mutating func refreshHudSnapshotNow() {
        var pAlive = 0
        var eAlive = 0
        var moraleWeightedSum = 0.0
        var moraleSoldierCount = 0

        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 {
            if soldiers[i].side == .player {
                pAlive += 1
            } else {
                eAlive += 1
            }
        }
        for sq in squads where sq.side == .player && sq.aliveCount > 0 {
            moraleWeightedSum += sq.morale * Double(sq.aliveCount)
            moraleSoldierCount += sq.aliveCount
        }
        let avgMorale = moraleSoldierCount > 0 ? (moraleWeightedSum / Double(moraleSoldierCount)) : (outcome == .playerCommanderMartyred ? 0.0 : GameConstants.moraleBase)

        latestHudSnapshot = BattleHudSnapshot(
            elapsedSeconds: elapsedSeconds,
            isPaused: isPaused,
            controlMode: controlMode,
            switchCooldownRemaining: switchCooldownRemaining,
            garrisonBellActive: playerState.garrisonBellActive,
            gold: playerState.gold,
            wood: playerState.wood,
            grain: playerState.grain,
            rationStage: playerState.rationStage,
            playerAliveCount: pAlive,
            playerPopUsed: playerState.popUsed,
            playerPopCap: playerState.popCap,
            enemyAliveCount: eAlive,
            averagePlayerMorale: avgMorale,
            heroHp: playerHero.hp,
            heroMaxHp: playerHero.maxHp,
            heroVitalState: playerHero.vitalState,
            heroActiveWeapon: playerHero.activeWeapon,
            heroRemainingArrows: playerHero.remainingArrows,
            outcome: outcome
        )
    }

    // MARK: - 十四、战场地形、资源点、攻城防线与双方 6 大军团初始构建

    private mutating func setupTerrainAndResources(leftCampX: Double, rightCampX: Double) {
        let midX = worldWidth * 0.5
        let midY = worldHeight * 0.5

        // 北翼迂回走廊密林与山脊高地
        terrainZones.append(TerrainZoneRect(id: 0, terrain: .denseForest, minX: midX - 780.0, maxX: midX - 180.0, minY: 160.0, maxY: 620.0, elevationLevel: 1))
        terrainZones.append(TerrainZoneRect(id: 1, terrain: .denseForest, minX: midX + 180.0, maxX: midX + 780.0, minY: 160.0, maxY: 620.0, elevationLevel: 1))
        terrainZones.append(TerrainZoneRect(id: 2, terrain: .highGround, minX: midX - 380.0, maxX: midX + 380.0, minY: 660.0, maxY: 940.0, elevationLevel: 2))

        // 中路核心地形按场景 `context.terrain` 动态塑造
        switch context.terrain {
        case .riverFord:
            terrainZones.append(TerrainZoneRect(id: 3, terrain: .bridgePass, minX: midX - 170.0, maxX: midX + 170.0, minY: 620.0, maxY: 790.0, elevationLevel: 1))
            terrainZones.append(TerrainZoneRect(id: 4, terrain: .riverFord, minX: midX - 170.0, maxX: midX + 170.0, minY: 790.0, maxY: worldHeight - 620.0, elevationLevel: 0))
        case .bridgePass:
            terrainZones.append(TerrainZoneRect(id: 3, terrain: .bridgePass, minX: midX - 190.0, maxX: midX + 190.0, minY: midY - 140.0, maxY: midY + 140.0, elevationLevel: 1))
            terrainZones.append(TerrainZoneRect(id: 4, terrain: .riverFord, minX: midX - 160.0, maxX: midX + 160.0, minY: 640.0, maxY: midY - 140.0, elevationLevel: 0))
            terrainZones.append(TerrainZoneRect(id: 5, terrain: .riverFord, minX: midX - 160.0, maxX: midX + 160.0, minY: midY + 140.0, maxY: worldHeight - 640.0, elevationLevel: 0))
        case .highGround:
            terrainZones.append(TerrainZoneRect(id: 3, terrain: .highGround, minX: midX - 680.0, maxX: midX - 160.0, minY: midY - 320.0, maxY: midY + 320.0, elevationLevel: 2))
            terrainZones.append(TerrainZoneRect(id: 4, terrain: .highGround, minX: midX + 160.0, maxX: midX + 680.0, minY: midY - 320.0, maxY: midY + 320.0, elevationLevel: 2))
        case .denseForest:
            terrainZones.append(TerrainZoneRect(id: 3, terrain: .denseForest, minX: midX - 560.0, maxX: midX + 560.0, minY: midY - 360.0, maxY: midY + 360.0, elevationLevel: 1))
        default:
            // 标准平原保留一处中央浅滩与南侧缓坡，支持半渡而击与居高战术体验
            terrainZones.append(TerrainZoneRect(id: 3, terrain: .riverFord, minX: midX - 110.0, maxX: midX + 110.0, minY: midY + 80.0, maxY: midY + 460.0, elevationLevel: 0))
        }

        // 对称分布 6 处野外金矿、林木区与农庄粮垛
        resourceNodes = [
            BattleResourceNode(id: 0, kind: .goldMine, x: leftCampX + 560.0, y: 340.0, remainingAmount: 900.0, yieldPerTrip: 35.0, gatherDurationSec: 3.5),
            BattleResourceNode(id: 1, kind: .lumberForest, x: leftCampX + 480.0, y: 540.0, remainingAmount: 800.0, yieldPerTrip: 30.0, gatherDurationSec: 3.2),
            BattleResourceNode(id: 2, kind: .grainFarm, x: leftCampX + 540.0, y: worldHeight - 360.0, remainingAmount: 1100.0, yieldPerTrip: 48.0, gatherDurationSec: 3.5),
            BattleResourceNode(id: 3, kind: .goldMine, x: rightCampX - 560.0, y: 340.0, remainingAmount: 900.0, yieldPerTrip: 35.0, gatherDurationSec: 3.5),
            BattleResourceNode(id: 4, kind: .lumberForest, x: rightCampX - 480.0, y: 540.0, remainingAmount: 800.0, yieldPerTrip: 30.0, gatherDurationSec: 3.2),
            BattleResourceNode(id: 5, kind: .grainFarm, x: rightCampX - 540.0, y: worldHeight - 360.0, remainingAmount: 1100.0, yieldPerTrip: 48.0, gatherDurationSec: 3.5)
        ]
    }

    private mutating func setupBaseCampsAndSiegeWorks(leftCampX: Double, rightCampX: Double) {
        let midY = worldHeight * 0.5
        let pCampMult = playerState.faction == .yanlong ? 1.20 : 1.0
        let eCampMult = enemyState.faction == .yanlong ? 1.20 : 1.0

        structures.append(
            SiegeStructureEntity(id: 0, side: .player, kind: .baseCamp, x: leftCampX, y: midY, width: 150.0, height: 280.0, hp: 2600.0 * pCampMult, armor: 42.0)
        )
        structures.append(
            SiegeStructureEntity(id: 1, side: .enemy, kind: .baseCamp, x: rightCampX, y: midY, width: 150.0, height: 280.0, hp: 2600.0 * eCampMult, armor: 42.0)
        )

        if context.scenarioType == .siegeAssault || context.scenarioType == .siegeDefense {
            let defenderSide: BattleSide = context.scenarioType == .siegeAssault ? .enemy : .player
            let defenderFaction = defenderSide == .player ? playerState.faction : enemyState.faction
            let wallMult = defenderFaction == .yanlong ? 1.20 : 1.0
            let wallX = defenderSide == .enemy ? (rightCampX - 720.0) : (leftCampX + 720.0)
            let frontSign = defenderSide == .enemy ? -1.0 : 1.0

            // 城墙掩体地形带
            terrainZones.append(
                TerrainZoneRect(id: 90, terrain: .fortWall, minX: wallX - 65.0, maxX: wallX + 65.0, minY: 180.0, maxY: worldHeight - 180.0, elevationLevel: 2)
            )

            var nextStId = structures.count
            // 正城门 + 北/南城墙段 + 侧城门 + 双箭塔 + 双拒马 + 双云梯位
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .mainGate, x: wallX, y: midY, width: 72.0, height: 220.0, hp: 1850.0 * wallMult, armor: 32.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .wallSegment, x: wallX, y: midY - 520.0, width: 72.0, height: 780.0, hp: 2300.0 * wallMult, armor: 58.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .wallSegment, x: wallX, y: midY + 460.0, width: 72.0, height: 660.0, hp: 2300.0 * wallMult, armor: 58.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .sideSallyGate, x: wallX, y: worldHeight - 280.0, width: 68.0, height: 150.0, hp: 1150.0 * wallMult, armor: 36.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .arrowTower, x: wallX, y: midY - 190.0, width: 76.0, height: 76.0, hp: 1100.0 * wallMult, armor: 40.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .arrowTower, x: wallX, y: midY + 190.0, width: 76.0, height: 76.0, hp: 1100.0 * wallMult, armor: 40.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .woodenCheval, x: wallX + frontSign * 145.0, y: midY - 90.0, width: 42.0, height: 95.0, hp: 460.0, armor: 18.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide, kind: .woodenCheval, x: wallX + frontSign * 145.0, y: midY + 90.0, width: 42.0, height: 95.0, hp: 460.0, armor: 18.0))
            nextStId += 1
            // 两侧预设攻方简易登城云梯位（保证即便投石车全毁，攻方步兵也能登城决胜，彻底杜绝隔墙干瞪眼死锁！）
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide.opponent, kind: .siegeLadder, x: wallX + frontSign * 18.0, y: midY - 460.0, width: 44.0, height: 80.0, hp: 900.0, armor: 20.0))
            nextStId += 1
            structures.append(SiegeStructureEntity(id: nextStId, side: defenderSide.opponent, kind: .siegeLadder, x: wallX + frontSign * 18.0, y: midY + 460.0, width: 44.0, height: 80.0, hp: 900.0, armor: 20.0))
        }

        // 若雾林猎手参战，在前沿林道预置尖刺陷坑与绊马索
        if playerState.faction == .wulin {
            fieldTraps.append(BattleFieldTrap(id: fieldTraps.count, side: .player, kind: .tripwire, x: worldWidth * 0.42, y: 420.0))
            fieldTraps.append(BattleFieldTrap(id: fieldTraps.count, side: .player, kind: .spikePit, x: worldWidth * 0.42, y: worldHeight * 0.50))
        }
        if enemyState.faction == .wulin {
            fieldTraps.append(BattleFieldTrap(id: fieldTraps.count, side: .enemy, kind: .tripwire, x: worldWidth * 0.58, y: 420.0))
            fieldTraps.append(BattleFieldTrap(id: fieldTraps.count, side: .enemy, kind: .spikePit, x: worldWidth * 0.58, y: worldHeight * 0.50))
        }
    }

    private mutating func setupInitialArmies(leftCampX: Double, rightCampX: Double) {
        let playerRoster = deployment.customPlayerRoster ?? Self.defaultSixCorpsRoster(for: context.playerFaction, scenario: context.scenarioType, isPlayer: true)
        let enemyRoster = deployment.customEnemyRoster ?? Self.defaultSixCorpsRoster(for: context.enemyFaction, scenario: context.scenarioType, isPlayer: false)

        spawnArmyFromRoster(side: .player, faction: context.playerFaction, roster: playerRoster, campX: leftCampX)
        spawnArmyFromRoster(side: .enemy, faction: context.enemyFaction, roster: enemyRoster, campX: rightCampX)
    }

    /// 为任意势力生成符合 6 大军团建制（40% 前锋 / 18% 左翼 / 18% 右翼 / 24% 总预备队 + 攻城群 + 辎重护粮队）的精锐混编阵容
    public static func defaultSixCorpsRoster(
        for faction: FactionId,
        scenario: BattleScenarioType,
        isPlayer: Bool
    ) -> [BattleArmyRosterEntry] {
        let exclusive = FactionConfig.config(for: faction)?.exclusiveUnitId ?? .yanlongHalberdGrenadier
        let exclusiveCat = UnitConfig.stats(for: exclusive)?.category ?? .infantry

        // 苍狼汗国严禁建造配重投石车，改配破甲连弩车/复合弓手
        let siegeType: UnitTypeId = {
            if faction == .canglang { return .ballista }
            if scenario == .siegeAssault || (scenario == .siegeDefense && !isPlayer) {
                return .trebuchet
            }
            return faction == .tieying ? .tieyingPaviseCrossbow : .compositeArcher
        }()

        let vanguardUnit: UnitTypeId = (exclusiveCat == .infantry || exclusiveCat == .shock) ? exclusive : .shieldSwordsman
        let leftWingUnit: UnitTypeId = (exclusiveCat == .cavalry) ? exclusive : .lightCavalry
        let rightWingUnit: UnitTypeId = .pikeman
        let reserveUnit: UnitTypeId = (exclusiveCat == .ranged) ? .greatAxeman : exclusive

        return [
            BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: vanguardUnit, count: vanguardUnit == .shuangyuanGiantBreaker ? 8 : 18, initialFormation: .phalanxRect),
            BattleArmyRosterEntry(corpsRole: .leftWing, unitType: leftWingUnit, count: leftWingUnit == .xuanjiaCataphract ? 7 : 10, initialFormation: .wedgeCharge),
            BattleArmyRosterEntry(corpsRole: .rightWing, unitType: rightWingUnit, count: 12, initialFormation: .phalanxRect),
            BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: reserveUnit, count: reserveUnit == .shuangyuanGiantBreaker || reserveUnit == .xuanjiaCataphract ? 6 : 12, initialFormation: .phalanxRect),
            BattleArmyRosterEntry(corpsRole: .siegeBattery, unitType: siegeType, count: (siegeType == .trebuchet || siegeType == .ballista) ? 3 : 12, initialFormation: .echelonLine),
            BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 4, initialFormation: .circleDefense)
        ]
    }

    private mutating func spawnArmyFromRoster(
        side: BattleSide,
        faction: FactionId,
        roster: [BattleArmyRosterEntry],
        campX: Double
    ) {
        let dirSign = side == .player ? 1.0 : -1.0
        let facing = side == .player ? 0.0 : Double.pi
        let midY = worldHeight * 0.5

        for entry in roster {
            guard let stats = UnitConfig.stats(for: entry.unitType) else { continue }
            // 强校验苍狼汗国禁造配重投石车规则，若自定义表误传则自动降级为破甲连弩车
            let safeUnitType: UnitTypeId = (faction == .canglang && entry.unitType == .trebuchet) ? .ballista : entry.unitType
            guard let finalStats = UnitConfig.stats(for: safeUnitType) else { continue }

            let anchor: (x: Double, y: Double) = {
                switch entry.corpsRole {
                case .vanguardCenter:
                    return (campX + dirSign * 640.0, midY)
                case .leftWing:
                    return (campX + dirSign * 580.0, 420.0)
                case .rightWing:
                    return (campX + dirSign * 580.0, worldHeight - 420.0)
                case .siegeBattery:
                    return (campX + dirSign * 420.0, midY - 90.0)
                case .rearReserve:
                    return (campX + dirSign * 310.0, midY + 90.0)
                case .supplyEscort:
                    return (campX + dirSign * 140.0, midY)
                }
            }()

            // 计算初始士气（含苍狼步兵 -5、商盟本土兵 -6、背盟惩罚、劫营夜袭 -15 与断粮上限封顶）
            var initMorale = GameConstants.moraleBase
            if faction == .canglang && (finalStats.category == .infantry || finalStats.category == .polearm) {
                initMorale -= 5.0
            } else if faction == .shamo && finalStats.exclusiveFaction == nil {
                initMorale -= 6.0
            }
            if side == .player {
                initMorale += deployment.playerBetrayalMoralePenalty
                initMorale = min(initMorale, playerState.supplyMoraleCeiling)
            } else {
                initMorale += deployment.enemyInitialMoraleDelta
            }
            if context.scenarioType == .nightRaid && side == .enemy && abs(deployment.enemyInitialMoraleDelta) < 1e-6 {
                initMorale -= 15.0 // 单局遭遇劫营夜袭方开场震慑敌军士气 -15（战役模式已由 enemyInitialMoraleDelta 注入）
            }
            if finalStats.id == .xueyueWardrumBerserker {
                initMorale = max(50.0, initMorale)
            }
            initMorale = clamp(initMorale, minVal: 25.0, maxVal: GameConstants.moraleMax)

            let sqId = squads.count
            let initialOrder: TacticalOrder = {
                if entry.corpsRole == .supplyEscort || entry.corpsRole == .rearReserve {
                    return .holdGround
                }
                if context.scenarioType == .siegeDefense && side == .player {
                    return .holdGround
                }
                if context.scenarioType == .siegeAssault && side == .enemy {
                    return .holdGround
                }
                return .advance
            }()

            var squad = BattleSquadState(
                id: sqId,
                side: side,
                faction: faction,
                corpsRole: entry.corpsRole,
                primaryUnitType: safeUnitType,
                formation: entry.initialFormation,
                order: initialOrder,
                anchorX: anchor.x,
                anchorY: anchor.y,
                facingRadians: facing,
                morale: initMorale
            )
            // 开战默认向敌方战线推进，实现“开战即多线真实交火”
            if initialOrder == .advance {
                squad.targetX = worldWidth * 0.5 + dirSign * 180.0
                squad.targetY = anchor.y
            }

            var spawnedInSquad = 0
            for slotIdx in 0..<entry.count {
                let offset = DamageMoraleCalculator.computeFormationSlotOffset(
                    slotIndex: slotIdx,
                    totalSlots: entry.count,
                    formation: entry.initialFormation,
                    spacing: finalStats.category == .cavalry ? 26.0 : (finalStats.category == .siege ? 38.0 : 20.0)
                )
                let cosF = cos(facing)
                let sinF = sin(facing)
                let wx = clamp(anchor.x + offset.forwardX * cosF - offset.lateralY * sinF, minVal: 30.0, maxVal: worldWidth - 30.0)
                let wy = clamp(anchor.y + offset.forwardX * sinF + offset.lateralY * cosF, minVal: 30.0, maxVal: worldHeight - 30.0)

                let isBanner = (slotIdx == 0 && entry.corpsRole != .supplyEscort && finalStats.category != .siege)
                if let uIdx = allocateSoldierSlot(
                    side: side,
                    faction: faction,
                    squadId: sqId,
                    corpsRole: entry.corpsRole,
                    stats: finalStats,
                    x: wx,
                    y: wy,
                    facing: facing,
                    slotOffsetX: offset.forwardX,
                    slotOffsetY: offset.lateralY,
                    isBannerBearer: isBanner
                ) {
                    if isBanner {
                        squad.bannerUnitIndex = uIdx
                    }
                    spawnedInSquad += 1
                    if side == .player {
                        playerState.popUsed += finalStats.popCap
                        playerState.totalInitialSoldiers += 1
                    } else {
                        enemyState.popUsed += finalStats.popCap
                        enemyState.totalInitialSoldiers += 1
                    }
                }
            }

            squad.initialCount = spawnedInSquad
            squad.aliveCount = spawnedInSquad
            squads.append(squad)
        }
    }

    private mutating func spawnTrainedSoldier(
        side: BattleSide,
        unitType: UnitTypeId,
        corpsRole: ArmyCorpsRole,
        isMercenary: Bool
    ) {
        let faction = side == .player ? playerState.faction : enemyState.faction
        guard let stats = UnitConfig.stats(for: unitType) else { return }
        let camp = baseCampCoordinates(for: side)
        let dirSign = side == .player ? 1.0 : -1.0
        let facing = side == .player ? 0.0 : Double.pi

        var targetSquadId = -1
        for idx in 0..<squads.count where squads[idx].side == side && squads[idx].corpsRole == corpsRole && squads[idx].isMercenary == isMercenary {
            targetSquadId = idx
            break
        }
        if targetSquadId == -1 {
            targetSquadId = squads.count
            let sq = BattleSquadState(
                id: targetSquadId,
                side: side,
                faction: faction,
                corpsRole: corpsRole,
                primaryUnitType: unitType,
                formation: stats.category == .cavalry ? .wedgeCharge : .phalanxRect,
                order: corpsRole == .supplyEscort ? .holdGround : .advance,
                anchorX: camp.x + dirSign * 110.0,
                anchorY: camp.y,
                facingRadians: facing,
                morale: GameConstants.moraleBase,
                isMercenary: isMercenary
            )
            squads.append(sq)
        }

        let spawnX = clamp(camp.x + dirSign * 95.0, minVal: 30.0, maxVal: worldWidth - 30.0)
        let spawnY = clamp(camp.y + rng.nextRange(min: -45.0, max: 45.0), minVal: 30.0, maxVal: worldHeight - 30.0)
        if allocateSoldierSlot(
            side: side,
            faction: faction,
            squadId: targetSquadId,
            corpsRole: corpsRole,
            stats: stats,
            x: spawnX,
            y: spawnY,
            facing: facing,
            slotOffsetX: 0.0,
            slotOffsetY: 0.0,
            isBannerBearer: false
        ) != nil {
            squads[targetSquadId].aliveCount += 1
            squads[targetSquadId].initialCount += 1
            if side == .player {
                playerState.totalInitialSoldiers += 1
            } else {
                enemyState.totalInitialSoldiers += 1
            }
            assignFormationSlotsForSquad(squadId: targetSquadId)
        }
    }

    private mutating func allocateSoldierSlot(
        side: BattleSide,
        faction: FactionId,
        squadId: Int,
        corpsRole: ArmyCorpsRole,
        stats: UnitStaticStats,
        x: Double,
        y: Double,
        facing: Double,
        slotOffsetX: Double,
        slotOffsetY: Double,
        isBannerBearer: Bool
    ) -> Int? {
        var foundIdx = -1
        for i in 0..<soldiers.count where !soldiers[i].isActive {
            foundIdx = i
            break
        }
        guard foundIdx != -1 else { return nil }

        // 应用势力基础属性被动：霜原全军生命 +15%，炎龙步兵护甲 +15%，玄甲骑兵护甲 +25%
        let hpMult = faction == .shuangyuan ? 1.15 : 1.0
        var armorVal = Double(stats.armor)
        if faction == .yanlong && (stats.category == .infantry || stats.category == .polearm) {
            armorVal *= 1.15
        } else if faction == .xuanjia && stats.category == .cavalry {
            armorVal *= 1.25
        }

        let radius: Double = {
            if stats.id == .shuangyuanGiantBreaker || stats.category == .cavalry { return 11.0 }
            if stats.category == .siege { return 14.0 }
            return 8.0
        }()

        var s = SoldierEntity.inactiveSlot(index: foundIdx)
        s.isActive = true
        s.side = side
        s.faction = faction
        s.squadId = squadId
        s.corpsRole = corpsRole
        s.unitType = stats.id
        s.category = stats.category
        s.x = x
        s.y = y
        s.facingRadians = facing
        s.slotOffsetX = slotOffsetX
        s.slotOffsetY = slotOffsetY
        s.collisionRadius = radius
        s.maxHp = Double(stats.hp) * hpMult
        s.hp = s.maxHp
        s.baseAttack = Double(stats.attack)
        s.baseArmor = armorVal
        s.armorPenetration = stats.armorPenetration
        s.shieldRangedBlock = stats.shieldRangedBlock
        s.attackRange = stats.attackRange
        s.minRange = stats.minRange
        s.attackInterval = stats.attackIntervalSec
        s.baseMoveSpeed = stats.moveSpeed
        s.chargeMultiplier = stats.chargeMultiplier
        s.antiCavalryMultiplier = stats.antiCavalryMultiplier
        s.grenadeCharges = stats.id == .yanlongHalberdGrenadier ? 1 : 0
        s.isBannerBearer = isBannerBearer
        s.isVisibleToOpponent = side == .player
        soldiers[foundIdx] = s
        return foundIdx
    }

    private mutating func assignFormationSlotsForSquad(squadId: Int) {
        guard squadId >= 0 && squadId < squads.count else { return }
        var total = 0
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 && soldiers[i].squadId == squadId {
            total += 1
        }
        guard total > 0 else { return }
        let formation = squads[squadId].formation
        var curSlot = 0
        for i in 0..<soldiers.count where soldiers[i].isActive && soldiers[i].hp > 0.0 && soldiers[i].squadId == squadId {
            let spacing = soldiers[i].category == .cavalry ? 26.0 : (soldiers[i].category == .siege ? 38.0 : 20.0)
            let off = DamageMoraleCalculator.computeFormationSlotOffset(
                slotIndex: curSlot,
                totalSlots: total,
                formation: formation,
                spacing: spacing
            )
            soldiers[i].slotOffsetX = off.forwardX
            soldiers[i].slotOffsetY = off.lateralY
            curSlot += 1
        }
    }

    @inline(__always)
    private func clamp(_ v: Double, minVal: Double, maxVal: Double) -> Double {
        max(minVal, min(maxVal, v))
    }
}
