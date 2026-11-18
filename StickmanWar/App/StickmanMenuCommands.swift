import SwiftUI

/// macOS 原生顶部 AppKit 菜单栏指令集（应用设置 / 文件 / 视图 / 帮助）
/// 采用 `let router: AppRouter` + `Task { @MainActor in ... }` 隔离派发，100% 满足 Swift 6 Strict Concurrency Complete 检查。
public struct StickmanMenuCommands: Commands {
    let router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some Commands {
        // 0. 应用主菜单（StickmanWar -> 游戏设置… ⌘,），遵循 macOS 标准 HIG 菜单槽位
        CommandGroup(replacing: .appSettings) {
            Button("游戏设置与键位指南…") {
                Task { @MainActor in router.navigate(to: .settings) }
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        // 1. 文件菜单：新建战局、快速存档、原生文件对话框导入/导出军档
        CommandGroup(replacing: .newItem) {
            Button("新建战役模式") {
                Task { @MainActor in router.startMode(.campaign, forceNewCampaign: true) }
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("快速遭遇战") {
                Task { @MainActor in router.startMode(.skirmish) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("守城挑战模式") {
                Task { @MainActor in router.startMode(.siegeChallenge) }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button("快速保存战役至槽位 #1") {
                Task { @MainActor in router.saveCurrentCampaignSnapshot(toSlot: 1) }
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("从文件导入军档…") {
                Task { @MainActor in router.importArchiveFromFinder(intoSlot: 1) }
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("导出军档备份为文件…") {
                Task { @MainActor in router.exportArchiveToFinder(slotIndex: 1) }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("管理本地军档槽位") {
                Task { @MainActor in router.navigate(to: .saveLoad) }
            }
            .keyboardShortcut("l", modifiers: [.command])
        }

        // 2. 视图菜单：核心路由直达
        CommandGroup(after: .toolbar) {
            Divider()

            Button("返回主帅大帐（主菜单）") {
                Task { @MainActor in router.returnToMainMenu() }
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("战略大地图与外交面板") {
                Task { @MainActor in router.startMode(.campaign, forceNewCampaign: false) }
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("战前整军面板") {
                Task { @MainActor in router.navigate(to: .preBattleSetup) }
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("立即开拔进入大战场") {
                Task { @MainActor in router.launchBattlefieldFromSetup() }
            }
            .keyboardShortcut("4", modifiers: [.command])
        }

        // 3. 帮助菜单：兵种克制与键鼠操控速查
        CommandGroup(replacing: .help) {
            Button("兵种克制闭环与 Mac 键鼠操作速查") {
                Task { @MainActor in router.showQuickHelpSheet = true }
            }
            .keyboardShortcut("/", modifiers: [.command])
        }
    }
}
