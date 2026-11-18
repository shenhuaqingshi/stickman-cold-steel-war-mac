import Foundation

/// 核心数据模型与枚举契约定义（第 1 步：纯静态类型骨架，零 UI/SpriteKit 依赖，不含任何战斗计算逻辑）
/// 所有类型均遵循 Swift 6 `Sendable`、`Codable`、`Hashable`，可直接跨 Actor 传递并支持 XCTest 独立单测与本地 JSON 存档。

// MARK: - 一、势力与兵种核心枚举

/// 八大非对称势力唯一标识枚举
public enum FactionId: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case yanlong = "yanlong"         // 炎龙帝国
    case canglang = "canglang"       // 苍狼汗国
    case tieying = "tieying"         // 铁鹰王国
    case shamo = "shamo"             // 沙漠商盟
    case shuangyuan = "shuangyuan"   // 霜原熊族
    case wulin = "wulin"             // 雾林猎手
    case xuanjia = "xuanjia"         // 玄甲重骑军团
    case xueyue = "xueyue"           // 血月祭司团

    public var id: String { rawValue }
}

/// 兵种职能大类枚举
public enum UnitCategory: String, CaseIterable, Sendable, Codable, Hashable {
    case support = "support"     // 后勤辅兵 / 辎重工兵
    case infantry = "infantry"   // 抗线重步兵
    case polearm = "polearm"     // 长柄反骑步兵
    case ranged = "ranged"       // 远程弓弩兵
    case cavalry = "cavalry"     // 轻重机动骑兵
    case shock = "shock"         // 重型破甲 / 狂战突击兵
    case siege = "siege"         // 攻城重器与破甲弩炮

    public var displayName: String {
        switch self {
        case .support: return "后勤辅兵"
        case .infantry: return "抗线步兵"
        case .polearm: return "反骑长柄"
        case .ranged: return "远程弓弩"
        case .cavalry: return "机动铁骑"
        case .shock: return "破甲突击"
        case .siege: return "攻城器械"
        }
    }
}

/// 全部 16 种可招募单位唯一标识（8 种全势力通用 + 8 种势力专属王牌精锐）
public enum UnitTypeId: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    // 8 种全势力通用基础兵种
    case sapper = "sapper"                                       // 辎重工兵
    case shieldSwordsman = "shield_swordsman"                    // 刀盾步兵
    case pikeman = "pikeman"                                     // 长枪方阵兵
    case compositeArcher = "composite_archer"                    // 复合弓手
    case lightCavalry = "light_cavalry"                          // 游骑兵
    case greatAxeman = "great_axeman"                            // 重型巨斧兵
    case ballista = "ballista"                                   // 破甲连弩车
    case trebuchet = "trebuchet"                                 // 配重投石车

    // 8 种八大势力专属王牌兵种
    case yanlongHalberdGrenadier = "yanlong_halberd_grenadier"   // 炎龙神机重卫
    case canglangKeshigHorseArcher = "canglang_keshig"           // 苍狼怯薛骑射
    case tieyingPaviseCrossbow = "tieying_pavise_crossbow"       // 铁鹰重装神弩手
    case shamoMamelukeCamel = "shamo_mameluke_camel"             // 黄金马穆鲁克卫队
    case shuangyuanGiantBreaker = "shuangyuan_giant_breaker"     // 霜原巨熊破阵者
    case wulinShadowSniper = "wulin_shadow_sniper"               // 雾林影袭神射
    case xuanjiaCataphract = "xuanjia_cataphract"                // 玄甲具装铁浮图
    case xueyueWardrumBerserker = "xueyue_wardrum_berserker"     // 血月狂战祭团

    public var id: String { rawValue }
}

// MARK: - 二、编队阵型、战术指令、多军团与骨骼动作枚举

/// 四种经典冷兵器编队阵型（对应 macOS 快捷键 1 / 2 / 3 / 4）
public enum FormationType: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case phalanxRect = "phalanx_rect"   // 方阵（护甲+20%，抗骑击退+50%，移速-15%）
    case echelonLine = "echelon_line"   // 雁行阵（远程齐射100%，受爆炸溅射-35%）
    case wedgeCharge = "wedge_charge"   // 锥形阵（移速+8%，冲锋倍率+25%，近防-10%）
    case circleDefense = "circle_def"   // 圆阵（360°消除侧背弱点，无法高速移动）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .phalanxRect: return "方阵"
        case .echelonLine: return "雁行阵"
        case .wedgeCharge: return "锥形阵"
        case .circleDefense: return "圆阵"
        }
    }

    public var shortcutHint: String {
        switch self {
        case .phalanxRect: return "1"
        case .echelonLine: return "2"
        case .wedgeCharge: return "3"
        case .circleDefense: return "4"
        }
    }
}

/// 主帅与 AI 战场战术指令枚举（覆盖推进、坚守、冲锋、撤退、包抄、合围、诈败、设伏、断粮）
public enum TacticalOrder: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case advance = "advance"                 // 稳步推进（快捷键 Q）
    case holdGround = "hold"                 // 原地坚守（快捷键 W）
    case allOutCharge = "charge"             // 全军冲锋（快捷键 E）
    case retreat = "retreat"                 // 交替撤退（快捷键 R）
    case flank = "flank"                     // 侧翼迂回包抄（快捷键 F）
    case pincerEncircle = "pincer_encircle"  // 钳形夹击合围（快捷键 G）
    case feignedRetreat = "feigned_retreat"  // 诈败诱敌入伏（快捷键 Z）
    case ambushHide = "ambush_hide"          // 潜伏设伏半渡而击（快捷键 X）
    case raidSupply = "raid_supply"          // 断粮奇袭焚粮（快捷键 C）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .advance: return "稳步推进"
        case .holdGround: return "原地坚守"
        case .allOutCharge: return "全军冲锋"
        case .retreat: return "交替撤退"
        case .flank: return "侧翼包抄"
        case .pincerEncircle: return "钳形合围"
        case .feignedRetreat: return "诈败诱敌"
        case .ambushHide: return "密林设伏"
        case .raidSupply: return "奇袭断粮"
        }
    }

    public var rtsShortcutKey: String {
        switch self {
        case .advance: return "Q"
        case .holdGround: return "W"
        case .allOutCharge: return "E"
        case .retreat: return "R"
        case .flank: return "F"
        case .pincerEncircle: return "G"
        case .feignedRetreat: return "Z"
        case .ambushHide: return "X"
        case .raidSupply: return "C"
        }
    }
}

/// 多军团多战线建制角色枚举（支持 Ctrl+1~6 编组 / F1~F6 快速选定）
public enum ArmyCorpsRole: String, CaseIterable, Sendable, Codable, Hashable {
    case vanguardCenter = "vanguard_center"  // 中军前锋
    case leftWing = "left_wing"              // 左翼机动军团（北走廊）
    case rightWing = "right_wing"            // 右翼机动军团（南走廊）
    case rearReserve = "rear_reserve"        // 总预备队
    case siegeBattery = "siege_battery"      // 远程攻城群
    case supplyEscort = "supply_escort"      // 辎重护粮队
}

/// 火柴人单兵程序化骨骼动作状态枚举
public enum UnitActionState: String, CaseIterable, Sendable, Codable, Hashable {
    case idleReady = "idle_ready"            // 持械戒备呼吸态
    case marchRun = "march_run"              // 行军奔跑摆臂迈腿态
    case chargeSprint = "charge_sprint"      // 压低身姿全力冲锋撞阵态
    case meleeWindup = "melee_windup"        // 挥砍 / 刺击前摇蓄力态
    case meleeStrike = "melee_strike"        // 刀劈 / 枪刺 / 斧砸命中挥击态
    case rangedDrawFire = "ranged_draw_fire" // 挽弓搭箭 / 踏张上弦抛射态
    case shieldBlock = "shield_block"        // 举盾格挡火星迸溅态
    case staggerHit = "stagger_hit"          // 受击后仰 / 战马冲撞击退态
    case routPanic = "rout_panic"            // 士气崩溃弃盾白旗溃逃态
    case dyingFall = "dying_fall"            // 致命伤倾倒动画态
    case fallenCorpse = "fallen_corpse"      // 战场倒地遗骸态（定量环形留存）
}

/// 分队八象限受围态势枚举
public enum EncirclementState: String, CaseIterable, Sendable, Codable, Hashable {
    case clear = "clear"           // 正面正常交战
    case flanked = "flanked"       // 单侧或背后遭袭
    case pincered = "pincered"     // 钳形夹击（双方向钝角受敌）
    case encircled = "encircled"   // 铁桶合围（>=5 扇区受敌且退路断绝）
}

/// 分队士气四阶状态枚举（含溃逃恢复迟滞防抖）
public enum MoraleBracket: String, CaseIterable, Sendable, Codable, Hashable {
    case high = "high"         // 高昂 (85 ~ 100)
    case steady = "steady"     // 稳定 (40 ~ 84)
    case wavering = "wavering" // 动摇 (20 ~ 39)
    case routing = "routing"   // 溃逃 (<20，回升至 >=32 方重整)
}

// MARK: - 三、主帅英雄模式与战场环境枚举

/// 主帅随身三种冷兵器切换枚举（英雄模式下数字键 1 / 2 / 3 切换）
public enum HeroWeaponType: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case commandSaber = "saber"   // 统帅佩刀（配盾格挡弹反 + 120° 扇形挥砍）
    case breakerSpear = "spear"   // 破阵大枪（68px 直线穿透 + 2.2x 反骑挑落）
    case heavyWarbow = "warbow"   // 百石硬弓（蓄力 0.9s 重箭贯穿 + 24 支箭袋上限）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .commandSaber: return "统帅佩刀"
        case .breakerSpear: return "破阵大枪"
        case .heavyWarbow: return "百石硬弓"
        }
    }
}

/// 主帅三大主动技能枚举
public enum HeroSkillId: String, CaseIterable, Sendable, Codable, Hashable {
    case breakthroughCharge = "breakthrough_charge" // 破阵突击（CD 10s，空格触发）
    case ironBulwark = "iron_bulwark"               // 铁壁横戈（CD 8s，E 键触发）
    case grandWarCry = "grand_war_cry"              // 三军战吼（CD 22s，R 键触发，唤醒溃军）
}

/// 主帅战场生命安全状态（两段式“落马重伤 — 二次绝命”保护机制）
public enum HeroVitalState: String, CaseIterable, Sendable, Codable, Hashable {
    case healthyActive = "healthy_active"           // 正常作战（享有首次落马抢救保护）
    case recoveringInCamp = "recovering_in_camp"    // 首次落马回营包扎中（45s，全军士气上限锁 65）
    case woundedWeakened = "wounded_weakened"       // 重创虚弱复出（35% 残血，属性 -25%，无免死）
    case fallenMartyred = "fallen_martyred"         // 二次阵亡或本阵已破殉国（全军崩溃战败）
}

/// 战场操控双视角枚举（Tab 键无缝切换，冷却 1.5s）
public enum BattleControlMode: String, CaseIterable, Sendable, Codable, Hashable {
    case rtsCommander = "rts_commander" // RTS 上帝统帅视角
    case heroAction = "hero_action"     // 主帅亲自上阵英雄视角
}

/// 八种战场与大地图地形类型枚举
public enum TerrainType: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case plain = "plain"             // 开阔平原
    case highGround = "highland"     // 制高点 / 山坡
    case riverFord = "river_ford"    // 河流浅滩
    case bridgePass = "bridge"       // 桥梁 / 狭窄关口
    case denseForest = "forest"      // 迷雾密林
    case desertDune = "desert"       // 荒漠沙丘
    case snowfield = "snowfield"     // 极寒雪原
    case fortWall = "fort_wall"      // 城墙 / 要塞掩体

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plain: return "开阔平原"
        case .highGround: return "制高点/山坡"
        case .riverFord: return "河流浅滩"
        case .bridgePass: return "桥梁/窄关"
        case .denseForest: return "迷雾密林"
        case .desertDune: return "荒漠沙丘"
        case .snowfield: return "极寒雪原"
        case .fortWall: return "城墙/工事"
        }
    }
}

/// 五种天气与昼夜状态枚举
public enum WeatherType: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case clearDay = "clear_day"   // 晴朗白昼
    case heavyFog = "heavy_fog"   // 浓雾弥漫
    case rainMud = "rain_mud"     // 暴雨泥泞
    case blizzard = "blizzard"    // 凛冽暴雪
    case night = "night"          // 幽暗黑夜

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .clearDay: return "晴朗白昼"
        case .heavyFog: return "浓雾弥漫"
        case .rainMud: return "暴雨泥泞"
        case .blizzard: return "凛冽暴雪"
        case .night: return "幽暗黑夜"
        }
    }
}

/// 六种战役与单局战斗场景类型枚举
public enum BattleScenarioType: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case fieldPitched = "field_pitched"   // 标准野战会战
    case siegeAssault = "siege_assault"   // 攻城攻坚战
    case siegeDefense = "siege_defense"   // 据城死守战
    case ambush = "ambush"                // 峡谷 / 密林伏击战
    case convoyEscort = "convoy_escort"   // 粮道护送 / 劫粮战
    case nightRaid = "night_raid"         // 劫营夜袭战

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fieldPitched: return "标准野战"
        case .siegeAssault: return "攻城攻坚战"
        case .siegeDefense: return "据城死守战"
        case .ambush: return "密林伏击战"
        case .convoyEscort: return "护粮/劫粮战"
        case .nightRaid: return "劫营夜袭战"
        }
    }
}

// MARK: - 四、外交与 AI 性格枚举

/// 外交双边条约状态枚举
public enum DiplomaticStatus: String, CaseIterable, Sendable, Codable, Hashable {
    case war = "war"                         // 交战状态
    case truce = "truce"                     // 停战协定期（撕毁触发背盟重罚）
    case neutral = "neutral"                 // 中立状态
    case nonAggression = "non_aggression"    // 互不侵犯条约
    case tradePact = "trade_pact"            // 丝路通商协定
    case alliance = "alliance"               // 军事攻守同盟（共享视野与粮道借道权）
    case vassal = "vassal"                   // 朝贡附庸关系
    case royalMarriage = "royal_marriage"    // 联姻结好关系

    public var displayName: String {
        switch self {
        case .war: return "交战"
        case .truce: return "停战期"
        case .neutral: return "中立"
        case .nonAggression: return "互不侵犯"
        case .tradePact: return "通商协定"
        case .alliance: return "军事同盟"
        case .vassal: return "朝贡附庸"
        case .royalMarriage: return "政治联姻"
        }
    }
}

/// 八大势力 AI 战略与战术性格原型枚举
public enum AiPersonality: String, CaseIterable, Sendable, Codable, Hashable {
    case imperialMethodical = "imperial_methodical" // 王道推进型（炎龙）
    case nomadOpportunist = "nomad_opportunist"     // 游牧掠夺型（苍狼）
    case fortressCounter = "fortress_counter"       // 稳健筑垒型（铁鹰）
    case merchantPragmatic = "merchant_pragmatic"   // 金元算计型（商盟）
    case honorBerserkBear = "honor_bear"            // 豪迈勇武型（熊族）
    case guerrillaTrapper = "guerrilla_trapper"     // 诡道伏击型（雾林）
    case ironShockElite = "iron_shock_elite"        // 傲慢铁血型（玄甲）
    case zealotSwarm = "zealot_swarm"               // 狂热扩张型（血月）
}

// MARK: - 五、纯静态数值与状态结构体（Value Types）

/// 三维资源消耗或储量结构
public struct ResourceCost: Sendable, Codable, Hashable {
    public let gold: Int
    public let wood: Int
    public let grain: Int

    public init(gold: Int, wood: Int, grain: Int) {
        self.gold = gold
        self.wood = wood
        self.grain = grain
    }
}

/// 单位静态数值配置结构体（严格对齐 DESIGN.md 第三节 16 兵种表）
public struct UnitStaticStats: Sendable, Codable, Hashable, Identifiable {
    public let id: UnitTypeId
    public let name: String
    public let category: UnitCategory
    /// 若为 nil 表示全势力通用基础兵种，否则为对应势力专属精锐
    public let exclusiveFaction: FactionId?
    public let hp: Int
    public let attack: Int
    /// 破甲比例（0.0 ~ 1.0）
    public let armorPenetration: Double
    /// 基础护甲值
    public let armor: Int
    /// 正面盾牌远程减伤率（0.0 ~ 0.85）
    public let shieldRangedBlock: Double
    /// 最大有效攻击距离（逻辑 px）
    public let attackRange: Double
    /// 最小盲区射程（逻辑 px，近身小于此距离无法开火）
    public let minRange: Double
    /// 攻击间隔（秒/次）
    public let attackIntervalSec: Double
    /// 基础移动速度（逻辑 px/秒）
    public let moveSpeed: Double
    /// 助跑成型后首击冲锋倍率
    public let chargeMultiplier: Double
    /// 正面架枪迎击冲锋骑兵时的反骑伤害倍率
    public let antiCavalryMultiplier: Double
    /// 招募三维资源花费
    public let cost: ResourceCost
    /// 训练耗时（秒）
    public let buildTimeSec: Double
    /// 占用人口编制
    public let popCap: Int
    /// 战场每秒消耗粮草值
    public let grainUpkeepPerSec: Double
    /// 核心战术机制说明
    public let traitDesc: String

    public init(
        id: UnitTypeId,
        name: String,
        category: UnitCategory,
        exclusiveFaction: FactionId?,
        hp: Int,
        attack: Int,
        armorPenetration: Double,
        armor: Int,
        shieldRangedBlock: Double,
        attackRange: Double,
        minRange: Double,
        attackIntervalSec: Double,
        moveSpeed: Double,
        chargeMultiplier: Double,
        antiCavalryMultiplier: Double,
        cost: ResourceCost,
        buildTimeSec: Double,
        popCap: Int,
        grainUpkeepPerSec: Double,
        traitDesc: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.exclusiveFaction = exclusiveFaction
        self.hp = hp
        self.attack = attack
        self.armorPenetration = armorPenetration
        self.armor = armor
        self.shieldRangedBlock = shieldRangedBlock
        self.attackRange = attackRange
        self.minRange = minRange
        self.attackIntervalSec = attackIntervalSec
        self.moveSpeed = moveSpeed
        self.chargeMultiplier = chargeMultiplier
        self.antiCavalryMultiplier = antiCavalryMultiplier
        self.cost = cost
        self.buildTimeSec = buildTimeSec
        self.popCap = popCap
        self.grainUpkeepPerSec = grainUpkeepPerSec
        self.traitDesc = traitDesc
    }
}

/// 势力专属科技节点配置结构体
public struct FactionTechItem: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let effectSummary: String
    public let cost: ResourceCost

    public init(id: String, name: String, effectSummary: String, cost: ResourceCost) {
        self.id = id
        self.name = name
        self.effectSummary = effectSummary
        self.cost = cost
    }
}

/// 八大势力静态配置结构体
public struct FactionStaticConfig: Sendable, Codable, Hashable, Identifiable {
    public let id: FactionId
    public let name: String
    public let bannerTitle: String
    public let primaryColorHex: String
    public let accentColorHex: String
    public let specialtyTag: String
    public let exclusiveUnitId: UnitTypeId
    public let aiPersonality: AiPersonality
    public let capitalNodeId: String
    public let homeTerrain: TerrainType
    public let bonusSummary: String
    public let weaknessSummary: String
    public let startingCredibility: Int
    public let uniqueTechs: [FactionTechItem]

    public init(
        id: FactionId,
        name: String,
        bannerTitle: String,
        primaryColorHex: String,
        accentColorHex: String,
        specialtyTag: String,
        exclusiveUnitId: UnitTypeId,
        aiPersonality: AiPersonality,
        capitalNodeId: String,
        homeTerrain: TerrainType,
        bonusSummary: String,
        weaknessSummary: String,
        startingCredibility: Int,
        uniqueTechs: [FactionTechItem]
    ) {
        self.id = id
        self.name = name
        self.bannerTitle = bannerTitle
        self.primaryColorHex = primaryColorHex
        self.accentColorHex = accentColorHex
        self.specialtyTag = specialtyTag
        self.exclusiveUnitId = exclusiveUnitId
        self.aiPersonality = aiPersonality
        self.capitalNodeId = capitalNodeId
        self.homeTerrain = homeTerrain
        self.bonusSummary = bonusSummary
        self.weaknessSummary = weaknessSummary
        self.startingCredibility = startingCredibility
        self.uniqueTechs = uniqueTechs
    }
}

/// 战役战略大地图节点类型枚举
public enum CampaignNodeType: String, CaseIterable, Sendable, Codable, Hashable {
    case capitalCitadel = "capital"  // 王都巨城（5级高防、核心仓城）
    case fortressPass = "pass"       // 险要雄关（一夫当关交通咽喉）
    case granaryTown = "granary"     // 粮仓重镇（高额粮草与远征中继）
    case resourceHub = "resource"    // 矿山 / 林场 / 商埠重镇
    case crossingOutpost = "outpost" // 渡口 / 绿洲前哨

    public var displayName: String {
        switch self {
        case .capitalCitadel: return "王都巨城"
        case .fortressPass: return "险要雄关"
        case .granaryTown: return "粮仓重镇"
        case .resourceHub: return "资源重镇"
        case .crossingOutpost: return "交通渡口"
        }
    }
}

/// 战役大地图节点静态配置结构体（40 座城关拓扑节点）
public struct CampaignNodeConfig: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let regionIndex: Int
    public let regionName: String
    public let nodeType: CampaignNodeType
    /// 大地图逻辑坐标 X (0 ~ 3600)
    public let x: Double
    /// 大地图逻辑坐标 Y (0 ~ 2400)
    public let y: Double
    public let initialOwner: FactionId
    public let terrain: TerrainType
    public let defenseLevel: Int
    public let goldYield: Int
    public let woodYield: Int
    public let grainYield: Int
    /// 是否可作为 BFS 远征补给线根源仓城
    public let isSupplyDepot: Bool
    /// 无向对称连通邻接节点 ID 列表
    public let neighbors: [String]

    public var totalYield: Int {
        goldYield + woodYield + grainYield
    }

    public init(
        id: String,
        name: String,
        regionIndex: Int,
        regionName: String,
        nodeType: CampaignNodeType,
        x: Double,
        y: Double,
        initialOwner: FactionId,
        terrain: TerrainType,
        defenseLevel: Int,
        goldYield: Int,
        woodYield: Int,
        grainYield: Int,
        isSupplyDepot: Bool,
        neighbors: [String]
    ) {
        self.id = id
        self.name = name
        self.regionIndex = regionIndex
        self.regionName = regionName
        self.nodeType = nodeType
        self.x = x
        self.y = y
        self.initialOwner = initialOwner
        self.terrain = terrain
        self.defenseLevel = defenseLevel
        self.goldYield = goldYield
        self.woodYield = woodYield
        self.grainYield = grainYield
        self.isSupplyDepot = isSupplyDepot
        self.neighbors = neighbors
    }
}

/// 大地图无向道路连接边（用于渲染与拓扑测试断言，保证 fromId < toId 唯一化）
public struct CampaignRoadEdge: Sendable, Codable, Hashable, Identifiable {
    public let fromNodeId: String
    public let toNodeId: String

    public var id: String { "\(fromNodeId)--\(toNodeId)" }

    public init(nodeA: String, nodeB: String) {
        if nodeA <= nodeB {
            self.fromNodeId = nodeA
            self.toNodeId = nodeB
        } else {
            self.fromNodeId = nodeB
            self.toNodeId = nodeA
        }
    }
}

/// 双边外交实时状态结构
public struct BilateralDiplomacyState: Sendable, Codable, Hashable, Identifiable {
    public let factionA: FactionId
    public let factionB: FactionId
    /// 双边关系值 [-100, +100]
    public var relation: Int
    public var status: DiplomaticStatus
    /// 条约或停战剩余回合数
    public var remainingTurns: Int
    /// 背盟触发的血海世仇禁谈剩余回合数
    public var vendettaLockTurns: Int

    public var id: String { "\(factionA.rawValue)_\(factionB.rawValue)" }

    public init(
        factionA: FactionId,
        factionB: FactionId,
        relation: Int,
        status: DiplomaticStatus,
        remainingTurns: Int = 0,
        vendettaLockTurns: Int = 0
    ) {
        self.factionA = factionA
        self.factionB = factionB
        self.relation = relation
        self.status = status
        self.remainingTurns = remainingTurns
        self.vendettaLockTurns = vendettaLockTurns
    }
}

/// 媾和谈判报价单结构体
public struct PeaceOfferTerms: Sendable, Codable, Hashable {
    public let proposer: FactionId
    public let target: FactionId
    public let goldIndemnity: Int
    public let grainTributePerTurn: Int
    public let cededNodeIds: [String]
    public let truceTurns: Int

    public init(
        proposer: FactionId,
        target: FactionId,
        goldIndemnity: Int,
        grainTributePerTurn: Int,
        cededNodeIds: [String],
        truceTurns: Int
    ) {
        self.proposer = proposer
        self.target = target
        self.goldIndemnity = goldIndemnity
        self.grainTributePerTurn = grainTributePerTurn
        self.cededNodeIds = cededNodeIds
        self.truceTurns = truceTurns
    }
}

/// 本地存档槽位元数据与战役摘要（持久化于 macOS Application Support 目录）
public struct SaveSlotSummary: Sendable, Codable, Hashable, Identifiable {
    public static let currentSchemaVersion: Int = 1

    public let schemaVersion: Int
    public let slotIndex: Int
    public var title: String
    public var factionId: FactionId
    public var turnNumber: Int
    public var controlledNodes: Int
    public var totalBattlesWon: Int
    public var totalEnemiesDefeated: Int
    public var updatedAtIso: String
    public var isEmpty: Bool

    public var id: Int { slotIndex }

    public init(
        schemaVersion: Int = SaveSlotSummary.currentSchemaVersion,
        slotIndex: Int,
        title: String,
        factionId: FactionId,
        turnNumber: Int,
        controlledNodes: Int,
        totalBattlesWon: Int = 0,
        totalEnemiesDefeated: Int = 0,
        updatedAtIso: String,
        isEmpty: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.slotIndex = slotIndex
        self.title = title
        self.factionId = factionId
        self.turnNumber = turnNumber
        self.controlledNodes = controlledNodes
        self.totalBattlesWon = totalBattlesWon
        self.totalEnemiesDefeated = totalEnemiesDefeated
        self.updatedAtIso = updatedAtIso
        self.isEmpty = isEmpty
    }

    public static func emptySlot(index: Int) -> SaveSlotSummary {
        SaveSlotSummary(
            slotIndex: index,
            title: "空白军档槽位 #\(index)",
            factionId: .yanlong,
            turnNumber: 0,
            controlledNodes: 0,
            updatedAtIso: "尚未写入",
            isEmpty: true
        )
    }
}

/// 游戏入口模式标识枚举
public enum GameEntryMode: String, CaseIterable, Sendable, Codable, Hashable {
    case campaign = "campaign"   // 战役模式
    case skirmish = "skirmish"   // 遭遇战
    case siegeChallenge = "siege"// 守城挑战
    case customSandbox = "custom"// 自定义沙盒演武

    public var displayTitle: String {
        switch self {
        case .campaign: return "战役模式"
        case .skirmish: return "遭遇战"
        case .siegeChallenge: return "守城挑战"
        case .customSandbox: return "自定义战场"
        }
    }
}

/// 页面路由跳转上下文参数
public struct RouteLaunchContext: Sendable, Codable, Hashable {
    public var entryMode: GameEntryMode
    public var playerFaction: FactionId
    public var enemyFaction: FactionId
    public var scenarioType: BattleScenarioType
    public var terrain: TerrainType
    public var weather: WeatherType
    public var targetNodeId: String?

    public init(
        entryMode: GameEntryMode = .skirmish,
        playerFaction: FactionId = .yanlong,
        enemyFaction: FactionId = .canglang,
        scenarioType: BattleScenarioType = .fieldPitched,
        terrain: TerrainType = .plain,
        weather: WeatherType = .clearDay,
        targetNodeId: String? = nil
    ) {
        self.entryMode = entryMode
        self.playerFaction = playerFaction
        self.enemyFaction = enemyFaction
        self.scenarioType = scenarioType
        self.terrain = terrain
        self.weather = weather
        self.targetNodeId = targetNodeId
    }
}
