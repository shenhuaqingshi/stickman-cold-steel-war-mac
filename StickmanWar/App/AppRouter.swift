import Foundation
import Observation

/// macOS 版 7 个核心业务页面路由枚举（与鸿蒙版 Stage 7 页一一对应）
public enum AppRoute: String, CaseIterable, Sendable, Hashable, Identifiable {
    case mainMenu = "main_menu"               // 1. 主菜单（战役/遭遇战/守城挑战/自定义/存档/设置）
    case campaignMap = "campaign_map"         // 2. 战役战略大地图与外交纵横面板页（40节点·78道路）
    case preBattleSetup = "pre_battle_setup"  // 3. 战前整军配兵页（遭遇战/守城挑战/自定义演武/战役整军）
    case battlefield = "battlefield"          // 4. 4800×2400 大战场与主帅英雄切换页（SpriteKit 宿主）
    case battleResult = "battle_result"       // 5. 战后结算页（伤兵恢复/俘虏/粮械缴获/晋升）
    case saveLoad = "save_load"               // 6. 本地存档与历史战绩页（Application Support + 原生对话框）
    case settings = "settings"                // 7. 游戏设置与 macOS 键鼠快捷键说明页

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mainMenu: return "主帅大帐 · 主菜单"
        case .campaignMap: return "战略大地图 · 外交纵横"
        case .preBattleSetup: return "战前整军 · 兵种编组"
        case .battlefield: return "冷兵器大战场 · 双视角"
        case .battleResult: return "战后军功结算"
        case .saveLoad: return "本地军档与战绩"
        case .settings: return "游戏设置与键鼠指南"
        }
    }
}

/// 全局应用路由与顶层会话状态容器（Swift 6 `@MainActor @Observable`）
@MainActor
@Observable
public final class AppRouter {
    /// 当前激活的核心路由页
    public private(set) var currentRoute: AppRoute = .mainMenu
    /// 历史返回栈
    public private(set) var routeHistory: [AppRoute] = []

    /// 当前战局启动配置上下文
    public var launchContext = RouteLaunchContext()
    /// 当前即将进入 `BattlefieldView` 的完整军团部署参数包
    public var pendingBattleDeployment = BattleDeploymentConfig()
    /// 战役模式下最近一次行军触发的前线补给/士气修正包（供战前整军面板检阅）
    public var activeCampaignBattleModifiers: CampaignBattleLaunchModifiers? = nil
    /// 遭遇战 / 守城挑战 / 自定义战场的玩家可编辑 6 军团编制表
    public var setupPlayerRoster: [BattleArmyRosterEntry] = BattleSimulationEngine.defaultSixCorpsRoster(
        for: .yanlong,
        scenario: .fieldPitched,
        isPlayer: true
    )
    /// 遭遇战 / 守城挑战 / 自定义战场的敌军可编辑 6 军团编制表
    public var setupEnemyRoster: [BattleArmyRosterEntry] = BattleSimulationEngine.defaultSixCorpsRoster(
        for: .canglang,
        scenario: .fieldPitched,
        isPlayer: false
    )

    /// 战役全局战略推演引擎（40 节点 · 78 条道路 · 8 势力外交与回合演化）
    public var campaignEngine: CampaignTurnEngine
    /// 最近一回合战略结算详报（供战役大地图展示税赋、粮道告警与天下大势简报）
    public var latestTurnReport: CampaignTurnResolutionReport? = nil

    /// 最近一场战后结算展示数据
    public var latestSettlement = PostBattleSettlementSummary()
    /// 标记当前战后结算是否尚未回写至战役引擎（防止重复点击多次加钱夺城）
    public var hasUnappliedCampaignSettlement: Bool = false

    /// 用户持久化设置
    public var userSettings: GameUserSettings
    /// 6 个本地存档槽位摘要（#0 自动存档，#1~#5 手动存档）
    public var saveSlots: [SaveSlotSummary]
    /// 底部或顶部全局操作反馈提示语
    public var bannerMessage: String = "统帅大帐就绪：可选定八大势力开启 40 城关战役，或直接进入 4800×2400 冷兵器大战场"
    /// 是否弹出快捷键与克制帮助速查面板
    public var showQuickHelpSheet: Bool = false

    public let storageManager: SaveStorageManager

    public init(storageManager: SaveStorageManager = SaveStorageManager()) {
        self.storageManager = storageManager
        let loadedSettings = storageManager.loadSettings()
        self.userSettings = loadedSettings
        let slots = storageManager.loadAllSlotSummaries()
        self.saveSlots = slots

        // 若本地存在自动军档快照则优先预载，否则按默认炎龙帝国初始化第 1 回合战役态势
        if let restored = try? CampaignTurnEngine.loadFromStorage(using: storageManager, slotIndex: 0) {
            self.campaignEngine = restored
            self.launchContext.playerFaction = restored.worldState.playerFaction
        } else {
            self.campaignEngine = CampaignTurnEngine(playerFaction: .yanlong)
        }
        rebuildSkirmishRostersForCurrentContext()
    }

    // MARK: - 路由跳转与模式启动

    public func navigate(to target: AppRoute) {
        guard target != currentRoute else { return }
        routeHistory.append(currentRoute)
        currentRoute = target
    }

    /// 开启指定游戏模式（战役 / 遭遇战 / 守城挑战 / 自定义沙盒）
    public func startMode(_ mode: GameEntryMode, playerFaction: FactionId? = nil, forceNewCampaign: Bool = false) {
        if let playerFaction {
            launchContext.playerFaction = playerFaction
        }
        launchContext.entryMode = mode
        activeCampaignBattleModifiers = nil

        // 确保敌我默认不为同一势力
        if launchContext.enemyFaction == launchContext.playerFaction {
            launchContext.enemyFaction = launchContext.playerFaction == .yanlong ? .canglang : .yanlong
        }

        switch mode {
        case .campaign:
            if forceNewCampaign || campaignEngine.worldState.playerFaction != launchContext.playerFaction {
                let seed = UInt64(Date().timeIntervalSince1970 * 1000) ^ 0x5354_4943_4B57_4152
                campaignEngine = CampaignTurnEngine(playerFaction: launchContext.playerFaction, seed: seed)
                latestTurnReport = nil
                autoSaveCampaignSilently()
                let fName = FactionConfig.config(for: launchContext.playerFaction)?.name ?? ""
                bannerMessage = "已开启【\(fName)】全新战略战役（第 1 回合 · 40 城关 · 78 条道路）"
            } else {
                let fName = FactionConfig.config(for: campaignEngine.worldState.playerFaction)?.name ?? ""
                bannerMessage = "继续【\(fName)】第 \(campaignEngine.worldState.turnNumber) 回合战略态势"
            }
            launchContext.scenarioType = .fieldPitched
            navigate(to: .campaignMap)

        case .skirmish:
            launchContext.scenarioType = .fieldPitched
            launchContext.terrain = FactionConfig.config(for: launchContext.playerFaction)?.homeTerrain ?? .plain
            launchContext.weather = .clearDay
            launchContext.targetNodeId = nil
            rebuildSkirmishRostersForCurrentContext()
            syncSkirmishDeploymentConfig()
            navigate(to: .preBattleSetup)

        case .siegeChallenge:
            launchContext.scenarioType = .siegeDefense
            launchContext.terrain = .fortWall
            launchContext.weather = .clearDay
            launchContext.targetNodeId = nil
            rebuildSkirmishRostersForCurrentContext()
            syncSkirmishDeploymentConfig()
            navigate(to: .preBattleSetup)

        case .customSandbox:
            launchContext.scenarioType = .fieldPitched
            launchContext.terrain = .plain
            launchContext.weather = .clearDay
            launchContext.targetNodeId = nil
            rebuildSkirmishRostersForCurrentContext()
            pendingBattleDeployment.playerInitialGold = 900
            pendingBattleDeployment.playerInitialWood = 650
            pendingBattleDeployment.playerInitialGrain = 1600.0
            navigate(to: .preBattleSetup)
        }
    }

    /// 根据当前 `launchContext` 重置遭遇战 / 守城挑战双方默认 6 军团兵表
    public func rebuildSkirmishRostersForCurrentContext() {
        setupPlayerRoster = BattleSimulationEngine.defaultSixCorpsRoster(
            for: launchContext.playerFaction,
            scenario: launchContext.scenarioType,
            isPlayer: true
        )
        var enemyBase = BattleSimulationEngine.defaultSixCorpsRoster(
            for: launchContext.enemyFaction,
            scenario: launchContext.scenarioType,
            isPlayer: false
        )
        // 守城挑战模式下攻城敌军配置更雄厚兵力与双投石车压境
        if launchContext.entryMode == .siegeChallenge {
            enemyBase = enemyBase.map { entry in
                let boosted = entry.unitType == .trebuchet || entry.unitType == .ballista
                    ? entry.count + 1
                    : Int((Double(entry.count) * 1.25).rounded())
                return BattleArmyRosterEntry(
                    corpsRole: entry.corpsRole,
                    unitType: entry.unitType,
                    count: boosted,
                    initialFormation: entry.initialFormation
                )
            }
        }
        setupEnemyRoster = enemyBase
    }

    /// 将 `PreBattleSetupView` 中编组好的参数同步至 `pendingBattleDeployment`
    public func syncSkirmishDeploymentConfig() {
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) ^ 0x2026_1118_5357_4152
        pendingBattleDeployment = BattleDeploymentConfig(
            customPlayerRoster: setupPlayerRoster,
            customEnemyRoster: setupEnemyRoster,
            playerInitialGold: pendingBattleDeployment.playerInitialGold > 0 ? pendingBattleDeployment.playerInitialGold : GameConstants.battleInitGold,
            playerInitialWood: pendingBattleDeployment.playerInitialWood > 0 ? pendingBattleDeployment.playerInitialWood : GameConstants.battleInitWood,
            playerInitialGrain: pendingBattleDeployment.playerInitialGrain > 0 ? pendingBattleDeployment.playerInitialGrain : GameConstants.battleInitGrain,
            enemyInitialGrain: GameConstants.battleInitGrain,
            playerSupplyStatus: .fullSupply(hops: 1),
            playerBetrayalMoralePenalty: 0.0,
            enemyInitialMoraleDelta: 0.0,
            isPlayerCommanderWeakened: false,
            applySupplyGrainDiscountInEngine: false,
            siegeHoldTargetSeconds: 150.0,
            randomSeed: seed
        )
    }

    /// 从战役大地图行军或迎击攻城进入战前整军面板（自动注入真实主力编制、BFS 粮道与士气修正）
    public func enterCampaignPreBattle(
        context: RouteLaunchContext,
        modifiers: CampaignBattleLaunchModifiers?
    ) {
        self.launchContext = context
        self.activeCampaignBattleModifiers = modifiers
        let deploy = campaignEngine.buildBattleDeploymentConfig(for: context, modifiers: modifiers)
        self.pendingBattleDeployment = deploy
        if let pRoster = deploy.customPlayerRoster {
            self.setupPlayerRoster = pRoster
        }
        if let eRoster = deploy.customEnemyRoster {
            self.setupEnemyRoster = eRoster
        }
        navigate(to: .preBattleSetup)
    }

    /// 从战前整军面板正式开拔进入 SpriteKit 大战场
    public func launchBattlefieldFromSetup() {
        if launchContext.entryMode == .campaign {
            var deploy = campaignEngine.buildBattleDeploymentConfig(
                for: launchContext,
                modifiers: activeCampaignBattleModifiers
            )
            // 保留玩家在整军页对各军团初始阵型的微调
            deploy.customPlayerRoster = setupPlayerRoster
            pendingBattleDeployment = deploy
        } else {
            syncSkirmishDeploymentConfig()
        }
        navigate(to: .battlefield)
    }

    /// 战斗结束：写入真实 `PostBattleSettlementSummary` 并跳转结算页
    public func completeBattleAndShowResult(_ summary: PostBattleSettlementSummary) {
        latestSettlement = summary
        hasUnappliedCampaignSettlement = (launchContext.entryMode == .campaign)
        navigate(to: .battleResult)
    }

    /// 在结算页确认战俘处置策略后，将战果原子回写至 40 城关大地图并返回
    public func applyCampaignSettlementAndReturn(prisonerChoice: CampaignPrisonerDisposition) {
        if hasUnappliedCampaignSettlement {
            hasUnappliedCampaignSettlement = false
            campaignEngine.applyPostBattleSettlement(
                latestSettlement,
                prisonerDisposition: prisonerChoice,
                explicitTargetNodeId: launchContext.targetNodeId
            )
            activeCampaignBattleModifiers = nil
            autoSaveCampaignSilently()
            let nodeName = launchContext.targetNodeId.flatMap { CampaignMapConfig.node(byId: $0)?.name } ?? "前线战区"
            bannerMessage = latestSettlement.isVictory
                ? "捷报回传大帐：【\(nodeName)】会战告捷，版图、缴获与统帅历练已同步更新！"
                : "残部收拢回营：【\(nodeName)】战损抚恤与医帐伤兵救治已结算完毕。"
        }
        routeHistory.removeAll()
        currentRoute = .campaignMap
    }

    public func goBack() {
        if let previous = routeHistory.popLast() {
            currentRoute = previous
        } else {
            currentRoute = .mainMenu
        }
    }

    public func returnToMainMenu() {
        routeHistory.removeAll()
        currentRoute = .mainMenu
    }

    // MARK: - 本地存档与设置动作（真实读写 Application Support）

    public func reloadSlots() {
        saveSlots = storageManager.loadAllSlotSummaries()
    }

    public var mostRecentNonEmptySlot: SaveSlotSummary? {
        saveSlots
            .filter { !$0.isEmpty }
            .max { $0.updatedAtIso < $1.updatedAtIso }
    }

    public func autoSaveCampaignSilently() {
        _ = try? campaignEngine.saveToStorage(
            using: storageManager,
            slotIndex: 0,
            customTitle: "\(FactionConfig.config(for: campaignEngine.worldState.playerFaction)?.name ?? "") · 第 \(campaignEngine.worldState.turnNumber) 回合自动备份"
        )
        reloadSlots()
    }

    public func saveCurrentCampaignSnapshot(toSlot slotIndex: Int, customTitle: String? = nil) {
        do {
            let trimmed = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveTitle = (trimmed?.isEmpty == false) ? trimmed : nil
            let summary = try campaignEngine.saveToStorage(
                using: storageManager,
                slotIndex: slotIndex,
                customTitle: effectiveTitle
            )
            reloadSlots()
            bannerMessage = "已保存【\(summary.title)】至槽位 #\(slotIndex)（Application Support 离线原子写入）"
        } catch {
            bannerMessage = "写入存档失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    public func loadCampaignFromSlot(_ slotIndex: Int) -> Bool {
        guard saveSlots.indices.contains(slotIndex), !saveSlots[slotIndex].isEmpty else {
            bannerMessage = "槽位 #\(slotIndex) 为空，无法读取"
            return false
        }
        let slotMeta = saveSlots[slotIndex]
        do {
            if storageManager.hasCampaignWorldSnapshot(at: slotIndex) {
                let restored = try CampaignTurnEngine.loadFromStorage(using: storageManager, slotIndex: slotIndex)
                self.campaignEngine = restored
            } else {
                // 兼容仅有摘要元数据的存档槽位
                self.campaignEngine = CampaignTurnEngine(playerFaction: slotMeta.factionId)
            }
            self.launchContext.playerFaction = campaignEngine.worldState.playerFaction
            self.launchContext.entryMode = .campaign
            self.latestTurnReport = nil
            self.bannerMessage = "已读取军档【\(slotMeta.title)】（第 \(campaignEngine.worldState.turnNumber) 回合）"
            routeHistory.removeAll()
            currentRoute = .campaignMap
            return true
        } catch {
            bannerMessage = "读取槽位 #\(slotIndex) 失败：\(error.localizedDescription)"
            return false
        }
    }

    public func deleteSaveSlot(_ slotIndex: Int) {
        do {
            try storageManager.deleteSlot(at: slotIndex)
            reloadSlots()
            bannerMessage = "已清空本地存档槽位 #\(slotIndex)"
        } catch {
            bannerMessage = "删除存档失败：\(error.localizedDescription)"
        }
    }

    public func persistUserSettings() {
        do {
            try storageManager.saveSettings(userSettings)
            bannerMessage = "游戏偏好设置已持久化至 Application Support/StickmanColdSteelWar/settings.json"
        } catch {
            bannerMessage = "保存设置失败：\(error.localizedDescription)"
        }
    }

    public func resetUserSettingsToDefaults() {
        userSettings = GameUserSettings()
        persistUserSettings()
        bannerMessage = "已恢复默认显示、帧率与键鼠操控设置"
    }

    public func importArchiveFromFinder(intoSlot slotIndex: Int = 1) {
        do {
            if let imported = try storageManager.importSlotViaOpenPanel(targetSlotIndex: slotIndex) {
                reloadSlots()
                bannerMessage = "成功导入军档【\(imported.title)】至槽位 #\(slotIndex)"
                navigate(to: .saveLoad)
            }
        } catch {
            bannerMessage = "导入军档文件失败：\(error.localizedDescription)"
        }
    }

    public func exportArchiveToFinder(slotIndex: Int = 1) {
        var slot = saveSlots.indices.contains(slotIndex) ? saveSlots[slotIndex] : SaveSlotSummary.emptySlot(index: slotIndex)
        if slot.isEmpty {
            // 若选中的是空槽位，自动导出当前内存中的活跃战役快照
            slot = campaignEngine.worldState.makeSaveSlotSummary(
                slotIndex: slotIndex,
                updatedAtIso: ISO8601DateFormatter().string(from: Date())
            )
        }
        do {
            if let url = try storageManager.exportSlotViaSavePanel(slot, fallbackWorldState: campaignEngine.worldState) {
                bannerMessage = "已导出完整军档包至：\(url.lastPathComponent)"
            }
        } catch {
            bannerMessage = "导出军档文件失败：\(error.localizedDescription)"
        }
    }
}
