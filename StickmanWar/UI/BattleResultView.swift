import SwiftUI

/// 核心路由 5：帝国凯旋军功结算页（展示两军战损、随军医帐包扎归建、战俘三选一诏令、粮械缴获与大地图回写）
public struct BattleResultView: View {
    @Bindable var router: AppRouter
    @State private var prisonerChoice: CampaignPrisonerDisposition = .ransomForGoldAndCredibility

    private var settlement: PostBattleSettlementSummary {
        router.latestSettlement
    }

    private var outcomeHeadline: String {
        switch settlement.outcomeReason {
        case .enemyBaseDestroyed: return "凯旋大捷 · 踏平敌军本阵大营"
        case .enemyArmyRouted: return "辉煌大捷 · 敌军士气崩盘全线溃散"
        case .siegeDefenseHeld: return "守城大捷 · 铁壁雄关屹立不倒"
        case .truceNegotiated: return "罢兵止戈 · 阵前停火盟约生效"
        case .playerCommanderMartyred: return "重创败绩 · 主帅落马 / 本阵失陷"
        case .playerArmyRouted: return "惜败收兵 · 重整残部再图霸业"
        case .ongoing: return settlement.isVictory ? "凯旋大捷" : "会战终局"
        }
    }

    private var moraleStrategicImpactText: String {
        if settlement.outcomeReason == .playerCommanderMartyred {
            return "⚠️ 主帅二次重创落马：战役模式下已由铁卫拼死抢回后方，未来 2 回合处于【重伤休养】属性折损态。"
        } else if settlement.isVictory {
            return "🔥 帝国鹰旗威震敌胆：敌军厌战度急剧攀升；若系【围点打援】伏击战捷，将令孤城守军初始士气直接暴跌 -25！"
        } else if settlement.outcomeReason == .truceNegotiated {
            return "🤝 双方依约罢兵停火，各自收拢伤员重整边防。"
        } else {
            return "🛡 随军医帐已全力抢救重伤兵员归建，建议充实帝国农庄粮储与铁匠破甲装备后再图反攻。"
        }
    }

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    settlement.isVictory
                        ? Color(red: 0.24, green: 0.16, blue: 0.07)
                        : Color(red: 0.20, green: 0.08, blue: 0.08),
                    ImperialPalette.obsidianDeep
                ],
                center: .top,
                startRadius: 40,
                endRadius: 720
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // 顶部帝国凯旋门 / 军报纹章横幅
                VStack(spacing: 8) {
                    HStack(spacing: 22) {
                        if let pCfg = FactionConfig.config(for: settlement.playerFaction) {
                            FactionCrestBadge(faction: pCfg, size: 52)
                        }
                        Image(systemName: settlement.isVictory ? "laurel.leading" : "shield.slash.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(settlement.isVictory ? ImperialPalette.imperialGoldBright : ImperialPalette.legionCrimsonBright)
                        Text(outcomeHeadline)
                            .font(.system(size: 32, weight: .heavy, design: .serif))
                            .foregroundStyle(
                                settlement.isVictory
                                    ? ImperialPalette.imperialGoldBright
                                    : (settlement.outcomeReason == .truceNegotiated ? Color.cyan : ImperialPalette.legionCrimsonBright)
                            )
                            .shadow(color: .black.opacity(0.65), radius: 6, x: 0, y: 3)
                        if settlement.isVictory {
                            Image(systemName: "laurel.trailing")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                        }
                        if let eCfg = FactionConfig.config(for: settlement.enemyFaction) {
                            FactionCrestBadge(faction: eCfg, size: 52)
                        }
                    }

                    let pName = FactionConfig.config(for: settlement.playerFaction)?.name ?? ""
                    let eName = FactionConfig.config(for: settlement.enemyFaction)?.name ?? ""
                    let nodeTag: String = {
                        guard let nid = router.launchContext.targetNodeId,
                              let cName = CampaignMapConfig.node(byId: nid)?.name else { return "" }
                        return " · 决战地：【\(cName)】"
                    }()
                    Text("\(pName) vs \(eName) · \(settlement.scenarioType.displayName)\(nodeTag) · 鏖战历时 \(settlement.durationSeconds) 秒")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                }
                .padding(.top, 12)

                // 核心军功四联勋章带
                HStack(spacing: 14) {
                    statMedal(title: "斩敌与击溃", value: "\(settlement.enemyKilled) 人", icon: "flame.fill", tint: ImperialPalette.imperialGoldBright)
                    statMedal(title: "我军阵亡抚恤", value: "\(settlement.playerKilled) 人", icon: "shield.lefthalf.filled", tint: ImperialPalette.legionCrimsonBright)
                    statMedal(title: "医帐包扎归建", value: "+\(settlement.playerWoundedRecovered) 人", icon: "cross.case.fill", tint: ImperialPalette.jadeSupply)
                    statMedal(title: "主帅军功历练", value: "+\(settlement.commanderExpGained) EXP", icon: "crown.fill", tint: Color.orange)
                }
                .frame(maxWidth: 980)

                HStack(alignment: .top, spacing: 16) {
                    // 左卡：战略态势与缴获物资详单
                    ImperialPanel(padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "shippingbox.fill")
                                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                                Text("战场缴获辎重与战略军心影响")
                                    .font(.headline.bold())
                                    .foregroundStyle(ImperialPalette.imperialGold)
                            }

                            HStack(spacing: 12) {
                                lootPill(label: "黄金", amount: settlement.lootedGold, tint: ImperialPalette.imperialGoldBright)
                                lootPill(label: "良木", amount: settlement.lootedWood, tint: Color(red: 0.45, green: 0.82, blue: 0.44))
                                lootPill(label: "军粮", amount: settlement.lootedGrain, tint: Color.orange)
                            }

                            Divider()

                            Text("阵前生擒敌军战俘：\(settlement.capturedPrisoners) 名")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(ImperialPalette.parchmentText)

                            Text(moraleStrategicImpactText)
                                .font(.caption)
                                .foregroundStyle(ImperialPalette.parchmentMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 右卡：战俘三选一帝国诏令
                    ImperialPanel(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "scroll.fill")
                                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                                Text("战俘处置三选一诏令（共 \(settlement.capturedPrisoners) 俘）")
                                    .font(.headline.bold())
                                    .foregroundStyle(ImperialPalette.imperialGold)
                            }

                            let pCount = settlement.capturedPrisoners
                            let estInfantry = max(0, Int((Double(pCount) * 0.60).rounded()))
                            let estRansom = pCount * 12
                            let estPorters = pCount / 2

                            prisonerOptionButton(
                                choice: .incorporateInfantry,
                                title: "劝降收编 · 充实军团步兵",
                                subtitle: "补充刀盾步兵 +\(estInfantry) 人（需拨付口粮 \(estInfantry * 10)）",
                                disabled: pCount == 0
                            )
                            prisonerOptionButton(
                                choice: .ransomForGoldAndCredibility,
                                title: "礼送索赎 · 彰示帝国仁义",
                                subtitle: "换取赎金 +\(estRansom) 黄金，天下外交信誉 +2",
                                disabled: pCount == 0
                            )
                            prisonerOptionButton(
                                choice: .conscriptSupplyPorters,
                                title: "押充民夫 · 随军营建搬运",
                                subtitle: "补充辎重工兵 +\(estPorters) 人，随军干粮 +\(pCount * 4)",
                                disabled: pCount == 0
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: 980)

                Spacer()

                HStack(spacing: 16) {
                    if router.launchContext.entryMode == .campaign {
                        Button("确认战果回写九州版图 · 返回战略大地图 ›") {
                            BattleAudioEngine.shared.play(.drumMarch)
                            router.applyCampaignSettlementAndReturn(prisonerChoice: prisonerChoice)
                        }
                        .buttonStyle(ImperialCrimsonButtonStyle())
                    } else {
                        Button("重返点兵台再战一局 ›") {
                            BattleAudioEngine.shared.play(.warHorn)
                            router.navigate(to: .preBattleSetup)
                        }
                        .buttonStyle(ImperialCrimsonButtonStyle())
                    }

                    Button("凯旋返回主帅大帐（主菜单）") {
                        BattleAudioEngine.shared.play(.uiClick)
                        if router.launchContext.entryMode == .campaign && router.hasUnappliedCampaignSettlement {
                            router.applyCampaignSettlementAndReturn(prisonerChoice: prisonerChoice)
                        }
                        router.returnToMainMenu()
                    }
                    .buttonStyle(ImperialBronzeButtonStyle())
                }
                .padding(.bottom, 16)
            }
            .padding(24)
        }
        .onAppear {
            if settlement.isVictory {
                BattleAudioEngine.shared.play(.victoryFanfare)
            } else {
                BattleAudioEngine.shared.play(.defeatBell)
            }
        }
    }

    private func statMedal(title: String, value: String, icon: String, tint: Color) -> some View {
        ImperialPanel(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2.bold())
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                    Text(value)
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(ImperialPalette.parchmentText)
                }
                Spacer()
            }
        }
    }

    private func lootPill(label: String, amount: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(ImperialPalette.parchmentMuted)
            Text("+\(amount)")
                .font(.callout.monospacedDigit().bold())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(ImperialPalette.obsidianElevated)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        )
    }

    private func prisonerOptionButton(
        choice: CampaignPrisonerDisposition,
        title: String,
        subtitle: String,
        disabled: Bool
    ) -> some View {
        let selected = (prisonerChoice == choice) && !disabled
        return Button {
            BattleAudioEngine.shared.play(.uiClick)
            prisonerChoice = choice
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.seal.fill" : "circle")
                    .foregroundStyle(selected ? ImperialPalette.imperialGoldBright : ImperialPalette.parchmentMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.bold())
                        .foregroundStyle(ImperialPalette.parchmentText)
                    Text(subtitle)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                }
                Spacer()
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? ImperialPalette.obsidianElevated : ImperialPalette.obsidianDeep.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(selected ? ImperialPalette.imperialGoldBright : ImperialPalette.bronzeBorder.opacity(0.35), lineWidth: selected ? 1.4 : 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1.0)
    }
}
