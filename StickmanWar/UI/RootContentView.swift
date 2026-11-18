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
        .sheet(isPresented: $router.showQuickHelpSheet) {
            QuickTacticalHelpSheet(isPresented: $router.showQuickHelpSheet)
        }
    }
}

/// 菜单栏【帮助 -> 兵种克制闭环与 Mac 键鼠操作速查 (⌘/)】原生 Sheet 面板
private struct QuickTacticalHelpSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("冷兵器克制闭环与 macOS 键鼠速查")
                    .font(.title2.bold())
                Spacer()
                Button("关闭 (Esc)") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            GroupBox("四大闭环克制铁律") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 刀盾步兵（55% 正面盾防）顶箭克制 复合弓手 -> 复合弓手 抛射克制无盾 长枪兵 / 巨斧兵 / 狂战士")
                    Text("• 长枪方阵兵（3.2× 反骑 + 30% 动能破甲停马）正面克制 骑兵 -> 骑兵 高速绕后切碎 弓弩手 / 投石车 / 工兵")
                    Text("• 重型巨斧兵 / 巨熊破阵者（65%~70% 破甲）横扫克制 重甲刀盾 -> 连弩车 / 神弩手 高破甲点杀 巨人 / 铁浮图")
                    Text("• 配重投石车 超远砸崩 密集方阵与城墙 -> 游骑兵 / 影袭神射 突入 220px 盲区摧毁 投石车")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("macOS 双视角键鼠核心操作") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• RTS 统帅视角：左键点选/拖拽框选部队，右键移动/攻击，双指滑动或中键平移，⌘+滚轮/双指捏合缩放")
                    Text("• RTS 编队快捷键：[1~4] 方阵/雁行/锥形/圆阵；[Q/W/E/R/F] 推进/坚守/冲锋/撤退/包抄；[B] 鸣响本阵警钟；[Space] 战术暂停")
                    Text("• 亲自上阵英雄视角（[Tab] 切换，冷却 1.5s）：[WASD] 移动主帅，鼠标瞄准，左键挥砍/蓄力射箭，右键举盾弹反（0.25s 窗口）")
                    Text("• 英雄武器与技能：[1/2/3] 统帅佩刀 / 破阵大枪 / 百石硬弓（24 支箭袋上限）；[Space] 破阵突击，[E] 铁壁横戈，[R] 三军战吼")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 720, height: 430)
    }
}
