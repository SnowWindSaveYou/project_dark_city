-- ============================================================================
-- StoryConfig.lua - 故事系统数据定义
-- 纯数据模块: 天数、章节、结局、碎片定义
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- 天数常量
-- ---------------------------------------------------------------------------
M.BASE_DAYS     = 7    -- 基础游戏天数
M.EXTENDED_DAYS = 14   -- 收集足够碎片后延展天数
M.EXTEND_THRESHOLD = 5 -- 碎片数达到此值时延展天数

-- ---------------------------------------------------------------------------
-- 章节定义 (按天数范围划分)
-- ---------------------------------------------------------------------------
M.CHAPTERS = {
    {
        id       = "awakening",
        name     = "苏醒与恐惧",
        dayRange = { 1, 3 },
    },
    {
        id       = "bonding",
        name     = "磨合与依存",
        dayRange = { 4, 7 },
    },
    {
        id       = "truth",
        name     = "真相与决裂",
        dayRange = { 8, 11 },
    },
    {
        id       = "finale",
        name     = "终章抉择",
        dayRange = { 12, 14 },
    },
}

-- ---------------------------------------------------------------------------
-- 结局定义 (按 priority 升序排列, 越小越优先匹配)
-- ---------------------------------------------------------------------------
-- conditions 使用 StoryManager.checkCondition 格式
-- priority 越小越优先; default 结局 priority 最大作为兜底
M.ENDINGS = {
    {
        id         = "companion",
        title      = "灵体相伴",
        subtitle   = "白夜化为微弱的灵光，留在你身边。一人一灵，继续在这座都市生活……",
        priority   = 10,
        conditions = { all = {
            { flag = "chose_acceptance" },
            { not_flag = "chose_merge" },
            { not_flag = "chose_devour" },
            { min_fragments = 10 },
        }},
        isVictory  = true,
    },
    {
        id         = "seal",
        title      = "永囚深渊",
        subtitle   = "你与魔王达成协议，将白夜永久封印回暗面。公寓空了，雷雨夜不会再有人钻被窝……",
        priority   = 15,
        conditions = { flag = "ending_seal" },
        isVictory  = true,
    },
    {
        id         = "substitute",
        title      = "代餐完成",
        subtitle   = "你融合了前世的记忆，变成了'她'。白夜恢复了人类形态，但你每日对镜梳妆时，总觉得自己在演别人……",
        priority   = 20,
        conditions = { flag = "chose_merge" },
        isVictory  = true,
    },
    {
        id         = "dark_lord",
        title      = "新魔王",
        subtitle   = "你吞噬了白夜的力量，成为新的魔王。暗面扩张，整栋居民楼被侵蚀……",
        priority   = 30,
        conditions = { flag = "chose_devour" },
        isVictory  = false,
    },
    {
        -- 兜底结局: 无特殊条件, 存活到最后一天即触发
        id         = "default",
        title      = "迷雾中的日常",
        subtitle   = "你活了下来。但记忆的碎片仍散落在暗面深处，白夜仍在等待……",
        priority   = 99,
        conditions = nil,  -- nil = 总是匹配
        isVictory  = true,
    },
}

-- ---------------------------------------------------------------------------
-- 记忆碎片定义 (10 个, Phase 1 为占位内容)
-- ---------------------------------------------------------------------------
M.FRAGMENTS = {
    {
        id      = "frag_01",
        name    = "碎片·初遇",
        chapter = "awakening",
        order   = 1,
        desc    = "模糊的闪回画面：你和一个身影站在废墟之上。",
    },
    {
        id      = "frag_02",
        name    = "碎片·约定",
        chapter = "awakening",
        order   = 2,
        desc    = "金色眼睛的少年说：'我会一直守着你。'",
    },
    {
        id      = "frag_03",
        name    = "碎片·训练",
        chapter = "bonding",
        order   = 3,
        desc    = "废弃的操场上，两个人影在练习剑术。",
    },
    {
        id      = "frag_04",
        name    = "碎片·背叛",
        chapter = "bonding",
        order   = 4,
        desc    = "人群的怒吼，火焰吞噬了城堡的尖塔。",
    },
    {
        id      = "frag_05",
        name    = "碎片·变身",
        chapter = "bonding",
        order   = 5,
        desc    = "黑色的羽翼从少年背后展开，他的眼睛变成了猩红色。",
    },
    {
        id      = "frag_06",
        name    = "碎片·逃亡",
        chapter = "bonding",
        order   = 6,
        desc    = "在雨夜的森林中奔跑，身后是永不停歇的追兵。",
    },
    {
        id      = "frag_07",
        name    = "碎片·誓言",
        chapter = "bonding",
        order   = 7,
        desc    = "在悬崖边上，你们互相许下了不会背弃对方的誓言。",
    },
    {
        id      = "frag_08",
        name    = "碎片·封印",
        chapter = "truth",
        order   = 8,
        desc    = "你举起了圣剑，面前的少年没有躲闪。",
    },
    {
        id      = "frag_09",
        name    = "碎片·沉睡",
        chapter = "truth",
        order   = 9,
        desc    = "漫长的黑暗，没有声音，没有光。你在等谁？",
    },
    {
        id      = "frag_10",
        name    = "碎片·觉醒",
        chapter = "truth",
        order   = 10,
        desc    = "你终于想起了一切。你就是那个挥剑的人。",
    },
}

return M
