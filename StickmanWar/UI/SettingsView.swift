import SwiftUI

/// 核心路由 7：macOS 原生游戏偏好设置与帝国双视角键鼠操作宝典（支持即时多声道合成音效试听与实时音量同步）
public struct SettingsView: View {
    @Bindable var router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button("‹ 返回上一页") {
                    syncAudioVolume()
                    router.persistUserSettings()
                    BattleAudioEngine.shared.play(.uiClick)
                    router.goBack()
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                Image(systemName: "gearshape.2.fill")
                    .font(.title3)
                    .foregroundStyle(ImperialPalette.imperialGoldBright)
                Text("帝国军务设置与 macOS 键鼠/触控板操控宝典")
                    .font(.title3.bold())
                    .foregroundStyle(ImperialPalette.parchmentText)

                Spacer()

                Button("恢复默认设置") {
                    router.resetUserSettingsToDefaults()
                    syncAudioVolume()
                    BattleAudioEngine.shared.play(.uiClick)
                }
                .buttonStyle(ImperialBronzeButtonStyle(isCompact: true))

                Button("保存偏好设置") {
                    syncAudioVolume()
                    router.persistUserSettings()
                    BattleAudioEngine.shared.play(.forgeClang, volumeScale: 0.7)
                }
                .buttonStyle(ImperialCrimsonButtonStyle(isCompact: true))
            }

            HSplitView {
                // 左栏：显示帧率、Retina LOD、多声道物理建模音效引擎与镜头灵敏度
                VStack(alignment: .leading, spacing: 14) {
                    ImperialPanel(padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Retina 渲染帧率与战场显示偏好")
                                .font(.subheadline.bold())
                                .foregroundStyle(ImperialPalette.imperialGold)

                            Picker("目标渲染帧率", selection: $router.userSettings.targetFps) {
                                Text("60 FPS（Apple Silicon 推荐满帧丝滑档）").tag(60)
                                Text("30 FPS（移动办公低功耗续航档）").tag(30)
                            }

                            Picker("窗口外观基调", selection: $router.userSettings.appearance) {
                                ForEach(GameUserSettings.AppearancePreference.allCases) { pref in
                                    Text(pref.displayName).tag(pref)
                                }
                            }

                            Toggle("启用鸟瞰远景智能 LOD（缩放 < 0.60x 自动精简次级骨骼以保障百人会战满帧）", isOn: $router.userSettings.enableFarLod)
                                .foregroundStyle(ImperialPalette.parchmentText)

                            Toggle("显示战场暴击、冲锋破甲与重箭贯穿飘字", isOn: $router.userSettings.showDamageNumbers)
                                .foregroundStyle(ImperialPalette.parchmentText)
                        }
                    }

                    ImperialPanel(padding: 14) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text("多声道物理合成音效与镜头推镜灵敏度")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(ImperialPalette.imperialGold)
                                Spacer()
                                Button("🥁 试听铜角战鼓") {
                                    syncAudioVolume()
                                    BattleAudioEngine.shared.play(.warHorn)
                                }
                                .buttonStyle(ImperialBronzeButtonStyle(isHighlighted: true, isCompact: true))
                            }

                            HStack {
                                Text("主音量 \(Int(router.userSettings.masterVolume * 100))%")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(ImperialPalette.parchmentText)
                                    .frame(width: 135, alignment: .leading)
                                Slider(value: $router.userSettings.masterVolume, in: 0.0...1.0)
                                    .onChange(of: router.userSettings.masterVolume) { _, _ in
                                        syncAudioVolume()
                                    }
                            }
                            HStack {
                                Text("金铁战鼓音效 \(Int(router.userSettings.sfxVolume * 100))%")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(ImperialPalette.parchmentText)
                                    .frame(width: 135, alignment: .leading)
                                Slider(value: $router.userSettings.sfxVolume, in: 0.0...1.0)
                                    .onChange(of: router.userSettings.sfxVolume) { _, _ in
                                        syncAudioVolume()
                                    }
                            }
                            HStack {
                                Text("镜头平移速度 \(Int(router.userSettings.cameraEdgePanSpeed))")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(ImperialPalette.parchmentText)
                                    .frame(width: 135, alignment: .leading)
                                Slider(value: $router.userSettings.cameraEdgePanSpeed, in: 240.0...960.0, step: 20.0)
                            }
                            Toggle("反转鼠标滚轮缩放方向", isOn: $router.userSettings.invertScrollZoom)
                                .foregroundStyle(ImperialPalette.parchmentText)
                            Toggle("RTS 模式下启用窗口边缘光标自动推镜", isOn: $router.userSettings.enableEdgeCursorPan)
                                .foregroundStyle(ImperialPalette.parchmentText)
                        }
                    }

                    Text(router.bannerMessage)
                        .font(.footnote)
                        .foregroundStyle(ImperialPalette.parchmentMuted)

                    Spacer()
                }
                .padding(.trailing, 12)
                .frame(minWidth: 440, maxWidth: .infinity)

                // 右栏：macOS 专属键鼠与触控板快捷键总表
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ImperialPanel(padding: 14) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("一、RTS 帝国统帅视角（致敬《指尖帝国》×《罗马全面战争》）")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(ImperialPalette.imperialGold)
                                keyRow("左键点选 / 拖拽框选", "点选单队 / 矩形框选多支分队；双击全选同兵种；Shift 加选；⌘A 全选主力")
                                keyRow("右键点击 / 右键拖拽拉线", "右键点地机动/点敌集火；按住右键横向拖拽可自定义排兵战线宽度与朝向！")
                                keyRow("数字键 1 / 2 / 3 / 4 / 5", "五大古战阵：方阵 / 雁行阵 / 锥形冲锋阵 / 环形铁桶阵 / 罗马龟甲阵(85%挡箭)")
                                keyRow("帝国营建 & 时代 I~IV", "底部控制台建造民居/农庄/兵营/靶场/马厩/铁匠铺/器械所/箭塔，攀升四大时代")
                                keyRow("Shift+点击募兵 / 句号 [.]", "按住 Shift 点击兵种卡一次连募 5 队；按 [.] 键镜头瞬间定位空闲辎重民夫")
                                keyRow("Q / W / E / R / F", "核心战术军令：稳步推进 / 原地死守 / 全军冲锋 / 交替撤退 / 侧翼包抄")
                                keyRow("G / Z / X / C / B", "高阶奇谋：钳形合围 / 诈败诱敌 / 密林设伏 / 奇袭断粮 / [B] 鸣响本阵警钟")
                                keyRow("Ctrl+1~6 / F1~F6 / Space", "编组与快速选定六路军团；[Space] 战术暂停从容排兵布阵")
                            }
                        }

                        ImperialPanel(padding: 14) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("二、亲自上阵 · 主帅英雄无双模式（按 [Tab] 无缝切换）")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(ImperialPalette.imperialGold)
                                keyRow("W / A / S / D 或 方向键", "控制主帅八方向走位（镜头平滑跟随主帅并随准星微前瞻）")
                                keyRow("鼠标左键点击 / 长按", "佩刀 120° 挥砍 / 大枪 2.2× 反骑穿刺 / 硬弓长按 0.9s 满蓄力重箭贯穿")
                                keyRow("鼠标右键举盾 / 弹反", "举盾减伤 80%，起盾前 0.25s 精准格挡触发金铁剑鸣并震晕周围近敌 1.5s！")
                                keyRow("数字键 1 / 2 / 3", "零损耗切换随身三兵刃：统帅佩刀 / 破阵大枪 / 百石硬弓（近大营自动补箭）")
                                keyRow("Space / E / R", "[Space] 破阵突击撞飞敌群 · [E] 铁壁横戈反弹箭矢 · [R] 三军战吼唤醒白旗溃兵")
                            }
                        }
                    }
                    .padding(.leading, 12)
                }
                .frame(minWidth: 470, maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(ImperialPalette.obsidianDeep)
        .onAppear {
            syncAudioVolume()
        }
    }

    private func syncAudioVolume() {
        let combined = Float(router.userSettings.masterVolume * router.userSettings.sfxVolume)
        BattleAudioEngine.shared.masterVolume = combined
    }

    private func keyRow(_ keyLabel: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(keyLabel)
                .font(.caption.monospaced().bold())
                .frame(width: 195, alignment: .leading)
                .foregroundStyle(ImperialPalette.imperialGoldBright)
            Text(desc)
                .font(.caption)
                .foregroundStyle(ImperialPalette.parchmentMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
