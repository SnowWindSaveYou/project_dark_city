-- ============================================================================
-- Card.lua - 卡牌数据、3D节点管理与动画
-- 双层卡牌系统: 地点层 (明牌) + 事件层 (暗牌, 翻开后显示)
-- 3D 版本: 使用 Box.mdl 薄片作为卡牌，NanoVG 纹理贴图
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

local M = {}

-- 缓存 Technique 资源, 避免每帧查找
local techDiff      = nil  -- 不透明
local techDiffAlpha = nil  -- 透明 (发牌淡入/淡出时用)

-- ---------------------------------------------------------------------------
-- 常量: 2D 逻辑 (保留兼容, 纹理用)
-- ---------------------------------------------------------------------------
M.WIDTH  = 64
M.HEIGHT = 90
M.RADIUS = 8

-- ---------------------------------------------------------------------------
-- 常量: 3D 世界尺寸 (米)
-- ---------------------------------------------------------------------------
M.CARD_W = 0.64          -- 世界宽
M.CARD_H = 0.90          -- 世界高(深度方向 Z)
M.CARD_THICKNESS = 0.015 -- 厚度 (Y 方向)
M.ICON_QUAD = 0.18       -- 侦查/揭示图标边长 (米)

-- ---------------------------------------------------------------------------
-- 地点信息 (卡牌正面显示的都市地点)
-- ---------------------------------------------------------------------------
M.LOCATION_INFO = {
    -- 特殊地点
    home        = { icon = "🏠", label = "家" },
    -- 商店地点 (便利店 = 商店)
    convenience = { icon = "🏪", label = "便利店" },
    -- 地标地点 (有祛邪光环的庇护所)
    church      = { icon = "⛪", label = "教堂" },
    police      = { icon = "🚔", label = "警察局" },
    shrine      = { icon = "⛩️", label = "神社" },
    -- 普通地点
    company     = { icon = "🏢", label = "公司" },
    school      = { icon = "🏫", label = "学校" },
    park        = { icon = "🌳", label = "公园" },
    alley       = { icon = "🌙", label = "小巷" },
    station     = { icon = "🚉", label = "车站" },
    hospital    = { icon = "🏥", label = "医院" },
    library     = { icon = "📚", label = "图书馆" },
    bank        = { icon = "🏦", label = "银行" },
}

-- 可随机分配的普通地点 (不含 home/landmark/shop)
M.REGULAR_LOCATIONS = {
    "company", "school", "park",
    "alley", "station", "hospital", "library", "bank",
}

-- 地标可用地点 (有祛邪力量的场所)
M.LANDMARK_LOCATIONS = { "church", "police", "shrine" }

-- ---------------------------------------------------------------------------
-- 事件类型 (翻开卡牌后显示的隐藏事件)
-- ---------------------------------------------------------------------------
M.EVENT_TYPES = { "safe", "monster", "trap", "reward", "plot", "clue" }

-- 兼容旧代码的完整类型列表 (含特殊类型)
M.ALL_TYPES = { "safe", "home", "landmark", "shop", "monster", "trap", "reward", "plot", "clue" }

-- ---------------------------------------------------------------------------
-- 暗面世界映射
-- ---------------------------------------------------------------------------
M.DARKSIDE_INFO = {
    company = {
        safe    = { icon = "🏢", label = "空荡办公室" },
        monster = { icon = "🕴️", label = "影子上司" },
        trap    = { icon = "📋", label = "无尽加班令" },
        reward  = { icon = "💼", label = "遗落的公文包" },
        plot    = { icon = "🖥️", label = "异常邮件" },
        clue    = { icon = "📂", label = "机密档案" },
    },
    school = {
        safe    = { icon = "🏫", label = "安静教室" },
        monster = { icon = "👤", label = "无面教师" },
        trap    = { icon = "🔔", label = "永不下课" },
        reward  = { icon = "📒", label = "旧笔记本" },
        plot    = { icon = "🎒", label = "无主书包" },
        clue    = { icon = "📝", label = "黑板留言" },
    },
    park = {
        safe    = { icon = "🌳", label = "寂静长椅" },
        monster = { icon = "🌑", label = "树影低语" },
        trap    = { icon = "🕸️", label = "缠绕藤蔓" },
        reward  = { icon = "🍃", label = "净化之风" },
        plot    = { icon = "🗿", label = "奇怪雕像" },
        clue    = { icon = "🪶", label = "地上羽毛" },
    },
    alley = {
        safe    = { icon = "🌙", label = "寂静小巷" },
        monster = { icon = "👁️", label = "墙缝窥视" },
        trap    = { icon = "🕳️", label = "地面塌陷" },
        reward  = { icon = "📦", label = "角落包裹" },
        plot    = { icon = "🚪", label = "不存在的门" },
        clue    = { icon = "✍️", label = "涂鸦暗号" },
    },
    station = {
        safe    = { icon = "🚉", label = "末班列车" },
        monster = { icon = "🚇", label = "不停靠的车" },
        trap    = { icon = "🌀", label = "循环站台" },
        reward  = { icon = "🎫", label = "神秘车票" },
        plot    = { icon = "📻", label = "广播异响" },
        clue    = { icon = "🗺️", label = "失落线路图" },
    },
    hospital = {
        safe    = { icon = "🏥", label = "空病房" },
        monster = { icon = "💉", label = "游走护士" },
        trap    = { icon = "🩺", label = "错误诊断" },
        reward  = { icon = "💊", label = "遗留药品" },
        plot    = { icon = "📋", label = "诡异病历" },
        clue    = { icon = "🔬", label = "实验记录" },
    },
    library = {
        safe    = { icon = "📚", label = "安静角落" },
        monster = { icon = "📖", label = "自翻的书" },
        trap    = { icon = "🔇", label = "沉默诅咒" },
        reward  = { icon = "📜", label = "古老卷轴" },
        plot    = { icon = "📕", label = "禁书" },
        clue    = { icon = "🔖", label = "夹页纸条" },
    },
    bank = {
        safe    = { icon = "🏦", label = "空金库" },
        monster = { icon = "🎭", label = "面具柜员" },
        trap    = { icon = "🔒", label = "锁死的门" },
        reward  = { icon = "💰", label = "无主存款" },
        plot    = { icon = "🏧", label = "异常终端" },
        clue    = { icon = "🧾", label = "可疑账单" },
    },
}

--- 获取暗面显示信息
function M.getDarksideInfo(location, eventType)
    local locMap = M.DARKSIDE_INFO[location]
    if locMap and locMap[eventType] then
        return locMap[eventType]
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

---@class CardData
---@field type string       事件类型
---@field location string   地点类型
---@field row number
---@field col number
---@field faceUp boolean
---@field x number   世界坐标 X
---@field y number   世界坐标 Z (棋盘深度)
---@field worldY number  世界坐标 Y (高度: 弹跳/浮动)
---@field scaleX number
---@field scaleY number
---@field rotation number degrees (绕 Y 轴)
---@field alpha number
---@field bounceY number  高度偏移 (正=上)
---@field glowIntensity number 0-1
---@field isFlipping boolean
---@field isDealing boolean
---@field hoverT number 0-1

function M.new(cardType, row, col, location)
    return {
        type = cardType or "safe",
        location = location or "company",
        row = row or 1,
        col = col or 1,
        faceUp = (cardType == "landmark"),

        -- 世界空间属性 (x→worldX, y→worldZ)
        x = 0, y = 0,
        worldY = 0,       -- 高度 (牌面在 Y=0 平面上)
        scaleX = 1.0,
        scaleY = 1.0,
        rotation = 0,     -- 绕 Y 轴旋转 (度)
        alpha = 0,
        bounceY = 0,      -- 3D: 正值=向上弹跳
        glowIntensity = 0,

        -- 状态
        isFlipping = false,
        isDealing = false,
        hoverT = 0,
        shakeX = 0,
        scouted = false,
        revealed = false,
        flipAngle = 0,      -- 绕 X 轴翻转角度 (0=正面朝上, 90=垂直)

        -- 3D 节点引用
        node3d = nil,        -- Urho3D Node
        model3d = nil,       -- StaticModel 组件
        material3d = nil,    -- 当前材质
        scoutedNode = nil,   -- 已侦查图标子节点
        revealedNode = nil,  -- 已揭示图标子节点
        safeGlowRings = nil,  -- 安全区光环数组 { {node=, mat=}, ... }
        safeGlowActive = false, -- 光晕是否激活
    }
end

-- ---------------------------------------------------------------------------
-- 3D 子节点工具: 创建图标小片 (CustomGeometry quad)
-- ---------------------------------------------------------------------------

--- 创建贴图图标四边形 (双面, DiffUnlit 不受光照影响)
---@param parentNode userdata 卡牌 node
---@param name string 子节点名
---@param texture userdata Texture2D 图标纹理
---@param offsetX number 相对卡牌中心的 X 偏移
---@param offsetZ number 相对卡牌中心的 Z 偏移
---@return userdata node
local function createIconQuad(parentNode, name, texture, offsetX, offsetZ)
    local half = M.ICON_QUAD / 2
    local node = parentNode:CreateChild(name)
    node:SetPosition(Vector3(offsetX, 0.15, offsetZ))  -- 浮在卡面上方

    local geom = node:CreateComponent("CustomGeometry")
    geom:SetNumGeometries(1)
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local nUp   = Vector3(0, 1, 0)
    local nDown = Vector3(0, -1, 0)

    -- 正面 (朝上) — 标准 UV: 左下(0,0) 右上(1,1)
    geom:DefineVertex(Vector3(-half, 0, -half)); geom:DefineNormal(nUp); geom:DefineTexCoord(Vector2(0, 0))
    geom:DefineVertex(Vector3(-half, 0,  half)); geom:DefineNormal(nUp); geom:DefineTexCoord(Vector2(0, 1))
    geom:DefineVertex(Vector3( half, 0,  half)); geom:DefineNormal(nUp); geom:DefineTexCoord(Vector2(1, 1))

    geom:DefineVertex(Vector3(-half, 0, -half)); geom:DefineNormal(nUp); geom:DefineTexCoord(Vector2(0, 0))
    geom:DefineVertex(Vector3( half, 0,  half)); geom:DefineNormal(nUp); geom:DefineTexCoord(Vector2(1, 1))
    geom:DefineVertex(Vector3( half, 0, -half)); geom:DefineNormal(nUp); geom:DefineTexCoord(Vector2(1, 0))

    -- 背面 (朝下)
    geom:DefineVertex(Vector3(-half, 0, -half)); geom:DefineNormal(nDown); geom:DefineTexCoord(Vector2(0, 0))
    geom:DefineVertex(Vector3( half, 0,  half)); geom:DefineNormal(nDown); geom:DefineTexCoord(Vector2(1, 1))
    geom:DefineVertex(Vector3(-half, 0,  half)); geom:DefineNormal(nDown); geom:DefineTexCoord(Vector2(0, 1))

    geom:DefineVertex(Vector3(-half, 0, -half)); geom:DefineNormal(nDown); geom:DefineTexCoord(Vector2(0, 0))
    geom:DefineVertex(Vector3( half, 0, -half)); geom:DefineNormal(nDown); geom:DefineTexCoord(Vector2(1, 0))
    geom:DefineVertex(Vector3( half, 0,  half)); geom:DefineNormal(nDown); geom:DefineTexCoord(Vector2(1, 1))

    geom:Commit()

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    mat:SetTexture(TU_DIFFUSE, texture)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    mat.renderOrder = 200   -- 默认128, 更高=更后渲染, 确保显示在卡牌上方
    geom:SetMaterial(mat)

    node:SetEnabled(false)
    return node
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 创建
-- ---------------------------------------------------------------------------

--- 为卡牌创建 3D 节点 (CustomGeometry 薄片, 精确 UV)
---@param card CardData
---@param parentNode userdata 父节点 (scene 或 boardNode)
---@param CardTextures table CardTextures 模块
function M.createNode(card, parentNode, CardTextures)
    if card.node3d then return end  -- 已创建

    local node = parentNode:CreateChild("Card_" .. card.row .. "_" .. card.col)

    -- CustomGeometry: 水平薄片，面朝 +Y
    -- 卡牌中心在 node 原点，无需额外缩放 (顶点直接使用世界尺寸)
    local halfW = M.CARD_W / 2
    local halfH = M.CARD_H / 2
    local normal = Vector3(0, 1, 0)  -- 面朝上

    local geom = node:CreateComponent("CustomGeometry")
    geom:SetNumGeometries(1)
    geom:BeginGeometry(0, TRIANGLE_LIST)

    -- UV 映射 (NanoVG render-target 的 V 轴翻转):
    -- NanoVG (0,0)=左上 → 屏幕左上 → 世界 (-X, +Z) → UV(0,1)
    -- NanoVG (1,0)=右上 → 屏幕右上 → 世界 (+X, +Z) → UV(1,1)
    -- NanoVG (0,1)=左下 → 屏幕左下 → 世界 (-X, -Z) → UV(0,0)
    -- NanoVG (1,1)=右下 → 屏幕右下 → 世界 (+X, -Z) → UV(1,0)

    -- 三角形 1: 左后 → 左前 → 右前
    geom:DefineVertex(Vector3(-halfW, 0, -halfH))  -- 左下(屏幕) = 左前(世界-Z)
    geom:DefineNormal(normal)
    geom:DefineTexCoord(Vector2(0, 0))

    geom:DefineVertex(Vector3(-halfW, 0, halfH))   -- 左上(屏幕) = 左后(世界+Z)
    geom:DefineNormal(normal)
    geom:DefineTexCoord(Vector2(0, 1))

    geom:DefineVertex(Vector3(halfW, 0, halfH))    -- 右上(屏幕) = 右后(世界+Z)
    geom:DefineNormal(normal)
    geom:DefineTexCoord(Vector2(1, 1))

    -- 三角形 2: 左前 → 右后 → 右前
    geom:DefineVertex(Vector3(-halfW, 0, -halfH))  -- 左下(屏幕)
    geom:DefineNormal(normal)
    geom:DefineTexCoord(Vector2(0, 0))

    geom:DefineVertex(Vector3(halfW, 0, halfH))    -- 右上(屏幕)
    geom:DefineNormal(normal)
    geom:DefineTexCoord(Vector2(1, 1))

    geom:DefineVertex(Vector3(halfW, 0, -halfH))   -- 右下(屏幕)
    geom:DefineNormal(normal)
    geom:DefineTexCoord(Vector2(1, 0))

    geom:Commit()

    -- 材质 (卡牌主体用不透明 Technique, 发牌动画时按需切换)
    if not techDiff then
        techDiff      = cache:GetResource("Technique", "Techniques/Diff.xml")
        techDiffAlpha = cache:GetResource("Technique", "Techniques/DiffAlpha.xml")
    end
    local mat = Material:new()
    if card.alpha < 1.0 then
        mat:SetTechnique(0, techDiffAlpha)
    else
        mat:SetTechnique(0, techDiff)
    end
    local tex = CardTextures.getLocationTexture(card.location)
    mat:SetTexture(TU_DIFFUSE, tex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, card.alpha)))
    geom:SetMaterial(mat)

    card.node3d = node
    card.model3d = geom
    card.material3d = mat

    -- 侦查/揭示 图标子节点 (右上角 = +X, +Z 卡面顶部)
    local margin = M.ICON_QUAD * 0.55
    local iconX = halfW - margin                            -- 右侧
    local iconZ1 = halfH - margin                           -- 卡面顶部 (+Z)
    local iconZ2 = halfH - margin - M.ICON_QUAD * 1.15     -- 第二个稍下
    local scoutedTex  = cache:GetResource("Texture2D", "image/icon_scouted_v2_20260426051601.png")
    local revealedTex = cache:GetResource("Texture2D", "image/icon_revealed_v2_20260426051619.png")
    card.scoutedNode  = createIconQuad(node, "ico_scouted",
        scoutedTex,  iconX, iconZ1)   -- 右上角第一个
    card.revealedNode = createIconQuad(node, "ico_revealed",
        revealedTex, iconX, iconZ2)   -- 右上角第二个

    -- 光环上浮淡出效果 (safe/home=白色, landmark=金色)
    local needGlow = (card.type == "safe" or card.type == "home" or card.type == "landmark")
    if needGlow and CardTextures then
        local glowTex
        if card.type == "landmark" then
            glowTex = CardTextures.getLandmarkGlowTexture and CardTextures.getLandmarkGlowTexture()
        else
            glowTex = CardTextures.getSafeGlowTexture and CardTextures.getSafeGlowTexture()
        end
        if glowTex then
            local gw = halfW
            local gh = halfH
            local nUp = Vector3(0, 1, 0)
            local techAlpha = cache:GetResource("Technique", "Techniques/DiffAlpha.xml")
            local rings = {}
            local RING_COUNT = 3

            for i = 1, RING_COUNT do
                local rn = node:CreateChild("safe_ring_" .. i)
                rn:SetPosition(Vector3(0, 0.005, 0))

                local gg = rn:CreateComponent("CustomGeometry")
                gg:SetNumGeometries(1)
                gg:BeginGeometry(0, TRIANGLE_LIST)
                gg:DefineVertex(Vector3(-gw, 0, -gh)); gg:DefineNormal(nUp); gg:DefineTexCoord(Vector2(0, 0))
                gg:DefineVertex(Vector3(-gw, 0,  gh)); gg:DefineNormal(nUp); gg:DefineTexCoord(Vector2(0, 1))
                gg:DefineVertex(Vector3( gw, 0,  gh)); gg:DefineNormal(nUp); gg:DefineTexCoord(Vector2(1, 1))
                gg:DefineVertex(Vector3(-gw, 0, -gh)); gg:DefineNormal(nUp); gg:DefineTexCoord(Vector2(0, 0))
                gg:DefineVertex(Vector3( gw, 0,  gh)); gg:DefineNormal(nUp); gg:DefineTexCoord(Vector2(1, 1))
                gg:DefineVertex(Vector3( gw, 0, -gh)); gg:DefineNormal(nUp); gg:DefineTexCoord(Vector2(1, 0))
                gg:Commit()

                local ringMat = Material:new()
                ringMat:SetTechnique(0, techAlpha)
                ringMat:SetTexture(TU_DIFFUSE, glowTex)
                ringMat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 0)))
                ringMat.renderOrder = 100
                gg:SetMaterial(ringMat)

                rn:SetEnabled(false)
                rings[i] = { node = rn, mat = ringMat }
            end

            card.safeGlowRings = rings
        end
    end
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 同步 Lua 状态 → Node Transform
-- ---------------------------------------------------------------------------

--- 每帧调用: 将 card 的 Lua 属性映射到 3D Node
---@param card CardData
function M.syncNode(card)
    local node = card.node3d
    if not node then return end

    -- 位置: card.x→worldX, card.y→worldZ, bounceY→worldY
    local wx = card.x + card.shakeX * 0.01  -- shakeX 单位缩放: 2D(5px) → 3D(~0.05m)
    local wy = card.bounceY + 0.01           -- +0.01m 避免与桌面 Z-fighting
    local wz = card.y                        -- card.y 映射到 worldZ

    node:SetPosition(Vector3(wx, wy, wz))

    -- 缩放: CustomGeometry 顶点已包含世界尺寸，scale 仅作动画乘数
    local hoverScale = 1.0 + card.hoverT * 0.08
    local sx = card.scaleX * hoverScale
    local sz = card.scaleY * hoverScale
    node:SetScale(Vector3(sx, 1.0, sz))

    -- 旋转: rotation 绕 Y 轴 + flipAngle 绕 Z 轴 (左右翻牌)
    local rot = Quaternion(card.rotation, Vector3.UP)
    if card.flipAngle and card.flipAngle ~= 0 then
        rot = rot * Quaternion(card.flipAngle, Vector3.FORWARD)
    end
    node:SetRotation(rot)

    -- alpha → 材质 (按需切换透明/不透明 Technique)
    if card.material3d then
        if card.alpha < 0.999 then
            card.material3d:SetTechnique(0, techDiffAlpha)
        else
            card.material3d:SetTechnique(0, techDiff)
        end
        card.material3d:SetShaderParameter("MatDiffColor",
            Variant(Color(1, 1, 1, card.alpha)))
    end

    -- 侦查/揭示图标: 只要卡牌可见就显示 (不论正反面, 不论是否翻转中)
    local showIcons = (card.alpha > 0.1)
    if card.scoutedNode then
        card.scoutedNode:SetEnabled(showIcons and card.scouted == true)
    end
    if card.revealedNode then
        card.revealedNode:SetEnabled(showIcons and card.revealed == true)
    end

    -- 安全区光环: 多层上浮淡出 (仅激活状态)
    if card.safeGlowActive and card.safeGlowRings then
        local elapsed = time and time.elapsedTime or 0
        local RING_COUNT = #card.safeGlowRings
        local CYCLE = 2.2           -- 每层循环周期 (秒)
        local Y_BASE = 0.005        -- 起始高度 (卡面上方)
        local Y_RISE = 0.05         -- 上浮距离
        local SCALE_GROW = 0.06     -- 上浮时微微放大

        for i = 1, RING_COUNT do
            local ring = card.safeGlowRings[i]
            -- 交错相位: 每层偏移 1/RING_COUNT 个周期
            local phase = ((elapsed / CYCLE) + (i - 1) / RING_COUNT) % 1.0
            local y = Y_BASE + phase * Y_RISE
            local alpha = (1.0 - phase) * (1.0 - phase)  -- 二次衰减
            local sc = 1.0 + phase * SCALE_GROW

            ring.node:SetPosition(Vector3(0, y, 0))
            ring.node:SetScale(Vector3(sc, 1, sc))
            ring.node:SetEnabled(card.alpha > 0.1)
            ring.mat:SetShaderParameter("MatDiffColor",
                Variant(Color(1, 1, 1, alpha * card.alpha)))
        end
    end
end

-- ---------------------------------------------------------------------------
-- 安全区光晕: 显示/隐藏
-- ---------------------------------------------------------------------------

--- 激活安全区光环 (多层上浮)
---@param card CardData
function M.showSafeGlow(card)
    if not card.safeGlowRings then
        print(string.format("[Card] showSafeGlow(%d,%d) SKIP: no rings", card.row, card.col))
        return
    end
    if card.safeGlowActive then return end
    print(string.format("[Card] showSafeGlow(%d,%d) type=%s ACTIVATED", card.row, card.col, card.type))
    card.safeGlowActive = true
    for _, ring in ipairs(card.safeGlowRings) do
        ring.node:SetEnabled(true)
    end
end

--- 关闭安全区光环 (淡出)
---@param card CardData
function M.hideSafeGlow(card)
    if not card.safeGlowRings then return end
    if not card.safeGlowActive then return end
    card.safeGlowActive = false
    for _, ring in ipairs(card.safeGlowRings) do
        ring.node:SetEnabled(false)
        ring.mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 0)))
    end
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 更新材质纹理 (翻牌时切换)
-- ---------------------------------------------------------------------------

--- 切换卡牌显示面的纹理
---@param card CardData
---@param CardTextures table
function M.updateTexture(card, CardTextures)
    if not card.material3d then return end

    local tex
    if card.faceUp then
        tex = CardTextures.getEventTexture(card.location, card.type)
    else
        tex = CardTextures.getLocationTexture(card.location)
    end
    card.material3d:SetTexture(TU_DIFFUSE, tex)
end

-- ---------------------------------------------------------------------------
-- 3D 节点: 销毁
-- ---------------------------------------------------------------------------

function M.destroyNode(card)
    if card.node3d then
        card.node3d:Remove()
        card.node3d = nil
        card.model3d = nil
        card.material3d = nil
        card.scoutedNode = nil   -- 子节点随父节点一起销毁
        card.revealedNode = nil
        card.safeGlowRings = nil
        card.safeGlowActive = false
    end
end

-- ---------------------------------------------------------------------------
-- 动画: 翻牌 (3D 版 — flipAngle 绕 X 轴翻转 + bounceY 弹跳)
-- ---------------------------------------------------------------------------

-- 翻牌安全高度: halfW(0.32) + 余量, 确保 90° 时底边不穿桌
M.FLIP_LIFT = M.CARD_W / 2 + 0.04  -- ~0.36m

function M.flip(card, onComplete, CardTextures)
    if card.isFlipping or card.faceUp then return end
    card.isFlipping = true

    -- 预备: 轻微下压蓄力 (0.05s)
    Tween.to(card, { bounceY = -0.01, scaleX = 1.03, scaleY = 0.97 }, 0.05, {
        easing = Tween.Easing.easeOutQuad,
        tag = "cardflip",
        onComplete = function()
            -- 弹起到安全高度 (0.12s)
            Tween.to(card, { bounceY = M.FLIP_LIFT }, 0.12, {
                easing = Tween.Easing.easeOutCubic,
                tag = "cardflip",
            })

            -- 缩放恢复 (与弹起同时)
            Tween.to(card, { scaleX = 1.0, scaleY = 1.0 }, 0.08, {
                easing = Tween.Easing.easeOutQuad,
                tag = "cardflip",
            })

            -- 翻转 (稍延后, 与弹起重叠, 确保已有足够高度)
            Tween.to(card, { flipAngle = 90 }, 0.16, {
                delay = 0.04,
                easing = Tween.Easing.easeInOutQuad,
                tag = "cardflip",
                onComplete = function()
                    -- 在 90° 时切换纹理 (侧面不可见, 完美切换)
                    card.faceUp = true
                    if CardTextures then
                        M.updateTexture(card, CardTextures)
                    end

                    -- 翻回 + 落下 (同步, 旋转轴在中心)
                    Tween.to(card, { flipAngle = 0, bounceY = 0 }, 0.25, {
                        easing = Tween.Easing.easeOutCubic,
                        tag = "cardflip",
                        onComplete = function()
                            card.isFlipping = false
                            card.glowIntensity = 1.0
                            Tween.to(card, { glowIntensity = 0 }, 0.6, {
                                easing = Tween.Easing.easeOutQuad,
                            })
                            if onComplete then onComplete(card) end
                        end
                    })
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 翻回 (正面 → 背面, 相机模式退出时使用)
-- ---------------------------------------------------------------------------

function M.flipBack(card, onComplete, CardTextures)
    if card.isFlipping or not card.faceUp then
        if onComplete then onComplete(card) end
        return
    end
    card.isFlipping = true

    -- 抬升到安全高度 (0.10s)
    Tween.to(card, { bounceY = M.FLIP_LIFT }, 0.10, {
        easing = Tween.Easing.easeOutCubic,
        tag = "cardflip",
    })

    -- 翻转到 90° (稍延后, 与抬升重叠)
    Tween.to(card, { flipAngle = 90 }, 0.14, {
        delay = 0.03,
        easing = Tween.Easing.easeInOutQuad,
        tag = "cardflip",
        onComplete = function()
            card.faceUp = false
            if CardTextures then
                M.updateTexture(card, CardTextures)
            end
            -- 翻回 + 落下 (同步)
            Tween.to(card, { flipAngle = 0, bounceY = 0 }, 0.22, {
                easing = Tween.Easing.easeOutCubic,
                tag = "cardflip",
                onComplete = function()
                    card.isFlipping = false
                    if onComplete then onComplete(card) end
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 快速翻到正面 (相机模式进入时, 不弹跳)
-- ---------------------------------------------------------------------------

function M.flipToFace(card, CardTextures)
    if card.isFlipping or card.faceUp then return end
    card.isFlipping = true

    -- 抬升到安全高度 (0.08s, 快速版)
    Tween.to(card, { bounceY = M.FLIP_LIFT }, 0.08, {
        easing = Tween.Easing.easeOutCubic,
        tag = "cameramode",
    })

    -- 翻转到 90° (稍延后)
    Tween.to(card, { flipAngle = 90 }, 0.10, {
        delay = 0.02,
        easing = Tween.Easing.easeInOutQuad,
        tag = "cameramode",
        onComplete = function()
            card.faceUp = true
            if CardTextures then
                M.updateTexture(card, CardTextures)
            end
            -- 翻回 + 落下
            Tween.to(card, { flipAngle = 0, bounceY = 0 }, 0.18, {
                easing = Tween.Easing.easeOutCubic,
                tag = "cameramode",
                onComplete = function()
                    card.isFlipping = false
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 快速翻回背面 (相机模式退出时, 不弹跳)
-- ---------------------------------------------------------------------------

function M.flipToBack(card, CardTextures)
    if card.isFlipping or not card.faceUp then return end
    card.isFlipping = true

    -- 抬升到安全高度 (0.08s)
    Tween.to(card, { bounceY = M.FLIP_LIFT }, 0.08, {
        easing = Tween.Easing.easeOutCubic,
        tag = "cameramode",
    })

    -- 翻转到 90° (稍延后)
    Tween.to(card, { flipAngle = 90 }, 0.08, {
        delay = 0.02,
        easing = Tween.Easing.easeInOutQuad,
        tag = "cameramode",
        onComplete = function()
            card.faceUp = false
            if CardTextures then
                M.updateTexture(card, CardTextures)
            end
            -- 翻回 + 落下
            Tween.to(card, { flipAngle = 0, bounceY = 0 }, 0.15, {
                easing = Tween.Easing.easeOutCubic,
                tag = "cameramode",
                onComplete = function()
                    card.isFlipping = false
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 无效操作抖动
-- ---------------------------------------------------------------------------

function M.shake(card)
    if card._shaking then return end
    card._shaking = true
    card._shakeT = 0
    Tween.to(card, { _shakeT = 1 }, 0.35, {
        easing = Tween.Easing.linear,
        tag = "cardshake",
        onUpdate = function(_, t)
            local decay = (1 - t) ^ 2
            card.shakeX = math.sin(t * math.pi * 6) * 0.04 * decay
        end,
        onComplete = function()
            card.shakeX = 0
            card._shaking = false
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 发牌 (3D 世界坐标)
-- ---------------------------------------------------------------------------

function M.dealTo(card, targetX, targetY, delay)
    card.isDealing = true
    card.alpha = 0
    card.scaleX = 0.7
    card.scaleY = 0.7
    card.rotation = 0
    card.bounceY = 0.8       -- 从较高处出发
    card.flipAngle = 0

    local d = delay or 0

    -- 阶段1: 快速出现 (0~0.08s) — 从牌堆弹出，透明度迅速拉满
    Tween.to(card, { alpha = 1.0 }, 0.08, {
        delay = d,
        easing = Tween.Easing.easeOutQuad,
        tag = "carddeal",
    })

    -- 阶段2: 飞行轨迹 (位置) — 先快后慢，用 easeOutCubic 不过冲
    Tween.to(card, {
        x = targetX,
        y = targetY,
    }, 0.35, {
        delay = d,
        easing = Tween.Easing.easeOutCubic,
        tag = "carddeal",
    })

    -- 阶段3: 落地展开 (缩放) — 稍晚启动，带轻微过冲回弹
    Tween.to(card, {
        scaleX = 1.0,
        scaleY = 1.0,
    }, 0.28, {
        delay = d + 0.06,
        easing = Tween.Easing.easeOutBack,
        tag = "carddeal",
    })

    -- 阶段4: 高度下落 — 分两段：快速下降 + 轻弹落定
    Tween.to(card, { bounceY = 0.02 }, 0.30, {
        delay = d,
        easing = Tween.Easing.easeInOutCubic,
        tag = "carddeal",
        onComplete = function()
            -- 最后一小段弹跳落定
            Tween.to(card, { bounceY = 0 }, 0.15, {
                easing = Tween.Easing.easeOutQuad,
                tag = "carddeal",
                onComplete = function()
                    card.isDealing = false
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 收牌
-- ---------------------------------------------------------------------------

function M.undeal(card, deckX, deckY, delay, onComplete)
    -- 先弹起再飞走
    Tween.to(card, { bounceY = 0.3 }, 0.12, {
        delay = delay or 0,
        easing = Tween.Easing.easeOutQuad,
        tag = "carddeal",
    })

    Tween.to(card, {
        x = deckX,
        y = deckY,
        alpha = 0,
        scaleX = 0.2,
        scaleY = 0.2,
        bounceY = 0,
        rotation = math.random(-20, 20),
    }, 0.3, {
        delay = (delay or 0) + 0.08,
        easing = Tween.Easing.easeInBack,
        tag = "carddeal",
        onComplete = function()
            card.faceUp = (card.type == "landmark")
            card.glowIntensity = 0
            card.bounceY = 0
            card.flipAngle = 0
            if onComplete then onComplete(card) end
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 变形 (monster → photo)
-- ---------------------------------------------------------------------------

function M.transformTo(card, newType, onComplete, CardTextures)
    if card._transforming then return end
    card._transforming = true

    -- 抬升到安全高度 (70° 时需 halfW*sin70° ≈ 0.30m)
    local liftH = M.FLIP_LIFT  -- 0.36m, 足够 70° 翻转
    Tween.to(card, { bounceY = liftH }, 0.12, {
        easing = Tween.Easing.easeOutCubic,
        tag = "cardtransform",
    })

    -- 抖动 + flipAngle 掀起 (稍延后, 与抬升重叠)
    card._shakeT = 0
    Tween.to(card, { flipAngle = 70, _shakeT = 1 }, 0.25, {
        delay = 0.04,
        easing = Tween.Easing.easeInQuad,
        tag = "cardtransform",
        onUpdate = function(_, t)
            card.shakeX = math.sin(t * math.pi * 10) * 0.05 * (1 - t * 0.5)
        end,
        onComplete = function()
            card.type = newType
            card.shakeX = 0
            if CardTextures then
                M.updateTexture(card, CardTextures)
            end

            -- 落回: flipAngle + bounceY + scale 同步归位
            Tween.to(card, { flipAngle = 0, bounceY = 0, scaleX = 1.0, scaleY = 1.0 }, 0.35, {
                easing = Tween.Easing.easeOutCubic,
                tag = "cardtransform",
                onComplete = function()
                    card._transforming = false
                    card.glowIntensity = 1.0
                    Tween.to(card, { glowIntensity = 0 }, 0.8, {
                        easing = Tween.Easing.easeOutQuad,
                    })
                    if onComplete then onComplete(card) end
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 传闻角标 (外部注入查询函数)
-- ---------------------------------------------------------------------------

---@type fun(location: string): table|nil
local rumorQueryFn = nil

function M.setRumorQuery(fn)
    rumorQueryFn = fn
end

-- ---------------------------------------------------------------------------
-- hitTest: 3D 版本由 Board 层通过 ray-plane 实现
-- 保留 2D 版本用于向后兼容，但标记为 deprecated
-- ---------------------------------------------------------------------------

function M.hitTest(card, px, py)
    if card.alpha < 0.1 then return false end
    -- 3D 模式下 px,py 是世界坐标
    local dx = math.abs(px - card.x)
    local dy = math.abs(py - card.y)
    return dx < M.CARD_W / 2 and dy < M.CARD_H / 2
end

return M
