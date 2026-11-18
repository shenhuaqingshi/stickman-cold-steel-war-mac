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
    case nodeAndMarch = "城关出征"
    case armyAndTech = "国策科技"
    case diplomacy = "外交纵横"
    case warChronicle = "天下战报"

    var id: String { rawValue }
}

/// 核心路由 2：战役战略大地图与外交纵横页（帝国锋刃版 · 山川河岳手绘风沙盘 · 40座城关 · 78条官道 · 赋税国策与王庭诏令）
public struct CampaignMapView: View {
    @Bindable var router: AppRouter

    @State private var mapZoom: Double = 0.62
    @State private var zoomGestureBase: Double? = nil
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

    // 背盟强阻断二次确认弹窗状态
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

            Rectangle()
                .fill(ImperialPalette.bronzeBorder.opacity(0.45))
                .frame(height: 1)

            HSplitView {
                // 左侧主视口：3600×2400 帝国地形沙盘 + 右上角交互雷达缩略图 + 左下角战报快讯
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
                                        let base = zoomGestureBase ?? mapZoom
                                        if zoomGestureBase == nil {
                                            zoomGestureBase = mapZoom
                                        }
                                        let next = base * value.magnification
                                        mapZoom = max(GameConstants.campaignZoomMin, min(GameConstants.campaignZoomMax, next))
                                    }
                                    .onEnded { _ in
                                        zoomGestureBase = nil
                                    }
                            )

                        VStack(alignment: .trailing, spacing: 8) {
                            minimapOverlay(viewportSize: geo.size)

                            // 图例小条
                            HStack(spacing: 8) {
                                Label("补给畅通", systemImage: "line.diagonal")
                                    .foregroundStyle(ImperialPalette.jadeSupply)
                                Label("交战前线", systemImage: "flame.fill")
                                    .foregroundStyle(ImperialPalette.legionCrimsonBright)
                                Label("主力驻地", systemImage: "star.fill")
                                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(ImperialPalette.obsidianDeep.opacity(0.88))
                                    .overlay(Capsule().strokeBorder(ImperialPalette.bronzeBorder.opacity(0.5), lineWidth: 1))
                            )
                        }
                        .padding(14)

                        if !localFeedback.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "scroll.fill")
                                            .foregroundStyle(ImperialPalette.imperialGold)
                                        Text(localFeedback)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(ImperialPalette.parchmentText)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(ImperialPalette.obsidianCard.opacity(0.93))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(ImperialPalette.imperialGold.opacity(0.55), lineWidth: 1)
                                            )
                                    )
                                    Spacer()
                                }
                                .padding(14)
                            }
                        }
                    }
                }
                .frame(minWidth: 660, maxWidth: .infinity, maxHeight: .infinity)

                // 右侧四合一帝国军政枢密台
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(CampaignRightTab.allCases) { tab in
                            Button(tab.rawValue) {
                                BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.65)
                                rightTab = tab
                            }
                            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: rightTab == tab, isCompact: true))
                        }
                    }

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
                .background(ImperialPalette.obsidianDeep)
                .frame(minWidth: 385, idealWidth: 425, maxWidth: 475, maxHeight: .infinity)
            }
        }
        .background(ImperialPalette.obsidianDeep)
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
            Button("‹ 主帅大帐") {
                BattleAudioEngine.shared.play(.uiClick)
                router.returnToMainMenu()
            }
            .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

            if let pCfg {
                FactionCrestBadge(faction: pCfg, size: 32)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("\(pCfg?.name ?? "") · 第 \(world.turnNumber) 回合")
                        .font(.headline.bold())
                        .foregroundStyle(ImperialPalette.parchmentText)
                    Text("疆域 \(ownedCount)/\(GameConstants.campaignNodeCount)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(ImperialPalette.imperialGoldBright)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ImperialPalette.obsidianElevated))
                }
                Text("主力驻地：【\(mainNodeName)】 · 行军力 \(String(format: "%.1f", playerState.mainArmyActionPoints)) · 国策：\(router.campaignEngine.currentPlayerTaxPolicy.displayName)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(ImperialPalette.parchmentMuted)
            }

            Divider().frame(height: 22)

            HStack(spacing: 10) {
                resourceBadge(icon: "dollarsign.circle.fill", label: "黄金", value: "\(playerState.gold)", tint: ImperialPalette.imperialGoldBright)
                resourceBadge(icon: "tree.fill", label: "良木", value: "\(playerState.wood)", tint: Color(red: 0.45, green: 0.80, blue: 0.42))
                resourceBadge(icon: "leaf.circle.fill", label: "军粮", value: "\(playerState.grain)", tint: Color.orange)
                resourceBadge(
                    icon: "seal.fill",
                    label: "信誉",
                    value: "\(playerState.credibility)",
                    tint: playerState.credibility < 40 ? ImperialPalette.legionCrimsonBright : Color.cyan
                )
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(ImperialPalette.parchmentMuted)
                Slider(value: $mapZoom, in: GameConstants.campaignZoomMin...GameConstants.campaignZoomMax)
                    .frame(width: 88)
                Button("居中帅旗") {
                    BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.6)
                    centerCameraOnNode(playerState.mainArmyNodeId)
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
            }

            Button("存军档 (⌘S)") {
                BattleAudioEngine.shared.play(.uiClick)
                router.saveCurrentCampaignSnapshot(toSlot: 1)
                localFeedback = router.bannerMessage
            }
            .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

            Button("推进下一回合 ›") {
                if world.pendingDefensivePrompt != nil {
                    localFeedback = "⚠️ 敌军正围攻我方城池！请先点击顶部红条【立即披甲登城迎战】击退敌军后再推进下一回合。"
                    return
                }
                BattleAudioEngine.shared.play(.drumMarch)
                let report = router.campaignEngine.advanceTurn()
                router.latestTurnReport = report
                router.autoSaveCampaignSilently()
                let headlineText = report.aiWorldHeadlines.first.map { " · 天下：\($0)" } ?? ""
                localFeedback = "已进入第 \(report.newTurnNumber) 回合：税金 +\(report.playerGoldEarned + report.playerTradeGoldEarned)、木 +\(report.playerWoodEarned)、净粮 \(report.playerGrainNetChange >= 0 ? "+\(report.playerGrainNetChange)" : "\(report.playerGrainNetChange)")\(headlineText)"
                if !report.warningSeveredNodeIds.isEmpty || !report.starvationAttritionByNode.isEmpty {
                    rightTab = .warChronicle
                }
            }
            .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
            .disabled(world.pendingDefensivePrompt != nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(ImperialPalette.obsidianCard)
    }

    private func resourceBadge(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text("\(label) \(value)")
                .foregroundStyle(ImperialPalette.parchmentText)
        }
        .font(.caption.monospacedDigit().bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ImperialPalette.obsidianElevated)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint.opacity(0.32), lineWidth: 1))
        )
    }

    private func centerCameraOnNode(_ nodeId: String) {
        selectedNodeId = nodeId
        guard let node = CampaignMapConfig.node(byId: nodeId) else {
            panOffset = .zero
            dragBaseOffset = .zero
            return
        }
        let dx = (GameConstants.campaignMapWidth * 0.5 - node.x) * mapZoom
        let dy = (GameConstants.campaignMapHeight * 0.5 - node.y) * mapZoom
        withAnimation(.easeOut(duration: 0.22)) {
            panOffset = CGSize(width: dx, height: dy)
            dragBaseOffset = panOffset
        }
    }

    private func urgentDefensiveBanner(_ ctx: RouteLaunchContext) -> some View {
        let eName = FactionConfig.config(for: ctx.enemyFaction)?.name ?? ctx.enemyFaction.rawValue
        let cityName = ctx.targetNodeId.flatMap { CampaignMapConfig.node(byId: $0)?.name } ?? "边境要塞"
        return HStack {
            Image(systemName: "flame.circle.fill")
                .font(.title3)
                .foregroundStyle(ImperialPalette.imperialGoldBright)
            Text("烽火急报：【\(eName)】大军猛攻我方【\(cityName)】（\(ctx.scenarioType.displayName)）！")
                .font(.callout.bold())
                .foregroundStyle(.white)
            Spacer()
            Button("立即披甲登城迎战 ›") {
                BattleAudioEngine.shared.play(.warHorn)
                router.enterCampaignPreBattle(context: ctx, modifiers: nil)
            }
            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ImperialPalette.crimsonWarGradient)
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
                .foregroundStyle(ImperialPalette.imperialGoldBright)
            Spacer()
            Button("开启新战役") {
                BattleAudioEngine.shared.play(.warHorn)
                router.startMode(.campaign, playerFaction: playerFaction, forceNewCampaign: true)
            }
            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ImperialPalette.obsidianElevated)
    }

    // MARK: - 3600×2400 帝国山川疆域沙盘画布与实时 BFS 粮道高亮

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
            // 羊皮古卷玄铁暗底渐变
            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.14, blue: 0.11),
                    Color(red: 0.09, green: 0.08, blue: 0.07)
                ],
                center: .center,
                startRadius: 60,
                endRadius: max(viewportSize.width, viewportSize.height) * 0.78
            )

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

            // 疆域势力范围柔光 + 山川森林河流地貌 + 78 条帝国石砌官道 + BFS 粮道
            Canvas { context, _ in
                // 0. 经纬古海图网格线
                let step = 300.0 * mapZoom
                if step >= 45 {
                    var gridPath = Path()
                    var gx = 0.0
                    while gx <= mapW {
                        let sx = originX + gx * mapZoom
                        gridPath.move(to: CGPoint(x: sx, y: originY))
                        gridPath.addLine(to: CGPoint(x: sx, y: originY + mapH * mapZoom))
                        gx += 300.0
                    }
                    var gy = 0.0
                    while gy <= mapH {
                        let sy = originY + gy * mapZoom
                        gridPath.move(to: CGPoint(x: originX, y: sy))
                        gridPath.addLine(to: CGPoint(x: originX + mapW * mapZoom, y: sy))
                        gy += 300.0
                    }
                    context.stroke(gridPath, with: .color(ImperialPalette.bronzeBorder.opacity(0.10)), lineWidth: 0.8)
                }

                // 1. 40 城关疆域归属光晕（直观呈现八国版图扩张）
                let auraRadius = CGFloat(210.0 * mapZoom)
                for node in CampaignMapConfig.allNodes {
                    let liveOwner = world.nodesById[node.id]?.owner ?? node.initialOwner
                    let hex = FactionConfig.config(for: liveOwner)?.primaryColorHex ?? "#78909C"
                    let c = CGPoint(x: originX + node.x * mapZoom, y: originY + node.y * mapZoom)
                    let r = node.nodeType == .capitalCitadel ? auraRadius * 1.25 : auraRadius
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [Color(hex: hex).opacity(0.20), Color(hex: hex).opacity(0.0)]),
                            center: c,
                            startRadius: 4,
                            endRadius: r
                        )
                    )
                }

                // 2. 地貌手绘装饰：雪岭山脉、蜿蜒大河、迷雾松林、大漠沙丘
                for node in CampaignMapConfig.allNodes {
                    let cx = originX + node.x * mapZoom
                    let cy = originY + node.y * mapZoom
                    let s = CGFloat(mapZoom)
                    switch node.terrain {
                    case .highGround, .snowfield:
                        for k in -1...1 {
                            let ox = cx + CGFloat(k * 36) * s
                            let oy = cy - CGFloat(26 + abs(k) * 6) * s
                            var mtn = Path()
                            mtn.move(to: CGPoint(x: ox - 22 * s, y: oy + 16 * s))
                            mtn.addLine(to: CGPoint(x: ox, y: oy - 16 * s))
                            mtn.addLine(to: CGPoint(x: ox + 22 * s, y: oy + 16 * s))
                            mtn.closeSubpath()
                            let mtnColor = node.terrain == .snowfield
                                ? Color(red: 0.72, green: 0.80, blue: 0.88).opacity(0.22)
                                : Color(red: 0.52, green: 0.46, blue: 0.38).opacity(0.24)
                            context.fill(mtn, with: .color(mtnColor))
                        }
                    case .riverFord, .bridgePass:
                        var river = Path()
                        river.move(to: CGPoint(x: cx - 58 * s, y: cy - 28 * s))
                        river.addQuadCurve(
                            to: CGPoint(x: cx + 58 * s, y: cy + 28 * s),
                            control: CGPoint(x: cx + 18 * s, y: cy - 16 * s)
                        )
                        context.stroke(
                            river,
                            with: .color(Color(red: 0.20, green: 0.52, blue: 0.76).opacity(0.36)),
                            style: StrokeStyle(lineWidth: max(2.0, 8.0 * s), lineCap: .round)
                        )
                    case .denseForest:
                        for (dx, dy) in [(-32.0, -20.0), (30.0, -18.0), (-26.0, 22.0), (28.0, 20.0)] {
                            let r = 11.0 * s
                            let treeRect = CGRect(x: cx + dx * s - r, y: cy + dy * s - r, width: r * 2, height: r * 2)
                            context.fill(Path(ellipseIn: treeRect), with: .color(Color(red: 0.16, green: 0.44, blue: 0.22).opacity(0.30)))
                        }
                    case .desertDune:
                        var dune = Path()
                        dune.move(to: CGPoint(x: cx - 44 * s, y: cy + 26 * s))
                        dune.addQuadCurve(to: CGPoint(x: cx + 44 * s, y: cy + 26 * s), control: CGPoint(x: cx, y: cy + 10 * s))
                        context.stroke(dune, with: .color(Color(red: 0.84, green: 0.68, blue: 0.34).opacity(0.26)), lineWidth: max(1.5, 3.0 * s))
                    default:
                        break
                    }
                }

                // 3. 78 条无向官道与 BFS 最短补给粮道高亮线
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
                        context.stroke(path, with: .color(ImperialPalette.jadeSupply.opacity(0.35)), style: StrokeStyle(lineWidth: 8.0, lineCap: .round))
                        context.stroke(path, with: .color(ImperialPalette.jadeSupply), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                    } else if isWarBorder {
                        context.stroke(path, with: .color(ImperialPalette.legionCrimsonBright.opacity(0.78)), style: StrokeStyle(lineWidth: 2.5, dash: [7, 4]))
                    } else if isBorderRoad {
                        context.stroke(path, with: .color(ImperialPalette.bronzeBorder.opacity(0.50)), style: StrokeStyle(lineWidth: 1.8, dash: [6, 4]))
                    } else {
                        context.stroke(path, with: .color(Color.black.opacity(0.45)), style: StrokeStyle(lineWidth: 3.6))
                        context.stroke(path, with: .color(ImperialPalette.parchmentText.opacity(0.32)), style: StrokeStyle(lineWidth: 2.0))
                    }
                }
            }

            // 40 座帝国城塞动态节点按钮
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
                let isCap = (node.nodeType == .capitalCitadel)
                let outerSize: CGFloat = isCap ? 34 : 24

                Button {
                    BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.65)
                    selectedNodeId = node.id
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            if isSelected || isPlayerMainArmy {
                                Circle()
                                    .stroke(
                                        isSelected ? ImperialPalette.imperialGoldBright : ImperialPalette.jadeSupply,
                                        lineWidth: 2.2
                                    )
                                    .frame(width: outerSize + 8, height: outerSize + 8)
                            }

                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [factionColor, factionColor.opacity(0.62), ImperialPalette.obsidianDeep],
                                        center: .center,
                                        startRadius: 2,
                                        endRadius: outerSize * 0.56
                                    )
                                )
                                .frame(width: outerSize, height: outerSize)
                                .shadow(color: .black.opacity(0.65), radius: 3, x: 0, y: 2)

                            Circle()
                                .strokeBorder(
                                    isCap ? ImperialPalette.imperialGoldBright : Color.white.opacity(0.75),
                                    lineWidth: isCap ? 2.2 : 1.3
                                )
                                .frame(width: outerSize, height: outerSize)

                            Image(systemName: symbolForNodeType(node.nodeType))
                                .font(.system(size: isCap ? 14 : 10, weight: .bold))
                                .foregroundStyle(isCap ? ImperialPalette.imperialGoldBright : .white)
                        }

                        if mapZoom >= 0.48 || isCap || isSelected || isPlayerMainArmy {
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
                                .font(.system(size: isCap ? 11.5 : 10.5, weight: (isSelected || isPlayerMainArmy || isCap) ? .bold : .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(ImperialPalette.obsidianDeep.opacity(0.86))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(
                                                    isSelected ? ImperialPalette.imperialGold : ImperialPalette.bronzeBorder.opacity(0.45),
                                                    lineWidth: isSelected ? 1.2 : 0.7
                                                )
                                        )
                                )
                                .foregroundStyle(
                                    isSevered
                                        ? ImperialPalette.legionCrimsonBright
                                        : (isSelected ? ImperialPalette.imperialGoldBright : ImperialPalette.parchmentText)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
                .position(x: posX, y: posY)
            }
        }
        .clipped()
    }

    private func symbolForNodeType(_ nodeType: CampaignNodeType) -> String {
        switch nodeType {
        case .capitalCitadel: return "crown.fill"
        case .fortressPass: return "shield.checkered"
        case .granaryTown: return "leaf.fill"
        case .resourceHub: return "hammer.fill"
        case .crossingOutpost: return "ferry.fill"
        }
    }

    private func minimapOverlay(viewportSize: CGSize) -> some View {
        let miniW: CGFloat = 216
        let miniH: CGFloat = 144
        let scaleX = miniW / GameConstants.campaignMapWidth
        let scaleY = miniH / GameConstants.campaignMapHeight

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(ImperialPalette.obsidianCard.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ImperialPalette.imperialGold.opacity(0.65), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 3)

            Canvas { context, _ in
                for edge in CampaignMapConfig.allRoadEdges {
                    guard let a = CampaignMapConfig.node(byId: edge.fromNodeId),
                          let b = CampaignMapConfig.node(byId: edge.toNodeId) else { continue }
                    var p = Path()
                    p.move(to: CGPoint(x: a.x * scaleX, y: a.y * scaleY))
                    p.addLine(to: CGPoint(x: b.x * scaleX, y: b.y * scaleY))
                    context.stroke(p, with: .color(Color.white.opacity(0.14)), lineWidth: 0.7)
                }

                for node in CampaignMapConfig.allNodes {
                    let liveOwner = world.nodesById[node.id]?.owner ?? node.initialOwner
                    let hex = FactionConfig.config(for: liveOwner)?.primaryColorHex ?? "#FFFFFF"
                    let pt = CGPoint(x: node.x * scaleX, y: node.y * scaleY)
                    let r: CGFloat = node.nodeType == .capitalCitadel ? 4.2 : 2.7
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(hex: hex)))
                    if node.id == playerState.mainArmyNodeId {
                        let ring = CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)
                        context.stroke(Path(ellipseIn: ring), with: .color(ImperialPalette.imperialGoldBright), lineWidth: 1.4)
                    }
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
                context.stroke(Path(box), with: .color(ImperialPalette.imperialGoldBright), lineWidth: 1.3)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let lx = max(0, min(GameConstants.campaignMapWidth, value.location.x / scaleX))
                        let ly = max(0, min(GameConstants.campaignMapHeight, value.location.y / scaleY))
                        let dx = (GameConstants.campaignMapWidth * 0.5 - lx) * mapZoom
                        let dy = (GameConstants.campaignMapHeight * 0.5 - ly) * mapZoom
                        panOffset = CGSize(width: dx, height: dy)
                        dragBaseOffset = panOffset
                    }
            )
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
                ImperialPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: symbolForNodeType(selectedNodeConfig.nodeType))
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                            Text(selectedNodeConfig.name)
                                .font(.title3.bold())
                                .foregroundStyle(ImperialPalette.parchmentText)
                            Spacer()
                            Text(selectedNodeConfig.nodeType.displayName)
                                .font(.caption.bold())
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(ImperialPalette.obsidianElevated))
                        }
                        Text("第 \(selectedNodeConfig.regionIndex) 州 · \(selectedNodeConfig.regionName) · 归属：【\(ownerCfg?.name ?? "")】")
                            .font(.caption)
                            .foregroundStyle(ImperialPalette.parchmentMuted)
                        Text("地形：\(selectedNodeConfig.terrain.displayName) · 城垣耐久：\(selectedNodeState?.wallIntegrity ?? 0)/\(selectedNodeState?.maxWallIntegrity ?? 1000)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(ImperialPalette.parchmentText)
                        Text("守备驻军：\(selectedNodeState?.totalGarrisonTroops ?? 0) 队 · 士气修正：\(Int(selectedNodeState?.garrisonMoraleModifier ?? 0))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ImperialPalette.parchmentMuted)
                        Text("每回合税赋：金 \(selectedNodeConfig.goldYield) / 木 \(selectedNodeConfig.woodYield) / 粮 \(selectedNodeConfig.grainYield)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ImperialPalette.imperialGold)
                        Divider()
                        Text(supplyText)
                            .font(.caption.bold())
                            .foregroundStyle(selectedSupplyDetail.shortestPathNodeIds.isEmpty ? ImperialPalette.legionCrimsonBright : ImperialPalette.jadeSupply)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 主力军团行军 / 跨境进攻操作卡
                ImperialPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("统帅主力军令（现驻：\(CampaignMapConfig.node(byId: playerState.mainArmyNodeId)?.name ?? "")）")
                            .font(.subheadline.bold())
                            .foregroundStyle(ImperialPalette.imperialGold)

                        if selectedNodeId == playerState.mainArmyNodeId {
                            Text("★ 我方主力野战军团正驻扎于此城（兵力 \(playerState.totalMainArmyTroops) · 剩余行军力 \(String(format: "%.1f", playerState.mainArmyActionPoints))）")
                                .font(.caption)
                                .foregroundStyle(ImperialPalette.jadeSupply)
                        } else if isFriendlyOrAllied {
                            Button {
                                performMarch(toNodeId: selectedNodeId, confirmBetrayal: false)
                            } label: {
                                Text("调遣主力和平移防至【\(selectedNodeConfig.name)】")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true))
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
                                HStack {
                                    Image(systemName: "flag.2.crossed.fill")
                                    Text("挥师进攻【\(selectedNodeConfig.name)】（战前整军 ›）")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ImperialCrimsonButtonStyle())

                            Text("提示：跨境进攻须先将主力移防至与目标城池直接相邻的前线城关。")
                                .font(.caption2)
                                .foregroundStyle(ImperialPalette.parchmentMuted)
                        }

                        // 围点打援预设伏兵入口
                        let adjacentEnemyWarCities = selectedNodeConfig.neighbors.filter { nbId in
                            guard let nbOwner = world.nodesById[nbId]?.owner, nbOwner != playerFaction else { return false }
                            return world.diplomacy.status(between: playerFaction, and: nbOwner) == .war
                        }
                        if !adjacentEnemyWarCities.isEmpty {
                            Divider()
                            Text("奇谋【围点打援】：在此咽喉设伏截击驰援敌军（大捷令孤城守军 -25 士气）")
                                .font(.caption2.bold())
                                .foregroundStyle(ImperialPalette.parchmentText)
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
                                    BattleAudioEngine.shared.play(.drumMarch, volumeScale: 0.7)
                                    let chosen = adjacentEnemyWarCities.contains(ambushBesiegeTargetId) ? ambushBesiegeTargetId : adjacentEnemyWarCities[0]
                                    let res = router.campaignEngine.setupReliefAmbush(
                                        factionId: playerFaction,
                                        ambushNodeId: selectedNodeId,
                                        besiegedTargetNodeId: chosen
                                    )
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                            }
                        }
                    }
                }

                // 连通邻接官道列表
                Text("官道直通邻城（共 \(selectedNodeConfig.neighbors.count) 条）")
                    .font(.subheadline.bold())
                    .foregroundStyle(ImperialPalette.imperialGold)

                ForEach(selectedNodeConfig.neighbors, id: \.self) { nbId in
                    if let nbCfg = CampaignMapConfig.node(byId: nbId) {
                        let nbOwner = world.nodesById[nbId]?.owner ?? nbCfg.initialOwner
                        let nbFaction = FactionConfig.config(for: nbOwner)
                        Button {
                            BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.55)
                            selectedNodeId = nbId
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: nbFaction?.primaryColorHex ?? "#FFFFFF"))
                                    .frame(width: 9, height: 9)
                                Text(nbCfg.name)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(ImperialPalette.parchmentText)
                                if playerState.mainArmyNodeId == nbId {
                                    Text("[主力驻地]")
                                        .font(.caption2.bold())
                                        .foregroundStyle(ImperialPalette.jadeSupply)
                                }
                                Spacer()
                                Text("\(nbFaction?.name ?? "") · 守军 \(world.nodesById[nbId]?.totalGarrisonTroops ?? 0)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(ImperialPalette.parchmentMuted)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(ImperialPalette.obsidianElevated)
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.35), lineWidth: 0.8))
                            )
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
            BattleAudioEngine.shared.play(.drumMarch, volumeScale: 0.75)
            let name = CampaignMapConfig.node(byId: destId)?.name ?? destId
            localFeedback = "主力军团已顺利移防进驻【\(name)】（剩余行军力 \(String(format: "%.1f", playerState.mainArmyActionPoints))）"
        case .requiresWarConfirmation(let assessment, let targetFac):
            pendingBetrayalAssessment = assessment
            pendingBetrayalTargetFaction = targetFac
            pendingBetrayalMarchNodeId = targetId
            showBetrayalAlert = true
        case .battleTriggered(let ctx, let mods):
            BattleAudioEngine.shared.play(.warHorn)
            router.enterCampaignPreBattle(context: ctx, modifiers: mods)
        }
    }

    private func confirmAndExecuteBetrayal() {
        BattleAudioEngine.shared.play(.warHorn)
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

    // MARK: - 右栏页签 2：帝国赋税国策、王庭悬赏诏令、专属科技与征募

    private var armyAndTechPanel: some View {
        let pCfg = FactionConfig.config(for: playerFaction)
        let legalUnits = UnitConfig.recruitableUnits(for: playerFaction)
        let currentPolicy = router.campaignEngine.currentPlayerTaxPolicy
        let claimedStages = Set(world.mandateClaimedStages ?? [])
        let ownedCount = router.campaignEngine.controlledNodes(of: playerFaction).count
        let tradeCount = FactionId.allCases.filter {
            $0 != playerFaction && world.diplomacy.hasTradeAgreement(between: playerFaction, and: $0)
        }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // 1. 帝国行省赋税国策（罗马全战式税率民生调控）
                ImperialPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                            Text("帝国行省赋税国策")
                                .font(.subheadline.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                            Spacer()
                            Text(currentPolicy.displayName)
                                .font(.caption.bold())
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                        }

                        HStack(spacing: 6) {
                            ForEach(CampaignTaxPolicy.allCases) { policy in
                                Button(policy.displayName) {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    router.campaignEngine.setPlayerTaxPolicy(policy)
                                    localFeedback = "已颁布行省赋税国策：【\(policy.displayName)】（\(policy.effectBrief)）"
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: currentPolicy == policy, isCompact: true))
                            }
                        }

                        Text("当前国策效应：\(currentPolicy.effectBrief)")
                            .font(.caption2)
                            .foregroundStyle(ImperialPalette.parchmentMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 2. 王庭/元老院悬赏诏令（三阶段战略里程碑重赏）
                ImperialPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "seal.fill")
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                            Text("元老院 · 王命拓土悬赏诏令")
                                .font(.subheadline.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                        }

                        mandateStageRow(
                            stage: 1,
                            title: "初展宏图 · 掌控七城",
                            progressText: "进度 \(min(ownedCount, 7))/7 座城池 · 赐 金350 木180",
                            isReady: ownedCount >= 7,
                            isClaimed: claimedStages.contains(1)
                        )
                        mandateStageRow(
                            stage: 2,
                            title: "威震四方 · 武功通商",
                            progressText: "胜战 \(world.totalBattlesWon)/3 或 商约 \(tradeCount)/2 · 赐 金450 粮360",
                            isReady: world.totalBattlesWon >= 3 || tradeCount >= 2,
                            isClaimed: claimedStages.contains(2)
                        )
                        mandateStageRow(
                            stage: 3,
                            title: "雄踞九州 · 十二连城",
                            progressText: "进度 \(min(ownedCount, 12))/12 座城池 · 赐 金700 木350 粮500",
                            isReady: ownedCount >= 12,
                            isClaimed: claimedStages.contains(3)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 3. 主帅统御与主力编制
                ImperialPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("主帅 Lv.\(playerState.commanderLevel)（EXP \(playerState.commanderExp)/\(playerState.commanderLevel * 500)）")
                                .font(.callout.bold())
                                .foregroundStyle(ImperialPalette.parchmentText)
                            Spacer()
                            Text("编制 \(playerState.usedMainArmyPop)/\(GameConstants.defaultArmyPopCap)")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                        }
                        if playerState.commanderWoundedTurns > 0 {
                            Text("⚠️ 主帅重伤休养剩余 \(playerState.commanderWoundedTurns) 回合")
                                .font(.caption.bold())
                                .foregroundStyle(ImperialPalette.legionCrimsonBright)
                        }
                        let rosterDesc = playerState.mainArmyRoster.map { stack in
                            "\(UnitConfig.stats(for: stack.unitId)?.name ?? "")×\(stack.count)"
                        }.joined(separator: " · ")
                        Text(rosterDesc.isEmpty ? "暂无兵力" : rosterDesc)
                            .font(.caption)
                            .foregroundStyle(ImperialPalette.parchmentMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 4. 三阶专属军制科技
                ImperialPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("三阶专属军制科技")
                            .font(.subheadline.bold())
                            .foregroundStyle(ImperialPalette.imperialGold)

                        ForEach(pCfg?.uniqueTechs ?? []) { tech in
                            let unlocked = playerState.unlockedTechIds.contains(tech.id)
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("《\(tech.name)》")
                                        .font(.callout.bold())
                                        .foregroundStyle(ImperialPalette.parchmentText)
                                    Text(tech.effectSummary)
                                        .font(.caption2)
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
                                    Text("耗资：金\(tech.cost.gold) / 木\(tech.cost.wood) / 粮\(tech.cost.grain)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(ImperialPalette.imperialGold)
                                }
                                Spacer()
                                if unlocked {
                                    Text("已解锁")
                                        .font(.caption.bold())
                                        .foregroundStyle(ImperialPalette.jadeSupply)
                                } else {
                                    Button("研发") {
                                        let res = router.campaignEngine.researchTechnology(factionId: playerFaction, techId: tech.id)
                                        if res.succeeded {
                                            BattleAudioEngine.shared.play(.forgeClang)
                                        }
                                        localFeedback = res.message
                                    }
                                    .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
                                }
                            }
                            Divider()
                        }
                    }
                }

                // 5. 征募兵员
                ImperialPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("征募常备军团（每次 +4 人）")
                            .font(.subheadline.bold())
                            .foregroundStyle(ImperialPalette.imperialGold)

                        Toggle("直接编入统帅主力军团（取消则充实选中城关守军）", isOn: $recruitIntoMainArmy)
                            .font(.caption)
                            .foregroundStyle(ImperialPalette.parchmentText)
                        if playerFaction == .shamo {
                            Toggle("沙漠商盟特权：耗纯金币即时征召雇佣军", isOn: $useShamoMercenaryGold)
                                .font(.caption)
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                        }

                        ForEach(legalUnits) { unit in
                            let batchCost = router.campaignEngine.effectiveRecruitmentCost(
                                for: unit.id,
                                factionId: playerFaction,
                                count: 4,
                                useInstantMercenaryGold: playerFaction == .shamo && useShamoMercenaryGold
                            )
                            HStack(spacing: 8) {
                                Image(systemName: UnitVisualSymbol.sfSymbol(for: unit.id))
                                    .font(.caption.bold())
                                    .foregroundStyle(ImperialPalette.imperialGold)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unit.name)
                                        .font(.callout.bold())
                                        .foregroundStyle(ImperialPalette.parchmentText)
                                    if let c = batchCost {
                                        Text("4人耗资：金\(c.gold) / 木\(c.wood) / 粮\(c.grain) · 人口\(unit.popCap * 4)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(ImperialPalette.parchmentMuted)
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
                                    if res.succeeded {
                                        BattleAudioEngine.shared.play(.drumMarch, volumeScale: 0.65)
                                    }
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                            }
                        }
                    }
                }
            }
        }
    }

    private func mandateStageRow(
        stage: Int,
        title: String,
        progressText: String,
        isReady: Bool,
        isClaimed: Bool
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(ImperialPalette.parchmentText)
                Text(progressText)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(ImperialPalette.parchmentMuted)
            }
            Spacer()
            if isClaimed {
                Text("已领赏")
                    .font(.caption2.bold())
                    .foregroundStyle(ImperialPalette.jadeSupply)
            } else {
                Button(isReady ? "领受赏赐" : "未达成") {
                    let res = router.campaignEngine.claimImperialMandateReward(stage: stage)
                    if res.succeeded {
                        BattleAudioEngine.shared.play(.ageFanfare)
                    }
                    localFeedback = res.message
                }
                .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: isReady, isCompact: true))
                .disabled(!isReady)
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 6).fill(ImperialPalette.obsidianElevated.opacity(0.85)))
    }

    // MARK: - 右栏页签 3：8 势力实时关系矩阵、结盟/宣战/调停与三档量化媾和谈判

    private var diplomacyFullPanel: some View {
        let otherFactions = FactionConfig.allFactions.filter { $0.id != playerFaction }
        let targetCfg = FactionConfig.config(for: selectedDiploFaction)
        let targetState = router.campaignEngine.factionState(for: selectedDiploFaction)
        let bilateral = world.diplomacy.bilateralState(between: playerFaction, and: selectedDiploFaction)
        let playerBorderNodes = router.campaignEngine.controlledNodes(of: playerFaction).map(\.id)

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
                    .foregroundStyle(ImperialPalette.imperialGold)

                ForEach(otherFactions) { other in
                    let bi = world.diplomacy.bilateralState(between: playerFaction, and: other.id)
                    let fSt = router.campaignEngine.factionState(for: other.id)
                    let cityCnt = router.campaignEngine.controlledNodes(of: other.id).count
                    let isChosen = (other.id == selectedDiploFaction)

                    Button {
                        BattleAudioEngine.shared.play(.uiClick, volumeScale: 0.55)
                        selectedDiploFaction = other.id
                        activeCounterOffer = nil
                        peaceCededNodeIds.removeAll()
                    } label: {
                        HStack(spacing: 10) {
                            FactionCrestBadge(faction: other, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(other.name)
                                        .font(.callout.bold())
                                        .foregroundStyle(ImperialPalette.parchmentText)
                                    if fSt.isEliminated {
                                        Text("[已覆灭]")
                                            .font(.caption2)
                                            .foregroundStyle(ImperialPalette.legionCrimsonBright)
                                    } else {
                                        Text("\(cityCnt)城 · 信誉\(fSt.credibility)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(ImperialPalette.parchmentMuted)
                                    }
                                }
                                let turnTag = bi.remainingTurns > 0 ? "(\(bi.remainingTurns)回合)" : ""
                                let vendettaTag = bi.vendettaLockTurns > 0 ? " · 血海世仇(\(bi.vendettaLockTurns))" : ""
                                Text("条约：\(bi.status.displayName)\(turnTag)\(vendettaTag)")
                                    .font(.caption2)
                                    .foregroundStyle(bi.status == .war ? ImperialPalette.legionCrimsonBright : (bi.status == .alliance ? ImperialPalette.jadeSupply : ImperialPalette.parchmentMuted))
                            }
                            Spacer()
                            Text(bi.relation > 0 ? "+\(bi.relation)" : "\(bi.relation)")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(bi.relation >= 25 ? ImperialPalette.jadeSupply : (bi.relation < 0 ? ImperialPalette.legionCrimsonBright : ImperialPalette.parchmentText))
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isChosen ? Color(hex: other.primaryColorHex).opacity(0.22) : ImperialPalette.obsidianElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(isChosen ? ImperialPalette.imperialGoldBright : ImperialPalette.bronzeBorder.opacity(0.35), lineWidth: isChosen ? 1.4 : 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let (allyA, allyB) = warringAllyPair {
                    let nameA = FactionConfig.config(for: allyA)?.name ?? ""
                    let nameB = FactionConfig.config(for: allyB)?.name ?? ""
                    ImperialPanel(padding: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("双重同盟冲突调停（零信誉损失豁免）")
                                .font(.caption.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                            Text("我方两大盟友【\(nameA)】与【\(nameB)】爆发武装冲突！")
                                .font(.caption)
                                .foregroundStyle(ImperialPalette.parchmentText)
                            Button("居中斡旋促成 3 回合停火") {
                                BattleAudioEngine.shared.play(.ageFanfare, volumeScale: 0.7)
                                let res = router.campaignEngine.mediateAlliedConflict(
                                    mediator: playerFaction,
                                    belligerentA: allyA,
                                    belligerentB: allyB
                                )
                                localFeedback = res.message
                            }
                            .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
                        }
                    }
                }

                if !targetState.isEliminated {
                    ImperialPanel(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("对【\(targetCfg?.name ?? "")】派遣使节（当前：\(bilateral.status.displayName)）")
                                .font(.subheadline.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)

                            HStack(spacing: 6) {
                                Button("馈赠 150 金") {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    let res = router.campaignEngine.sendDiplomaticGift(from: playerFaction, to: selectedDiploFaction, gold: 150, grain: 0)
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                                Button("丝路通商") {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    let res = router.campaignEngine.signTradePact(proposer: playerFaction, target: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                                Button("互不侵犯") {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    let res = router.campaignEngine.signNonAggressionPact(proposer: playerFaction, target: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                            }

                            HStack(spacing: 6) {
                                Button("缔结同盟") {
                                    let res = router.campaignEngine.formAlliance(proposer: playerFaction, target: selectedDiploFaction)
                                    if res.succeeded { BattleAudioEngine.shared.play(.ageFanfare, volumeScale: 0.75) }
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))

                                Button("王室联姻(150金)") {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    let res = router.campaignEngine.arrangeRoyalMarriage(proposer: playerFaction, target: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                                Button("纳贡附庸") {
                                    BattleAudioEngine.shared.play(.uiClick)
                                    let res = router.campaignEngine.establishVassalage(suzerain: playerFaction, vassal: selectedDiploFaction)
                                    localFeedback = res.message
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
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
                                        BattleAudioEngine.shared.play(.uiClick)
                                        let targetSecond = safeDiscordBinding.wrappedValue
                                        let res = router.campaignEngine.instigateDiscord(
                                            actor: playerFaction,
                                            targetA: selectedDiploFaction,
                                            targetB: targetSecond
                                        )
                                        localFeedback = res.message
                                    }
                                    .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                                }
                            }

                            Divider()

                            if bilateral.status != .war {
                                let warPreview = world.diplomacy.assessWarDeclarationImpact(attacker: playerFaction, target: selectedDiploFaction)
                                Text("开战预判：\(warPreview.ruleExplanation)")
                                    .font(.caption2)
                                    .foregroundStyle(warPreview.isBetrayalTriggered ? ImperialPalette.legionCrimsonBright : ImperialPalette.parchmentMuted)

                                Button("向【\(targetCfg?.name ?? "")】宣战") {
                                    if warPreview.isBetrayalTriggered {
                                        pendingBetrayalAssessment = warPreview
                                        pendingBetrayalTargetFaction = selectedDiploFaction
                                        pendingBetrayalMarchNodeId = nil
                                        showBetrayalAlert = true
                                    } else {
                                        BattleAudioEngine.shared.play(.warHorn)
                                        let impact = router.campaignEngine.declareWar(attacker: playerFaction, target: selectedDiploFaction)
                                        localFeedback = "已向【\(targetCfg?.name ?? "")】正式宣战（\(impact.ruleExplanation)）"
                                    }
                                }
                                .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
                            } else {
                                let maxGoldMultiple = max(100.0, Double((playerState.gold / 25) * 25))
                                let clampedGoldBinding = Binding<Double>(
                                    get: { min(maxGoldMultiple, max(-300.0, peaceGoldIndemnity)) },
                                    set: { peaceGoldIndemnity = $0 }
                                )
                                let effectiveGoldOffer = min(playerState.gold, Int(clampedGoldBinding.wrappedValue))

                                Text("🏳️ 停火媾和谈判（自由组合赔款/岁粮/割地/停战期）")
                                    .font(.caption.bold())
                                    .foregroundStyle(ImperialPalette.parchmentText)

                                HStack {
                                    Text("赔付金币 \(effectiveGoldOffer)（负数为向敌索赔）")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
                                    Spacer()
                                }
                                Slider(value: clampedGoldBinding, in: -300.0...maxGoldMultiple, step: 25.0)

                                HStack {
                                    Text("每回合纳粮 \(Int(peaceGrainPerTurn))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(ImperialPalette.parchmentMuted)
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
                                        BattleAudioEngine.shared.play(.ageFanfare, volumeScale: 0.75)
                                        activeCounterOffer = nil
                                        peaceCededNodeIds.removeAll()
                                        localFeedback = String(format: "🤝 议和成功（净分 +%.1f）：双方正式停战 %d 回合！", netScore, peaceTruceTurns)
                                    case .counterOffer(let netScore, let counter):
                                        BattleAudioEngine.shared.play(.uiClick)
                                        activeCounterOffer = counter
                                        localFeedback = String(format: "📜 对方提出反报价（原方案净分 %.1f）：可审阅下方反报价条款决定是否签约", netScore)
                                    case .rejectedBreakdown(_, let reason):
                                        BattleAudioEngine.shared.play(.defeatBell, volumeScale: 0.6)
                                        activeCounterOffer = nil
                                        localFeedback = "❌ 谈判破裂：\(reason)"
                                    }
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true))

                                if let counter = activeCounterOffer, counter.target == selectedDiploFaction {
                                    let cededNames = counter.cededNodeIds.compactMap { CampaignMapConfig.node(byId: $0)?.name }.joined(separator: "、")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("对方反报价单：赔金 \(counter.goldIndemnity) · 岁粮 \(counter.grainTributePerTurn)/回合 × \(counter.truceTurns) 回合\(cededNames.isEmpty ? "" : " · 割让[\(cededNames)]")")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.orange)
                                        Button("接受反报价并立即停战") {
                                            BattleAudioEngine.shared.play(.ageFanfare, volumeScale: 0.7)
                                            let res = router.campaignEngine.acceptPeaceCounterOffer(counter)
                                            activeCounterOffer = nil
                                            localFeedback = res.message
                                        }
                                        .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.14)))
                                }
                            }
                        }
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
                    ImperialPanel(padding: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("第 \(rep.resolvedTurnNumber) 回合战略结算详报")
                                .font(.subheadline.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)
                            Text("• 税赋与商路：城池金 +\(rep.playerGoldEarned)，通商金 +\(rep.playerTradeGoldEarned)，林木 +\(rep.playerWoodEarned)，净粮 \(rep.playerGrainNetChange >= 0 ? "+\(rep.playerGrainNetChange)" : "\(rep.playerGrainNetChange)")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ImperialPalette.parchmentText)
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
                                        .foregroundStyle(ImperialPalette.legionCrimsonBright)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("天下大势编年日志（累计胜 \(world.totalBattlesWon)/\(world.totalBattlesFought) 场 · 歼敌 \(world.totalEnemiesDefeated)）")
                    .font(.subheadline.bold())
                    .foregroundStyle(ImperialPalette.imperialGold)

                ForEach(world.eventLogs.reversed()) { log in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("[第 \(log.turnNumber) 回合 · \(log.category)]")
                                .font(.caption2.bold())
                                .foregroundStyle(ImperialPalette.imperialGoldBright)
                            Spacer()
                        }
                        Text(log.summary)
                            .font(.caption)
                            .foregroundStyle(ImperialPalette.parchmentText)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(ImperialPalette.obsidianElevated)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.30), lineWidth: 0.8))
                    )
                }
            }
        }
    }
}
