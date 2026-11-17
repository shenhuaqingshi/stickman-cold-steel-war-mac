# 火柴人冷兵器大战 macOS 原生版（Stickman Cold Steel War for macOS）

一款面向 **macOS 14 Sonoma+（Apple Silicon 原生优先）** 的纯单机离线冷兵器战争策略动作游戏，基于 **Swift 6 + SwiftUI + SpriteKit（Xcode 16）** 原生开发（零 Electron / Web 套壳）。

玩家作为一军统帅，既可在 **4800×2400（攻城战 5600×2600）宏大战场**上框选军团、排兵布阵、调度前锋与两翼包抄合围、维护粮道与攻城重器，也可随时按 `Tab` 一键切换**主帅英雄模式**（`WASD` 走位 + 鼠标瞄准劈砍/格挡/狙杀）亲率亲卫冲阵斩将；并在 **8 大地理板块、40 座城池雄关、78 条道路**组成的战略大地图上，与其余 **7 大非对称势力**展开攻伐、结盟、通商、背盟与媾和博弈。

> 姊妹仓库（华为鸿蒙平板版 HarmonyOS NEXT）：[stickman-cold-steel-war](https://github.com/shenhuaqingshi/stickman-cold-steel-war)

---

## 重要说明（开发环境限制声明）

> **注意：当前代码编写所处的 Linux 云端主机未安装 macOS 系统与 Xcode 16 / Swift macOS SDK 工具链，因此无法在本机执行 `xcodebuild` 编译、运行 XCTest 或直接导出 `.app` 应用包。**
>
> 本仓库严格遵循 **Xcode 16 + Swift 6 严格并发模式 + SwiftUI + SpriteKit** 标准工程结构编写，采用 Ad-Hoc 本地签名配置（无需付费 Apple Developer 账号即可在任意 Mac 上直接编译运行）。请按下方指南在安装了 Xcode 16+ 的 Mac 电脑上打开、运行、测试与打包。

---

## 核心玩法与特性

- **真实冷兵器大战（拒绝静态摆拍）**：刀盾互砍、长枪拒马、弓弩抛射、重骑冲阵、巨斧破甲、投石车轰击；火柴人士兵具备挥砍、格挡、受击硬直、倒地与溃逃骨骼动作反馈。
- **高复杂度战术博弈**：支持包抄、合围、钳形夹击、侧翼迂回、正面佯攻、诈败诱敌、林地伏击、断粮道与夜袭；侧背受击承受额外伤害与士气惩罚，被四面合围的部队将触发恐慌溃散。
- **双视角无缝切换（RTS 统帅 <-> 主帅亲征）**：
  - **统帅上帝视角**：鼠标左键框选/点选军团，右键下达移动/攻击/包抄指令，数字键切换方阵/雁行/锥形/圆阵，滚轮与触控板无级缩放漫游战场。
  - **主帅英雄模式**：`Tab` 键瞬间附身主帅，`WASD` 移动、鼠标瞄准、左键挥砍/射击、右键举盾格挡、`Space` 突进冲锋、`1/2/3` 切换佩刀/长枪/强弓与战吼鼓舞；主帅阵亡将引发全军士气雪崩。
- **8 大非对称强权势力 & 16 种特色兵种**：炎龙帝国、苍狼汗国、铁鹰王国、沙漠商盟、霜原熊族、雾林猎手、玄甲重骑军团、血月祭司团——各自拥有专属王牌兵种（共 8 通用 + 8 专属）、科技分支、旗帜配色与 AI 战略性格。
- **40 城关战略大地图与深度外交**：8 大区域、40 座城池关隘与 78 条补给干道（BFS 实时粮道判定，断粮惩罚士气与战力）；支持关系值（-100 ~ +100）、攻守同盟、停火媾和（赔款/割城/纳贡/停战年限量化谈判）、互不侵犯、通商与背盟信誉惩罚，AI 势力之间亦会合纵连横。
- **macOS 原生桌面体验**：AppKit 原生菜单栏与快捷键、窗口自由缩放与原生全屏、Retina 高分屏渲染、深色/浅色外观适配；SpriteKit 视口裁剪 + 对象池批量绘制，支撑同屏 300~500 名火柴人流畅交战。

---

## 项目工程目录结构

```text
stickman-war-mac/
├── StickmanWar.xcodeproj/             # 标准 Xcode 16 工程文件（含主应用与 XCTest Target）
├── StickmanWar/
│   ├── App/                           # macOS App 入口、AppKit 菜单栏命令与全局窗口路由
│   ├── Model/                         # 纯 Swift 6 领域模型、枚举契约与状态结构（与 UI 解耦）
│   ├── Config/                        # 16 兵种、8 大势力、40 城关与 78 道路静态配置单点真相源
│   ├── Core/                          # 战斗模拟、空间网格寻敌、三层 AI 战术、BFS 粮道与外交纯逻辑引擎
│   ├── Render/                        # SpriteKit 大战场场景、火柴人骨骼动作池、投射物与视口裁剪渲染
│   ├── UI/                            # SwiftUI 7 大核心视图（主菜单/战役地图/整军/战场 HUD/结算/存档/设置）
│   ├── Storage/                       # Application Support 本地 JSON 存档读写与战绩统计持久化
│   ├── Assets.xcassets/               # 原生应用图标与主题色彩资源
│   └── StickmanWar.entitlements       # macOS App Sandbox 本地沙箱权限声明（零网络权限）
├── StickmanWarTests/                  # XCTest 单元测试套件（破甲公式/士气迟滞/粮道连通/外交媾和/图对称性）
├── MAC_BRIEF.md                       # macOS 原生版立项需求与打磨规范
├── DESIGN.md                          # 游戏总体设计文档（移植自鸿蒙版并标注 macOS 键鼠与渲染架构差异）
└── PROGRESS.md                        # 阶段开发进度与多轮自我审查重构台账
```

---

## 键鼠与触控板操作一览

| 模式 | 按键 / 手势 | 功能说明 |
| :--- | :--- | :--- |
| **全局通用** | `Tab` | 一键切换 **RTS 统帅视角** / **主帅英雄亲征模式** |
| **全局通用** | `Space`（RTS 模式）/ `P` | 战场战术暂停 / 继续 |
| **全局通用** | `Esc` | 呼出战局暂停菜单 / 返回上一级 |
| **RTS 统帅视角** | 鼠标左键点选 / 拖拽框选 | 选中单个或多个己方军团 |
| **RTS 统帅视角** | 鼠标右键点击地面 / 敌军 | 下达行军、正面进攻或侧翼包抄指令 |
| **RTS 统帅视角** | 滚轮 / 触控板双指捏合与滑动 | 大地图与战场无级缩放、视野平移漫游 |
| **RTS 统帅视角** | `1` / `2` / `3` / `4` | 切换编队阵型（方阵 / 雁行 / 锥形 / 圆阵） |
| **RTS 统帅视角** | `Q` / `W` / `E` / `R` | 下达战术姿态（前进 / 坚守 / 全军冲锋 / 交替撤退） |
| **主帅英雄模式** | `W` `A` `S` `D` / 方向键 | 控制主帅走位移动 |
| **主帅英雄模式** | 鼠标移动 + 左键 / 右键 | 鼠标朝向瞄准；左键挥砍/射击，右键举盾格挡 |
| **主帅英雄模式** | `Space` / `1` `2` `3` | `Space` 突进冲锋；`1/2/3` 切换佩刀/长枪/强弓及战吼技能 |

---

## 在 Mac 上打开、运行与测试步骤

### 1. 环境要求
- **硬件**：Apple Silicon Mac（M1 / M2 / M3 / M4 系列推荐，同时兼容 Intel Mac）
- **系统**：macOS 14.0 Sonoma 或更高版本
- **工具**：Xcode 16.0 或更高版本

### 2. 打开并运行项目
1. 克隆本仓库到本地 Mac：
   ```bash
   git clone https://github.com/shenhuaqingshi/stickman-cold-steel-war-mac.git
   cd stickman-war-mac
   ```
   *(若本地目录名为 `stickman-cold-steel-war-mac`，直接进入该目录即可)*
2. 双击打开 `StickmanWar.xcodeproj`（或执行 `open StickmanWar.xcodeproj`）。
3. 在 Xcode 顶部 Scheme 选择 **`StickmanWar`**，运行目标选择 **`My Mac`**。
4. 按下 **`Cmd + R`** 即可直接编译并启动原生 macOS 游戏窗口（工程默认配置 `Sign to Run Locally` Ad-Hoc 签名，无需配置付费开发者证书）。

### 3. 运行 XCTest 单元测试
- **Xcode 内运行**：按下 **`Cmd + U`**，自动编译并执行 `StickmanWarTests` 全部数值平衡、破甲伤害、士气状态机、40 节点地图拓扑与外交媾和测试用例。
- **命令行运行**：
  ```bash
  xcodebuild test \
    -project StickmanWar.xcodeproj \
    -scheme StickmanWar \
    -destination 'platform=macOS'
  ```

---

## 导出独立 `.app` 应用包步骤

### 方式一：通过 Xcode 图形界面导出
1. 在 Xcode 顶部菜单选择 **Product -> Archive**。
2. 构建完成后会自动弹出 **Organizer** 窗口，选中最新 Archive 记录并点击 **Distribute App**。
3. 选择 **Copy App**（本地免签分发）或 **Direct Distribution**（Developer ID 公证分发），即可导出独立的 `StickmanWar.app`，拖入 `/Applications` 即可双击游玩。

### 方式二：通过命令行一键构建 Release 版 `.app`
```bash
xcodebuild -project StickmanWar.xcodeproj \
  -scheme StickmanWar \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  build
```
构建完成后，独立应用包位于：
`build/Build/Products/Release/StickmanWar.app`
