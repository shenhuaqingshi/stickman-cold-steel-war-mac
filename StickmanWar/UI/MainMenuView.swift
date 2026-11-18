import SwiftUI

/// 核心路由 1：主帅大帐主菜单页（macOS 大屏双栏自适应布局：左栏 6 大入口 + 继续军档 + 右栏 8 大势力检阅）
public struct MainMenuView: View {
    @Bindable var router: AppRouter
    @State private var selectedFactionId: FactionId = .yanlong

    private var selectedFaction: FactionStaticConfig {
        FactionConfig.config(for: selectedFactionId) ?? FactionConfig.allFactions[0]
    }

    private var exclusiveUnit: UnitStaticStats? {
        UnitConfig.stats(for: selectedFaction.exclusiveUnitId)
    }

    private var homelandEconomyTotal: Int {
        CampaignMapConfig.initialNodes(for: selectedFactionId).reduce(0) { $0 + $1.totalYield }
    }

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        HSplitView {
            // 左栏：标题徽记、继续军档与六大模式入口
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("火柴人冷兵器大战")
                        .font(.system(size: 28, weight: .heavy))
                    Text("Stickman Cold Steel War · macOS 原生版 (Swift 6 + SpriteKit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                ScrollView {
                    VStack(spacing: 10) {
                        if let recentSlot = router.mostRecentNonEmptySlot {
                            let facName = FactionConfig.config(for: recentSlot.factionId)?.name ?? ""
                            Button {
                                _ = router.loadCampaignFromSlot(recentSlot.slotIndex)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("继续最近军档 · \(facName)")
                                            .font(.headline)
                                            .foregroundStyle(.yellow)
                                        Text("第 \(recentSlot.turnNumber) 回合 · 已控 \(recentSlot.controlledNodes)/\(GameConstants.campaignNodeCount) 城关 · 胜 \(recentSlot.totalBattlesWon) 场")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.yellow)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.14)))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.55), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }

                        menuEntryButton(
                            title: "开启新战役",
                            subtitle: "以【\(selectedFaction.name)】誓师出征 · 8大区域 · 40座城关 · 78条粮道",
                            shortcut: "⌘N"
                        ) {
                            router.startMode(.campaign, playerFaction: selectedFactionId, forceNewCampaign: true)
                        }

                        menuEntryButton(
                            title: "遭遇战",
                            subtitle: "4800×2400 宏大战场 · 六军排兵会战 + 主帅亲自上阵",
                            shortcut: "⇧⌘N"
                        ) {
                            router.startMode(.skirmish, playerFaction: selectedFactionId)
                        }

                        menuEntryButton(
                            title: "守城挑战",
                            subtitle: "5600×2600 雄关要塞 · 拒马箭塔抵御敌军三段式猛攻",
                            shortcut: "⌥⌘N"
                        ) {
                            router.startMode(.siegeChallenge, playerFaction: selectedFactionId)
                        }

                        menuEntryButton(
                            title: "自定义战场",
                            subtitle: "16兵种沙盒演武 · 自由调配敌我编制验证战术克制",
                            shortcut: "⌘3"
                        ) {
                            router.startMode(.customSandbox, playerFaction: selectedFactionId)
                        }

                        Divider().padding(.vertical, 4)

                        menuEntryButton(
                            title: "本地存档与战绩",
                            subtitle: "Application Support 离线军档 · 原生文件导入/导出",
                            shortcut: "⌘L"
                        ) {
                            router.navigate(to: .saveLoad)
                        }

                        menuEntryButton(
                            title: "游戏设置与键鼠表",
                            subtitle: "60/30 FPS · 远景 LOD · 深浅外观 · 双视角键位指南",
                            shortcut: "⌘,"
                        ) {
                            router.navigate(to: .settings)
                        }
                    }
                }

                Spacer(minLength: 6)

                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("纯正 macOS 原生单机 · 零联网依赖 · Apple Silicon 优先")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(minWidth: 365, idealWidth: 405, maxWidth: 455, maxHeight: .infinity)

            // 右栏：八大非对称势力总览与专属编制/科技检阅台
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("八方割据 · 统帅出征势力检阅")
                        .font(.title3.bold())
                    Spacer()
                    Button("兵种克制与快捷键速查 (⌘/)") {
                        router.showQuickHelpSheet = true
                    }
                    .buttonStyle(.bordered)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(FactionConfig.allFactions) { faction in
                        let isSelected = (faction.id == selectedFactionId)
                        let yieldSum = CampaignMapConfig.initialNodes(for: faction.id).reduce(0) { $0 + $1.totalYield }
                        Button {
                            selectedFactionId = faction.id
                            router.launchContext.playerFaction = faction.id
                            router.bannerMessage = "已选定【\(faction.name)】（本土 5 城总产出 \(yieldSum) · 信誉 \(faction.startingCredibility) · 王牌：\(UnitConfig.stats(for: faction.exclusiveUnitId)?.name ?? "")）"
                        } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: faction.primaryColorHex))
                                    .frame(width: 7, height: 44)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(faction.name)
                                            .font(.headline)
                                        Spacer()
                                        Text("产出 \(yieldSum) · 信誉 \(faction.startingCredibility)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(faction.specialtyTag) · \(faction.bannerTitle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color(hex: faction.primaryColorHex).opacity(0.18) : Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color(hex: faction.primaryColorHex) : Color.secondary.opacity(0.22), lineWidth: isSelected ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 当前选中势力的深度战术档案卡
                GroupBox {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label(selectedFaction.name, systemImage: "flag.2.crossed.fill")
                                .font(.title3.bold())
                                .foregroundStyle(Color(hex: selectedFaction.primaryColorHex))
                            Text("王都：\(CampaignMapConfig.node(byId: selectedFaction.capitalNodeId)?.name ?? selectedFaction.capitalNodeId) · 开局 5 城产出 \(homelandEconomyTotal)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let unit = exclusiveUnit {
                                Text("专属王牌：\(unit.name)（HP \(unit.hp) / 攻 \(unit.attack) / 甲 \(unit.armor)）")
                                    .font(.callout.bold())
                            }
                        }

                        Text("核心强势：\(selectedFaction.bonusSummary)")
                            .font(.callout)
                        Text("明确短板：\(selectedFaction.weaknessSummary)")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("三阶专属科技：")
                            .font(.subheadline.bold())
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(selectedFaction.uniqueTechs) { tech in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("《\(tech.name)》")
                                        .font(.subheadline.bold())
                                    Text(tech.effectSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("金\(tech.cost.gold) / 木\(tech.cost.wood) / 粮\(tech.cost.grain)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                            }
                        }
                    }
                    .padding(6)
                }

                Spacer(minLength: 4)

                Text(router.bannerMessage)
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectedFactionId = router.launchContext.playerFaction
            router.reloadSlots()
        }
    }

    private func menuEntryButton(
        title: String,
        subtitle: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(shortcut)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.16)))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
