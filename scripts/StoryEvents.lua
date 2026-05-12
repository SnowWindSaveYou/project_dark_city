-- ============================================================================
-- StoryEvents.lua - 剧情事件数据定义
-- 纯数据模块: 定义翻牌时可触发的剧情事件 (对话 + 选择 + 碎片)
-- 由 StoryEventManager 查询和触发, 不含任何逻辑
-- ============================================================================

local M = {}

--- 剧情事件列表
--- 字段说明:
---   id        : string    唯一标识
---   cardType  : string    绑定翻牌类型 "plot" | "clue"
---   priority  : number    越小越优先 (同优先级随机)
---   onceFlag  : string?   触发后设置此 flag, 防止重复; condition 应含 not_flag 匹配
---   condition : table?    StoryManager.checkCondition 格式, nil = 无条件
---   dialogue  : table[]   DialogueSystem 对话数据
---   choiceEffects : table<string, table>?  按 choiceId 索引的效果表
---   fragment  : string?   对话结束后自动收集的碎片 ID (来自 StoryConfig.FRAGMENTS)
M.EVENTS = {

    -- ====================================================================
    -- 1) 旧报纸 — 第2天+, plot, 带选择
    -- ====================================================================
    {
        id       = "plot_newspaper",
        cardType = "plot",
        priority = 10,
        onceFlag = "seen_newspaper",
        condition = { all = {
            { min_day = 2 },
            { not_flag = "seen_newspaper" },
        }},
        dialogue = {
            { speaker = "旁白", text = "你在废弃报亭的角落发现一张旧报纸。标题触目惊心——日期却是明天。" },
            { speaker = "白夜", text = "……这张报纸上写的事情还没有发生。你要仔细看看吗？",
              choices = {
                  { label = "仔细研究", choiceId = "study" },
                  { label = "丢掉它",   choiceId = "discard" },
              },
            },
        },
        choiceEffects = {
            study   = { set_flags = { "studied_paper" }, baiye_trust_change = 1,
                        effects = { inspiration = 1 } },
            discard = { baiye_trust_change = -1 },
        },
    },

    -- ====================================================================
    -- 2) 涂鸦暗号 — 第1天+, clue, 纯对话 + 碎片
    -- ====================================================================
    {
        id       = "clue_graffiti",
        cardType = "clue",
        priority = 10,
        onceFlag = "seen_graffiti",
        condition = { all = {
            { min_day = 1 },
            { not_flag = "seen_graffiti" },
        }},
        dialogue = {
            { speaker = "旁白", text = "墙上的涂鸦里藏着一组奇怪的符号。你举起相机，胶卷自动记录了一切。" },
            { speaker = "白夜", text = "这些符号……我好像见过。是很久以前的事了。" },
            { speaker = "旁白", text = "一段模糊的画面在脑海中闪过——你和一个身影站在废墟之上。" },
        },
        fragment = "frag_01",  -- 碎片·初遇
    },

    -- ====================================================================
    -- 3) 废弃电话 — 第4天+, bonding 章节, plot, 带选择
    -- ====================================================================
    {
        id       = "plot_phone_call",
        cardType = "plot",
        priority = 10,
        onceFlag = "seen_phone_call",
        condition = { all = {
            { min_day = 4 },
            { chapter = "bonding" },
            { not_flag = "seen_phone_call" },
        }},
        dialogue = {
            { speaker = "旁白", text = "废弃电话亭的话筒突然震动起来。你犹豫片刻，还是接了起来。" },
            { speaker = "???",  text = "……你终于接了。我等了很久。" },
            { speaker = "白夜", text = "这个声音……！挂掉！快挂掉！",
              choices = {
                  { label = "继续听",   choiceId = "listen" },
                  { label = "挂断电话", choiceId = "hangup" },
              },
            },
        },
        choiceEffects = {
            listen = { set_flags = { "heard_voice" }, baiye_trust_change = -1,
                       effects = { inspiration = 2 } },
            hangup = { baiye_trust_change = 2 },
        },
        fragment = "frag_04",  -- 碎片·背叛 (无论选择都获得)
    },

    -- ====================================================================
    -- 4) 扭曲镜面 — 第3天+, 需白夜可用, plot, 纯对话
    -- ====================================================================
    {
        id       = "plot_mirror",
        cardType = "plot",
        priority = 20,
        onceFlag = "seen_mirror",
        condition = { all = {
            { min_day = 3 },
            { baiye_available = true },
            { not_flag = "seen_mirror" },
        }},
        dialogue = {
            { speaker = "旁白", text = "健身房角落的全身镜映出一个不属于你的影像。那个身影正在朝你微笑。" },
            { speaker = "白夜", text = "别看！那不是镜子，是……门。" },
            { speaker = "旁白", text = "白夜猛地拉住你的手臂。镜面泛起涟漪后恢复了平静。" },
            { speaker = "白夜", text = "……抱歉，吓到你了。下次经过这种东西，离远点。" },
        },
    },

    -- ====================================================================
    -- 5) 录音磁带 — 第6天+, 需信任>=3, clue, 碎片收集
    -- ====================================================================
    {
        id       = "clue_tape",
        cardType = "clue",
        priority = 15,
        onceFlag = "seen_tape",
        condition = { all = {
            { min_day = 6 },
            { min_trust = 3 },
            { not_flag = "seen_tape" },
        }},
        dialogue = {
            { speaker = "旁白", text = "老旧的录音机里残留着一段对话。你按下了播放键。" },
            { speaker = "???",  text = "「……训练结束了。明天开始，你就是正式的骑士了。」" },
            { speaker = "???",  text = "「嗯！我会成为最强的骑士，然后保护你！」" },
            { speaker = "白夜", text = "……这是我们的声音。是很久很久以前的事了。" },
        },
        fragment = "frag_03",  -- 碎片·训练
    },
}

return M
