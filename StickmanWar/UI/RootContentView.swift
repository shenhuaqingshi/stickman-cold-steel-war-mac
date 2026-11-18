import SwiftUI

/// SwiftUI 十六进制颜色解析扩展（支持将 FactionConfig 中的 `#C62828` 转为原生 Color）
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgbValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

/// 顶层路由分发容器（承载全部 7 个核心页面路由与全局速查弹窗）
public struct RootContentView: View {
    @Bindable var router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        Group {
            switch router.currentRoute {
            case .mainMenu:
                MainMenuView(router: router)
            case .campaignMap:
                CampaignMapView(router: router)
            case .preBattleSetup:
                PreBattleSetupView(router: router)
            case .battlefield:
                BattlefieldView(router: router)
            case .battleResult:
                BattleResultView(router: router)
            case .saveLoad:
                SaveLoadView(router: router)
            case .settings:
                SettingsView(router: router)
            }
        }
        .background(ImperialPalette.obsidianDeep)
        .onAppear {
            BattleAudioEngine.shared.masterVolume = Float(router.userSettings.masterVolume * router.userSettings.sfxVolume)
        }
        .sheet(isPresented: $router.showQuickHelpSheet) {
            QuickTacticalHelpSheet(isPresented: $router.showQuickHelpSheet)
        }
    }
}

/// 菜单栏【帮助 -> 兵种克制闭环与 Mac 键鼠操作速查 (⌘/)】帝国军典 Sheet 面板
private struct QuickTacticalHelpSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                Text("帝国锋刃 · 兵种克制闭环与键鼠指挥速查")
                    .font(.title2.bold())
                    .foregroundStyle(ImperialPalette.parchmentText)
                Spacer()
                Button("关闭 (Esc)") {
                    isPresented = false
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            ImperialPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("一、冷兵器四大克制铁律")
                        .font(.subheadline.bold())
                        .foregroundStyle(ImperialPalette.imperialGold)
                    Text("• 刀盾军团（正面 55% 挡箭，结[5]罗马龟甲阵高达 85% 挡箭！）克制 弓弩齐射 -> 弓弩手 抛射克制无盾 长枪兵 / 巨斧兵")
                    Text("• 长枪方阵（3.2× 反骑 + 30% 动能破甲停马）正面克制 冲锋骑兵 -> 骑兵 高速迂回切碎 弓弩手 / 投石车 / 民夫")
                    Text("• 重型巨斧 / 巨熊破阵者（65%~70% 破甲）劈开 重甲盾墙 -> 连弩车 / 影袭神射 高破甲点杀 重装巨人与铁浮图")
                    Text("• 配重投石车 远程轰塌 城墙箭塔与密集方阵 -> 轻骑兵 / 精锐步兵 突入 220px 最小射程盲区拆毁器械")
                }
                .font(.callout)
                .foregroundStyle(ImperialPalette.parchmentText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ImperialPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("二、指尖帝国营建 × 罗马拉线布阵 × 双视角无双")
                        .font(.subheadline.bold())
                        .foregroundStyle(ImperialPalette.imperialGold)
                    Text("• 罗马拉线布阵：左键框选军团，按住右键在地面横向拖拽即可自由拉出宽窄战线与迎敌朝向；[1~5] 切换方阵/雁行/锥形/圆阵/龟甲阵")
                    Text("• 帝国营建与时代演进：建造民居(+16人口)、农庄(+军粮)、兵营/靶场/马厩(加速募兵)、铁匠铺(三系攻防锻造 Lv.1~3)，演进四大文明时代")
                    Text("• 主帅提刀上阵（[Tab] 切换）：[WASD] 走位，左键挥砍/穿刺/蓄力射箭，右键 0.25s 精准弹反震晕近敌，[R] 战吼唤醒白旗溃兵")
                }
                .font(.callout)
                .foregroundStyle(ImperialPalette.parchmentText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        .background(ImperialPalette.obsidianDeep)
        .frame(width: 780, height: 470)
    }
}
