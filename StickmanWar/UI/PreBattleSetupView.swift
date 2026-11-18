import SwiftUI

/// 核心路由 3：战前整军点兵台（帝国锋刃版 · 支持 6 军团配兵、5 大古战阵预设、AI 难度档位、粮耗测算与 16 兵种图鉴）
public struct PreBattleSetupView: View {
    @Bindable var router: AppRouter
    @State private var showUnitCodexSheet: Bool = false
    @State private var onlyShowRecruitableInCodex: Bool = true

    private var isCampaignBattle: Bool {
        router.launchContext.entryMode == .campaign
    }

    private var legalPlayerUnits: [UnitStaticStats] {
        UnitConfig.recruitableUnits(for: router.launchContext.playerFaction)
    }

    private var totalPlayerSoldiers: Int {
        router.setupPlayerRoster.reduce(0) { $0 + $1.count }
    }

    private var totalPlayerPop: Int {
        router.setupPlayerRoster.reduce(0) { acc, entry in
            let pop = UnitConfig.stats(for: entry.unitType)?.popCap ?? 1
            return acc + pop * entry.count
        }
    }

    private var totalGrainUpkeepPerSec: Double {
        let shuangyuanMult = router.launchContext.playerFaction == .shuangyuan ? 1.15 : 1.0
        return router.setupPlayerRoster.reduce(0.0) { acc, entry in
            let u = UnitConfig.stats(for: entry.unitType)?.grainUpkeepPerSec ?? 0.10
            return acc + u * shuangyuanMult * Double(entry.count)
        }
    }

    private var effectiveCarryGrain: Double {
        router.pendingBattleDeployment.playerInitialGrain > 0
            ? router.pendingBattleDeployment.playerInitialGrain
            : GameConstants.battleInitGrain
    }

    private var estimatedRationSeconds: Int {
        guard totalGrainUpkeepPerSec > 0.01 else { return 999 }
        return Int((effectiveCarryGrain / totalGrainUpkeepPerSec).rounded())
    }

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 12) {
            // 顶部主帅点兵导航条
            HStack(spacing: 14) {
                Button("‹ 返回上一页") {
                    BattleAudioEngine.shared.play(.uiClick)
                    router.goBack()
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                if let pCfg = FactionConfig.config(for: router.launchContext.playerFaction) {
                    FactionCrestBadge(faction: pCfg, size: 34)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(router.launchContext.entryMode.displayTitle) · 帝国战前点兵台")
                            .font(.title3.bold())
                            .foregroundStyle(ImperialPalette.parchmentText)
                        if let nid = router.launchContext.targetNodeId, let cfg = CampaignMapConfig.node(byId: nid) {
                            Text("交战要塞：【\(cfg.name)】")
                                .font(.callout.bold())
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                        }
                    }
                    Text("开战后可在前线直接营建军屯农庄、演进四大时代、锻造三系铁匠甲胄，并随时按 [Tab] 提刀上阵")
                        .font(.caption2)
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                }

                Spacer()

                Button("16 兵种克制图鉴") {
                    BattleAudioEngine.shared.play(.uiClick)
                    showUnitCodexSheet = true
                }
                .buttonStyle(ImperialBronzeButtonStyle())

                Button {
                    BattleAudioEngine.shared.play(.warHorn)
                    router.launchBattlefieldFromSetup()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.2.crossed.fill")
                        Text("擂鼓开拔 · 进入大战场 ›")
                    }
                }
                .buttonStyle(ImperialCrimsonButtonStyle())
                .disabled(totalPlayerPop > GameConstants.defaultArmyPopCap || totalPlayerSoldiers == 0)
            }

            // 会战双方、场景、地形、天气、AI难度与随军粮饷配置栏
            ImperialPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 14) {
                        Picker("我方势力", selection: $router.launchContext.playerFaction) {
                            ForEach(FactionConfig.allFactions) { faction in
                                Text(faction.name).tag(faction.id)
                            }
                        }
                        .disabled(isCampaignBattle)
                        .onChange(of: router.launchContext.playerFaction) { _, _ in
                            if !isCampaignBattle {
                                router.rebuildSkirmishRostersForCurrentContext()
                            }
                        }

                        Picker("敌军势力", selection: $router.launchContext.enemyFaction) {
                            ForEach(FactionConfig.allFactions) { faction in
                                Text(faction.name).tag(faction.id)
                            }
                        }
                        .disabled(isCampaignBattle)
                        .onChange(of: router.launchContext.enemyFaction) { _, _ in
                            if !isCampaignBattle {
                                router.rebuildSkirmishRostersForCurrentContext()
                            }
                        }

                        Picker("战斗类型", selection: $router.launchContext.scenarioType) {
                            ForEach(BattleScenarioType.allCases) { scenario in
                                Text(scenario.displayName).tag(scenario)
                            }
                        }
                        .disabled(isCampaignBattle)
                        .onChange(of: router.launchContext.scenarioType) { _, _ in
                            if !isCampaignBattle {
                                router.rebuildSkirmishRostersForCurrentContext()
                            }
                        }

                        Picker("战场地形", selection: $router.launchContext.terrain) {
                            ForEach(TerrainType.allCases) { terrain in
                                Text(terrain.displayName).tag(terrain)
                            }
                        }
                        .disabled(isCampaignBattle)

                        Picker("天时昼夜", selection: $router.launchContext.weather) {
                            ForEach(WeatherType.allCases) { weather in
                                Text(weather.displayName).tag(weather)
                            }
                        }
                        .disabled(isCampaignBattle)

                        Picker("AI 统帅", selection: $router.launchContext.aiDifficulty) {
                            ForEach(AIDifficultyTier.allCases) { tier in
                                Text(tier.displayName).tag(tier)
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 18) {
                        Text("参战总兵力：\(totalPlayerSoldiers) 人 · 开局编制：\(totalPlayerPop)/\(GameConstants.defaultArmyPopCap)（建军屯民居可扩编至 260+）")
                            .foregroundStyle(totalPlayerPop > GameConstants.defaultArmyPopCap ? ImperialPalette.legionCrimsonBright : ImperialPalette.parchmentText)

                        Text("携行军粮：\(Int(effectiveCarryGrain)) · 全军耗粮 \(String(format: "%.2f", totalGrainUpkeepPerSec))/s（净耗可维持 \(estimatedRationSeconds) 秒，建帝国农庄可持续产粮）")
                            .foregroundStyle(estimatedRationSeconds < 75 ? .orange : ImperialPalette.jadeSupply)

                        if let mods = router.activeCampaignBattleModifiers {
                            Text("士气上限 \(Int(mods.playerInitialMoraleCap)) · 我士气 \(Int(mods.playerInitialMoraleDelta)) · 敌士气 \(Int(mods.enemyInitialMoraleDelta))")
                                .foregroundStyle(.cyan)
                        }

                        Spacer()

                        if router.launchContext.entryMode == .customSandbox {
                            let grainBinding = Binding<Double>(
                                get: { min(2400.0, max(300.0, (router.pendingBattleDeployment.playerInitialGrain / 100.0).rounded() * 100.0)) },
                                set: { router.pendingBattleDeployment.playerInitialGrain = $0 }
                            )
                            HStack(spacing: 6) {
                                Text("沙盒携粮")
                                    .foregroundStyle(ImperialPalette.imperialGold)
                                Slider(value: grainBinding, in: 300...2400, step: 100)
                                    .frame(width: 115)
                            }
                        }
                    }
                    .font(.caption.monospacedDigit())
                }
            }

            // 双栏：左栏我军 6 大军团精细配兵与阵型，右栏敌军侦察情报与罗马/指尖操作要诀
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("我军六路常备军团（F1~F6 选定 · 1~5 切换五大古战阵）")
                            .font(.subheadline.bold())
                            .foregroundStyle(ImperialPalette.imperialGold)
                        Spacer()
                        if !isCampaignBattle {
                            Button("罗马龟甲军团") { applyPreset(.romanTestudo) }
                                .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
                            Button("均衡六军阵") { applyPreset(.balanced) }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                            Button("双翼铁骑阵") { applyPreset(.cavalryWings) }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                            Button("高地强弩阵") { applyPreset(.rangedHedgehog) }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                            Button("重装破城群") { applyPreset(.siegeBreaker) }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                        }
                    }

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(router.setupPlayerRoster.enumerated()), id: \.offset) { idx, entry in
                                playerCorpsEditorRow(index: idx, entry: entry)
                            }
                        }
                    }
                }
                .padding(.trailing, 10)
                .frame(minWidth: 640, maxWidth: .infinity)

                // 右栏：对阵敌军情报与帝国锋刃操作速览
                VStack(alignment: .leading, spacing: 10) {
                    let eCfg = FactionConfig.config(for: router.launchContext.enemyFaction)
                    ImperialPanel(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                if let eCfg {
                                    FactionCrestBadge(faction: eCfg, size: 30)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("敌军军情 · 【\(eCfg?.name ?? "")】")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(ImperialPalette.imperialGold)
                                    Text(eCfg?.specialtyTag ?? "")
                                        .font(.caption2.bold())
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
                                }
                            }
                            Text("敌方强势：\(eCfg?.bonusSummary ?? "")")
                                .font(.caption)
                                .foregroundStyle(ImperialPalette.parchmentText)
                            Text("敌方破绽：\(eCfg?.weaknessSummary ?? "")")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            Divider()
                            Text("侦知敌军首发六路建制：")
                                .font(.caption.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                            ForEach(Array(router.setupEnemyRoster.enumerated()), id: \.offset) { _, eEntry in
                                let uName = UnitConfig.stats(for: eEntry.unitType)?.name ?? ""
                                HStack {
                                    Image(systemName: UnitVisualSymbol.sfSymbol(for: eEntry.unitType))
                                        .foregroundStyle(ImperialPalette.legionCrimsonBright)
                                        .frame(width: 16)
                                    Text("\(corpsDisplayName(eEntry.corpsRole))：\(uName) × \(eEntry.count)")
                                        .foregroundStyle(ImperialPalette.parchmentText)
                                    Spacer()
                                    Text(eEntry.initialFormation.displayName)
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ImperialPanel(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("帝国锋刃 · 统帅决胜要诀")
                                .font(.subheadline.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                            Text("1. 【罗马拉线布阵】：框选军团后按住右键在地面横向拖拽，即可自定义排兵宽度与军阵朝向！按 [5] 结成【罗马龟甲阵】可获 85% 挡箭减伤顶箭推城。")
                            Text("2. 【指尖帝国营建】：底部切换至【帝国营建与铁匠】，建造民居扩人口、农庄稳军粮、兵营马厩提速募兵，攀升时代 I→IV 并升满铁匠三系锻造。")
                            Text("3. 【合围崩解士气】：善用 [Space] 暂停下达双翼骑兵 [F] 包抄或 [G] 钳形合围，八象限铁桶合围每秒削敌 4.8 士气。")
                            Text("4. 【主帅提刀无双】：按 [Tab] 随时化身主帅亲临前线，右键 0.25s 精准弹反震晕群敌，[R] 三军战吼当场唤醒白旗溃兵！")
                        }
                        .font(.caption)
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()
                }
                .padding(.leading, 10)
                .frame(minWidth: 350, idealWidth: 400, maxWidth: 470)
            }
        }
        .padding(18)
        .background(ImperialPalette.obsidianDeep)
        .sheet(isPresented: $showUnitCodexSheet) {
            unitCodexSheetView
        }
    }

    // MARK: - 单支军团行编辑器

    private func playerCorpsEditorRow(index: Int, entry: BattleArmyRosterEntry) -> some View {
        let stats = UnitConfig.stats(for: entry.unitType)
        return HStack(spacing: 12) {
            Image(systemName: UnitVisualSymbol.sfSymbol(for: entry.unitType))
                .font(.headline)
                .foregroundStyle(ImperialPalette.imperialGoldBright)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("[F\(index + 1)] \(corpsDisplayName(entry.corpsRole))")
                    .font(.callout.bold())
                    .foregroundStyle(ImperialPalette.parchmentText)
                if let st = stats {
                    Text("HP \(st.hp) · 攻 \(st.attack) · 破甲 \(Int(st.armorPenetration * 100))% · 甲 \(st.armor) · 人口 \(st.popCap * entry.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                }
            }
            .frame(width: 195, alignment: .leading)

            if isCampaignBattle {
                Text("\(stats?.name ?? "") × \(entry.count)")
                    .font(.callout.monospacedDigit().bold())
                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                    .frame(width: 150, alignment: .leading)
            } else {
                Picker("兵种", selection: Binding(
                    get: {
                        legalPlayerUnits.contains(where: { $0.id == entry.unitType })
                            ? entry.unitType
                            : (legalPlayerUnits.first?.id ?? .shieldSwordsman)
                    },
                    set: { newUnit in
                        BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.5)
                        router.setupPlayerRoster[index] = BattleArmyRosterEntry(
                            corpsRole: entry.corpsRole,
                            unitType: newUnit,
                            count: entry.count,
                            initialFormation: entry.initialFormation
                        )
                    }
                )) {
                    ForEach(legalPlayerUnits) { u in
                        Text(u.name).tag(u.id)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                HStack(spacing: 6) {
                    Button("-") {
                        BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.5)
                        let next = max(1, entry.count - 2)
                        router.setupPlayerRoster[index] = BattleArmyRosterEntry(
                            corpsRole: entry.corpsRole,
                            unitType: entry.unitType,
                            count: next,
                            initialFormation: entry.initialFormation
                        )
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                    Text("\(entry.count)人")
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(ImperialPalette.parchmentText)
                        .frame(width: 44)

                    Button("+") {
                        BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.5)
                        let next = min(36, entry.count + 2)
                        router.setupPlayerRoster[index] = BattleArmyRosterEntry(
                            corpsRole: entry.corpsRole,
                            unitType: entry.unitType,
                            count: next,
                            initialFormation: entry.initialFormation
                        )
                    }
                    .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                }
            }

            Spacer()

            Picker("初始阵型", selection: Binding(
                get: { entry.initialFormation },
                set: { newForm in
                    BattleAudioEngine.shared.play(.drumMarch, volumeScale: 0.5)
                    router.setupPlayerRoster[index] = BattleArmyRosterEntry(
                        corpsRole: entry.corpsRole,
                        unitType: entry.unitType,
                        count: entry.count,
                        initialFormation: newForm
                    )
                }
            )) {
                ForEach(FormationType.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .frame(width: 148)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ImperialPalette.obsidianCard)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.42), lineWidth: 1))
        )
    }

    private enum RosterPresetKind {
        case romanTestudo
        case balanced
        case cavalryWings
        case rangedHedgehog
        case siegeBreaker
    }

    private func applyPreset(_ preset: RosterPresetKind) {
        BattleAudioEngine.shared.play(.drumMarch, volumeScale: 0.7)
        let pf = router.launchContext.playerFaction
        let excl = FactionConfig.config(for: pf)?.exclusiveUnitId ?? .shieldSwordsman
        let siegeUnit: UnitTypeId = (pf == .canglang) ? .ballista : .trebuchet

        switch preset {
        case .romanTestudo:
            router.setupPlayerRoster = [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 22, initialFormation: .testudo),
                BattleArmyRosterEntry(corpsRole: .leftWing, unitType: .shieldSwordsman, count: 16, initialFormation: .testudo),
                BattleArmyRosterEntry(corpsRole: .rightWing, unitType: .lightCavalry, count: 10, initialFormation: .wedgeCharge),
                BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: .pikeman, count: 12, initialFormation: .phalanxRect),
                BattleArmyRosterEntry(corpsRole: .siegeBattery, unitType: excl, count: 12, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 5, initialFormation: .circleDefense)
            ]
        case .balanced:
            router.setupPlayerRoster = BattleSimulationEngine.defaultSixCorpsRoster(
                for: pf,
                scenario: router.launchContext.scenarioType,
                isPlayer: true
            )
        case .cavalryWings:
            let cavUnit: UnitTypeId = (UnitConfig.stats(for: excl)?.category == .cavalry) ? excl : .lightCavalry
            router.setupPlayerRoster = [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 18, initialFormation: .testudo),
                BattleArmyRosterEntry(corpsRole: .leftWing, unitType: cavUnit, count: 12, initialFormation: .wedgeCharge),
                BattleArmyRosterEntry(corpsRole: .rightWing, unitType: .lightCavalry, count: 12, initialFormation: .wedgeCharge),
                BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: .pikeman, count: 12, initialFormation: .phalanxRect),
                BattleArmyRosterEntry(corpsRole: .siegeBattery, unitType: .compositeArcher, count: 12, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 4, initialFormation: .circleDefense)
            ]
        case .rangedHedgehog:
            let rngUnit: UnitTypeId = (UnitConfig.stats(for: excl)?.category == .ranged) ? excl : .compositeArcher
            router.setupPlayerRoster = [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .pikeman, count: 20, initialFormation: .phalanxRect),
                BattleArmyRosterEntry(corpsRole: .leftWing, unitType: .shieldSwordsman, count: 14, initialFormation: .testudo),
                BattleArmyRosterEntry(corpsRole: .rightWing, unitType: rngUnit, count: 16, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: .ballista, count: 4, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .siegeBattery, unitType: .compositeArcher, count: 16, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 4, initialFormation: .circleDefense)
            ]
        case .siegeBreaker:
            router.setupPlayerRoster = [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 20, initialFormation: .testudo),
                BattleArmyRosterEntry(corpsRole: .leftWing, unitType: .greatAxeman, count: 16, initialFormation: .wedgeCharge),
                BattleArmyRosterEntry(corpsRole: .rightWing, unitType: excl, count: 10, initialFormation: .phalanxRect),
                BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: .pikeman, count: 12, initialFormation: .phalanxRect),
                BattleArmyRosterEntry(corpsRole: .siegeBattery, unitType: siegeUnit, count: 4, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 5, initialFormation: .circleDefense)
            ]
        }
    }

    private func corpsDisplayName(_ role: ArmyCorpsRole) -> String {
        switch role {
        case .vanguardCenter: return "中军前锋"
        case .leftWing: return "北翼军团"
        case .rightWing: return "南翼军团"
        case .rearReserve: return "总预备队"
        case .siegeBattery: return "远程攻城群"
        case .supplyEscort: return "辎重民夫队"
        }
    }

    // MARK: - 16 兵种静态数值图鉴弹窗

    private var unitCodexSheetView: some View {
        let units = onlyShowRecruitableInCodex ? legalPlayerUnits : UnitConfig.allUnits
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("帝国军典 · 全兵种静态数值表（共 16 种 · 双曲护甲 K=50 · 长枪反骑 3.2×）")
                    .font(.title3.bold())
                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                Spacer()
                Toggle("仅看本势力可募", isOn: $onlyShowRecruitableInCodex)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(ImperialPalette.parchmentText)
                Button("关闭 (Esc)") {
                    showUnitCodexSheet = false
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                .keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(units) { unit in
                        let tag = unit.exclusiveFaction.flatMap { FactionConfig.config(for: $0)?.name } ?? "通用常备"
                        ImperialPanel(padding: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: UnitVisualSymbol.sfSymbol(for: unit.id))
                                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                                    Text(unit.name)
                                        .font(.headline)
                                        .foregroundStyle(ImperialPalette.parchmentText)
                                    Spacer()
                                    Text(tag)
                                        .font(.caption2.bold())
                                        .foregroundStyle(ImperialPalette.imperialGold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(ImperialPalette.obsidianElevated))
                                }
                                Text("HP \(unit.hp) · 攻 \(unit.attack) · 破甲 \(Int(unit.armorPenetration * 100))% · 甲 \(unit.armor) · 盾挡箭 \(Int(unit.shieldRangedBlock * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(ImperialPalette.parchmentText)
                                Text("射程 \(Int(unit.attackRange))(\(Int(unit.minRange))) · 速 \(Int(unit.moveSpeed)) · 冲\(String(format: "%.2f", unit.chargeMultiplier))× / 反骑\(String(format: "%.1f", unit.antiCavalryMultiplier))×")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(ImperialPalette.parchmentMuted)
                                Text("金\(unit.cost.gold)/木\(unit.cost.wood)/粮\(unit.cost.grain) · 人口\(unit.popCap) · 耗粮\(String(format: "%.2f", unit.grainUpkeepPerSec))/s")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(ImperialPalette.imperialGold)
                                Text(unit.traitDesc)
                                    .font(.caption2)
                                    .foregroundStyle(ImperialPalette.parchmentMuted)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(ImperialPalette.obsidianDeep)
        .frame(width: 980, height: 600)
    }
}
