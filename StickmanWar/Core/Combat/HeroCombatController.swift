import Foundation

/// 主帅英雄实体与亲自上阵战斗状态机控制器（纯值类型 Sendable，零 UI/SpriteKit 依赖）
/// 严格兑现 DESIGN.md 第五节与 10.2 节：
/// - 统帅佩刀（0.75s 120° 扇形斩 3 人 + 举盾减伤 80% + 0.25s 精准弹反窗口震晕 1.5s）
/// - 破阵大枪（1.05s 68px 直线穿透 2 人 + 55% 破甲 + 2.2x 反骑挑落）
/// - 百石硬弓（0.9s 蓄力 460px 重箭贯穿 2 人 + 24 支箭袋上限 + 大营/辎重补箭 + 脱战 2.5s 寻回 1 支）
/// - 三大主动战技（破阵突击 CD 10s、铁壁横戈 CD 8s、三军战吼 CD 22s 唤醒溃军）
/// - 两段式【落马重伤（全军士气 -35、上限锁 65、医帐包扎 45s、35% 残血虚弱复出）— 二次阵亡殉国】闭环。

/// 战场主帅英雄状态实体（玩家主帅与敌军 AI 主帅对等共用同一物理模型）
public struct HeroCommanderEntity: Sendable, Equatable {
    public let side: BattleSide
    public let faction: FactionId

    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var facingRadians: Double

    public var hp: Double
    public var maxHp: Double
    public var baseArmor: Double
    public var baseMoveSpeed: Double
    public var vitalState: HeroVitalState
    public var activeWeapon: HeroWeaponType

    /// 百石硬弓剩余箭矢（上限 24 支）
    public var remainingArrows: Int
    public var outOfCombatTimer: Double
    public var arrowRecoverTimer: Double

    /// 攻击、蓄力与格挡精准弹反状态
    public var attackCooldown: Double
    public var bowChargeElapsed: Double
    public var isBlocking: Bool
    /// 举盾已持续秒数（<= 0.25s 为精准弹反窗口）
    public var blockRaisedElapsed: Double

    /// 三大主动战技冷却与持续态计时器
    public var breakthroughCooldown: Double
    public var ironBulwarkCooldown: Double
    public var grandWarCryCooldown: Double

    public var dashRemainingSec: Double
    public var dashDirX: Double
    public var dashDirY: Double
    /// 本次破阵突击已撞击过的最多 6 名士兵下标（定长标量字段零堆分配，且满足 Swift 6 自动合成 Equatable）
    public var dashHitUnit0: Int
    public var dashHitUnit1: Int
    public var dashHitUnit2: Int
    public var dashHitUnit3: Int
    public var dashHitUnit4: Int
    public var dashHitUnit5: Int

    public var ironBulwarkRemainingSec: Double
    /// 首次落马回本阵医帐包扎剩余秒数（45s）
    public var medicalRecoveryRemainingSec: Double

    public var killsCount: Int
    public var bannersSlainCount: Int

    public init(
        side: BattleSide,
        faction: FactionId,
        spawnX: Double,
        spawnY: Double,
        facingRadians: Double
    ) {
        let hpBonus = faction == .shuangyuan ? 1.15 : 1.0
        let computedMaxHp = GameConstants.heroBaseHp * hpBonus

        self.side = side
        self.faction = faction
        self.x = spawnX
        self.y = spawnY
        self.vx = 0.0
        self.vy = 0.0
        self.facingRadians = facingRadians
        self.hp = computedMaxHp
        self.maxHp = computedMaxHp
        self.baseArmor = GameConstants.heroBaseArmor
        self.baseMoveSpeed = GameConstants.heroBaseMoveSpeed
        self.vitalState = .healthyActive
        self.activeWeapon = .commandSaber
        self.remainingArrows = GameConstants.heroWarbowQuiverCap
        self.outOfCombatTimer = 0.0
        self.arrowRecoverTimer = 0.0
        self.attackCooldown = 0.0
        self.bowChargeElapsed = 0.0
        self.isBlocking = false
        self.blockRaisedElapsed = 0.0
        self.breakthroughCooldown = 0.0
        self.ironBulwarkCooldown = 0.0
        self.grandWarCryCooldown = 0.0
        self.dashRemainingSec = 0.0
        self.dashDirX = cos(facingRadians)
        self.dashDirY = sin(facingRadians)
        self.dashHitUnit0 = -1
        self.dashHitUnit1 = -1
        self.dashHitUnit2 = -1
        self.dashHitUnit3 = -1
        self.dashHitUnit4 = -1
        self.dashHitUnit5 = -1
        self.ironBulwarkRemainingSec = 0.0
        self.medicalRecoveryRemainingSec = 0.0
        self.killsCount = 0
        self.bannersSlainCount = 0
    }

    /// 主帅当前是否在场上有效参战（非医帐包扎、非殉国）
    public var isActiveOnField: Bool {
        vitalState == .healthyActive || vitalState == .woundedWeakened
    }

    /// 【重创虚弱】复出后攻防移速折损 25%
    public var attributeScale: Double {
        vitalState == .woundedWeakened ? 0.75 : 1.0
    }

    /// 当前是否处于 0.25s 统帅佩刀起盾精准弹反窗口
    public var isInPerfectParryWindow: Bool {
        isActiveOnField
            && activeWeapon == .commandSaber
            && isBlocking
            && blockRaisedElapsed <= GameConstants.heroPerfectParryWindowSec
    }

    public func cooldownRemaining(for skill: HeroSkillId) -> Double {
        switch skill {
        case .breakthroughCharge: return breakthroughCooldown
        case .ironBulwark: return ironBulwarkCooldown
        case .grandWarCry: return grandWarCryCooldown
        }
    }

    @inline(__always)
    public func hasDashHit(_ unitIndex: Int) -> Bool {
        dashHitUnit0 == unitIndex || dashHitUnit1 == unitIndex || dashHitUnit2 == unitIndex
            || dashHitUnit3 == unitIndex || dashHitUnit4 == unitIndex || dashHitUnit5 == unitIndex
    }

    @inline(__always)
    public mutating func recordDashHit(_ unitIndex: Int) {
        if dashHitUnit0 == -1 { dashHitUnit0 = unitIndex }
        else if dashHitUnit1 == -1 { dashHitUnit1 = unitIndex }
        else if dashHitUnit2 == -1 { dashHitUnit2 = unitIndex }
        else if dashHitUnit3 == -1 { dashHitUnit3 = unitIndex }
        else if dashHitUnit4 == -1 { dashHitUnit4 = unitIndex }
        else if dashHitUnit5 == -1 { dashHitUnit5 = unitIndex }
    }
}

/// 主帅动作事件回调结果（供战斗引擎同步顿帧、镜头微震、投射物生成与全军士气波动）
public struct HeroStepEvents: Sendable, Equatable {
    public var triggeredHitStopSec: Double = 0.0
    public var cameraShakeDelta: Double = 0.0
    public var spawnedHeavyArrow: Bool = false
    public var arrowOriginX: Double = 0.0
    public var arrowOriginY: Double = 0.0
    public var arrowTargetX: Double = 0.0
    public var arrowTargetY: Double = 0.0
    public var arrowDamage: Double = 0.0
    public var ironBulwarkFinisherSweep: Bool = false
    public var firstDownTriggered: Bool = false
    public var martyredTriggered: Bool = false

    public init() {}
}

public enum HeroCombatController: Sendable {
    // MARK: - 一、切换兵刃与释放三大主动战技

    public static func switchWeapon(hero: inout HeroCommanderEntity, to weapon: HeroWeaponType) {
        guard hero.isActiveOnField, hero.activeWeapon != weapon else { return }
        hero.activeWeapon = weapon
        hero.bowChargeElapsed = 0.0
        hero.isBlocking = false
        hero.blockRaisedElapsed = 0.0
    }

    /// 触发主帅三大主动技能；成功释放返回 true
    public static func triggerSkill(
        _ skill: HeroSkillId,
        hero: inout HeroCommanderEntity,
        squads: inout [BattleSquadState],
        events: inout HeroStepEvents
    ) -> Bool {
        guard hero.isActiveOnField else { return false }

        switch skill {
        case .breakthroughCharge:
            guard hero.breakthroughCooldown <= 0.0 else { return false }
            hero.breakthroughCooldown = 10.0
            hero.dashRemainingSec = 0.32 // 500 px/s * 0.32s = 160px 猛冲
            hero.dashDirX = cos(hero.facingRadians)
            hero.dashDirY = sin(hero.facingRadians)
            hero.dashHitUnit0 = -1
            hero.dashHitUnit1 = -1
            hero.dashHitUnit2 = -1
            hero.dashHitUnit3 = -1
            hero.dashHitUnit4 = -1
            hero.dashHitUnit5 = -1
            hero.outOfCombatTimer = 0.0
            events.cameraShakeDelta = max(events.cameraShakeDelta, 0.45)
            return true

        case .ironBulwark:
            guard hero.ironBulwarkCooldown <= 0.0 else { return false }
            hero.ironBulwarkCooldown = 8.0
            hero.ironBulwarkRemainingSec = 2.0
            hero.outOfCombatTimer = 0.0
            return true

        case .grandWarCry:
            guard hero.grandWarCryCooldown <= 0.0 else { return false }
            hero.grandWarCryCooldown = 22.0
            hero.outOfCombatTimer = 0.0
            events.cameraShakeDelta = max(events.cameraShakeDelta, 0.35)

            let allyRadiusSq = 320.0 * 320.0
            let enemyRadiusSq = 180.0 * 180.0
            for idx in 0..<squads.count where squads[idx].aliveCount > 0 {
                let dx = squads[idx].anchorX - hero.x
                let dy = squads[idx].anchorY - hero.y
                let distSq = dx * dx + dy * dy
                if squads[idx].side == hero.side && distSq <= allyRadiusSq {
                    // 320px 内友军立即恢复士气 +18，并可直接唤醒溃逃部队重整反扑，攻移速 +15% 持续 8s
                    let isBerserker = squads[idx].primaryUnitType == .xueyueWardrumBerserker
                    let updated = DamageMoraleCalculator.updateMoraleAndBracket(
                        currentMorale: squads[idx].morale,
                        wasRouting: squads[idx].isRouting,
                        moraleDelta: 18.0,
                        commanderRecoveringInCamp: false,
                        encirclementCap: squads[idx].encirclementState == .encircled ? 45.0 : nil,
                        supplyCap: GameConstants.moraleMax,
                        isFearlessBerserker: isBerserker,
                        inCloseEnemyContact: false,
                        forceWarCryRally: true
                    )
                    squads[idx].morale = updated.morale
                    squads[idx].moraleBracket = updated.bracket
                    squads[idx].isRouting = updated.isRouting
                    squads[idx].warCryBuffTimer = 8.0
                } else if squads[idx].side != hero.side && distSq <= enemyRadiusSq {
                    // 震慑 180px 内敌军士气 -10
                    let isBerserker = squads[idx].primaryUnitType == .xueyueWardrumBerserker
                    let updated = DamageMoraleCalculator.updateMoraleAndBracket(
                        currentMorale: squads[idx].morale,
                        wasRouting: squads[idx].isRouting,
                        moraleDelta: -10.0,
                        commanderRecoveringInCamp: false,
                        encirclementCap: nil,
                        supplyCap: GameConstants.moraleMax,
                        isFearlessBerserker: isBerserker,
                        inCloseEnemyContact: true
                    )
                    squads[idx].morale = updated.morale
                    squads[idx].moraleBracket = updated.bracket
                    squads[idx].isRouting = updated.isRouting
                }
            }
            return true
        }
    }

    // MARK: - 二、单步推进主帅移动、格挡、蓄力射击、箭袋补给与医帐恢复

    public static func stepHero(
        hero: inout HeroCommanderEntity,
        input: HeroControlInputState,
        isManualControl: Bool,
        deltaTime: Double,
        worldWidth: Double,
        worldHeight: Double,
        campPosition: (x: Double, y: Double),
        nearSupplyUnit: Bool,
        events: inout HeroStepEvents
    ) {
        // 冷却递减
        hero.attackCooldown = max(0.0, hero.attackCooldown - deltaTime)
        hero.breakthroughCooldown = max(0.0, hero.breakthroughCooldown - deltaTime)
        hero.ironBulwarkCooldown = max(0.0, hero.ironBulwarkCooldown - deltaTime)
        hero.grandWarCryCooldown = max(0.0, hero.grandWarCryCooldown - deltaTime)

        // 医帐包扎恢复期（45s）
        if hero.vitalState == .recoveringInCamp {
            hero.x = campPosition.x
            hero.y = campPosition.y
            hero.vx = 0.0
            hero.vy = 0.0
            hero.medicalRecoveryRemainingSec -= deltaTime
            if hero.medicalRecoveryRemainingSec <= 0.0 {
                hero.medicalRecoveryRemainingSec = 0.0
                hero.vitalState = .woundedWeakened
                hero.hp = hero.maxHp * 0.35
                hero.remainingArrows = GameConstants.heroWarbowQuiverCap
            }
            return
        }

        guard hero.isActiveOnField else { return }

        // 铁壁横戈 2.0s 招架倒计时与结束旋身横扫触发
        if hero.ironBulwarkRemainingSec > 0.0 {
            hero.ironBulwarkRemainingSec -= deltaTime
            if hero.ironBulwarkRemainingSec <= 0.0 {
                hero.ironBulwarkRemainingSec = 0.0
                events.ironBulwarkFinisherSweep = true
            }
        }

        // 破阵突击位移期
        if hero.dashRemainingSec > 0.0 {
            let stepTime = min(deltaTime, hero.dashRemainingSec)
            hero.dashRemainingSec -= stepTime
            let dashSpeed = 500.0
            hero.vx = hero.dashDirX * dashSpeed
            hero.vy = hero.dashDirY * dashSpeed
            hero.x = clamp(hero.x + hero.vx * stepTime, minVal: 24.0, maxVal: worldWidth - 24.0)
            hero.y = clamp(hero.y + hero.vy * stepTime, minVal: 24.0, maxVal: worldHeight - 24.0)
            return
        }

        // 键鼠操控移动与瞄准（若处于 RTS 视角，由引擎层传入自主护阵输入向量）
        if isManualControl {
            let aimDx = input.aimWorldX - hero.x
            let aimDy = input.aimWorldY - hero.y
            if aimDx * aimDx + aimDy * aimDy > 4.0 {
                hero.facingRadians = atan2(aimDy, aimDx)
            }

            // 右键举盾主动格挡（仅统帅佩刀支持主动举盾与 0.25s 弹反）
            if input.isSecondaryBlockHeld && hero.activeWeapon == .commandSaber {
                if !hero.isBlocking {
                    hero.isBlocking = true
                    hero.blockRaisedElapsed = 0.0
                } else {
                    hero.blockRaisedElapsed += deltaTime
                }
            } else {
                hero.isBlocking = false
                hero.blockRaisedElapsed = 0.0
            }

            let axisMag = hypot(input.moveAxisX, input.moveAxisY)
            if axisMag > 0.01 {
                let normX = input.moveAxisX / max(1.0, axisMag)
                let normY = input.moveAxisY / max(1.0, axisMag)
                var moveSpd = hero.baseMoveSpeed * hero.attributeScale
                if hero.isBlocking { moveSpd *= 0.60 }
                if hero.bowChargeElapsed > 0.0 { moveSpd *= 0.65 }
                hero.vx = normX * moveSpd
                hero.vy = normY * moveSpd
                hero.x = clamp(hero.x + hero.vx * deltaTime, minVal: 24.0, maxVal: worldWidth - 24.0)
                hero.y = clamp(hero.y + hero.vy * deltaTime, minVal: 24.0, maxVal: worldHeight - 24.0)
            } else {
                hero.vx = 0.0
                hero.vy = 0.0
            }

            // 百石硬弓蓄力 0.9s 与发射处理
            if hero.activeWeapon == .heavyWarbow {
                if input.isPrimaryAttackHeld && hero.remainingArrows > 0 && hero.attackCooldown <= 0.0 {
                    hero.bowChargeElapsed += deltaTime
                    if hero.bowChargeElapsed >= 0.90 {
                        fireHeroWarbow(hero: &hero, events: &events)
                    }
                } else if !input.isPrimaryAttackHeld && hero.bowChargeElapsed >= 0.45 && hero.remainingArrows > 0 {
                    // 半蓄力以上松开左键也可射出按比例缩放伤害的重箭
                    fireHeroWarbow(hero: &hero, events: &events)
                } else if !input.isPrimaryAttackHeld {
                    hero.bowChargeElapsed = 0.0
                }
            } else {
                hero.bowChargeElapsed = 0.0
            }
        }

        // 随身箭袋 24 支上限补给机制：靠近本阵大营 180px 或辎重工兵快速补满；脱战每 2.5s 自动寻回 1 支
        hero.outOfCombatTimer += deltaTime
        let campDx = hero.x - campPosition.x
        let campDy = hero.y - campPosition.y
        if campDx * campDx + campDy * campDy <= 180.0 * 180.0 || nearSupplyUnit {
            hero.remainingArrows = GameConstants.heroWarbowQuiverCap
            hero.arrowRecoverTimer = 0.0
        } else if hero.remainingArrows < GameConstants.heroWarbowQuiverCap && hero.outOfCombatTimer >= 3.0 {
            hero.arrowRecoverTimer += deltaTime
            while hero.arrowRecoverTimer >= GameConstants.heroArrowRecoverIntervalSec
                && hero.remainingArrows < GameConstants.heroWarbowQuiverCap {
                hero.arrowRecoverTimer -= GameConstants.heroArrowRecoverIntervalSec
                hero.remainingArrows += 1
            }
        }
    }

    private static func fireHeroWarbow(hero: inout HeroCommanderEntity, events: inout HeroStepEvents) {
        guard hero.remainingArrows > 0 else { return }
        let ratio = min(1.0, max(0.5, hero.bowChargeElapsed / 0.90))
        hero.remainingArrows -= 1
        hero.bowChargeElapsed = 0.0
        hero.attackCooldown = 0.35
        hero.outOfCombatTimer = 0.0

        let range = 460.0
        events.spawnedHeavyArrow = true
        events.arrowOriginX = hero.x + cos(hero.facingRadians) * 14.0
        events.arrowOriginY = hero.y + sin(hero.facingRadians) * 14.0
        events.arrowTargetX = hero.x + cos(hero.facingRadians) * range
        events.arrowTargetY = hero.y + sin(hero.facingRadians) * range
        events.arrowDamage = 95.0 * ratio * hero.attributeScale
    }

    // MARK: - 三、主帅受击结算、精准弹反与两段式落马重伤状态机

    /// 对主帅施加伤害；返回实际扣血值，并在触发精准弹反或落马重伤/殉国时更新状态机
    public static func applyDamageToHero(
        hero: inout HeroCommanderEntity,
        rawAttack: Double,
        armorPenetration: Double,
        attackerX: Double,
        attackerY: Double,
        isMelee: Bool,
        friendlyCampDestroyed: Bool,
        nonRoutingFriendlyRatio: Double,
        hasReserveTroops: Bool,
        events: inout HeroStepEvents
    ) -> (actualDamage: Double, triggeredPerfectParry: Bool) {
        guard hero.isActiveOnField else { return (0.0, false) }
        hero.outOfCombatTimer = 0.0

        let incomingAngle = DamageMoraleCalculator.incomingAttackAngle(
            targetX: hero.x,
            targetY: hero.y,
            targetFacingRadians: hero.facingRadians,
            attackerX: attackerX,
            attackerY: attackerY
        )
        let isFrontal = incomingAngle <= (Double.pi * 0.5)

        // 1. 统帅佩刀起盾前 0.25s 精准弹反窗口：正面近战零伤弹反，卡肉顿帧 40ms
        if isMelee && isFrontal && hero.isInPerfectParryWindow {
            events.triggeredHitStopSec = Double(GameConstants.heroHitStopMilliseconds) / 1000.0
            events.cameraShakeDelta = max(events.cameraShakeDelta, 0.30)
            return (0.0, true)
        }

        // 2. 铁壁横戈招架期或举盾格挡减伤
        var blockMult = 1.0
        if hero.ironBulwarkRemainingSec > 0.0 && isFrontal {
            blockMult = isMelee ? 0.25 : 0.10
        } else if hero.isBlocking && hero.activeWeapon == .commandSaber && isFrontal {
            blockMult = 0.20 // 主动举盾减免正面 80% 伤害
        }

        let effArmor = DamageMoraleCalculator.computeEffectiveArmor(
            targetArmor: hero.baseArmor * hero.attributeScale,
            armorPenetration: armorPenetration
        )
        let mitigation = DamageMoraleCalculator.computeArmorMitigation(effectiveArmor: effArmor)
        let finalDmg = max(GameConstants.minimumHitDamage * blockMult, rawAttack * blockMult * (1.0 - mitigation))

        hero.hp -= finalDmg
        if hero.hp <= 0.0 {
            hero.hp = 0.0
            handleHeroZeroHp(
                hero: &hero,
                friendlyCampDestroyed: friendlyCampDestroyed,
                nonRoutingFriendlyRatio: nonRoutingFriendlyRatio,
                hasReserveTroops: hasReserveTroops,
                events: &events
            )
        }
        return (finalDmg, false)
    }

    private static func handleHeroZeroHp(
        hero: inout HeroCommanderEntity,
        friendlyCampDestroyed: Bool,
        nonRoutingFriendlyRatio: Double,
        hasReserveTroops: Bool,
        events: inout HeroStepEvents
    ) {
        // 首次落马判定：须处于 healthyActive，且本阵未破，且场上未溃兵力 >= 10% 或仍有后备军
        let canRescue = hero.vitalState == .healthyActive
            && !friendlyCampDestroyed
            && (nonRoutingFriendlyRatio >= 0.10 || hasReserveTroops)

        if canRescue {
            hero.vitalState = .recoveringInCamp
            hero.medicalRecoveryRemainingSec = GameConstants.heroMedicalRecoverySec
            hero.isBlocking = false
            hero.bowChargeElapsed = 0.0
            hero.dashRemainingSec = 0.0
            hero.ironBulwarkRemainingSec = 0.0
            events.firstDownTriggered = true
            events.cameraShakeDelta = max(events.cameraShakeDelta, 0.75)
        } else {
            // 二次阵亡或本阵已失守无处抢救 -> 主帅殉国
            hero.vitalState = .fallenMartyred
            hero.medicalRecoveryRemainingSec = 0.0
            events.martyredTriggered = true
            events.cameraShakeDelta = max(events.cameraShakeDelta, 1.0)
        }
    }

    @inline(__always)
    private static func clamp(_ v: Double, minVal: Double, maxVal: Double) -> Double {
        max(minVal, min(maxVal, v))
    }
}
