import Foundation

/// L2 战场多军团战术黑板指挥官 AI 与攻守城三段式状态机（纯值类型 Sendable，每 0.5 秒更新黑板态势）
/// 严格对齐 AIContracts.swift 与 DESIGN.md 9.2 节：
/// 1. 绝不将全部兵力混成一团无脑平推，按 6 大建制军团（前锋、左翼、右翼、总预备队、攻城群、护粮队）多线协同；
/// 2. 完整实现锤砧两翼包抄、高地刺猬防反（拒追单骑诱饵）、诈败诱敌入林、半渡而击、奇袭断粮、总预备队决胜投入；
/// 3. 反风筝智能克制：检测到玩家主帅孤身骚扰时仅单派 1 支机动分队驱离（残血 <45% 则围猎斩首），主力严守战线绝不全军傻追；
/// 4. 攻守城专项三段式状态机（`SiegeTacticalPhase`）及投石全毁后步兵云梯/巨斧破门防死锁机制。
public struct BattleTacticalAI: Sendable, Equatable {
    /// 黑板刷新周期（秒）
    public static let blackboardUpdateIntervalSec: Double = 0.50

    public private(set) var timeSinceLastUpdate: Double = 0.0
    public private(set) var blackboard: TacticalBlackboardSummary
    private var feignedRetreatTriggeredOnce: Bool = false

    public init(initialDoctrine: BattlefieldAiDoctrine = .hammerAndAnvil) {
        self.blackboard = TacticalBlackboardSummary(
            activeDoctrine: initialDoctrine,
            siegePhase: nil,
            reserveCommitted: false,
            detectedPlayerHeroKiting: false
        )
    }

    /// 推进 AI 计时器；每满 0.5s 刷新战术黑板并向 AI 所属各军团下达协同阵型与航点指令
    public mutating func stepAI(
        deltaTime: Double,
        aiSide: BattleSide = .enemy,
        aiFaction: FactionId,
        scenarioType: BattleScenarioType,
        elapsedSeconds: Double,
        worldWidth: Double,
        worldHeight: Double,
        commandParalysisTimer: Double,
        opponentGarrisonBellActive: Bool,
        opponentHero: HeroCommanderEntity,
        aiHero: HeroCommanderEntity,
        squads: inout [BattleSquadState],
        soldiers: [SoldierEntity],
        structures: [SiegeStructureEntity],
        terrainZones: [TerrainZoneRect],
        resourceNodes: [BattleResourceNode]
    ) {
        timeSinceLastUpdate += deltaTime
        guard timeSinceLastUpdate >= Self.blackboardUpdateIntervalSec else { return }
        timeSinceLastUpdate = 0.0

        // 敌帅落马 15s 指挥瘫痪期内：无法变阵、无法切换条令或投入总预备队
        guard commandParalysisTimer <= 0.0 else { return }

        let personality = FactionConfig.config(for: aiFaction)?.aiPersonality ?? .imperialMethodical
        let opponentSide = aiSide.opponent

        // 1. 汇总敌我军团态势中心、士气缺口与远程/近战比重
        var opponentMainX = opponentSide == .player ? worldWidth * 0.30 : worldWidth * 0.70
        var opponentMainY = worldHeight * 0.50
        var sumOpponentX = 0.0
        var sumOpponentY = 0.0
        var opponentRangedX = opponentMainX
        var opponentRangedY = opponentMainY
        var hasOpponentRanged = false
        var opponentSquadCount = 0
        var weakestOpponentSquadIdx: Int = -1
        var weakestOpponentMorale: Double = 999.0
        var halfFordTargetIdx: Int = -1

        var aiAliveSquadCount = 0
        var criticalAiFrontIdx: Int = -1
        var lowestAiFrontMorale: Double = 999.0
        var aiRangedPop = 0
        var aiTotalPop = 0

        for idx in 0..<squads.count where squads[idx].aliveCount > 0 {
            let sq = squads[idx]
            if sq.side == opponentSide {
                opponentSquadCount += 1
                sumOpponentX += sq.anchorX
                sumOpponentY += sq.anchorY
                let oppCat = UnitConfig.stats(for: sq.primaryUnitType)?.category
                if sq.corpsRole == .siegeBattery || oppCat == .ranged || oppCat == .siege {
                    opponentRangedX = sq.anchorX
                    opponentRangedY = sq.anchorY
                    hasOpponentRanged = true
                }
                if sq.morale < weakestOpponentMorale {
                    weakestOpponentMorale = sq.morale
                    weakestOpponentSquadIdx = idx
                }
                if sq.riverWadingRatio >= 0.30 && sq.riverWadingRatio <= 0.80 && !sq.isRouting {
                    halfFordTargetIdx = idx
                }
            } else {
                aiAliveSquadCount += 1
                aiTotalPop += sq.aliveCount
                if let cat = UnitConfig.stats(for: sq.primaryUnitType)?.category,
                   cat == .ranged || cat == .siege {
                    aiRangedPop += sq.aliveCount
                }
                if (sq.corpsRole == .vanguardCenter || sq.corpsRole == .leftWing || sq.corpsRole == .rightWing),
                   sq.morale < lowestAiFrontMorale {
                    lowestAiFrontMorale = sq.morale
                    criticalAiFrontIdx = idx
                }
            }
        }

        if opponentSquadCount > 0 {
            opponentMainX = sumOpponentX / Double(opponentSquadCount)
            opponentMainY = sumOpponentY / Double(opponentSquadCount)
            if !hasOpponentRanged {
                opponentRangedX = opponentMainX
                opponentRangedY = opponentMainY
            }
        }
        guard aiAliveSquadCount > 0 else { return }

        // 2. 检测玩家主帅是否孤身越线风筝骚扰或残血冒进
        var minHeroToAllyDistSq = Double.greatestFiniteMagnitude
        var minHeroToAiDistSq = Double.greatestFiniteMagnitude
        if opponentHero.isActiveOnField {
            for idx in 0..<squads.count where squads[idx].aliveCount > 0 {
                let dx = squads[idx].anchorX - opponentHero.x
                let dy = squads[idx].anchorY - opponentHero.y
                let dSq = dx * dx + dy * dy
                if squads[idx].side == opponentSide {
                    if dSq < minHeroToAllyDistSq { minHeroToAllyDistSq = dSq }
                } else {
                    if dSq < minHeroToAiDistSq { minHeroToAiDistSq = dSq }
                }
            }
        }
        let heroIsolated = opponentHero.isActiveOnField
            && minHeroToAllyDistSq > (240.0 * 240.0)
            && minHeroToAiDistSq < (520.0 * 520.0)
        let heroLowHpAssassinate = heroIsolated && (opponentHero.hp < opponentHero.maxHp * 0.45)

        // 3. 攻守城专项三段式状态机分支
        if scenarioType == .siegeAssault || scenarioType == .siegeDefense {
            let aiIsAttacker = (aiSide == .enemy && scenarioType == .siegeDefense)
                || (aiSide == .player && scenarioType == .siegeAssault)
            updateSiegeTactics(
                aiSide: aiSide,
                aiIsAttacker: aiIsAttacker,
                opponentMainX: opponentMainX,
                opponentMainY: opponentMainY,
                opponentRangedX: opponentRangedX,
                opponentRangedY: opponentRangedY,
                hasOpponentRanged: hasOpponentRanged,
                heroIsolated: heroIsolated,
                opponentHero: opponentHero,
                worldWidth: worldWidth,
                worldHeight: worldHeight,
                squads: &squads,
                structures: structures
            )
            return
        }

        // 4. 野战总预备队决胜投入判定（己方前线 <35 士气危急堵口，或敌方前线 <40 动摇一锤定音）
        var commitReserve = blackboard.reserveCommitted
        if !commitReserve {
            if lowestAiFrontMorale < 35.0 || (elapsedSeconds > 16.0 && weakestOpponentMorale < 40.0) {
                commitReserve = true
            }
        }

        // 5. 选择主战术条令（Doctrine）
        let chosenDoctrine: BattlefieldAiDoctrine
        if heroIsolated && !commitReserve {
            chosenDoctrine = .antiKiteEscort
        } else if commitReserve && (lowestAiFrontMorale < 35.0 || weakestOpponentMorale < 40.0) {
            chosenDoctrine = .reserveBreakthrough
        } else if (personality == .fortressCounter || (personality == .merchantPragmatic && Double(aiRangedPop) > Double(max(1, aiTotalPop)) * 0.38))
            && hasHighGroundOrBridge(in: terrainZones) {
            chosenDoctrine = .highGroundHedgehog
        } else if (personality == .guerrillaTrapper || personality == .nomadOpportunist)
            && aiAliveSquadCount >= 2
            && !feignedRetreatTriggeredOnce
            && elapsedSeconds >= 12.0 && elapsedSeconds <= 58.0 {
            chosenDoctrine = .feignedRetreatAmbush
        } else {
            chosenDoctrine = .hammerAndAnvil
        }

        blackboard = TacticalBlackboardSummary(
            activeDoctrine: chosenDoctrine,
            siegePhase: nil,
            reserveCommitted: commitReserve,
            detectedPlayerHeroKiting: heroIsolated
        )

        // 6. 检查敌方野外是否有无护卫采集工兵可供轻骑【奇袭断粮】
        let exposedSapperTarget = findExposedEnemySapperPosition(
            opponentSide: opponentSide,
            opponentBellActive: opponentGarrisonBellActive,
            soldiers: soldiers,
            worldWidth: worldWidth
        )

        // 7. 按 6 大军团职责分配精细阵型、指令与机动航点（反风筝仅允许单支侧翼驱离，严禁主力脱队）
        var antiKiteEscortAssigned = false
        let aiHomeX = aiSide == .enemy ? (worldWidth - 520.0) : 520.0
        let advanceSign = aiSide == .enemy ? -1.0 : 1.0

        for idx in 0..<squads.count {
            guard squads[idx].side == aiSide,
                  squads[idx].aliveCount > 0,
                  !squads[idx].isRouting else { continue }

            let role = squads[idx].corpsRole
            let unitStats = UnitConfig.stats(for: squads[idx].primaryUnitType)
            let category = unitStats?.category ?? .infantry

            // 辎重护粮队由经济采集逻辑自主驱动，遇袭时回靠本阵
            if role == .supplyEscort {
                if category != .support {
                    squads[idx].formation = .circleDefense
                    squads[idx].order = .holdGround
                    squads[idx].targetX = aiHomeX + advanceSign * 180.0
                    squads[idx].targetY = worldHeight * 0.50
                }
                continue
            }

            // 半渡而击最高瞬时优先级：敌军涉水 30%~80% 首尾脱节时岸上全力猛扑
            if halfFordTargetIdx != -1, role == .vanguardCenter || role == .siegeBattery {
                let fordSq = squads[halfFordTargetIdx]
                squads[idx].order = category == .ranged || category == .siege ? .holdGround : .allOutCharge
                squads[idx].formation = category == .ranged ? .echelonLine : .wedgeCharge
                squads[idx].targetX = fordSq.anchorX
                squads[idx].targetY = fordSq.anchorY
                squads[idx].waypoints.removeAll(keepingCapacity: true)
                continue
            }

            // 反风筝单队驱离 / 残血主帅围猎斩首（主力前锋绝不跟追！）
            if heroIsolated && !antiKiteEscortAssigned && (role == .leftWing || role == .rightWing) {
                antiKiteEscortAssigned = true
                squads[idx].formation = category == .cavalry ? .wedgeCharge : .echelonLine
                squads[idx].order = heroLowHpAssassinate ? .allOutCharge : .advance
                squads[idx].targetX = opponentHero.x
                squads[idx].targetY = opponentHero.y
                squads[idx].waypoints.removeAll(keepingCapacity: true)
                continue
            }
            if heroLowHpAssassinate && (role == .siegeBattery || category == .ranged) {
                // 敌帅残血 <45% 时附近远程协同集火斩首
                let dx = squads[idx].anchorX - opponentHero.x
                let dy = squads[idx].anchorY - opponentHero.y
                let effRange = (unitStats?.attackRange ?? 360.0) * 1.05
                if dx * dx + dy * dy <= effRange * effRange {
                    squads[idx].order = .holdGround
                    squads[idx].targetX = opponentHero.x
                    squads[idx].targetY = opponentHero.y
                    continue
                }
            }

            // 按当前条令与军团角色分派战术任务
            switch chosenDoctrine {
            case .highGroundHedgehog:
                let hillPos = bestDefensiveAnchor(
                    aiSide: aiSide,
                    terrainZones: terrainZones,
                    worldWidth: worldWidth,
                    worldHeight: worldHeight
                )
                switch role {
                case .vanguardCenter:
                    squads[idx].formation = .phalanxRect
                    squads[idx].order = .holdGround
                    squads[idx].targetX = hillPos.x + advanceSign * 65.0
                    squads[idx].targetY = hillPos.y
                case .leftWing:
                    squads[idx].formation = category == .polearm ? .phalanxRect : .wedgeCharge
                    squads[idx].order = .holdGround
                    squads[idx].targetX = hillPos.x
                    squads[idx].targetY = max(180.0, hillPos.y - 210.0)
                case .rightWing:
                    if let raidPt = exposedSapperTarget, category == .cavalry {
                        squads[idx].formation = .wedgeCharge
                        squads[idx].order = .raidSupply
                        squads[idx].targetX = raidPt.x
                        squads[idx].targetY = raidPt.y
                    } else {
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .holdGround
                        squads[idx].targetX = hillPos.x
                        squads[idx].targetY = min(worldHeight - 180.0, hillPos.y + 210.0)
                    }
                case .siegeBattery:
                    squads[idx].formation = .echelonLine
                    squads[idx].order = .holdGround
                    squads[idx].targetX = hillPos.x - advanceSign * 55.0
                    squads[idx].targetY = hillPos.y
                case .rearReserve:
                    if commitReserve, criticalAiFrontIdx != -1 {
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .advance
                        squads[idx].targetX = squads[criticalAiFrontIdx].anchorX
                        squads[idx].targetY = squads[criticalAiFrontIdx].anchorY
                    } else {
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .holdGround
                        squads[idx].targetX = hillPos.x - advanceSign * 140.0
                        squads[idx].targetY = hillPos.y
                    }
                case .supplyEscort:
                    break
                }
                squads[idx].waypoints.removeAll(keepingCapacity: true)

            case .feignedRetreatAmbush:
                let trapPos = bestForestAmbushAnchor(
                    aiSide: aiSide,
                    terrainZones: terrainZones,
                    worldWidth: worldWidth,
                    worldHeight: worldHeight
                )
                let distOpponentToTrap = hypot(opponentMainX - trapPos.x, opponentMainY - trapPos.y)
                if distOpponentToTrap <= 320.0 {
                    // 敌军已踏入伏击袋：三面伏兵瞬间暴起合围！
                    feignedRetreatTriggeredOnce = true
                    squads[idx].formation = category == .ranged ? .echelonLine : .wedgeCharge
                    squads[idx].order = category == .ranged ? .holdGround : .pincerEncircle
                    squads[idx].targetX = opponentMainX
                    squads[idx].targetY = opponentMainY
                    squads[idx].waypoints.removeAll(keepingCapacity: true)
                } else {
                    switch role {
                    case .vanguardCenter:
                        squads[idx].formation = .echelonLine
                        squads[idx].order = .feignedRetreat
                        squads[idx].targetX = trapPos.x + advanceSign * 90.0
                        squads[idx].targetY = trapPos.y
                    case .leftWing:
                        squads[idx].formation = category == .ranged ? .echelonLine : .wedgeCharge
                        squads[idx].order = .ambushHide
                        squads[idx].targetX = trapPos.x
                        squads[idx].targetY = max(180.0, trapPos.y - 240.0)
                    case .rightWing:
                        squads[idx].formation = category == .ranged ? .echelonLine : .wedgeCharge
                        squads[idx].order = .ambushHide
                        squads[idx].targetX = trapPos.x
                        squads[idx].targetY = min(worldHeight - 180.0, trapPos.y + 240.0)
                    case .siegeBattery:
                        squads[idx].formation = .echelonLine
                        squads[idx].order = .holdGround
                        squads[idx].targetX = trapPos.x - advanceSign * 130.0
                        squads[idx].targetY = trapPos.y
                    case .rearReserve:
                        squads[idx].formation = .wedgeCharge
                        squads[idx].order = .ambushHide
                        squads[idx].targetX = trapPos.x - advanceSign * 80.0
                        squads[idx].targetY = trapPos.y
                    case .supplyEscort:
                        break
                    }
                }

            case .hammerAndAnvil, .reserveBreakthrough, .antiKiteEscort:
                switch role {
                case .vanguardCenter:
                    // 正面铁砧稳步压迫牵制玩家中军（熊族与狂战接敌近距转冲锋）
                    let distToCenter = hypot(squads[idx].anchorX - opponentMainX, squads[idx].anchorY - opponentMainY)
                    if (personality == .honorBerserkBear || personality == .zealotSwarm) && distToCenter < 240.0 {
                        squads[idx].formation = .wedgeCharge
                        squads[idx].order = .allOutCharge
                    } else {
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .advance
                    }
                    squads[idx].targetX = opponentMainX
                    squads[idx].targetY = opponentMainY
                    squads[idx].waypoints.removeAll(keepingCapacity: true)

                case .leftWing:
                    // 北走廊大弧线迂回（偏移 >= 220px）直扑敌后排或钳形合围
                    if let raidPt = exposedSapperTarget, category == .cavalry && personality == .nomadOpportunist {
                        squads[idx].formation = .wedgeCharge
                        squads[idx].order = .raidSupply
                        squads[idx].targetX = raidPt.x
                        squads[idx].targetY = raidPt.y
                        squads[idx].waypoints.removeAll(keepingCapacity: true)
                    } else {
                        let targetX = hasOpponentRanged ? opponentRangedX : (opponentMainX - advanceSign * 140.0)
                        let targetY = hasOpponentRanged ? opponentRangedY : opponentMainY
                        let northLaneY = min(420.0, max(200.0, targetY - 320.0))
                        squads[idx].formation = category == .cavalry ? .wedgeCharge : .phalanxRect
                        squads[idx].order = .pincerEncircle
                        if abs(squads[idx].anchorX - targetX) > 340.0 {
                            squads[idx].waypoints = [SquadWaypoint(x: (squads[idx].anchorX + targetX) * 0.5, y: northLaneY)]
                            squads[idx].targetX = targetX
                            squads[idx].targetY = targetY
                        } else {
                            squads[idx].waypoints.removeAll(keepingCapacity: true)
                            squads[idx].targetX = targetX
                            squads[idx].targetY = targetY
                        }
                    }

                case .rightWing:
                    // 南走廊大回环迂回或断粮奇袭
                    if let raidPt = exposedSapperTarget, category == .cavalry {
                        squads[idx].formation = .wedgeCharge
                        squads[idx].order = .raidSupply
                        squads[idx].targetX = raidPt.x
                        squads[idx].targetY = raidPt.y
                        squads[idx].waypoints.removeAll(keepingCapacity: true)
                    } else {
                        let targetX = hasOpponentRanged ? opponentRangedX : (opponentMainX - advanceSign * 140.0)
                        let targetY = hasOpponentRanged ? opponentRangedY : opponentMainY
                        let southLaneY = max(worldHeight - 420.0, min(worldHeight - 200.0, targetY + 320.0))
                        squads[idx].formation = category == .cavalry ? .wedgeCharge : .phalanxRect
                        squads[idx].order = .pincerEncircle
                        if abs(squads[idx].anchorX - targetX) > 340.0 {
                            squads[idx].waypoints = [SquadWaypoint(x: (squads[idx].anchorX + targetX) * 0.5, y: southLaneY)]
                            squads[idx].targetX = targetX
                            squads[idx].targetY = targetY
                        } else {
                            squads[idx].waypoints.removeAll(keepingCapacity: true)
                            squads[idx].targetX = targetX
                            squads[idx].targetY = targetY
                        }
                    }

                case .siegeBattery:
                    squads[idx].formation = .echelonLine
                    let idealStandOff = max(260.0, (unitStats?.attackRange ?? 380.0) * 0.82)
                    let desiredX = clamp(opponentMainX - advanceSign * idealStandOff, minVal: 220.0, maxVal: worldWidth - 220.0)
                    squads[idx].order = abs(squads[idx].anchorX - desiredX) > 90.0 ? .advance : .holdGround
                    squads[idx].targetX = desiredX
                    squads[idx].targetY = opponentMainY
                    squads[idx].waypoints.removeAll(keepingCapacity: true)

                case .rearReserve:
                    if commitReserve {
                        if lowestAiFrontMorale < 35.0, criticalAiFrontIdx != -1 {
                            // 己方侧翼濒溃：总预备队紧急顶上稳住阵脚
                            squads[idx].formation = .phalanxRect
                            squads[idx].order = .advance
                            squads[idx].targetX = squads[criticalAiFrontIdx].anchorX
                            squads[idx].targetY = squads[criticalAiFrontIdx].anchorY
                        } else if weakestOpponentSquadIdx != -1 {
                            // 敌军防线动摇：具装重骑/巨熊总预备队锥形冲锋一锤定音凿穿缺口
                            squads[idx].formation = .wedgeCharge
                            squads[idx].order = .allOutCharge
                            squads[idx].targetX = squads[weakestOpponentSquadIdx].anchorX
                            squads[idx].targetY = squads[weakestOpponentSquadIdx].anchorY
                        } else {
                            squads[idx].formation = .wedgeCharge
                            squads[idx].order = .allOutCharge
                            squads[idx].targetX = opponentMainX
                            squads[idx].targetY = opponentMainY
                        }
                    } else {
                        // 未到决胜时刻：扣留 24% 精锐总预备队于中军后方 280px 蓄势待发
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .holdGround
                        squads[idx].targetX = clamp(opponentMainX - advanceSign * 460.0, minVal: 320.0, maxVal: worldWidth - 320.0)
                        squads[idx].targetY = worldHeight * 0.50
                    }
                    squads[idx].waypoints.removeAll(keepingCapacity: true)

                case .supplyEscort:
                    break
                }
            }
        }
    }

    // MARK: - 攻城与守城三段式专项战术状态机

    private mutating func updateSiegeTactics(
        aiSide: BattleSide,
        aiIsAttacker: Bool,
        opponentMainX: Double,
        opponentMainY: Double,
        opponentRangedX: Double,
        opponentRangedY: Double,
        hasOpponentRanged: Bool,
        heroIsolated: Bool,
        opponentHero: HeroCommanderEntity,
        worldWidth: Double,
        worldHeight: Double,
        squads: inout [BattleSquadState],
        structures: [SiegeStructureEntity]
    ) {
        let defenderSide = aiIsAttacker ? aiSide.opponent : aiSide
        var mainGate: SiegeStructureEntity?
        var sideGate: SiegeStructureEntity?
        var anyWallBreached = false
        var aliveTowerCount = 0

        for st in structures where st.side == defenderSide {
            switch st.kind {
            case .mainGate:
                mainGate = st
                if st.isDestroyed { anyWallBreached = true }
            case .sideSallyGate:
                sideGate = st
            case .wallSegment:
                if st.isDestroyed { anyWallBreached = true }
            case .arrowTower:
                if !st.isDestroyed { aliveTowerCount += 1 }
            default:
                break
            }
        }

        let gateX = mainGate?.x ?? (defenderSide == .enemy ? worldWidth - 1150.0 : 1150.0)
        let gateY = mainGate?.y ?? (worldHeight * 0.50)
        let gateHpRatio = (mainGate.map { $0.hp / max(1.0, $0.maxHp) }) ?? 0.0

        if aiIsAttacker {
            // 统计攻方存活攻城重器数（若投石车全毁或苍狼无投石车，立即跳过炮火准备直接多点登城+巨斧破门，绝不隔墙卡死！）
            var aliveSiegeSquads = 0
            for sq in squads where sq.side == aiSide && sq.aliveCount > 0 && sq.corpsRole == .siegeBattery {
                if sq.primaryUnitType == .trebuchet || sq.primaryUnitType == .ballista {
                    aliveSiegeSquads += 1
                }
            }

            let phase: SiegeTacticalPhase
            var commitReserve = blackboard.reserveCommitted
            if anyWallBreached {
                phase = .attackerBreachExploit
                commitReserve = true
            } else if aliveSiegeSquads > 0 && aliveTowerCount > 0 && gateHpRatio > 0.65 {
                phase = .attackerArtilleryPrep
            } else {
                phase = .attackerMultiLadder
            }

            blackboard = TacticalBlackboardSummary(
                activeDoctrine: commitReserve ? .reserveBreakthrough : .hammerAndAnvil,
                siegePhase: phase,
                reserveCommitted: commitReserve,
                detectedPlayerHeroKiting: heroIsolated
            )

            let standOffSign = defenderSide == .enemy ? -1.0 : 1.0
            for idx in 0..<squads.count where squads[idx].side == aiSide && squads[idx].aliveCount > 0 && !squads[idx].isRouting {
                let role = squads[idx].corpsRole
                switch phase {
                case .attackerArtilleryPrep:
                    if role == .siegeBattery {
                        squads[idx].formation = .echelonLine
                        squads[idx].order = .holdGround
                        squads[idx].targetX = gateX + standOffSign * 640.0
                        squads[idx].targetY = gateY
                    } else if role == .vanguardCenter {
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .holdGround
                        squads[idx].targetX = gateX + standOffSign * 460.0
                        squads[idx].targetY = gateY
                    } else {
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .holdGround
                        squads[idx].targetX = gateX + standOffSign * 540.0
                        squads[idx].targetY = role == .leftWing ? 560.0 : (role == .rightWing ? worldHeight - 560.0 : gateY)
                    }

                case .attackerMultiLadder:
                    switch role {
                    case .vanguardCenter:
                        // 巨斧与刀盾顶箭雨猛劈正门
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .advance
                        squads[idx].targetX = gateX
                        squads[idx].targetY = gateY
                    case .leftWing:
                        // 北翼架云梯登城牵制城头火力
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .advance
                        squads[idx].targetX = gateX
                        squads[idx].targetY = max(380.0, gateY - 540.0)
                    case .rightWing:
                        // 南翼架云梯登城
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .advance
                        squads[idx].targetX = gateX
                        squads[idx].targetY = min(worldHeight - 380.0, gateY + 540.0)
                    case .siegeBattery:
                        squads[idx].formation = .echelonLine
                        squads[idx].order = .holdGround
                        squads[idx].targetX = gateX + standOffSign * 580.0
                        squads[idx].targetY = gateY
                    case .rearReserve, .supplyEscort:
                        squads[idx].formation = .phalanxRect
                        squads[idx].order = .holdGround
                        squads[idx].targetX = gateX + standOffSign * 420.0
                        squads[idx].targetY = gateY
                    }

                case .attackerBreachExploit:
                    let innerCampX = defenderSide == .enemy ? (worldWidth - 500.0) : 500.0
                    squads[idx].formation = role == .siegeBattery ? .echelonLine : .wedgeCharge
                    squads[idx].order = role == .siegeBattery ? .holdGround : .allOutCharge
                    if role != .siegeBattery && role != .supplyEscort {
                        squads[idx].waypoints = [SquadWaypoint(x: gateX, y: gateY)]
                        squads[idx].targetX = innerCampX
                        squads[idx].targetY = gateY
                    }

                default:
                    break
                }
            }
        } else {
            // AI 作为守城方三段式状态机
            let attackerNearWall = abs(opponentMainX - gateX) < 460.0
            let phase: SiegeTacticalPhase
            var commitReserve = blackboard.reserveCommitted

            if gateHpRatio < 0.30 || anyWallBreached {
                phase = .defenderGatePlugPhalanx
                commitReserve = true
            } else if attackerNearWall && hasOpponentRanged {
                phase = .defenderSallyDestroySiege
            } else {
                phase = .defenderWallFocusFire
            }

            blackboard = TacticalBlackboardSummary(
                activeDoctrine: .highGroundHedgehog,
                siegePhase: phase,
                reserveCommitted: commitReserve,
                detectedPlayerHeroKiting: heroIsolated
            )

            let insideSign = defenderSide == .enemy ? 1.0 : -1.0
            for idx in 0..<squads.count where squads[idx].side == aiSide && squads[idx].aliveCount > 0 && !squads[idx].isRouting {
                let role = squads[idx].corpsRole
                let cat = UnitConfig.stats(for: squads[idx].primaryUnitType)?.category ?? .infantry

                if phase == .defenderSallyDestroySiege && role == .rightWing && cat == .cavalry {
                    // 从侧门派出 1 队游骑绕后奇袭烧毁攻方投石车
                    let sallyY = sideGate?.y ?? (worldHeight - 360.0)
                    squads[idx].formation = .wedgeCharge
                    squads[idx].order = .raidSupply
                    squads[idx].waypoints = [SquadWaypoint(x: gateX, y: sallyY)]
                    squads[idx].targetX = opponentRangedX
                    squads[idx].targetY = opponentRangedY
                    continue
                }

                if phase == .defenderGatePlugPhalanx && (role == .vanguardCenter || role == .rearReserve) {
                    // 城门耐久 <30% 或已破：长枪与重步在门洞内结圆阵/方阵死堵缺口
                    squads[idx].formation = role == .rearReserve ? .circleDefense : .phalanxRect
                    squads[idx].order = .holdGround
                    squads[idx].targetX = gateX + insideSign * 85.0
                    squads[idx].targetY = gateY
                    squads[idx].waypoints.removeAll(keepingCapacity: true)
                    continue
                }

                // 城头弓弩集火推云梯工兵与无盾巨斧
                if cat == .ranged || role == .siegeBattery {
                    squads[idx].formation = .echelonLine
                    squads[idx].order = .holdGround
                    squads[idx].targetX = gateX + insideSign * 35.0
                    squads[idx].targetY = role == .leftWing ? (gateY - 320.0) : gateY
                } else {
                    squads[idx].formation = .phalanxRect
                    squads[idx].order = .holdGround
                    squads[idx].targetX = gateX + insideSign * 130.0
                    squads[idx].targetY = gateY
                }
            }
        }
    }

    // MARK: - 战场环境特征提取辅助函数

    private func hasHighGroundOrBridge(in zones: [TerrainZoneRect]) -> Bool {
        for z in zones where z.terrain == .highGround || z.terrain == .bridgePass {
            return true
        }
        return false
    }

    private func bestDefensiveAnchor(
        aiSide: BattleSide,
        terrainZones: [TerrainZoneRect],
        worldWidth: Double,
        worldHeight: Double
    ) -> (x: Double, y: Double) {
        let homeX = aiSide == .enemy ? (worldWidth * 0.72) : (worldWidth * 0.28)
        var best = (x: homeX, y: worldHeight * 0.50)
        var bestDist = Double.greatestFiniteMagnitude
        for z in terrainZones where z.terrain == .highGround || z.terrain == .bridgePass {
            let cx = (z.minX + z.maxX) * 0.5
            let cy = (z.minY + z.maxY) * 0.5
            let d = abs(cx - homeX)
            if d < bestDist {
                bestDist = d
                best = (cx, cy)
            }
        }
        return best
    }

    private func bestForestAmbushAnchor(
        aiSide: BattleSide,
        terrainZones: [TerrainZoneRect],
        worldWidth: Double,
        worldHeight: Double
    ) -> (x: Double, y: Double) {
        let homeX = aiSide == .enemy ? (worldWidth * 0.68) : (worldWidth * 0.32)
        for z in terrainZones where z.terrain == .denseForest {
            let cx = (z.minX + z.maxX) * 0.5
            let cy = (z.minY + z.maxY) * 0.5
            if (aiSide == .enemy && cx >= worldWidth * 0.42) || (aiSide == .player && cx <= worldWidth * 0.58) {
                return (cx, cy)
            }
        }
        return (homeX, worldHeight * 0.32)
    }

    private func findExposedEnemySapperPosition(
        opponentSide: BattleSide,
        opponentBellActive: Bool,
        soldiers: [SoldierEntity],
        worldWidth: Double
    ) -> (x: Double, y: Double)? {
        guard !opponentBellActive else { return nil }
        let campX = opponentSide == .player ? 500.0 : (worldWidth - 500.0)
        for unit in soldiers where unit.isActive && unit.hp > 0.0 && unit.side == opponentSide && unit.unitType == .sapper {
            // 仅挑远离本阵箭孔超过 300px 的外派采集工兵突袭
            if abs(unit.x - campX) > 300.0 {
                return (unit.x, unit.y)
            }
        }
        return nil
    }

    @inline(__always)
    private func clamp(_ v: Double, minVal: Double, maxVal: Double) -> Double {
        max(minVal, min(maxVal, v))
    }
}
