-- ============================================================================
-- CardManager.lua - 日程卡 + 传闻卡 数据管理
-- 负责生成、状态追踪、完成检测、日结算
-- ============================================================================

local Card = require "Card"
local ResourceBar = require "ResourceBar"

local M = {}

-- ---------------------------------------------------------------------------
-- 日程卡模板 (根据地点生成描述)
-- ---------------------------------------------------------------------------
local SCHEDULE_TEMPLATES = {
    -- 普通地点 (可作为日程目标)
    company     = { verb = "去公司上班",     reward = { "money", 10 } },
    school      = { verb = "去学校上课",     reward = { "money",  8 } },
    park        = { verb = "去公园散步",     reward = { "san",    1 } },
    alley       = { verb = "穿过小巷",       reward = { "money",  8 } },
    station     = { verb = "去车站接人",     reward = { "money",  6 } },
    hospital    = { verb = "去医院看病",     reward = { "san",    1 } },
    library     = { verb = "去图书馆学习",   reward = { "order",  1 } },
    bank        = { verb = "去银行办事",     reward = { "money", 12 } },
    -- 商店地点
    convenience = { verb = "去便利店购物",   reward = { "money",  5 } },
    -- 地标地点 (也可作为日程目标，且走到地标区域是安全的)
    church      = { verb = "去教堂祈祷",     reward = { "san",    1 } },
    police      = { verb = "去警察局报案",   reward = { "order",  1 } },
    shrine      = { verb = "去神社参拜",     reward = { "san",    1 } },
}

-- ---------------------------------------------------------------------------
-- 传闻模板
-- ---------------------------------------------------------------------------
local RUMOR_SAFE_TEXTS = {
    "今天%s很平静",
    "%s附近没有异常",
    "听说%s今天很安全",
}

local RUMOR_DANGER_TEXTS = {
    "%s有脏东西",
    "别去%s，有危险",
    "听说%s闹鬼了",
}

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local state = {
    schedules = {},        -- 当天日程卡列表
    rumors = {},           -- 当天传闻卡列表
    deferredFromYesterday = nil,  -- 前一天推迟的日程 (最多1张)
}

-- ---------------------------------------------------------------------------
-- 生成: 每天开始时调用
-- ---------------------------------------------------------------------------

--- 从棋盘中收集所有可用地点 (排除 home)
local function collectBoardLocations(board)
    local locations = {}
    local seen = {}
    for row = 1, 5 do
        if board.cards[row] then
            for col = 1, 5 do
                local card = board.cards[row][col]
                if card and card.location and card.location ~= "home" then
                    if not seen[card.location] then
                        seen[card.location] = true
                        locations[#locations + 1] = {
                            location = card.location,
                            row = card.row,
                            col = card.col,
                        }
                    end
                end
            end
        end
    end
    return locations
end

--- 洗牌工具
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

--- 创建一张日程卡
local function createSchedule(location)
    local locInfo = Card.LOCATION_INFO[location]
    local template = SCHEDULE_TEMPLATES[location]
    if not locInfo or not template then return nil end

    return {
        location = location,
        label = template.verb,
        icon = locInfo.icon,
        reward = { template.reward[1], template.reward[2] },
        status = "pending",  -- "pending" | "completed" | "deferred"
    }
end

--- 创建一张传闻卡
local function createRumor(location, isSafe)
    local locInfo = Card.LOCATION_INFO[location]
    if not locInfo then return nil end

    local templates = isSafe and RUMOR_SAFE_TEXTS or RUMOR_DANGER_TEXTS
    local textTemplate = templates[math.random(1, #templates)]
    local text = string.format(textTemplate, locInfo.label)

    return {
        location = location,
        label = locInfo.label,
        icon = locInfo.icon,
        isSafe = isSafe,
        text = text,
    }
end

--- 预选今天日程所需的地点 (在 Board.generateCards 之前调用)
--- 返回地点列表，Board 需保证这些地点出现在棋盘上
---@return string[] requiredLocations
function M.preSelectLocations()
    -- 收集所有可用的日程地点
    local allLocs = {}
    for loc, _ in pairs(SCHEDULE_TEMPLATES) do
        allLocs[#allLocs + 1] = loc
    end
    -- 洗牌
    for i = #allLocs, 2, -1 do
        local j = math.random(1, i)
        allLocs[i], allLocs[j] = allLocs[j], allLocs[i]
    end

    local required = {}
    local used = {}

    -- 昨天推迟的日程地点 (不占新日程名额，额外追加)
    if state.deferredFromYesterday then
        required[#required + 1] = state.deferredFromYesterday.location
        used[state.deferredFromYesterday.location] = true
    end

    -- 始终选 3 个新地点 (推迟的不算在内)
    local needed = 3
    for _, loc in ipairs(allLocs) do
        if needed <= 0 then break end
        if not used[loc] then
            required[#required + 1] = loc
            used[loc] = true
            needed = needed - 1
        end
    end

    -- 缓存预选结果，generateDaily 时使用
    state.preSelected = required
    print(string.format("[CardManager] Pre-selected locations: %s", table.concat(required, ", ")))
    return required
end

--- 每天开始时生成日程卡和传闻卡
--- 日程地点优先使用 preSelectLocations() 预选的结果，保证日程目标一定在棋盘上
---@param board BoardData
function M.generateDaily(board)
    -- 清空当天数据
    state.schedules = {}
    state.rumors = {}

    -- 使用预选地点生成日程卡 (由 preSelectLocations 在 Board.generateCards 前调用)
    local preSelected = state.preSelected or {}

    -- 加入前一天推迟的日程 (最多1张, 其地点已在 preSelected 中)
    local deferredCount = 0
    if state.deferredFromYesterday then
        state.deferredFromYesterday.status = "pending"
        state.schedules[1] = state.deferredFromYesterday
        state.deferredFromYesterday = nil
        deferredCount = 1
    end

    -- 从预选地点中生成剩余日程卡 (3 个新日程 + 推迟的)
    local maxSchedules = 3 + deferredCount
    local usedLocations = {}
    for _, s in ipairs(state.schedules) do
        usedLocations[s.location] = true
    end

    for _, loc in ipairs(preSelected) do
        if #state.schedules >= maxSchedules then break end
        if not usedLocations[loc] and SCHEDULE_TEMPLATES[loc] then
            local sched = createSchedule(loc)
            if sched then
                state.schedules[#state.schedules + 1] = sched
                usedLocations[sched.location] = true
            end
        end
    end

    -- 清空预选缓存
    state.preSelected = nil

    -- 生成 1 张传闻卡 (从棋盘地点中随机选一个，告知安全/危险)
    local boardLocs = collectBoardLocations(board)
    shuffle(boardLocs)
    for _, loc in ipairs(boardLocs) do
        local card = board.cards[loc.row] and board.cards[loc.row][loc.col]
        if card and card.location ~= "home" then
            local isSafe = (card.type == "safe" or card.type == "reward" or card.type == "plot" or card.type == "clue")
            local rumor = createRumor(card.location, isSafe)
            if rumor then
                state.rumors[1] = rumor
                break
            end
        end
    end

    local schedCount = #state.schedules
    local rumorCount = #state.rumors
    print(string.format("[CardManager] Generated: %d schedules, %d rumors", schedCount, rumorCount))
end

-- ---------------------------------------------------------------------------
-- 到达检测: token 到达地点时调用
-- ---------------------------------------------------------------------------

--- 检查是否完成了某个日程
---@param location string 到达的地点类型
---@return boolean anyCompleted 是否有日程被完成
function M.checkArrival(location)
    local anyCompleted = false
    for _, sched in ipairs(state.schedules) do
        if sched.status == "pending" and sched.location == location then
            sched.status = "completed"
            anyCompleted = true
            print("[CardManager] Schedule completed: " .. sched.label)
        end
    end
    return anyCompleted
end

-- ---------------------------------------------------------------------------
-- 推迟: 玩家主动推迟日程
-- ---------------------------------------------------------------------------

--- 推迟指定索引的日程卡
---@param index number 日程卡索引 (1-based)
---@return boolean success
---@return string? reason 失败原因
function M.deferSchedule(index)
    local sched = state.schedules[index]
    if not sched then return false, "invalid" end
    if sched.status ~= "pending" then return false, "not_pending" end
    if state.deferredFromYesterday then return false, "already_deferred" end

    -- 检查是否已经有推迟的
    for _, s in ipairs(state.schedules) do
        if s.status == "deferred" then
            return false, "already_deferred"
        end
    end

    sched.status = "deferred"
    print("[CardManager] Schedule deferred: " .. sched.label)
    return true
end

--- 取消推迟指定索引的日程卡 (恢复为 pending)
---@param index number 日程卡索引 (1-based)
---@return boolean success
function M.undeferSchedule(index)
    local sched = state.schedules[index]
    if not sched then return false end
    if sched.status ~= "deferred" then return false end

    sched.status = "pending"
    print("[CardManager] Schedule undeferred: " .. sched.label)
    return true
end

-- ---------------------------------------------------------------------------
-- 日结算: 一天结束时调用
-- ---------------------------------------------------------------------------

--- 结算日程卡 (返回结算报告)
---@return table effects 资源变化列表 { { resKey, delta }, ... }
function M.settleDay()
    local effects = {}

    for _, sched in ipairs(state.schedules) do
        if sched.status == "completed" then
            -- 完成: 发奖励
            effects[#effects + 1] = { sched.reward[1], sched.reward[2] }
            print("[CardManager] Reward: " .. sched.reward[1] .. " +" .. sched.reward[2])
        elseif sched.status == "deferred" then
            -- 推迟: 累积到明天 (最多1张)
            state.deferredFromYesterday = {
                location = sched.location,
                label = sched.label,
                icon = sched.icon,
                reward = sched.reward,
                status = "pending",
            }
            print("[CardManager] Deferred to tomorrow: " .. sched.label)
        else
            -- 未完成且未推迟: 扣秩序值
            effects[#effects + 1] = { "order", -1 }
            print("[CardManager] Penalty: order -1 for " .. sched.label)
        end
    end

    -- 应用资源变化
    for _, eff in ipairs(effects) do
        ResourceBar.change(eff[1], eff[2])
    end

    -- 清空传闻 (仅当天有效)
    state.rumors = {}

    return effects
end

-- ---------------------------------------------------------------------------
-- 查询接口
-- ---------------------------------------------------------------------------

--- 获取当前日程卡列表
function M.getSchedules()
    return state.schedules
end

--- 获取当前传闻卡列表
function M.getRumors()
    return state.rumors
end

--- 查询指定地点是否有传闻
---@param location string
---@return table|nil rumor { isSafe = bool, text = string }
function M.getRumorFor(location)
    for _, r in ipairs(state.rumors) do
        if r.location == location then
            return r
        end
    end
    return nil
end

--- 获取日程完成统计
---@return number completed, number total
function M.getProgress()
    local completed = 0
    local total = #state.schedules
    for _, s in ipairs(state.schedules) do
        if s.status == "completed" then
            completed = completed + 1
        end
    end
    return completed, total
end

--- 重置所有状态 (新游戏)
function M.reset()
    state.schedules = {}
    state.rumors = {}
    state.deferredFromYesterday = nil
end

return M
