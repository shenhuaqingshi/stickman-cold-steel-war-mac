import Foundation

/// 冷兵器真实物理伤害、双曲护甲、八象限合围、士气迟滞防抖、断粮递进与阵型槽位纯函数计算器
/// 无状态 `Sendable` 命名空间，所有数学公式 100% 对齐 DESIGN.md 第 3/4/7/10 节与 GameConstants.swift，支持直接单元测试断言。

/// 受击方位扇区分类
public enum HitDirectionZone: String, Sendable, Codable, Hashable {
    case front = "front" // 正面受击 (<= 60°)
    case flank = "flank" // 侧翼打击 (60° ~ 135°，+25% 伤害，盾防减半，士气打击 ×1.5)
    case rear = "rear"   // 背击突袭 (> 135°，+45% 伤害，盾防与架枪归零，士气打击 ×2.0)
}

/// 单次伤害结算输入上下文（纯值类型）
public struct DamageCalculationInput: Sendable, Equatable {
    public var baseAttack: Double
    public var attackerArmorPenetration: Double
    public var attackerChargeMultiplier: Double
    public var attackerAntiCavMultiplier: Double
    public var attackerFaction: FactionId
    public var attackerTerrain: TerrainType
    public var attackerWeather: WeatherType
    public var attackerMoraleBracket: MoraleBracket
    public var attackerRationStage: BattlefieldRationStage
    public var attackerFormation: FormationType
    public var attackerFormationBonusActive: Bool
    public var attackerIsCharging: Bool
    public var attackerIsBraced: Bool
    public var attackerIsRouting: Bool
    public var attackerCamelSpooked: Bool
    public var attackerBreaksStealth: Bool
    public var isMelee: Bool
    public var isExplosiveArea: Bool

    public var targetBaseArmor: Double
    public var targetShieldRangedBlock: Double
    public var targetCategory: UnitCategory
    public var targetFaction: FactionId
    public var targetTerrain: TerrainType
    public var targetMoraleBracket: MoraleBracket
    public var targetFormation: FormationType
    public var targetFormationBonusActive: Bool
    public var targetEncirclement: EncirclementState
    public var targetIsChargingCavalry: Bool
    public var targetIsBracedPolearm: Bool
    public var targetIsReloadingBackShield: Bool
    /// 目标所属分队涉水成员占比 (0.0 ~ 1.0)，介于 0.30 ~ 0.80 时触发半渡而击 1.20x 易伤
    public var targetSquadRiverWadingRatio: Double
    /// 攻击来源相对于受击者的入射方向角（由受击者指向攻击者的向量与受击者朝向的夹角，或显式方位）
    public var incomingAngleDifferenceRadians: Double

    public init(
        baseAttack: Double,
        attackerArmorPenetration: Double,
        attackerChargeMultiplier: Double = 1.0,
        attackerAntiCavMultiplier: Double = 1.0,
        attackerFaction: FactionId = .yanlong,
        attackerTerrain: TerrainType = .plain,
        attackerWeather: WeatherType = .clearDay,
        attackerMoraleBracket: MoraleBracket = .steady,
        attackerRationStage: BattlefieldRationStage = .abundant,
        attackerFormation: FormationType = .phalanxRect,
        attackerFormationBonusActive: Bool = true,
        attackerIsCharging: Bool = false,
        attackerIsBraced: Bool = false,
        attackerIsRouting: Bool = false,
        attackerCamelSpooked: Bool = false,
        attackerBreaksStealth: Bool = false,
        isMelee: Bool = true,
        isExplosiveArea: Bool = false,
        targetBaseArmor: Double,
        targetShieldRangedBlock: Double = 0.0,
        targetCategory: UnitCategory = .infantry,
        targetFaction: FactionId = .canglang,
        targetTerrain: TerrainType = .plain,
        targetMoraleBracket: MoraleBracket = .steady,
        targetFormation: FormationType = .phalanxRect,
        targetFormationBonusActive: Bool = true,
        targetEncirclement: EncirclementState = .clear,
        targetIsChargingCavalry: Bool = false,
        targetIsBracedPolearm: Bool = false,
        targetIsReloadingBackShield: Bool = false,
        targetSquadRiverWadingRatio: Double = 0.0,
        incomingAngleDifferenceRadians: Double = 0.0
    ) {
        self.baseAttack = baseAttack
        self.attackerArmorPenetration = attackerArmorPenetration
        self.attackerChargeMultiplier = attackerChargeMultiplier
        self.attackerAntiCavMultiplier = attackerAntiCavMultiplier
        self.attackerFaction = attackerFaction
        self.attackerTerrain = attackerTerrain
        self.attackerWeather = attackerWeather
        self.attackerMoraleBracket = attackerMoraleBracket
        self.attackerRationStage = attackerRationStage
        self.attackerFormation = attackerFormation
        self.attackerFormationBonusActive = attackerFormationBonusActive
        self.attackerIsCharging = attackerIsCharging
        self.attackerIsBraced = attackerIsBraced
        self.attackerIsRouting = attackerIsRouting
        self.attackerCamelSpooked = attackerCamelSpooked
        self.attackerBreaksStealth = attackerBreaksStealth
        self.isMelee = isMelee
        self.isExplosiveArea = isExplosiveArea
        self.targetBaseArmor = targetBaseArmor
        self.targetShieldRangedBlock = targetShieldRangedBlock
        self.targetCategory = targetCategory
        self.targetFaction = targetFaction
        self.targetTerrain = targetTerrain
        self.targetMoraleBracket = targetMoraleBracket
        self.targetFormation = targetFormation
        self.targetFormationBonusActive = targetFormationBonusActive
        self.targetEncirclement = targetEncirclement
        self.targetIsChargingCavalry = targetIsChargingCavalry
        self.targetIsBracedPolearm = targetIsBracedPolearm
        self.targetIsReloadingBackShield = targetIsReloadingBackShield
        self.targetSquadRiverWadingRatio = targetSquadRiverWadingRatio
        self.incomingAngleDifferenceRadians = incomingAngleDifferenceRadians
    }
}

/// 单次伤害结算输出明细
public struct DamageCalculationOutput: Sendable, Equatable {
    public let finalDamage: Double
    public let effectiveArmor: Double
    public let armorMitigationRate: Double
    public let directionZone: HitDirectionZone
    public let triggeredCharge: Bool
    public let triggeredBracedAntiCav: Bool
    public let triggeredHalfFord: Bool
    public let shieldBlocked: Bool
    public let moraleShockToTarget: Double
}

/// 八象限受围判定结果
public struct EncirclementEvaluationResult: Sendable, Equatable {
    public let state: EncirclementState
    public let occupiedOctantMask: UInt8
    public let occupiedOctantCount: Int
    public let moraleDrainPerSec: Double
    public let moraleCapOverride: Double?
}

public enum DamageMoraleCalculator: Sendable {
    // MARK: - 一、双曲护甲与角度基础纯函数

    /// 将任意角度归一化至 [-π, π]
    @inline(__always)
    public static func normalizeAngle(_ radians: Double) -> Double {
        var a = radians.truncatingRemainder(dividingBy: 2.0 * Double.pi)
        if a > Double.pi {
            a -= 2.0 * Double.pi
        } else if a < -Double.pi {
            a += 2.0 * Double.pi
        }
        return a
    }

    /// 计算两个朝向角之间的绝对夹角 [0, π]
    @inline(__always)
    public static func absoluteAngleBetween(_ angleA: Double, _ angleB: Double) -> Double {
        abs(normalizeAngle(angleA - angleB))
    }

    /// 计算攻击来源相对于目标朝向的入射夹角 [0, π]（0 代表正迎面来袭，π 代表正背后突袭）
    @inline(__always)
    public static func incomingAttackAngle(
        targetX: Double,
        targetY: Double,
        targetFacingRadians: Double,
        attackerX: Double,
        attackerY: Double
    ) -> Double {
        let toAttacker = atan2(attackerY - targetY, attackerX - targetX)
        return absoluteAngleBetween(targetFacingRadians, toAttacker)
    }

    /// 判定受击方位（圆阵有效时 360° 全向视为正面防御；桥梁窄口地形同样免除侧背包抄）
    public static func classifyHitDirection(
        incomingAngleRadians: Double,
        targetFormation: FormationType,
        targetFormationBonusActive: Bool,
        targetTerrain: TerrainType = .plain
    ) -> HitDirectionZone {
        if (targetFormation == .circleDefense && targetFormationBonusActive) || targetTerrain == .bridgePass {
            return .front
        }
        let absAngle = abs(incomingAngleRadians)
        let sixtyDeg = Double.pi / 3.0
        let oneThirtyFiveDeg = 3.0 * Double.pi / 4.0
        if absAngle <= sixtyDeg {
            return .front
        } else if absAngle <= oneThirtyFiveDeg {
            return .flank
        } else {
            return .rear
        }
    }

    /// 有效护甲公式：A_eff = max(0, A_target * (1 - Pen))
    @inline(__always)
    public static func computeEffectiveArmor(targetArmor: Double, armorPenetration: Double) -> Double {
        let clampedPen = min(1.0, max(0.0, armorPenetration))
        return max(0.0, targetArmor * (1.0 - clampedPen))
    }

    /// 双曲护甲减伤率：Mitigation = A_eff / (A_eff + 50)
    @inline(__always)
    public static func computeArmorMitigation(effectiveArmor: Double) -> Double {
        guard effectiveArmor > 0.0 else { return 0.0 }
        return effectiveArmor / (effectiveArmor + GameConstants.armorHyperbolicConstant)
    }

    // MARK: - 二、完整冷兵器物理伤害结算

    public static func calculateDamage(_ input: DamageCalculationInput) -> DamageCalculationOutput {
        let direction = classifyHitDirection(
            incomingAngleRadians: input.incomingAngleDifferenceRadians,
            targetFormation: input.targetFormation,
            targetFormationBonusActive: input.targetFormationBonusActive,
            targetTerrain: input.targetTerrain
        )

        // 1. 方位倍率与盾防有效系数
        let directionalMult: Double
        let shieldFactor: Double
        let dirMoraleMult: Double
        switch direction {
        case .front:
            directionalMult = 1.0
            shieldFactor = 1.0
            dirMoraleMult = 1.0
        case .flank:
            directionalMult = GameConstants.flankDamageMultiplier
            shieldFactor = 0.5
            dirMoraleMult = 1.5
        case .rear:
            directionalMult = GameConstants.rearDamageMultiplier
            shieldFactor = 0.0
            dirMoraleMult = 2.0
        }

        // 2. 反骑架枪倍率与 +30% 动能破甲判定（非溃逃、架枪态迎击冲锋骑兵，背袭时架枪归零失效）
        let bracedAntiCavTriggered = input.isMelee
            && direction != .rear
            && !input.attackerIsRouting
            && input.attackerIsBraced
            && input.attackerAntiCavMultiplier > 1.0
            && input.targetCategory == .cavalry
            && input.targetIsChargingCavalry

        let mAntiCav: Double
        var effectivePen = input.attackerArmorPenetration
        if bracedAntiCavTriggered {
            mAntiCav = input.attackerAntiCavMultiplier
            effectivePen = min(0.95, effectivePen + GameConstants.bracedAntiCavBonusPenetration)
        } else if input.isMelee && direction != .rear && input.targetCategory == .cavalry && input.attackerAntiCavMultiplier > 1.0 {
            // 非冲锋缠斗态仅保留基础长柄克制余威，核心爆发留给架枪迎冲锋
            mAntiCav = 1.0 + (input.attackerAntiCavMultiplier - 1.0) * 0.30
        } else {
            mAntiCav = 1.0
        }

        // 3. 骑兵/突击兵 2.5s 冲锋首击倍率（若正面撞上已架枪长枪方阵，冲锋动量被强制清零停马；侧背击则完整生效！）
        let blockedByBracedPikeWall = direction == .front
            && input.targetCategory == .polearm
            && (input.targetIsBracedPolearm || input.targetFormationBonusActive)
        let chargeTriggered = input.isMelee
            && input.attackerIsCharging
            && input.attackerChargeMultiplier > 1.0
            && !blockedByBracedPikeWall

        var mCharge = 1.0
        if chargeTriggered {
            mCharge = input.attackerChargeMultiplier
            if input.attackerFaction == .xuanjia {
                mCharge *= 1.30
            }
            if input.attackerFormation == .wedgeCharge && input.attackerFormationBonusActive {
                mCharge *= 1.25
            }
            if input.attackerTerrain == .highGround && input.targetTerrain != .highGround {
                mCharge *= 1.15
            }
            if input.attackerCamelSpooked {
                mCharge *= 0.75
            }
        }

        // 4. 目标护甲修正（阵型 + 罗马龟甲阵 + 势力 + 涉水 + 士气动摇）
        var adjustedArmor = input.targetBaseArmor
        if input.targetFormationBonusActive {
            if input.targetFormation == .testudo && direction != .rear {
                adjustedArmor *= 1.35
            } else if input.targetFormation == .phalanxRect && input.targetEncirclement != .pincered {
                adjustedArmor *= 1.20
            } else if input.targetFormation == .wedgeCharge && input.isMelee {
                adjustedArmor *= 0.90
            }
        }
        if input.targetTerrain == .riverFord {
            adjustedArmor *= 0.85
        }
        if input.targetMoraleBracket == .wavering {
            adjustedArmor *= 0.85
        } else if input.targetMoraleBracket == .routing {
            adjustedArmor *= 0.70
        }

        let effArmor = computeEffectiveArmor(targetArmor: adjustedArmor, armorPenetration: effectivePen)
        let mitigation = computeArmorMitigation(effectiveArmor: effArmor)

        // 5. 远程盾牌格挡、罗马龟甲阵覆顶巨盾与铁鹰换弹背盾机制
        var mShield = 1.0
        var shieldBlocked = false
        if !input.isMelee && !input.isExplosiveArea {
            var blockRate = input.targetShieldRangedBlock * shieldFactor
            if input.targetFormation == .testudo && input.targetFormationBonusActive && direction != .rear {
                // 罗马龟甲阵：前排与顶层大盾严密咬合，箭矢与弩矢减伤高达 85%！
                blockRate = max(blockRate, 0.85)
            }
            if input.targetIsReloadingBackShield {
                blockRate = max(blockRate, 0.60)
            }
            blockRate = min(0.88, max(0.0, blockRate))
            if blockRate > 0.05 {
                shieldBlocked = true
            }
            mShield = 1.0 - blockRate
        }

        // 6. 地形、天时、势力与士气/断粮修正
        var mTerrain = 1.0
        if input.isMelee && input.attackerTerrain == .highGround && input.targetTerrain != .highGround {
            mTerrain *= 1.12
        }
        if input.attackerFaction == .tieying && (input.attackerTerrain == .highGround || input.attackerTerrain == .fortWall) {
            mTerrain *= 1.15
        }
        if input.isMelee && input.attackerFaction == .shuangyuan
            && (input.attackerTerrain == .snowfield || input.attackerWeather == .blizzard) {
            mTerrain *= 1.10
        }
        if input.attackerFaction == .xueyue && input.attackerWeather == .night {
            mTerrain *= 1.15
        }
        if !input.isMelee && input.targetTerrain == .fortWall {
            // 城墙/工事掩体远程减伤 65%
            mTerrain *= 0.35
        }
        if input.isExplosiveArea && input.targetFormation == .echelonLine && input.targetFormationBonusActive {
            // 雁行阵受范围爆炸伤害 -35%
            mTerrain *= 0.65
        }
        if input.isExplosiveArea && input.attackerWeather == .rainMud {
            // 暴雨泥泞下火雷引燃效果减半
            mTerrain *= 0.75
        }

        var mMorale: Double
        switch input.attackerMoraleBracket {
        case .high:
            mMorale = 1.12
        case .steady:
            mMorale = 1.00
        case .wavering:
            mMorale = 0.80
        case .routing:
            mMorale = 0.50
        }
        if input.attackerRationStage == .starving {
            mMorale *= 0.75
        }

        // 7. 雾林影袭破隐 180% 暴击与渡河 30%~80% 半渡而击 1.20x 易伤
        let stealthMult = input.attackerBreaksStealth ? 1.80 : 1.0
        let isHalfFord = input.targetSquadRiverWadingRatio >= 0.30 && input.targetSquadRiverWadingRatio <= 0.80
        let halfFordMult = isHalfFord ? GameConstants.halfFordVulnerabilityMultiplier : 1.0

        let rawDamage = input.baseAttack
            * mCharge
            * mAntiCav
            * directionalMult
            * mTerrain
            * mMorale
            * mShield
            * stealthMult
            * halfFordMult
            * (1.0 - mitigation)

        let finalDamage = max(GameConstants.minimumHitDamage, rawDamage)
        let baseMoraleHit = min(4.5, (finalDamage / 65.0)) * dirMoraleMult * (mCharge > 1.3 ? 1.35 : 1.0)

        return DamageCalculationOutput(
            finalDamage: finalDamage,
            effectiveArmor: effArmor,
            armorMitigationRate: mitigation,
            directionZone: direction,
            triggeredCharge: chargeTriggered,
            triggeredBracedAntiCav: bracedAntiCavTriggered,
            triggeredHalfFord: isHalfFord,
            shieldBlocked: shieldBlocked,
            moraleShockToTarget: baseMoraleHit
        )
    }

    // MARK: - 三、八象限包抄、钳形夹击与五扇区铁桶合围评估

    /// 将相对角度映射至 0~7 八个 45° 方位扇区（0 为正前方 [-22.5°, +22.5°)）
    @inline(__always)
    public static func octantIndex(forRelativeAngle relAngle: Double) -> Int {
        let shifted = normalizeAngle(relAngle) + (Double.pi / 8.0)
        let positive = shifted < 0.0 ? (shifted + 2.0 * Double.pi) : shifted
        let idx = Int(floor(positive / (Double.pi / 4.0))) % 8
        return max(0, min(7, idx))
    }

    /// 评估军团周围 160px 交战圈八象限受围状态与每秒士气流失
    public static func evaluateEncirclement(
        occupiedOctantMask: UInt8,
        distinctEnemySquadCount: Int,
        retreatOctantBlocked: Bool,
        formation: FormationType,
        formationBonusActive: Bool,
        terrain: TerrainType
    ) -> EncirclementEvaluationResult {
        // 桥梁/窄关免除被包抄侧击
        if terrain == .bridgePass {
            return EncirclementEvaluationResult(
                state: .clear,
                occupiedOctantMask: occupiedOctantMask,
                occupiedOctantCount: occupiedOctantMask.nonzeroBitCount,
                moraleDrainPerSec: 0.0,
                moraleCapOverride: nil
            )
        }

        let count = occupiedOctantMask.nonzeroBitCount
        let isCircleActive = formation == .circleDefense && formationBonusActive

        // 1. 铁桶合围（>= 5 个扇区受敌且退往本阵扇区被封堵）
        if count >= GameConstants.encirclementMinOctants && retreatOctantBlocked {
            let drain = isCircleActive
                ? (GameConstants.encirclementMoraleDrainPerSec * 0.5)
                : GameConstants.encirclementMoraleDrainPerSec
            return EncirclementEvaluationResult(
                state: .encircled,
                occupiedOctantMask: occupiedOctantMask,
                occupiedOctantCount: count,
                moraleDrainPerSec: drain,
                moraleCapOverride: 45.0
            )
        }

        // 2. 钳形夹击：至少 2 个方向互成钝角 (>= 120°，即八象限圆周步距 >= 3，3 * 45° = 135°)，且至少含 1 个侧后非正面扇区
        if count >= 2 && distinctEnemySquadCount >= 2 {
            let nonFrontalMask: UInt8 = 0b1111_1110 // 扇区 1~7 均为非正迎面扇区
            var hasObtusePair = false
            if (occupiedOctantMask & nonFrontalMask) != 0 {
                for a in 0..<8 where (occupiedOctantMask & (1 << a)) != 0 {
                    for b in (a + 1)..<8 where (occupiedOctantMask & (1 << b)) != 0 {
                        let diff = b - a
                        let circularSteps = min(diff, 8 - diff)
                        if circularSteps >= 3 {
                            hasObtusePair = true
                            break
                        }
                    }
                    if hasObtusePair { break }
                }
            }
            if hasObtusePair {
                let drain = isCircleActive ? 0.0 : GameConstants.pincerMoraleDrainPerSec
                return EncirclementEvaluationResult(
                    state: .pincered,
                    occupiedOctantMask: occupiedOctantMask,
                    occupiedOctantCount: count,
                    moraleDrainPerSec: drain,
                    moraleCapOverride: nil
                )
            }
        }

        // 3. 单侧翼或背后受敌（扇区 2, 3, 4, 5, 6）
        let flankRearMask: UInt8 = (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6)
        if (occupiedOctantMask & flankRearMask) != 0 && !isCircleActive {
            return EncirclementEvaluationResult(
                state: .flanked,
                occupiedOctantMask: occupiedOctantMask,
                occupiedOctantCount: count,
                moraleDrainPerSec: 0.6,
                moraleCapOverride: nil
            )
        }

        return EncirclementEvaluationResult(
            state: .clear,
            occupiedOctantMask: occupiedOctantMask,
            occupiedOctantCount: count,
            moraleDrainPerSec: 0.0,
            moraleCapOverride: nil
        )
    }

    // MARK: - 四、士气迟滞防抖状态机（<20 溃逃，须脱离接触回升 >=32 或战吼唤醒方重整）

    public static func updateMoraleAndBracket(
        currentMorale: Double,
        wasRouting: Bool,
        moraleDelta: Double,
        commanderRecoveringInCamp: Bool,
        encirclementCap: Double?,
        supplyCap: Double,
        isFearlessBerserker: Bool,
        inCloseEnemyContact: Bool,
        forceWarCryRally: Bool = false
    ) -> (morale: Double, bracket: MoraleBracket, isRouting: Bool) {
        var ceiling = min(GameConstants.moraleMax, supplyCap)
        if commanderRecoveringInCamp {
            ceiling = min(ceiling, GameConstants.heroDownMoraleCap)
        }
        if let encCap = encirclementCap {
            ceiling = min(ceiling, encCap)
        }

        var nextMorale = min(ceiling, max(0.0, currentMorale + moraleDelta))
        if isFearlessBerserker {
            nextMorale = max(50.0, nextMorale)
            let bracket: MoraleBracket = nextMorale >= GameConstants.moraleHighThreshold ? .high : .steady
            return (nextMorale, bracket, false)
        }

        var nextRouting = wasRouting
        if wasRouting {
            if forceWarCryRally && nextMorale >= GameConstants.moraleRoutThreshold {
                nextRouting = false
            } else if nextMorale >= GameConstants.moraleRallyThreshold && !inCloseEnemyContact {
                nextRouting = false
            }
        } else {
            if nextMorale < GameConstants.moraleRoutThreshold {
                nextRouting = true
            }
        }

        let bracket: MoraleBracket
        if nextRouting {
            bracket = .routing
        } else if nextMorale < GameConstants.moraleWaveringThreshold {
            bracket = .wavering
        } else if nextMorale >= GameConstants.moraleHighThreshold {
            bracket = .high
        } else {
            bracket = .steady
        }
        return (nextMorale, bracket, nextRouting)
    }

    // MARK: - 五、断粮三级递进状态与地形/天气机动修正

    /// 根据当前余粮、每秒总耗粮与已断粮秒数判定断粮阶段及惩罚参数
    public static func evaluateRationStage(
        remainingGrain: Double,
        upkeepPerSec: Double,
        zeroGrainElapsedSec: Double
    ) -> (stage: BattlefieldRationStage, moraleDrainPerSec: Double, speedMultiplier: Double) {
        if remainingGrain > 0.0 {
            let safeUpkeep = max(0.01, upkeepPerSec)
            let runwaySec = remainingGrain / safeUpkeep
            if runwaySec < GameConstants.rationWarningSeconds {
                return (.warning, 0.0, 1.0)
            }
            return (.abundant, 0.0, 1.0)
        }
        if zeroGrainElapsedSec <= GameConstants.starvationSevereSeconds {
            // 断粮 0~30s 饥饿期：停止自然回士气、每秒 -0.8、移速 -12%
            return (.hungry, 0.8, 0.88)
        } else {
            // 断粮 >30s 饥溃期：每秒 -1.8、攻击 -25%（在伤害公式中结算）、移速 -15%
            return (.starving, 1.8, 0.85)
        }
    }

    /// 计算士兵在当前地形、天气、阵型、势力与状态下的实际最大移速
    public static func effectiveUnitMoveSpeed(
        baseMoveSpeed: Double,
        category: UnitCategory,
        armor: Double,
        faction: FactionId,
        terrain: TerrainType,
        weather: WeatherType,
        formation: FormationType,
        formationBonusActive: Bool,
        moraleBracket: MoraleBracket,
        rationStage: BattlefieldRationStage,
        warCryActive: Bool,
        bloodMoonFervorActive: Bool,
        poisonSlowActive: Bool,
        camelSpooked: Bool
    ) -> Double {
        var speed = baseMoveSpeed

        // 势力全局移速法则
        if faction == .canglang && category == .cavalry {
            speed *= 1.12
        } else if faction == .yanlong && armor >= 40.0 {
            speed *= 0.95
        }

        // 阵型移速修正
        if formationBonusActive {
            switch formation {
            case .phalanxRect:
                speed *= 0.85
            case .echelonLine:
                break
            case .wedgeCharge:
                speed *= 1.08
            case .circleDefense:
                speed *= 0.12
            case .testudo:
                speed *= 0.68
            }
        }

        // 地形移速修正
        switch terrain {
        case .plain, .bridgePass, .fortWall:
            break
        case .highGround:
            speed *= 0.92
        case .riverFord:
            if category == .cavalry {
                speed *= (faction == .xuanjia ? 0.48 : 0.55)
            } else {
                speed *= 0.60
            }
        case .denseForest:
            if faction == .wulin {
                speed *= 1.20
            } else if category == .cavalry {
                speed *= 0.65
            } else {
                speed *= 0.75
            }
        case .desertDune:
            if faction != .shamo {
                if category == .cavalry {
                    speed *= 0.90
                } else if armor >= 40.0 {
                    speed *= 0.85
                }
            }
        case .snowfield:
            if faction != .shuangyuan {
                speed *= 0.85
            }
        }

        // 天气移速修正
        switch weather {
        case .clearDay, .heavyFog, .night:
            break
        case .rainMud:
            if category == .cavalry && armor >= 40.0 {
                speed *= (faction == .xuanjia ? 0.65 : 0.70)
            } else {
                speed *= 0.90
            }
        case .blizzard:
            if faction != .shuangyuan {
                speed *= 0.85
            }
        }

        // 断粮、士气与增益/减益
        if rationStage == .hungry {
            speed *= (faction == .xuanjia && category == .cavalry) ? 0.65 : 0.88
        } else if rationStage == .starving {
            speed *= (faction == .xuanjia && category == .cavalry) ? 0.62 : 0.85
        }

        if moraleBracket == .high {
            speed *= 1.06
        } else if moraleBracket == .routing {
            speed *= 1.15
        }

        if warCryActive {
            speed *= 1.15
        }
        if bloodMoonFervorActive && faction == .xueyue {
            speed *= 1.20
        }
        if poisonSlowActive {
            speed *= 0.65
        }
        if camelSpooked && category == .cavalry {
            speed *= 0.75
        }

        return max(8.0, speed)
    }

    // MARK: - 六、四种经典阵型弹簧槽位局部坐标生成（局部 X 指向正面朝向，局部 Y 指向侧翼）

    public static func computeFormationSlotOffset(
        slotIndex: Int,
        totalSlots: Int,
        formation: FormationType,
        spacing: Double = 20.0,
        lineSpreadMultiplier: Double = 1.0
    ) -> (forwardX: Double, lateralY: Double) {
        let count = max(1, totalSlots)
        let clampedSpread = max(0.55, min(2.2, lineSpreadMultiplier))
        switch formation {
        case .phalanxRect:
            // 密集矩形（支持右键拉宽或收窄纵深）
            let baseCols = Double(max(3, min(12, Int(ceil(sqrt(Double(count) * 1.6))))))
            let cols = max(2, min(count, Int((baseCols * clampedSpread).rounded())))
            let rank = slotIndex / cols
            let file = slotIndex % cols
            let totalRanks = Int(ceil(Double(count) / Double(cols)))
            let forward = (Double(totalRanks - 1) * 0.5 - Double(rank)) * (spacing * 0.92)
            let lateral = (Double(file) - Double(cols - 1) * 0.5) * (spacing * 0.90)
            return (forward, lateral)

        case .testudo:
            // 罗马龟甲重盾阵：肩并肩严丝合缝紧凑重盾方匣
            let baseCols = Double(max(3, min(8, Int(ceil(sqrt(Double(count) * 1.25))))))
            let cols = max(2, min(count, Int((baseCols * clampedSpread).rounded())))
            let rank = slotIndex / cols
            let file = slotIndex % cols
            let totalRanks = Int(ceil(Double(count) / Double(cols)))
            let forward = (Double(totalRanks - 1) * 0.5 - Double(rank)) * (spacing * 0.72)
            let lateral = (Double(file) - Double(cols - 1) * 0.5) * (spacing * 0.72)
            return (forward, lateral)

        case .echelonLine:
            // 宽幅双排微弧线展开，无后排遮挡
            let cols = max(3, min(count, Int((ceil(Double(count) / 2.0) * clampedSpread).rounded())))
            let rank = slotIndex / cols
            let file = slotIndex % cols
            let normLateral = cols > 1 ? (Double(file) - Double(cols - 1) * 0.5) : 0.0
            let arcCurve = -abs(normLateral) * 2.2
            let forward = (0.5 - Double(rank)) * (spacing * 1.05) + arcCurve
            let lateral = normLateral * (spacing * 1.18)
            return (forward, lateral)

        case .wedgeCharge:
            // 楔形三角箭头：第 0 排 1 人居尖端，向后每排递增 2 人
            var remaining = slotIndex
            var row = 0
            var rowCap = 1
            while remaining >= rowCap {
                remaining -= rowCap
                row += 1
                rowCap += 2
            }
            let forward = (1.5 - Double(row)) * (spacing * 0.95)
            let lateral = (Double(remaining) - Double(rowCap - 1) * 0.5) * (spacing * 0.95)
            return (forward, lateral)

        case .circleDefense:
            // 环形外向防御阵
            if count == 1 {
                return (0.0, 0.0)
            }
            let radius = max(24.0, Double(count) * spacing / (2.0 * Double.pi) * 0.95)
            let angle = (Double(slotIndex) / Double(count)) * 2.0 * Double.pi
            return (cos(angle) * radius, sin(angle) * radius)
        }
    }
}
