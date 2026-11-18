import AppKit
import SwiftUI

/// 原生 AppKit 滚轮与双指触控板滚动捕获层（使外接鼠标滚轮可直接缩放 3600×2400 战略大地图，双指滑动可漫游大地图）
private struct MacCampaignScrollCatcher: NSViewRepresentable {
    var invertZoom: Bool
    var onScrollPan: @MainActor (CGFloat, CGFloat) -> Void
    var onZoomFactor: @MainActor (Double) -> Void

    func makeNSView(context: Context) -> ScrollCatchingNSView {
        let view = ScrollCatchingNSView()
        view.invertZoom = invertZoom
        view.onScrollPan = onScrollPan
        view.onZoomFactor = onZoomFactor
        return view
    }

    func updateNSView(_ nsView: ScrollCatchingNSView, context: Context) {
        nsView.invertZoom = invertZoom
        nsView.onScrollPan = onScrollPan
        nsView.onZoomFactor = onZoomFactor
    }

    @MainActor
    final class ScrollCatchingNSView: NSView {
        var invertZoom: Bool = false
        var onScrollPan: (@MainActor (CGFloat, CGFloat) -> Void)?
        var onZoomFactor: (@MainActor (Double) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || !event.hasPreciseScrollingDeltas {
                let rawDelta = invertZoom ? -event.scrollingDeltaY : event.scrollingDeltaY
                guard abs(rawDelta) > 0.01 else { return }
                let factor = rawDelta > 0 ? 1.07 : 0.93
                onZoomFactor?(factor)
            } else {
                onScrollPan?(event.scrollingDeltaX, event.scrollingDeltaY)
            }
        }
    }
}

private enum CampaignRightTab: String, CaseIterable, Identifiable {
    case nodeAndMarch = "城关与出兵"
    case armyAndTech = "军备与科技"
    case diplomacy = "外交纵横"
    case warChronicle = "天下战报"

    var id: String { rawValue }
}

/// 核心路由 2：战役战略大地图与外交纵横页（3600×2400 · 8大区域 · 40座城关 · 78条对称道路 · 实时 BFS 粮道 · 完整外交与回合推演）
public struct CampaignMapView: View {
    @Bindable var router: AppRouter

    @State private var mapZoom: Double = 0.62
    @State private var panOffset: CGSize = .zero
    @State private var dragBaseOffset: CGSize = .zero
    @State private var selectedNodeId: String = "yl_capital"
    @State private var rightTab: CampaignRightTab = .nodeAndMarch

    // 出兵与围点打援交互状态
    @State private var preferredAttackScenario: BattleScenarioType? = nil
    @State private var ambushBesiegeTargetId: String = ""
    @State private var recruitIntoMainArmy: Bool = true
    @State private var useShamoMercenaryGold: Bool = false
    @State private var localFeedback: String = ""

    // 背盟强阻断二次确认弹窗状态（对应 DESIGN.md 10.3）
    @State private var pendingBetrayalAssessment: BetrayalImpactAssessment? = nil
    @State private var pendingBetrayalTargetFaction: FactionId? = nil
    @State private var pendingBetrayalMarchNodeId: String? = nil
    @State private var showBetrayalAlert: Bool = false

    // 外交纵横与媾和谈判表单状态
    @State private var selectedDiploFaction: FactionId = .canglang
    @State private var peaceGoldIndemnity: Double = 150.0
    @State private var peaceGrainPerTurn: Double = 20.0
    @State private var peaceTruceTurns: Int = 8
    @State private var peaceCededNodeIds: Set<String> = []
    @State private var activeCounterOffer: PeaceOfferTerms? = nil
    @State private var discordSecondFaction: FactionId = .tieying

    private var world: CampaignWorldState {
        router.campaignEngine.worldState
    }

    private var playerFaction: FactionId {
        world.playerFaction
    }

    private var playerState: CampaignFactionState {
        router.campaignEngine.factionState(for: playerFaction)
    }

    private var selectedNodeConfig: CampaignNodeConfig {
        CampaignMapConfig.node(byId: selectedNodeId) ?? CampaignMapConfig.allNodes[0]
    }

    private var selectedNodeState: CampaignNodeState? {
        router.campaignEngine.nodeState(for: selectedNodeId)
    }

    private var selectedSupplyDetail: CampaignSupplyRouteEvaluation {
        router.campaignEngine.supplyRouteDetail(forNodeId: selectedNodeId)
    }

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 0) {
            topStrategicBar

            if let defensiveCtx = world.pendingDefensivePrompt {
                urgentDefensiveBanner(defensiveCtx)
            }

            if world.victoryStatus != .ongoing {
                campaignOutcomeBanner(world.victoryStatus)
            }

            Divider()

            HSplitView {
                // 左侧主视口：3600×2400 拓扑大地图画布 + 右上角缩略小地图 + 左下角反馈条
                GeometryReader { geo in
                    ZStack(alignment: .topTrailing) {
                        campaignCanvas(viewportSize: geo.size)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        panOffset = CGSize(
                                            width: dragBaseOffset.width + value.translation.width,
                                            height: dragBaseOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        dragBaseOffset = panOffset
                                    }
                            )
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        let next = mapZoom * value.magnification
                                        mapZoom = max(GameConstants.campaignZoomMin, min(GameConstants.campaignZoomMax, next))
                                    }
                            )

                        minimapOverlay(viewportSize: geo.size)
                            .padding(14)

                        if !localFeedback.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    Text(localFeedback)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.78)))
                                    Spacer()
                                }
                                .padding(12)
                            }
                        }
                    }
                }
                .frame(minWidth: 660, maxWidth: .infinity, maxHeight: .infinity)

                // 右侧四合一战略军情台
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $rightTab) {
                        ForEach(CampaignRightTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch rightTab {
                    case .nodeAndMarch:
                        nodeAndMarchPanel
                    case .armyAndTech:
                        armyAndTechPanel
                    case .diplomacy:
                        diplomacyFullPanel
                    case .warChronicle:
                        warChroniclePanel
                    }
                }
                .padding(14)
                .frame(minWidth: 375, idealWidth: 410, maxWidth: 465, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectedNodeId = playerState.mainArmyNodeId
            if selectedDiploFaction == playerFaction {
                selectedDiploFaction = FactionId.allCases.first(where: { $0 != playerFaction }) ?? .canglang
            }
            localFeedback = router.bannerMessage
        }
        .alert("撕毁条约 · 背盟重罚二次确认", isPresented: $showBetrayalAlert) {
            Button("悬崖勒马（取消）", role: .cancel) {
                pendingBetrayalAssessment = nil
                pendingBetrayalTargetFaction = nil
                pendingBetrayalMarchNodeId = nil
            }
            Button("执意背盟开战！", role: .destructive) {
                confirmAndExecuteBetrayal()
            }
        } message: {
            if let assess = pendingBetrayalAssessment, let target = pendingBetrayalTargetFaction {
                let tName = FactionConfig.config(for: target)?.name ?? target.rawValue
                Text("""
                你与【\(tName)】尚有未到期的和平或同盟条约！
                强行撕毁条约将立即触发以下不可逆雪崩惩罚：
                • 我方外交信誉暴扣 \(assess.credibilityDelta)（低于 40 全图禁结盟、求和溢价 +80%）；
                • 【\(tName)】关系锁死 -100 并激活 \(assess.vendettaLockTurns) 回合【血海世仇】（拒一切议和）；
                • 天下其余诸侯关系一律 \(assess.globalRelationDelta)；
                • 随后 2 场战斗我军初始士气 \(Int(assess.battleMoralePenalty))！
                """)
            }
        }
    }

    // MARK: - 顶部全局战略指挥栏

    private var topStrategicBar: some View {
        let pCfg = FactionConfig.config(for: playerFaction)
        let ownedCount = router.campaignEngine.controlledNodes(of: playerFaction).count
        let mainNodeName = CampaignMapConfig.node(byId: playerState.mainArmyNodeId)?.name ?? playerState.mainArmyNodeId

        return HStack(spacing: 12) {
            Button("‹ 主菜单") {
                router.returnToMainMenu()
            }
            .buttonStyle(.bordered)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: pCfg?.primaryColorHex ?? "#C62828"))
                    .frame(width: 10, height: 10)
                Text("\(pCfg?.name ?? "") · 第 \(world.turnNumber) 回合")
                    .font(.headline)
                Text("城关 \(ownedCount)/\(GameConstants.campaignNodeCount)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }

            Divider().frame(height: 18)

            HStack(spacing: 10) {
                Text("金 \(playerState.gold)")
                    .foregroundStyle(.yellow)
                Text("木 \(playerState.wood)")
                    .foregroundStyle(.green)
                Text("粮 \(playerState.grain)")
                    .foregroundStyle(.orange)
                Text("信誉 \(playerState.credibility)")
                    .foregroundStyle(playerState.credibility < 40 ? .red : .cyan)
                Text("主力[\(mainNodeName)] 行军力 \(String(format: "%.1f", playerState.mainArmyActionPoints))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit().bold())

            Spacer()

            HStack(spacing: 6) {
                Slider(value: $mapZoom, in: GameConstants.campaignZoomMin...GameConstants.campaignZoomMax)
                    .frame(width: 95)
                Button("复位") {
                    mapZoom = 0.62
                    panOffset = .zero
                    dragBaseOffset = .zero
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("存军档 (⌘S)") {
                router.saveCurrentCampaignSnapshot(toSlot: 1)
                localFeedback = router.bannerMessage
            }
            .buttonStyle(.bordered)

            Button("推进下一回合 ›") {
                if world.pendingDefensivePrompt != nil {
                    localFeedback = "⚠️ 敌军正围攻我方城池！请先点击顶部红条【立即披甲登城迎战】击退敌军后再推进下一回合。"
                    return
                }
                let report = router.campaignEngine.advanceTurn()
                router.latestTurnReport = report
                router.autoSaveCampaignSilently()
                let headlineText = report.aiWorldHeadlines.first.map { " · 天下：\($0)" } ?? ""
                localFeedback = "已进入第 \(report.newTurnNumber) 回合：税金 +\(report.playerGoldEarned + report.playerTradeGoldEarned)、木 +\(report.playerWoodEarned)、净粮 \(report.playerGrainNetChange >= 0 ? "+\(report.playerGrainNetChange)" : "\(report.playerGrainNetChange)")\(headlineText)"
                if !report.warningSeveredNodeIds.isEmpty || !report.starvationAttritionByNode.isEmpty {
                    rightTab = .warChronicle
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(world.pendingDefensivePrompt != nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private func urgentDefensiveBanner(_ ctx: RouteLaunchContext) -> some View {
        let eName = FactionConfig.config(for: ctx.enemyFaction)?.name ?? ctx.enemyFaction.rawValue
        let cityName = ctx.targetNodeId.flatMap { CampaignMapConfig.node(byId: $0)?.name } ?? "边境要塞"
        return HStack {
            Text("🚨 烽火急报：【\(eName)】大军猛攻我方【\(cityName)】（\(ctx.scenarioType.displayName)）！")
                .font(.callout.bold())
                .foregroundStyle(.white)
            Spacer()
            Button("立即披甲登城迎战 ›") {
                router.enterCampaignPreBattle(context: ctx, modifiers: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.86))
    }

    private func campaignOutcomeBanner(_ status: CampaignVictoryStatus) -> some View {
        let text: String = {
            switch status {
            case .ongoing:
                return ""
            case .capitalUnificationVictory(let winner):
                let name = FactionConfig.config(for: winner)?.name ?? ""
                return "🏆 天下一统大捷！【\(name)】尽揽八州王都，缔造万世冷兵器帝国！"
            case .hegemonyAllianceVictory(let winner, let allies):
                let name = FactionConfig.config(for: winner)?.name ?? ""
                return "🏆 合纵霸权胜利！【\(name)】携 \(allies.count) 盟邦共掌天下八成城池与八大王都！"
            case .playerDefeated(let reason):
                return "💔 霸业中道崩殂：\(reason)（可读取军档或返回主菜单重整旗鼓）"
            }
        }()
        return HStack {
            Text(text)
                .font(.callout.bold())
            Spacer()
            Button("开启新战役") {
                router.startMode(.campaign, playerFaction: playerFaction, forceNewCampaign: true)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.26))
    }

    // MARK: - 3600×2400 动态战略大地图画布与实时 BFS 粮道高亮

    private func campaignCanvas(viewportSize: CGSize) -> some View {
        let mapW = GameConstants.campaignMapWidth
        let mapH = GameConstants.campaignMapHeight
        let originX = (viewportSize.width - mapW * mapZoom) * 0.5 + panOffset.width
        let originY = (viewportSize.height - mapH * mapZoom) * 0.5 + panOffset.height
        let supplyPath = selectedSupplyDetail.shortestPathNodeIds

        var supplyEdgePairs = Set<String>()
        if supplyPath.count >= 2 {
            for idx in 0..<(supplyPath.count - 1) {
                let a = supplyPath[idx]
                let b = supplyPath[idx + 1]
                supplyEdgePairs.insert(a < b ? "\(a)--\(b)" : "\(b)--\(a)")
            }
        }

        let aiMainArmyNodes: Set<String> = Set(
            world.factions.filter { !$0.isEliminated && $0.factionId != playerFaction }.map(\.mainArmyNodeId)
        )

        return ZStack(alignment: .topLeading) {
            Color(red: 0.11, green: 0.10, blue: 0.09)

            MacCampaignScrollCatcher(
                invertZoom: router.userSettings.invertScrollZoom,
                onScrollPan: { dx, dy in
                    panOffset = CGSize(width: panOffset.width + dx, height: panOffset.height + dy)
                    dragBaseOffset = panOffset
                },
                onZoomFactor: { factor in
                    let next = mapZoom * factor
                    mapZoom = max(GameConstants.campaignZoomMin, min(GameConstants.campaignZoomMax, next))
                }
            )

            // 78 条无向双向道路线 + 选中城关 BFS 最短补给粮道高亮线
            Canvas { context, _ in
                for edge in CampaignMapConfig.allRoadEdges {
                    guard let from = CampaignMapConfig.node(byId: edge.fromNodeId),
                          let to = CampaignMapConfig.node(byId: edge.toNodeId) else { continue }
                    let ownerA = world.nodesById[from.id]?.owner ?? from.initialOwner
                    let ownerB = world.nodesById[to.id]?.owner ?? to.initialOwner
                    let p1 = CGPoint(x: originX + from.x * mapZoom, y: originY + from.y * mapZoom)
                    let p2 = CGPoint(x: originX + to.x * mapZoom, y: originY + to.y * mapZoom)
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)

                    let isHighlightedSupply = supplyEdgePairs.contains(edge.id)
                    let isWarBorder = (ownerA != ownerB) && world.diplomacy.status(between: ownerA, and: ownerB) == .war
                    let isBorderRoad = (ownerA != ownerB)

                    if isHighlightedSupply {
                        context.stroke(path, with: .color(Color.green.opacity(0.90)), style: StrokeStyle(lineWidth: 3.4))
                    } else if isWarBorder {
                        context.stroke(path, with: .color(Color.red.opacity(0.68)), style: StrokeStyle(lineWidth: 2.2, dash: [6, 3]))
                    } else {
                        context.stroke(
                            path,
                            with: .color(isBorderRoad ? Color.orange.opacity(0.42) : Color.white.opacity(0.26)),
                            style: StrokeStyle(lineWidth: isBorderRoad ? 1.7 : 2.1, dash: isBorderRoad ? [6, 4] : [])
                        )
                    }
                }
            }

            // 40 座城关动态节点按钮
            ForEach(CampaignMapConfig.allNodes) { node in
                let liveState = world.nodesById[node.id]
                let liveOwner = liveState?.owner ?? node.initialOwner
                let factionColor = Color(hex: FactionConfig.config(for: liveOwner)?.primaryColorHex ?? "#90A4AE")
                let isSelected = (node.id == selectedNodeId)
                let isPlayerMainArmy = (playerState.mainArmyNodeId == node.id)
                let hasAiMainArmy = aiMainArmyNodes.contains(node.id)
                let isSevered = (liveState?.cachedSupplyHops == nil)
                let isUnderSiege = (liveState?.underSiegeBy != nil)
                let hasAmbush = (liveState?.reliefAmbush != nil)
                let posX = originX + node.x * mapZoom
                let posY = originY + node.y * mapZoom

                Button {
                    selectedNodeId = node.id
                } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(factionColor)
                                .frame(
                                    width: node.nodeType == .capitalCitadel ? 23 : 16,
                                    height: node.nodeType == .capitalCitadel ? 23 : 16
                                )
                            Circle()
                                .stroke(
                                    isSelected ? Color.yellow : (isPlayerMainArmy ? Color.green : Color.white.opacity(0.85)),
                                    lineWidth: (isSelected || isPlayerMainArmy) ? 3.0 : 1.3
                                )
                                .frame(
                                    width: node.nodeType == .capitalCitadel ? 28 : 20,
                                    height: node.nodeType == .capitalCitadel ? 28 : 20
                                )
                        }
                        if mapZoom >= 0.50 || node.nodeType == .capitalCitadel || isSelected || isPlayerMainArmy {
                            let statusPrefix: String = {
                                var tags = ""
                                if isPlayerMainArmy { tags += "★帅 " }
                                else if hasAiMainArmy { tags += "⚑ " }
                                if isUnderSiege { tags += "⚔️" }
                                if hasAmbush { tags += "🎯" }
                                if isSevered { tags += "⚠️" }
                                return tags
                            }()
                            Text("\(statusPrefix)\(node.name)")
                                .font(.system(size: 11, weight: (isSelected || isPlayerMainArmy) ? .bold : .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.76)))
                                .foregroundStyle(isSevered ? Color.red : (isSelected ? Color.yellow : Color.white))
                        }
                    }
                }
                .buttonStyle(.plain)
                .position(x: posX, y: posY)
            }
        }
        .clipped()
    }

    private func minimapOverlay(viewportSize: CGSize) -> some View {
        let miniW: CGFloat = 205
        let miniH: CGFloat = 136
        let scaleX = miniW / GameConstants.campaignMapWidth
        let scaleY = miniH / GameConstants.campaignMapHeight

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.84))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.5), lineWidth: 1))

            Canvas { context, _ in
                for node in CampaignMapConfig.allNodes {
                    let liveOwner = world.nodesById[node.id]?.owner ?? node.initialOwner
                    let hex = FactionConfig.config(for: liveOwner)?.primaryColorHex ?? "#FFFFFF"
                    let pt = CGPoint(x: node.x * scaleX, y: node.y * scaleY)
                    let r: CGFloat = node.nodeType == .capitalCitadel ? 3.8 : 2.5
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(hex: hex)))
                }

                let mapOriginX = (viewportSize.width - GameConstants.campaignMapWidth * mapZoom) * 0.5 + panOffset.width
                let mapOriginY = (viewportSize.height - GameConstants.campaignMapHeight * mapZoom) * 0.5 + panOffset.height
                let visibleLogicX = max(0, -mapOriginX / mapZoom)
                let visibleLogicY = max(0, -mapOriginY / mapZoom)
                let visibleLogicW = min(GameConstants.campaignMapWidth, viewportSize.width / mapZoom)
                let visibleLogicH = min(GameConstants.campaignMapHeight, viewportSize.height / mapZoom)
                let box = CGRect(
                    x: visibleLogicX * scaleX,
                    y: visibleLogicY * scaleY,
                    width: min(miniW, visibleLogicW * scaleX),
                    height: min(miniH, visibleLogicH * scaleY)
                )
                context.stroke(Path(box), with: .color(.yellow.opacity(0.88)), lineWidth: 1.2)
            }
        }
        .frame(width: miniW, height: miniH)
    }

    // MARK: - 右栏页签 1：城关实时军情、BFS 粮道与出兵/围点打援

    private var nodeAndMarchPanel: some View {
        let liveOwner = selectedNodeState?.owner ?? selectedNodeConfig.initialOwner
        let ownerCfg = FactionConfig.config(for: liveOwner)
        let allies = world.diplomacy.alliedFactions(of: playerFaction)
        let isFriendlyOrAllied = (liveOwner == playerFaction) || allies.contains(liveOwner)
        let supplyText: String = {
            switch selectedSupplyDetail.status {
            case .fullSupply(let hops):
                return "✅ 近境无损补给（距仓城 \(hops) 跳 · 效率 100%）"
            case .extendedMarch(let hops):
                return "🔸 长途远征（\(hops) 跳 · 耗粮+25%，携粮-15%）"
            case .overextended(let hops):
                return "🟠 孤军悬远（\(hops) 跳 · 耗粮+50%，建议结盟借道）"
            case .severed(let turns):
                return turns == 1
                    ? "⚠️ 粮道断绝第 1 回合（消耗随军干粮预警！）"
                    : "🚨 粮道断绝 \(turns) 回合【饥疲】（逃亡 -8%/回合，士气锁 65）"
            }
        }()

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(selectedNodeConfig.name)
                                .font(.title3.bold())
                            Spacer()
                            Text(selectedNodeConfig.nodeType.displayName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        }
                        Text("第 \(selectedNodeConfig.regionIndex) 区 · \(selectedNodeConfig.regionName) · 当前控制：【\(ownerCfg?.name ?? "")】")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("地形：\(selectedNodeConfig.terrain.displayName) · 城墙耐久：\(selectedNodeState?.wallIntegrity ?? 0)/\(selectedNodeState?.maxWallIntegrity ?? 1000)")
                            .font(.callout.monospacedDigit())
                        Text("城防驻军：\(selectedNodeState?.totalGarrisonTroops ?? 0) 队 · 士气修正：\(Int(selectedNodeState?.garrisonMoraleModifier ?? 0))")
                            .font(.caption.monospacedDigit())
                        Text("每回合税赋：金 \(selectedNodeConfig.goldYield) / 木 \(selectedNodeConfig.woodYield) / 粮 \(selectedNodeConfig.grainYield)")
                            .font(.caption.monospacedDigit())
                        Divider()
                        Text(supplyText)
                            .font(.caption.bold())
                            .foregroundStyle(selectedSupplyDetail.shortestPathNodeIds.isEmpty ? .red : .green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                // 主力军团行军 / 跨境进攻操作卡
                GroupBox("统帅主力调度（当前驻扎：\(CampaignMapConfig.node(byId: playerState.mainArmyNodeId)?.name ?? "")）") {
                    VStack(alignment: .leading, spacing: 8) {
                        if selectedNodeId == playerState.mainArmyNodeId {
                            Text("★ 我方主力野战军团正驻扎于此城（兵力 \(playerState.totalMainArmyTroops) · 剩余行军力 \(String(format: "%.1f", playerState.mainArmyActionPoints))）")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if isFriendlyOrAllied {
                            Button {
                                performMarch(toNodeId: selectedNodeId, confirmBetrayal: false)
                            } label: {
                                Text("调遣主力和平移防至【\(selectedNodeConfig.name)】")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Picker("战法选择", selection: $preferredAttackScenario) {
                                Text("按地形城防自动判定").tag(Optional<BattleScenarioType>.none)
                                Text("标准野战会战").tag(Optional<BattleScenarioType>.some(.fieldPitched))
                                Text("攻城攻坚战").tag(Optional<BattleScenarioType>.some(.siegeAssault))
                                Text("劫营夜袭（首轮震慑敌士气）").tag(Optional<BattleScenarioType>.some(.nightRaid))
                                Text("密林伏击（先手破隐奇袭）").tag(Optional<BattleScenarioType>.some(.ambush))
                                Text("护粮/劫粮战").tag(Optional<BattleScenarioType>.some(.convoyEscort))
                            }
                            .font(.caption)

                            Button {
                                performMarch(toNodeId: selectedNodeId, confirmBetrayal: false)
                            } label: {
                                Text("挥师进攻【\(selectedNodeConfig.name)】（进入战前整军 ›）")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Text("提示：跨境进攻须先将主力移防至与目标城池直接相邻的前线城关。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // 围点打援预设伏兵入口：若相邻节点存在交战中的敌城，允许在此咽喉布设打援伏兵
                        let adjacentEnemyWarCities = selectedNodeConfig.neighbors.filter { nbId in
                            guard let nbOwner = world.nodesById[nbId]?.owner, nbOwner != playerFaction else { return false }
                            return world.diplomacy.status(between: playerFaction, and: nbOwner) == .war
                        }
                        if !adjacentEnemyWarCities.isEmpty {
                            Divider()
                            Text("奇谋【围点打援】：在此咽喉设伏截击驰援敌军（大捷令孤城守军 -25 士气）")
                                .font(.caption2.bold())
                            HStack {
                                let safeAmbushBinding = Binding<String>(
                                    get: {
                                        adjacentEnemyWarCities.contains(ambushBesiegeTargetId)
                                            ? ambushBesiegeTargetId
                                            : adjacentEnemyWarCities[0]
                                    },
                                    set: { ambushBesiegeTargetId = $0 }
                                )
                                Picker("围困孤城", selection: safeAmbushBinding) {
                                    ForEach(adjacentEnemyWarCities, id: \.self) { cid in
                                        Text(CampaignMapConfig.node(byId: cid)?.name ?? cid).tag(cid)
                                    }
                                }
                                .labelsHidden()
                                Button("布设伏兵") {
                                    let chosen = adjacentEnemyWarCities.contains(ambushBesiegeTargetId) ? ambushBesiegeTargetId : adjacentEnemyWarCities[0]
                                    let res = router.campaignEngine.setupReliefAmbush(
                                        factionId: playerFaction,
                                        ambushNodeId: selectedNodeId,
                                        besiegedTargetNodeId: chosen
                                    )
                                    localFeedback = res.message
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(4)
                }

                // 连通邻接道路列表
                Text("连通道路邻城（共 \(selectedNodeConfig.neighbors.count) 条）：")
                    .font(.subheadline.bold())

                ForEach(selectedNodeConfig.neighbors, id: \.self) { nbId in
                    if let nbCfg = CampaignMapConfig.node(byId: nbId) {
                        let nbOwner = world.nodesById[nbId]?.owner ?? nbCfg.initialOwner
                        let nbFaction = FactionConfig.config(for: nbOwner)
                        Button {
                            selectedNodeId = nbId
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: nbFaction?.primaryColorHex ?? "#FFFFFF"))
                                    .frame(width: 8, height: 8)
                                Text(nbCfg.name)
                                    .font(.callout)
                                if playerState.mainArmyNodeId == nbId {
                                    Text("[主力驻地]")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.green)
                                }
                                Spacer()
                                Text("\(nbFaction?.name ?? "") · 驻军 \(world.nodesById[nbId]?.totalGarrisonTroops ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func performMarch(toNodeId targetId: String, confirmBetrayal: Bool) {
        let res = router.campaignEngine.executeMarchOrder(
            factionId: playerFaction,
            toNodeId: targetId,
            preferredScenario: preferredAttackScenario,
            confirmBetrayalIfNeeded: confirmBetrayal
        )
        switch res {
        case .invalidOrder(let reason):
            localFeedback = "行军受阻：\(reason)"
        case .relocatedPeacefully(let destId, _):
            let name = CampaignMapConfig.node(byId: destId)?.name ?? destId
            localFeedback = "主力军团已顺利移防进驻【\(name)】（剩余行军力 \(String(format: "%.1f", playerState.mainArmyActionPoints))）"
        case .requiresWarConfirmation(let assessment, let targetFac):
            pendingBetrayalAssessment = assessment
            pendingBetrayalTargetFaction = targetFac
            pendingBetrayalMarchNodeId = targetId
            showBetrayalAlert = true
        case .battleTriggered(let ctx, let mods):
            router.enterCampaignPreBattle(context: ctx, modifiers: mods)
        }
    }

    private func confirmAndExecuteBetrayal() {
        if let marchId = pendingBetrayalMarchNodeId {
            pendingBetrayalMarchNodeId = nil
            performMarch(toNodeId: marchId, confirmBetrayal: true)
        } else if let targetFac = pendingBetrayalTargetFaction {
            let impact = router.campaignEngine.declareWar(attacker: playerFaction, target: targetFac)
            localFeedback = "已撕毁条约向【\(FactionConfig.config(for: targetFac)?.name ?? "")】开战：\(impact.ruleExplanation)"
        }
        pendingBetrayalAssessment = nil
        pendingBetrayalTargetFaction = nil
    }

    // MARK: - 右栏页签 2：非对称征募与三阶专属科技研发

    private var armyAndTechPanel: some View {
        let pCfg = FactionConfig.config(for: playerFaction)
        let legalUnits = UnitConfig.recruitableUnits(for: playerFaction)

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("主帅统御与主力编制（人口 \(playerState.usedMainArmyPop)/\(GameConstants.defaultArmyPopCap)）") {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("统御等级 Lv.\(playerState.commanderLevel)（EXP \(playerState.commanderExp)/\(playerState.commanderLevel * 500)）")
                                .font(.callout.bold())
                            Spacer()
                            if playerState.commanderWoundedTurns > 0 {
                                Text("重伤休养剩余 \(playerState.commanderWoundedTurns) 回合")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            }
                        }
                        let rosterDesc = playerState.mainArmyRoster.map { stack in
                            "\(UnitConfig.stats(for: stack.unitId)?.name ?? "")×\(stack.count)"
                        }.joined(separator: " · ")
                        Text(rosterDesc.isEmpty ? "暂无兵力" : rosterDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("三阶专属军制科技") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pCfg?.uniqueTechs ?? []) { tech in
                            let unlocked = playerState.unlockedTechIds.contains(tech.id)
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("《\(tech.name)》")
                                        .font(.callout.bold())
                                    Text(tech.effectSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("耗资：金\(tech.cost.gold) / 木\(tech.cost.wood) / 粮\(tech.cost.grain)")
                                        .font(.caption2.monospacedDigit())
                                }
                                Spacer()
                                if unlocked {
                                    Text("已解锁")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                } else {
                                    Button("研发") {
                                        let res = router.campaignEngine.researchTechnology(factionId: playerFaction, techId: tech.id)
                                        localFeedback = res.message
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            Divider()
                        }
                    }
                    .padding(4)
                }

                GroupBox("征募兵员（每次 +4 人）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("直接编入统帅主力军团（取消则编入选中城关驻军）", isOn: $recruitIntoMainArmy)
                            .font(.caption)
                        if playerFaction == .shamo {
                            Toggle("沙漠商盟特权：耗纯金币即时征召雇佣军", isOn: $useShamoMercenaryGold)
                                .font(.caption)
                        }

                        ForEach(legalUnits) { unit in
                            let batchCost = router.campaignEngine.effectiveRecruitmentCost(
                                for: unit.id,
                                factionId: playerFaction,
                                count: 4,
                                useInstantMercenaryGold: playerFaction == .shamo && useShamoMercenaryGold
                            )
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unit.name)
                                        .font(.callout.bold())
                                    if let c = batchCost {
                                        Text("4人耗资：金\(c.gold) / 木\(c.wood) / 粮\(c.grain) · 人口\(unit.popCap * 4)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("+4 征召") {
                                    let targetNode = recruitIntoMainArmy ? playerState.mainArmyNodeId : selectedNodeId
                                    let res = router.campaignEngine.recruitUnits(
                                        factionId: playerFaction,
                                        unitId: unit.id,
                                        count: 4,
                                        intoMainArmy: recruitIntoMainArmy,
                                        atNodeId: targetNode,
                                        useInstantMercenaryGold: playerFaction == .shamo && useShamoMercenaryGold
                                    )
                                    localFeedback = res.message
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
    }

    // MARK: - 右栏页签 3：8 势力实时关系矩阵、结盟/宣战/调停与三档量化媾和谈判

    private var diplomacyFullPanel: some View {
        let otherFactions = FactionConfig.allFactions.filter { $0.id != playerFaction }
        let targetCfg = FactionConfig.config(for: selectedDiploFaction)
        let targetState = router.campaignEngine.factionState(for: selectedDiploFaction)
        let bilateral = world.diplomacy.bilateralState(between: playerFaction, and: selectedDiploFaction)
        let playerBorderNodes = router.campaignEngine.controlledNodes(of: playerFaction).map(\.id)

        // 检测是否存在两个正在互攻的我方军事盟友（激活双重同盟居中调停按钮）
        let myAllies = Array(world.diplomacy.alliedFactions(of: playerFaction))
        var warringAllyPair: (FactionId, FactionId)? = nil
        if myAllies.count >= 2 {
            for i in 0..<myAllies.count {
                for j in (i + 1)..<myAllies.count {
                    if world.diplomacy.status(between: myAllies[i], and: myAllies[j]) == .war {
                        warringAllyPair = (myAllies[i], myAllies[j])
                        break
                    }
                }
            }
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("八大诸侯邦交态势（我方信誉 \(playerState.credibility)/100）")
                    .font(.subheadline.bold())

                // 7 个非玩家势力列表
                ForEach(otherFactions) { other in
                    let bi = world.diplomacy.bilateralState(between: playerFaction, and: other.id)
                    let fSt = router.campaignEngine.factionState(for: other.id)
                    let cityCnt = router.campaignEngine.controlledNodes(of: other.id).count
                    let isChosen = (other.id == selectedDiploFaction)

                    Button {
                        selectedDiploFaction = other.id
                        activeCounterOffer = nil
                        peaceCededNodeIds.removeAll()
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: other.primaryColorHex))
                                .frame(width: 5, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(other.name)
                                        .font(.callout.bold())
                                    if fSt.isEliminated {
                                        Text("[已覆灭]")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("\(cityCnt)城 · 信誉\(fSt.credibility)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                let turnTag = bi.remainingTurns > 0 ? "(\(bi.remainingTurns)回合)" : ""
                                let vendettaTag = bi.vendettaLockTurns > 0 ? " · 血海世仇(\(bi.vendettaLockTurns))" : ""
                                Text("条约：\(bi.status.displayName)\(turnTag)\(vendettaTag)")
                                    .font(.caption2)
                                    .foregroundStyle(bi.status == .war ? .red : (bi.status == .alliance ? .green : .secondary))
                            }
                            Spacer()
                            Text(bi.relation > 0 ? "+\(bi.relation)" : "\(bi.relation)")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(bi.relation >= 25 ? .green : (bi.relation < 0 ? .red : .primary))
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isChosen ? Color(hex: other.primaryColorHex).opacity(0.18) : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isChosen ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let (allyA, allyB) = warringAllyPair {
                    let nameA = FactionConfig.config(for: allyA)?.name ?? ""
                    let nameB = FactionConfig.config(for: allyB)?.name ?? ""
                    GroupBox("双重同盟冲突调停（零信誉损失豁免）") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("我方两大盟友【\(nameA)】与【\(nameB)】爆发武装冲突！")
                                .font(.caption)
                            Button("居中斡旋促成 3 回合停火") {
                                let res = router.campaignEngine.mediateAlliedConflict(
                                    mediator: playerFaction,
                                    belligerentA: allyA,
                                    belligerentB: allyB
                                )
                                localFeedback = res.message
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                // 针对当前选中势力的真实外交行动台
                if !targetState.isEliminated {
                    GroupBox("对【\(targetCfg?.name ?? "")】派遣使节（当前：\(bilateral.status.displayName)）") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Button("馈赠 150 金") {
                                    let res = router.campaignEngine.sendDiplomaticGift(from: playerFaction, to: selectedDiploFaction, gold: 150, grain: 0)
                                    localFeedback = res.message
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("丝路通商") {
                                    let res = router.campaignEngine.signTradePact(proposer: playerFaction, target: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("互不侵犯") {
                                    let res = router.campaignEngine.signNonAggressionPact(proposer: playerFaction, target: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            HStack(spacing: 6) {
                                Button("缔结军事同盟") {
                                    let res = router.campaignEngine.formAlliance(proposer: playerFaction, target: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("王室联姻(150金)") {
                                    let res = router.campaignEngine.arrangeRoyalMarriage(proposer: playerFaction, target: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("纳贡/附庸") {
                                    let res = router.campaignEngine.establishVassalage(suzerain: playerFaction, vassal: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            let discordCandidates = otherFactions.filter { $0.id != selectedDiploFaction }
                            if let firstCand = discordCandidates.first {
                                let safeDiscordBinding = Binding<FactionId>(
                                    get: {
                                        discordCandidates.contains(where: { $0.id == discordSecondFaction })
                                            ? discordSecondFaction
                                            : firstCand.id
                                    },
                                    set: { discordSecondFaction = $0 }
                                )
                                HStack(spacing: 6) {
                                    Picker("离间对象", selection: safeDiscordBinding) {
                                        ForEach(discordCandidates) { cand in
                                            Text(cand.name).tag(cand.id)
                                        }
                                    }
                                    .labelsHidden()
                                    Button("密使离间(180金)") {
                                        let targetSecond = safeDiscordBinding.wrappedValue
                                        let res = router.campaignEngine.instigateDiscord(
                                            actor: playerFaction,
                                            targetA: selectedDiploFaction,
                                            targetB: targetSecond
                                        )
                                        localFeedback = res.message
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            Divider()

                            if bilateral.status != .war {
                                let warPreview = world.diplomacy.assessWarDeclarationImpact(attacker: playerFaction, target: selectedDiploFaction)
                                Text("开战预判：\(warPreview.ruleExplanation)")
                                    .font(.caption2)
                                    .foregroundStyle(warPreview.isBetrayalTriggered ? .red : .secondary)

                                Button("向【\(targetCfg?.name ?? "")】宣战") {
                                    if warPreview.isBetrayalTriggered {
                                        pendingBetrayalAssessment = warPreview
                                        pendingBetrayalTargetFaction = selectedDiploFaction
                                        pendingBetrayalMarchNodeId = nil
                                        showBetrayalAlert = true
                                    } else {
                                        let impact = router.campaignEngine.declareWar(attacker: playerFaction, target: selectedDiploFaction)
                                        localFeedback = "已向【\(targetCfg?.name ?? "")】正式宣战（\(impact.ruleExplanation)）"
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            } else {
                                // 交战状态下：完整可调筹码停火媾和谈判台（确保 Slider 上下界严格为步长 25 的整数倍，防止 Sonoma 滑块越界断言）
                                let maxGoldMultiple = max(100.0, Double((playerState.gold / 25) * 25))
                                let clampedGoldBinding = Binding<Double>(
                                    get: { min(maxGoldMultiple, max(-300.0, peaceGoldIndemnity)) },
                                    set: { peaceGoldIndemnity = $0 }
                                )
                                let effectiveGoldOffer = min(playerState.gold, Int(clampedGoldBinding.wrappedValue))

                                Text("🏳️ 停火媾和谈判（自由组合赔款/岁粮/割地/停战期）")
                                    .font(.caption.bold())

                                HStack {
                                    Text("赔付金币 \(effectiveGoldOffer)（负数为向敌索赔）")
                                        .font(.caption2.monospacedDigit())
                                    Spacer()
                                }
                                Slider(value: clampedGoldBinding, in: -300.0...maxGoldMultiple, step: 25.0)

                                HStack {
                                    Text("每回合纳粮 \(Int(peaceGrainPerTurn))")
                                        .font(.caption2.monospacedDigit())
                                    Spacer()
                                    Picker("停战期", selection: $peaceTruceTurns) {
                                        Text("5 回合").tag(5)
                                        Text("8 回合").tag(8)
                                        Text("12 回合").tag(12)
                                    }
                                    .frame(width: 120)
                                }
                                Slider(value: $peaceGrainPerTurn, in: 0.0...80.0, step: 10.0)

                                if playerBorderNodes.count > 1 {
                                    Menu("附带割让城关（已选 \(peaceCededNodeIds.count) 座）") {
                                        ForEach(playerBorderNodes, id: \.self) { nid in
                                            if nid != pCfgCapital(playerFaction) {
                                                let cname = CampaignMapConfig.node(byId: nid)?.name ?? nid
                                                Button(peaceCededNodeIds.contains(nid) ? "✓ \(cname)" : cname) {
                                                    if peaceCededNodeIds.contains(nid) {
                                                        peaceCededNodeIds.remove(nid)
                                                    } else {
                                                        peaceCededNodeIds.insert(nid)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .font(.caption)
                                }

                                let draftOffer = PeaceOfferTerms(
                                    proposer: playerFaction,
                                    target: selectedDiploFaction,
                                    goldIndemnity: effectiveGoldOffer,
                                    grainTributePerTurn: Int(peaceGrainPerTurn),
                                    cededNodeIds: Array(peaceCededNodeIds),
                                    truceTurns: peaceTruceTurns
                                )

                                Button("派遣议和使者递交国书") {
                                    let outcome = router.campaignEngine.proposePeaceOffer(draftOffer)
                                    switch outcome {
                                    case .accepted(let netScore):
                                        activeCounterOffer = nil
                                        peaceCededNodeIds.removeAll()
                                        localFeedback = String(format: "🤝 议和成功（净分 +%.1f）：双方正式停战 %d 回合！", netScore, peaceTruceTurns)
                                    case .counterOffer(let netScore, let counter):
                                        activeCounterOffer = counter
                                        localFeedback = String(format: "📜 对方提出反报价（原方案净分 %.1f）：可审阅下方反报价条款决定是否签约", netScore)
                                    case .rejectedBreakdown(_, let reason):
                                        activeCounterOffer = nil
                                        localFeedback = "❌ 谈判破裂：\(reason)"
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                if let counter = activeCounterOffer, counter.target == selectedDiploFaction {
                                    let cededNames = counter.cededNodeIds.compactMap { CampaignMapConfig.node(byId: $0)?.name }.joined(separator: "、")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("对方反报价单：赔金 \(counter.goldIndemnity) · 岁粮 \(counter.grainTributePerTurn)/回合 × \(counter.truceTurns) 回合\(cededNames.isEmpty ? "" : " · 割让[\(cededNames)]")")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.orange)
                                        Button("接受反报价并立即停战") {
                                            let res = router.campaignEngine.acceptPeaceCounterOffer(counter)
                                            activeCounterOffer = nil
                                            localFeedback = res.message
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.orange)
                                        .controlSize(.small)
                                    }
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.14)))
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
        }
    }

    private func pCfgCapital(_ fid: FactionId) -> String {
        FactionConfig.config(for: fid)?.capitalNodeId ?? ""
    }

    // MARK: - 右栏页签 4：回合结算详报与环形历史编年史

    private var warChroniclePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let rep = router.latestTurnReport {
                    GroupBox("第 \(rep.resolvedTurnNumber) 回合战略结算详报") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 税赋与商路：城池金 +\(rep.playerGoldEarned)，通商金 +\(rep.playerTradeGoldEarned)，林木 +\(rep.playerWoodEarned)，净粮 \(rep.playerGrainNetChange >= 0 ? "+\(rep.playerGrainNetChange)" : "\(rep.playerGrainNetChange)")")
                                .font(.caption.monospacedDigit())
                            if !rep.warningSeveredNodeIds.isEmpty {
                                let names = rep.warningSeveredNodeIds.compactMap { CampaignMapConfig.node(byId: $0)?.name }.joined(separator: "、")
                                Text("⚠️ 粮道断绝干粮预警：\(names)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }
                            if !rep.starvationAttritionByNode.isEmpty {
                                ForEach(rep.starvationAttritionByNode.keys.sorted(), id: \.self) { nid in
                                    let lost = rep.starvationAttritionByNode[nid] ?? 0
                                    let cname = CampaignMapConfig.node(byId: nid)?.name ?? nid
                                    Text("🚨 【\(cname)】饥疲逃亡减员 -\(lost) 人（8%）")
                                        .font(.caption.bold())
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }

                Text("天下大势编年日志（累计胜 \(world.totalBattlesWon)/\(world.totalBattlesFought) 场 · 歼敌 \(world.totalEnemiesDefeated)）")
                    .font(.subheadline.bold())

                ForEach(world.eventLogs.reversed()) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("[第 \(log.turnNumber) 回合 · \(log.category)]")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        Text(log.summary)
                            .font(.caption)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.09)))
                }
            }
        }
    }
}
