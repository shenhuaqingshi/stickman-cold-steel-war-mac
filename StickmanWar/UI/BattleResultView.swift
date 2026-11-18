import SwiftUI

/// 核心路由 5：战后军功结算页（展示真实伤亡统计、医帐伤兵救治恢复、俘虏三选一处置、粮械缴获与战役版图回写）
public struct BattleResultView: View {
    @Bindable var router: AppRouter
    @State private var prisonerChoice: CampaignPrisonerDisposition = .ransomForGoldAndCredibility

    private var settlement: PostBattleSettlementSummary {
        router.latestSettlement
    }

    private var outcomeHeadline: String {
        switch settlement.outcomeReason {
        case .enemyBaseDestroyed: return "大捷 · 捣毁敌军本阵大营"
        case .enemyArmyRouted: return "大捷 · 敌军士气崩盘全线溃散"
        case .siegeDefenseHeld: return "守城大捷 · 雄关坚守期满"
        case .truceNegotiated: return "罢兵休战 · 阵前停火协议生效"
        case .playerCommanderMartyred: return "重创败北 · 主帅阵前殉国 / 本阵失守"
        case .playerArmyRouted: return "惜败退守 · 全军整编再战"
        case .ongoing: return settlement.isVictory ? "凯旋大捷" : "战局结束"
        }
    }

    private var moraleStrategicImpactText: String {
        if settlement.outcomeReason == .playerCommanderMartyred {
            return "⚠️ 主帅二次重创落马：战役模式下已由亲卫抢回后方，未来 2 回合处于【重伤休养】属性折损态。"
        } else if settlement.isVictory {
            return "🔥 三军士气如虹：敌军厌战度飙升，若系【围点打援】伏击战捷将直接令孤城守军初始士气暴跌 -25！"
        } else if settlement.outcomeReason == .truceNegotiated {
            return "🤝 双方依约停火止戈，各自收拢伤兵重整防线。"
        } else {
            return "🛡 医帐全力救治重伤员，建议回城补充粮草与破甲兵种后再图反攻。"
        }
    }

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 18) {
            // 胜负主横幅
            VStack(spacing: 6) {
                Text(outcomeHeadline)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(settlement.isVictory ? .yellow : (settlement.outcomeReason == .truceNegotiated ? .cyan : .red))

                let pName = FactionConfig.config(for: settlement.playerFaction)?.name ?? ""
                let eName = FactionConfig.config(for: settlement.enemyFaction)?.name ?? ""
                let nodeTag: String = {
                    guard let nid = router.launchContext.targetNodeId,
                          let cName = CampaignMapConfig.node(byId: nid)?.name else { return "" }
                    return " · 战场：【\(cName)】"
                }()
                Text("\(pName) vs \(eName) · \(settlement.scenarioType.displayName)\(nodeTag) · 鏖战历时 \(settlement.durationSeconds) 秒")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)

            HStack(alignment: .top, spacing: 16) {
                // 左卡：真实两军伤亡、医帐救治与士气战略影响
                GroupBox("两军伤亡、医帐救治与军心影响") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("• 我军永久阵亡抚恤：\(settlement.playerKilled) 人")
                        Text("• 随军医帐包扎归建伤兵：+\(settlement.playerWoundedRecovered) 人")
                            .foregroundStyle(.green)
                        Text("• 斩首与击溃敌军主力：\(settlement.enemyKilled) 人")
                        Text("• 阵前生擒敌军战俘：\(settlement.capturedPrisoners) 人")
                        Text("• 统帅军功历练晋升：+\(settlement.commanderExpGained) EXP")
                            .foregroundStyle(.orange)

                        Divider()

                        Text(moraleStrategicImpactText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                // 右卡：战场缴获物资与战俘三选一处置策略
                GroupBox("战场缴获与战俘处置决策") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("缴获物资：金 +\(settlement.lootedGold)  |  木 +\(settlement.lootedWood)  |  粮草 +\(settlement.lootedGrain)")
                            .font(.callout.monospacedDigit().bold())
                            .foregroundStyle(.yellow)

                        Divider()

                        let pCount = settlement.capturedPrisoners
                        let estInfantry = max(0, Int((Double(pCount) * 0.60).rounded()))
                        let estRansom = pCount * 12
                        let estPorters = pCount / 2

                        Picker("战俘处置方案（共 \(pCount) 名俘虏）", selection: $prisonerChoice) {
                            Text("劝降收编：补充刀盾轻步兵 +\(estInfantry) 人（耗粮 \(estInfantry * 10)）")
                                .tag(CampaignPrisonerDisposition.incorporateInfantry)
                            Text("遣返索赎：换取赎金 +\(estRansom) 金，外交信誉 +2")
                                .tag(CampaignPrisonerDisposition.ransomForGoldAndCredibility)
                            Text("押充民夫：补充辎重工兵 +\(estPorters) 人，随军口粮 +\(pCount * 4)")
                                .tag(CampaignPrisonerDisposition.conscriptSupplyPorters)
                        }
                        .pickerStyle(.radioGroup)
                        .disabled(pCount == 0)

                        if pCount == 0 {
                            Text("本场会战未生擒战俘，战俘处置项无需选择。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            .frame(maxWidth: 960)

            Spacer()

            HStack(spacing: 16) {
                if router.launchContext.entryMode == .campaign {
                    Button("确认战果回写天下态势 · 返回战略大地图 ›") {
                        router.applyCampaignSettlementAndReturn(prisonerChoice: prisonerChoice)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("重返点兵台再战一局 ›") {
                        router.navigate(to: .preBattleSetup)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button("凯旋返回主帅大帐（主菜单）") {
                    if router.launchContext.entryMode == .campaign && router.hasUnappliedCampaignSettlement {
                        router.applyCampaignSettlementAndReturn(prisonerChoice: prisonerChoice)
                    }
                    router.returnToMainMenu()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
