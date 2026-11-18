import SwiftUI

/// 核心路由 6：帝国军档枢密院与战绩统计页
/// 真实读写 `~/Library/Application Support/StickmanColdSteelWar/Saves/`，支持完整 40 城关战役快照持久化及原生 `NSOpenPanel`/`NSSavePanel` 导入导出。
public struct SaveLoadView: View {
    @Bindable var router: AppRouter
    @State private var selectedSlotIndex: Int = 1
    @State private var customArchiveTitle: String = ""

    private var activeFactionName: String {
        FactionConfig.config(for: router.campaignEngine.worldState.playerFaction)?.name ?? ""
    }

    private var activeControlledCount: Int {
        router.campaignEngine.controlledNodes(of: router.campaignEngine.worldState.playerFaction).count
    }

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button("‹ 返回上一页") {
                    BattleAudioEngine.shared.play(.uiClick)
                    router.goBack()
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                Text("帝国军档枢密院 · 本地离线归档与战绩")
                    .font(.title3.bold())
                    .foregroundStyle(ImperialPalette.parchmentText)

                Spacer()

                Button("从 Finder 导入军档… (⌘O)") {
                    BattleAudioEngine.shared.play(.uiClick)
                    router.importArchiveFromFinder(intoSlot: max(1, selectedSlotIndex))
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                Button("导出选中军档备份… (⇧⌘S)") {
                    BattleAudioEngine.shared.play(.uiClick)
                    router.exportArchiveToFinder(slotIndex: selectedSlotIndex)
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
            }

            // 当前内存活跃战役概览与快捷命名保存条
            ImperialPanel(padding: 12) {
                HStack(spacing: 12) {
                    if let pCfg = FactionConfig.config(for: router.campaignEngine.worldState.playerFaction) {
                        FactionCrestBadge(faction: pCfg, size: 34)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前活跃战役会话（可写入任意手动军档槽 #1 ~ #5）")
                            .font(.caption.bold())
                            .foregroundStyle(ImperialPalette.imperialGold)
                        Text("统帅：【\(activeFactionName)】 · 第 \(router.campaignEngine.worldState.turnNumber) 回合 · 疆域 \(activeControlledCount)/\(GameConstants.campaignNodeCount) · 累计胜 \(router.campaignEngine.worldState.totalBattlesWon) 场")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(ImperialPalette.parchmentText)
                    }

                    Spacer()

                    TextField("可选自定义军档封号…", text: $customArchiveTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    Button("钤印保存至槽位 #\(max(1, selectedSlotIndex))") {
                        BattleAudioEngine.shared.play(.forgeClang, volumeScale: 0.7)
                        let targetSlot = max(1, selectedSlotIndex)
                        router.saveCurrentCampaignSnapshot(toSlot: targetSlot, customTitle: customArchiveTitle)
                        customArchiveTitle = ""
                    }
                    .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
                }
            }

            ImperialPanel(padding: 10) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(ImperialPalette.imperialGold)
                    Text(router.storageManager.savesDirectoryURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                        .textSelection(.enabled)
                    Spacer()
                    Text("macOS 原子写入保护 · 含 40 城关/赋税/诏令/外交完整快照 · 100% 纯离线")
                        .font(.caption2.bold())
                        .foregroundStyle(ImperialPalette.jadeSupply)
                }
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(router.saveSlots) { slot in
                        saveSlotRow(slot)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(ImperialPalette.imperialGold)
                Text(router.bannerMessage)
                    .font(.footnote)
                    .foregroundStyle(ImperialPalette.parchmentText)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ImperialPalette.obsidianCard)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ImperialPalette.bronzeBorder.opacity(0.45), lineWidth: 1))
            )
        }
        .padding(20)
        .background(ImperialPalette.obsidianDeep)
        .onAppear {
            router.reloadSlots()
        }
    }

    private func saveSlotRow(_ slot: SaveSlotSummary) -> some View {
        let isSelected = (slot.slotIndex == selectedSlotIndex)
        let fCfg = FactionConfig.config(for: slot.factionId)
        let factionName = fCfg?.name ?? "无"
        let hasFullWorld = router.storageManager.hasCampaignWorldSnapshot(at: slot.slotIndex)

        return HStack(spacing: 14) {
            if !slot.isEmpty, let fCfg {
                FactionCrestBadge(faction: fCfg, size: 38)
            } else {
                ZStack {
                    Circle()
                        .fill(ImperialPalette.obsidianElevated)
                        .frame(width: 38, height: 38)
                    Circle()
                        .strokeBorder(ImperialPalette.bronzeBorder.opacity(0.5), lineWidth: 1.2)
                        .frame(width: 38, height: 38)
                    Image(systemName: "tray")
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(slot.slotIndex == 0 ? "[自动军档 #0]" : "[手动槽位 #\(slot.slotIndex)]")
                        .font(.subheadline.monospaced().bold())
                        .foregroundStyle(slot.slotIndex == 0 ? Color.cyan : ImperialPalette.imperialGold)
                    Text(slot.title)
                        .font(.headline)
                        .foregroundStyle(ImperialPalette.parchmentText)
                    if !slot.isEmpty && hasFullWorld {
                        Text("完整帝国快照")
                            .font(.caption2.bold())
                            .foregroundStyle(ImperialPalette.jadeSupply)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(ImperialPalette.jadeSupply.opacity(0.16)))
                    }
                }

                if slot.isEmpty {
                    Text("空白军档卷宗 —— 点击右侧【保存至此】即可封存当前 40 城关天下大势")
                        .font(.caption)
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                } else {
                    Text("势力：\(factionName) · 第 \(slot.turnNumber) 回合 · 疆域：\(slot.controlledNodes)/\(GameConstants.campaignNodeCount) · 胜场：\(slot.totalBattlesWon) · 歼敌：\(slot.totalEnemiesDefeated) · 时间：\(slot.updatedAtIso)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ImperialPalette.parchmentMuted)
                }
            }

            Spacer()

            if slot.slotIndex > 0 {
                Button(slot.isEmpty ? "保存至此" : "覆盖保存") {
                    BattleAudioEngine.shared.play(.forgeClang, volumeScale: 0.65)
                    selectedSlotIndex = slot.slotIndex
                    router.saveCurrentCampaignSnapshot(toSlot: slot.slotIndex, customTitle: customArchiveTitle)
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
            }

            if !slot.isEmpty {
                Button("读取执政 ›") {
                    BattleAudioEngine.shared.play(.warHorn, volumeScale: 0.75)
                    selectedSlotIndex = slot.slotIndex
                    _ = router.loadCampaignFromSlot(slot.slotIndex)
                }
                .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))

                Button("清空") {
                    BattleAudioEngine.shared.play(.uiClick)
                    router.deleteSaveSlot(slot.slotIndex)
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? ImperialPalette.obsidianElevated : ImperialPalette.obsidianCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    isSelected ? ImperialPalette.imperialGoldBright : ImperialPalette.bronzeBorder.opacity(0.38),
                    lineWidth: isSelected ? 1.5 : 1.0
                )
        )
        .onTapGesture {
            selectedSlotIndex = slot.slotIndex
        }
    }
}
