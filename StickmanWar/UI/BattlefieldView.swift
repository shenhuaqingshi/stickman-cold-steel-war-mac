import SpriteKit
import SwiftUI

/// 核心路由 4：冷兵器大战场与主帅亲自上阵实时交锋页（承载 SpriteKit 4800×2400 / 5600×2600 真刀真枪模拟与 4Hz 节流双视角指挥台）
public struct BattlefieldView: View {
    @Bindable var router: AppRouter

    @State private var sceneInstance: BattlefieldSKScene?
    @State private var syncPacket: BattlefieldUiSyncPacket?
    @State private var interactionTip: String = "大战已启：左键框选分队，右键点地面机动/点敌军集火，[Space] 暂停布阵，随时按 [Tab] 提刀上阵杀敌！"
    @State private var showEscapeMenu: Bool = false
    @State private var concludedSummary: PostBattleSettlementSummary? = nil
    @State private var recruitUseShamoMerc: Bool = false

    private var hud: BattleHudSnapshot {
        syncPacket?.hud ?? BattleHudSnapshot()
    }

    private var legalRecruitUnits: [UnitStaticStats] {
        UnitConfig.recruitableUnits(for: router.launchContext.playerFaction)
    }

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBattleHudBar

            ZStack(alignment: .topLeading) {
                if let scene = sceneInstance {
                    SpriteView(scene: scene)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                }

                // 左上角轻量实时战况与 AI 黑板态势浮层
                tacticalTelemetryOverlay
                    .padding(12)

                // 终局胜负战果横幅浮层
                if let finalSummary = concludedSummary {
                    battleConcludedOverlay(finalSummary)
                }

                // Esc 战场军务暂停菜单浮层
                if showEscapeMenu && concludedSummary == nil {
                    escapeTacticalMenuOverlay
                }
            }

            bottomCommandDeck
        }
        .onAppear {
            initializeOrSyncBattleScene(forceRecreate: false)
        }
        .onChange(of: router.pendingBattleDeployment.randomSeed) { _, _ in
            concludedSummary = nil
            showEscapeMenu = false
            initializeOrSyncBattleScene(forceRecreate: true)
        }
        .onChange(of: router.userSettings) { _, updated in
            applyUserSettings(updated, to: sceneInstance)
        }
    }

    // MARK: - 场景创建与回调绑定

    private func initializeOrSyncBattleScene(forceRecreate: Bool) {
        if sceneInstance == nil || forceRecreate {
            let created = BattlefieldSKScene(
                context: router.launchContext,
                deployment: router.pendingBattleDeployment
            )
            applyUserSettings(router.userSettings, to: created)
            created.onInteractionFeedback = { msg in
                interactionTip = msg
            }
            created.onUiPacketSynced = { packet in
                syncPacket = packet
            }
            created.onRequestToggleEscapeMenu = {
                toggleEscapeMenu()
            }
            created.onBattleConcluded = { summary in
                concludedSummary = summary
            }
            sceneInstance = created
        } else {
            applyUserSettings(router.userSettings, to: sceneInstance)
            sceneInstance?.focusResponder()
        }
    }

    private func applyUserSettings(_ settings: GameUserSettings, to scene: BattlefieldSKScene?) {
        guard let scene else { return }
        scene.preferredFps = settings.targetFps
        scene.enableFarLod = settings.enableFarLod
        scene.invertScrollZoom = settings.invertScrollZoom
        scene.keyboardPanSpeed = settings.cameraEdgePanSpeed
        scene.showDamageNumbers = settings.showDamageNumbers
        scene.enableEdgeCursorPan = settings.enableEdgeCursorPan
    }

    private func toggleEscapeMenu() {
        showEscapeMenu.toggle()
        sceneInstance?.setBattlePaused(showEscapeMenu)
        if !showEscapeMenu {
            sceneInstance?.focusResponder()
        }
    }

    // MARK: - 顶部 4Hz 节流战场态势栏

    private var topBattleHudBar: some View {
        let mins = Int(hud.elapsedSeconds) / 60
        let secs = Int(hud.elapsedSeconds) % 60
        let timeStr = String(format: "%02d:%02d", mins, secs)
        let siegeRemain = max(0, Int(router.pendingBattleDeployment.siegeHoldTargetSeconds - hud.elapsedSeconds))

        let rationBadge: (text: String, color: Color) = {
            switch hud.rationStage {
            case .abundant: return ("粮 \(Int(hud.grain))", .orange)
            case .warning: return ("⚠️ 余粮告警 \(Int(hud.grain))", .yellow)
            case .hungry: return ("🟠 断粮饥饿(-0.8士气/s)", .orange)
            case .starving: return ("🚨 饥溃崩盘(-1.8士气/s)", .red)
            }
        }()

        let heroStateText: String = {
            switch hud.heroVitalState {
            case .healthyActive:
                return "主帅 \(Int(hud.heroHp))/\(Int(hud.heroMaxHp))"
            case .recoveringInCamp:
                let rem = Int(syncPacket?.heroMedicalRemainingSec ?? 0)
                return "⛺ 医帐包扎(\(rem)s·士气锁65)"
            case .woundedWeakened:
                return "⚠️ 主帅虚弱 \(Int(hud.heroHp))/\(Int(hud.heroMaxHp))"
            case .fallenMartyred:
                return "💀 主帅殉国"
            }
        }()

        return HStack(spacing: 10) {
            Button("军务 (Esc)") {
                toggleEscapeMenu()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 6) {
                Text(timeStr)
                    .font(.callout.monospacedDigit().bold())
                if router.launchContext.scenarioType == .siegeDefense {
                    Text("坚守余 \(siegeRemain)s")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.cyan)
                }
            }

            Divider().frame(height: 16)

            HStack(spacing: 10) {
                Text("金 \(hud.gold)").foregroundStyle(.yellow)
                Text("木 \(hud.wood)").foregroundStyle(.green)
                Text(rationBadge.text).foregroundStyle(rationBadge.color)
            }
            .font(.caption.monospacedDigit().bold())

            Divider().frame(height: 16)

            HStack(spacing: 8) {
                Text("我军 \(hud.playerAliveCount)（人口\(hud.playerPopUsed)/\(hud.playerPopCap)）")
                    .foregroundStyle(.green)
                Text("vs 敌 \(hud.enemyAliveCount)")
                    .foregroundStyle(.red)
                Text("士气 \(Int(hud.averagePlayerMorale))")
                    .foregroundStyle(hud.averagePlayerMorale < 35 ? .red : .cyan)
                Text(heroStateText)
                    .foregroundStyle(hud.heroVitalState == .healthyActive ? .yellow : .orange)
            }
            .font(.caption.monospacedDigit().bold())

            Spacer()

            Button(hud.garrisonBellActive ? "🔔 解除警钟(B)" : "🔔 本阵警钟(B)") {
                sceneInstance?.toggleGarrisonBell()
                sceneInstance?.focusResponder()
            }
            .buttonStyle(.bordered)
            .tint(hud.garrisonBellActive ? .red : .secondary)
            .controlSize(.small)

            let switchLabel: String = {
                if hud.switchCooldownRemaining > 0.05 {
                    return String(format: "视角冷却 %.1fs", hud.switchCooldownRemaining)
                }
                return hud.controlMode == .rtsCommander ? "⚔️ 亲自上阵 (Tab)" : "🗺 统帅全局 (Tab)"
            }()
            Button(switchLabel) {
                _ = sceneInstance?.requestToggleControlMode()
                sceneInstance?.focusResponder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(hud.heroVitalState == .recoveringInCamp || hud.heroVitalState == .fallenMartyred || hud.switchCooldownRemaining > 0.05)

            let pauseKeyHint = hud.controlMode == .rtsCommander ? "Space" : "P"
            Button(hud.isPaused ? "▶️ 继续(\(pauseKeyHint))" : "⏸ 暂停(\(pauseKeyHint))") {
                sceneInstance?.toggleBattlePause()
                sceneInstance?.focusResponder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - 左上角战术反馈与 AI 指挥黑板透视

    private var tacticalTelemetryOverlay: some View {
        let aiDesc: String = {
            if let sp = syncPacket?.aiSiegePhase {
                switch sp {
                case .attackerArtilleryPrep: return "攻城阶段1·重器拆塔"
                case .attackerMultiLadder: return "攻城阶段2·云梯破门"
                case .attackerBreachExploit: return "攻城阶段3·铁骑突瓮城"
                case .defenderWallFocusFire: return "守城阶段1·强弩点杀工兵"
                case .defenderGatePlugPhalanx: return "守城阶段2·枪盾死堵城门"
                case .defenderSallyDestroySiege: return "守城阶段3·侧门奇袭烧投石"
                }
            }
            switch syncPacket?.aiDoctrine ?? .hammerAndAnvil {
            case .hammerAndAnvil: return "锤砧两翼包抄"
            case .highGroundHedgehog: return "高地刺猬防反"
            case .feignedRetreatAmbush: return "诈败诱敌入伏"
            case .reserveBreakthrough: return "总预备队决胜突击"
            case .antiKiteEscort: return "反风筝单队驱离"
            }
        }()

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(hud.controlMode == .rtsCommander ? "【RTS 统帅视角】" : "【主帅英雄亲自上阵 · 斩敌 \(syncPacket?.heroKills ?? 0)】")
                    .font(.caption.bold())
                    .foregroundStyle(.yellow)
                Text("敌帅条令：\(aiDesc)")
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                if let fervor = syncPacket?.bloodMoonFervorRemaining, fervor > 0 {
                    Text("🩸 血月狂热 \(Int(fervor))s")
                        .font(.caption2.bold())
                        .foregroundStyle(.pink)
                }
            }
            Text(interactionTip)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.68)))
    }

    // MARK: - 底部双模式动态指挥台（含实时编队选择、全套 9 战术指令、本阵增援训练与英雄战技冷却）

    private var bottomCommandDeck: some View {
        VStack(spacing: 6) {
            if hud.controlMode == .rtsCommander {
                // 第一行：我方场上分队实时状态卡片 + 本阵增援招募菜单
                HStack(spacing: 8) {
                    Button("全选(~)") {
                        sceneInstance?.selectAllCombatSquads()
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            let selSet = Set(syncPacket?.selectedSquadIds ?? [])
                            ForEach(Array((syncPacket?.playerSquads ?? []).enumerated()), id: \.element.id) { idx, sq in
                                if sq.aliveCount > 0 {
                                    let isSel = selSet.contains(sq.id)
                                    Button {
                                        sceneInstance?.selectSingleSquad(sq.id, centerCamera: isSel)
                                        sceneInstance?.focusResponder()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("[F\(min(6, idx + 1))] \(sq.unitName)×\(sq.aliveCount)")
                                                .font(.caption2.bold())
                                            Text(sq.isRouting ? "🏳️溃" : "士\(Int(sq.morale))")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(sq.isRouting ? .red : (sq.morale < 40 ? .yellow : .green))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(isSel ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.14))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(isSel ? Color.yellow : Color.clear, lineWidth: 1.4)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Spacer()

                    if router.launchContext.playerFaction == .wulin {
                        Menu("🌲 布设陷阱(25木)") {
                            Button("部署绊马索（坠马眩晕敌骑 3s）") {
                                sceneInstance?.deployWulinTrap(.tripwire)
                                sceneInstance?.focusResponder()
                            }
                            Button("部署尖刺陷坑（穿甲毒伤减速）") {
                                sceneInstance?.deployWulinTrap(.spikePit)
                                sceneInstance?.focusResponder()
                            }
                        }
                        .controlSize(.small)
                    }

                    if router.launchContext.playerFaction == .shamo {
                        Toggle("纯金雇兵", isOn: $recruitUseShamoMerc)
                            .toggleStyle(.checkbox)
                            .font(.caption2)
                    }

                    Menu("⛺ 本阵招募增援 (队列 \(syncPacket?.trainingQueueCount ?? 0))") {
                        ForEach(legalRecruitUnits) { u in
                            Button("\(u.name)（金\(u.cost.gold)/木\(u.cost.wood)/粮\(u.cost.grain) · 人口\(u.popCap)）") {
                                sceneInstance?.recruitReinforcement(
                                    unitType: u.id,
                                    useMercenaryGold: router.launchContext.playerFaction == .shamo && recruitUseShamoMerc
                                )
                                sceneInstance?.focusResponder()
                            }
                        }
                    }
                    .controlSize(.small)
                }

                // 第二行：4 阵型 + 9 战术指令 + 复位镜头
                HStack(spacing: 6) {
                    Text("阵型:").font(.caption2.bold())
                    ForEach(FormationType.allCases) { f in
                        Button("[\(f.shortcutHint)]\(f.displayName)") {
                            sceneInstance?.applyFormationToSelection(f)
                            sceneInstance?.focusResponder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider().frame(height: 16)

                    Text("军令:").font(.caption2.bold())
                    ForEach(TacticalOrder.allCases) { order in
                        Button("[\(order.rtsShortcutKey)]\(order.displayName)") {
                            sceneInstance?.applyTacticalOrderToSelection(order)
                            sceneInstance?.focusResponder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()

                    Button("居中镜头") {
                        sceneInstance?.resetCameraToCenter()
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                // 亲自上阵英雄模式专属动作武器栏与实时战技冷却条
                HStack(spacing: 10) {
                    Text("随身兵刃:").font(.caption.bold())
                    ForEach(Array(HeroWeaponType.allCases.enumerated()), id: \.element.id) { idx, weapon in
                        let quiverInfo = weapon == .heavyWarbow ? " (\(hud.heroRemainingArrows)/\(GameConstants.heroWarbowQuiverCap)箭)" : ""
                        Button("[\(idx + 1)] \(weapon.displayName)\(quiverInfo)") {
                            sceneInstance?.switchHeroWeapon(weapon)
                            sceneInstance?.focusResponder()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(hud.heroActiveWeapon == weapon ? .accentColor : .secondary)
                        .controlSize(.small)
                    }

                    Divider().frame(height: 18)

                    let cd1 = syncPacket?.heroBreakthroughCd ?? 0.0
                    Button(cd1 > 0.05 ? String(format: "[Space] 破阵突击 (%.1fs)", cd1) : "[Space] 破阵突击 (就绪)") {
                        sceneInstance?.triggerHeroSkill(.breakthroughCharge)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(.bordered)
                    .tint(cd1 <= 0.05 ? .orange : .secondary)
                    .disabled(cd1 > 0.05)
                    .controlSize(.small)

                    let cd2 = syncPacket?.heroBulwarkCd ?? 0.0
                    Button(cd2 > 0.05 ? String(format: "[E] 铁壁横戈 (%.1fs)", cd2) : "[E] 铁壁横戈 (就绪)") {
                        sceneInstance?.triggerHeroSkill(.ironBulwark)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(.bordered)
                    .tint(cd2 <= 0.05 ? .cyan : .secondary)
                    .disabled(cd2 > 0.05)
                    .controlSize(.small)

                    let cd3 = syncPacket?.heroWarCryCd ?? 0.0
                    Button(cd3 > 0.05 ? String(format: "[R] 三军战吼 (%.1fs)", cd3) : "[R] 三军战吼 (+18士气·唤醒溃军)") {
                        sceneInstance?.triggerHeroSkill(.grandWarCry)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(.bordered)
                    .tint(cd3 <= 0.05 ? .yellow : .secondary)
                    .disabled(cd3 > 0.05)
                    .controlSize(.small)

                    Spacer()

                    Text("WASD/方向键走位 · 鼠标瞄准 · 左键攻/蓄射 · 右键0.25s弹反")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - 终局胜负战果浮层与 Esc 战场军务菜单浮层

    private func battleConcludedOverlay(_ summary: PostBattleSettlementSummary) -> some View {
        let title: String = {
            switch summary.outcomeReason {
            case .enemyBaseDestroyed: return "🏆 大捷 · 攻破敌军本阵大营！"
            case .enemyArmyRouted: return "🏆 大捷 · 敌军全线崩溃溃逃！"
            case .siegeDefenseHeld: return "🛡 守城大捷 · 雄关屹立不倒！"
            case .playerCommanderMartyred: return "💔 败北 · 主帅阵前殉国 / 本阵失守"
            case .playerArmyRouted: return "🏳️ 惜败 · 我军士气崩溃退守"
            case .truceNegotiated: return "🤝 阵前停火 · 两军罢兵休战"
            case .ongoing: return "战局结算"
            }
        }()

        return ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(summary.isVictory ? .yellow : .orange)

                Text("斩敌 \(summary.enemyKilled) · 俘虏 \(summary.capturedPrisoners) · 我军阵亡 \(summary.playerKilled)（医帐救回伤兵 +\(summary.playerWoundedRecovered)）")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white)

                Text("缴获物资：金 +\(summary.lootedGold) / 木 +\(summary.lootedWood) / 粮 +\(summary.lootedGrain) · 主帅历练 +\(summary.commanderExpGained) EXP")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button("检阅完整军功战报 · 进入战后结算页 ›") {
                    router.completeBattleAndShowResult(summary)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.5), lineWidth: 1.5))
        }
    }

    private var escapeTacticalMenuOverlay: some View {
        ZStack {
            Color.black.opacity(0.52)
            VStack(spacing: 12) {
                Text("帅帐军务暂停菜单")
                    .font(.title3.bold())

                Button("继续战斗 (Esc)") {
                    toggleEscapeMenu()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if router.launchContext.entryMode == .campaign {
                    Button("派遣阵前使者赔款 200 金请求停火") {
                        let offer = PeaceOfferTerms(
                            proposer: router.launchContext.playerFaction,
                            target: router.launchContext.enemyFaction,
                            goldIndemnity: min(200, router.campaignEngine.factionState(for: router.launchContext.playerFaction).gold),
                            grainTributePerTurn: 15,
                            cededNodeIds: [],
                            truceTurns: 5
                        )
                        let outcome = router.campaignEngine.proposePeaceOffer(offer)
                        switch outcome {
                        case .accepted:
                            showEscapeMenu = false
                            if let summary = sceneInstance?.concludeBattleByTruceAndSummarize() {
                                router.completeBattleAndShowResult(summary)
                            }
                        case .counterOffer(_, let counter):
                            interactionTip = "敌帅索要更高停火筹码：赔金 \(counter.goldIndemnity)、岁粮 \(counter.grainTributePerTurn)/回合（可在大地图外交台细谈）"
                            toggleEscapeMenu()
                        case .rejectedBreakdown(_, let reason):
                            interactionTip = "阵前求和被拒（敌获士气激励）：\(reason)"
                            toggleEscapeMenu()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Button("鸣金收兵（按当前真实伤亡结算撤退）") {
                    showEscapeMenu = false
                    if let cur = sceneInstance?.buildCurrentSettlementSummary() {
                        let retreatSummary = PostBattleSettlementSummary(
                            scenarioType: cur.scenarioType,
                            playerFaction: cur.playerFaction,
                            enemyFaction: cur.enemyFaction,
                            isVictory: false,
                            outcomeReason: .playerArmyRouted,
                            durationSeconds: cur.durationSeconds,
                            playerKilled: cur.playerKilled,
                            playerWoundedRecovered: cur.playerWoundedRecovered,
                            enemyKilled: cur.enemyKilled,
                            capturedPrisoners: 0,
                            lootedGold: 0,
                            lootedWood: 0,
                            lootedGrain: 0,
                            commanderExpGained: max(30, cur.commanderExpGained / 2)
                        )
                        router.completeBattleAndShowResult(retreatSummary)
                    }
                }
                .buttonStyle(.bordered)

                Button("兵种克制与键鼠速查 (⌘/)") {
                    router.showQuickHelpSheet = true
                }
                .buttonStyle(.bordered)

                Button("返回上一页（不保存本场临时进度）") {
                    showEscapeMenu = false
                    router.goBack()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(26)
            .frame(width: 390)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        }
    }
}
