import Foundation

/// 全局游戏静态常量表（第 1 步：纯静态常量层，与 DESIGN.md 及鸿蒙版数值体系严格一致，不含战斗执行逻辑）
/// 采用无实例枚举命名空间，满足 Swift 6 Strict Concurrency 的 Sendable 全局安全访问要求。
public enum GameConstants: Sendable {
    // MARK: - 一、战场大地图逻辑尺寸（硬性要求 >= 4000×2000）

    /// 标准野战 / 遭遇战 / 护粮战逻辑宽度（px）
    public static let battlefieldWidth: Double = 4800.0
    /// 标准野战 / 遭遇战 / 护粮战逻辑高度（px）
    public static let battlefieldHeight: Double = 2400.0
    /// 大型攻城战逻辑宽度（px）
    public static let siegeBattlefieldWidth: Double = 5600.0
    /// 大型攻城战逻辑高度（px）
    public static let siegeBattlefieldHeight: Double = 2600.0
    /// 两军本阵大营标准水平间距（px）
    public static let baseCampHorizontalSpan: Double = 3800.0
    /// 均匀空间哈希网格单格尺寸（px），4800×2400 划分为 40×20 = 800 桶
    public static let spatialGridCellSize: Double = 120.0
    /// SpriteKit 视口裁剪安全外扩边距（px），防止长枪枪尖或投石弹道边缘闪烁
    public static let viewportCullMargin: Double = 96.0
    /// 常规步兵战争迷雾基础视野半径（px）
    public static let visionRadiusInfantry: Double = 420.0
    /// 游骑兵 / 侦察骑兵基础视野半径（px）
    public static let visionRadiusCavalry: Double = 580.0
    /// 密林内未开火伏兵隐蔽识破距离（px，非雾林猎手势力）
    public static let forestStealthRevealRadius: Double = 140.0
    /// 长枪架枪正面迎击冲锋骑兵时的动能附加破甲率（+30%）
    public static let bracedAntiCavBonusPenetration: Double = 0.30

    // MARK: - 二、战役战略大地图尺寸与拓扑常数（以 DESIGN.md 40 节点 / 78 道路为准）

    /// 战役战略大地图逻辑宽度（px）
    public static let campaignMapWidth: Double = 3600.0
    /// 战役战略大地图逻辑高度（px）
    public static let campaignMapHeight: Double = 2400.0
    /// 战役大地图地理大区数量（8 大势力领地板块）
    public static let campaignRegionCount: Int = 8
    /// 战役大地图每大势力开局均衡城关数
    public static let campaignNodesPerFaction: Int = 5
    /// 战役大地图城池 / 关隘 / 要塞总节点数（8 × 5 = 40 座，以鸿蒙版最新 DESIGN.md 为准）
    public static let campaignNodeCount: Int = 40
    /// 战役大地图无向对称双向道路总数（78 条，无平面交叉悬空飞线）
    public static let campaignRoadCount: Int = 78
    /// 战役大地图最小缩放倍率
    public static let campaignZoomMin: Double = 0.45
    /// 战役大地图最大缩放倍率
    public static let campaignZoomMax: Double = 1.80
    /// 战场镜头最小缩放倍率（全局鸟瞰触发远景 LOD 阈值 0.60x）
    public static let battlefieldZoomMin: Double = 0.40
    /// 战场镜头最大缩放倍率（近景观察拼杀细节）
    public static let battlefieldZoomMax: Double = 1.85
    /// 战场远景简化渲染 LOD 切换缩放阈值
    public static let battlefieldFarLodZoomThreshold: Double = 0.60

    // MARK: - 三、帧率预算、对象池容量与 UI 节流常数

    /// 确定性战斗逻辑步进频率（Hz）
    public static let logicTickHz: Int = 30
    /// 标准渲染目标帧率（FPS，ProMotion 屏幕支持自适应同步）
    public static let renderTargetFps: Int = 60
    /// SwiftUI 顶部资源 / 粮草 / 士气 HUD 状态同步节流频率（Hz，每 250ms 一次防高频重排）
    public static let hudSyncThrottleHz: Int = 4
    /// 单场战斗同屏士兵实体对象池上限
    public static let maxUnitPoolSize: Int = 600
    /// 单场战斗箭矢 / 弩矢 / 巨石投射物对象池上限
    public static let maxProjectilePoolSize: Int = 400
    /// 单场战斗受击火星 / 飘字粒子对象池上限
    public static let maxEffectParticlePoolSize: Int = 300
    /// 战场环形保留倒地遗骸与折断旌旗最大数量
    public static let maxFallenCorpseDecals: Int = 150
    /// 单方标准人口上限
    public static let defaultArmyPopCap: Int = 240
    /// 单方最大可独立编组军团数（Ctrl+1~6 / F1~F6：前锋、左翼、右翼、预备队、攻城群、护粮队）
    public static let maxArmyCorpsGroups: Int = 6
    /// 主帅重击命中卡肉顿帧时长（毫秒）
    public static let heroHitStopMilliseconds: Int = 40

    // MARK: - 四、战场开局资源与大营经济死锁保底

    /// 战场标准初始金币
    public static let battleInitGold: Int = 500
    /// 战场标准初始木材
    public static let battleInitWood: Int = 350
    /// 战场标准初始携行粮草（支撑百人军团约 3.5~4.5 分钟高强度作战）
    public static let battleInitGrain: Double = 1200.0
    /// 本阵大营每秒保底军饷金币产出（防零钱零工兵死锁）
    public static let basePassiveGoldPerSec: Double = 1.2
    /// 本阵大营每秒保底木材产出
    public static let basePassiveWoodPerSec: Double = 0.5
    /// 工兵全灭且金币不足 35 时免费应急征召民夫间隔（秒）
    public static let emergencySapperRespawnSec: Double = 25.0

    // MARK: - 五、双曲护甲、侧背包抄、钳形夹击、合围与半渡而击常数

    /// 双曲护甲减伤常数 K（有效护甲 = 50 时减伤 50%）
    public static let armorHyperbolicConstant: Double = 50.0
    /// 单次命中最低保底伤害（杜绝刮痧免疫死局）
    public static let minimumHitDamage: Double = 2.0
    /// 骑兵 / 突击兵触发冲锋倍率所需直线加速时间（秒）
    public static let chargeWindupSeconds: Double = 2.5
    /// 冲锋首击触发后重整冷却时间（秒）
    public static let chargeCooldownSeconds: Double = 8.0
    /// 侧翼受击伤害倍率（60°~135°）
    public static let flankDamageMultiplier: Double = 1.25
    /// 背击突袭伤害倍率（>135°，且无视正面盾防与架枪）
    public static let rearDamageMultiplier: Double = 1.45
    /// 钳形夹击每秒额外士气流失
    public static let pincerMoraleDrainPerSec: Double = 2.2
    /// 铁桶合围判定所需受敌扇区数（8 象限中至少 5 个扇区受敌且退路受阻）
    public static let encirclementMinOctants: Int = 5
    /// 铁桶合围状态下每秒士气雪崩流失值
    public static let encirclementMoraleDrainPerSec: Double = 4.8
    /// 渡河“半渡而击”（分队 30%~80% 成员涉水首尾脱节时受击）额外易伤倍率
    public static let halfFordVulnerabilityMultiplier: Double = 1.20

    // MARK: - 六、士气迟滞状态机与主帅英雄常数

    /// 分队基础初始士气
    public static let moraleBase: Double = 80.0
    /// 士气满分上限
    public static let moraleMax: Double = 100.0
    /// 高昂士气阈值（>=85 获攻移加成）
    public static let moraleHighThreshold: Double = 85.0
    /// 动摇阈值（<40 攻防下滑并闪黄旗）
    public static let moraleWaveringThreshold: Double = 40.0
    /// 溃逃阈值（<20 脱离指挥举白旗溃退）
    public static let moraleRoutThreshold: Double = 20.0
    /// 重整旗鼓恢复控制阈值（须回升至 >=32 方解除溃逃，形成 12 点迟滞环防鬼畜抖动）
    public static let moraleRallyThreshold: Double = 32.0

    /// RTS 上帝视角与主帅亲自上阵切换保护冷却（秒）
    public static let heroViewSwitchCooldownSec: Double = 1.5
    /// 主帅基础生命值
    public static let heroBaseHp: Double = 1100.0
    /// 主帅基础护甲值
    public static let heroBaseArmor: Double = 55.0
    /// 主帅基础移动速度（px/s）
    public static let heroBaseMoveSpeed: Double = 92.0
    /// 主帅百石硬弓随身箭袋上限（防单骑无限风筝逃课）
    public static let heroWarbowQuiverCap: Int = 24
    /// 主帅脱战状态下自动寻回箭矢间隔（秒/支）
    public static let heroArrowRecoverIntervalSec: Double = 2.5
    /// 主帅统帅佩刀起盾精准弹反窗口（秒）
    public static let heroPerfectParryWindowSec: Double = 0.25
    /// 主帅首次重伤落马造成的全军瞬间士气暴击扣除值
    public static let heroFirstDownMoraleShock: Double = 35.0
    /// 主帅重伤包扎期间全军士气临时封顶上限
    public static let heroDownMoraleCap: Double = 65.0
    /// 主帅首次落马回营包扎耗时（秒）
    public static let heroMedicalRecoverySec: Double = 45.0

    // MARK: - 七、后勤补给 BFS 跳数与断粮三级递进阈值

    /// 补给线 100% 无损最大连通跳数
    public static let supplyFullEfficiencyHops: Int = 2
    /// 战场余粮红色闪烁预警阈值（秒）
    public static let rationWarningSeconds: Double = 15.0
    /// 战场断粮由“饥饿期”升级为“饥溃期”的持续秒数
    public static let starvationSevereSeconds: Double = 30.0
    /// 奇袭敌营粮车单次夺取应急粮草量
    public static let raidEnemyGranaryLootGrain: Double = 150.0

    // MARK: - 八、外交关系、信誉、媾和与反霸权制衡常数

    /// 双边外交关系下限（死敌 / 血海世仇）
    public static let diplomacyRelationMin: Int = -100
    /// 双边外交关系上限（铁杆同盟）
    public static let diplomacyRelationMax: Int = 100
    /// 标准参考初始外交信誉
    public static let credibilityDefaultInit: Int = 80
    /// 签署互不侵犯条约最低关系要求
    public static let nonAggressionMinRelation: Int = 15
    /// 签署互不侵犯条约最低信誉要求
    public static let nonAggressionMinCredibility: Int = 40
    /// 签署丝路通商协定最低关系要求
    public static let tradePactMinRelation: Int = 25
    /// 缔结军事攻守同盟最低关系要求
    public static let allianceMinRelation: Int = 55
    /// 缔结军事攻守同盟最低信誉要求
    public static let allianceMinCredibility: Int = 50
    /// 背盟撕毁条约造成的自身信誉暴跌惩罚
    public static let betrayalCredibilityPenalty: Int = 45
    /// 背盟造成的全图其余存活势力关系惩罚
    public static let betrayalGlobalRelationPenalty: Int = 25
    /// 背盟触发受害国【血海世仇】拒绝一切停火谈判回合数
    public static let betrayalVendettaLockTurns: Int = 10
    /// 触发全图 AI【合纵警觉】反霸权制衡的占领城关阈值（40 座的 35% = 14，设计规定 >=13 座即触发）
    public static let antiHegemonyNodeThreshold: Int = 13

    // MARK: - 九、macOS 原生桌面窗口尺寸规范

    /// macOS 主窗口最小宽度（pt）
    public static let macWindowMinWidth: Double = 1180.0
    /// macOS 主窗口最小高度（pt）
    public static let macWindowMinHeight: Double = 740.0
    /// macOS 主窗口推荐默认宽度（pt）
    public static let macWindowDefaultWidth: Double = 1440.0
    /// macOS 主窗口推荐默认高度（pt）
    public static let macWindowDefaultHeight: Double = 900.0
}
