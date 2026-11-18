// ============================================================================
// 文件：CombatEngineTests.swift
// 模块：Core/Combat 战斗模拟核心引擎专用单元测试（XCTest）
// 覆盖：双曲护甲与巨斧破甲、远程方向性盾防、长枪架枪反骑停马、半渡而击、
//       八象限包抄/钳形夹击/五扇区铁桶合围、士气 20->32 迟滞防抖与战吼唤醒、
//       主帅 0.25s 弹反与两段式“落马重伤—二次绝命”、三级断粮与奇袭敌粮车、
//       空间哈希网格零分配检索与密林反隐、战术暂停预下令与 25s 应急民夫防死锁。
//
// 在 Mac 上的运行方式（当前 Linux 开发机无 Xcode / macOS，未在本机跑过）：
//   方式一（Xcode GUI）：打开 `StickmanWar.xcodeproj`，选择 `StickmanWar` Scheme，按 `Cmd+U`（⌘U）运行全部测试。
//   方式二（命令行）：在工程根目录执行：
//     xcodebuild test \
//       -project StickmanWar.xcodeproj \
//       -scheme StickmanWar \
//       -destination 'platform=macOS,arch=arm64' \
//       -only-testing:StickmanWarTests/CombatEngineTests
// ============================================================================

import Foundation
import XCTest
@testable import StickmanWar

final class CombatEngineTests: XCTestCase {

    // MARK: - 1. 双曲护甲（K=50）、巨斧高破甲、保底伤害与远程方向性盾防结算

    func testHyperbolicArmorGreatAxePenetrationAndDirectionalShield() {
        // K = 50：有效护甲 50 时减伤严格为 50%
        let eff50 = DamageMoraleCalculator.computeEffectiveArmor(targetArmor: 50.0, armorPenetration: 0.0)
        XCTAssertEqual(eff50, 50.0, accuracy: 1e-6)
        XCTAssertEqual(DamageMoraleCalculator.computeArmorMitigation(effectiveArmor: eff50), 0.50, accuracy: 1e-6)

        // 超高护甲绝不出现 100% 免伤死局，且遵守单次最低 2.0 保底伤害
        let minDmgOut = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 3.0,
                attackerArmorPenetration: 0.0,
                targetBaseArmor: 500.0,
                targetFormationBonusActive: false
            )
        )
        XCTAssertEqual(minDmgOut.finalDamage, GameConstants.minimumHitDamage, accuracy: 1e-6)

        // 重型巨斧兵（攻 34，破甲 65%）vs 方阵刀盾步兵（基础甲 45，方阵 +20% -> 54）
        let axeStats = UnitConfig.stats(for: .greatAxeman)!
        let shieldStats = UnitConfig.stats(for: .shieldSwordsman)!
        let axeVsShield = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: Double(axeStats.attack),
                attackerArmorPenetration: axeStats.armorPenetration,
                attackerFormationBonusActive: false,
                isMelee: true,
                targetBaseArmor: Double(shieldStats.armor),
                targetFormation: .phalanxRect,
                targetFormationBonusActive: true
            )
        )
        // 54 * (1 - 0.65) = 18.9 -> 减伤 18.9 / 68.9 -> 最终伤害 34 * (50 / 68.9)
        XCTAssertEqual(axeVsShield.effectiveArmor, 18.9, accuracy: 1e-6)
        XCTAssertEqual(axeVsShield.finalDamage, 34.0 * (50.0 / 68.9), accuracy: 1e-4)

        // 远程方向性盾防：正面（<=60°）减免 55%，侧翼（90°）盾防减半 + 1.25x 侧伤，背射（180°）无视盾防 + 1.45x 背伤
        let frontArrow = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 40.0,
                attackerArmorPenetration: 0.0,
                attackerFormationBonusActive: false,
                isMelee: false,
                targetBaseArmor: 0.0,
                targetShieldRangedBlock: 0.55,
                targetFormationBonusActive: false,
                incomingAngleDifferenceRadians: 0.0
            )
        )
        XCTAssertEqual(frontArrow.directionZone, .front)
        XCTAssertTrue(frontArrow.shieldBlocked)
        XCTAssertEqual(frontArrow.finalDamage, 40.0 * (1.0 - 0.55), accuracy: 1e-6)

        let flankArrow = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 40.0,
                attackerArmorPenetration: 0.0,
                attackerFormationBonusActive: false,
                isMelee: false,
                targetBaseArmor: 0.0,
                targetShieldRangedBlock: 0.55,
                targetFormationBonusActive: false,
                incomingAngleDifferenceRadians: Double.pi * 0.5
            )
        )
        XCTAssertEqual(flankArrow.directionZone, .flank)
        XCTAssertEqual(flankArrow.finalDamage, 40.0 * 1.25 * (1.0 - 0.275), accuracy: 1e-6)

        let rearArrow = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 40.0,
                attackerArmorPenetration: 0.0,
                attackerFormationBonusActive: false,
                isMelee: false,
                targetBaseArmor: 0.0,
                targetShieldRangedBlock: 0.55,
                targetFormationBonusActive: false,
                incomingAngleDifferenceRadians: Double.pi
            )
        )
        XCTAssertEqual(rearArrow.directionZone, .rear)
        XCTAssertFalse(rearArrow.shieldBlocked)
        XCTAssertEqual(rearArrow.finalDamage, 40.0 * 1.45, accuracy: 1e-6)

        // 圆阵有效时消除 360° 背击惩罚，背后中箭仍按正面盾防结算
        let circleRearArrow = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 40.0,
                attackerArmorPenetration: 0.0,
                attackerFormationBonusActive: false,
                isMelee: false,
                targetBaseArmor: 0.0,
                targetShieldRangedBlock: 0.55,
                targetFormation: .circleDefense,
                targetFormationBonusActive: true,
                incomingAngleDifferenceRadians: Double.pi
            )
        )
        XCTAssertEqual(circleRearArrow.directionZone, .front)
        XCTAssertEqual(circleRearArrow.finalDamage, frontArrow.finalDamage, accuracy: 1e-6)
    }

    // MARK: - 2. 长枪正面架枪 3.2x 反骑 +30% 动能破甲停马 vs 背击失效，以及渡河半渡而击

    func testBracedPikemanAntiCavalryMomentumAndHalfFordVulnerability() {
        let pike = UnitConfig.stats(for: .pikeman)!
        let cataphract = UnitConfig.stats(for: .xuanjiaCataphract)!

        // 长枪方阵正面架枪迎击冲锋具装铁浮图：激活 3.2x 反骑倍率且破甲由 25% 跃升至 55%
        let bracedFront = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: Double(pike.attack),
                attackerArmorPenetration: pike.armorPenetration,
                attackerAntiCavMultiplier: pike.antiCavalryMultiplier,
                attackerFormationBonusActive: false,
                attackerIsBraced: true,
                isMelee: true,
                targetBaseArmor: Double(cataphract.armor),
                targetCategory: .cavalry,
                targetFormationBonusActive: false,
                targetIsChargingCavalry: true,
                incomingAngleDifferenceRadians: 0.0
            )
        )
        XCTAssertTrue(bracedFront.triggeredBracedAntiCav)
        XCTAssertEqual(bracedFront.effectiveArmor, 68.0 * (1.0 - 0.55), accuracy: 1e-6)
        XCTAssertGreaterThan(bracedFront.finalDamage, 38.0)

        // 若敌骑绕至长枪背后突袭（180°）：架枪反骑失效，且敌骑冲锋倍率正常触发
        let rearFromCav = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: Double(pike.attack),
                attackerArmorPenetration: pike.armorPenetration,
                attackerAntiCavMultiplier: pike.antiCavalryMultiplier,
                attackerFormationBonusActive: false,
                attackerIsBraced: true,
                isMelee: true,
                targetBaseArmor: Double(cataphract.armor),
                targetCategory: .cavalry,
                targetFormationBonusActive: false,
                targetIsChargingCavalry: true,
                incomingAngleDifferenceRadians: Double.pi
            )
        )
        XCTAssertFalse(rearFromCav.triggeredBracedAntiCav)

        // 骑兵正撞已架枪长枪方阵时冲锋倍率被强制封锁，侧翼冲撞则触发冲锋
        let cavChargeFrontIntoPike = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 24.0,
                attackerArmorPenetration: 0.20,
                attackerChargeMultiplier: 2.10,
                attackerFormationBonusActive: false,
                attackerIsCharging: true,
                isMelee: true,
                targetBaseArmor: 28.0,
                targetCategory: .polearm,
                targetFormation: .phalanxRect,
                targetFormationBonusActive: true,
                targetIsBracedPolearm: true,
                incomingAngleDifferenceRadians: 0.0
            )
        )
        XCTAssertFalse(cavChargeFrontIntoPike.triggeredCharge)

        let cavChargeFlankIntoPike = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 24.0,
                attackerArmorPenetration: 0.20,
                attackerChargeMultiplier: 2.10,
                attackerFormationBonusActive: false,
                attackerIsCharging: true,
                isMelee: true,
                targetBaseArmor: 28.0,
                targetCategory: .polearm,
                targetFormation: .phalanxRect,
                targetFormationBonusActive: true,
                targetIsBracedPolearm: true,
                incomingAngleDifferenceRadians: Double.pi * 0.5
            )
        )
        XCTAssertTrue(cavChargeFlankIntoPike.triggeredCharge)
        XCTAssertGreaterThan(cavChargeFlankIntoPike.finalDamage, cavChargeFrontIntoPike.finalDamage * 2.4)

        // 半渡而击：分队 30%~80% 成员涉水首尾脱节时额外承受 1.20x 易伤
        let dryHit = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 30.0,
                attackerArmorPenetration: 0.20,
                attackerFormationBonusActive: false,
                targetBaseArmor: 20.0,
                targetFormationBonusActive: false,
                targetSquadRiverWadingRatio: 0.10
            )
        )
        let halfFordHit = DamageMoraleCalculator.calculateDamage(
            DamageCalculationInput(
                baseAttack: 30.0,
                attackerArmorPenetration: 0.20,
                attackerFormationBonusActive: false,
                targetBaseArmor: 20.0,
                targetFormationBonusActive: false,
                targetSquadRiverWadingRatio: 0.55
            )
        )
        XCTAssertFalse(dryHit.triggeredHalfFord)
        XCTAssertTrue(halfFordHit.triggeredHalfFord)
        XCTAssertEqual(halfFordHit.finalDamage, dryHit.finalDamage * GameConstants.halfFordVulnerabilityMultiplier, accuracy: 1e-6)
    }

    // MARK: - 3. 八象限包抄、钳形夹击、五扇区铁桶合围与窄桥地形免疫

    func testOctantEncirclementPincerAndBridgeImmunity() {
        XCTAssertEqual(DamageMoraleCalculator.octantIndex(forRelativeAngle: 0.0), 0)
        XCTAssertEqual(DamageMoraleCalculator.octantIndex(forRelativeAngle: Double.pi * 0.5), 2)
        XCTAssertEqual(DamageMoraleCalculator.octantIndex(forRelativeAngle: Double.pi), 4)

        // 单纯正面接敌（扇区 0）-> clear
        let frontEval = DamageMoraleCalculator.evaluateEncirclement(
            occupiedOctantMask: 0b0000_0001,
            distinctEnemySquadCount: 1,
            retreatOctantBlocked: false,
            formation: .phalanxRect,
            formationBonusActive: true,
            terrain: .plain
        )
        XCTAssertEqual(frontEval.state, .clear)
        XCTAssertEqual(frontEval.moraleDrainPerSec, 0.0, accuracy: 1e-6)

        // 单侧背后遭袭（扇区 4）-> flanked
        let flankEval = DamageMoraleCalculator.evaluateEncirclement(
            occupiedOctantMask: 1 << 4,
            distinctEnemySquadCount: 1,
            retreatOctantBlocked: false,
            formation: .phalanxRect,
            formationBonusActive: true,
            terrain: .plain
        )
        XCTAssertEqual(flankEval.state, .flanked)
        XCTAssertEqual(flankEval.moraleDrainPerSec, 0.6, accuracy: 1e-6)

        // 双军团前后钝角夹击（扇区 0 与扇区 4，步距 4 >= 3）-> pincered (-2.2/s)
        let pincerEval = DamageMoraleCalculator.evaluateEncirclement(
            occupiedOctantMask: (1 << 0) | (1 << 4),
            distinctEnemySquadCount: 2,
            retreatOctantBlocked: false,
            formation: .phalanxRect,
            formationBonusActive: true,
            terrain: .plain
        )
        XCTAssertEqual(pincerEval.state, .pincered)
        XCTAssertEqual(pincerEval.moraleDrainPerSec, GameConstants.pincerMoraleDrainPerSec, accuracy: 1e-6)

        // 五扇区受敌且退路被封堵 -> encircled (-4.8/s，士气上限压制至 45)
        let fiveOctantsMask: UInt8 = 0b0001_1111
        let encircledPhalanx = DamageMoraleCalculator.evaluateEncirclement(
            occupiedOctantMask: fiveOctantsMask,
            distinctEnemySquadCount: 3,
            retreatOctantBlocked: true,
            formation: .phalanxRect,
            formationBonusActive: true,
            terrain: .plain
        )
        XCTAssertEqual(encircledPhalanx.state, .encircled)
        XCTAssertEqual(encircledPhalanx.occupiedOctantCount, 5)
        XCTAssertEqual(encircledPhalanx.moraleDrainPerSec, GameConstants.encirclementMoraleDrainPerSec, accuracy: 1e-6)
        XCTAssertEqual(encircledPhalanx.moraleCapOverride, 45.0)

        // 圆阵下被铁桶合围士气流失减半，桥梁窄口完全免疫合围
        let encircledCircle = DamageMoraleCalculator.evaluateEncirclement(
            occupiedOctantMask: fiveOctantsMask,
            distinctEnemySquadCount: 3,
            retreatOctantBlocked: true,
            formation: .circleDefense,
            formationBonusActive: true,
            terrain: .plain
        )
        XCTAssertEqual(encircledCircle.moraleDrainPerSec, GameConstants.encirclementMoraleDrainPerSec * 0.5, accuracy: 1e-6)

        let bridgeProtected = DamageMoraleCalculator.evaluateEncirclement(
            occupiedOctantMask: 0b0111_1111,
            distinctEnemySquadCount: 4,
            retreatOctantBlocked: true,
            formation: .phalanxRect,
            formationBonusActive: true,
            terrain: .bridgePass
        )
        XCTAssertEqual(bridgeProtected.state, .clear)
        XCTAssertEqual(bridgeProtected.moraleDrainPerSec, 0.0, accuracy: 1e-6)
    }

    // MARK: - 4. 士气 <20 溃逃至 >=32 恢复的迟滞防抖状态机、战吼强行唤醒与血月狂战免溃

    func testMoraleHysteresisWarCryRallyAndBerserkerFloor() {
        // 跌破 20 进入溃逃
        let dropToRout = DamageMoraleCalculator.updateMoraleAndBracket(
            currentMorale: 24.0,
            wasRouting: false,
            moraleDelta: -6.0,
            commanderRecoveringInCamp: false,
            encirclementCap: nil,
            supplyCap: 100.0,
            isFearlessBerserker: false,
            inCloseEnemyContact: true
        )
        XCTAssertEqual(dropToRout.morale, 18.0, accuracy: 1e-6)
        XCTAssertTrue(dropToRout.isRouting)
        XCTAssertEqual(dropToRout.bracket, .routing)

        // 迟滞防抖：回升至 28（>=20 但 <32）且已脱战，仍须维持溃逃态防止鬼畜抽搐
        let stillRoutingInBand = DamageMoraleCalculator.updateMoraleAndBracket(
            currentMorale: dropToRout.morale,
            wasRouting: true,
            moraleDelta: 10.0,
            commanderRecoveringInCamp: false,
            encirclementCap: nil,
            supplyCap: 100.0,
            isFearlessBerserker: false,
            inCloseEnemyContact: false
        )
        XCTAssertEqual(stillRoutingInBand.morale, 28.0, accuracy: 1e-6)
        XCTAssertTrue(stillRoutingInBand.isRouting)
        XCTAssertEqual(stillRoutingInBand.bracket, .routing)

        // 若仍在近身交战（inCloseEnemyContact == true），即便士气 >= 32 也无法自然重整
        let blockedByContact = DamageMoraleCalculator.updateMoraleAndBracket(
            currentMorale: 28.0,
            wasRouting: true,
            moraleDelta: 6.0,
            commanderRecoveringInCamp: false,
            encirclementCap: nil,
            supplyCap: 100.0,
            isFearlessBerserker: false,
            inCloseEnemyContact: true
        )
        XCTAssertTrue(blockedByContact.isRouting)

        // 脱离接触且回升至 >= 32 -> 解除溃逃重返动摇可控状态
        let naturalRally = DamageMoraleCalculator.updateMoraleAndBracket(
            currentMorale: 28.0,
            wasRouting: true,
            moraleDelta: 5.0,
            commanderRecoveringInCamp: false,
            encirclementCap: nil,
            supplyCap: 100.0,
            isFearlessBerserker: false,
            inCloseEnemyContact: false
        )
        XCTAssertEqual(naturalRally.morale, 33.0, accuracy: 1e-6)
        XCTAssertFalse(naturalRally.isRouting)
        XCTAssertEqual(naturalRally.bracket, .wavering)

        // 主帅【三军战吼】（forceWarCryRally == true）：即便处于 24 点迟滞区间且贴身肉搏，也可当场唤醒溃军
        let warCryRally = DamageMoraleCalculator.updateMoraleAndBracket(
            currentMorale: 10.0,
            wasRouting: true,
            moraleDelta: 18.0,
            commanderRecoveringInCamp: false,
            encirclementCap: nil,
            supplyCap: 100.0,
            isFearlessBerserker: false,
            inCloseEnemyContact: true,
            forceWarCryRally: true
        )
        XCTAssertEqual(warCryRally.morale, 28.0, accuracy: 1e-6)
        XCTAssertFalse(warCryRally.isRouting)

        // 血月狂战祭团锁定士气 >= 50 永不溃逃
        let berserkerCheck = DamageMoraleCalculator.updateMoraleAndBracket(
            currentMorale: 60.0,
            wasRouting: false,
            moraleDelta: -95.0,
            commanderRecoveringInCamp: false,
            encirclementCap: nil,
            supplyCap: 100.0,
            isFearlessBerserker: true,
            inCloseEnemyContact: true
        )
        XCTAssertEqual(berserkerCheck.morale, 50.0, accuracy: 1e-6)
        XCTAssertFalse(berserkerCheck.isRouting)
    }

    // MARK: - 5. 主帅 0.25s 精准弹反与两段式“落马重伤（-35 士气、锁 65、包扎 45s）—二次阵亡判负”

    func testHeroPerfectParryTwoStageDownAndSecondDeathMartyrdom() {
        // 5.1 统帅佩刀起盾前 0.25s 精准弹反窗口验证
        var hero = HeroCommanderEntity(side: .player, faction: .yanlong, spawnX: 800.0, spawnY: 1200.0, facingRadians: 0.0)
        hero.isBlocking = true
        hero.blockRaisedElapsed = 0.12
        XCTAssertTrue(hero.isInPerfectParryWindow)

        var parryEvents = HeroStepEvents()
        let parryRes = HeroCombatController.applyDamageToHero(
            hero: &hero,
            rawAttack: 90.0,
            armorPenetration: 0.40,
            attackerX: 830.0,
            attackerY: 1200.0,
            isMelee: true,
            friendlyCampDestroyed: false,
            nonRoutingFriendlyRatio: 1.0,
            hasReserveTroops: true,
            events: &parryEvents
        )
        XCTAssertTrue(parryRes.triggeredPerfectParry)
        XCTAssertEqual(parryRes.actualDamage, 0.0, accuracy: 1e-6)
        XCTAssertEqual(hero.hp, hero.maxHp, accuracy: 1e-6)
        XCTAssertEqual(parryEvents.triggeredHitStopSec, Double(GameConstants.heroHitStopMilliseconds) / 1000.0, accuracy: 1e-6)

        // 5.2 在完整战斗模拟引擎中验证两段式落马重伤与二次阵亡殉国闭环（使用驻守与后勤编制隔离前线混战干扰）
        var engine = BattleSimulationEngine(
            context: RouteLaunchContext(playerFaction: .yanlong, enemyFaction: .canglang),
            deployment: BattleDeploymentConfig(
                customPlayerRoster: [
                    BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 12, initialFormation: .phalanxRect)
                ],
                customEnemyRoster: [
                    BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 4, initialFormation: .circleDefense)
                ]
            )
        )
        engine.issueSquadCommand(SquadCommandRequest(squadIds: [0], order: .holdGround, targetWorldX: 900.0, targetWorldY: 1200.0))
        XCTAssertTrue(engine.toggleControlMode())
        XCTAssertEqual(engine.controlMode, .heroAction)
        XCTAssertFalse(engine.toggleControlMode(), "1.5s 视角切换保护冷却内应拒绝重复切换")

        // 首次致命重击：大营未破且主力健在 -> 落马回营包扎 45s、自动切回 RTS 视角、全军士气暴扣 -35 且封顶 65
        engine.damageCommander(
            targetSide: .player,
            rawAttack: 5000.0,
            armorPen: 0.90,
            attackerX: engine.playerHero.x + 25.0,
            attackerY: engine.playerHero.y,
            isMelee: true
        )
        XCTAssertEqual(engine.playerHero.vitalState, .recoveringInCamp)
        XCTAssertEqual(engine.playerHero.medicalRecoveryRemainingSec, GameConstants.heroMedicalRecoverySec, accuracy: 1e-6)
        XCTAssertEqual(engine.controlMode, .rtsCommander)
        XCTAssertEqual(engine.outcome, .ongoing)
        for sq in engine.squads where sq.side == .player && sq.aliveCount > 0 {
            XCTAssertLessThanOrEqual(sq.morale, GameConstants.heroDownMoraleCap)
            XCTAssertLessThanOrEqual(sq.morale, GameConstants.moraleBase - GameConstants.heroFirstDownMoraleShock + 1e-5)
        }

        // 推进 2.0s 解除视角切换冷却后，医帐昏迷期间仍严禁按 Tab 切入英雄模式
        for _ in 0..<20 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(engine.playerHero.vitalState, .recoveringInCamp)
        XCTAssertFalse(engine.toggleControlMode(), "主帅昏迷包扎期间必须禁止切入亲自上阵视角")

        // 推进剩余包扎时长（共超过 45s）-> 35% 残血 + 重创虚弱（属性 0.75x）复出，箭袋补满 24 支
        for _ in 0..<440 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(engine.playerHero.vitalState, .woundedWeakened)
        XCTAssertEqual(engine.playerHero.attributeScale, 0.75, accuracy: 1e-6)
        XCTAssertEqual(engine.playerHero.hp, engine.playerHero.maxHp * 0.35, accuracy: 1.0)
        XCTAssertEqual(engine.playerHero.remainingArrows, GameConstants.heroWarbowQuiverCap)

        // 对敌帅对等法则：击倒敌军主帅令敌方陷入 15s 指挥瘫痪
        engine.damageCommander(
            targetSide: .enemy,
            rawAttack: 5000.0,
            armorPen: 0.90,
            attackerX: engine.enemyHero.x - 25.0,
            attackerY: engine.enemyHero.y,
            isMelee: true,
            byHero: true
        )
        XCTAssertEqual(engine.enemyHero.vitalState, .recoveringInCamp)
        XCTAssertEqual(engine.enemyState.commandParalysisTimer, 15.0, accuracy: 1e-6)

        // 玩家主帅挂着【重创虚弱】二次 HP 归零 -> 失去免死保护，直接殉国判负
        engine.damageCommander(
            targetSide: .player,
            rawAttack: 5000.0,
            armorPen: 0.90,
            attackerX: engine.playerHero.x + 25.0,
            attackerY: engine.playerHero.y,
            isMelee: true
        )
        XCTAssertEqual(engine.playerHero.vitalState, .fallenMartyred)
        XCTAssertEqual(engine.outcome, .playerCommanderMartyred)
    }

    // MARK: - 6. 战场三级断粮惩罚与轻骑奇袭敌本阵粮车夺取应急粮草闭环

    func testBattlefieldStarvationThreeStagesAndRaidEnemyGranaryRecovery() {
        let abundant = DamageMoraleCalculator.evaluateRationStage(remainingGrain: 100.0, upkeepPerSec: 2.0, zeroGrainElapsedSec: 0.0)
        XCTAssertEqual(abundant.stage, .abundant)

        let warning = DamageMoraleCalculator.evaluateRationStage(remainingGrain: 20.0, upkeepPerSec: 2.0, zeroGrainElapsedSec: 0.0)
        XCTAssertEqual(warning.stage, .warning)

        let hungry = DamageMoraleCalculator.evaluateRationStage(remainingGrain: 0.0, upkeepPerSec: 2.0, zeroGrainElapsedSec: 10.0)
        XCTAssertEqual(hungry.stage, .hungry)
        XCTAssertEqual(hungry.moraleDrainPerSec, 0.8, accuracy: 1e-6)
        XCTAssertEqual(hungry.speedMultiplier, 0.88, accuracy: 1e-6)

        let starving = DamageMoraleCalculator.evaluateRationStage(remainingGrain: 0.0, upkeepPerSec: 2.0, zeroGrainElapsedSec: 35.0)
        XCTAssertEqual(starving.stage, .starving)
        XCTAssertEqual(starving.moraleDrainPerSec, 1.8, accuracy: 1e-6)
        XCTAssertEqual(starving.speedMultiplier, 0.85, accuracy: 1e-6)

        // 实战引擎推进：开局极低余粮耗尽后先进入 hungry，超过 30s 升级为 starving
        let starveRoster = [
            BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 20, initialFormation: .phalanxRect)
        ]
        let isolatedEnemySappers = [
            BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 2, initialFormation: .circleDefense)
        ]
        var starveEngine = BattleSimulationEngine(
            context: RouteLaunchContext(playerFaction: .yanlong, enemyFaction: .tieying),
            deployment: BattleDeploymentConfig(
                customPlayerRoster: starveRoster,
                customEnemyRoster: isolatedEnemySappers,
                playerInitialGrain: 0.2
            )
        )
        let playerSqIds = starveEngine.squads.filter { $0.side == .player }.map(\.id)
        starveEngine.issueSquadCommand(SquadCommandRequest(squadIds: playerSqIds, order: .holdGround))

        for _ in 0..<20 {
            starveEngine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(starveEngine.playerState.rationStage, .hungry)

        for _ in 0..<310 {
            starveEngine.stepLogicTick(deltaTime: 0.10)
        }
        XCTAssertEqual(starveEngine.playerState.rationStage, .starving)

        // 苍狼游骑兵奇袭敌方本阵大营粮车：首次劈中敌本阵当场夺取双倍 300 粮（常规势力 150 粮）解除断粮
        let raidDeployment = BattleDeploymentConfig(
            customPlayerRoster: [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .lightCavalry, count: 16, initialFormation: .wedgeCharge)
            ],
            customEnemyRoster: [
                BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 1, initialFormation: .circleDefense)
            ],
            playerInitialGrain: 20.0
        )
        var raidEngine = BattleSimulationEngine(
            context: RouteLaunchContext(playerFaction: .canglang, enemyFaction: .yanlong),
            deployment: raidDeployment
        )
        let enemyCamp = raidEngine.baseCampCoordinates(for: .enemy)
        let raiderIds = raidEngine.squads.filter { $0.side == .player }.map(\.id)
        raidEngine.issueSquadCommand(
            SquadCommandRequest(
                squadIds: raiderIds,
                formation: .wedgeCharge,
                order: .allOutCharge,
                targetWorldX: enemyCamp.x,
                targetWorldY: enemyCamp.y
            )
        )
        for _ in 0..<360 where raidEngine.outcome == .ongoing {
            raidEngine.stepLogicTick(deltaTime: 0.10)
            if raidEngine.playerState.lootedGrainTotal > 0.0 {
                break
            }
        }
        let enemyCampEntity = raidEngine.structures.first { $0.side == .enemy && $0.kind == .baseCamp }
        XCTAssertEqual(enemyCampEntity?.granaryLooted, true, "轻骑突入敌营应成功劫掠敌方随军粮车")
        XCTAssertEqual(raidEngine.playerState.lootedGrainTotal, GameConstants.raidEnemyGranaryLootGrain * 2.0, accuracy: 1e-6)
    }

    // MARK: - 7. 均匀空间哈希网格检索、密林潜伏反隐规则、战术暂停下令与 25s 应急工兵保底

    func testSpatialHashGridStealthPauseCommandAndEmergencySapperGuard() {
        var grid = SpatialHashGrid(worldWidth: 4800.0, worldHeight: 2400.0, cellSize: 120.0, maxUnits: 600)
        XCTAssertEqual(grid.cols, 40)
        XCTAssertEqual(grid.rows, 20)

        // 在距观察者 (1000, 1000) 200px 处插入一名密林潜伏敌军（>140px 普通步兵识破半径，<=210px 轻骑侦察半径）
        grid.insert(unitIndex: 7, x: 1200.0, y: 1000.0, radius: 8.0, side: .enemy, isConcealed: true)

        let missedByInfantry = grid.findNearestEnemy(
            fromX: 1000.0,
            fromY: 1000.0,
            enemySide: .enemy,
            maxRange: 360.0,
            viewerFaction: .yanlong,
            viewerIsCavalryScout: false
        )
        XCTAssertEqual(missedByInfantry, -1, "常规步兵在 140px 外不应识破密林未开火伏兵")

        let spottedByCavalry = grid.findNearestEnemy(
            fromX: 1000.0,
            fromY: 1000.0,
            enemySide: .enemy,
            maxRange: 360.0,
            viewerFaction: .yanlong,
            viewerIsCavalryScout: true
        )
        XCTAssertEqual(spottedByCavalry, 7, "游骑兵侦察应在 210px 内识破密林伏兵")

        let spottedByWulin = grid.findNearestEnemy(
            fromX: 880.0,
            fromY: 1000.0,
            enemySide: .enemy,
            maxRange: 400.0,
            viewerFaction: .wulin,
            viewerIsCavalryScout: false
        )
        XCTAssertEqual(spottedByWulin, 7, "雾林猎手自带密林透视应在全射程内直接识破伏兵")

        // 零金零工兵死锁保底 + 战术暂停期间允许预下达包抄指令
        var engine = BattleSimulationEngine(
            context: RouteLaunchContext(playerFaction: .yanlong, enemyFaction: .tieying),
            deployment: BattleDeploymentConfig(
                customPlayerRoster: [
                    BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 6, initialFormation: .phalanxRect)
                ],
                customEnemyRoster: [
                    BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 2, initialFormation: .circleDefense)
                ],
                playerInitialGold: 0
            )
        )
        engine.setPaused(true)
        engine.stepLogicTick(deltaTime: 0.10)
        XCTAssertEqual(engine.elapsedSeconds, 0.0, accuracy: 1e-6, "战术暂停期间逻辑时钟不应推进")

        engine.issueSquadCommand(
            SquadCommandRequest(
                squadIds: [0],
                formation: .wedgeCharge,
                order: .flank,
                targetWorldX: 2800.0,
                targetWorldY: 1200.0
            )
        )
        XCTAssertEqual(engine.squads[0].formation, .wedgeCharge)
        XCTAssertEqual(engine.squads[0].order, .flank)
        XCTAssertFalse(engine.squads[0].waypoints.isEmpty, "侧翼包抄指令在暂停期也应立即生成弧线迂回航点")

        // 解除暂停推进 25.5s（大营被动产金 1.2/s * 25s = 30 < 35），触发免费应急民夫征召防经济死锁
        engine.setPaused(false)
        engine.issueSquadCommand(SquadCommandRequest(squadIds: [0], order: .holdGround, targetWorldX: 900.0, targetWorldY: 1200.0))
        for _ in 0..<255 {
            engine.stepLogicTick(deltaTime: 0.10)
        }
        let spawnedSappers = engine.soldiers.filter { $0.isActive && $0.hp > 0.0 && $0.side == .player && $0.unitType == .sapper }
        XCTAssertEqual(spawnedSappers.count, 1, "零工兵且金币不足 35 满 25s 后应自动免费补充 1 名应急辎重工兵")
    }

    // MARK: - 8. 敌兵近战围攻上阵主帅、战役重伤虚弱态注入与敌军初始士气修正验证

    func testEnemySoldiersEngagePlayerCommanderInMeleeAndCampaignModifiers() {
        var engine = BattleSimulationEngine(
            context: RouteLaunchContext(playerFaction: .yanlong, enemyFaction: .canglang),
            deployment: BattleDeploymentConfig(
                customPlayerRoster: [
                    BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 2, initialFormation: .circleDefense)
                ],
                customEnemyRoster: [
                    BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .lightCavalry, count: 8, initialFormation: .wedgeCharge)
                ],
                enemyInitialMoraleDelta: -25.0,
                isPlayerCommanderWeakened: true
            )
        )
        // 验证战役主帅重伤虚弱态与围点打援敌军 -25 士气真实生效
        XCTAssertEqual(engine.playerHero.vitalState, .woundedWeakened)
        XCTAssertEqual(engine.playerHero.attributeScale, 0.75, accuracy: 1e-6)
        let enemySq = engine.squads.first { $0.side == .enemy }!
        XCTAssertEqual(enemySq.morale, GameConstants.moraleBase - 25.0, accuracy: 1e-5)

        // 玩家切入英雄模式孤身迎向敌方骑兵前锋，验证敌方近战士兵可真实围攻扣减主帅生命值
        XCTAssertTrue(engine.toggleControlMode())
        let startHeroHp = engine.playerHero.hp
        for _ in 0..<240 where engine.outcome == .ongoing {
            let targetSq = engine.squads.first { $0.side == .enemy }!
            let dx = targetSq.anchorX - engine.playerHero.x
            let dy = targetSq.anchorY - engine.playerHero.y
            let len = max(1.0, hypot(dx, dy))
            engine.updateHeroInput(
                HeroControlInputState(
                    moveAxisX: dx / len,
                    moveAxisY: dy / len,
                    aimWorldX: targetSq.anchorX,
                    aimWorldY: targetSq.anchorY,
                    isPrimaryAttackHeld: false,
                    isSecondaryBlockHeld: false
                )
            )
            engine.stepLogicTick(deltaTime: 0.05)
            if engine.playerHero.hp < startHeroHp {
                break
            }
        }
        XCTAssertLessThan(engine.playerHero.hp, startHeroHp, "上阵主帅冲入敌阵不格挡时应真实承受敌兵近战劈刺伤害")
    }
}
