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
-- 记忆碎片定义 (10 个, 与 story_doc.md 剧情对齐)
-- ---------------------------------------------------------------------------
M.FRAGMENTS = {
    {
        id      = "frag_01",
        name    = "碎片·初遇",
        chapter = "awakening",
        order   = 1,
        desc    = "模糊的闪回画面：你和一个身影站在废墟之上，金色的眼睛在黑暗中发光。",
    },
    {
        id      = "frag_02",
        name    = "碎片·雷夜",
        chapter = "awakening",
        order   = 2,
        desc    = "雨夜梦境：与白夜并肩的人影，背对着你，看不清面容。诅咒在两人之间流动。",
    },
    {
        id      = "frag_03",
        name    = "碎片·训练",
        chapter = "bonding",
        order   = 3,
        desc    = "「……训练结束了。明天开始，你就是正式的骑士了。」「嗯！我会成为最强的骑士，然后保护你！」",
    },
    {
        id      = "frag_04",
        name    = "碎片·失控",
        chapter = "bonding",
        order   = 4,
        desc    = "暗面中，白夜试图将苏柚锁在身边。保护与控制之间，那条线越来越模糊。",
    },
    {
        id      = "frag_05",
        name    = "碎片·裂缝",
        chapter = "bonding",
        order   = 5,
        desc    = "「你的世界不是我的世界。」那道裂缝从那一夜开始，悄悄生长。",
    },
    {
        id      = "frag_06",
        name    = "碎片·守卫",
        chapter = "bonding",
        order   = 6,
        desc    = "白夜用整个身体挡住了碎片守卫的攻击。诅咒的力量在转移——从那个人的手指，流进他的胸口。",
    },
    {
        id      = "frag_07",
        name    = "碎片·棠",
        chapter = "truth",
        order   = 7,
        desc    = "眉眼凛冽，站姿笔直，像一柄收在鞘中的刀。风吹过的时候，她没动。白夜站在她身侧，眼神里全是追随。",
    },
    {
        id      = "frag_08",
        name    = "碎片·篝火",
        chapter = "truth",
        order   = 8,
        desc    = "篝火旁，白夜靠在棠的肩膀上，棠的嘴角有一点很淡的笑。「我不会让你一个人扛。」",
    },
    {
        id      = "frag_09",
        name    = "碎片·背离",
        chapter = "finale",
        order   = 9,
        desc    = "诅咒侵蚀了白夜大半身体，黑色的纹路爬上他的脸。棠没有说话，只是看着他——然后转身走了。",
    },
    {
        id      = "frag_10",
        name    = "碎片·真相",
        chapter = "finale",
        order   = 10,
        desc    = "棠和白夜本可以各自承担一半诅咒，都能活下来。但棠没有那样做。她选择了独自面对——和魔王同归于尽。",
    },
}

return M
