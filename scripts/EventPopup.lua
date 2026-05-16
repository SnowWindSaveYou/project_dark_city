-- ============================================================================
-- EventPopup.lua - 事件弹窗系统
-- 翻牌后弹出动画弹窗，展示事件内容、资源变化预览、确认按钮
-- 入场: 缩放弹入(easeOutBack) + 内容逐行错时渐入
-- 退场: 缩放收回(easeInBack) + 淡出
-- ============================================================================

local Tween        = require "lib.Tween"
local Theme        = require "Theme"
local ResourceBar  = require "ResourceBar"
local EventPool    = require "EventPool"
local CardImageMap = require "CardImageMap"
local MonsterGhost = require "MonsterGhost"

local M = {}

-- ---------------------------------------------------------------------------
-- NVG 图像缓存 (懒加载, 用于相片弹窗中渲染场景图和怪物chibi)
-- ---------------------------------------------------------------------------
local nvgImageCache_ = {}   -- path → handle

local function getNvgImage(vg, path)
    if not path then return -1 end
    if nvgImageCache_[path] then return nvgImageCache_[path] end
    local handle = nvgCreateImage(vg, path, 0)
    nvgImageCache_[path] = (handle and handle > 0) and handle or -1
    return nvgImageCache_[path]
end

-- 资源中文名 / 图标
local resourceMeta = {
    san         = { icon = "🧠", label = "理智" },
    health      = { icon = "❤️",  label = "健康" },
    inspiration = { icon = "✨", label = "灵感" },
    film        = { icon = "🎞️",  label = "胶卷" },
    dailyFilm   = { icon = "🎞️",  label = "每日胶卷" },
    permFilm    = { icon = "🎞️",  label = "长期胶卷" },
    money       = { icon = "💰", label = "钱币" },
}

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

---@class PopupState
---@field active boolean
---@field phase string "enter"|"idle"|"exit"|"done"
---@field cardType string
---@field title string
---@field desc string
---@field effects table
---@field cx number 弹窗中心 X（逻辑坐标）
---@field cy number 弹窗中心 Y
---@field onDismiss function|nil 关闭后回调
---@field isPhoto boolean 是否为相片预览模式
---@field baiiye string|nil 白夜的碎碎念台词（可选彩蛋）

local state = {
    active = false,
    phase = "done",
    cardType = "safe",
    title = "",
    desc = "",
    effects = {},
    cx = 0, cy = 0,
    onDismiss = nil,
    isPhoto = false,           -- 相片预览模式 (拍立得风格)
    isEvent = false,           -- 事件结果模式 (替代 toast, 显示 effects + 确认按钮)
    baiiye = nil,              -- 白夜碎碎念台词（可选彩蛋）
    photoLocation = nil,       -- 相片对应的地点
    photoScenePath = nil,      -- 场景图 NVG 图片路径
    monsterChibiPath = nil,    -- 怪物 chibi 图片路径 (仅 monster 类型)
    eventEffects = {},         -- 已结算的资源变化 [{资源key, 增量}]
    eventShieldUsed = false,   -- 护盾是否生效
    -- 确认按钮 hover 状态
    confirmBtnHoverT = 0,
    confirmBtnX = 0, confirmBtnY = 0, confirmBtnW = 0, confirmBtnH = 0,

    -- 动画参数
    overlayAlpha = 0,
    popupScale = 0,
    popupAlpha = 0,
    photoRotation = 0,     -- 相片微倾角度 (度)

    -- 内容逐行入场进度 (0~1 each)
    iconT      = 0,
    titleT     = 0,
    descT      = 0,
    effectsT   = 0,
    buttonT    = 0,

    -- 按钮 hover
    btnHoverT  = 0,
}

-- ---------------------------------------------------------------------------
-- 弹窗尺寸
-- ---------------------------------------------------------------------------
local POPUP_W   = 260
local POPUP_H   = 220
local POPUP_R   = 14
local BTN_W     = 100
local BTN_H     = 32
local BTN_R     = 8

-- ---------------------------------------------------------------------------
-- 打开弹窗
-- ---------------------------------------------------------------------------

--- 打开事件弹窗
---@param cardType string 卡牌类型
---@param cx number 弹窗出现的中心 X（逻辑坐标）
---@param cy number 弹窗出现的中心 Y
---@param onDismiss function|nil 关闭后的回调（资源结算等）
---@param location string|nil 地点类型，用于显示暗面世界名称
function M.show(cardType, cx, cy, onDismiss, location)
    -- 随机选取文案
    local pool = EventPool.TEMPLATES[cardType]
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    -- 暗面世界标题：优先使用地点+事件类型对应的暗面名称
    local darkInfo = location and EventPool.getDarksideInfo(location, cardType) or nil
    local displayTitle = darkInfo and darkInfo.label or tmpl.title

    state.active = true
    state.phase = "enter"
    state.cardType = cardType
    state.title = displayTitle
    state.desc = tmpl.desc
    state.baiiye = nil  -- 普通弹窗不显示白夜台词
    state.effects = (cardType == "monster")
        and EventPool.getMonsterEffects(ResourceBar.get("inspiration"))
        or (EventPool.CARD_EFFECTS[cardType] or {})
    state.cx = cx
    state.cy = cy
    state.onDismiss = onDismiss

    -- 重置动画值
    state.overlayAlpha = 0
    state.popupScale = 0.3
    state.popupAlpha = 0
    state.iconT = 0
    state.titleT = 0
    state.descT = 0
    state.effectsT = 0
    state.buttonT = 0
    state.btnHoverT = 0

    -- 弹窗整体入场
    Tween.to(state, { overlayAlpha = 0.45, popupScale = 1.0, popupAlpha = 1.0 }, 0.35, {
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })

    -- 内容逐行错时入场
    local base = 0.12
    local stagger = 0.08
    Tween.to(state, { iconT = 1 }, 0.3, {
        delay = base,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })
    Tween.to(state, { titleT = 1 }, 0.3, {
        delay = base + stagger,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })
    Tween.to(state, { descT = 1 }, 0.3, {
        delay = base + stagger * 2,
        easing = Tween.Easing.easeOutCubic,
        tag = "popup",
    })
    Tween.to(state, { effectsT = 1 }, 0.25, {
        delay = base + stagger * 3,
        easing = Tween.Easing.easeOutCubic,
        tag = "popup",
    })
    Tween.to(state, { buttonT = 1 }, 0.3, {
        delay = base + stagger * 4,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
        onComplete = function()
            state.phase = "idle"
        end
    })

    print(string.format("[EventPopup] Show: %s - %s", cardType, tmpl.title))
end

-- ---------------------------------------------------------------------------
-- 打开相片预览弹窗 (拍立得/底片风格，仅预览不结算)
-- ---------------------------------------------------------------------------

--- 打开相片预览弹窗
---@param cardType string 卡牌事件类型
---@param cx number 弹窗中心 X
---@param cy number 弹窗中心 Y
---@param onDismiss function|nil 关闭后回调
---@param location string|nil 地点类型
function M.showPhoto(cardType, cx, cy, onDismiss, location)
    -- 随机选取文案：优先地点专属池，fallback 通用池
    local pool = (location
        and EventPool.LOCATION_EVENT_TEMPLATES
        and EventPool.LOCATION_EVENT_TEMPLATES[location]
        and EventPool.LOCATION_EVENT_TEMPLATES[location][cardType])
        or EventPool.TEMPLATES[cardType]
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    -- 暗面世界标题
    local darkInfo = location and EventPool.getDarksideInfo(location, cardType) or nil
    local displayTitle = (darkInfo and darkInfo.label) or tmpl.title

    -- 事件图路径: 优先地点专属事件图，fallback 通用事件图
    local sceneFile = location and CardImageMap.getEventImage(location, cardType)
    local scenePath = sceneFile and ("image/" .. sceneFile) or nil

    -- 怪物 chibi: 仅 monster 类型
    local chibiPath = nil
    if cardType == "monster" and location then
        chibiPath = MonsterGhost.getMonsterTexture(location)
    end

    state.active = true
    state.phase = "enter"
    state.cardType = cardType
    state.title = displayTitle
    state.desc = tmpl.desc
    state.baiiye = tmpl.baiiye or nil
    state.effects = {}  -- 相片预览不显示资源变化
    state.cx = cx
    state.cy = cy
    state.onDismiss = onDismiss
    state.isPhoto = true
    state.photoLocation = location
    state.photoScenePath = scenePath
    state.monsterChibiPath = chibiPath

    -- 重置动画值
    state.overlayAlpha = 0
    state.popupScale = 0.2
    state.popupAlpha = 0
    state.photoRotation = math.random(-5, 5)  -- 随机微倾
    state.iconT = 0
    state.titleT = 0
    state.descT = 0
    state.effectsT = 0
    state.buttonT = 0
    state.btnHoverT = 0

    -- 相片入场：快速弹入 + 轻微弹跳
    Tween.to(state, { overlayAlpha = 0.5, popupScale = 1.0, popupAlpha = 1.0 }, 0.3, {
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })

    -- 内容入场 (相片模式更快)
    local base = 0.08
    Tween.to(state, { iconT = 1 }, 0.25, {
        delay = base,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })
    Tween.to(state, { titleT = 1 }, 0.25, {
        delay = base + 0.06,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })
    Tween.to(state, { descT = 1 }, 0.25, {
        delay = base + 0.12,
        easing = Tween.Easing.easeOutCubic,
        tag = "popup",
    })
    Tween.to(state, { buttonT = 1 }, 0.25, {
        delay = base + 0.18,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
        onComplete = function()
            state.phase = "idle"
        end
    })

    print(string.format("[EventPopup] ShowPhoto: %s - %s | location=%s baiiye=%s",
        cardType, displayTitle, tostring(location), tostring(state.baiiye)))
end

-- ---------------------------------------------------------------------------
-- 打开事件结果弹窗 (阻塞式, 替代 toast)
-- 显示笔记本+拍立得布局 + 已结算 effects + 确认按钮
-- ---------------------------------------------------------------------------

--- 打开事件结果弹窗
---@param cardType string 卡牌事件类型
---@param appliedEffects table 已结算资源变化 {{ "san", -1 }, ...}
---@param shieldUsed boolean 护盾是否生效
---@param cx number 弹窗中心 X
---@param cy number 弹窗中心 Y
---@param onDismiss function|nil 关闭后回调
---@param location string|nil 地点类型
---@param trapSubtype string|nil 陷阱子类型
function M.showEvent(cardType, appliedEffects, shieldUsed, cx, cy, onDismiss, location, trapSubtype, titleOverride, descOverride)
    -- 文案: 陷阱子类型专属池 → 地点专属池 → 通用池
    local pool
    if cardType == "trap" and trapSubtype and EventPool.TRAP_SUBTYPE_TEMPLATES and EventPool.TRAP_SUBTYPE_TEMPLATES[trapSubtype] then
        pool = EventPool.TRAP_SUBTYPE_TEMPLATES[trapSubtype]
    else
        pool = (location
            and EventPool.LOCATION_EVENT_TEMPLATES
            and EventPool.LOCATION_EVENT_TEMPLATES[location]
            and EventPool.LOCATION_EVENT_TEMPLATES[location][cardType])
            or EventPool.TEMPLATES[cardType]
    end
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    -- 暗面世界标题 (外部 override 优先)
    local darkInfo = location and EventPool.getDarksideInfo(location, cardType) or nil
    local displayTitle = titleOverride or (darkInfo and darkInfo.label) or tmpl.title

    -- 事件图 (优先地点专属事件图，fallback 通用事件图)
    local sceneFile = location and CardImageMap.getEventImage(location, cardType)
    local scenePath = sceneFile and ("image/" .. sceneFile) or nil

    -- 怪物 chibi 叠加
    local chibiPath = nil
    if cardType == "monster" and location then
        chibiPath = MonsterGhost.getMonsterTexture(location)
    end

    state.active = true
    state.phase = "enter"
    state.cardType = cardType
    state.title = displayTitle
    state.desc = descOverride or tmpl.desc
    state.baiiye = (not descOverride) and (tmpl.baiiye or nil) or nil
    state.effects = {}      -- 不用于 drawPopup, 仅 isEvent 模式用 eventEffects
    state.cx = cx
    state.cy = cy
    state.onDismiss = onDismiss
    state.isPhoto = true        -- 复用相片布局渲染
    state.isEvent = true
    state.photoLocation = location
    state.photoScenePath = scenePath
    state.monsterChibiPath = chibiPath
    state.eventEffects = appliedEffects or {}
    state.eventShieldUsed = shieldUsed or false
    state.confirmBtnHoverT = 0

    -- 重置动画
    state.overlayAlpha = 0
    state.popupScale = 0.2
    state.popupAlpha = 0
    state.photoRotation = math.random(-4, 4)
    state.iconT = 0
    state.titleT = 0
    state.descT = 0
    state.effectsT = 0
    state.buttonT = 0
    state.btnHoverT = 0

    Tween.to(state, { overlayAlpha = 0.5, popupScale = 1.0, popupAlpha = 1.0 }, 0.3, {
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })

    local base = 0.08
    Tween.to(state, { iconT = 1 }, 0.25, {
        delay = base,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })
    Tween.to(state, { titleT = 1 }, 0.25, {
        delay = base + 0.06,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
    })
    Tween.to(state, { effectsT = 1 }, 0.25, {
        delay = base + 0.12,
        easing = Tween.Easing.easeOutCubic,
        tag = "popup",
    })
    Tween.to(state, { descT = 1 }, 0.25, {
        delay = base + 0.18,
        easing = Tween.Easing.easeOutCubic,
        tag = "popup",
    })
    Tween.to(state, { buttonT = 1 }, 0.25, {
        delay = base + 0.24,
        easing = Tween.Easing.easeOutBack,
        tag = "popup",
        onComplete = function()
            state.phase = "idle"
        end
    })

    print(string.format("[EventPopup] ShowEvent: %s - %s (shield=%s) | location=%s baiiye=%s",
        cardType, displayTitle, tostring(shieldUsed), tostring(location), tostring(state.baiiye)))
end

-- ---------------------------------------------------------------------------
-- 关闭弹窗
-- ---------------------------------------------------------------------------

function M.dismiss()
    if not state.active or state.phase == "exit" then return end
    state.phase = "exit"

    Tween.cancelTag("popup")

    Tween.to(state, {
        overlayAlpha = 0,
        popupScale = 0.5,
        popupAlpha = 0,
        iconT = 0, titleT = 0, descT = 0, effectsT = 0, buttonT = 0,
    }, 0.22, {
        easing = Tween.Easing.easeInBack,
        tag = "popup",
        onComplete = function()
            state.active = false
            state.phase = "done"
            state.isPhoto = false
            state.isEvent = false
            state.photoLocation = nil
            state.eventEffects = {}
            state.eventShieldUsed = false
            if state.onDismiss then
                state.onDismiss(state.cardType, state.effects)
            end
        end
    })
end

-- ---------------------------------------------------------------------------
-- 查询
-- ---------------------------------------------------------------------------

function M.isActive()
    return state.active
end

-- ---------------------------------------------------------------------------
-- 按钮碰撞检测（逻辑坐标）
-- ---------------------------------------------------------------------------

local function btnRect()
    local bx = state.cx - BTN_W / 2
    local by = state.cy + POPUP_H / 2 - BTN_H - 16
    return bx, by, BTN_W, BTN_H
end

--- 检测点击是否在弹窗按钮上
function M.hitTestButton(lx, ly)
    if not state.active then return false end
    local bx, by, bw, bh = btnRect()
    return lx >= bx and lx <= bx + bw and ly >= by and ly <= by + bh
end

--- 检测点击是否在弹窗面板内
function M.hitTestPanel(lx, ly)
    if not state.active then return false end
    local px = state.cx - POPUP_W / 2
    local py = state.cy - POPUP_H / 2
    return lx >= px and lx <= px + POPUP_W and ly >= py and ly <= py + POPUP_H
end

--- 处理点击：按钮 → 关闭；面板内 → 吃掉事件；面板外 → 也关闭
---@return boolean consumed 是否消费了此次点击
function M.handleClick(lx, ly)
    if not state.active then return false end

    if state.phase == "enter" then
        -- 入场动画中不处理点击，但吃掉事件
        return true
    end

    -- 相片模式: 点击任意处关闭
    if state.isPhoto then
        M.dismiss()
        return true
    end

    if M.hitTestButton(lx, ly) then
        M.dismiss()
        return true
    end

    -- 面板外点击也关闭
    if not M.hitTestPanel(lx, ly) then
        M.dismiss()
        return true
    end

    -- 面板内但非按钮，吃掉事件
    return true
end

-- ---------------------------------------------------------------------------
-- Hover 更新（每帧调用）
-- ---------------------------------------------------------------------------

function M.updateHover(lx, ly, dt)
    if not state.active or state.phase ~= "idle" then
        state.btnHoverT = state.btnHoverT + (0 - state.btnHoverT) * math.min(1, dt * 12)
        state.confirmBtnHoverT = state.confirmBtnHoverT + (0 - state.confirmBtnHoverT) * math.min(1, dt * 12)
        return
    end
    local target = M.hitTestButton(lx, ly) and 1.0 or 0.0
    state.btnHoverT = state.btnHoverT + (target - state.btnHoverT) * math.min(1, dt * 12)

    -- 事件模式确认按钮 hover
    if state.isEvent and state.confirmBtnW > 0 then
        local inBtn = lx >= state.confirmBtnX and lx <= state.confirmBtnX + state.confirmBtnW
                   and ly >= state.confirmBtnY and ly <= state.confirmBtnY + state.confirmBtnH
        local cTarget = inBtn and 1.0 or 0.0
        state.confirmBtnHoverT = state.confirmBtnHoverT + (cTarget - state.confirmBtnHoverT) * math.min(1, dt * 12)
    else
        state.confirmBtnHoverT = state.confirmBtnHoverT + (0 - state.confirmBtnHoverT) * math.min(1, dt * 12)
    end
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.active then return end

    -- 分流：相片模式用专用渲染
    if state.isPhoto then
        M.drawPhoto(vg, logicalW, logicalH, gameTime)
        return
    end

    local t = Theme.current

    -- === 遮罩层 ===
    if state.overlayAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(state.overlayAlpha * 255)))
        nvgFill(vg)
    end

    -- === 弹窗面板 ===
    nvgSave(vg)
    nvgTranslate(vg, state.cx, state.cy)
    nvgScale(vg, state.popupScale, state.popupScale)
    nvgGlobalAlpha(vg, state.popupAlpha)

    local hw = POPUP_W / 2
    local hh = POPUP_H / 2

    -- 阴影
    local shadowP = nvgBoxGradient(vg, -hw + 2, -hh + 4, POPUP_W, POPUP_H, POPUP_R, 16,
        nvgRGBA(0, 0, 0, 70), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, -hw - 20, -hh - 16, POPUP_W + 40, POPUP_H + 40)
    nvgFillPaint(vg, shadowP)
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, POPUP_W, POPUP_H, POPUP_R)
    nvgFillColor(vg, nvgRGBA(t.panelBg.r, t.panelBg.g, t.panelBg.b, 245))
    nvgFill(vg)

    -- 面板边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, POPUP_W, POPUP_H, POPUP_R)
    nvgStrokeColor(vg, Theme.rgbaA(t.panelBorder, 120))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- 顶部色条
    local tc = Theme.cardTypeColor(state.cardType)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw + 4, -hh + 4, POPUP_W - 8, 5, 3)
    nvgFillColor(vg, Theme.rgbaA(tc, 200))
    nvgFill(vg)

    -- === 内容（逐行错时入场）===
    local info = Theme.cardTypeInfo(state.cardType)
    local contentY = -hh + 22

    -- 图标
    if state.iconT > 0.01 then
        nvgSave(vg)
        local iconScale = state.iconT
        nvgTranslate(vg, 0, contentY + 12)
        nvgScale(vg, iconScale, iconScale)
        nvgGlobalAlpha(vg, state.popupAlpha * state.iconT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        nvgText(vg, 0, 0, info and info.icon or "❓", nil)
        nvgRestore(vg)
    end
    contentY = contentY + 36

    -- 标题
    if state.titleT > 0.01 then
        nvgSave(vg)
        local titleOff = (1 - state.titleT) * 15
        nvgGlobalAlpha(vg, state.popupAlpha * state.titleT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, Theme.rgba(tc))
        nvgText(vg, 0, contentY + titleOff, state.title, nil)
        nvgRestore(vg)
    end
    contentY = contentY + 26

    -- 描述文字（自动换行）
    if state.descT > 0.01 then
        nvgSave(vg)
        local descOff = (1 - state.descT) * 10
        nvgGlobalAlpha(vg, state.popupAlpha * state.descT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 220))

        local textPadding = 20
        local maxW = POPUP_W - textPadding * 2
        nvgTextBox(vg, -hw + textPadding, contentY + descOff, maxW, state.desc, nil)
        nvgRestore(vg)
    end
    contentY = contentY + 48

    -- 资源变化预览徽章
    if #state.effects > 0 and state.effectsT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, state.popupAlpha * state.effectsT)

        local badgeH = 22
        local badgeGap = 8
        local totalBadges = #state.effects
        local badgeWidths = {}
        local totalBadgeW = 0

        -- 先测量每个徽章宽度
        for idx, eff in ipairs(state.effects) do
            local meta = resourceMeta[eff[1]]
            local label = (meta and meta.icon or "") .. " " .. (eff[2] > 0 and "+" or "") .. eff[2]
            -- 估算宽度
            local w = #label * 7 + 16
            badgeWidths[idx] = w
            totalBadgeW = totalBadgeW + w
        end
        totalBadgeW = totalBadgeW + (totalBadges - 1) * badgeGap

        local bx = -totalBadgeW / 2
        local by = contentY

        for idx, eff in ipairs(state.effects) do
            local meta = resourceMeta[eff[1]]
            local icon = meta and meta.icon or "?"
            local delta = eff[2]
            local label = icon .. " " .. (delta > 0 and "+" or "") .. delta
            local bw = badgeWidths[idx]

            -- 逐个延迟入场
            local individualT = math.max(0, state.effectsT - (idx - 1) * 0.15)
            individualT = math.min(1, individualT / 0.7)

            if individualT > 0.01 then
                local badgeScale = individualT
                nvgSave(vg)
                nvgTranslate(vg, bx + bw / 2, by + badgeH / 2)
                nvgScale(vg, badgeScale, badgeScale)

                -- 背景
                local bgColor = delta > 0 and t.safe or t.danger
                nvgBeginPath(vg)
                nvgRoundedRect(vg, -bw / 2, -badgeH / 2, bw, badgeH, badgeH / 2)
                nvgFillColor(vg, Theme.rgbaA(bgColor, 40))
                nvgFill(vg)
                nvgStrokeColor(vg, Theme.rgbaA(bgColor, 100))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)

                -- 文字
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, Theme.rgbaA(delta > 0 and t.safe or t.danger, 230))
                nvgText(vg, 0, 0, label, nil)

                nvgRestore(vg)
            end

            bx = bx + bw + badgeGap
        end

        nvgRestore(vg)
    end

    -- === 确认按钮 ===
    if state.buttonT > 0.01 then
        nvgSave(vg)
        local btnY = hh - BTN_H - 16
        local btnOff = (1 - state.buttonT) * 20
        nvgTranslate(vg, 0, btnY + BTN_H / 2 + btnOff)
        nvgScale(vg, state.buttonT, state.buttonT)
        nvgGlobalAlpha(vg, state.popupAlpha * state.buttonT)

        -- 按钮背景
        local hoverLerp = state.btnHoverT
        local btnR = math.floor(tc.r + (255 - tc.r) * hoverLerp * 0.15)
        local btnG = math.floor(tc.g + (255 - tc.g) * hoverLerp * 0.15)
        local btnB = math.floor(tc.b + (255 - tc.b) * hoverLerp * 0.15)
        local btnScale = 1.0 + hoverLerp * 0.05

        nvgScale(vg, btnScale, btnScale)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, -BTN_W / 2, -BTN_H / 2, BTN_W, BTN_H, BTN_R)
        nvgFillColor(vg, nvgRGBA(btnR, btnG, btnB, 220))
        nvgFill(vg)

        -- 按钮高光
        if hoverLerp > 0.01 then
            local glowP = nvgBoxGradient(vg, -BTN_W / 2 - 2, -BTN_H / 2 - 2,
                BTN_W + 4, BTN_H + 4, BTN_R + 1, 6,
                nvgRGBA(255, 255, 255, math.floor(hoverLerp * 30)),
                nvgRGBA(255, 255, 255, 0))
            nvgBeginPath(vg)
            nvgRect(vg, -BTN_W / 2 - 10, -BTN_H / 2 - 10, BTN_W + 20, BTN_H + 20)
            nvgFillPaint(vg, glowP)
            nvgFill(vg)
        end

        -- 按钮文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, 0, 0, "确认", nil)

        nvgRestore(vg)
    end

    nvgRestore(vg)  -- 弹窗整体 transform
end

-- ---------------------------------------------------------------------------
-- 渲染: 相片预览模式 (笔记本底板 + 倾斜拍立得卡溢出 + 右侧文字区)
-- ---------------------------------------------------------------------------

-- 笔记本容器尺寸
local NB_W          = 300     -- 笔记本宽
local NB_H          = 200     -- 笔记本高
local NB_R          = 8       -- 笔记本圆角
local NB_PAD        = 12      -- 内边距

-- 拍立得卡尺寸 (卡牌比例 256:360 = 0.711)
local POL_IMG_W     = 104     -- 内图区宽
local POL_IMG_H     = 146     -- 内图区高 (104 * 360/256 ≈ 146)
local POL_SIDE      = 9       -- 左/右/上白边宽
local POL_BOTTOM    = 32      -- 底部白边 (拍立得特征)
local POL_W         = POL_IMG_W + POL_SIDE * 2     -- 总宽 122
local POL_H         = POL_IMG_H + POL_SIDE + POL_BOTTOM  -- 总高 187
local POL_R         = 3       -- 整体圆角
local POL_IMG_R     = 2       -- 内图区圆角

-- 拍立得相对于笔记本中心的偏移 (左边溢出笔记本约 35px)
local POL_CENTER_X  = -(NB_W / 2) + (POL_W / 2) - 30   -- cx_nb - 150 + 61 - 30 = cx_nb - 119

-- 文字区起始 X (相对笔记本左边)
-- 拍立得右边缘相对弹窗中心 = POL_CENTER_X + POL_W/2 = (-119) + 61 = -58
-- 文字起点转换: txStartX = -NB_W/2 + TEXT_AREA_X
-- 要让 txStartX > -58 (即在拍立得右边缘之外), 需 TEXT_AREA_X > (-58 + NB_W/2) = 92
local TEXT_AREA_X   = 98                                  -- txStartX = -150+98 = -52, 拍立得右边缘 -58 右侧 6px
local TEXT_AREA_W   = NB_W - TEXT_AREA_X - NB_PAD        -- 300 - 98 - 12 = 190px

function M.drawPhoto(vg, logicalW, logicalH, gameTime)
    local t = Theme.current
    local tc = Theme.cardTypeColor(state.cardType)
    local info = Theme.cardTypeInfo(state.cardType)

    -- 懒加载 NVG 图像句柄
    local sceneImg  = getNvgImage(vg, state.photoScenePath)
    local chibiImg  = (state.monsterChibiPath) and getNvgImage(vg, state.monsterChibiPath) or -1

    -- === 遮罩层 ===
    if state.overlayAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(state.overlayAlpha * 255)))
        nvgFill(vg)
    end

    -- === 弹窗整体 transform (缩放入场) ===
    nvgSave(vg)
    nvgTranslate(vg, state.cx, state.cy)
    nvgScale(vg, state.popupScale, state.popupScale)
    nvgGlobalAlpha(vg, state.popupAlpha)

    -- ==================================================================
    -- 1. 笔记本底板
    -- ==================================================================
    local nbX = -NB_W / 2
    local nbY = -NB_H / 2

    -- 笔记本阴影
    local shadowP = nvgBoxGradient(vg, nbX + 2, nbY + 4, NB_W, NB_H, NB_R, 18,
        nvgRGBA(0, 0, 0, 55), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, nbX - 20, nbY - 14, NB_W + 40, NB_H + 36)
    nvgFillPaint(vg, shadowP)
    nvgFill(vg)

    -- 笔记本背景 (奶白色纸质感)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nbX, nbY, NB_W, NB_H, NB_R)
    nvgFillColor(vg, nvgRGBA(250, 246, 238, 252))
    nvgFill(vg)

    -- 笔记本边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nbX, nbY, NB_W, NB_H, NB_R)
    nvgStrokeColor(vg, nvgRGBA(196, 184, 164, 180))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- 左侧红色竖线装饰 (笔记本特征)
    local redLineX = nbX + 42
    nvgBeginPath(vg)
    nvgMoveTo(vg, redLineX, nbY + 6)
    nvgLineTo(vg, redLineX, nbY + NB_H - 6)
    nvgStrokeColor(vg, nvgRGBA(200, 85, 85, 130))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- 横线装饰 (笔记本稿纸风格)
    local lineSpacing = 22
    local lineStartY  = nbY + 28
    local lineEndX    = nbX + NB_W - NB_PAD
    nvgStrokeWidth(vg, 0.6)
    for li = 0, 6 do
        local ly = lineStartY + li * lineSpacing
        if ly < nbY + NB_H - 12 then
            nvgBeginPath(vg)
            nvgMoveTo(vg, redLineX + 6, ly)
            nvgLineTo(vg, lineEndX, ly)
            nvgStrokeColor(vg, nvgRGBA(197, 212, 232, 90))
            nvgStroke(vg)
        end
    end

    -- ==================================================================
    -- 2. 倾斜的拍立得卡 (叠在笔记本上，左侧溢出)
    -- ==================================================================
    local polCX = POL_CENTER_X   -- 相对弹窗中心
    local polCY = 0

    nvgSave(vg)
    nvgTranslate(vg, polCX, polCY)
    nvgRotate(vg, state.photoRotation * math.pi / 180)

    -- 拍立得阴影
    local psx = -POL_W / 2
    local psy = -POL_H / 2
    local polShadow = nvgBoxGradient(vg, psx + 2, psy + 4, POL_W, POL_H, POL_R, 16,
        nvgRGBA(30, 20, 10, 80), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, psx - 18, psy - 14, POL_W + 36, POL_H + 32)
    nvgFillPaint(vg, polShadow)
    nvgFill(vg)

    -- 拍立得白底 (奶白色相纸)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, psx, psy, POL_W, POL_H, POL_R)
    nvgFillColor(vg, nvgRGBA(253, 251, 246, 255))
    nvgFill(vg)

    -- 拍立得外框线
    nvgBeginPath(vg)
    nvgRoundedRect(vg, psx, psy, POL_W, POL_H, POL_R)
    nvgStrokeColor(vg, nvgRGBA(210, 200, 185, 140))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- 内图区位置
    local imgX = psx + POL_SIDE
    local imgY = psy + POL_SIDE
    local imgW = POL_IMG_W
    local imgH = POL_IMG_H

    -- 内图区底色 (深色, 以防图片未加载)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, imgX, imgY, imgW, imgH, POL_IMG_R)
    nvgFillColor(vg, nvgRGBA(30, 35, 45, 240))
    nvgFill(vg)

    -- 场景图片 (aspect-fill: 保持宽高比填满图区，居中裁剪)
    if sceneImg > 0 then
        nvgSave(vg)
        nvgScissor(vg, imgX, imgY, imgW, imgH)
        -- 获取图片原始尺寸，计算 aspect-fill 缩放
        local srcW, srcH = nvgImageSize(vg, sceneImg)
        local scaleX = imgW / (srcW > 0 and srcW or imgW)
        local scaleY = imgH / (srcH > 0 and srcH or imgH)
        local scale  = math.max(scaleX, scaleY)   -- fill: 取较大值确保无黑边
        local dstW   = (srcW > 0 and srcW or imgW) * scale
        local dstH   = (srcH > 0 and srcH or imgH) * scale
        local dstX   = imgX + (imgW - dstW) * 0.5  -- 居中
        local dstY   = imgY + (imgH - dstH) * 0.5
        local imgPaint = nvgImagePattern(vg, dstX, dstY, dstW, dstH, 0, sceneImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, imgX, imgY, imgW, imgH, POL_IMG_R)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    else
        -- 场景图加载失败时, 显示事件图标作为占位
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 120))
        nvgText(vg, imgX + imgW / 2, imgY + imgH / 2, info and info.icon or "📷", nil)
    end

    -- 怪物 chibi 叠加 (仅 monster 类型)
    if chibiImg > 0 then
        nvgSave(vg)
        nvgScissor(vg, imgX, imgY, imgW, imgH)
        -- chibi 居中偏下, 大小约占图区 85%
        local chibiW = imgW * 0.85
        local chibiH = chibiW  -- 假设 chibi 接近正方形
        local chibiX = imgX + (imgW - chibiW) / 2
        local chibiY = imgY + imgH - chibiH + chibiH * 0.15  -- 底部对齐带轻微裁剪
        local chibiPaint = nvgImagePattern(vg, chibiX, chibiY, chibiW, chibiH, 0, chibiImg, 0.92)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, imgX, imgY, imgW, imgH, POL_IMG_R)
        nvgFillPaint(vg, chibiPaint)
        nvgFill(vg)
        nvgResetScissor(vg)
        nvgRestore(vg)
    end

    -- 照片暗角 (镜头效果)
    local vigPaint = nvgBoxGradient(vg, imgX, imgY, imgW, imgH, POL_IMG_R, imgW * 0.4,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 70))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, imgX, imgY, imgW, imgH, POL_IMG_R)
    nvgFillPaint(vg, vigPaint)
    nvgFill(vg)

    -- 照片内边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, imgX, imgY, imgW, imgH, POL_IMG_R)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 50))
    nvgStrokeWidth(vg, 0.6)
    nvgStroke(vg)

    -- 底部白标签区: 事件类型 (上行) + 地点 (下行)
    local labelY = imgY + imgH + 4
    if state.buttonT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, state.popupAlpha * state.buttonT)

        local typeLabel = (info and info.label) or state.cardType
        local typeIcon  = (info and info.icon) or "❓"

        -- 事件类型 + 地点并排（同一行居中）
        local locInfo = state.photoLocation and EventPool.LOCATION_INFO[state.photoLocation]
        local bottomText = typeIcon .. " " .. typeLabel
        if locInfo then
            bottomText = bottomText .. "  " .. locInfo.icon .. " " .. locInfo.label
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(tc, 200))
        nvgText(vg, 0, labelY + (POL_BOTTOM - 4) / 2, bottomText, nil)

        nvgRestore(vg)
    end

    nvgRestore(vg)  -- 拍立得 transform (旋转)

    -- ==================================================================
    -- 3. 笔记本右侧文字区
    -- ==================================================================
    -- 文字区相对于弹窗中心的起点X
    local txStartX = -NB_W / 2 + TEXT_AREA_X
    local txY      = -NB_H / 2 + 16  -- 距笔记本顶部 16px（地点移走后稍微上移）

    -- 事件名 (大字, 关键信息)
    if state.titleT > 0.01 then
        nvgSave(vg)
        local titleSlide = (1 - state.titleT) * 14
        nvgGlobalAlpha(vg, state.popupAlpha * state.titleT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(45, 38, 28, 230))
        nvgText(vg, txStartX + titleSlide, txY, state.title, nil)

        nvgRestore(vg)
    end
    txY = txY + 22

    if state.isEvent then
        -- ---------------------------------------------------------------
        -- 事件结果模式: 护盾/effects 列表 + 确认按钮
        -- ---------------------------------------------------------------
        if state.effectsT > 0.01 then
            nvgSave(vg)
            nvgGlobalAlpha(vg, state.popupAlpha * state.effectsT)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

            if state.eventShieldUsed then
                -- 护盾格档提示
                nvgFontSize(vg, 12)
                nvgFillColor(vg, nvgRGBA(80, 160, 220, 230))
                nvgText(vg, txStartX, txY + 8, "🧿 护身符抵消伤害", nil)
                txY = txY + 22
            elseif #state.eventEffects == 0 then
                -- 无资源变化
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(120, 110, 90, 180))
                nvgText(vg, txStartX, txY + 8, "无资源变化", nil)
                txY = txY + 20
            else
                -- 流式换行排列 effects（按容器宽度自动折行）
                local ITEM_GAP_X = 8    -- 同行间距
                local ITEM_H     = 17   -- 行高
                local curX = txStartX + 2
                local lineY = txY + 4
                nvgFontSize(vg, 12)
                for i, eff in ipairs(state.eventEffects) do
                    local resKey = eff[1]
                    local delta  = eff[2]
                    local meta   = resourceMeta[resKey]
                    local icon   = meta and meta.icon or "?"
                    local label  = meta and meta.label or resKey
                    local isPos  = delta > 0
                    local sign   = isPos and "+" or ""
                    local text   = icon .. " " .. label .. " " .. sign .. tostring(delta)

                    -- 估算文本宽度（emoji~14px，汉字~12px，ASCII~7px）
                    local estW = #text * 7 + 10  -- 粗估，足够判断是否换行

                    if curX + estW > txStartX + TEXT_AREA_W and curX > txStartX + 2 then
                        -- 换行
                        curX  = txStartX + 2
                        lineY = lineY + ITEM_H
                        if lineY > NB_H / 2 - 50 then break end
                    end

                    local r, g, b = isPos and 70 or 200, isPos and 175 or 65, isPos and 90 or 65
                    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
                    nvgText(vg, curX, lineY, text, nil)
                    curX = curX + estW + ITEM_GAP_X
                end
                txY = lineY + ITEM_H  -- txY 推进到 effects 块之后
            end
            nvgRestore(vg)
        end

        -- 描述文字 (小字, 填充 effects 与按钮间空白)
        if state.descT > 0.01 and state.desc ~= "" then
            nvgSave(vg)
            nvgGlobalAlpha(vg, state.popupAlpha * state.descT * 0.75)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(120, 110, 90, 180))
            nvgTextBox(vg, txStartX + 2, txY + 6, TEXT_AREA_W - 6, state.desc, nil)
            nvgRestore(vg)
            txY = txY + 32
        end

        -- 白夜碎碎念（彩蛋，斜体小字）
        if state.descT > 0.01 and state.baiiye and state.baiiye ~= "" then
            nvgSave(vg)
            nvgGlobalAlpha(vg, state.popupAlpha * state.descT * 0.65)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(90, 105, 130, 200))
            nvgText(vg, txStartX + TEXT_AREA_W - 4, txY, "— " .. state.baiiye, nil)
            nvgRestore(vg)
        end

        -- 确认按钮
        if state.buttonT > 0.01 then
            local btnW   = math.min(TEXT_AREA_W - 8, 88)
            local btnH   = 26
            local btnX   = txStartX + (TEXT_AREA_W - btnW) / 2
            local btnY   = NB_H / 2 - btnH - NB_PAD

            -- 记录碰撞区 (转换为弹窗中心相对坐标系 → 屏幕坐标需加 cx/cy, 此处先存偏移)
            state.confirmBtnX = state.cx + btnX
            state.confirmBtnY = state.cy - NB_H / 2 * state.popupScale + (btnY + NB_H / 2) * state.popupScale
            state.confirmBtnW = btnW * state.popupScale
            state.confirmBtnH = btnH * state.popupScale

            nvgSave(vg)
            nvgGlobalAlpha(vg, state.popupAlpha * state.buttonT)

            -- hover 填充
            local hov = state.confirmBtnHoverT
            local btnAlpha = math.floor(180 + hov * 50)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 6)
            nvgFillColor(vg, Theme.rgbaA(tc, btnAlpha))
            nvgFill(vg)

            -- 文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "知道了", nil)

            nvgRestore(vg)
        end
    else
        -- ---------------------------------------------------------------
        -- 相片预览模式: 描述文本 + 点击关闭提示
        -- ---------------------------------------------------------------

        -- 描述文本 (小字, 多行)
        if state.descT > 0.01 then
            nvgSave(vg)
            local descSlide = (1 - state.descT) * 10
            nvgGlobalAlpha(vg, state.popupAlpha * state.descT * 0.85)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(80, 70, 55, 200))
            nvgTextBox(vg, txStartX + descSlide, txY, TEXT_AREA_W - 4, state.desc, nil)

            nvgRestore(vg)
            txY = txY + 40
        end

        -- 白夜碎碎念（彩蛋，右对齐小字）
        if state.descT > 0.01 and state.baiiye and state.baiiye ~= "" then
            nvgSave(vg)
            nvgGlobalAlpha(vg, state.popupAlpha * state.descT * 0.65)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(90, 105, 130, 200))
            nvgText(vg, txStartX + TEXT_AREA_W - 4, txY, "— " .. state.baiiye, nil)
            nvgRestore(vg)
        end

        -- 底部关闭提示 (笔记本右下角)
        if state.buttonT > 0.01 then
            nvgSave(vg)
            nvgGlobalAlpha(vg, state.popupAlpha * state.buttonT * 0.5)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(150, 140, 120, 180))
            nvgText(vg, NB_W / 2 - NB_PAD, NB_H / 2 - 8, "点击任意处关闭", nil)
            nvgRestore(vg)
        end
    end

    nvgRestore(vg)  -- 弹窗整体 transform (缩放)
end

-- ===========================================================================
-- Toast 子系统 (非阻塞卡牌通知)
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- Toast 常量
-- ---------------------------------------------------------------------------
local TOAST_W       = 220    -- 卡牌宽度
local TOAST_R       = 10     -- 圆角
local TOAST_GAP     = 8      -- 堆叠间距
local TOAST_MARGIN_R = 12    -- 右边距
local TOAST_MARGIN_T = 52    -- 顶部距离 (ResourceBar 下方)
local TOAST_MAX     = 3      -- 最多同时可见
local TOAST_IDLE    = 3.0    -- 驻留时间 (秒)
local TOAST_ENTER   = 0.35   -- 入场动画时间
local TOAST_EXIT    = 0.25   -- 退场动画时间

-- ---------------------------------------------------------------------------
-- Toast 状态
-- ---------------------------------------------------------------------------
local toastQueue = {}   -- ToastInstance[] (newest at tail)
local toastNextId = 1

-- ---------------------------------------------------------------------------
-- Toast: 入队
-- ---------------------------------------------------------------------------

--- 推送一条非阻塞事件 Toast
---@param cardType string
---@param appliedEffects table  已结算的资源变化 (可能被护盾清空)
---@param shieldUsed boolean   护盾是否生效
---@param location string|nil  地点类型
---@param trapSubtype string|nil  陷阱子类型 (sanity/money/film/teleport)
function M.toast(cardType, appliedEffects, shieldUsed, location, trapSubtype)
    -- 随机文案: 陷阱子类型使用专属文案池
    local pool
    if cardType == "trap" and trapSubtype and EventPool.TRAP_SUBTYPE_TEMPLATES[trapSubtype] then
        pool = EventPool.TRAP_SUBTYPE_TEMPLATES[trapSubtype]
    else
        pool = EventPool.TEMPLATES[cardType]
    end
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    -- 暗面世界标题
    local darkInfo = location and EventPool.getDarksideInfo(location, cardType) or nil
    local displayTitle = darkInfo and darkInfo.label or tmpl.title

    local id = toastNextId
    toastNextId = toastNextId + 1

    ---@class ToastInstance
    local toast = {
        id = id,
        cardType = cardType,
        trapSubtype = trapSubtype,  -- 陷阱子类型 (nil for non-trap)
        title = displayTitle,
        desc = tmpl.desc,
        effects = appliedEffects or {},
        shieldUsed = shieldUsed or false,
        location = location,

        phase = "enter",   -- "enter" | "idle" | "exit" | "done"
        timer = 0,

        -- 动画属性
        slideX = TOAST_W + TOAST_MARGIN_R + 20,  -- 从右侧屏幕外滑入
        alpha = 0,
        scale = 0.8,
        targetY = 0,   -- 目标 Y 位置 (由堆栈计算)
        currentY = 0,  -- 当前 Y 位置 (动画平滑)

        -- 碰撞检测 (draw 时更新)
        drawX = 0, drawY = 0, drawW = 0, drawH = 0,
    }

    toastQueue[#toastQueue + 1] = toast

    -- 溢出: 强制退场最老的
    local visibleCount = 0
    for i = 1, #toastQueue do
        if toastQueue[i].phase ~= "exit" and toastQueue[i].phase ~= "done" then
            visibleCount = visibleCount + 1
        end
    end
    if visibleCount > TOAST_MAX then
        for i = 1, #toastQueue do
            if toastQueue[i].phase ~= "exit" and toastQueue[i].phase ~= "done" then
                toastQueue[i].phase = "exit"
                toastQueue[i].timer = 0
                break  -- 只退最老的一个
            end
        end
    end

    -- 入场 tween
    Tween.to(toast, { slideX = 0, alpha = 1, scale = 1.0 }, TOAST_ENTER, {
        easing = Tween.Easing.easeOutBack,
        tag = "toast_" .. id,
        onComplete = function()
            if toast.phase == "enter" then
                toast.phase = "idle"
                toast.timer = 0
            end
        end
    })

    print(string.format("[EventPopup] Toast: %s - %s (id=%d)", cardType, displayTitle, id))
end

-- ---------------------------------------------------------------------------
-- Toast: 每帧更新
-- ---------------------------------------------------------------------------

function M.updateToasts(dt)
    -- 更新计时器 + 自动退场
    for i = #toastQueue, 1, -1 do
        local t = toastQueue[i]
        t.timer = t.timer + dt

        if t.phase == "idle" and t.timer >= TOAST_IDLE then
            -- 自动退场
            t.phase = "exit"
            t.timer = 0
            Tween.to(t, { slideX = TOAST_W + 30, alpha = 0, scale = 0.85 }, TOAST_EXIT, {
                easing = Tween.Easing.easeInCubic,
                tag = "toast_" .. t.id,
                onComplete = function()
                    t.phase = "done"
                end
            })
        end

        if t.phase == "exit" and t.timer > TOAST_EXIT + 0.1 then
            t.phase = "done"
        end
    end

    -- 移除已完成的
    for i = #toastQueue, 1, -1 do
        if toastQueue[i].phase == "done" then
            Tween.cancelTag("toast_" .. toastQueue[i].id)
            table.remove(toastQueue, i)
        end
    end

    -- 计算目标 Y (从上往下排列, 最新的在最下)
    -- 只对非 done 的 toast 计算
    local slot = 0
    for i = 1, #toastQueue do
        local t = toastQueue[i]
        if t.phase ~= "done" then
            t.targetY = TOAST_MARGIN_T + slot * (M._toastItemH(t) + TOAST_GAP)
            slot = slot + 1
        end
    end

    -- 平滑 Y
    for i = 1, #toastQueue do
        local t = toastQueue[i]
        if t.phase == "enter" and t.timer < 0.05 then
            t.currentY = t.targetY  -- 第一帧直接到位
        else
            t.currentY = t.currentY + (t.targetY - t.currentY) * math.min(1, dt * 12)
        end
    end
end

--- 计算单个 toast 的高度
function M._toastItemH(toast)
    local baseH = 42   -- 色条 + 图标/标题行
    baseH = baseH + 28  -- 描述行
    if toast.shieldUsed or #toast.effects > 0 then
        baseH = baseH + 24  -- 徽章行
    end
    baseH = baseH + 12  -- 进度条 + 底部间距
    return baseH
end

-- ---------------------------------------------------------------------------
-- Toast: 渲染
-- ---------------------------------------------------------------------------

function M.drawToasts(vg, logicalW, logicalH, gameTime)
    if #toastQueue == 0 then return end

    local tc_theme = Theme.current

    for i = 1, #toastQueue do
        local t = toastQueue[i]
        if t.phase == "done" then goto continue end
        if t.alpha < 0.01 then goto continue end

        local itemH = M._toastItemH(t)
        local x = logicalW - TOAST_W - TOAST_MARGIN_R + t.slideX
        local y = t.currentY

        -- 记录碰撞区域
        t.drawX = x
        t.drawY = y
        t.drawW = TOAST_W
        t.drawH = itemH

        nvgSave(vg)
        nvgGlobalAlpha(vg, t.alpha)

        -- 缩放 (以卡牌右中心为原点)
        if math.abs(t.scale - 1.0) > 0.005 then
            nvgTranslate(vg, x + TOAST_W, y + itemH / 2)
            nvgScale(vg, t.scale, t.scale)
            nvgTranslate(vg, -(x + TOAST_W), -(y + itemH / 2))
        end

        -- 阴影
        local shadowP = nvgBoxGradient(vg, x + 1, y + 2, TOAST_W, itemH, TOAST_R, 10,
            nvgRGBA(0, 0, 0, 50), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRect(vg, x - 12, y - 8, TOAST_W + 24, itemH + 20)
        nvgFillPaint(vg, shadowP)
        nvgFill(vg)

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, TOAST_W, itemH, TOAST_R)
        nvgFillColor(vg, nvgRGBA(tc_theme.panelBg.r, tc_theme.panelBg.g, tc_theme.panelBg.b, 240))
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, TOAST_W, itemH, TOAST_R)
        nvgStrokeColor(vg, Theme.rgbaA(tc_theme.panelBorder, 80))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 顶部类型色条
        local typeColor = Theme.cardTypeColor(t.cardType)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + 3, y + 3, TOAST_W - 6, 4, 2)
        nvgFillColor(vg, Theme.rgbaA(typeColor, 200))
        nvgFill(vg)

        -- 内容区域
        local contentX = x + 12
        local contentY = y + 14

        -- 图标 + 标题 (同行)
        local info = Theme.cardTypeInfo(t.cardType)
        -- 陷阱子类型: 使用专属图标
        local displayIcon = (info and info.icon or "❓")
        if t.cardType == "trap" and t.trapSubtype and EventPool.TRAP_SUBTYPE_INFO[t.trapSubtype] then
            displayIcon = EventPool.TRAP_SUBTYPE_INFO[t.trapSubtype].icon
        end
        nvgFontFace(vg, "sans")

        -- 图标
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(tc_theme.textPrimary))
        nvgText(vg, contentX, contentY + 8, displayIcon, nil)

        -- 标题
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(typeColor, 240))
        nvgText(vg, contentX + 28, contentY + 8, t.title, nil)

        contentY = contentY + 24

        -- 描述 (1-2 行, 截断)
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, Theme.rgbaA(tc_theme.textSecondary, 200))
        local maxTextW = TOAST_W - 24
        -- 截断到约 40 字符 (2行)
        local descText = t.desc
        if #descText > 60 then
            descText = descText:sub(1, 57) .. "..."
        end
        nvgTextBox(vg, contentX, contentY, maxTextW, descText, nil)
        contentY = contentY + 28

        -- 资源徽章 或 护盾提示
        if t.shieldUsed then
            -- 护盾提示
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, Theme.rgbaA(tc_theme.safe, 220))
            nvgText(vg, contentX, contentY + 8, "🧿 护身符抵挡了伤害!", nil)
            contentY = contentY + 20
        elseif #t.effects > 0 then
            local badgeX = contentX
            for _, eff in ipairs(t.effects) do
                local meta = resourceMeta[eff[1]]
                local icon = meta and meta.icon or "?"
                local delta = eff[2]
                local label = icon .. (delta > 0 and "+" or "") .. delta

                local bw = #label * 6 + 14
                local bh = 18

                -- 徽章背景
                local bgC = delta > 0 and tc_theme.safe or tc_theme.danger
                nvgBeginPath(vg)
                nvgRoundedRect(vg, badgeX, contentY, bw, bh, bh / 2)
                nvgFillColor(vg, Theme.rgbaA(bgC, 35))
                nvgFill(vg)
                nvgStrokeColor(vg, Theme.rgbaA(bgC, 80))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)

                -- 徽章文字
                nvgFontSize(vg, 10)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, Theme.rgbaA(delta > 0 and tc_theme.safe or tc_theme.danger, 220))
                nvgText(vg, badgeX + bw / 2, contentY + bh / 2, label, nil)

                badgeX = badgeX + bw + 6
            end
            contentY = contentY + 24
        end

        -- 进度条 (自动消失倒计时)
        if t.phase == "idle" then
            local progress = 1.0 - math.min(t.timer / TOAST_IDLE, 1.0)
            local barY = y + itemH - 6
            local barW = TOAST_W - 20
            local barH = 2

            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x + 10, barY, barW, barH, 1)
            nvgFillColor(vg, nvgRGBA(tc_theme.textSecondary.r, tc_theme.textSecondary.g, tc_theme.textSecondary.b, 30))
            nvgFill(vg)

            -- 前景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x + 10, barY, barW * progress, barH, 1)
            nvgFillColor(vg, Theme.rgbaA(typeColor, 120))
            nvgFill(vg)
        end

        nvgRestore(vg)

        ::continue::
    end
end

-- ---------------------------------------------------------------------------
-- Toast: 点击处理 (提前关闭)
-- ---------------------------------------------------------------------------

--- 点击 Toast 提前关闭
---@param lx number 逻辑 X
---@param ly number 逻辑 Y
---@return boolean consumed
function M.handleToastClick(lx, ly)
    -- 从最新 (队尾) 往最老遍历
    for i = #toastQueue, 1, -1 do
        local t = toastQueue[i]
        if t.phase ~= "done" and t.phase ~= "exit" then
            if lx >= t.drawX and lx <= t.drawX + t.drawW
                and ly >= t.drawY and ly <= t.drawY + t.drawH then
                -- 触发退场
                t.phase = "exit"
                t.timer = 0
                Tween.cancelTag("toast_" .. t.id)
                Tween.to(t, { slideX = TOAST_W + 30, alpha = 0, scale = 0.85 }, TOAST_EXIT, {
                    easing = Tween.Easing.easeInCubic,
                    tag = "toast_" .. t.id,
                    onComplete = function()
                        t.phase = "done"
                    end
                })
                return true
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Toast: 查询 / 清空
-- ---------------------------------------------------------------------------

function M.isToastActive()
    return #toastQueue > 0
end

function M.clearToasts()
    for i = 1, #toastQueue do
        Tween.cancelTag("toast_" .. toastQueue[i].id)
    end
    toastQueue = {}
end

-- ===========================================================================
-- 裂隙确认弹窗 (双按钮: 进入暗面 / 留在原地)
-- ===========================================================================

local riftState = {
    active = false,
    phase = "done",        -- "enter" | "idle" | "exit"
    cx = 0, cy = 0,
    onConfirm = nil,       -- 点击"进入"
    onCancel  = nil,       -- 点击"留下"
    -- 可配置文案 (nil 时使用默认裂隙文案)
    icon = nil,
    title = nil,
    desc1 = nil,
    desc2 = nil,
    btnConfirmLabel = nil,
    btnCancelLabel  = nil,
    accentColor = nil,     -- { r, g, b }
    -- 动画
    overlayAlpha = 0,
    popupScale   = 0,
    popupAlpha   = 0,
    iconT        = 0,
    titleT       = 0,
    descT        = 0,
    btnEnterT    = 0,
    btnStayT     = 0,
    btnEnterHover = 0,
    btnStayHover  = 0,
}

local RIFT_POPUP_W = 260
local RIFT_POPUP_H = 185
local RIFT_BTN_W   = 100
local RIFT_BTN_H   = 30
local RIFT_BTN_GAP = 12

--- 显示双选确认弹窗 (裂隙 / 转换事件等通用)
---@param cx number 弹窗中心 X
---@param cy number 弹窗中心 Y
---@param onConfirm function 确认回调
---@param onCancel function|nil 取消回调
---@param opts table|nil 可选文案 { icon, title, desc1, desc2, btnConfirm, btnCancel, accent }
function M.showRiftConfirm(cx, cy, onConfirm, onCancel, opts)
    riftState.active = true
    riftState.phase = "enter"
    riftState.cx = cx
    riftState.cy = cy
    riftState.onConfirm = onConfirm
    riftState.onCancel  = onCancel
    -- 可配置文案
    riftState.icon           = opts and opts.icon or nil
    riftState.title          = opts and opts.title or nil
    riftState.desc1          = opts and opts.desc1 or nil
    riftState.desc2          = opts and opts.desc2 or nil
    riftState.btnConfirmLabel = opts and opts.btnConfirm or nil
    riftState.btnCancelLabel  = opts and opts.btnCancel or nil
    riftState.accentColor    = opts and opts.accent or nil

    riftState.overlayAlpha = 0
    riftState.popupScale   = 0.3
    riftState.popupAlpha   = 0
    riftState.iconT        = 0
    riftState.titleT       = 0
    riftState.descT        = 0
    riftState.btnEnterT    = 0
    riftState.btnStayT     = 0
    riftState.btnEnterHover = 0
    riftState.btnStayHover  = 0

    Tween.to(riftState, { overlayAlpha = 0.4, popupScale = 1.0, popupAlpha = 1.0 }, 0.35, {
        easing = Tween.Easing.easeOutBack, tag = "riftpopup",
    })
    local base = 0.12
    Tween.to(riftState, { iconT = 1 }, 0.3, {
        delay = base, easing = Tween.Easing.easeOutBack, tag = "riftpopup",
    })
    Tween.to(riftState, { titleT = 1 }, 0.3, {
        delay = base + 0.08, easing = Tween.Easing.easeOutBack, tag = "riftpopup",
    })
    Tween.to(riftState, { descT = 1 }, 0.3, {
        delay = base + 0.16, easing = Tween.Easing.easeOutCubic, tag = "riftpopup",
    })
    Tween.to(riftState, { btnEnterT = 1 }, 0.3, {
        delay = base + 0.24, easing = Tween.Easing.easeOutBack, tag = "riftpopup",
    })
    Tween.to(riftState, { btnStayT = 1 }, 0.3, {
        delay = base + 0.30, easing = Tween.Easing.easeOutBack, tag = "riftpopup",
        onComplete = function() riftState.phase = "idle" end,
    })
end

local function dismissRift(accepted)
    if not riftState.active or riftState.phase == "exit" then return end
    riftState.phase = "exit"
    Tween.cancelTag("riftpopup")
    Tween.to(riftState, {
        overlayAlpha = 0, popupScale = 0.5, popupAlpha = 0,
        iconT = 0, titleT = 0, descT = 0, btnEnterT = 0, btnStayT = 0,
    }, 0.22, {
        easing = Tween.Easing.easeInBack, tag = "riftpopup",
        onComplete = function()
            riftState.active = false
            riftState.phase = "done"
            if accepted and riftState.onConfirm then
                riftState.onConfirm()
            elseif not accepted and riftState.onCancel then
                riftState.onCancel()
            end
        end,
    })
end

function M.isRiftConfirmActive()
    return riftState.active
end

--- 裂隙确认弹窗碰撞检测 (两个按钮)
---@return string|nil "enter"|"stay"|nil
local function riftBtnHitTest(lx, ly)
    local hw = RIFT_POPUP_W / 2
    local hh = RIFT_POPUP_H / 2
    local btnY = riftState.cy + hh - RIFT_BTN_H - 14
    local totalW = RIFT_BTN_W * 2 + RIFT_BTN_GAP
    local startX = riftState.cx - totalW / 2
    -- 进入按钮
    if lx >= startX and lx <= startX + RIFT_BTN_W
        and ly >= btnY and ly <= btnY + RIFT_BTN_H then
        return "enter"
    end
    -- 留下按钮
    local stayX = startX + RIFT_BTN_W + RIFT_BTN_GAP
    if lx >= stayX and lx <= stayX + RIFT_BTN_W
        and ly >= btnY and ly <= btnY + RIFT_BTN_H then
        return "stay"
    end
    return nil
end

function M.handleRiftClick(lx, ly)
    if not riftState.active then return false end
    if riftState.phase == "enter" then return true end
    local hit = riftBtnHitTest(lx, ly)
    if hit == "enter" then
        dismissRift(true)
        return true
    elseif hit == "stay" then
        dismissRift(false)
        return true
    end
    -- 面板外点击 = 留下
    local px = riftState.cx - RIFT_POPUP_W / 2
    local py = riftState.cy - RIFT_POPUP_H / 2
    if not (lx >= px and lx <= px + RIFT_POPUP_W and ly >= py and ly <= py + RIFT_POPUP_H) then
        dismissRift(false)
        return true
    end
    return true
end

function M.updateRiftHover(lx, ly, dt)
    if not riftState.active then return end
    local hit = riftBtnHitTest(lx, ly)
    local targetEnter = (hit == "enter") and 1 or 0
    local targetStay  = (hit == "stay")  and 1 or 0
    local speed = 8
    riftState.btnEnterHover = riftState.btnEnterHover + (targetEnter - riftState.btnEnterHover) * math.min(1, dt * speed)
    riftState.btnStayHover  = riftState.btnStayHover  + (targetStay  - riftState.btnStayHover)  * math.min(1, dt * speed)
end

function M.drawRiftConfirm(vg, logicalW, logicalH)
    if not riftState.active then return end

    local t = Theme.current

    -- 遮罩
    if riftState.overlayAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(riftState.overlayAlpha * 255)))
        nvgFill(vg)
    end

    nvgSave(vg)
    nvgTranslate(vg, riftState.cx, riftState.cy)
    nvgScale(vg, riftState.popupScale, riftState.popupScale)
    nvgGlobalAlpha(vg, riftState.popupAlpha)

    local hw = RIFT_POPUP_W / 2
    local hh = RIFT_POPUP_H / 2

    -- 阴影
    local shadowP = nvgBoxGradient(vg, -hw + 2, -hh + 4, RIFT_POPUP_W, RIFT_POPUP_H, POPUP_R, 16,
        nvgRGBA(0, 0, 0, 70), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, -hw - 20, -hh - 16, RIFT_POPUP_W + 40, RIFT_POPUP_H + 40)
    nvgFillPaint(vg, shadowP)
    nvgFill(vg)

    -- 面板
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, RIFT_POPUP_W, RIFT_POPUP_H, POPUP_R)
    nvgFillColor(vg, nvgRGBA(t.panelBg.r, t.panelBg.g, t.panelBg.b, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, RIFT_POPUP_W, RIFT_POPUP_H, POPUP_R)
    nvgStrokeColor(vg, Theme.rgbaA(t.darkAccent, 100))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- 主题色 (可配置或默认 darkAccent)
    local accent = riftState.accentColor or t.darkAccent

    -- 顶部色条
    nvgSave(vg)
    nvgScissor(vg, -hw, -hh, RIFT_POPUP_W, 4)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, RIFT_POPUP_W, RIFT_POPUP_H, POPUP_R)
    nvgFillColor(vg, Theme.rgba(accent))
    nvgFill(vg)
    nvgRestore(vg)

    -- 图标
    if riftState.iconT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, riftState.popupAlpha * riftState.iconT)
        nvgTranslate(vg, 0, -hh + 35 + (1 - riftState.iconT) * 15)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(accent))
        nvgText(vg, 0, 0, riftState.icon or "🌀", nil)
        nvgRestore(vg)
    end

    -- 标题
    if riftState.titleT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, riftState.popupAlpha * riftState.titleT)
        nvgTranslate(vg, 0, -hh + 65 + (1 - riftState.titleT) * 10)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(t.textPrimary))
        nvgText(vg, 0, 0, riftState.title or "发现空间裂隙", nil)
        nvgRestore(vg)
    end

    -- 描述
    if riftState.descT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, riftState.popupAlpha * riftState.descT)
        nvgTranslate(vg, 0, -hh + 92 + (1 - riftState.descT) * 8)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 180))
        nvgText(vg, 0, 0, riftState.desc1 or "此处出现通往暗面世界的裂隙", nil)
        nvgText(vg, 0, 16, riftState.desc2 or "是否要进入？", nil)
        nvgRestore(vg)
    end

    -- 双按钮
    local btnY = hh - RIFT_BTN_H - 14
    local totalW = RIFT_BTN_W * 2 + RIFT_BTN_GAP
    local startX = -totalW / 2

    -- "进入暗面" 按钮
    if riftState.btnEnterT > 0.01 then
        nvgSave(vg)
        local bx = startX + RIFT_BTN_W / 2
        local by = btnY + RIFT_BTN_H / 2
        local off = (1 - riftState.btnEnterT) * 15
        nvgTranslate(vg, bx, by + off)
        nvgScale(vg, riftState.btnEnterT, riftState.btnEnterT)
        local h = riftState.btnEnterHover
        local sc = 1.0 + h * 0.05
        nvgScale(vg, sc, sc)
        local da = accent
        local br = math.floor(da.r + (255 - da.r) * h * 0.15)
        local bg = math.floor(da.g + (255 - da.g) * h * 0.15)
        local bb = math.floor(da.b + (255 - da.b) * h * 0.15)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -RIFT_BTN_W / 2, -RIFT_BTN_H / 2, RIFT_BTN_W, RIFT_BTN_H, 6)
        nvgFillColor(vg, nvgRGBA(br, bg, bb, 220))
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, 0, 0, riftState.btnConfirmLabel or "进入暗面", nil)
        nvgRestore(vg)
    end

    -- "留在原地" 按钮
    if riftState.btnStayT > 0.01 then
        nvgSave(vg)
        local bx = startX + RIFT_BTN_W + RIFT_BTN_GAP + RIFT_BTN_W / 2
        local by = btnY + RIFT_BTN_H / 2
        local off = (1 - riftState.btnStayT) * 15
        nvgTranslate(vg, bx, by + off)
        nvgScale(vg, riftState.btnStayT, riftState.btnStayT)
        local h = riftState.btnStayHover
        local sc = 1.0 + h * 0.05
        nvgScale(vg, sc, sc)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -RIFT_BTN_W / 2, -RIFT_BTN_H / 2, RIFT_BTN_W, RIFT_BTN_H, 6)
        nvgFillColor(vg, Theme.rgbaA(t.textSecondary, 60))
        nvgFill(vg)
        nvgStrokeColor(vg, Theme.rgbaA(t.textSecondary, 120))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgbaA(t.textPrimary, 200))
        nvgText(vg, 0, 0, riftState.btnCancelLabel or "留在原地", nil)
        nvgRestore(vg)
    end

    nvgRestore(vg)
end

return M
