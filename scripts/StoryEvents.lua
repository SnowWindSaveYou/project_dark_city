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

    -- ====================================================================
    -- 6) 碎片守卫遭遇 — 第6天, 暗面中触发 (clue, 强制碎片收集)
    -- 注: 此事件在 DarkWorldFlow 进入第6天暗面后由 StoryEventManager 自动查询
    -- ====================================================================
    {
        id       = "dark_shard_guardian",
        cardType = "clue",
        priority = 1,
        onceFlag = "seen_shard_guardian",
        condition = { all = {
            { min_day = 6 },
            { max_day = 6 },
            { flag = "in_dark_world" },
            { not_flag = "seen_shard_guardian" },
        }},
        dialogue = {
            { speaker = "白夜", text = "不对劲。有东西在等我们。" },
            { speaker = "旁白", text = "雾气深处，一个巨大的轮廓缓缓移动。比之前遇到的所有东西都大。" },
            { speaker = "白夜", text = "是碎片守卫。暗面最古老的东西之一。它守着记忆。" },
            { speaker = "白夜", text = "退后！！！" },
            { speaker = "旁白", text = "苏柚被一股力量推了出去。摔在地上，抬起头——白夜体积变得巨大，像一面墙一样挡在她面前。" },
            { speaker = "旁白", text = "守卫撞上白夜。没有声音，只有空间的震颤。白夜的身体挡住了魔物的攻击。" },
            { speaker = "苏柚", text = "白夜！！！" },
            { speaker = "白夜", text = "拿碎片。快！" },
            { speaker = "旁白", text = "苏柚触碰到碎片的瞬间，画面涌来：白夜站在一个人面前，说「我来扛」。那个人伸出手，抵住他的胸口，力量从她指尖流入他体内。诅咒在转移。" },
            { speaker = "旁白", text = "碎片碎了。守卫消失。白夜缩成毛球掉下来。" },
        },
        fragment = "frag_06",  -- 碎片·诅咒转移
    },

    -- ====================================================================
    -- 7) 棠的誓言碎片 — 第7天, truth章节开始时, plot
    -- ====================================================================
    {
        id       = "plot_tang_vow",
        cardType = "plot",
        priority = 5,
        onceFlag = "seen_tang_vow",
        condition = { all = {
            { min_day = 7 },
            { max_day = 8 },
            { not_flag = "seen_tang_vow" },
            { flag = "morning_day7_seen" },
        }},
        dialogue = {
            { speaker = "旁白", text = "新的碎片补全了闪回画面。终于看清了那个和白夜并肩站着的人——" },
            { speaker = "旁白", text = "容貌和自己相似，但气质截然不同。眉眼凛冽，站姿笔直，像一柄收在鞘中的刀。" },
            { speaker = "旁白", text = "风吹过的时候，她没动。白夜站在她身侧，眼神里全是追随。" },
            { speaker = "白夜", text = "棠……" },
            { speaker = "旁白", text = "暗面裂隙里传出声音。" },
            { speaker = "???",  text = "你想成为棠吗？我可以帮你。" },
            { speaker = "???",  text = "或者，把白夜还回来，你就自由了。" },
            { speaker = "苏柚", text = "（她是我的前世？）" },
        },
        fragment = "frag_07",  -- 碎片·棠的样子
    },

    -- ====================================================================
    -- 8) 棠的篝火记忆 — 第11天, clue
    -- ====================================================================
    {
        id       = "clue_tang_campfire",
        cardType = "clue",
        priority = 5,
        onceFlag = "seen_tang_campfire",
        condition = { all = {
            { min_day = 11 },
            { max_day = 11 },
            { not_flag = "seen_tang_campfire" },
        }},
        dialogue = {
            { speaker = "旁白", text = "碎片的画面——棠站在战场上，剑尖抵着地面，血从手臂滴下来。" },
            { speaker = "旁白", text = "棠坐在篝火边，白夜靠在她肩膀上，她没动，但嘴角有一点很淡的笑。" },
            { speaker = "棠",   text = "我不会让你一个人扛。" },
            { speaker = "旁白", text = "碎片碎了。苏柚看着自己的手，久久没有说话。" },
        },
        fragment = "frag_08",  -- 碎片·篝火约定
    },

    -- ====================================================================
    -- 9) 棠转身那一刻 — 第12天, 倒数第二片碎片, plot
    -- ====================================================================
    {
        id       = "plot_tang_turns_away",
        cardType = "plot",
        priority = 5,
        onceFlag = "seen_tang_turns_away",
        condition = { all = {
            { min_day = 12 },
            { max_day = 12 },
            { not_flag = "seen_tang_turns_away" },
        }},
        dialogue = {
            { speaker = "旁白", text = "倒数第二片碎片。" },
            { speaker = "旁白", text = "碎片里，棠站在白夜面前。白夜已经半跪在地上，诅咒侵蚀了他大半身体，黑色的纹路爬上他的脸。" },
            { speaker = "旁白", text = "棠没有说话。她只是看着他。然后她转身走了。" },
            { speaker = "白夜", text = "棠。" },
            { speaker = "旁白", text = "碎片碎了。苏柚的眼眶红了一下，又忍住了。" },
        },
        fragment = "frag_09",  -- 碎片·背离
    },

    -- ====================================================================
    -- 10) 最后一片碎片 — 第13天, 全部记忆揭晓, clue
    -- ====================================================================
    {
        id       = "clue_final_memory",
        cardType = "clue",
        priority = 1,
        onceFlag = "seen_final_memory",
        condition = { all = {
            { min_day = 13 },
            { max_day = 13 },
            { not_flag = "seen_final_memory" },
        }},
        dialogue = {
            { speaker = "旁白", text = "最后一片碎片。白夜试图拉住她的手——指尖握住了她的手腕，全部记忆向苏柚涌来。" },
            { speaker = "旁白", text = "棠和白夜相爱。诅咒降临。两人本可以各自承担一半，都能活下来。" },
            { speaker = "旁白", text = "但棠没有那样做。她选择了独自面对——和魔王同归于尽。" },
            { speaker = "苏柚", text = "她明明答应了和你一起分担，最后自己和魔王同归于尽。" },
            { speaker = "白夜", text = "我也不明白。想了一千年，还是不明白。" },
            { speaker = "苏柚", text = "所以你找上我。因为她是我的前世。你可以重新来过，把她找回来，然后问她为什么。" },
        },
        fragment = "frag_10",  -- 碎片·真相
    },
}

return M
