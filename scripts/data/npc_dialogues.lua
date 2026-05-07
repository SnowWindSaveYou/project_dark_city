-- ============================================================================
-- npc_dialogues.lua - NPC 对话数据 + 注册逻辑
-- 房东 (fangdong) / 猫 (cat) 的多组随机对话 + 选项功能回调
-- ============================================================================

local NPCManager   = require "NPCManager"
local ResourceBar   = require "ResourceBar"
local AudioManager  = require "AudioManager"

local VFX  -- 延迟加载避免循环依赖
local function getVFX()
    if not VFX then VFX = require "lib.VFX" end
    return VFX
end

local M = {}

-- ============================================================================
-- 房东对话组 (Day 3+): 日常寒暄 → 选项触发资源交换
-- ============================================================================
local FANGDONG_DIALOGUES = {
    -- 对话组 1: 关心租客
    {
        { speaker = "房东", text = "又出去了？最近这附近不太平，早点回来。" },
        { speaker = "房东", text = "对了，你上次说身体不太舒服……" },
        { speaker = "房东", text = "要不要拿点东西给你？我这儿有些用得上的。",
            choices = {
                { label = "用 15 金币换 3 健康", action = "trade", cost = { "money", 15 }, gain = { "health", 3 } },
                { label = "不用了，谢谢", action = "none" },
            }
        },
    },
    -- 对话组 2: 聊到白夜
    {
        { speaker = "房东", text = "说起来，你那个朋友……白夜？" },
        { speaker = "房东", text = "好久没见她出来了呢。她还好吧？" },
        { speaker = "房东", text = "如果你需要什么，说一声就行。",
            choices = {
                { label = "用 20 金币换 2 理智", action = "trade", cost = { "money", 20 }, gain = { "san", 2 } },
                { label = "我再想想", action = "none" },
            }
        },
    },
    -- 对话组 3: 谈天气
    {
        { speaker = "房东", text = "今天天气不错啊……虽然那些雾还是怪怪的。" },
        { speaker = "房东", text = "最近有邻居搬走了，说总看到影子。" },
        { speaker = "房东", text = "你胆子大，这点我挺佩服的。需要帮忙吗？",
            choices = {
                { label = "用 10 金币换 1 胶卷", action = "trade", cost = { "money", 10 }, gain = { "film", 1 } },
                { label = "不了", action = "none" },
            }
        },
    },
    -- 对话组 4: 纯寒暄 (无选项)
    {
        { speaker = "房东", text = "垃圾记得分类啊，上次被投诉了。" },
        { speaker = "房东", text = "……不过我没告诉他们是你。" },
        { speaker = "房东", text = "行了，有事敲门。" },
    },
    -- 对话组 5: 给点东西
    {
        { speaker = "房东", text = "这个月你的房租我就不催了。" },
        { speaker = "房东", text = "看你最近够辛苦的了。" },
        { speaker = "房东", text = "来，拿点东西傍身吧。",
            choices = {
                { label = "用 12 金币换 2 健康", action = "trade", cost = { "money", 12 }, gain = { "health", 2 } },
                { label = "用 18 金币换 1 理智", action = "trade", cost = { "money", 18 }, gain = { "san", 1 } },
                { label = "不用了", action = "none" },
            }
        },
    },
}

-- 资源名称/图标映射
local RES_NAMES = {
    health = "健康", san = "理智", money = "金币",
    film = "胶卷", inspiration = "灵感",
}
local RES_ICONS = {
    health = "❤️", san = "🧠", money = "💰",
    film = "📷", inspiration = "✨",
}

-- 房东选项回调
local function onFangdongChoice(idx, choiceData, npc, G)
    if not choiceData or choiceData.action ~= "trade" then return end

    -- 每日只能交换一次
    if NPCManager.isUsedToday("fangdong") then
        AudioManager.playSFX("card_shake")
        getVFX().spawnBanner("今天已经交换过了", 200, 180, 80, 16, 0.7)
        return
    end

    local costRes, costAmt = choiceData.cost[1], choiceData.cost[2]
    local gainRes, gainAmt = choiceData.gain[1], choiceData.gain[2]

    if ResourceBar.get(costRes) < costAmt then
        AudioManager.playSFX("card_shake")
        getVFX().spawnBanner("资源不足!", 220, 80, 80, 16, 0.7)
        return
    end

    ResourceBar.change(costRes, -costAmt)
    ResourceBar.change(gainRes, gainAmt)
    NPCManager.markUsedToday("fangdong")
    AudioManager.playSFX("resource_gain")

    local icon = RES_ICONS[gainRes] or ""
    local name = RES_NAMES[gainRes] or gainRes
    getVFX().spawnBanner(icon .. " " .. name .. " +" .. gainAmt, 100, 200, 120, 18, 0.8)
end

-- ============================================================================
-- 猫对话组 (随机出没): 治愈系, 恢复少量理智
-- ============================================================================
local CAT_DIALOGUES = {
    -- 对话组 1
    {
        { speaker = "???", text = "（一只橘猫蹲在路边，用尾巴拍着地面。）" },
        { speaker = "???", text = "喵～",
            choices = {
                { label = "摸摸它", action = "pet", gain = { "san", 1 } },
                { label = "蹲下来看它", action = "look" },
            }
        },
    },
    -- 对话组 2
    {
        { speaker = "???", text = "（橘猫打了个哈欠，眯着眼睛看你。）" },
        { speaker = "???", text = "（它蹭了蹭你的脚踝。）",
            choices = {
                { label = "蹲下来陪它一会", action = "pet", gain = { "san", 1 } },
                { label = "给它点吃的", action = "feed", cost = { "money", 5 }, gain = { "san", 2 } },
            }
        },
    },
    -- 对话组 3
    {
        { speaker = "???", text = "（橘猫趴在一张已翻开的卡牌上，呼噜呼噜地响。）" },
        { speaker = "???", text = "（它好像完全不在意周围那些奇怪的影子。）" },
        { speaker = "???", text = "（看着它你觉得稍微安心了一点。）" },
    },
    -- 对话组 4
    {
        { speaker = "???", text = "（橘猫叼着什么东西跑过来。）" },
        { speaker = "???", text = "（是一枚旧硬币。它放在你脚边然后走开了。）",
            choices = {
                { label = "收下礼物", action = "gift" },
                { label = "摸摸它", action = "pet", gain = { "san", 1 } },
            }
        },
    },
    -- 对话组 5
    {
        { speaker = "???", text = "（橘猫用爪子挠了挠你的裤腿。）" },
        { speaker = "???", text = "（它仰头看着你，发出细小的叫声。）" },
        { speaker = "???", text = "喵呜……",
            choices = {
                { label = "陪它玩一会", action = "pet", gain = { "san", 1 } },
                { label = "只是看着它", action = "look" },
            }
        },
    },
}

-- 猫选项回调
local function onCatChoice(idx, choiceData, npc, G)
    if not choiceData then return end

    local action = choiceData.action

    -- "look" 无资源变动，不受每日限制
    if action == "look" then
        getVFX().spawnBanner("🐱 ……", 180, 180, 180, 14, 0.6)
        return
    end

    -- 有资源效果的交互每日只能一次
    if NPCManager.isUsedToday("cat") then
        AudioManager.playSFX("card_shake")
        getVFX().spawnBanner("猫今天已经不想理你了", 200, 180, 80, 16, 0.7)
        return
    end

    if action == "pet" then
        if choiceData.gain then
            ResourceBar.change(choiceData.gain[1], choiceData.gain[2])
        end
        NPCManager.markUsedToday("cat")
        AudioManager.playSFX("resource_gain")
        getVFX().spawnBanner("🐱 被治愈了", 180, 220, 160, 16, 0.8)

    elseif action == "feed" then
        if choiceData.cost then
            if ResourceBar.get(choiceData.cost[1]) < choiceData.cost[2] then
                AudioManager.playSFX("card_shake")
                getVFX().spawnBanner("金币不够…", 220, 80, 80, 16, 0.7)
                return
            end
            ResourceBar.change(choiceData.cost[1], -choiceData.cost[2])
        end
        if choiceData.gain then
            ResourceBar.change(choiceData.gain[1], choiceData.gain[2])
        end
        NPCManager.markUsedToday("cat")
        AudioManager.playSFX("resource_gain")
        getVFX().spawnBanner("🐱 猫吃饱了，舒服地蜷起来", 180, 220, 160, 16, 0.9)

    elseif action == "gift" then
        ResourceBar.change("money", 8)
        NPCManager.markUsedToday("cat")
        AudioManager.playSFX("resource_gain")
        getVFX().spawnBanner("💰 +8 金币（猫的礼物）", 255, 220, 100, 16, 0.8)
    end
end

-- ============================================================================
-- 注册 NPC 类型
-- ============================================================================

function M.registerAll()
    NPCManager.registerNPCType("fangdong", {
        name = "房东",
        texPath = "image/npc_房东_chibi_20260507035549.png",
        dialogues = FANGDONG_DIALOGUES,
        onChoice = onFangdongChoice,
    })

    NPCManager.registerNPCType("cat", {
        name = "猫",
        texPath = "image/npc_猫咪_自然_20260507040343.png",
        dialogues = CAT_DIALOGUES,
        onChoice = onCatChoice,
        spriteScale = 0.5,
    })

    print("[NPCDialogues] Registered all NPC types")
end

return M
