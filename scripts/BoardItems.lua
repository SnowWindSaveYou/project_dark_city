-- ============================================================================
-- BoardItems.lua - 棋盘道具系统
-- 每回合在地图上放置1~3个可拾取道具，玩家走到格子上后拾取
-- 使用3D Billboard显示（与Token/MonsterGhost一致）
-- ============================================================================

local Tween     = require "lib.Tween"
local VFX       = require "lib.VFX"
local Theme     = require "Theme"
local ItemIcons  = require "ItemIcons"

local M = {}

-- ---------------------------------------------------------------------------
-- 道具池定义 (key, 权重, 拾取效果描述)
-- ---------------------------------------------------------------------------
local ITEM_POOL = {
    { key = "coffee",    weight = 25, label = "咖啡",     icon = "☕" },
    { key = "film",      weight = 20, label = "胶卷",     icon = "🎞️" },
    { key = "shield",    weight = 15, label = "护身符",   icon = "🧿" },
    { key = "exorcism",  weight = 15, label = "驱魔香",   icon = "🪔" },
    { key = "mapReveal", weight = 25, label = "地图碎片", icon = "🗺️" },
}

-- 3D Billboard 参数
local ITEM_SIZE    = 0.22         -- 道具图标尺寸(米)
local ITEM_BASE_Y  = 0.35        -- 浮空基础高度
local FLOAT_AMP    = 0.025       -- 上下浮动幅度
local FLOAT_SPEED  = 2.2         -- 浮动频率
local GLOW_SIZE    = 0.08        -- 底部光晕额外半径
local CAMERA_OFFSET_Z = -0.18   -- 向相机方向偏移，使道具显示在玩家前方

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

---@type userdata
local parentNode_ = nil

---@class BoardItem
---@field key string       道具key
---@field row number       所在行
---@field col number       所在列
---@field worldX number    世界X
---@field worldZ number    世界Z
---@field node userdata    3D节点
---@field bbSet userdata   BillboardSet
---@field bb userdata      Billboard
---@field glowNode userdata 光晕节点
---@field phase number     浮动相位
---@field scale number     当前缩放
---@field alpha number     当前透明度
---@field collected boolean 已被拾取

local items_ = {}    -- 当前地图上的道具列表

-- ---------------------------------------------------------------------------
-- 工具: 按权重随机选取道具
-- ---------------------------------------------------------------------------
local function randomItemKey()
    local totalW = 0
    for _, entry in ipairs(ITEM_POOL) do
        totalW = totalW + entry.weight
    end
    local roll = math.random(1, totalW)
    local acc = 0
    for _, entry in ipairs(ITEM_POOL) do
        acc = acc + entry.weight
        if roll <= acc then return entry end
    end
    return ITEM_POOL[1]
end

--- 获取道具池条目 by key
local function getPoolEntry(key)
    for _, entry in ipairs(ITEM_POOL) do
        if entry.key == key then return entry end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 创建单个道具 3D Billboard
-- ---------------------------------------------------------------------------
local function createItemBillboard(itemKey, worldX, worldZ, phase)
    local tex = ItemIcons.getTexture(itemKey)
    if not tex then
        print("[BoardItems] WARNING: no texture for " .. itemKey)
        return nil
    end

    local node = parentNode_:CreateChild("BoardItem_" .. itemKey)
    node:SetPosition(Vector3(worldX, 0, worldZ + CAMERA_OFFSET_Z))

    -- 主图标 Billboard
    local bbSet = node:CreateComponent("BillboardSet")
    bbSet:SetNumBillboards(1)
    bbSet:SetFaceCameraMode(FC_ROTATE_Y)
    bbSet:SetSorted(true)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    mat:SetTexture(TU_DIFFUSE, tex)
    bbSet:SetMaterial(mat)

    local bb = bbSet:GetBillboard(0)
    bb.position = Vector3(0, ITEM_BASE_Y, 0)
    bb.size = Vector2(0.001, 0.001)  -- 初始极小，弹出动画放大
    bb.color = Color(1, 1, 1, 0)
    bb.enabled = true
    bbSet:Commit()

    -- 底部光晕圆盘 (半透明圆柱)
    local glowNode = parentNode_:CreateChild("ItemGlow")
    glowNode:SetPosition(Vector3(worldX, 0.016, worldZ + CAMERA_OFFSET_Z))
    local glowR = ITEM_SIZE * 0.5 + GLOW_SIZE
    glowNode:SetScale(Vector3(glowR * 2, 0.001, glowR * 2))
    local glowModel = glowNode:CreateComponent("StaticModel")
    glowModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    local glowMat = Material:new()
    glowMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    -- 金色光晕
    glowMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.85, 0.3, 0.0)))
    glowMat:SetShaderParameter("MatRoughness", Variant(1.0))
    glowMat:SetShaderParameter("MatMetallic", Variant(0.0))
    glowModel:SetMaterial(glowMat)

    return {
        node = node,
        bbSet = bbSet,
        bb = bb,
        glowNode = glowNode,
        glowMat = glowMat,
        phase = phase,
        scale = 0,
        alpha = 0,
        glowAlpha = 0,
    }
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化 (在 scene 创建后调用一次)
function M.init(scene)
    parentNode_ = scene:CreateChild("BoardItems")
end

--- 清除所有地图道具 (含3D节点)
function M.clear()
    for _, item in ipairs(items_) do
        Tween.cancelTarget(item)
        if item.node then item.node:Remove() end
        if item.glowNode then item.glowNode:Remove() end
    end
    items_ = {}
end

--- 每回合放置道具
--- @param board table 棋盘数据
--- @param Board table Board模块 (用于cardPos)
--- @param excludeRow number 玩家所在行 (家)
--- @param excludeCol number 玩家所在列 (家)
function M.spawnDaily(board, Board, excludeRow, excludeCol)
    M.clear()
    if not parentNode_ then
        print("[BoardItems] ERROR: not initialized")
        return
    end

    -- 收集可放置的格子 (排除家、地标、商店)
    local candidates = {}
    for r = 1, Board.ROWS do
        for c = 1, Board.COLS do
            -- 排除玩家起点 (家)
            if r ~= excludeRow or c ~= excludeCol then
                local card = board.cards[r] and board.cards[r][c]
                if card then
                    -- 排除特殊格：家/地标/商店
                    if card.type ~= "home" and card.type ~= "landmark" and card.type ~= "shop" then
                        candidates[#candidates + 1] = { r = r, c = c }
                    end
                end
            end
        end
    end

    -- 打乱候选格子
    for i = #candidates, 2, -1 do
        local j = math.random(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    -- 放置1~3个道具
    local count = math.min(math.random(1, 3), #candidates)
    print(string.format("[BoardItems] Spawning %d items on board", count))

    for i = 1, count do
        local pos = candidates[i]
        local entry = randomItemKey()
        local wx, wz = Board.cardPos(board, pos.r, pos.c)
        local phase = math.random() * math.pi * 2

        local sprite = createItemBillboard(entry.key, wx, wz, phase)
        if sprite then
            local item = {
                key = entry.key,
                row = pos.r,
                col = pos.c,
                worldX = wx,
                worldZ = wz,
                collected = false,
                -- 3D引用
                node = sprite.node,
                bbSet = sprite.bbSet,
                bb = sprite.bb,
                glowNode = sprite.glowNode,
                glowMat = sprite.glowMat,
                phase = sprite.phase,
                scale = sprite.scale,
                alpha = sprite.alpha,
                glowAlpha = sprite.glowAlpha,
            }
            items_[#items_ + 1] = item

            -- 弹出动画: 延迟交错
            Tween.to(item, { scale = 1.0, alpha = 1.0, glowAlpha = 0.35 }, 0.4, {
                easing = Tween.Easing.easeOutBack,
                delay = 0.3 + (i - 1) * 0.15,
                tag = "boarditem_spawn",
            })

            print(string.format("[BoardItems]   → %s at (%d,%d) world(%.2f,%.2f)",
                entry.key, pos.r, pos.c, wx, wz))
        end
    end
end

--- 检测玩家到达格子时是否有道具可拾取
--- @param row number 玩家到达的行
--- @param col number 玩家到达的列
--- @return table|nil  拾取到的道具信息 { key, label, icon } 或 nil
function M.tryCollect(row, col)
    for i, item in ipairs(items_) do
        if not item.collected and item.row == row and item.col == col then
            item.collected = true

            -- === 拾取动效: 上浮→缩小→消失 ===
            -- 1) 光晕脉冲放大后消失
            if item.glowNode then
                local glowScale = item.glowNode:GetScale()
                local bigScale = Vector3(glowScale.x * 2.0, glowScale.y, glowScale.z * 2.0)
                -- 用 glowAlpha 做动画驱动
                Tween.to(item, { glowAlpha = 0 }, 0.3, {
                    easing = Tween.Easing.easeOutQuad,
                    tag = "boarditem_collect",
                })
            end

            -- 2) 图标上浮旋转后消失
            local collectAnim = { t = 0 }
            local startY = item.bb.position.y
            local startScale = item.scale

            Tween.to(collectAnim, { t = 1 }, 0.45, {
                easing = Tween.Easing.easeOutCubic,
                tag = "boarditem_collect",
                onUpdate = function(_, progress)
                    -- 上浮
                    local liftY = startY + progress * 0.25
                    item.bb.position = Vector3(0, liftY, 0)
                    -- 先放大再缩小 (钟形曲线)
                    local bellScale = 1.0 + math.sin(progress * math.pi) * 0.3
                    item.scale = startScale * bellScale * (1.0 - progress * 0.5)
                    -- 后半段淡出
                    if progress > 0.5 then
                        item.alpha = 1.0 - (progress - 0.5) * 2.0
                    end
                end,
                onComplete = function()
                    -- 移除3D节点
                    if item.node then item.node:Remove(); item.node = nil end
                    if item.glowNode then item.glowNode:Remove(); item.glowNode = nil end
                    -- 从列表移除
                    for j = #items_, 1, -1 do
                        if items_[j] == item then
                            table.remove(items_, j)
                            break
                        end
                    end
                end,
            })

            -- 返回道具信息
            local entry = getPoolEntry(item.key)
            return {
                key = item.key,
                label = entry and entry.label or item.key,
                icon = entry and entry.icon or "?",
            }
        end
    end
    return nil
end

--- 每帧更新: 浮动动画
---@param dt number
---@param gameTime number
function M.update(dt, gameTime)
    for _, item in ipairs(items_) do
        if not item.collected and item.bb then
            -- 上下浮动
            local floatY = math.sin(gameTime * FLOAT_SPEED + item.phase) * FLOAT_AMP
            item.bb.position = Vector3(0, ITEM_BASE_Y + floatY, 0)

            -- 缩放 + 透明度
            local s = item.scale * ITEM_SIZE
            item.bb.size = Vector2(s, s)
            item.bb.color = Color(1, 1, 1, item.alpha)
            item.bbSet:Commit()

            -- 光晕透明度
            if item.glowMat then
                item.glowMat:SetShaderParameter("MatDiffColor",
                    Variant(Color(1.0, 0.85, 0.3, item.glowAlpha)))
            end

            -- 光晕呼吸
            if item.glowNode and item.glowAlpha > 0.01 then
                local breathe = 1.0 + math.sin(gameTime * 3.0 + item.phase) * 0.08
                local glowR = (ITEM_SIZE * 0.5 + GLOW_SIZE) * breathe
                item.glowNode:SetScale(Vector3(glowR * 2, 0.001, glowR * 2))
            end
        elseif item.collected and item.bb then
            -- 收集动画期间持续同步
            local s = item.scale * ITEM_SIZE
            item.bb.size = Vector2(s, s)
            item.bb.color = Color(1, 1, 1, math.max(0, item.alpha))
            item.bbSet:Commit()

            if item.glowMat then
                item.glowMat:SetShaderParameter("MatDiffColor",
                    Variant(Color(1.0, 0.85, 0.3, math.max(0, item.glowAlpha))))
            end
        end
    end
end

--- 获取当前道具数量 (调试用)
function M.getCount()
    local active = 0
    for _, item in ipairs(items_) do
        if not item.collected then active = active + 1 end
    end
    return active
end

--- 销毁
function M.destroy()
    M.clear()
    if parentNode_ then
        parentNode_:Remove()
        parentNode_ = nil
    end
end

return M
