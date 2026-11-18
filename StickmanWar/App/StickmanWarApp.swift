import SwiftUI

/// 《火柴人冷兵器大战》macOS 原生应用入口（Swift 6 + SwiftUI + SpriteKit + AppKit）
@main
@MainActor
struct StickmanWarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter()

    private var resolvedColorScheme: ColorScheme? {
        switch router.userSettings.appearance {
        case .system:
            return nil
        case .darkWarRoom:
            return .dark
        case .lightParchment:
            return .light
        }
    }

    var body: some Scene {
        WindowGroup("火柴人冷兵器大战 · Stickman Cold Steel War") {
            RootContentView(router: router)
                .frame(
                    minWidth: GameConstants.macWindowMinWidth,
                    minHeight: GameConstants.macWindowMinHeight
                )
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(
            width: GameConstants.macWindowDefaultWidth,
            height: GameConstants.macWindowDefaultHeight
        )
        .commands {
            StickmanMenuCommands(router: router)
        }
    }
}
