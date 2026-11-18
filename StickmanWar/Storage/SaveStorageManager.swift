import AppKit
import Foundation
import UniformTypeIdentifiers

/// 游戏用户偏好设置（持久化于 Application Support 目录，支持 macOS 外观、帧率、远景 LOD 与战斗反馈）
public struct GameUserSettings: Sendable, Codable, Equatable {
    public enum AppearancePreference: String, CaseIterable, Sendable, Codable, Identifiable {
        case system = "system"
        case darkWarRoom = "dark"
        case lightParchment = "light"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .system: return "跟随 macOS 系统外观"
            case .darkWarRoom: return "深色铁血帅帐（推荐）"
            case .lightParchment: return "浅色羊皮舆图"
            }
        }
    }

    public var targetFps: Int
    public var enableFarLod: Bool
    public var appearance: AppearancePreference
    public var masterVolume: Double
    public var sfxVolume: Double
    public var cameraEdgePanSpeed: Double
    public var invertScrollZoom: Bool
    public var showDamageNumbers: Bool
    public var enableEdgeCursorPan: Bool

    public init(
        targetFps: Int = GameConstants.renderTargetFps,
        enableFarLod: Bool = true,
        appearance: AppearancePreference = .darkWarRoom,
        masterVolume: Double = 0.85,
        sfxVolume: Double = 0.90,
        cameraEdgePanSpeed: Double = 520.0,
        invertScrollZoom: Bool = false,
        showDamageNumbers: Bool = true,
        enableEdgeCursorPan: Bool = false
    ) {
        self.targetFps = targetFps
        self.enableFarLod = enableFarLod
        self.appearance = appearance
        self.masterVolume = masterVolume
        self.sfxVolume = sfxVolume
        self.cameraEdgePanSpeed = cameraEdgePanSpeed
        self.invertScrollZoom = invertScrollZoom
        self.showDamageNumbers = showDamageNumbers
        self.enableEdgeCursorPan = enableEdgeCursorPan
    }

    enum CodingKeys: String, CodingKey {
        case targetFps
        case enableFarLod
        case appearance
        case masterVolume
        case sfxVolume
        case cameraEdgePanSpeed
        case invertScrollZoom
        case showDamageNumbers
        case enableEdgeCursorPan
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.targetFps = try c.decodeIfPresent(Int.self, forKey: .targetFps) ?? GameConstants.renderTargetFps
        self.enableFarLod = try c.decodeIfPresent(Bool.self, forKey: .enableFarLod) ?? true
        self.appearance = try c.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? .darkWarRoom
        self.masterVolume = try c.decodeIfPresent(Double.self, forKey: .masterVolume) ?? 0.85
        self.sfxVolume = try c.decodeIfPresent(Double.self, forKey: .sfxVolume) ?? 0.90
        self.cameraEdgePanSpeed = try c.decodeIfPresent(Double.self, forKey: .cameraEdgePanSpeed) ?? 520.0
        self.invertScrollZoom = try c.decodeIfPresent(Bool.self, forKey: .invertScrollZoom) ?? false
        self.showDamageNumbers = try c.decodeIfPresent(Bool.self, forKey: .showDamageNumbers) ?? true
        self.enableEdgeCursorPan = try c.decodeIfPresent(Bool.self, forKey: .enableEdgeCursorPan) ?? false
    }
}

/// 独立文件导出/导入完整军档包（同时内嵌槽位摘要与完整 40 城关战役快照，兼容旧版纯摘要 JSON）
public struct SaveArchiveBundle: Sendable, Codable, Equatable {
    public let bundleVersion: Int
    public let summary: SaveSlotSummary
    public let campaignWorldState: CampaignWorldState?

    public init(
        bundleVersion: Int = 1,
        summary: SaveSlotSummary,
        campaignWorldState: CampaignWorldState?
    ) {
        self.bundleVersion = bundleVersion
        self.summary = summary
        self.campaignWorldState = campaignWorldState
    }
}

/// macOS 原生离线存档与设置持久化管理器
/// 默认存储路径：`~/Library/Application Support/StickmanColdSteelWar/Saves/`
/// 同时支持通过 AppKit `NSSavePanel` / `NSOpenPanel` 原生文件对话框导出与导入 `.json` 存档包，全程零联网依赖。
public struct SaveStorageManager: Sendable {
    public static let appFolderName = "StickmanColdSteelWar"
    public static let savesSubfolderName = "Saves"
    public static let slotCount = 6

    /// 存档根目录 URL（支持在 XCTest 中注入临时目录做隔离读写测试）
    public let rootDirectoryURL: URL

    public var savesDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent(Self.savesSubfolderName, isDirectory: true)
    }

    public var settingsFileURL: URL {
        rootDirectoryURL.appendingPathComponent("settings.json", isDirectory: false)
    }

    public init(customRootDirectoryURL: URL? = nil) {
        if let customRootDirectoryURL {
            self.rootDirectoryURL = customRootDirectoryURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.rootDirectoryURL = appSupport.appendingPathComponent(Self.appFolderName, isDirectory: true)
        }
    }

    /// 确保 Application Support/StickmanColdSteelWar/Saves 目录已创建
    public func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(
            at: savesDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// 获取指定槽位摘要 JSON 文件路径（slot 0 为自动存档，1~5 为手动存档）
    public func fileURL(forSlot slotIndex: Int) -> URL {
        let filename = slotIndex == 0 ? "autosave_slot_0.json" : "save_slot_\(slotIndex).json"
        return savesDirectoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    /// 获取指定槽位完整战役状态 JSON 文件路径
    public func campaignWorldFileURL(forSlot slotIndex: Int) -> URL {
        let filename = slotIndex == 0
            ? "campaign_world_autosave_0.json"
            : "campaign_world_slot_\(slotIndex).json"
        return savesDirectoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    /// 检查指定槽位是否存在完整战役世界快照文件
    public func hasCampaignWorldSnapshot(at slotIndex: Int) -> Bool {
        FileManager.default.fileExists(atPath: campaignWorldFileURL(forSlot: slotIndex).path)
    }

    /// 读取全部 6 个存档槽位摘要（不存在或损坏的槽位自动安全回退为空白槽位，防读档崩溃）
    public func loadAllSlotSummaries() -> [SaveSlotSummary] {
        let decoder = JSONDecoder()
        return (0..<Self.slotCount).map { idx in
            let url = fileURL(forSlot: idx)
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? decoder.decode(SaveSlotSummary.self, from: data) else {
                var empty = SaveSlotSummary.emptySlot(index: idx)
                if idx == 0 {
                    empty.title = "自动军档槽位（回合结算/战后自动备份）"
                }
                return empty
            }
            return decoded
        }
    }

    /// 原子化写入存档槽位摘要（Write-Temp-Then-Rename 防止断电损坏原档）
    public func writeSlotSummary(_ summary: SaveSlotSummary) throws {
        try ensureDirectoriesExist()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: fileURL(forSlot: summary.slotIndex), options: [.atomic])
    }

    /// 删除指定存档槽位（同步清理槽位摘要与战役世界完整快照）并恢复为空白态
    public func deleteSlot(at slotIndex: Int) throws {
        let summaryURL = fileURL(forSlot: slotIndex)
        if FileManager.default.fileExists(atPath: summaryURL.path) {
            try FileManager.default.removeItem(at: summaryURL)
        }
        let worldURL = campaignWorldFileURL(forSlot: slotIndex)
        if FileManager.default.fileExists(atPath: worldURL.path) {
            try FileManager.default.removeItem(at: worldURL)
        }
    }

    /// 读取用户设置（若尚未创建则返回标准默认配置）
    public func loadSettings() -> GameUserSettings {
        guard let data = try? Data(contentsOf: settingsFileURL),
              let settings = try? JSONDecoder().decode(GameUserSettings.self, from: data) else {
            return GameUserSettings()
        }
        return settings
    }

    /// 原子化保存用户设置
    public func saveSettings(_ settings: GameUserSettings) throws {
        try ensureDirectoriesExist()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsFileURL, options: [.atomic])
    }

    // MARK: - AppKit 原生文件对话框导出 / 导入（主线程调用）

    /// 弹出 macOS 原生 NSSavePanel 将指定存档连同完整战役世界快照导出为独立 `.json` 备份文件
    @MainActor
    public func exportSlotViaSavePanel(_ summary: SaveSlotSummary, fallbackWorldState: CampaignWorldState? = nil) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出《火柴人冷兵器大战》本地军档"
        panel.prompt = "导出军档"
        panel.nameFieldStringValue = "StickmanWar_Slot\(summary.slotIndex)_\(summary.factionId.rawValue)_Turn\(summary.turnNumber).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return nil
        }

        let storedWorld: CampaignWorldState? = {
            let worldURL = campaignWorldFileURL(forSlot: summary.slotIndex)
            if let data = try? Data(contentsOf: worldURL),
               let decoded = try? JSONDecoder().decode(CampaignWorldState.self, from: data) {
                return decoded
            }
            return fallbackWorldState
        }()

        let bundle = SaveArchiveBundle(summary: summary, campaignWorldState: storedWorld)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bundle)
        try data.write(to: destinationURL, options: [.atomic])
        return destinationURL
    }

    /// 弹出 macOS 原生 NSOpenPanel 导入外部 `.json` 军档文件（兼容完整 Bundle 与单摘要格式）并落盘
    @MainActor
    public func importSlotViaOpenPanel(targetSlotIndex: Int) throws -> SaveSlotSummary? {
        let panel = NSOpenPanel()
        panel.title = "导入《火柴人冷兵器大战》本地军档"
        panel.prompt = "导入军档"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return nil
        }
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()

        let importedSummary: SaveSlotSummary
        let importedWorld: CampaignWorldState?
        if let bundle = try? decoder.decode(SaveArchiveBundle.self, from: data) {
            importedSummary = bundle.summary
            importedWorld = bundle.campaignWorldState
        } else {
            importedSummary = try decoder.decode(SaveSlotSummary.self, from: data)
            importedWorld = nil
        }

        let normalized = SaveSlotSummary(
            schemaVersion: importedSummary.schemaVersion,
            slotIndex: targetSlotIndex,
            title: importedSummary.title,
            factionId: importedSummary.factionId,
            turnNumber: max(1, importedSummary.turnNumber),
            controlledNodes: max(0, min(GameConstants.campaignNodeCount, importedSummary.controlledNodes)),
            totalBattlesWon: max(0, importedSummary.totalBattlesWon),
            totalEnemiesDefeated: max(0, importedSummary.totalEnemiesDefeated),
            updatedAtIso: importedSummary.updatedAtIso,
            isEmpty: false
        )
        try ensureDirectoriesExist()
        if let world = importedWorld {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let worldData = try encoder.encode(world)
            try worldData.write(to: campaignWorldFileURL(forSlot: targetSlotIndex), options: [.atomic])
        }
        try writeSlotSummary(normalized)
        return normalized
    }
}
