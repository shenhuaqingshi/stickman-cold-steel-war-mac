import SwiftUI

/// 核心路由 3：战前整军配兵页（支持遭遇战/守城挑战/自定义沙盒 6 军团自由配兵、阵型预设、粮耗耐力测算，以及战役模式前线整军检阅）
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
            HStack(spacing: 12) {
                Button("‹ 返回上一页") {
                    router.goBack()
                }
                .buttonStyle(.bordered)

                Text("\(router.launchContext.entryMode.displayTitle) · 战前整军点兵台")
                    .font(.title3.bold())

                if let nid = router.launchContext.targetNodeId, let cfg = CampaignMapConfig.node(byId: nid) {
                    Text("目标城关：【\(cfg.name)】")
                        .font(.callout.bold())
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button("16 兵种数值与克制图鉴") {
                    showUnitCodexSheet = true
                }
                .buttonStyle(.bordered)

                Button("🥁 擂鼓开拔 · 进入冷兵器大战场 ›") {
                    router.launchBattlefieldFromSetup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(totalPlayerPop > GameConstants.defaultArmyPopCap || totalPlayerSoldiers == 0)
            }

            // 会战双方、场景、地形、天气与随军粮饷配置栏
            GroupBox(isCampaignBattle ? "战役前线态势与 BFS 粮道修正（由大地图实时锁定注入）" : "会战双方、地形天时与随军粮饷设置") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
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
                    }

                    HStack(spacing: 18) {
                        Text("参战总兵力：\(totalPlayerSoldiers) 人 · 编制人口：\(totalPlayerPop)/\(GameConstants.defaultArmyPopCap)")
                            .foregroundStyle(totalPlayerPop > GameConstants.defaultArmyPopCap ? .red : .primary)

                        Text("携行军粮：\(Int(effectiveCarryGrain)) · 全军耗粮 \(String(format: "%.2f", totalGrainUpkeepPerSec))/s（预计够吃 \(estimatedRationSeconds) 秒）")
                            .foregroundStyle(estimatedRationSeconds < 75 ? .orange : .green)

                        if let mods = router.activeCampaignBattleModifiers {
                            Text("士气上限 \(Int(mods.playerInitialMoraleCap)) · 我士气修正 \(Int(mods.playerInitialMoraleDelta)) · 敌士气修正 \(Int(mods.enemyInitialMoraleDelta))")
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
                                Slider(value: grainBinding, in: 300...2400, step: 100)
                                    .frame(width: 120)
                            }
                        }
                    }
                    .font(.caption.monospacedDigit())
                }
                .padding(6)
            }

            // 双栏：左栏我军 6 大军团精细配兵与阵型，右栏敌军侦察情报与快捷战术模板
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("我军六路军团建制编组（开战后按 F1~F6 快速选定，1~4 变阵）")
                            .font(.subheadline.bold())
                        Spacer()
                        if !isCampaignBattle {
                            Button("均衡六军阵") { applyPreset(.balanced) }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("两翼铁骑包抄阵") { applyPreset(.cavalryWings) }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("高地强弩刺猬阵") { applyPreset(.rangedHedgehog) }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("重装破城攻坚群") { applyPreset(.siegeBreaker) }
                                .buttonStyle(.bordered).controlSize(.small)
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
                .frame(minWidth: 620, maxWidth: .infinity)

                // 右栏：对阵敌军情报与战场双视角操控要诀
                VStack(alignment: .leading, spacing: 10) {
                    let eCfg = FactionConfig.config(for: router.launchContext.enemyFaction)
                    GroupBox("敌军侦察情报 · 【\(eCfg?.name ?? "")】") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("敌方特性：\(eCfg?.specialtyTag ?? "")")
                                .font(.callout.bold())
                            Text("敌方强势：\(eCfg?.bonusSummary ?? "")")
                                .font(.caption)
                            Text("敌方破绽：\(eCfg?.weaknessSummary ?? "")")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            Divider()
                            Text("侦知敌军出战六路编制：")
                                .font(.caption.bold())
                            ForEach(Array(router.setupEnemyRoster.enumerated()), id: \.offset) { _, eEntry in
                                let uName = UnitConfig.stats(for: eEntry.unitType)?.name ?? ""
                                HStack {
                                    Text("• \(corpsDisplayName(eEntry.corpsRole))：\(uName) × \(eEntry.count)")
                                    Spacer()
                                    Text(eEntry.initialFormation.displayName)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }

                    GroupBox("大战场致胜操作速览") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("1. 开战默认处于【RTS 统帅视角】：左键拖拽框选多支分队，右键点地面机动、点敌军集火，Shift+右键拉大弧线绕后。")
                            Text("2. 善用 [Space] 战术暂停：暂停时从容给两翼骑兵下达 [F] 侧翼包抄或 [G] 钳形合围（八象限合围每秒打掉敌军 4.8 士气！）。")
                            Text("3. 随时按 [Tab] 提刀上阵：[WASD] 走位，鼠标瞄准，左键挥刀/穿刺/蓄力射箭，右键起盾前 0.25s 精准弹反震晕周围敌兵，按 [R] 三军战吼当场唤醒白旗溃军！")
                            Text("4. 盯紧顶部余粮：派游骑兵按 [C] 奇袭敌营粮车可当场夺取 150 应急军粮（苍狼双倍 300 粮）。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                    }

                    Spacer()
                }
                .padding(.leading, 10)
                .frame(minWidth: 340, idealWidth: 390, maxWidth: 460)
            }
        }
        .padding(18)
        .sheet(isPresented: $showUnitCodexSheet) {
            unitCodexSheetView
        }
    }

    // MARK: - 单支军团行编辑器

    private func playerCorpsEditorRow(index: Int, entry: BattleArmyRosterEntry) -> some View {
        let stats = UnitConfig.stats(for: entry.unitType)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("[F\(index + 1)] \(corpsDisplayName(entry.corpsRole))")
                    .font(.callout.bold())
                if let st = stats {
                    Text("HP \(st.hp) · 攻 \(st.attack) · 破甲 \(Int(st.armorPenetration * 100))% · 甲 \(st.armor) · 占用人口 \(st.popCap * entry.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 195, alignment: .leading)

            if isCampaignBattle {
                Text("\(stats?.name ?? "") × \(entry.count)")
                    .font(.callout.monospacedDigit().bold())
                    .frame(width: 150, alignment: .leading)
            } else {
                Picker("兵种", selection: Binding(
                    get: {
                        legalPlayerUnits.contains(where: { $0.id == entry.unitType })
                            ? entry.unitType
                            : (legalPlayerUnits.first?.id ?? .shieldSwordsman)
                    },
                    set: { newUnit in
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
                .frame(width: 155)

                HStack(spacing: 6) {
                    Button("-") {
                        let next = max(1, entry.count - 2)
                        router.setupPlayerRoster[index] = BattleArmyRosterEntry(
                            corpsRole: entry.corpsRole,
                            unitType: entry.unitType,
                            count: next,
                            initialFormation: entry.initialFormation
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("\(entry.count)人")
                        .font(.callout.monospacedDigit().bold())
                        .frame(width: 44)

                    Button("+") {
                        let next = min(36, entry.count + 2)
                        router.setupPlayerRoster[index] = BattleArmyRosterEntry(
                            corpsRole: entry.corpsRole,
                            unitType: entry.unitType,
                            count: next,
                            initialFormation: entry.initialFormation
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Spacer()

            Picker("初始阵型", selection: Binding(
                get: { entry.initialFormation },
                set: { newForm in
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
            .frame(width: 145)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22), lineWidth: 1))
    }

    private enum RosterPresetKind {
        case balanced
        case cavalryWings
        case rangedHedgehog
        case siegeBreaker
    }

    private func applyPreset(_ preset: RosterPresetKind) {
        let pf = router.launchContext.playerFaction
        let excl = FactionConfig.config(for: pf)?.exclusiveUnitId ?? .shieldSwordsman
        let siegeUnit: UnitTypeId = (pf == .canglang) ? .ballista : .trebuchet

        switch preset {
        case .balanced:
            router.setupPlayerRoster = BattleSimulationEngine.defaultSixCorpsRoster(
                for: pf,
                scenario: router.launchContext.scenarioType,
                isPlayer: true
            )
        case .cavalryWings:
            let cavUnit: UnitTypeId = (UnitConfig.stats(for: excl)?.category == .cavalry) ? excl : .lightCavalry
            router.setupPlayerRoster = [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 18, initialFormation: .phalanxRect),
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
                BattleArmyRosterEntry(corpsRole: .leftWing, unitType: .shieldSwordsman, count: 14, initialFormation: .phalanxRect),
                BattleArmyRosterEntry(corpsRole: .rightWing, unitType: rngUnit, count: 16, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .rearReserve, unitType: .ballista, count: 4, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .siegeBattery, unitType: .compositeArcher, count: 16, initialFormation: .echelonLine),
                BattleArmyRosterEntry(corpsRole: .supplyEscort, unitType: .sapper, count: 4, initialFormation: .circleDefense)
            ]
        case .siegeBreaker:
            router.setupPlayerRoster = [
                BattleArmyRosterEntry(corpsRole: .vanguardCenter, unitType: .shieldSwordsman, count: 20, initialFormation: .phalanxRect),
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
        case .supplyEscort: return "辎重工兵队"
        }
    }

    // MARK: - 16 兵种静态数值图鉴弹窗

    private var unitCodexSheetView: some View {
        let units = onlyShowRecruitableInCodex ? legalPlayerUnits : UnitConfig.allUnits
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("全兵种静态数值表（共 16 种 · 双曲护甲 K=50 · 长枪反骑 3.2× +30% 动能破甲）")
                    .font(.title3.bold())
                Spacer()
                Toggle("仅看本势力可募", isOn: $onlyShowRecruitableInCodex)
                    .toggleStyle(.checkbox)
                Button("关闭 (Esc)") {
                    showUnitCodexSheet = false
                }
                .keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(units) { unit in
                        let tag = unit.exclusiveFaction.flatMap { FactionConfig.config(for: $0)?.name } ?? "通用"
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(unit.name).font(.headline)
                                Spacer()
                                Text(tag).font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                            }
                            Text("HP \(unit.hp) · 攻 \(unit.attack) · 破甲 \(Int(unit.armorPenetration * 100))% · 甲 \(unit.armor) · 盾减伤 \(Int(unit.shieldRangedBlock * 100))%")
                                .font(.caption.monospacedDigit())
                            Text("射程 \(Int(unit.attackRange))(\(Int(unit.minRange))) · 速 \(Int(unit.moveSpeed)) · 冲\(String(format: "%.2f", unit.chargeMultiplier))× / 反骑\(String(format: "%.1f", unit.antiCavalryMultiplier))×")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            Text("金\(unit.cost.gold)/木\(unit.cost.wood)/粮\(unit.cost.grain) · 人口\(unit.popCap) · 耗粮\(String(format: "%.2f", unit.grainUpkeepPerSec))/s")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            Text(unit.traitDesc)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10)))
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 960, height: 580)
    }
}
