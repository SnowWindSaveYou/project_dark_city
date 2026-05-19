-- ============================================================================
-- CardTextures.lua - NanoVG 渲染到纹理 (卡牌贴图生成器)
-- 将 NanoVG 矢量绘制的卡面烘焙为 Texture2D，供 3D 卡牌模型使用
-- 优先使用 PNG 插画，fallback 到 NanoVG 程序化绘制
-- ============================================================================

local Card         = require "Card"
local EventPool    = require "EventPool"
local Theme        = require "Theme"
local CardImageMap = require "CardImageMap"

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
local darkCardTexCache = {}   -- "darkType_darkName" → Texture2D (暗面卡牌)
local darkWallTex      = nil  -- 暗面墙壁纹理

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
    darkCardTexCache = {}
    darkWallTex = nil
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
    -- 翻转 Y 轴：render-target 存储约定与新 UV (V=0=顶部) 对齐
    nvgTranslate(vg, 0, h)
    nvgScale(vg, 1, -1)

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
    local locInfo = EventPool.LOCATION_INFO[locKey]
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
        local locInfo = EventPool.LOCATION_INFO[locKey]
        displayIcon  = locInfo and locInfo.icon or info.icon
        displayLabel = locInfo and locInfo.label or info.label
    else
        local darkInfo = EventPool.getDarksideInfo(locKey, eventType)
        displayIcon  = darkInfo and darkInfo.icon or info.icon
        displayLabel = darkInfo and darkInfo.label or info.label
    end

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)
    -- 翻转 Y 轴：与新 UV 约定对齐
    nvgTranslate(vg, 0, h)
    nvgScale(vg, 1, -1)

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
    nvgTranslate(vg, 0, h)
    nvgScale(vg, 1, -1)

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

    -- 白色外卡框
    local borderW = 6
    nvgBeginPath(vg)
    nvgRect(vg, borderW / 2, borderW / 2, w - borderW, h - borderW)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgStrokeWidth(vg, borderW)
    nvgStroke(vg)

    -- 内圈细边框（层次感）
    nvgBeginPath(vg)
    nvgRect(vg, borderW + 4, borderW + 4, w - (borderW + 4) * 2, h - (borderW + 4) * 2)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 80))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)
end

-- ---------------------------------------------------------------------------
-- 绘制函数: 暗面世界卡牌 (全明牌, 暗色底 + 类型图标)
-- ---------------------------------------------------------------------------

local function renderDarkCard(tex, darkType, darkName, hasDot)
    local vg = texVg
    local w, h = TEX_W, TEX_H
    local t = Theme.current
    local typeInfo = Theme.darkCardTypeInfo(darkType) or { icon = "🌑", label = "暗巷" }
    local typeColor = Theme.darkCardTypeColor(darkType)

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)
    nvgTranslate(vg, 0, h)
    nvgScale(vg, 1, -1)

    -- 清透明
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- 暗面卡体底色
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, Theme.rgba(t.darkCardFace))
    nvgFill(vg)

    -- 顶部类型色条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 12, 12, w - 24, 24, 12)
    nvgFillColor(vg, Theme.rgbaA(typeColor, 180))
    nvgFill(vg)

    -- 类型图标 (居中大图标)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 112)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, w / 2, h / 2 - 16, typeInfo.icon, nil)

    -- 地点名称 (底部)
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Theme.rgbaA(typeColor, 220))
    nvgText(vg, w / 2, h - 56, darkName or typeInfo.label, nil)

    -- 暗面内边框 (淡紫光晕)
    local inset = 14
    nvgBeginPath(vg)
    nvgRect(vg, inset, inset, w - inset * 2, h - inset * 2)
    nvgStrokeColor(vg, Theme.rgbaA(t.darkGlow or t.darkAccent, 50))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 外边框
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgStrokeColor(vg, Theme.rgbaA(t.darkCardBorder, 200))
    nvgStrokeWidth(vg, 6)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)
end

-- ---------------------------------------------------------------------------
-- 公共 API: 纹理获取 (带懒渲染)
-- ---------------------------------------------------------------------------

-- overlay 缓存（PNG 卡框+卡名叠加层，透明背景）
local locationOverlayCache = {}  -- locKey → Texture2D
local eventOverlayCache    = {}  -- "locKey_eventType" → Texture2D

--- 直接用 ResourceCache 加载 PNG 纹理（在引擎 WASM 环境中可靠）
--- 返回 Texture2D 或 nil
local function loadPNGTexture(imgFile)
    if not imgFile then return nil end
    local path = "image/" .. imgFile
    local tex = cache:GetResource("Texture2D", path)
    if tex then
        return tex
    end
    print("[CardTextures] WARN: PNG not found: " .. path)
    return nil
end

--- 渲染拍立得风格 overlay（未翻开地点卡专用）
--- 样式：左/右/上各 12px 白色实边 + 底部 56px 白色标签区 + 深色卡名文字
--- 中心完全透明，让 PNG 地点插图透出
--- @param labelText  string  底部卡名
local function renderPolaroidOverlay(labelText)
    local vg = texVg
    local w, h = TEX_W, TEX_H

    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(w, h, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_BILINEAR)

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)
    nvgTranslate(vg, 0, h)
    nvgScale(vg, 1, -1)

    local sideW  = 12   -- 左/右/上边框宽度
    local bottomH = 60  -- 底部标签区高度（稍大留文字空间）

    -- ── 1. 全透明底（不遮挡 PNG）─────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- ── 2. 左边白条 ───────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sideW, h)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)

    -- ── 3. 右边白条 ───────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, w - sideW, 0, sideW, h)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)

    -- ── 4. 上边白条（NanoVG Y=0 为卡牌顶部）──────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, sideW)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)

    -- ── 5. 底部标签区（NanoVG Y=h 为卡牌底部）────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, h - bottomH, w, bottomH)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)

    -- ── 6. 底部标签区上方细分隔线 ─────────────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, sideW, h - bottomH)
    nvgLineTo(vg, w - sideW, h - bottomH)
    nvgStrokeColor(vg, nvgRGBA(200, 190, 175, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ── 7. 卡名文字（深色，居中，带轻微阴影）─────────────────────────────
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local textY = h - bottomH / 2
    -- 文字阴影
    nvgFillColor(vg, nvgRGBA(120, 110, 95, 60))
    nvgText(vg, w / 2 + 1, textY + 1, labelText, nil)
    -- 文字主体
    nvgFillColor(vg, nvgRGBA(45, 38, 30, 220))
    nvgText(vg, w / 2, textY, labelText, nil)

    -- ── 8. 极细外轮廓线（卡片边缘感）─────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0.5, 0.5, w - 1, h - 1)
    nvgStrokeColor(vg, nvgRGBA(180, 170, 155, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)

    return tex
end

--- 渲染事件拍立得 overlay（翻开后事件卡专用）
--- 与地点卡拍立得相同白色边框，底部标签区叠上事件类型半透明色
--- @param labelText  string  事件名称
--- @param typeColor  table   { r, g, b } 事件类型颜色
local function renderEventPolaroidOverlay(labelText, typeColor)
    local vg = texVg
    local w, h = TEX_W, TEX_H

    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(w, h, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_BILINEAR)

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)
    nvgTranslate(vg, 0, h)
    nvgScale(vg, 1, -1)

    local sideW   = 12
    local bottomH = 60
    local tc = typeColor or { r = 180, g = 160, b = 120 }

    -- ── 1. 全透明底 ───────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- ── 2. 左/右白条 ──────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sideW, h)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, w - sideW, 0, sideW, h)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)

    -- ── 3. 上边白条 ───────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, sideW)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)

    -- ── 4. 底部标签区：奶白底 ─────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, h - bottomH, w, bottomH)
    nvgFillColor(vg, nvgRGBA(252, 248, 240, 255))
    nvgFill(vg)

    -- ── 5. 底部标签区：事件类型半透明叠色 ────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, sideW, h - bottomH, w - sideW * 2, bottomH)
    nvgFillColor(vg, nvgRGBA(tc.r, tc.g, tc.b, 72))
    nvgFill(vg)

    -- ── 6. 分隔线 ─────────────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, sideW, h - bottomH)
    nvgLineTo(vg, w - sideW, h - bottomH)
    nvgStrokeColor(vg, nvgRGBA(tc.r, tc.g, tc.b, 100))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- ── 7. 卡名文字 ───────────────────────────────────────────────────────
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local textY = h - bottomH / 2
    nvgFillColor(vg, nvgRGBA(tc.r, tc.g, tc.b, 50))
    nvgText(vg, w / 2 + 1, textY + 1, labelText, nil)
    nvgFillColor(vg, nvgRGBA(45, 38, 30, 230))
    nvgText(vg, w / 2, textY, labelText, nil)

    -- ── 8. 极细外轮廓线 ───────────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0.5, 0.5, w - 1, h - 1)
    nvgStrokeColor(vg, nvgRGBA(180, 170, 155, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)

    return tex
end

--- 渲染 overlay（透明背景 + 三层矩形边框 + 底部标签）
--- 叠加在 PNG 图片上方，不遮挡图片内容
--- @param labelText  string  底部卡名
--- @param borderColor table  { r, g, b } 边框颜色
local function renderOverlay(labelText, borderColor)
    local vg = texVg
    local w, h = TEX_W, TEX_H

    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(w, h, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_BILINEAR)

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, w, h, 1.0)
    nvgTranslate(vg, 0, h)
    nvgScale(vg, 1, -1)

    local bc = borderColor or { r = 180, g = 160, b = 120 }
    local BW = 9   -- 主边框宽度（加粗）

    -- ── 1. 全透明底（不遮挡 PNG）────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- ── 2. 底部标签渐变遮罩 ──────────────────────────────────────────────
    local labelH = 56
    local labelY = h - labelH
    local gradPaint = nvgLinearGradient(vg, 0, labelY - 28, 0, h,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 200))
    nvgBeginPath(vg)
    nvgRect(vg, 0, labelY - 28, w, labelH + 28)
    nvgFillPaint(vg, gradPaint)
    nvgFill(vg)

    -- ── 3. 卡名文字（阴影 + 主体）──────────────────────────────────────
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 34)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 130))
    nvgText(vg, w / 2 + 1, h - labelH / 2 + 3, labelText, nil)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 245))
    nvgText(vg, w / 2, h - labelH / 2 + 2, labelText, nil)

    -- ── 4. 三层矩形边框 ─────────────────────────────────────────────────
    -- 层①：外侧深影（立体感）
    nvgBeginPath(vg)
    nvgRect(vg, 1, 1, w - 2, h - 2)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgStrokeWidth(vg, 5)
    nvgStroke(vg)

    -- 层②：主色边框（加粗）
    nvgBeginPath(vg)
    nvgRect(vg, BW / 2, BW / 2, w - BW, h - BW)
    nvgStrokeColor(vg, nvgRGBA(bc.r, bc.g, bc.b, 240))
    nvgStrokeWidth(vg, BW)
    nvgStroke(vg)

    -- 层③：内侧白色高光（浮雕感）
    nvgBeginPath(vg)
    nvgRect(vg, BW + 3, BW + 3, w - (BW + 3) * 2, h - (BW + 3) * 2)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 75))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)

    return tex
end

--- 获取地点面 PNG 纹理（主体，无叠加层）
--- 返回 Texture2D 或 nil（nil 表示无 PNG，应使用 NanoVG fallback）
function M.getLocationTexture(locKey)
    if locationTexCache[locKey] ~= nil then
        return locationTexCache[locKey]
    end
    local imgFile = CardImageMap.getLocationImage(locKey)
    local tex = loadPNGTexture(imgFile)
    if tex then
        print("[CardTextures] PNG location loaded: " .. locKey)
    else
        -- fallback: NanoVG 程序化绘制
        tex = createRenderTexture()
        renderLocation(tex, locKey)
        print("[CardTextures] Fallback NanoVG for location: " .. locKey)
    end
    locationTexCache[locKey] = tex
    return tex
end

--- 获取地点面 overlay 纹理（卡框+卡名，透明背景）
--- 只在有 PNG 时才生成 overlay；NanoVG fallback 时返回 nil（已内嵌卡框）
function M.getLocationOverlay(locKey)
    if locationOverlayCache[locKey] ~= nil then
        return locationOverlayCache[locKey]
    end
    local imgFile = CardImageMap.getLocationImage(locKey)
    if not imgFile then
        locationOverlayCache[locKey] = false  -- 标记为"无 overlay"
        return nil
    end
    local locInfo = EventPool.LOCATION_INFO[locKey]
    local label = locInfo and locInfo.label or locKey
    -- 地点卡（未翻开）使用拍立得样式
    local overlay = renderPolaroidOverlay(label)
    locationOverlayCache[locKey] = overlay
    return overlay
end

-- home/landmark/shop 类型：事件面无专属图时，复用地点面图片
local REUSE_LOC_IMAGE_TYPES = { home = true, landmark = true, shop = true }

--- 获取事件面 PNG 纹理（主体，无叠加层）
function M.getEventTexture(locKey, eventType)
    local cacheKey = locKey .. "_" .. eventType
    if eventTexCache[cacheKey] ~= nil then
        return eventTexCache[cacheKey]
    end
    local imgFile = CardImageMap.getEventImage(locKey, eventType)
    -- home/landmark/shop 无专属事件图时，复用地点面图片
    if not imgFile and REUSE_LOC_IMAGE_TYPES[eventType] then
        imgFile = CardImageMap.getLocationImage(locKey)
    end
    local tex = loadPNGTexture(imgFile)
    if tex then
        print("[CardTextures] PNG event loaded: " .. locKey .. "/" .. eventType)
    else
        tex = createRenderTexture()
        renderEvent(tex, locKey, eventType)
        print("[CardTextures] Fallback NanoVG for event: " .. locKey .. "/" .. eventType)
    end
    eventTexCache[cacheKey] = tex
    return tex
end

--- 获取事件面 overlay 纹理（卡框+卡名，透明背景）
function M.getEventOverlay(locKey, eventType)
    local cacheKey = locKey .. "_" .. eventType
    if eventOverlayCache[cacheKey] ~= nil then
        return eventOverlayCache[cacheKey]
    end
    local imgFile = CardImageMap.getEventImage(locKey, eventType)
    -- home/landmark/shop 无专属事件图时，复用地点面图片（同样需要 overlay）
    if not imgFile and REUSE_LOC_IMAGE_TYPES[eventType] then
        imgFile = CardImageMap.getLocationImage(locKey)
    end
    if not imgFile then
        eventOverlayCache[cacheKey] = false
        return nil
    end
    local darkInfo = EventPool.getDarksideInfo(locKey, eventType)
    local typeInfo = Theme.cardTypeInfo(eventType)
    -- home/landmark 用地点名作为 label
    local locInfo = EventPool.LOCATION_INFO[locKey]
    local label = (locInfo and (eventType == "home" or eventType == "landmark" or eventType == "shop") and locInfo.label)
        or (darkInfo and darkInfo.label) or (typeInfo and typeInfo.label) or eventType
    local overlay
    local tc = Theme.cardTypeColor(eventType)
    if REUSE_LOC_IMAGE_TYPES[eventType] then
        -- home/landmark/shop 复用地点图，使用纯拍立得样式（无事件色）
        overlay = renderPolaroidOverlay(label)
    else
        -- 普通事件：拍立得白框 + 底部叠事件类型颜色
        overlay = renderEventPolaroidOverlay(label, tc)
    end
    eventOverlayCache[cacheKey] = overlay
    return overlay
end

--- 获取牌背纹理 (牌堆显示)
function M.getBackTexture()
    if backTex then return backTex end
    backTex = createRenderTexture()
    renderBack(backTex)
    return backTex
end

--- 获取暗面卡牌纹理 (全明牌, 暗色主题)
---@param darkType string  暗面类型 (normal/shop/clue/item/passage/intel/checkpoint/abyss_core)
---@param darkName string|nil  地点名称 (可选, 未传则用 typeInfo.label)
---@param hasDot boolean|nil   是否显示暗币小点 (仅 normal 类型有效)
---@return userdata Texture2D
function M.getDarkCardTexture(darkType, darkName, hasDot)
    local dotSuffix = hasDot and "_dot" or ""
    local cacheKey = (darkType or "normal") .. "_" .. (darkName or "") .. dotSuffix
    if darkCardTexCache[cacheKey] then
        return darkCardTexCache[cacheKey]
    end
    local tex = createRenderTexture()
    renderDarkCard(tex, darkType, darkName, hasDot)
    darkCardTexCache[cacheKey] = tex
    return tex
end

-- ---------------------------------------------------------------------------
-- 预加载: 为棋盘所有卡牌提前生成纹理
-- ---------------------------------------------------------------------------

--- 确保一张卡的所有纹理已就绪
function M.ensureCard(card)
    if card.isDark then
        -- 暗面卡牌: 全明牌, 只需暗面纹理
        M.getDarkCardTexture(card.darkType or "normal", card.darkName, card.darkDot)
    else
        M.getLocationTexture(card.location)
        M.getEventTexture(card.location, card.type)
    end
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

--- 清空缓存 (换天/切暗面时调用)
function M.clearCache()
    locationTexCache = {}
    eventTexCache = {}
    locationOverlayCache = {}
    eventOverlayCache = {}
    darkCardTexCache = {}
    darkWallTex = nil
    -- backTex / icon / glow 纹理保留，不会变
    print("[CardTextures] Cache cleared")
end

-- ---------------------------------------------------------------------------
-- 安全光晕纹理 (方形发光边框, 与卡牌同比例 256x360)
-- ---------------------------------------------------------------------------
local safeGlowTex = nil
local landmarkGlowTex = nil

function M.getSafeGlowTexture()
    if safeGlowTex then return safeGlowTex end
    if not texVg then return nil end

    local w, h = TEX_W, TEX_H  -- 256x360, 与卡牌纹理同比例

    safeGlowTex = Texture2D:new()
    safeGlowTex:SetNumLevels(1)
    safeGlowTex:SetSize(w, h, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    safeGlowTex:SetFilterMode(FILTER_BILINEAR)

    nvgSetRenderTarget(texVg, safeGlowTex)
    nvgBeginFrame(texVg, w, h, 1.0)
    nvgTranslate(texVg, 0, h)
    nvgScale(texVg, 1, -1)

    -- 清透明
    nvgBeginPath(texVg)
    nvgRect(texVg, 0, 0, w, h)
    nvgFillColor(texVg, nvgRGBA(0, 0, 0, 0))
    nvgFill(texVg)

    -- 多层发光边框 (由外到内, 从淡到浓)
    local r, g, b = 255, 255, 255  -- 白色发光
    local margin = 6   -- 纹理边距, 给最外层模糊留空间

    -- 外发光层 (宽模糊)
    nvgBeginPath(texVg)
    nvgRect(texVg, margin, margin, w - margin * 2, h - margin * 2)
    nvgStrokeColor(texVg, nvgRGBA(r, g, b, 120))
    nvgStrokeWidth(texVg, 16)
    nvgStroke(texVg)

    -- 中间发光层
    nvgBeginPath(texVg)
    nvgRect(texVg, margin + 4, margin + 4, w - (margin + 4) * 2, h - (margin + 4) * 2)
    nvgStrokeColor(texVg, nvgRGBA(r, g, b, 200))
    nvgStrokeWidth(texVg, 8)
    nvgStroke(texVg)

    -- 内层实线边框 (最亮)
    nvgBeginPath(texVg)
    nvgRect(texVg, margin + 8, margin + 8, w - (margin + 8) * 2, h - (margin + 8) * 2)
    nvgStrokeColor(texVg, nvgRGBA(r, g, b, 255))
    nvgStrokeWidth(texVg, 3)
    nvgStroke(texVg)

    nvgEndFrame(texVg)
    nvgSetRenderTarget(texVg, nil)

    print("[CardTextures] Safe glow border texture created (" .. w .. "x" .. h .. ")")
    return safeGlowTex
end

-- ---------------------------------------------------------------------------
-- 地标光晕纹理 (金色发光边框, 与卡牌同比例 256x360)
-- ---------------------------------------------------------------------------

function M.getLandmarkGlowTexture()
    if landmarkGlowTex then return landmarkGlowTex end
    if not texVg then return nil end

    local w, h = TEX_W, TEX_H

    landmarkGlowTex = Texture2D:new()
    landmarkGlowTex:SetNumLevels(1)
    landmarkGlowTex:SetSize(w, h, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    landmarkGlowTex:SetFilterMode(FILTER_BILINEAR)

    nvgSetRenderTarget(texVg, landmarkGlowTex)
    nvgBeginFrame(texVg, w, h, 1.0)
    nvgTranslate(texVg, 0, h)
    nvgScale(texVg, 1, -1)

    -- 清透明
    nvgBeginPath(texVg)
    nvgRect(texVg, 0, 0, w, h)
    nvgFillColor(texVg, nvgRGBA(0, 0, 0, 0))
    nvgFill(texVg)

    -- 多层发光边框 (金色)
    local r, g, b = 255, 200, 60
    local margin = 6

    -- 外发光层
    nvgBeginPath(texVg)
    nvgRect(texVg, margin, margin, w - margin * 2, h - margin * 2)
    nvgStrokeColor(texVg, nvgRGBA(r, g, b, 120))
    nvgStrokeWidth(texVg, 16)
    nvgStroke(texVg)

    -- 中间发光层
    nvgBeginPath(texVg)
    nvgRect(texVg, margin + 4, margin + 4, w - (margin + 4) * 2, h - (margin + 4) * 2)
    nvgStrokeColor(texVg, nvgRGBA(r, g, b, 200))
    nvgStrokeWidth(texVg, 8)
    nvgStroke(texVg)

    -- 内层实线边框
    nvgBeginPath(texVg)
    nvgRect(texVg, margin + 8, margin + 8, w - (margin + 8) * 2, h - (margin + 8) * 2)
    nvgStrokeColor(texVg, nvgRGBA(255, 220, 100, 255))
    nvgStrokeWidth(texVg, 3)
    nvgStroke(texVg)

    nvgEndFrame(texVg)
    nvgSetRenderTarget(texVg, nil)

    print("[CardTextures] Landmark glow border texture created (" .. w .. "x" .. h .. ")")
    return landmarkGlowTex
end

return M
