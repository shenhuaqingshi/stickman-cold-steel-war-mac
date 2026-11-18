# 火柴人冷兵器大战 macOS 原生版（Stickman Cold Steel War for macOS）

一款面向 **macOS 14 Sonoma+（Apple Silicon 优先）** 的纯原生单机冷兵器战争策略动作游戏。采用 **Swift 6 + SwiftUI + SpriteKit + AppKit** 构建，严禁 Electron 或 Web 套壳，零联网依赖、零付费 SDK。

玩家化身冷兵器时代的一军统帅：既可在 **4800×2400（攻城 5600×2600）宏大战场**上用键鼠框选百人方阵、调度辎重粮草、实施两翼钳形包抄，也可随时按下 `Tab` 键**提刀亲自上阵**（`WASD` 走位 + 鼠标瞄准挥砍/格挡弹反/蓄力狙杀）；并在 **8 大区域、40 座城关、78 条双向粮道**组成的战略大地图上，与其余 **7 大非对称势力**展开攻伐、结盟、通商、背盟与媾和博弈。

---

## 重要说明：当前 Linux 开发环境限制声明

> **诚实声明：当前编写代码的这台 Linux 机器没有 macOS 操作系统，也没有安装 Xcode / Apple macOS SDK 工具链，因此无法在本机编译 SwiftUI/SpriteKit 代码、无法运行 XCTest，也无法直接打包生成 `.app` 产物（绝不伪造编译结果）。**
>
> 本工程已严格按照 **Xcode 16 + Swift 6.0（`SWIFT_STRICT_CONCURRENCY = complete`）+ macOS 14.0+ (`arm64`)** 标准工程规范编写并完成了全套引用 ID、路径对称性与静态拓扑核验。请将本目录拷贝或克隆至装有 **macOS 14+ 与 Xcode 16+** 的 Apple Silicon Mac 电脑上，按下方步骤打开、运行、执行单元测试及打包 `.app`。

---

## 工程目录分层结构

```text
stickman-war-mac/
├── MAC_BRIEF.md                                  # macOS 原生版立项开发 Brief
├── DESIGN.md                                     # 游戏总体设计文档（含 macOS 键鼠/SpriteKit/存档差异与 40 节点校准说明）
├── PROGRESS.md                                   # 阶段开发进度与多轮自我审查重构优化台账
├── README.md                                     # Mac 打开、运行、测试、打包指南与已知限制说明
├── project.yml                                   # 与 .xcodeproj 1:1 同步的可选 XcodeGen 规格文件
├── StickmanWar.xcodeproj/                        # 标准 Xcode 16 工程（开箱即用，无需额外安装第三方工具）
│   ├── project.pbxproj                           # App 主目标与 StickmanWarTests 测试目标构建配置
│   └── xcshareddata/xcschemes/StickmanWar.xcscheme
├── StickmanWar/                                  # 主应用 Target（Swift 6 + SwiftUI + SpriteKit + AppKit）
│   ├── StickmanWar.entitlements                  # Hardened Runtime 与离线单机沙箱权限（无网络权限）
│   ├── Assets.xcassets/                          # macOS 全尺寸 AppIcon 与主题色资源目录
│   ├── App/                                      # 应用入口、AppDelegate、AppKit 原生菜单栏、7 页全流程状态路由器
│   ├── Model/                                    # 纯 Swift Sendable 游戏常量、枚举与数据契约（与 UI 解耦）
│   ├── Config/                                   # 16 兵种、8 大势力、40 城关 / 78 道路静态单点真相源（与鸿蒙版零差异对齐）
│   ├── Core/                                     # 战斗 / AI / 战役 / 外交四大纯逻辑引擎（支持独立 XCTest 单测）
│   ├── Render/                                   # SpriteKit 大战场 CoreGraphics 预烘焙图集、600 士兵池与键鼠/触控板宿主
│   ├── UI/                                       # SwiftUI 7 个全流程打通页面（主菜单/大地图/整军/战场/结算/存档/设置）
│   └── Storage/                                  # Application Support 原子 JSON 存档与 NSSavePanel 完整军档包导入导出
└── StickmanWarTests/                             # XCTest 单元测试 Target（共 6 套测试套件）
    ├── StickmanWarSkeletonTests.swift            # 尺寸、8 势力、16 兵种、40 节点 / 78 道路精确拓扑与离线存档单测
    ├── CombatEngineTests.swift                   # 双曲护甲、反骑停马、八象限合围、主帅 0.25s 弹反与攻帅闭环、断粮单测
    ├── AIEngineTests.swift                       # L2 战场黑板（反风筝/预备队/攻守城三段式）与 L1 大地图效用 AI 单测
    ├── CampaignEngineTests.swift                 # BFS 粮道跳数、断粮 8% 饥疲减员、募兵科技、围点打援与存档回环单测
    ├── DiplomacyEngineTests.swift                # 背盟雪崩、双重同盟防御豁免、媾和三档反报价与孤城防灭国单测
    └── FullFlowIntegrationTests.swift            # 7 大页面路由全链路打通集成单测（开局->大地图->整军->实战->结算->存档）
```

---

## 在 Mac 上打开、运行、测试与打包 `.app` 步骤

### 1. 环境准备
- 硬件建议：搭载 Apple Silicon（M1 / M2 / M3 / M4，`arm64`）的 Mac 电脑（若需在 Intel Mac 编译，可在 Xcode `Build Settings -> Architectures` 将 `arm64` 改为 `$(ARCHS_STANDARD)`）。
- 系统与工具：**macOS 14.0 Sonoma** 或更高版本，安装 **Xcode 16.0** 或更高版本。
- 无需付费开发者账号：工程默认已配置 `CODE_SIGN_IDENTITY = "-"`（**Sign to Run Locally** 本地自签名），无需配置 `$99` 证书即可直接编译运行。

### 2. 在 Xcode 16 中打开与运行（GUI 方式）
1. 在终端进入本工程目录并直接打开标准 Xcode 工程：
   ```bash
   cd ~/workspace/stickman-war-mac
   open StickmanWar.xcodeproj
   ```
2. 在 Xcode 顶部工具栏确认 Scheme 选择为 **`StickmanWar`**，运行目标选择 **`My Mac`**。
3. 按下快捷键 **`⌘R`**（或点击左上角 **Run** 三角按钮）编译并启动游戏：
   - 验证顶部 **macOS 原生菜单栏**（`StickmanWar -> 游戏设置… ⌘,`、`文件`、`视图`、`帮助`）正常响应；
   - 验证主菜单、40 节点 / 78 道路战略大地图缩放漫游与小地图、战前 16 兵种整军检阅、SpriteKit 4800×2400 战场视口框选/右键/捏合缩放、战后结算、本地存档与设置共 **7 个核心页面路由**全部畅通。

### 3. 运行 XCTest 单元测试
- **方式一（Xcode GUI）**：在 Xcode 中按下 **`⌘U`**（`Product -> Test`），运行 `StickmanWarTests` 套件，查看测试导航栏全部绿灯通过。
- **方式二（终端命令行 `xcodebuild`）**：
  ```bash
  xcodebuild test \
    -project StickmanWar.xcodeproj \
    -scheme StickmanWar \
    -destination 'platform=macOS,arch=arm64'
  ```

### 4. 打包独立 `.app` 应用程序
- **方式一（Xcode Organizer 归档导出）**：
  1. 在 Xcode 顶部菜单选择 **`Product -> Archive`**；
  2. 归档完成后自动弹出 Organizer 窗口，选中刚生成的 Archive，点击右侧 **`Distribute App`**；
  3. 若在本地/内测分发，选择 **`Custom -> Copy App`** 导出独立 `StickmanWar.app`（若拥有 Apple Developer ID 证书并需公证分发，可选择 **`Direct Distribution`** 自动完成 Notarization）。
- **方式二（命令行一键构建 Release 版 `.app`）**：
  ```bash
  xcodebuild build \
    -project StickmanWar.xcodeproj \
    -scheme StickmanWar \
    -configuration Release \
    -derivedDataPath ./build

  # 构建产物路径：
  ls -la ./build/Build/Products/Release/StickmanWar.app
  ```
- *（可选）使用 XcodeGen 重新生成工程*：仓库内同步附带了 `project.yml`，如后续增删大量源文件且安装了 `xcodegen`，可直接运行 `xcodegen generate` 重新生成 `StickmanWar.xcodeproj`。

---

## 本地离线存档位置说明

游戏全程单机离线运行，默认自动与手动存档、用户设置保存在 macOS 标准沙箱应用支持目录下：
- 开启 App Sandbox 时：`~/Library/Containers/com.stickmanwar.macos/Data/Library/Application Support/StickmanColdSteelWar/Saves/`
- 未开启容器重定向时：`~/Library/Application Support/StickmanColdSteelWar/Saves/`
- 玩家亦可在菜单栏选择 **`文件 -> 导出军档备份为文件… (⇧⌘S)`** 或 **`从文件导入军档… (⌘O)`** 通过原生 Finder 对话框自由备份迁移 `.json` 存档。

---

## Mac 专属键鼠与触控板操作速查

- **RTS 统帅视角**：
  - **框选 / 编队**：左键拖拽框选、左键点选、双击同兵种全选、`Shift` 加减选、`Ctrl + 1~6` 编组、`F1~F6` 选编队（双击镜头聚焦）。
  - **上下文指令**：右键地面行军（`Shift + 右键` 连续路径点，最多 4 段）、右键敌军集火、右键资源点派工兵采集。
  - **阵型与战术**：`1~4` 切换横阵 / 密集方阵 / 散兵阵 / 抗骑圆阵；`Q/W/E/R/F/G/Z/X/C` 触发推进、全军冲锋、坚守、后撤、两翼包抄、奇袭断粮、抛射覆盖、诈败诱敌、死战不退；`B` 敲响本阵警钟召回工兵。
  - **镜头与节奏**：鼠标滚轮 / 触控板双指捏合缩放（`0.45x ~ 1.60x`）；双指滑动 / 中键拖拽 / `Option + 左键` / 方向键 / 屏幕边缘推屏漫游；`Space` 或 `P` 战术暂停（暂停期间允许预下达一切阵型与移动指令）。
- **主帅亲征视角（按 `Tab` 无缝切换）**：
  - **移动与瞄准**：`W/A/S/D`（或方向键）八向走位，鼠标实时朝向瞄准。
  - **武器与弹反**：`1` 统帅佩刀（右键按住格挡减伤 80%，起手 `0.25s` 精准弹反震晕近战敌兵 `1.5s`）、`2` 破阵大枪、`3` 百石硬弓（左键按住 `0.9s` 满蓄力高破甲贯射，上限 24 支，回本阵军械架补箭）。
  - **主帅战技**：`Space` 破阵突击、`E` 三军战吼（周围友军 `+20` 士气并唤醒溃兵）、`R` 火矢齐射信标。
- **全局菜单栏快捷键**：`⌘N` 新战役、`⌘S` 快速存档（槽位 `#1`）、`⇧⌘S` 导出完整军档备份、`⌘O` 导入军档、`⌘,` 游戏设置、`⌃⌘F` 全屏切换。

---

## 当前阶段状态与已知限制说明

1. **全流程 7 大页面可玩形态代码与 6 套 XCTest 单测草稿已落盘（停下等待督工检查）**：已完成道路数 `78` 条拍板及与鸿蒙版 40 节点 / 78 道路逐字段零差异对齐、四大纯逻辑核心引擎、CoreGraphics 预烘焙火柴人纹理图集与 600 士兵池化 `BattlefieldSKScene`、7 个 SwiftUI 页面与底层引擎/存档全链路打通及两轮深度自我审查优化。
2. **Linux 环境未实机编译与未跑测声明**：当前开发机为无 macOS / Xcode 工具链的 Linux 环境，全仓 Swift 源码与 6 套 XCTest 单测均为**未编译、未在本机跑过的草稿**，需在装有 macOS 14+ 与 Xcode 16+ 的 Mac 上执行首次编译（`⌘R`）与单元测试（`⌘U` / `xcodebuild test`）验收。
