import SwiftUI

/// 核心路由 6：本地离线军档与战绩统计页
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
                    router.goBack()
                }
                .buttonStyle(.bordered)

                Text("本地军档管理与战绩统计")
                    .font(.title3.bold())

                Spacer()

                Button("从外部文件导入军档… (⌘O)") {
                    router.importArchiveFromFinder(intoSlot: max(1, selectedSlotIndex))
                }
                .buttonStyle(.bordered)

                Button("导出选中槽位备份文件… (⇧⌘S)") {
                    router.exportArchiveToFinder(slotIndex: selectedSlotIndex)
                }
                .buttonStyle(.bordered)
            }

            // 当前内存活跃战役概览与快捷命名保存条
            GroupBox("当前活跃战役会话（可直接写入任意手动槽位 #1 ~ #5）") {
                HStack(spacing: 12) {
                    Text("当前统帅：【\(activeFactionName)】 · 第 \(router.campaignEngine.worldState.turnNumber) 回合 · 控制城关 \(activeControlledCount)/\(GameConstants.campaignNodeCount) · 胜 \(router.campaignEngine.worldState.totalBattlesWon) 场")
                        .font(.callout.monospacedDigit())

                    Spacer()

                    TextField("可选自定义军档标题…", text: $customArchiveTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    Button("保存至槽位 #\(max(1, selectedSlotIndex))") {
                        let targetSlot = max(1, selectedSlotIndex)
                        router.saveCurrentCampaignSnapshot(toSlot: targetSlot, customTitle: customArchiveTitle)
                        customArchiveTitle = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(4)
            }

            GroupBox("macOS Application Support 本地离线存储路径") {
                HStack {
                    Text(router.storageManager.savesDirectoryURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Text("原子写入保护 · 含完整 40 城关与外交状态 · 零联网依赖")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                .padding(4)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(router.saveSlots) { slot in
                        saveSlotRow(slot)
                    }
                }
            }

            Text(router.bannerMessage)
                .font(.footnote)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.10)))
        }
        .padding(20)
        .onAppear {
            router.reloadSlots()
        }
    }

    private func saveSlotRow(_ slot: SaveSlotSummary) -> some View {
        let isSelected = (slot.slotIndex == selectedSlotIndex)
        let factionName = FactionConfig.config(for: slot.factionId)?.name ?? "无"
        let hasFullWorld = router.storageManager.hasCampaignWorldSnapshot(at: slot.slotIndex)

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(slot.slotIndex == 0 ? "[自动军档 #0]" : "[手动槽位 #\(slot.slotIndex)]")
                        .font(.subheadline.monospaced().bold())
                        .foregroundStyle(slot.slotIndex == 0 ? .cyan : .primary)
                    Text(slot.title)
                        .font(.headline)
                    if !slot.isEmpty && hasFullWorld {
                        Text("完整快照")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.20)))
                    }
                }

                if slot.isEmpty {
                    Text("空槽位 —— 点击右侧【覆盖保存】可将当前 40 城关战役进度持久化至此槽位")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("势力：\(factionName) · 第 \(slot.turnNumber) 回合 · 城关：\(slot.controlledNodes)/\(GameConstants.campaignNodeCount) · 胜场：\(slot.totalBattlesWon) · 歼敌：\(slot.totalEnemiesDefeated) · 时间：\(slot.updatedAtIso)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if slot.slotIndex > 0 {
                Button(slot.isEmpty ? "保存至此" : "覆盖保存") {
                    selectedSlotIndex = slot.slotIndex
                    router.saveCurrentCampaignSnapshot(toSlot: slot.slotIndex, customTitle: customArchiveTitle)
                }
                .buttonStyle(.bordered)
            }

            if !slot.isEmpty {
                Button("读取进入大地图") {
                    selectedSlotIndex = slot.slotIndex
                    _ = router.loadCampaignFromSlot(slot.slotIndex)
                }
                .buttonStyle(.borderedProminent)

                Button("删除") {
                    router.deleteSaveSlot(slot.slotIndex)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: isSelected ? 1.5 : 1))
        .onTapGesture {
            selectedSlotIndex = slot.slotIndex
        }
    }
}
