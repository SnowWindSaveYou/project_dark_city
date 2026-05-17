-- ============================================================================
-- StoryEventManager.lua - 剧情事件查询与触发
-- 根据翻牌类型 + 条件引擎筛选可用剧情事件，通过 DialogueSystem 播放
-- ============================================================================

local StoryEvents      = require "StoryEvents"
local StoryManager     = require "StoryManager"
local DialogueSystem   = require "DialogueSystem"
local MilestoneManager = require "MilestoneManager"

local M = {}

-- ---------------------------------------------------------------------------
-- 每日开场事件 (从 Lua 模块加载)
-- ---------------------------------------------------------------------------

local morningData_ = require "data.morning_events"

-- ---------------------------------------------------------------------------
-- 每日中段事件 (daily_goal 触发，从 Lua 模块加载)
-- ---------------------------------------------------------------------------

local midDayData_ = require "data.mid_day_events"

---@type table<string, table[]>
local midDayByHook_ = {}
local midDayIndexed_ = false

local function loadMidDayEvents()
    if midDayIndexed_ then return end
    local events = midDayData_.events or {}
    for _, evt in ipairs(events) do
        local hook = evt.hookId
        if hook then
            if not midDayByHook_[hook] then midDayByHook_[hook] = {} end
            midDayByHook_[hook][#midDayByHook_[hook] + 1] = evt
        end
    end
    midDayIndexed_ = true
    print(string.format("[StoryEventManager] Mid-day events indexed: %d total", #events))
end

---@type table[]
local morningEvents_ = morningData_.events or {}

local function loadMorningEvents()
    -- Lua require 已在模块加载时完成, 此函数保留兼容性
end

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
-- 查询: 每日开场事件
-- ---------------------------------------------------------------------------

--- 查询当前可触发的每日开场事件
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@return table|nil event 匹配的事件, nil 表示无匹配
function M.queryMorningEvent(sm, ctx)
    loadMorningEvents()

    local candidates = {}
    for _, evt in ipairs(morningEvents_) do
        if StoryManager.checkCondition(sm, evt.condition, ctx) then
            candidates[#candidates + 1] = evt
        end
    end

    if #candidates == 0 then return nil end

    -- 按 priority 排序 (越小越优先)
    table.sort(candidates, function(a, b) return a.priority < b.priority end)

    local bestPriority = candidates[1].priority
    local topCandidates = {}
    for _, evt in ipairs(candidates) do
        if evt.priority == bestPriority then
            topCandidates[#topCandidates + 1] = evt
        else
            break
        end
    end

    local pick = topCandidates[math.random(1, #topCandidates)]
    print(string.format("[StoryEventManager] Morning event matched: %s (priority=%d)",
        pick.id, pick.priority))
    return pick
end

--- 尝试触发每日开场事件
--- 如果有匹配的事件, 启动 DialogueSystem 对话并在完成后调用 onComplete
--- 如果无匹配, 立即调用 onComplete
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@param onComplete function|nil 对话完成后回调
---@return boolean triggered 是否触发了对话
function M.tryMorningEvent(sm, ctx, onComplete)
    local event = M.queryMorningEvent(sm, ctx)
    if not event then
        if onComplete then onComplete() end
        return false
    end

    print(string.format("[StoryEventManager] Triggering morning event: %s", event.id))

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
                print(string.format("[StoryEventManager] Morning choice: %s → %s", event.id, choiceId))
                StoryManager.applyChoiceEffects(sm, eff, nil)
            end
        end
    end

    -- 对话完成回调
    local onDialogueComplete = function()
        if event.fragment then
            local isNew = StoryManager.addFragment(sm, event.fragment)
            if isNew then
                print(string.format("[StoryEventManager] Fragment from morning: %s → %s",
                    event.id, event.fragment))
            end
        end
        if onComplete then onComplete() end
    end

    DialogueSystem.start(event.dialogue, nil, onDialogueComplete, onChoiceSelected)
    return true
end

-- ---------------------------------------------------------------------------
-- 触发: 启动对话流程, 处理选择和碎片
-- ---------------------------------------------------------------------------

--- 触发剧情事件 (启动 DialogueSystem 对话)
---@param event table StoryEvents 中的事件数据
---@param sm table StoryManager 实例
---@param resourceBar table ResourceBar 模块 (用于 applyChoiceEffects)
---@param onComplete function 对话结束后回调
---@param ctx table|nil 上下文 { dayCount, weather } (用于里程碑触发)
function M.triggerEvent(event, sm, resourceBar, onComplete, ctx)
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
                local wasSleeping = sm.sleep_days_left > 0
                StoryManager.applyChoiceEffects(sm, eff, resourceBar)
                -- 里程碑: 白夜沉睡 hook (选择导致沉睡时)
                if not wasSleeping and sm.sleep_days_left > 0 then
                    local msCtx = { dayCount = ctx and ctx.dayCount or 1 }
                    MilestoneManager.tryTrigger("baiye_sleep", sm, msCtx, nil)
                end
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
                -- 里程碑: 碎片收集 hook
                local msCtx = { dayCount = ctx and ctx.dayCount or 1 }
                MilestoneManager.tryTrigger("fragment_collect", sm, msCtx, nil)
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

-- ---------------------------------------------------------------------------
-- 每日夜谈事件 (一天结束时触发, 从 Lua 模块加载)
-- ---------------------------------------------------------------------------

local eveningData_ = require "data.evening_events"

---@type table[]
local eveningEvents_ = eveningData_.events or {}

--- 查询当前可触发的夜谈事件
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@return table|nil event 匹配的事件, nil 表示无匹配
function M.queryEveningEvent(sm, ctx)
    local candidates = {}
    for _, evt in ipairs(eveningEvents_) do
        if StoryManager.checkCondition(sm, evt.condition, ctx) then
            candidates[#candidates + 1] = evt
        end
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b) return a.priority < b.priority end)

    local bestPriority = candidates[1].priority
    local topCandidates = {}
    for _, evt in ipairs(candidates) do
        if evt.priority == bestPriority then
            topCandidates[#topCandidates + 1] = evt
        else
            break
        end
    end

    local pick = topCandidates[math.random(1, #topCandidates)]
    print(string.format("[StoryEventManager] Evening event matched: %s (priority=%d)",
        pick.id, pick.priority))
    return pick
end

--- 尝试触发每日夜谈事件
--- 玩家点击结束一天时调用（在 undeal 动画之前）
--- 如果有匹配的事件, 启动 DialogueSystem 并在完成后调用 onComplete
--- 如果无匹配, 立即调用 onComplete
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@param onComplete function|nil 对话完成后回调
---@return boolean triggered 是否触发了对话
function M.tryEveningEvent(sm, ctx, onComplete)
    local event = M.queryEveningEvent(sm, ctx)
    if not event then
        if onComplete then onComplete() end
        return false
    end

    print(string.format("[StoryEventManager] Triggering evening event: %s", event.id))

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
                print(string.format("[StoryEventManager] Evening choice: %s → %s", event.id, choiceId))
                StoryManager.applyChoiceEffects(sm, eff, nil)
            end
        end
    end

    local onDialogueComplete = function()
        if event.fragment then
            local isNew = StoryManager.addFragment(sm, event.fragment)
            if isNew then
                print(string.format("[StoryEventManager] Fragment from evening: %s → %s",
                    event.id, event.fragment))
            end
        end
        if onComplete then onComplete() end
    end

    DialogueSystem.start(event.dialogue, nil, onDialogueComplete, onChoiceSelected)
    return true
end

-- ---------------------------------------------------------------------------
-- 每日中段事件: daily_goal 触发
-- ---------------------------------------------------------------------------

--- 查询当日任务完成时可触发的中段剧情事件
--- 优先匹配地点专属 hookId, 无匹配时降级到通用兜底 hookId
---@param location string  完成任务的地点 (如 "hospital", "park")
---@param sm table         StoryManager 实例
---@param ctx table        上下文 { dayCount, weather }
---@return table|nil       匹配的事件, nil 表示无需触发
function M.queryMidEvent(location, sm, ctx)
    loadMidDayEvents()

    -- 内部查询函数: 从指定 hookId 池里找优先级最高的匹配事件
    local function pickFromHook(hookId)
        local pool = midDayByHook_[hookId]
        if not pool then return nil end

        local candidates = {}
        for _, evt in ipairs(pool) do
            if StoryManager.checkCondition(sm, evt.condition, ctx) then
                candidates[#candidates + 1] = evt
            end
        end
        if #candidates == 0 then return nil end

        table.sort(candidates, function(a, b) return a.priority < b.priority end)
        local best = candidates[1].priority
        local top = {}
        for _, evt in ipairs(candidates) do
            if evt.priority == best then top[#top + 1] = evt else break end
        end
        return top[math.random(1, #top)]
    end

    -- 1. 地点专属
    local specific = pickFromHook("daily_goal_" .. location)
    if specific then
        print(string.format("[StoryEventManager] Mid-day event (specific): %s (location=%s)", specific.id, location))
        return specific
    end

    -- 2. 通用兜底
    local fallback = pickFromHook("daily_goal_any")
    if fallback then
        print(string.format("[StoryEventManager] Mid-day event (fallback): %s", fallback.id))
        return fallback
    end

    return nil
end

--- 尝试触发每日中段事件
--- 完成当日任务（CardManager.checkArrival 返回 true）后调用
---@param location string         完成任务的地点
---@param sm table                StoryManager 实例
---@param ctx table               上下文 { dayCount, weather, resourceBar }
---@param onComplete function|nil 对话完成或无事件时的回调
---@return boolean triggered      是否触发了对话
function M.tryMidEvent(location, sm, ctx, onComplete)
    local event = M.queryMidEvent(location, sm, ctx)
    if not event then
        if onComplete then onComplete() end
        return false
    end

    print(string.format("[StoryEventManager] Triggering mid-day event: %s", event.id))

    -- 设置 onceFlag
    if event.onceFlag then
        StoryManager.setFlag(sm, event.onceFlag)
    end

    -- 选择回调
    local onChoiceSelected = nil
    if event.choiceEffects then
        onChoiceSelected = function(index, choiceData)
            local choiceId = choiceData and choiceData.choiceId
            if choiceId and event.choiceEffects[choiceId] then
                StoryManager.applyChoiceEffects(sm, event.choiceEffects[choiceId], ctx.resourceBar)
            end
        end
    end

    local onDialogueComplete = function()
        if event.fragment then
            StoryManager.addFragment(sm, event.fragment)
        end
        if onComplete then onComplete() end
    end

    DialogueSystem.start(event.dialogue, nil, onDialogueComplete, onChoiceSelected)
    return true
end

-- ---------------------------------------------------------------------------
-- 线索翻牌事件池 (明面/暗面)
-- ---------------------------------------------------------------------------

--- 从指定事件池中按权重随机选取满足条件的事件
---@param pool table[] 事件池 (含 condition/weight 字段)
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@return table|nil event 选中的事件, nil=无满足条件的事件
local function pickWeightedEvent(pool, sm, ctx)
    local candidates = {}
    local totalWeight = 0
    for _, evt in ipairs(pool) do
        if StoryManager.checkCondition(sm, evt.condition, ctx) then
            candidates[#candidates + 1] = evt
            totalWeight = totalWeight + (evt.weight or 10)
        end
    end
    if #candidates == 0 then return nil end

    local roll = math.random() * totalWeight
    local acc = 0
    for _, evt in ipairs(candidates) do
        acc = acc + (evt.weight or 10)
        if roll <= acc then return evt end
    end
    return candidates[#candidates]
end

local StoryConfig = require "StoryConfig"

--- 从明面线索事件池随机选一个满足条件的事件
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@return table|nil
function M.pickClueEvent(sm, ctx)
    return pickWeightedEvent(StoryConfig.CLUE_EVENTS, sm, ctx or {})
end

--- 从暗面线索事件池随机选一个满足条件的事件
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@return table|nil
function M.pickDarkClueEvent(sm, ctx)
    return pickWeightedEvent(StoryConfig.DARK_CLUE_EVENTS, sm, ctx or {})
end

--- 应用线索事件效果: 设置 flags、收集线索
--- 返回 { clue_name, is_new_clue, text }
---@param event table 线索事件 (来自 CLUE_EVENTS / DARK_CLUE_EVENTS)
---@param sm table StoryManager 实例
---@return table result
function M.applyClueEvent(event, sm)
    local result = { clue_name = "", is_new_clue = false, text = event.text or "" }

    -- 设置 flags
    if event.set_flags then
        for _, flag in ipairs(event.set_flags) do
            StoryManager.setFlag(sm, flag)
        end
    end

    -- 收集线索
    local clueId = event.clue_id
    if clueId and clueId ~= "" then
        local isNew = StoryManager.collectClue(sm, clueId)
        local info = StoryConfig.CLUES[clueId]
        result.clue_name  = info and info.name or clueId
        result.is_new_clue = isNew
    end

    return result
end

-- ---------------------------------------------------------------------------
-- 重置状态 (游戏重启时调用)
-- ---------------------------------------------------------------------------
function M.reset()
    -- morningEvents_ 从 require 加载, 无需清空
    -- 重置中段事件索引，使下一局重新计算条件
    midDayByHook_ = {}
    midDayIndexed_ = false
    print("[StoryEventManager] Reset")
end

return M
