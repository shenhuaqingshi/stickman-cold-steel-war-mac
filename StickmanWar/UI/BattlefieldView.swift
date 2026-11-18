import AppKit
import SpriteKit
import SwiftUI

/// 核心路由 4：帝国冷兵器大战场实时交锋与《指尖帝国 × 罗马帝国》RTS 营建指挥台
/// 包含：顶部时代演进与资源状态带、中央高清 SpriteKit 战场、右下交互式战术雷达小地图、底部三区（营建锻造 / 军团募兵 / 古战阵型军令）指挥台。
public struct BattlefieldView: View {
    private enum LeftDeckTab: String, CaseIterable, Identifiable {
        case buildings = "帝国营建"
        case blacksmith = "铁匠锻造"
        var id: String { rawValue }
    }

    @Bindable var router: AppRouter

    @State private var sceneInstance: BattlefieldSKScene?
    @State private var syncPacket: BattlefieldUiSyncPacket?
    @State private var interactionTip: String = "号角已鸣：左键框选军团，【按住右键拖拽】拉设古罗马战线，左下营建农庄/兵营/铁匠铺，按 [Tab] 提刀上阵！"
    @State private var showEscapeMenu: Bool = false
    @State private var concludedSummary: PostBattleSettlementSummary? = nil
    @State private var recruitUseShamoMerc: Bool = false
    @State private var leftDeckTab: LeftDeckTab = .buildings
    @State private var isAudioMuted: Bool = BattleAudioEngine.shared.isMuted

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
            topImperialHudRibbon

            ZStack(alignment: .topLeading) {
                if let scene = sceneInstance {
                    SpriteView(scene: scene)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ImperialPalette.obsidianDeep
                }

                // 左上角轻量战场战报与文明态势浮窗
                tacticalTelemetryOverlay
                    .padding(12)

                // 右下角《指尖帝国 / 帝国时代》式实时交互战术雷达小地图
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        interactiveRadarMinimap
                            .padding(12)
                    }
                }

                if let finalSummary = concludedSummary {
                    battleConcludedOverlay(finalSummary)
                }

                if showEscapeMenu && concludedSummary == nil {
                    escapeTacticalMenuOverlay
                }
            }

            bottomImperialCommandConsole
        }
        .background(ImperialPalette.obsidianDeep)
        .onAppear {
            BattleAudioEngine.shared.masterVolume = Float(router.userSettings.masterVolume * router.userSettings.sfxVolume)
            initializeOrSyncBattleScene(forceRecreate: false)
        }
        .onChange(of: router.pendingBattleDeployment.randomSeed) { _, _ in
            concludedSummary = nil
            showEscapeMenu = false
            initializeOrSyncBattleScene(forceRecreate: true)
        }
        .onChange(of: router.userSettings) { _, updated in
            BattleAudioEngine.shared.masterVolume = Float(updated.masterVolume * updated.sfxVolume)
            applyUserSettings(updated, to: sceneInstance)
        }
    }

    // MARK: - 场景创建与绑定

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

    // MARK: - 顶部帝国资源、四时代演进、倍速与主帅亲征状态栏

    private var topImperialHudRibbon: some View {
        let mins = Int(hud.elapsedSeconds) / 60
        let secs = Int(hud.elapsedSeconds) % 60
        let timeStr = String(format: "%02d:%02d", mins, secs)

        return HStack(spacing: 10) {
            // 军务菜单与时钟
            Button {
                toggleEscapeMenu()
            } label: {
                Label("军务", systemImage: "line.3.horizontal")
            }
            .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

            Text(timeStr)
                .font(.system(.callout, design: .monospaced).bold())
                .foregroundStyle(ImperialPalette.parchmentText)
                .frame(width: 48)

            // 四时代演进勋章与一键升级时代按钮
            HStack(spacing: 6) {
                Text("时代 \(hud.currentAge.romanNumeral)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ImperialPalette.goldGradient))
                    .foregroundStyle(ImperialPalette.obsidianDeep)

                if let targetAge = hud.advancingToAge {
                    HStack(spacing: 4) {
                        ProgressView(value: hud.ageAdvanceProgress)
                            .frame(width: 48)
                            .tint(ImperialPalette.imperialGold)
                        Text("演进 \(targetAge.romanNumeral) \(Int(hud.ageAdvanceProgress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(ImperialPalette.imperialGoldBright)
                    }
                } else if let nextAge = hud.currentAge.nextAge {
                    let c = nextAge.advanceCost
                    Button {
                        sceneInstance?.triggerAgeAdvancement()
                        sceneInstance?.focusResponder()
                    } label: {
                        Text("⬆ 升时代\(nextAge.romanNumeral) (金\(c.gold)/木\(c.wood))")
                    }
                    .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
                    .help("演进至【\(nextAge.displayName)】：全军攻击 +\(Int((nextAge.attackMultiplierBonus - 1.0) * 100))%、人口上限 +\(nextAge.popCapBonus)，解锁高阶马厩/箭塔/攻城所与铁匠科技")
                } else {
                    Text("巅峰霸业")
                        .font(.caption2.bold())
                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                }
            }

            Divider().frame(height: 20).overlay(ImperialPalette.bronzeBorder.opacity(0.4))

            // 金 / 木 / 粮 / 人口 四维帝国资源表
            HStack(spacing: 11) {
                resourcePill(symbol: "bitcoinsign.circle.fill", color: .yellow, label: "\(hud.gold)")
                resourcePill(symbol: "tree.fill", color: .green, label: "\(hud.wood)")
                resourcePill(
                    symbol: "leaf.circle.fill",
                    color: hud.rationStage == .abundant ? ImperialPalette.imperialGold : .red,
                    label: "\(Int(hud.grain)) (\(rationStageShortLabel(hud.rationStage)))"
                )
                resourcePill(
                    symbol: "person.3.fill",
                    color: hud.playerPopUsed >= hud.playerPopCap ? .orange : .cyan,
                    label: "\(hud.playerPopUsed)/\(hud.playerPopCap)"
                )
            }

            Spacer(minLength: 4)

            // 空闲民夫定位 + 警戒钟
            Button {
                sceneInstance?.focusIdleOrNearestSapper()
                sceneInstance?.focusResponder()
            } label: {
                Text("🔨 民夫\(hud.idleSapperCount > 0 ? "(\(hud.idleSapperCount)闲)" : "") [.]")
            }
            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: hud.idleSapperCount > 0, isCompact: true))

            Button {
                sceneInstance?.toggleGarrisonBell()
                sceneInstance?.focusResponder()
            } label: {
                Text(hud.garrisonBellActive ? "🔔 解除警钟 [B]" : "🔔 警戒钟 [B]")
            }
            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: hud.garrisonBellActive, isCompact: true))

            // 战斗节奏倍速切换 [0.5x | 1x | 1.5x | 2x]
            HStack(spacing: 3) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { spd in
                    let curSpd = syncPacket?.simulationSpeed ?? 1.0
                    Button("\(spd == 1.0 ? "1x" : (spd == 2.0 ? "2x" : String(format: "%.1fx", spd)))") {
                        sceneInstance?.simulationSpeedMultiplier = spd
                        BattleAudioEngine.shared.play(.uiClick)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: abs(curSpd - spd) < 0.05, isCompact: true))
                }
            }

            // 音效开关与暂停
            Button {
                isAudioMuted.toggle()
                BattleAudioEngine.shared.isMuted = isAudioMuted
                sceneInstance?.focusResponder()
            } label: {
                Image(systemName: isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

            Button {
                sceneInstance?.toggleBattlePause()
                sceneInstance?.focusResponder()
            } label: {
                Image(systemName: hud.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: hud.isPaused, isCompact: true))

            // 灵魂双视角切换按钮：[Tab] 主帅提刀亲征
            Button {
                _ = sceneInstance?.requestToggleControlMode()
                sceneInstance?.focusResponder()
            } label: {
                Text(hud.controlMode == .heroAction ? "🗺 切回统帅 [Tab]" : "⚔️ 主帅亲征 [Tab]")
            }
            .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
            .disabled(hud.heroVitalState == .recoveringInCamp || hud.heroVitalState == .fallenMartyred)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(ImperialPalette.obsidianCard)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ImperialPalette.bronzeBorder.opacity(0.55)).frame(height: 1)
        }
    }

    private func resourcePill(symbol: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.caption)
            Text(label)
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(ImperialPalette.parchmentText)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.42)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.30), lineWidth: 0.8))
    }

    private func rationStageShortLabel(_ stage: BattlefieldRationStage) -> String {
        switch stage {
        case .abundant: return "充沛"
        case .warning: return "告急!"
        case .hungry: return "断粮!"
        case .starving: return "饥溃!!"
        }
    }

    // MARK: - 左上角战报态势浮窗 & 右下角交互式战术雷达小地图

    private var tacticalTelemetryOverlay: some View {
        let pCfg = FactionConfig.config(for: router.launchContext.playerFaction)
        let eCfg = FactionConfig.config(for: router.launchContext.enemyFaction)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: pCfg?.primaryColorHex ?? "#C62828")).frame(width: 8, height: 8)
                Text("\(pCfg?.name ?? "") \(hud.playerAliveCount)人 (士气\(Int(hud.averagePlayerMorale)))")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(ImperialPalette.parchmentText)
                Text("VS")
                    .font(.caption2.bold())
                    .foregroundStyle(ImperialPalette.imperialGold)
                Circle().fill(Color(hex: eCfg?.primaryColorHex ?? "#1565C0")).frame(width: 8, height: 8)
                Text("\(eCfg?.name ?? "") \(hud.enemyAliveCount)人 (时代\(hud.enemyCurrentAge.romanNumeral))")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(ImperialPalette.parchmentText)
            }

            HStack(spacing: 10) {
                Text("主帅 HP \(Int(hud.heroHp))/\(Int(hud.heroMaxHp))")
                    .foregroundStyle(hud.heroVitalState == .recoveringInCamp ? .orange : ImperialPalette.jadeSupply)
                Text("锻造：刃Lv.\(hud.meleeForgeLevel) · 甲Lv.\(hud.armorTemperLevel) · 箭Lv.\(hud.fletchingLevel)")
                    .foregroundStyle(ImperialPalette.imperialGold)
                if let packet = syncPacket, packet.bloodMoonFervorRemaining > 0.1 {
                    Text("🩸 血月狂热 \(Int(packet.bloodMoonFervorRemaining))s")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption2.monospacedDigit())

            Text(interactionTip)
                .font(.caption)
                .foregroundStyle(ImperialPalette.imperialGoldBright)
                .lineLimit(2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: 530, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(ImperialPalette.obsidianDeep.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.55), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private var interactiveRadarMinimap: some View {
        let mapW: CGFloat = 196
        let mapH: CGFloat = 104
        let dots = syncPacket?.minimapDots ?? []
        let camCX = syncPacket?.cameraNormCenterX ?? 0.5
        let camCY = syncPacket?.cameraNormCenterY ?? 0.5
        let camNW = syncPacket?.cameraNormWidth ?? 0.3
        let camNH = syncPacket?.cameraNormHeight ?? 0.3

        return VStack(alignment: .trailing, spacing: 3) {
            Text("战术沙盘雷达（点击/拖拽跳镜）")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ImperialPalette.parchmentMuted)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0.10, green: 0.13, blue: 0.09).opacity(0.92))

                Canvas { ctx, sz in
                    // 中路古道参考线
                    var road = Path()
                    road.move(to: CGPoint(x: 8, y: sz.height * 0.5))
                    road.addLine(to: CGPoint(x: sz.width - 8, y: sz.height * 0.5))
                    ctx.stroke(road, with: .color(Color.brown.opacity(0.45)), lineWidth: 2)

                    for d in dots {
                        let px = CGFloat(d.normX) * sz.width
                        let py = CGFloat(d.normY) * sz.height
                        if d.isResource {
                            let rect = CGRect(x: px - 2.2, y: py - 2.2, width: 4.4, height: 4.4)
                            ctx.fill(Path(ellipseIn: rect), with: .color(.yellow.opacity(0.85)))
                        } else if d.isBuilding {
                            let rect = CGRect(x: px - 3.5, y: py - 3.5, width: 7.0, height: 7.0)
                            ctx.fill(Path(rect), with: .color(d.isPlayer ? .green : .red))
                        } else {
                            let rect = CGRect(x: px - 2.8, y: py - 2.8, width: 5.6, height: 5.6)
                            ctx.fill(Path(ellipseIn: rect), with: .color(d.isPlayer ? .cyan : .orange))
                        }
                    }

                    let vw = max(18, CGFloat(camNW) * sz.width)
                    let vh = max(14, CGFloat(camNH) * sz.height)
                    let vx = min(sz.width - vw, max(0, CGFloat(camCX) * sz.width - vw * 0.5))
                    let vy = min(sz.height - vh, max(0, CGFloat(camCY) * sz.height - vh * 0.5))
                    ctx.stroke(Path(CGRect(x: vx, y: vy, width: vw, height: vh)), with: .color(.white.opacity(0.9)), lineWidth: 1.3)
                }
                .frame(width: mapW, height: mapH)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let nx = Double(val.location.x / mapW)
                            let ny = Double(val.location.y / mapH)
                            sceneInstance?.jumpCameraToNormalized(normX: nx, normY: ny)
                        }
                        .onEnded { _ in
                            sceneInstance?.focusResponder()
                        }
                )
            }
            .frame(width: mapW, height: mapH)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ImperialPalette.imperialGold.opacity(0.70), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.5), radius: 5)
        }
    }

    // MARK: - 底部三区帝国指挥台（左：指尖营建&铁匠科技 | 中：军团鹰旗与募兵队列 | 右：五阵型与九军令 / 主帅战技）

    private var bottomImperialCommandConsole: some View {
        HStack(alignment: .top, spacing: 12) {
            if hud.controlMode == .rtsCommander {
                leftConstructionAndForgePanel
                    .frame(width: 340)

                Divider().frame(height: 146).overlay(ImperialPalette.bronzeBorder.opacity(0.35))

                centerCohortsAndRecruitPanel
                    .frame(maxWidth: .infinity)

                Divider().frame(height: 146).overlay(ImperialPalette.bronzeBorder.opacity(0.35))

                rightFormationsAndTacticsPanel
                    .frame(width: 390)
            } else {
                heroActionConsolePanel
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(height: 166)
        .background(ImperialPalette.obsidianCard)
        .overlay(alignment: .top) {
            Rectangle().fill(ImperialPalette.imperialGold.opacity(0.50)).frame(height: 1.2)
        }
    }

    // 左区：指尖帝国式基地营建 + 铁匠铺三系攻防锻造
    private var leftConstructionAndForgePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(LeftDeckTab.allCases) { tab in
                    Button(tab.rawValue) {
                        leftDeckTab = tab
                        BattleAudioEngine.shared.play(.uiClick)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: leftDeckTab == tab, isCompact: true))
                }
                Spacer()
                if syncPacket?.pendingBuildKind != nil {
                    Button("取消选址") {
                        sceneInstance?.cancelPendingBuildPlacement()
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
                } else {
                    Text("Shift+点直接建")
                        .font(.system(size: 10))
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                }
            }

            if leftDeckTab == .buildings {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                    ForEach(SiegeStructureKind.constructibleBuildings) { kind in
                        let cost = kind.buildCost ?? ResourceCost(gold: 0, wood: 0, grain: 0)
                        let locked = hud.currentAge < kind.requiredAge
                        let isPicking = syncPacket?.pendingBuildKind == kind
                        Button {
                            let shiftPressed = NSEvent.modifierFlags.contains(.shift)
                            sceneInstance?.beginOrAutoConstructBuilding(kind, quickAutoPlace: shiftPressed)
                            sceneInstance?.focusResponder()
                        } label: {
                            VStack(spacing: 2) {
                                Text(kind.displayName)
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                                Text(locked ? "需时代\(kind.requiredAge.romanNumeral)" : "金\(cost.gold)·木\(cost.wood)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(locked ? .orange : ImperialPalette.parchmentMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isPicking ? ImperialPalette.imperialGold.opacity(0.32) : ImperialPalette.obsidianElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isPicking ? ImperialPalette.imperialGoldBright : ImperialPalette.bronzeBorder.opacity(0.45), lineWidth: 1)
                            )
                            .opacity(locked ? 0.58 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .help("\(kind.displayName)：\(kind.roleSummary)（点击后在战场左键落盘，按住 Shift 点击可自动选址建造）")
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(BlacksmithUpgradeTrack.allCases) { track in
                        let lvl: Int = {
                            switch track {
                            case .meleeForging: return hud.meleeForgeLevel
                            case .armorTempering: return hud.armorTemperLevel
                            case .fletchingcraft: return hud.fletchingLevel
                            }
                        }()
                        let nextCost = track.cost(forTargetLevel: min(3, lvl + 1))
                        HStack(spacing: 8) {
                            Image(systemName: track.iconSymbol)
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(track.displayName) Lv.\(lvl)/3")
                                    .font(.caption.bold())
                                    .foregroundStyle(ImperialPalette.parchmentText)
                                Text(track.summary(atLevel: max(1, lvl)))
                                    .font(.system(size: 10))
                                    .foregroundStyle(ImperialPalette.parchmentMuted)
                            }
                            Spacer()
                            if lvl < 3 {
                                Button("锻造 (金\(nextCost.gold)/木\(nextCost.wood))") {
                                    sceneInstance?.triggerBlacksmithUpgrade(track)
                                    sceneInstance?.focusResponder()
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
                            } else {
                                Text("已满级")
                                    .font(.caption2.bold())
                                    .foregroundStyle(ImperialPalette.jadeSupply)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.32)))
                    }
                }
            }
        }
    }

    // 中区：现役军团鹰旗卡 + 募兵与实时生产队列
    private var centerCohortsAndRecruitPanel: some View {
        let squads = syncPacket?.playerSquads.filter { $0.aliveCount > 0 } ?? []
        let selectedSet = Set(syncPacket?.selectedSquadIds ?? [])
        let queueItems = syncPacket?.trainingQueueItems ?? []

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("现役军团 (\(squads.count))")
                    .font(.caption.bold())
                    .foregroundStyle(ImperialPalette.imperialGold)
                Button("全选主力 [~]") {
                    sceneInstance?.selectAllCombatSquads()
                    sceneInstance?.focusResponder()
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                if router.launchContext.playerFaction == .wulin {
                    Button("绊马索") {
                        sceneInstance?.deployWulinTrap(.tripwire)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                    Button("尖刺坑") {
                        sceneInstance?.deployWulinTrap(.spikePit)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                }
                if router.launchContext.playerFaction == .shamo {
                    Toggle("纯金秒募雇佣兵", isOn: $recruitUseShamoMerc)
                        .toggleStyle(.checkbox)
                        .font(.caption2)
                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                }

                Spacer()

                // 实时训练队列图标条（点击可取消退钱）
                if !queueItems.isEmpty {
                    HStack(spacing: 4) {
                        Text("队列:")
                            .font(.caption2)
                            .foregroundStyle(ImperialPalette.parchmentMuted)
                        ForEach(Array(queueItems.prefix(5).enumerated()), id: \.offset) { idx, item in
                            let uShort = UnitConfig.stats(for: item.unitType)?.name.prefix(2) ?? "兵"
                            Button("\(uShort) \(Int(ceil(item.remainingSeconds)))s ×") {
                                sceneInstance?.cancelQueueItem(at: idx)
                                sceneInstance?.focusResponder()
                            }
                            .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                            .help("点击取消该项招募并全额退还资源")
                        }
                    }
                }
            }

            // 军团编制横向卡片列
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(squads) { sq in
                        let isSel = selectedSet.contains(sq.id)
                        let stars = sq.veterancyStars > 0 ? String(repeating: "★", count: sq.veterancyStars) : ""
                        Button {
                            sceneInstance?.selectSingleSquad(sq.id, centerCamera: isSel)
                            sceneInstance?.focusResponder()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: UnitVisualSymbol.sfSymbol(for: sq.unitType))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                                    Text("\(stars)\(sq.unitName)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(ImperialPalette.parchmentText)
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    Text("\(sq.aliveCount)")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                                }
                                HStack(spacing: 4) {
                                    Text(sq.isRouting ? "溃逃!" : "士\(Int(sq.morale))")
                                        .foregroundStyle(sq.isRouting ? .red : ImperialPalette.jadeSupply)
                                    Text("· \(sq.formation.displayName)")
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
                                }
                                .font(.system(size: 9.5))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(width: 122, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSel ? ImperialPalette.legionCrimson.opacity(0.36) : ImperialPalette.obsidianElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(isSel ? ImperialPalette.imperialGoldBright : ImperialPalette.bronzeBorder.opacity(0.40), lineWidth: isSel ? 1.5 : 0.9)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 底部快捷募兵栏（支持 Shift+点击一次连招 5 名！）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(legalRecruitUnits) { u in
                        Button {
                            let batch = NSEvent.modifierFlags.contains(.shift) ? 5 : 1
                            sceneInstance?.recruitReinforcement(
                                unitType: u.id,
                                useMercenaryGold: recruitUseShamoMerc && router.launchContext.playerFaction == .shamo,
                                batchCount: batch
                            )
                            sceneInstance?.focusResponder()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: UnitVisualSymbol.sfSymbol(for: u.id))
                                    .font(.system(size: 10))
                                    .foregroundStyle(u.exclusiveFaction != nil ? ImperialPalette.imperialGoldBright : ImperialPalette.parchmentMuted)
                                Text("+ \(u.name) (金\(u.cost.gold))")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(u.exclusiveFaction != nil ? ImperialPalette.imperialGoldBright : ImperialPalette.parchmentText)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.42)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.45), lineWidth: 0.9))
                        }
                        .buttonStyle(.plain)
                        .help("\(u.name)：\(u.traitDesc)（消耗 金\(u.cost.gold)/木\(u.cost.wood)/粮\(u.cost.grain)，按住 Shift 点击一次连募 5 人！）")
                    }
                }
            }
        }
    }

    // 右区：五种古战阵型（含罗马龟甲阵）+ 九大奇正战术指令
    private var rightFormationsAndTacticsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("古战阵型 [1~5] 与奇正军令（可按住右键拖拽拉阵线）")
                    .font(.caption.bold())
                    .foregroundStyle(ImperialPalette.imperialGold)
                Spacer()
                Button("重置镜头") {
                    sceneInstance?.resetCameraToCenter()
                    sceneInstance?.focusResponder()
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
            }

            HStack(spacing: 4) {
                ForEach(FormationType.allCases) { f in
                    Button("[\(f.shortcutHint)]\(f.displayName)") {
                        sceneInstance?.applyFormationToSelection(f)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: f == .testudo, isCompact: true))
                    .help("\(f.displayName)：\(f.tacticalBrief)")
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                ForEach(TacticalOrder.allCases) { order in
                    Button("[\(order.rtsShortcutKey)]\(order.displayName)") {
                        sceneInstance?.applyTacticalOrderToSelection(order)
                        sceneInstance?.focusResponder()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                }
            }
        }
    }

    // 主帅亲征英雄动作操控台
    private var heroActionConsolePanel: some View {
        let p = syncPacket
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("⚔️ 主帅亲征随身三兵刃（数字键 1 / 2 / 3 切换）")
                    .font(.caption.bold())
                    .foregroundStyle(ImperialPalette.imperialGold)
                HStack(spacing: 8) {
                    ForEach(Array(HeroWeaponType.allCases.enumerated()), id: \.element.id) { idx, weapon in
                        let active = hud.heroActiveWeapon == weapon
                        Button {
                            sceneInstance?.switchHeroWeapon(weapon)
                            sceneInstance?.focusResponder()
                        } label: {
                            Text("[\(idx + 1)] \(weapon.displayName)\(weapon == .heavyWarbow ? " (\(hud.heroRemainingArrows)支)" : "")")
                        }
                        .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: active))
                    }
                }
                Text("操作：[WASD] 八向走位 · 鼠标瞄准 · 左键挥砍/突刺/0.9s满蓄力贯射 · 右键佩刀举盾（前 0.25s 精准弹反零伤震晕 1.5s！）")
                    .font(.caption2)
                    .foregroundStyle(ImperialPalette.parchmentMuted)
            }

            Divider().frame(height: 110).overlay(ImperialPalette.bronzeBorder.opacity(0.4))

            VStack(alignment: .leading, spacing: 6) {
                Text("🔥 统帅无双战技（主帅已斩敌 \(p?.heroKills ?? 0) 首级）")
                    .font(.caption.bold())
                    .foregroundStyle(ImperialPalette.imperialGold)
                HStack(spacing: 10) {
                    heroSkillButton(
                        title: "[Space] 破阵突击",
                        subtitle: "猛冲撞飞敌阵",
                        cd: p?.heroBreakthroughCd ?? 0
                    ) {
                        sceneInstance?.triggerHeroSkill(.breakthroughCharge)
                        sceneInstance?.focusResponder()
                    }

                    heroSkillButton(
                        title: "[E] 铁壁横戈",
                        subtitle: "2s弹箭+旋斩",
                        cd: p?.heroBulwarkCd ?? 0
                    ) {
                        sceneInstance?.triggerHeroSkill(.ironBulwark)
                        sceneInstance?.focusResponder()
                    }

                    heroSkillButton(
                        title: "[R] 三军战吼",
                        subtitle: "+18士气唤醒溃军",
                        cd: p?.heroWarCryCd ?? 0
                    ) {
                        sceneInstance?.triggerHeroSkill(.grandWarCry)
                        sceneInstance?.focusResponder()
                    }
                }
            }

            Spacer()
        }
    }

    private func heroSkillButton(title: String, subtitle: String, cd: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cd > 0.05 ? "\(title) (\(String(format: "%.1fs", cd)))" : title)
                    .font(.callout.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(ImperialPalette.parchmentMuted)
            }
        }
        .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
        .disabled(cd > 0.05)
    }

    // MARK: - 战场 Esc 军务菜单与胜负横幅浮层

    private var escapeTacticalMenuOverlay: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
            ImperialPanel(cornerRadius: 14, borderOpacity: 0.85, padding: 26) {
                VStack(spacing: 14) {
                    Text("战场统帅军务大帐")
                        .font(.title2.bold())
                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                    Text("战局已暂停 —— 可随时重返沙场、查阅克制宝典或议和收兵")
                        .font(.caption)
                        .foregroundStyle(ImperialPalette.parchmentMuted)

                    Button("▶ 继续指挥作战 (Esc)") {
                        toggleEscapeMenu()
                    }
                    .buttonStyle(ImperialCrimsonButtonStyle())

                    Button("📖 兵种克制与快捷键宝典 (⌘/)") {
                        router.showQuickHelpSheet = true
                    }
                    .buttonStyle(ImperialBronzeButtonStyle())

                    Button("🏳 阵前鸣金休战 · 进入军功结算") {
                        showEscapeMenu = false
                        if let summary = sceneInstance?.concludeBattleByTruceAndSummarize() {
                            router.completeBattleAndShowResult(summary)
                        }
                    }
                    .buttonStyle(ImperialBronzeButtonStyle())

                    Button("‹ 撤回主帅大帐（主菜单）") {
                        showEscapeMenu = false
                        router.returnToMainMenu()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle())
                }
                .frame(width: 340)
            }
        }
    }

    private func battleConcludedOverlay(_ summary: PostBattleSettlementSummary) -> some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
            ImperialPanel(cornerRadius: 16, borderOpacity: 0.90, padding: 28) {
                VStack(spacing: 14) {
                    Image(systemName: summary.isVictory ? "crown.fill" : "shield.slash.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(summary.isVictory ? ImperialPalette.imperialGoldBright : .red)

                    Text(summary.isVictory ? "🏆 三军凯旋 · 会战大捷！" : "⚔️ 鸣金收兵 · 战局落幕")
                        .font(.system(size: 28, weight: .black, design: .serif))
                        .foregroundStyle(summary.isVictory ? ImperialPalette.imperialGoldBright : .orange)

                    Text("歼敌 \(summary.enemyKilled) · 阵亡 \(summary.playerKilled)（医帐抢救归建 +\(summary.playerWoundedRecovered)）· 生擒战俘 \(summary.capturedPrisoners)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(ImperialPalette.parchmentText)

                    Text("缴获军资：黄金 +\(summary.lootedGold)  |  良木 +\(summary.lootedWood)  |  粮草 +\(summary.lootedGrain)")
                        .font(.callout.bold())
                        .foregroundStyle(ImperialPalette.imperialGold)

                    Button("检阅军功与处置战俘 ›") {
                        let finalSum = sceneInstance?.buildCurrentSettlementSummary() ?? summary
                        router.completeBattleAndShowResult(finalSum)
                    }
                    .buttonStyle(ImperialCrimsonButtonStyle())
                    .padding(.top, 6)
                }
                .frame(width: 500)
            }
        }
    }
}
