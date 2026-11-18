import SpriteKit
import SwiftUI

/// 核心路由 1：帝国统帅大帐主界面（全画幅动态冷兵器交锋 SpriteKit 背景 + 黑曜鎏金古铜双栏指挥大厅）
public struct MainMenuView: View {
    @Bindable var router: AppRouter
    @State private var selectedFactionId: FactionId = .yanlong
    @State private var backdropScene = MenuBackdropBattleScene(size: CGSize(width: 1440, height: 900))

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
        ZStack {
            // 底层：实时演算两军火柴人军团冲杀与升腾战火粒子背景
            SpriteView(scene: backdropScene)
                .ignoresSafeArea()

            // 暗角渐晕遮罩，确保前景鎏金铜框文字清晰锐利
            LinearGradient(
                colors: [
                    ImperialPalette.obsidianDeep.opacity(0.88),
                    ImperialPalette.obsidianDeep.opacity(0.66),
                    ImperialPalette.obsidianDeep.opacity(0.86)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 22) {
                // 左栏：帝国金徽标题、继续征途、四大出征模式、难度档位与军档设置
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(ImperialPalette.goldGradient)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("火柴人冷兵器大战")
                                    .font(.system(size: 30, weight: .black, design: .serif))
                                    .foregroundStyle(ImperialPalette.goldGradient)
                                Text("IMPERIAL EDITION · 帝国锋刃（指尖营建 × 罗马军团）")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(ImperialPalette.parchmentMuted)
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    // AI 统帅难度三档快速切换
                    ImperialPanel(cornerRadius: 9, borderOpacity: 0.45, padding: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("敌军统帅博弈强度")
                                .font(.caption.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                            HStack(spacing: 6) {
                                ForEach(AIDifficultyTier.allCases) { tier in
                                    let active = router.launchContext.aiDifficulty == tier
                                    Button(tier.displayName) {
                                        BattleAudioEngine.shared.play(.uiClick)
                                        router.launchContext.aiDifficulty = tier
                                    }
                                    .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: active, isCompact: true))
                                }
                            }
                        }
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if let recentSlot = router.mostRecentNonEmptySlot {
                                let facCfg = FactionConfig.config(for: recentSlot.factionId)
                                Button {
                                    BattleAudioEngine.shared.play(.warHorn, volumeScale: 0.7)
                                    _ = router.loadCampaignFromSlot(recentSlot.slotIndex)
                                } label: {
                                    HStack(spacing: 12) {
                                        if let facCfg {
                                            FactionCrestBadge(faction: facCfg, size: 38)
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("继续霸业征途 · \(facCfg?.name ?? "")")
                                                .font(.headline.bold())
                                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                                            Text("第 \(recentSlot.turnNumber) 回合 · 掌控 \(recentSlot.controlledNodes)/\(GameConstants.campaignNodeCount) 城关 · 累计胜 \(recentSlot.totalBattlesWon) 场")
                                                .font(.caption)
                                                .foregroundStyle(ImperialPalette.parchmentMuted)
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                            .font(.title3.bold())
                                            .foregroundStyle(ImperialPalette.imperialGoldBright)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(ImperialPalette.legionCrimson.opacity(0.32))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .strokeBorder(ImperialPalette.imperialGold, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            imperialModeCard(
                                icon: "map.fill",
                                title: "开启宏大帝国战役",
                                subtitle: "以【\(selectedFaction.name)】逐鹿九州 · 40座城关 · 78条粮道 · 赋税诏令与合纵连横",
                                shortcut: "⌘N",
                                isPrimary: true
                            ) {
                                BattleAudioEngine.shared.play(.warHorn, volumeScale: 0.72)
                                router.startMode(.campaign, playerFaction: selectedFactionId, forceNewCampaign: true)
                            }

                            imperialModeCard(
                                icon: "flag.2.crossed.fill",
                                title: "经典帝国遭遇战",
                                subtitle: "四时代演进 · 筑城屯田 · 铁匠三系锻造 · 罗马龟甲阵 + 主帅提刀亲征",
                                shortcut: "⇧⌘N",
                                isPrimary: false
                            ) {
                                BattleAudioEngine.shared.play(.drumMarch)
                                router.startMode(.skirmish, playerFaction: selectedFactionId)
                            }

                            imperialModeCard(
                                icon: "building.columns.fill",
                                title: "雄关死守攻坚战",
                                subtitle: "5600×2600 巨型瓮城 · 箭塔拒马迎战敌军投石车与重步三段式猛攻",
                                shortcut: "⌥⌘N",
                                isPrimary: false
                            ) {
                                BattleAudioEngine.shared.play(.drumMarch)
                                router.startMode(.siegeChallenge, playerFaction: selectedFactionId)
                            }

                            imperialModeCard(
                                icon: "slider.horizontal.below.square.filled.and.square",
                                title: "自定义演武沙盒",
                                subtitle: "充裕军资 · 16大兵种自由混编 · 实测方阵抗骑、包抄合围与主帅弹反",
                                shortcut: "⌘3",
                                isPrimary: false
                            ) {
                                BattleAudioEngine.shared.play(.uiClick)
                                router.startMode(.customSandbox, playerFaction: selectedFactionId)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    router.navigate(to: .saveLoad)
                                } label: {
                                    Label("本地军档库 (⌘L)", systemImage: "externaldrive.fill.badge.checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ImperialBronzeButtonStyle())

                                Button {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    router.navigate(to: .settings)
                                } label: {
                                    Label("音画与键位 (⌘,)", systemImage: "gearshape.2.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ImperialBronzeButtonStyle())
                            }
                            .padding(.top, 4)
                        }
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(ImperialPalette.jadeSupply)
                            .frame(width: 8, height: 8)
                        Text("macOS 原生 Metal 合批 · 多声道实时战鼓金铁音效 · 零内购纯净单机")
                            .font(.caption2)
                            .foregroundStyle(ImperialPalette.parchmentMuted)
                    }
                }
                .frame(width: 425)

                // 右栏：八大非对称帝国/汗国纹章检阅台与王牌精锐档案
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("八方帝国与王庭 · 选择你的出征势力")
                                .font(.title3.bold())
                                .foregroundStyle(ImperialPalette.parchmentText)
                            Text("每一方势力均拥有独一无二的经济/战术法则、专属王牌精锐与三阶传世科技")
                                .font(.caption)
                                .foregroundStyle(ImperialPalette.parchmentMuted)
                        }
                        Spacer()
                        Button {
                            BattleAudioEngine.shared.play(.uiClick)
                            router.showQuickHelpSheet = true
                        } label: {
                            Label("兵种克制与操作宝典 (⌘/)", systemImage: "book.pages.fill")
                        }
                        .buttonStyle(ImperialBronzeButtonStyle())
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                        ForEach(FactionConfig.allFactions) { faction in
                            let isSelected = (faction.id == selectedFactionId)
                            let yieldSum = CampaignMapConfig.initialNodes(for: faction.id).reduce(0) { $0 + $1.totalYield }
                            let aceName = UnitConfig.stats(for: faction.exclusiveUnitId)?.name ?? ""
                            Button {
                                BattleAudioEngine.shared.play(.uiClick)
                                selectedFactionId = faction.id
                                router.launchContext.playerFaction = faction.id
                                router.bannerMessage = "已选定【\(faction.name)】—— 王牌精锐：\(aceName) · 开局五城总产出 \(yieldSum)"
                            } label: {
                                HStack(spacing: 12) {
                                    FactionCrestBadge(faction: faction, size: 42)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(faction.name)
                                                .font(.headline.bold())
                                                .foregroundStyle(isSelected ? ImperialPalette.imperialGoldBright : ImperialPalette.parchmentText)
                                            Spacer()
                                            Text("信誉 \(faction.startingCredibility)")
                                                .font(.caption2.monospacedDigit())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                                .foregroundStyle(ImperialPalette.imperialGold)
                                        }
                                        Text("\(faction.specialtyTag) · 王牌【\(aceName)】")
                                            .font(.caption)
                                            .foregroundStyle(ImperialPalette.parchmentMuted)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            isSelected
                                                ? Color(hex: faction.primaryColorHex).opacity(0.28)
                                                : ImperialPalette.obsidianCard.opacity(0.88)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            isSelected ? ImperialPalette.imperialGoldBright : ImperialPalette.bronzeBorder.opacity(0.38),
                                            lineWidth: isSelected ? 2.0 : 1.0
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 选中势力的帝国军机卷轴详单
                    ImperialPanel(cornerRadius: 12, borderOpacity: 0.72, padding: 16) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(spacing: 14) {
                                FactionCrestBadge(faction: selectedFaction, size: 50)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 10) {
                                        Text(selectedFaction.name)
                                            .font(.title2.bold())
                                            .foregroundStyle(ImperialPalette.imperialGoldBright)
                                        Text(selectedFaction.bannerTitle)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color(hex: selectedFaction.primaryColorHex).opacity(0.35)))
                                            .foregroundStyle(ImperialPalette.parchmentText)
                                    }
                                    Text("王都巨城：\(CampaignMapConfig.node(byId: selectedFaction.capitalNodeId)?.name ?? selectedFaction.capitalNodeId) · 本土五城总税粮 \(homelandEconomyTotal)")
                                        .font(.caption)
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
                                }
                                Spacer()
                                if let unit = exclusiveUnit {
                                    VStack(alignment: .trailing, spacing: 3) {
                                        HStack(spacing: 5) {
                                            Image(systemName: UnitVisualSymbol.sfSymbol(for: unit.id))
                                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                                            Text("专属王牌：\(unit.name)")
                                                .font(.callout.bold())
                                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                                        }
                                        Text("HP \(unit.hp) · 攻 \(unit.attack) · 破甲 \(Int(unit.armorPenetration * 100))% · 甲 \(unit.armor)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(ImperialPalette.parchmentMuted)
                                    }
                                }
                            }

                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("帝国强权法则", systemImage: "crown.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(ImperialPalette.jadeSupply)
                                    Text(selectedFaction.bonusSummary)
                                        .font(.caption)
                                        .foregroundStyle(ImperialPalette.parchmentText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Label("战略制衡弱点", systemImage: "exclamationmark.shield.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                    Text(selectedFaction.weaknessSummary)
                                        .font(.caption)
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Divider().overlay(ImperialPalette.bronzeBorder.opacity(0.4))

                            HStack(alignment: .top, spacing: 10) {
                                ForEach(selectedFaction.uniqueTechs) { tech in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("《\(tech.name)》")
                                            .font(.caption.bold())
                                            .foregroundStyle(ImperialPalette.imperialGold)
                                        Text(tech.effectSummary)
                                            .font(.caption2)
                                            .foregroundStyle(ImperialPalette.parchmentText)
                                            .lineLimit(2)
                                        Text("金\(tech.cost.gold) · 木\(tech.cost.wood) · 粮\(tech.cost.grain)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(ImperialPalette.parchmentMuted)
                                    }
                                    .padding(9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.36)))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.32), lineWidth: 1))
                                }
                            }
                        }
                    }

                    Spacer(minLength: 2)

                    HStack(spacing: 10) {
                        Image(systemName: "scroll.fill")
                            .foregroundStyle(ImperialPalette.imperialGold)
                        Text(router.bannerMessage)
                            .font(.caption)
                            .foregroundStyle(ImperialPalette.parchmentText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ImperialPalette.obsidianCard.opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.4), lineWidth: 1))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
        }
        .onAppear {
            BattleAudioEngine.shared.masterVolume = Float(router.userSettings.masterVolume * router.userSettings.sfxVolume)
            selectedFactionId = router.launchContext.playerFaction
            router.reloadSlots()
        }
    }

    private func imperialModeCard(
        icon: String,
        title: String,
        subtitle: String,
        shortcut: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPrimary ? AnyShapeStyle(ImperialPalette.crimsonWarGradient) : AnyShapeStyle(ImperialPalette.obsidianElevated))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(isPrimary ? ImperialPalette.imperialGoldBright : ImperialPalette.parchmentText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                        .lineLimit(2)
                }
                Spacer()
                Text(shortcut)
                    .font(.caption2.monospaced().bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.45)))
                    .foregroundStyle(ImperialPalette.imperialGold)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPrimary ? ImperialPalette.obsidianElevated.opacity(0.96) : ImperialPalette.obsidianCard.opacity(0.90))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isPrimary ? ImperialPalette.imperialGold : ImperialPalette.bronzeBorder.opacity(0.45),
                        lineWidth: isPrimary ? 1.6 : 1.0
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
