-- ============================================================================
-- EndingSystem.lua - 多结局判定
-- 无状态模块: 遍历结局定义, 返回第一个条件满足的结局
-- ============================================================================

local StoryConfig  = require "StoryConfig"
local StoryManager = require "StoryManager"

local M = {}

--- 判定当前应触发的结局
--- 遍历 ENDINGS (按 priority 升序), 返回第一个条件满足的结局
---@param sm table StoryManager 实例
---@param ctx table 条件上下文 { dayCount, weather }
---@return table ending { id, title, subtitle, priority, isVictory }
function M.judge(sm, ctx)
    -- ENDINGS 已按 priority 升序排列
    for _, ending in ipairs(StoryConfig.ENDINGS) do
        if ending.conditions == nil then
            -- nil conditions = 兜底结局, 总是匹配
            return ending
        end
        if StoryManager.checkCondition(sm, ending.conditions, ctx) then
            return ending
        end
    end

    -- 不应到达这里 (最后一个结局 conditions=nil), 保险兜底
    return StoryConfig.ENDINGS[#StoryConfig.ENDINGS]
end

return M
