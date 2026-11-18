import Foundation

/// 八大势力静态配置表（第 1 步：纯静态元数据配置，严格对齐鸿蒙版 FactionConfig.ets 与 DESIGN.md 第六节）
public enum FactionConfig: Sendable {
    /// 八大势力完整静态配置列表
    public static let allFactions: [FactionStaticConfig] = [
        FactionStaticConfig(
            id: .yanlong,
            name: "炎龙帝国",
            bannerTitle: "赤底蟠龙金纹旗",
            primaryColorHex: "#C62828",
            accentColorHex: "#FFD54F",
            specialtyTag: "重甲步兵 · 攻城器械",
            exclusiveUnitId: .yanlongHalberdGrenadier,
            aiPersonality: .imperialMethodical,
            capitalNodeId: "yl_capital",
            homeTerrain: .plain,
            bonusSummary: "步兵护甲 +15%；攻城器械造价 -20% 且对城防伤害 +25%；本阵城池耐久 +20%",
            weaknessSummary: "骑兵招募花费 +15%；重装编队大地图与野战基础移速 -5%",
            startingCredibility: 88,
            uniqueTechs: [
                FactionTechItem(
                    id: "yl_tech_armor",
                    name: "玄铁札甲",
                    effectSummary: "全步兵护甲额外 +8，对箭矢穿透抗性提升",
                    cost: ResourceCost(gold: 260, wood: 120, grain: 80)
                ),
                FactionTechItem(
                    id: "yl_tech_thunder",
                    name: "神机火雷",
                    effectSummary: "神机重卫火雷装填增至 2 枚，投石车解锁火油弹引燃效果",
                    cost: ResourceCost(gold: 340, wood: 180, grain: 100)
                ),
                FactionTechItem(
                    id: "yl_tech_discipline",
                    name: "督战军法",
                    effectSummary: "方阵与圆阵下部队士气动摇阈值下降 8 点，稳固防线",
                    cost: ResourceCost(gold: 220, wood: 80, grain: 140)
                )
            ]
        ),
        FactionStaticConfig(
            id: .canglang,
            name: "苍狼汗国",
            bannerTitle: "苍青奔狼白纛旗",
            primaryColorHex: "#0277BD",
            accentColorHex: "#E1F5FE",
            specialtyTag: "轻骑游击 · 侧翼包抄",
            exclusiveUnitId: .canglangKeshigHorseArcher,
            aiPersonality: .nomadOpportunist,
            capitalNodeId: "cl_capital",
            homeTerrain: .plain,
            bonusSummary: "全骑兵移速 +12%；远征补给跳数惩罚降低 35%；劫掠敌方农田/粮车获得双倍粮草",
            weaknessSummary: "无法建造重型配重投石车（攻城限用连弩车与云梯火矢）；步兵基础抗线士气 -5",
            startingCredibility: 72,
            uniqueTechs: [
                FactionTechItem(
                    id: "cl_tech_remount",
                    name: "双马换乘",
                    effectSummary: "大地图行军力 +25%，战场骑兵冲锋冷却缩短 20%",
                    cost: ResourceCost(gold: 240, wood: 90, grain: 160)
                ),
                FactionTechItem(
                    id: "cl_tech_whistle",
                    name: "鸣镝齐射",
                    effectSummary: "怯薛骑射与复合弓手集火同一目标时附加破甲标记 +15%",
                    cost: ResourceCost(gold: 280, wood: 150, grain: 100)
                ),
                FactionTechItem(
                    id: "cl_tech_forage",
                    name: "草原劫掠",
                    effectSummary: "每击溃一队敌军当场回收 25 粮草与 15 金币以战养战",
                    cost: ResourceCost(gold: 200, wood: 60, grain: 120)
                )
            ]
        ),
        FactionStaticConfig(
            id: .tieying,
            name: "铁鹰王国",
            bannerTitle: "靛蓝铁翼双头鹰旗",
            primaryColorHex: "#283593",
            accentColorHex: "#B0BEC5",
            specialtyTag: "强弩齐射 · 防守反击",
            exclusiveUnitId: .tieyingPaviseCrossbow,
            aiPersonality: .fortressCounter,
            capitalNodeId: "ty_capital",
            homeTerrain: .highGround,
            bonusSummary: "全远程射程 +12%；据守高地或城墙伤害额外 +15%；工兵修筑拒马与箭塔速度 +40%",
            weaknessSummary: "冲锋突击类近战兵种招募金币 +10%；离开工事野战机动偏慢",
            startingCredibility: 86,
            uniqueTechs: [
                FactionTechItem(
                    id: "ty_tech_arbalest",
                    name: "踏张钢弩",
                    effectSummary: "神弩手与连弩车装填间隔缩短 15%，射程额外 +30px",
                    cost: ResourceCost(gold: 300, wood: 200, grain: 80)
                ),
                FactionTechItem(
                    id: "ty_tech_pavise",
                    name: "背盾轮射",
                    effectSummary: "远程编队处于雁行阵或坚守态时，正面近战格挡提升 20%",
                    cost: ResourceCost(gold: 240, wood: 160, grain: 90)
                ),
                FactionTechItem(
                    id: "ty_tech_bastion",
                    name: "棱堡工事",
                    effectSummary: "拒马对冲锋骑兵反伤翻倍，关隘/城池守城箭塔射速 +25%",
                    cost: ResourceCost(gold: 260, wood: 220, grain: 70)
                )
            ]
        ),
        FactionStaticConfig(
            id: .shamo,
            name: "沙漠商盟",
            bannerTitle: "鎏金天平弯月旗",
            primaryColorHex: "#F9A825",
            accentColorHex: "#FFF8E1",
            specialtyTag: "富甲天下 · 雇佣混编",
            exclusiveUnitId: .shamoMamelukeCamel,
            aiPersonality: .merchantPragmatic,
            capitalNodeId: "sm_capital",
            homeTerrain: .desertDune,
            bonusSummary: "金矿采集与通商收入 +35%；可耗纯金币即时征召外邦雇佣团（免训练耗时）；沙漠地形无减速与耗粮惩罚",
            weaknessSummary: "本土常规步兵初始士气 -6；若国库或战场金币跌至 0 则雇佣军士气每秒衰减",
            startingCredibility: 78,
            uniqueTechs: [
                FactionTechItem(
                    id: "sm_tech_caravan",
                    name: "丝路商队",
                    effectSummary: "每签署一份通商协定额外产出 +45 金币/回合，外交送礼好感效率 +25%",
                    cost: ResourceCost(gold: 280, wood: 100, grain: 80)
                ),
                FactionTechItem(
                    id: "sm_tech_mercenary",
                    name: "黄金契约",
                    effectSummary: "雇佣兵征召费用降低 20%，并解锁邻近盟友专属精锐的限量雇佣权",
                    cost: ResourceCost(gold: 380, wood: 60, grain: 100)
                ),
                FactionTechItem(
                    id: "sm_tech_camel",
                    name: "骆驼惊骑阵",
                    effectSummary: "马穆鲁克卫队惊马光环半径扩大至 220px，并免疫沙暴视野损失",
                    cost: ResourceCost(gold: 260, wood: 90, grain: 120)
                )
            ]
        ),
        FactionStaticConfig(
            id: .shuangyuan,
            name: "霜原熊族",
            bannerTitle: "冰晶咆哮白熊图腾旗",
            primaryColorHex: "#29B6F6",
            accentColorHex: "#E0F7FA",
            specialtyTag: "重斧巨人 · 正面硬刚",
            exclusiveUnitId: .shuangyuanGiantBreaker,
            aiPersonality: .honorBerserkBear,
            capitalNodeId: "sy_capital",
            homeTerrain: .snowfield,
            bonusSummary: "全军生命上限 +15%；极寒雪原与暴风雪免疫减速/冻耗且近战伤害 +10%",
            weaknessSummary: "远程弓弩射程 -10%；族人食量庞大导致全军日常耗粮 +15%",
            startingCredibility: 84,
            uniqueTechs: [
                FactionTechItem(
                    id: "sy_tech_frostaxe",
                    name: "寒铁重斧",
                    effectSummary: "巨斧兵与巨熊破阵者横扫范围 +25%，命中附带短暂破盾僵直",
                    cost: ResourceCost(gold: 270, wood: 140, grain: 150)
                ),
                FactionTechItem(
                    id: "sy_tech_totem",
                    name: "熊灵战意",
                    effectSummary: "主帅亲自近战搏杀时，全图友军近战攻击力提升 10%",
                    cost: ResourceCost(gold: 230, wood: 100, grain: 160)
                ),
                FactionTechItem(
                    id: "sy_tech_winterhunt",
                    name: "雪原冬猎",
                    effectSummary: "抵消全军 15% 额外耗粮惩罚，雪原行军速度反增 +15%",
                    cost: ResourceCost(gold: 190, wood: 120, grain: 140)
                )
            ]
        ),
        FactionStaticConfig(
            id: .wulin,
            name: "雾林猎手",
            bannerTitle: "翡翠银叶鹿角旗",
            primaryColorHex: "#2E7D32",
            accentColorHex: "#C8E6C9",
            specialtyTag: "神射狙击 · 丛林陷阱",
            exclusiveUnitId: .wulinShadowSniper,
            aiPersonality: .guerrillaTrapper,
            capitalNodeId: "wl_capital",
            homeTerrain: .denseForest,
            bonusSummary: "密林地形移速反增 +20% 且透视林间迷雾；战前与战中可布置尖刺陷坑与绊马索",
            weaknessSummary: "缺乏超重甲抗线单位（全军护甲上限受限）；开阔无遮挡平原正面对决吃亏",
            startingCredibility: 76,
            uniqueTechs: [
                FactionTechItem(
                    id: "wl_tech_venom",
                    name: "见血封喉",
                    effectSummary: "影袭神射与复合弓手箭矢附带持续 4 秒流血毒伤，克制高血量巨人与战马",
                    cost: ResourceCost(gold: 260, wood: 170, grain: 90)
                ),
                FactionTechItem(
                    id: "wl_tech_pitfall",
                    name: "诡道陷坑",
                    effectSummary: "战场可部署陷阱上限 +4，绊马索必定令冲锋骑兵坠马眩晕 3 秒",
                    cost: ResourceCost(gold: 210, wood: 190, grain: 80)
                ),
                FactionTechItem(
                    id: "wl_tech_mist",
                    name: "迷雾潜行",
                    effectSummary: "浓雾与黑夜下全军远程射程不衰减，脱战潜行进入时间缩短至 2.5 秒",
                    cost: ResourceCost(gold: 250, wood: 140, grain: 100)
                )
            ]
        ),
        FactionStaticConfig(
            id: .xuanjia,
            name: "玄甲重骑军团",
            bannerTitle: "暗紫玄铁狮鹫枪旗",
            primaryColorHex: "#7B1FA2",
            accentColorHex: "#E1BEE7",
            specialtyTag: "具装铁骑 · 破阵冲锋",
            exclusiveUnitId: .xuanjiaCataphract,
            aiPersonality: .ironShockElite,
            capitalNodeId: "xj_capital",
            homeTerrain: .plain,
            bonusSummary: "骑兵护甲 +25%、冲锋撞击倍率 +30%；每次冲锋击溃敌队重置 50% 冲锋冷却并回升士气 +12",
            weaknessSummary: "精锐骑兵造价与粮耗高昂、兵员数量少；泥泞河流与断粮状态下战马移速暴跌 35%",
            startingCredibility: 82,
            uniqueTechs: [
                FactionTechItem(
                    id: "xj_tech_barding",
                    name: "人马具装",
                    effectSummary: "铁浮图与游骑兵远程箭矢减伤额外 +20%，免疫轻步兵阻滞",
                    cost: ResourceCost(gold: 350, wood: 100, grain: 140)
                ),
                FactionTechItem(
                    id: "xj_tech_wedge",
                    name: "楔形连环马",
                    effectSummary: "锥形阵下骑兵正面抗长枪反制伤害减免 30%，凿穿深度增加",
                    cost: ResourceCost(gold: 320, wood: 120, grain: 150)
                ),
                FactionTechItem(
                    id: "xj_tech_trample",
                    name: "铁蹄破阵",
                    effectSummary: "冲锋撞击波及路径两侧敌军造成额外士气震慑 -10",
                    cost: ResourceCost(gold: 280, wood: 90, grain: 130)
                )
            ]
        ),
        FactionStaticConfig(
            id: .xueyue,
            name: "血月祭司团",
            bannerTitle: "绯紫血月骨鼓旗",
            primaryColorHex: "#AD1457",
            accentColorHex: "#F8BBD0",
            specialtyTag: "战鼓祭祀 · 嗜血狂战",
            exclusiveUnitId: .xueyueWardrumBerserker,
            aiPersonality: .zealotSwarm,
            capitalNodeId: "xy_capital",
            homeTerrain: .denseForest,
            bonusSummary: "敌我伤亡充能【血月狂热】赋予全军移速 +20% 与免溃；夜战全军视野无损且攻击力 +15%",
            weaknessSummary: "主力护甲极薄且缺盾，畏惧强弩火器密集交叉火力；正统诸侯初始外交好感 -15",
            startingCredibility: 65,
            uniqueTechs: [
                FactionTechItem(
                    id: "xy_tech_wardrum",
                    name: "血祭战鼓",
                    effectSummary: "狂热池充能效率 +35%，激活期间近战攻击附带 15% 生命汲取",
                    cost: ResourceCost(gold: 240, wood: 110, grain: 130)
                ),
                FactionTechItem(
                    id: "xy_tech_eternalnight",
                    name: "永夜狂热",
                    effectSummary: "大地图发起夜袭成功率 +40%，夜战敌军视野额外缩减 15%",
                    cost: ResourceCost(gold: 260, wood: 100, grain: 120)
                ),
                FactionTechItem(
                    id: "xy_tech_dread",
                    name: "骸骨威慑",
                    effectSummary: "狂战士接敌近身时令周围 100px 敌军每秒士气流失 1.2 点",
                    cost: ResourceCost(gold: 220, wood: 90, grain: 110)
                )
            ]
        )
    ]

    /// O(1) 势力静态索引
    public static let byId: [FactionId: FactionStaticConfig] = {
        Dictionary(uniqueKeysWithValues: allFactions.map { ($0.id, $0) })
    }()

    /// 按势力 ID 查询静态配置
    public static func config(for factionId: FactionId) -> FactionStaticConfig? {
        byId[factionId]
    }

    /// 计算开局标准双边初始关系（严格落实血月祭司团与正统诸侯初始 -15、商盟务实中立 +10、游牧与中原历史摩擦 -12）
    public static func initialRelation(between factionA: FactionId, and factionB: FactionId) -> Int {
        guard factionA != factionB else { return GameConstants.diplomacyRelationMax }
        let pair: Set<FactionId> = [factionA, factionB]
        if pair.contains(.xueyue) {
            return -15
        }
        if pair == [.yanlong, .canglang] || pair == [.canglang, .xuanjia] {
            return -12
        }
        if pair.contains(.shamo) {
            return 10
        }
        if pair == [.yanlong, .tieying] {
            return 8
        }
        return 0
    }
}
