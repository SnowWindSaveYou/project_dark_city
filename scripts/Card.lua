-- ============================================================================
-- Card.lua - 卡牌数据、3D节点管理与动画
-- 双层卡牌系统: 地点层 (明牌) + 事件层 (暗牌, 翻开后显示)
-- 3D 版本: 使用 Box.mdl 薄片作为卡牌，NanoVG 纹理贴图
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

local M = {}

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

        -- 3D 节点引用
        node3d = nil,        -- Urho3D Node
        model3d = nil,       -- StaticModel 组件
        material3d = nil,    -- 当前材质
    }
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

    -- 材质
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    local tex = CardTextures.getLocationTexture(card.location)
    mat:SetTexture(TU_DIFFUSE, tex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, card.alpha)))
    geom:SetMaterial(mat)

    card.node3d = node
    card.model3d = geom
    card.material3d = mat
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

    -- 旋转: rotation 绕 Y 轴
    node:SetRotation(Quaternion(card.rotation, Vector3.UP))

    -- alpha → 材质
    if card.material3d then
        card.material3d:SetShaderParameter("MatDiffColor",
            Variant(Color(1, 1, 1, card.alpha)))
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
    end
end

-- ---------------------------------------------------------------------------
-- 动画: 翻牌 (3D 版 — scaleX 翻转 + bounceY 弹跳)
-- ---------------------------------------------------------------------------

function M.flip(card, onComplete, CardTextures)
    if card.isFlipping or card.faceUp then return end
    card.isFlipping = true

    -- 阶段1: scaleX → 0 (收缩)
    Tween.to(card, { scaleX = 0, scaleY = 1.08 }, 0.14, {
        easing = Tween.Easing.easeInQuad,
        tag = "cardflip",
        onComplete = function()
            -- 切换正反面 + 纹理
            card.faceUp = true
            if CardTextures then
                M.updateTexture(card, CardTextures)
            end

            -- 阶段2: scaleX → 1 (展开)
            Tween.to(card, { scaleX = 1.0, scaleY = 1.0 }, 0.28, {
                easing = Tween.Easing.easeOutBack,
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

    -- 弹跳 Y (3D: 正值=上)
    Tween.to(card, { bounceY = 0.08 }, 0.12, {
        easing = Tween.Easing.easeOutQuad,
        tag = "cardflip",
        onComplete = function()
            Tween.to(card, { bounceY = 0 }, 0.35, {
                easing = Tween.Easing.easeOutBounce,
                tag = "cardflip",
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
    card.scaleX = 0.3
    card.scaleY = 0.3
    card.rotation = math.random(-15, 15)

    Tween.to(card, {
        x = targetX,
        y = targetY,
        alpha = 1.0,
        scaleX = 1.0,
        scaleY = 1.0,
        rotation = 0,
    }, 0.45, {
        delay = delay or 0,
        easing = Tween.Easing.easeOutBack,
        tag = "carddeal",
        onComplete = function()
            card.isDealing = false
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 收牌
-- ---------------------------------------------------------------------------

function M.undeal(card, deckX, deckY, delay, onComplete)
    Tween.to(card, {
        x = deckX,
        y = deckY,
        alpha = 0,
        scaleX = 0.2,
        scaleY = 0.2,
        rotation = math.random(-20, 20),
    }, 0.3, {
        delay = delay or 0,
        easing = Tween.Easing.easeInBack,
        tag = "carddeal",
        onComplete = function()
            card.faceUp = (card.type == "landmark")
            card.glowIntensity = 0
            card.bounceY = 0
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

    card._shakeT = 0
    Tween.to(card, { scaleX = 0.3, scaleY = 0.3, _shakeT = 1 }, 0.25, {
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

            Tween.to(card, { scaleX = 1.0, scaleY = 1.0 }, 0.35, {
                easing = Tween.Easing.easeOutBack,
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
