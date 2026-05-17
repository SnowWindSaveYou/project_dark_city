-- ============================================================================
-- StoryManager.lua - 故事系统核心状态管理
-- 白夜数据(trust/power/sleep) + 碎片追踪 + flag系统 + 条件引擎
-- 不依赖 ResourceBar/GameFlow, 通过参数传入避免循环依赖
-- ============================================================================

local StoryConfig = require "StoryConfig"

local M = {}

-- ---------------------------------------------------------------------------
-- 构造 / 重置
-- ---------------------------------------------------------------------------

--- 创建新的故事管理器实例
---@return table storyMgr
function M.new()
    local sm = {
        -- 白夜数据
        baiye_trust      = 0,    -- 信任度 0-10
        baiye_power      = 0,    -- 蓄积力量 0-5
        sleep_days_left  = 0,    -- 沉睡剩余天数, >0 表示沉睡中

        -- flag 系统 (key → true)
        flags = {},

        -- 碎片收集 (fragId → true)
        fragments = {},

        -- 实物线索收集 (clueId → true)
        clues = {},

        -- 当前章节 ID
        currentChapter = "awakening",
    }
    print("[StoryManager] Initialized")
    return sm
end

--- 重置全部状态 (游戏重启时调用)
---@param sm table
function M.reset(sm)
    sm.baiye_trust     = 0
    sm.baiye_power     = 0
    sm.sleep_days_left = 0
    sm.flags           = {}
    sm.fragments       = {}
    sm.clues           = {}
    sm.currentChapter  = "awakening"
    print("[StoryManager] Reset")
end

-- ---------------------------------------------------------------------------
-- 白夜属性
-- ---------------------------------------------------------------------------

--- 修改信任度 (clamp 0-10)
---@param sm table
---@param amount integer 正值增加, 负值减少
function M.addTrust(sm, amount)
    if amount == 0 then return end
    local old = sm.baiye_trust
    sm.baiye_trust = math.max(0, math.min(10, sm.baiye_trust + amount))
    if old ~= sm.baiye_trust then
        print(string.format("[StoryManager] Trust: %d → %d", old, sm.baiye_trust))
    end
end

--- 修改蓄积力量 (clamp 0-5)
---@param sm table
---@param amount integer
function M.addPower(sm, amount)
    if amount == 0 then return end
    sm.baiye_power = math.max(0, math.min(5, sm.baiye_power + amount))
end

--- 消耗力量, 成功返回 true
---@param sm table
---@param cost integer
---@return boolean
function M.usePower(sm, cost)
    if sm.baiye_power >= cost then
        sm.baiye_power = sm.baiye_power - cost
        return true
    end
    return false
end

--- 每日结算: 沉睡倒计时 -1
---@param sm table
function M.tickSleep(sm)
    if sm.sleep_days_left > 0 then
        sm.sleep_days_left = sm.sleep_days_left - 1
        if sm.sleep_days_left <= 0 then
            print("[StoryManager] Baiye woke up from sleep")
        end
    end
end

--- 白夜是否可用 (非沉睡且未被封印)
---@param sm table
---@return boolean
function M.isBaiyeAvailable(sm)
    return sm.sleep_days_left <= 0 and not sm.flags["ending_seal"]
end

-- ---------------------------------------------------------------------------
-- Flag 系统
-- ---------------------------------------------------------------------------

--- 设置 flag
---@param sm table
---@param flag string
function M.setFlag(sm, flag)
    if not sm.flags[flag] then
        sm.flags[flag] = true
        print("[StoryManager] Flag set: " .. flag)
    end
end

--- 查询 flag
---@param sm table
---@param flag string
---@return boolean
function M.hasFlag(sm, flag)
    return sm.flags[flag] == true
end

-- ---------------------------------------------------------------------------
-- 碎片系统
-- ---------------------------------------------------------------------------

--- 收集碎片
---@param sm table
---@param fragId string
---@return boolean isNew 是否为新收集的碎片
function M.addFragment(sm, fragId)
    if sm.fragments[fragId] then
        return false
    end
    sm.fragments[fragId] = true
    local count = M.getFragmentCount(sm)
    print(string.format("[StoryManager] Fragment collected: %s (total: %d/10)", fragId, count))
    return true
end

--- 已收集碎片总数
---@param sm table
---@return integer
function M.getFragmentCount(sm)
    local count = 0
    for _ in pairs(sm.fragments) do
        count = count + 1
    end
    return count
end

--- 是否已收集某碎片
---@param sm table
---@param fragId string
---@return boolean
function M.hasFragment(sm, fragId)
    return sm.fragments[fragId] == true
end

-- ---------------------------------------------------------------------------
-- 实物线索系统
-- ---------------------------------------------------------------------------

--- 收集实物线索
---@param sm table
---@param clueId string
---@return boolean isNew 是否为新收集的线索
function M.collectClue(sm, clueId)
    if sm.clues[clueId] then
        return false
    end
    sm.clues[clueId] = true
    local count = M.getClueCount(sm)
    print(string.format("[StoryManager] Clue collected: %s (total: %d)", clueId, count))
    return true
end

--- 是否已收集某线索
---@param sm table
---@param clueId string
---@return boolean
function M.hasClue(sm, clueId)
    return sm.clues[clueId] == true
end

--- 已收集线索总数
---@param sm table
---@return integer
function M.getClueCount(sm)
    local count = 0
    for _ in pairs(sm.clues) do count = count + 1 end
    return count
end

--- 获取某分类下已收集的线索列表
--- 返回 [{ id, info }] 格式 (与 Godot get_clues_by_category 对齐)
---@param sm table
---@param category string
---@return table[]
function M.getCluesByCategory(sm, category)
    local result = {}
    for clueId in pairs(sm.clues) do
        local info = StoryConfig.CLUES[clueId]
        if info and info.category == category then
            result[#result + 1] = { id = clueId, info = info }
        end
    end
    -- 按 name 排序保证稳定显示
    table.sort(result, function(a, b) return a.info.name < b.info.name end)
    return result
end

--- 获取已收集线索中存在的分类列表 (去重, 稳定排序)
---@param sm table
---@return string[]
function M.getClueCategories(sm)
    local seen = {}
    local cats = {}
    for clueId in pairs(sm.clues) do
        local info = StoryConfig.CLUES[clueId]
        if info then
            local cat = info.category
            if not seen[cat] then
                seen[cat] = true
                cats[#cats + 1] = cat
            end
        end
    end
    table.sort(cats)
    return cats
end

--- 获取所有已收集线索列表 (按分类再按名称排序)
--- 返回 [{ id, info }] 格式
---@param sm table
---@return table[]
function M.getAllClues(sm)
    local result = {}
    for clueId in pairs(sm.clues) do
        local info = StoryConfig.CLUES[clueId]
        if info then
            result[#result + 1] = { id = clueId, info = info }
        end
    end
    table.sort(result, function(a, b)
        if a.info.category ~= b.info.category then
            return a.info.category < b.info.category
        end
        return a.info.name < b.info.name
    end)
    return result
end

-- ---------------------------------------------------------------------------
-- 章节管理
-- ---------------------------------------------------------------------------

--- 根据当前天数更新章节
---@param sm table
---@param dayCount integer
function M.updateChapter(sm, dayCount)
    for _, ch in ipairs(StoryConfig.CHAPTERS) do
        if dayCount >= ch.dayRange[1] and dayCount <= ch.dayRange[2] then
            if sm.currentChapter ~= ch.id then
                print(string.format("[StoryManager] Chapter: %s → %s (%s)",
                    sm.currentChapter, ch.id, ch.name))
                sm.currentChapter = ch.id
            end
            return
        end
    end
    -- 超出所有章节范围, 保持 finale
    if sm.currentChapter ~= "finale" then
        sm.currentChapter = "finale"
    end
end

-- ---------------------------------------------------------------------------
-- 动态天数
-- ---------------------------------------------------------------------------

--- 获取当前最大天数 (碎片足够则延展)
---@param sm table
---@return integer
function M.getMaxDays(sm)
    if M.getFragmentCount(sm) >= StoryConfig.EXTEND_THRESHOLD then
        return StoryConfig.EXTENDED_DAYS
    end
    return StoryConfig.BASE_DAYS
end

-- ---------------------------------------------------------------------------
-- 条件引擎 (递归)
-- ---------------------------------------------------------------------------

--- 检查条件是否满足
---@param sm table storyMgr 实例
---@param cond table|nil 条件表, nil 表示无条件(总是通过)
---@param ctx table 上下文 { dayCount, weather }
---@return boolean
function M.checkCondition(sm, cond, ctx)
    if cond == nil then return true end

    -- 组合: all (AND)
    if cond.all then
        for _, sub in ipairs(cond.all) do
            if not M.checkCondition(sm, sub, ctx) then
                return false
            end
        end
        return true
    end

    -- 组合: any (OR)
    if cond.any then
        for _, sub in ipairs(cond.any) do
            if M.checkCondition(sm, sub, ctx) then
                return true
            end
        end
        return false
    end

    -- 组合: not (NOT)
    if cond["not"] then
        return not M.checkCondition(sm, cond["not"], ctx)
    end

    -- 原子: min_day
    if cond.min_day then
        return (ctx.dayCount or 0) >= cond.min_day
    end

    -- 原子: max_day (天数上限)
    if cond.max_day then
        return (ctx.dayCount or 0) <= cond.max_day
    end

    -- 原子: flag
    if cond.flag then
        return M.hasFlag(sm, cond.flag)
    end

    -- 原子: not_flag
    if cond.not_flag then
        return not M.hasFlag(sm, cond.not_flag)
    end

    -- 原子: min_trust
    if cond.min_trust then
        return sm.baiye_trust >= cond.min_trust
    end

    -- 原子: min_fragments
    if cond.min_fragments then
        return M.getFragmentCount(sm) >= cond.min_fragments
    end

    -- 原子: has_clue
    if cond.has_clue then
        return M.hasClue(sm, cond.has_clue)
    end

    -- 原子: min_clues
    if cond.min_clues then
        return M.getClueCount(sm) >= cond.min_clues
    end

    -- 原子: baiye_available
    if cond.baiye_available ~= nil then
        return M.isBaiyeAvailable(sm) == cond.baiye_available
    end

    -- 原子: max_trust (信任度上限)
    if cond.max_trust then
        return sm.baiye_trust <= cond.max_trust
    end

    -- 原子: chapter (当前章节匹配)
    if cond.chapter then
        return sm.currentChapter == cond.chapter
    end

    -- 原子: weather
    if cond.weather then
        return (ctx.weather or "") == cond.weather
    end

    -- 未知条件类型, 默认通过
    print("[StoryManager] WARNING: Unknown condition type in: " .. tostring(cond))
    return true
end

-- ---------------------------------------------------------------------------
-- 效果结算
-- ---------------------------------------------------------------------------

--- 应用选择效果 (由外部调用, 传入 resourceBar 避免循环依赖)
---@param sm table storyMgr
---@param choice table 选择数据 { effects, set_flags, baiye_trust_change, trigger_sleep }
---@param resourceBar table ResourceBar 模块 (可选)
function M.applyChoiceEffects(sm, choice, resourceBar)
    if not choice then return end

    -- 资源效果
    if choice.effects and resourceBar then
        for key, delta in pairs(choice.effects) do
            resourceBar.change(key, delta)
        end
    end

    -- 设置 flags
    if choice.set_flags then
        if type(choice.set_flags) == "table" then
            -- 支持数组格式 {"flag1", "flag2"} 和字典格式 {flag1=true}
            for k, v in pairs(choice.set_flags) do
                if type(k) == "number" then
                    -- 数组格式: value 是 flag 名
                    M.setFlag(sm, v)
                else
                    -- 字典格式: key 是 flag 名
                    if v then M.setFlag(sm, k) end
                end
            end
        end
    end

    -- 信任度变化
    if choice.baiye_trust_change and choice.baiye_trust_change ~= 0 then
        M.addTrust(sm, choice.baiye_trust_change)
    end

    -- 触发沉睡
    if choice.trigger_sleep and choice.trigger_sleep > 0 then
        sm.sleep_days_left = choice.trigger_sleep
        print(string.format("[StoryManager] Baiye enters sleep for %d days", choice.trigger_sleep))
    end
end

return M
