-- ============================================================================
-- StoryEventManager.lua - 剧情事件查询与触发
-- 根据翻牌类型 + 条件引擎筛选可用剧情事件，通过 DialogueSystem 播放
-- ============================================================================

local StoryEvents   = require "StoryEvents"
local StoryManager  = require "StoryManager"
local DialogueSystem = require "DialogueSystem"

local M = {}

-- ---------------------------------------------------------------------------
-- 查询: 根据翻牌类型返回匹配的最高优先级事件 (或 nil)
-- ---------------------------------------------------------------------------

--- 查询当前可触发的剧情事件
---@param cardType string "plot" | "clue"
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@return table|nil event 匹配的事件, nil 表示无匹配
function M.queryEvent(cardType, sm, ctx)
    -- 收集所有满足条件的候选事件
    local candidates = {}
    for _, evt in ipairs(StoryEvents.EVENTS) do
        if evt.cardType == cardType then
            if StoryManager.checkCondition(sm, evt.condition, ctx) then
                candidates[#candidates + 1] = evt
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    -- 按 priority 排序 (越小越优先)
    table.sort(candidates, function(a, b) return a.priority < b.priority end)

    -- 取最高优先级 (最小 priority 值)
    local bestPriority = candidates[1].priority
    local topCandidates = {}
    for _, evt in ipairs(candidates) do
        if evt.priority == bestPriority then
            topCandidates[#topCandidates + 1] = evt
        else
            break  -- 已排序, 后续 priority 更大
        end
    end

    -- 同优先级随机选一个
    local pick = topCandidates[math.random(1, #topCandidates)]
    print(string.format("[StoryEventManager] Matched event: %s (priority=%d, candidates=%d)",
        pick.id, pick.priority, #candidates))
    return pick
end

-- ---------------------------------------------------------------------------
-- 触发: 启动对话流程, 处理选择和碎片
-- ---------------------------------------------------------------------------

--- 触发剧情事件 (启动 DialogueSystem 对话)
---@param event table StoryEvents 中的事件数据
---@param sm table StoryManager 实例
---@param resourceBar table ResourceBar 模块 (用于 applyChoiceEffects)
---@param onComplete function 对话结束后回调
function M.triggerEvent(event, sm, resourceBar, onComplete)
    print(string.format("[StoryEventManager] Triggering event: %s", event.id))

    -- 设置 onceFlag (防止重复触发)
    if event.onceFlag then
        StoryManager.setFlag(sm, event.onceFlag)
    end

    -- 选择回调
    local onChoiceSelected = nil
    if event.choiceEffects then
        onChoiceSelected = function(index, choiceData)
            local choiceId = choiceData and choiceData.choiceId
            if choiceId and event.choiceEffects[choiceId] then
                local eff = event.choiceEffects[choiceId]
                print(string.format("[StoryEventManager] Choice selected: %s → %s", event.id, choiceId))
                StoryManager.applyChoiceEffects(sm, eff, resourceBar)
            end
        end
    end

    -- 对话完成回调 (碎片收集 + 外部回调)
    local onDialogueComplete = function()
        -- 碎片收集
        if event.fragment then
            local isNew = StoryManager.addFragment(sm, event.fragment)
            if isNew then
                print(string.format("[StoryEventManager] Fragment collected from event: %s → %s",
                    event.id, event.fragment))
            end
        end
        -- 外部回调
        if onComplete then
            onComplete()
        end
    end

    -- 启动对话 (portraitTexPath 传 nil, 使用默认)
    DialogueSystem.start(event.dialogue, nil, onDialogueComplete, onChoiceSelected)
end

return M
