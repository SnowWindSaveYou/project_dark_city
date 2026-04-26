-- ============================================================================
-- CardTextures.lua - NanoVG 渲染到纹理 (卡牌贴图生成器)
-- 将 NanoVG 矢量绘制的卡面烘焙为 Texture2D，供 3D 卡牌模型使用
-- ============================================================================

local Card  = require "Card"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local TEX_W = 256     -- 纹理宽 (像素)
local TEX_H = 360     -- 纹理高 (像素) — 保持卡牌比例 64:90 ≈ 256:360

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------
---@type userdata 独立 NanoVG 上下文 (仅用于纹理渲染)
local texVg = nil
local fontSans = -1

-- 纹理缓存
local locationTexCache = {}   -- locKey → Texture2D (地点面)
local eventTexCache    = {}   -- "locKey_eventType" → Texture2D (事件面)
local backTex          = nil  -- 牌背纹理

-- 待渲染队列
local pendingQueue = {}  -- { { kind="location"|"event"|"back", key=string, card=table }, ... }

-- 传闻查询函数 (外部注入)
---@type fun(location: string): table|nil
local rumorQueryFn = nil

-- ---------------------------------------------------------------------------
-- 初始化 / 销毁
-- ---------------------------------------------------------------------------

function M.init()
    texVg = nvgCreate(1)
    if not texVg then
        print("[CardTextures] ERROR: Failed to create NanoVG texture context")
        return
    end
    fontSans = nvgCreateFont(texVg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontSans == -1 then
        print("[CardTextures] ERROR: Failed to load font for textures")
    end
    print("[CardTextures] Initialized (TEX=" .. TEX_W .. "x" .. TEX_H .. ")")
end

function M.destroy()
    if texVg then
        nvgDelete(texVg)
        texVg = nil
    end
    locationTexCache = {}
    eventTexCache = {}
    backTex = nil
    pendingQueue = {}
end

--- 注入传闻查询函数 (与 Card.lua 共享)
function M.setRumorQuery(fn)
    rumorQueryFn = fn
end

-- ---------------------------------------------------------------------------
-- 纹理创建工具
-- ---------------------------------------------------------------------------

local function createRenderTexture()
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(TEX_W, TEX_H, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_BILINEAR)
    return tex
end

-- ---------------------------------------------------------------------------
-- 绘制函数: 地点面 (未翻开时显示)
-- ---------------------------------------------------------------------------

local function renderLocation(tex, locKey)
    local vg = texVg
    local w, h = TEX_W, TEX_H
    local t = Theme.current

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)

    -- 清透明
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- 卡体底色 (直角, 匹配 CustomGeometry)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, Theme.rgba(t.cardLocationBg or t.cardFace))
    nvgFill(vg)

    -- 地点信息
    local locInfo = Card.LOCATION_INFO[locKey]
    if not locInfo then
        locInfo = { icon = "❓", label = "未知" }
    end

    -- 地点图标
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 112)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgba(t.textPrimary))
    nvgText(vg, w / 2, h / 2 - 32, locInfo.icon, nil)

    -- 地点名称
    nvgFontSize(vg, 44)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 200))
    nvgText(vg, w / 2, h - 56, locInfo.label, nil)

    -- 内边框
    local inset = 16
    nvgBeginPath(vg)
    nvgRect(vg, inset, inset, w - inset * 2, h - inset * 2)
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBorder, 40))
    nvgStrokeWidth(vg, 3.2)
    nvgStroke(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBorder, 180))
    nvgStrokeWidth(vg, 6)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)
end

-- ---------------------------------------------------------------------------
-- 绘制函数: 事件面 (翻开后显示)
-- ---------------------------------------------------------------------------

local function renderEvent(tex, locKey, eventType)
    local vg = texVg
    local w, h = TEX_W, TEX_H
    local t = Theme.current
    local info = Theme.cardTypeInfo(eventType)
    if not info then return end
    local tc = Theme.cardTypeColor(eventType)

    -- 获取显示内容
    local displayIcon, displayLabel
    if eventType == "landmark" or eventType == "home" or eventType == "shop" then
        local locInfo = Card.LOCATION_INFO[locKey]
        displayIcon  = locInfo and locInfo.icon or info.icon
        displayLabel = locInfo and locInfo.label or info.label
    else
        local darkInfo = Card.getDarksideInfo(locKey, eventType)
        displayIcon  = darkInfo and darkInfo.icon or info.icon
        displayLabel = darkInfo and darkInfo.label or info.label
    end

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)

    -- 清透明
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- 卡体底色 (直角, 匹配 CustomGeometry)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, Theme.rgba(t.cardFace))
    nvgFill(vg)

    -- 顶部色条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 12, 12, w - 24, 24, 12)
    nvgFillColor(vg, Theme.rgbaA(tc, 200))
    nvgFill(vg)

    -- 事件图标
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 112)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgba(t.textPrimary))
    nvgText(vg, w / 2, h / 2 - 16, displayIcon, nil)

    -- 事件标签
    nvgFontSize(vg, 44)
    nvgFillColor(vg, Theme.rgbaA(tc, 220))
    nvgText(vg, w / 2, h - 56, displayLabel, nil)

    -- 边框
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBorder, 180))
    nvgStrokeWidth(vg, 6)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)
end

-- ---------------------------------------------------------------------------
-- 绘制函数: 牌背
-- ---------------------------------------------------------------------------

local function renderBack(tex)
    local vg = texVg
    local w, h = TEX_W, TEX_H
    local t = Theme.current
    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)

    -- 清透明
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- 卡背底色 (直角, 匹配 CustomGeometry)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, Theme.rgba(t.cardBack))
    nvgFill(vg)

    -- 交叉花纹装饰 (简约)
    local cx, cy = w / 2, h / 2
    local patternR = w * 0.3
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBackAlt or t.cardBorder, 80))
    nvgStrokeWidth(vg, 3)
    for i = -3, 3 do
        local off = i * 20
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + off - patternR, cy - patternR)
        nvgLineTo(vg, cx + off + patternR, cy + patternR)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + off + patternR, cy - patternR)
        nvgLineTo(vg, cx + off - patternR, cy + patternR)
        nvgStroke(vg)
    end

    -- 中心圆
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 30)
    nvgFillColor(vg, Theme.rgbaA(t.cardBackAlt or t.cardBorder, 120))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgStrokeColor(vg, Theme.rgbaA(t.cardBorder, 180))
    nvgStrokeWidth(vg, 6)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)
end

-- ---------------------------------------------------------------------------
-- 公共 API: 纹理获取 (带懒渲染)
-- ---------------------------------------------------------------------------

--- 获取地点面纹理 (未翻开时)
function M.getLocationTexture(locKey)
    if locationTexCache[locKey] then
        return locationTexCache[locKey]
    end
    -- 立即创建并渲染
    local tex = createRenderTexture()
    renderLocation(tex, locKey)
    locationTexCache[locKey] = tex
    return tex
end

--- 获取事件面纹理 (翻开后)
function M.getEventTexture(locKey, eventType)
    local cacheKey = locKey .. "_" .. eventType
    if eventTexCache[cacheKey] then
        return eventTexCache[cacheKey]
    end
    local tex = createRenderTexture()
    renderEvent(tex, locKey, eventType)
    eventTexCache[cacheKey] = tex
    return tex
end

--- 获取牌背纹理 (牌堆显示)
function M.getBackTexture()
    if backTex then return backTex end
    backTex = createRenderTexture()
    renderBack(backTex)
    return backTex
end

-- ---------------------------------------------------------------------------
-- 预加载: 为棋盘所有卡牌提前生成纹理
-- ---------------------------------------------------------------------------

--- 确保一张卡的所有纹理已就绪
function M.ensureCard(card)
    M.getLocationTexture(card.location)
    M.getEventTexture(card.location, card.type)
end

--- 为整个棋盘预加载纹理
function M.preloadBoard(board, ROWS, COLS)
    M.getBackTexture()
    for row = 1, ROWS do
        if board.cards[row] then
            for col = 1, COLS do
                local card = board.cards[row][col]
                if card then
                    M.ensureCard(card)
                end
            end
        end
    end
    print("[CardTextures] Preloaded textures for board")
end

--- 清空缓存 (换天时调用)
function M.clearCache()
    locationTexCache = {}
    eventTexCache = {}
    -- backTex 保留，不会变
    print("[CardTextures] Cache cleared")
end

return M
