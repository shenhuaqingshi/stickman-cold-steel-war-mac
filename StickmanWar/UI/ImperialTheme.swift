import SwiftUI

/// 《火柴人冷兵器大战 · 帝国锋刃》全局视觉语言系统
/// 采用黑曜玄铁底色、古罗马鎏金铜框、朱砂战旗红与羊皮卷暖白文字，彻底告别原生表单灰框感。
public enum ImperialPalette {
    public static let obsidianDeep = Color(red: 0.06, green: 0.06, blue: 0.07)
    public static let obsidianCard = Color(red: 0.10, green: 0.09, blue: 0.08)
    public static let obsidianElevated = Color(red: 0.14, green: 0.12, blue: 0.10)
    public static let bronzeBorder = Color(red: 0.62, green: 0.48, blue: 0.24)
    public static let imperialGold = Color(red: 0.91, green: 0.74, blue: 0.34)
    public static let imperialGoldBright = Color(red: 0.99, green: 0.86, blue: 0.48)
    public static let legionCrimson = Color(red: 0.68, green: 0.15, blue: 0.14)
    public static let legionCrimsonBright = Color(red: 0.86, green: 0.24, blue: 0.20)
    public static let parchmentText = Color(red: 0.95, green: 0.92, blue: 0.85)
    public static let parchmentMuted = Color(red: 0.72, green: 0.67, blue: 0.58)
    public static let jadeSupply = Color(red: 0.22, green: 0.76, blue: 0.44)

    public static let goldGradient = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.82, blue: 0.44),
            Color(red: 0.76, green: 0.56, blue: 0.20)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let crimsonWarGradient = LinearGradient(
        colors: [
            Color(red: 0.78, green: 0.18, blue: 0.15),
            Color(red: 0.48, green: 0.09, blue: 0.08)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let panelBackgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.13, green: 0.11, blue: 0.10).opacity(0.95),
            Color(red: 0.08, green: 0.07, blue: 0.07).opacity(0.97)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 鎏金雕花角标古铜面板容器
public struct ImperialPanel<Content: View>: View {
    private let cornerRadius: CGFloat
    private let borderOpacity: Double
    private let paddingValue: CGFloat
    private let content: Content

    public init(
        cornerRadius: CGFloat = 10,
        borderOpacity: Double = 0.55,
        padding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.borderOpacity = borderOpacity
        self.paddingValue = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(paddingValue)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(ImperialPalette.panelBackgroundGradient)
                    .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                ImperialPalette.imperialGold.opacity(borderOpacity),
                                ImperialPalette.bronzeBorder.opacity(borderOpacity * 0.55),
                                ImperialPalette.imperialGold.opacity(borderOpacity * 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
    }
}

/// 帝国主战朱砂鎏金按钮样式（用于“誓师出征 / 开启会战 / 演进时代”等核心召唤动作）
public struct ImperialCrimsonButtonStyle: ButtonStyle {
    var isCompact: Bool = false

    public init(isCompact: Bool = false) {
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? .callout.bold() : .headline.bold())
            .foregroundStyle(ImperialPalette.parchmentText)
            .padding(.horizontal, isCompact ? 12 : 18)
            .padding(.vertical, isCompact ? 6 : 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ImperialPalette.crimsonWarGradient)
                    .brightness(configuration.isPressed ? -0.08 : 0.0)
                    .shadow(color: ImperialPalette.legionCrimson.opacity(0.45), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ImperialPalette.imperialGold.opacity(0.85), lineWidth: 1.3)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

/// 古铜锻铁次级按钮样式
public struct ImperialBronzeButtonStyle: ButtonStyle {
    var isHighlighted: Bool = false
    var isCompact: Bool = false

    public init(isHighlighted: Bool = false, isCompact: Bool = false) {
        self.isHighlighted = isHighlighted
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? .caption.bold() : .callout.weight(.semibold))
            .foregroundStyle(isHighlighted ? ImperialPalette.obsidianDeep : ImperialPalette.parchmentText)
            .padding(.horizontal, isCompact ? 9 : 13)
            .padding(.vertical, isCompact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        isHighlighted
                            ? AnyShapeStyle(ImperialPalette.goldGradient)
                            : AnyShapeStyle(ImperialPalette.obsidianElevated.opacity(0.92))
                    )
                    .brightness(configuration.isPressed ? -0.08 : 0.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        isHighlighted ? ImperialPalette.imperialGoldBright : ImperialPalette.bronzeBorder.opacity(0.60),
                        lineWidth: isHighlighted ? 1.4 : 1.0
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

/// 势力纹章盾徽组件
public struct FactionCrestBadge: View {
    public let faction: FactionStaticConfig
    public var size: CGFloat = 38

    public init(faction: FactionStaticConfig, size: CGFloat = 38) {
        self.faction = faction
        self.size = size
    }

    private var symbolName: String {
        switch faction.id {
        case .yanlong: return "flame.circle.fill"
        case .canglang: return "wind.circle.fill"
        case .tieying: return "shield.checkered"
        case .shamo: return "sun.max.circle.fill"
        case .shuangyuan: return "snowflake.circle.fill"
        case .wulin: return "leaf.circle.fill"
        case .xuanjia: return "bolt.shield.fill"
        case .xueyue: return "moon.circle.fill"
        }
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: faction.primaryColorHex),
                            Color(hex: faction.primaryColorHex).opacity(0.45),
                            ImperialPalette.obsidianDeep
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(ImperialPalette.imperialGold, lineWidth: max(1.2, size * 0.05))
                .frame(width: size, height: size)
            Image(systemName: symbolName)
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(Color(hex: faction.accentColorHex))
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
    }
}

/// 兵种职能图标辅助映射
public enum UnitVisualSymbol {
    public static func sfSymbol(for unitId: UnitTypeId) -> String {
        switch unitId {
        case .sapper: return "hammer.fill"
        case .shieldSwordsman: return "shield.lefthalf.filled"
        case .pikeman: return "arrow.up.to.line.compact"
        case .compositeArcher: return "arrow.up.right"
        case .lightCavalry: return "hare.fill"
        case .greatAxeman: return "burst.fill"
        case .ballista: return "scope"
        case .trebuchet: return "flame.fill"
        case .yanlongHalberdGrenadier: return "sparkles"
        case .canglangKeshigHorseArcher: return "wind"
        case .tieyingPaviseCrossbow: return "shield.checkerboard"
        case .shamoMamelukeCamel: return "crown.fill"
        case .shuangyuanGiantBreaker: return "tornado"
        case .wulinShadowSniper: return "eye.slash.fill"
        case .xuanjiaCataphract: return "bolt.horizontal.circle.fill"
        case .xueyueWardrumBerserker: return "waveform.path.ecg"
        }
    }
}
