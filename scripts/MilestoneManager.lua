-- ============================================================================
-- MilestoneManager.lua - 里程碑对话查询与触发
-- 根据 hookId + 条件引擎筛选首次触发的里程碑对话, 通过 DialogueSystem 播放
-- 数据从 data/milestone_events.json 加载
-- ============================================================================

local StoryManager   = require "StoryManager"
local DialogueSystem = require "DialogueSystem"

local M = {}

-- ---------------------------------------------------------------------------
-- 数据加载 (从 Lua 模块)
-- ---------------------------------------------------------------------------

local milestoneData_ = require "data.milestone_events"

--- 已加载的事件列表 (按 hookId 分组)
---@type table<string, table[]>
local eventsByHook_ = {}

--- 是否已建立索引
local indexed_ = false

--- 建立按 hookId 分组的索引
local function loadEvents()
    if indexed_ then return end

    local events = milestoneData_.events or {}
    for _, evt in ipairs(events) do
        local hook = evt.hookId
        if hook then
            if not eventsByHook_[hook] then
                eventsByHook_[hook] = {}
            end
            eventsByHook_[hook][#eventsByHook_[hook] + 1] = evt
        end
    end

    local hookCount = 0
    for _ in pairs(eventsByHook_) do hookCount = hookCount + 1 end
    print(string.format("[MilestoneManager] Indexed %d events across %d hooks", #events, hookCount))
    indexed_ = true
end

-- ---------------------------------------------------------------------------
-- 查询: 根据 hookId 返回匹配的最高优先级事件 (或 nil)
-- ---------------------------------------------------------------------------

--- 查询当前 hook 点可触发的里程碑事件
---@param hookId string hook 标识 (如 "enter_dark_world")
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather }
---@return table|nil event 匹配的事件, nil 表示无匹配
function M.query(hookId, sm, ctx)
    loadEvents()

    local pool = eventsByHook_[hookId]
    if not pool then return nil end

    -- 收集所有满足条件的候选事件
    local candidates = {}
    for _, evt in ipairs(pool) do
        if StoryManager.checkCondition(sm, evt.condition, ctx) then
            candidates[#candidates + 1] = evt
        end
    end

    if #candidates == 0 then return nil end

    -- 按 priority 排序 (越小越优先)
    table.sort(candidates, function(a, b) return a.priority < b.priority end)

    -- 取最高优先级 (最小 priority 值)
    local bestPriority = candidates[1].priority
    local topCandidates = {}
    for _, evt in ipairs(candidates) do
        if evt.priority == bestPriority then
            topCandidates[#topCandidates + 1] = evt
        else
            break
        end
    end

    -- 同优先级随机选一个
    return topCandidates[math.random(1, #topCandidates)]
end

-- ---------------------------------------------------------------------------
-- 触发: 启动对话流程
-- ---------------------------------------------------------------------------

--- 尝试触发 hook 点的里程碑对话
--- 如果有匹配的事件, 启动 DialogueSystem 对话并在完成后调用 onComplete
--- 如果无匹配, 立即调用 onComplete
---@param hookId string hook 标识
---@param sm table StoryManager 实例
---@param ctx table 上下文 { dayCount, weather, resourceBar }
---@param onComplete function|nil 对话完成后回调 (无论是否触发对话都会调用)
---@return boolean triggered 是否触发了对话
function M.tryTrigger(hookId, sm, ctx, onComplete)
    local event = M.query(hookId, sm, ctx)
    if not event then
        if onComplete then onComplete() end
        return false
    end

    print(string.format("[MilestoneManager] Triggering milestone: %s (hook=%s)", event.id, hookId))

    -- 设置 onceFlag (防止重复触发)
    if event.onceFlag then
        StoryManager.setFlag(sm, event.onceFlag)
    end

    -- 选择回调 (里程碑事件支持 choiceEffects)
    local onChoiceSelected = nil
    if event.choiceEffects then
        onChoiceSelected = function(index, choiceData)
            local choiceId = choiceData and choiceData.choiceId
            if choiceId and event.choiceEffects[choiceId] then
                local eff = event.choiceEffects[choiceId]
                print(string.format("[MilestoneManager] Choice: %s → %s", event.id, choiceId))
                StoryManager.applyChoiceEffects(sm, eff, ctx.resourceBar)
            end
        end
    end

    -- 对话完成回调 (碎片收集 + 外部回调)
    local onDialogueComplete = function()
        -- 碎片收集
        if event.fragment then
            local isNew = StoryManager.addFragment(sm, event.fragment)
            if isNew then
                print(string.format("[MilestoneManager] Fragment from milestone: %s → %s",
                    event.id, event.fragment))
            end
        end
        -- 外部回调
        if onComplete then
            onComplete()
        end
    end

    -- 启动对话
    DialogueSystem.start(event.dialogue, nil, onDialogueComplete, onChoiceSelected)
    return true
end

--- 重置索引状态 (游戏重启时调用)
function M.reset()
    eventsByHook_ = {}
    indexed_ = false
    print("[MilestoneManager] Reset")
end

return M
