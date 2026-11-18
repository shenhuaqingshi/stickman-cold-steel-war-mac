import SwiftUI

/// 核心路由 7：macOS 原生游戏设置与双视角键鼠/触控板操作总表页（所有设置项真实持久化并即时作用于窗口外观与 SpriteKit 战场）
public struct SettingsView: View {
    @Bindable var router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button("‹ 返回上一页") {
                    router.persistUserSettings()
                    router.goBack()
                }
                .buttonStyle(.bordered)

                Text("游戏偏好设置与 macOS 键鼠/触控板操控指南")
                    .font(.title3.bold())

                Spacer()

                Button("恢复默认设置") {
                    router.resetUserSettingsToDefaults()
                }
                .buttonStyle(.bordered)

                Button("立即保存设置") {
                    router.persistUserSettings()
                }
                .buttonStyle(.borderedProminent)
            }

            HSplitView {
                // 左栏：显示帧率、远景 LOD、战斗飘字、边缘推镜与音量灵敏度配置
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("渲染帧率、Retina 显示与外观主题") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("目标渲染帧率", selection: $router.userSettings.targetFps) {
                                Text("60 FPS（Apple Silicon 推荐满帧丝滑档）").tag(60)
                                Text("30 FPS（移动办公续航低功耗档）").tag(30)
                            }

                            Picker("界面色彩外观", selection: $router.userSettings.appearance) {
                                ForEach(GameUserSettings.AppearancePreference.allCases) { pref in
                                    Text(pref.displayName).tag(pref)
                                }
                            }

                            Toggle("启用全局鸟瞰远景简化 LOD（缩放 < 0.60x 时自动精简次级肢体以保障百人合批帧率）", isOn: $router.userSettings.enableFarLod)

                            Toggle("显示战场暴击与高额破甲伤害飘字", isOn: $router.userSettings.showDamageNumbers)
                        }
                        .padding(8)
                    }

                    GroupBox("战场音效与键鼠镜头操控灵敏度") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("主音量 \(Int(router.userSettings.masterVolume * 100))%")
                                    .frame(width: 130, alignment: .leading)
                                Slider(value: $router.userSettings.masterVolume, in: 0.0...1.0)
                            }
                            HStack {
                                Text("金铁交鸣音效 \(Int(router.userSettings.sfxVolume * 100))%")
                                    .frame(width: 130, alignment: .leading)
                                Slider(value: $router.userSettings.sfxVolume, in: 0.0...1.0)
                            }
                            HStack {
                                Text("镜头平移速度 \(Int(router.userSettings.cameraEdgePanSpeed))")
                                    .frame(width: 130, alignment: .leading)
                                Slider(value: $router.userSettings.cameraEdgePanSpeed, in: 240.0...960.0, step: 20.0)
                            }
                            Toggle("反转鼠标滚轮缩放方向", isOn: $router.userSettings.invertScrollZoom)
                            Toggle("RTS 模式下启用窗口边缘光标自动推镜", isOn: $router.userSettings.enableEdgeCursorPan)
                        }
                        .padding(8)
                    }

                    Text(router.bannerMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.trailing, 12)
                .frame(minWidth: 430, maxWidth: .infinity)

                // 右栏：macOS 专属键鼠与触控板快捷键对照表（替代移动端虚拟摇杆）
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupBox("一、RTS 统帅上帝视角（键鼠 & 触控板）") {
                            VStack(alignment: .leading, spacing: 6) {
                                keyRow("左键点选 / 拖拽框选", "点选单队 / 矩形框选多支分队；双击全选同兵种；Shift 加选；~ 或 ⌘A 全选主力")
                                keyRow("右键情境下令", "点空地保持阵型机动；点敌军/城门发起进攻；Shift+右键追加迂回路径点")
                                keyRow("双指滑动 / 中键或⌥拖拽 / 方向键", "平滑平移 4800×2400 战场与 3600×2400 战略大地图（保留 Q/W/E 给军令零冲突）")
                                keyRow("双指捏合 / ⌘+滚轮 / 外接滚轮", "连续缩放战场与战略大地图（<0.60x 自动切换远景 LOD）")
                                keyRow("数字键 1 / 2 / 3 / 4", "切换选中部队阵型：方阵 / 雁行阵 / 锥形阵 / 圆阵")
                                keyRow("Q / W / E / R / F", "核心战术军令：稳步推进 / 原地坚守 / 全军冲锋 / 交替撤退 / 侧翼包抄")
                                keyRow("G / Z / X / C", "高阶奇谋军令：钳形合围 / 诈败诱敌 / 密林设伏 / 奇袭断粮")
                                keyRow("Ctrl + 1~6 / F1~F6", "绑定 / 快速选中最多 6 支作战军团（连按两次 F1~F6 镜头居中该军团）")
                                keyRow("B 键", "鸣响/解除本阵警钟（辎重工兵紧急退入大营射击孔协防敌骑偷家）")
                                keyRow("空格键 Space / P 键", "战术暂停（允许在暂停状态下从容框选多线军团预下达包抄指令）")
                                keyRow("Tab 键 / Esc 键", "Tab 无缝切换【RTS 视角 <-> 主帅亲自上阵】（冷却 1.5s）；Esc 呼出战场军务菜单")
                            }
                            .padding(6)
                        }

                        GroupBox("二、亲自上阵 · 主帅英雄模式（摒弃手机虚拟摇杆，纯正 Mac 动作手感）") {
                            VStack(alignment: .leading, spacing: 6) {
                                keyRow("W / A / S / D 或 方向键", "控制主帅八方向走位（镜头平滑跟随主帅并随准星微前瞻）")
                                keyRow("鼠标光标实时指向", "实时控制佩刀 120° 扇面、破阵大枪 68px 突刺轴线与百石硬弓准星")
                                keyRow("鼠标左键点击 / 长按", "佩刀挥砍 / 大枪反骑穿刺 / 硬弓长按 0.9s 满蓄力重箭贯穿 2 人")
                                keyRow("鼠标右键按住", "佩刀举盾减伤 80%（起盾前 0.25s 精准弹反震晕近敌 1.5s！）/ 取消拉弓")
                                keyRow("数字键 1 / 2 / 3", "零损耗切换三兵刃：统帅佩刀 / 破阵大枪 / 百石硬弓（24支箭袋上限，近营补满）")
                                keyRow("空格键 Space", "战技 1【破阵突击】（CD 10s，猛冲 160px 撞飞敌步兵、冲锋闪避一体）")
                                keyRow("E 键（或数字键 4）", "战技 2【铁壁横戈】（CD 8s，2.0s 反弹正面箭矢并收招旋身横扫）")
                                keyRow("R 键（或数字键 5）", "战技 3【三军战吼】（CD 22s，320px 友军士气+18 当场唤醒白旗溃军！）")
                                keyRow("P 键 / Esc 键", "英雄模式下战术暂停 / 战场军务菜单")
                            }
                            .padding(6)
                        }
                    }
                    .padding(.leading, 12)
                }
                .frame(minWidth: 460, maxWidth: .infinity)
            }
        }
        .padding(20)
    }

    private func keyRow(_ keyLabel: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(keyLabel)
                .font(.caption.monospaced().bold())
                .frame(width: 195, alignment: .leading)
                .foregroundStyle(.primary)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
