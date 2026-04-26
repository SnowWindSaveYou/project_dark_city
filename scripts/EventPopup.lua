-- ============================================================================
-- EventPopup.lua - 事件弹窗系统
-- 翻牌后弹出动画弹窗，展示事件内容、资源变化预览、确认按钮
-- 入场: 缩放弹入(easeOutBack) + 内容逐行错时渐入
-- 退场: 缩放收回(easeInBack) + 淡出
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"
local Card  = require "Card"

local M = {}

-- ---------------------------------------------------------------------------
-- 事件文案模板（每种卡牌类型多条，随机选取增加变化感）
-- ---------------------------------------------------------------------------

M.templates = {
    safe = {
        { title = "安全屋",   desc = "一间整洁的公寓，窗帘紧闭。你短暂休整，理智稍有恢复。" },
        { title = "便利店",   desc = "24小时亮着灯的便利店，店员面无表情。热咖啡让你安心不少。" },
        { title = "公园长椅", desc = "街边公园空无一人。你坐下来深呼吸，周围暂时没有异常。" },
    },
    landmark = {
        { title = "地标建筑", desc = "这座建筑是这片区域的标志。周围的街道以它为中心延伸。" },
        { title = "钟塔广场", desc = "古老的钟塔矗立在十字路口。指针停在了一个不存在的时刻。" },
    },
    shop = {
        { title = "黑市商人", desc = "\"需要什么？\" 戴兜帽的人低声问道。交易总是伴随代价。" },
        { title = "旧货铺",   desc = "货架上摆满了不知来源的物品。有些东西看起来不属于这个世界。" },
        { title = "自动售货机", desc = "孤零零的售货机发出嗡嗡声。投币口旁刻着你看不懂的符号。" },
    },
    monster = {
        { title = "阴影蠕动", desc = "墙壁上的影子扭曲变形，朝你涌来。你的理智在动摇……" },
        { title = "回声追踪", desc = "身后传来与你步伐完全同步的脚步声。你不敢回头。" },
        { title = "镜中来客", desc = "橱窗玻璃里映出的不是你的倒影。它在微笑。" },
    },
    trap = {
        { title = "地面塌陷", desc = "脚下的地面突然下沉！你勉强抓住边缘，但秩序感正在崩溃。" },
        { title = "迷雾弥漫", desc = "浓雾从巷子里涌出，方向感瞬间消失。你开始怀疑自己是否还在原地。" },
        { title = "时间错乱", desc = "手表指针疯狂旋转。你感觉刚刚过了一秒，但街上的人都不见了。" },
    },
    reward = {
        { title = "隐藏宝箱", desc = "墙缝里藏着一个锡盒，里面是现金和一卷未曝光的胶卷。" },
        { title = "神秘馈赠", desc = "邮箱里有一个写着你名字的包裹。里面的东西意外地有用。" },
        { title = "失物招领", desc = "桌上放着一叠钞票和记录着什么的胶片。似乎有人特意留给你。" },
    },
    plot = {
        { title = "字条",     desc = "折叠的纸条上写着：\"不要相信第三面墙。\" 秩序正在恢复。" },
        { title = "电话响了", desc = "废弃电话亭的话筒在震动。你接起来，听到了很久以前的声音。" },
        { title = "旧报纸",   desc = "报纸头版刊登着一则不可能的新闻——日期是明天。" },
    },
    clue = {
        { title = "涂鸦暗号", desc = "墙上的涂鸦里藏着符号。你举起相机，胶卷自动记录了一切。" },
        { title = "监控残影", desc = "碎裂的屏幕闪过一帧画面——那是一张你从未去过的地方的照片。" },
        { title = "录音磁带", desc = "老旧的录音机里残留着一段对话，说的是一个你似乎忘记的名字。" },
    },
    photo = {
        { title = "留影", desc = "相片上定格的画面取代了原本的恐惧。这里现在安全了。" },
        { title = "净化", desc = "曝光的胶片封印了阴影。被拍下的事物不再具有威胁。" },
    },
}

-- ---------------------------------------------------------------------------
-- 资源变化映射（与 main.lua 保持一致）
-- ---------------------------------------------------------------------------

M.cardEffects = {
    safe     = { { "san", 1 } },
    landmark = {},
    shop     = {},
    monster  = { { "san", -2 }, { "order", -1 } },
    trap     = { { "san", -1 }, { "order", -1 } },
    reward   = { { "money", 15 }, { "film", 1 } },
    plot     = { { "order", 1 } },
    clue     = { { "film", 1 } },
    photo    = {},  -- 相片：安全格，无资源效果
}

-- 资源中文名 / 图标
local resourceMeta = {
    san   = { icon = "🧠", label = "理智" },
    order = { icon = "⚖️",  label = "秩序" },
    film  = { icon = "🎞️",  label = "胶卷" },
    money = { icon = "💰", label = "钱币" },
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

local state = {
    active = false,
    phase = "done",
    cardType = "safe",
    title = "",
    desc = "",
    effects = {},
    cx = 0, cy = 0,
    onDismiss = nil,
    isPhoto = false,       -- 相片预览模式 (拍立得风格)
    photoLocation = nil,   -- 相片对应的地点

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
    local pool = M.templates[cardType]
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    -- 暗面世界标题：优先使用地点+事件类型对应的暗面名称
    local darkInfo = location and Card.getDarksideInfo(location, cardType) or nil
    local displayTitle = darkInfo and darkInfo.label or tmpl.title

    state.active = true
    state.phase = "enter"
    state.cardType = cardType
    state.title = displayTitle
    state.desc = tmpl.desc
    state.effects = M.cardEffects[cardType] or {}
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
    -- 随机选取文案
    local pool = M.templates[cardType]
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    -- 暗面世界标题
    local darkInfo = location and Card.getDarksideInfo(location, cardType) or nil
    local displayTitle = darkInfo and darkInfo.label or tmpl.title

    state.active = true
    state.phase = "enter"
    state.cardType = cardType
    state.title = displayTitle
    state.desc = tmpl.desc
    state.effects = {}  -- 相片预览不显示资源变化
    state.cx = cx
    state.cy = cy
    state.onDismiss = onDismiss
    state.isPhoto = true
    state.photoLocation = location

    -- 重置动画值
    state.overlayAlpha = 0
    state.popupScale = 0.2
    state.popupAlpha = 0
    state.photoRotation = math.random(-6, 6)  -- 随机微倾
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

    print(string.format("[EventPopup] ShowPhoto: %s - %s", cardType, displayTitle))
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
            local wasPhoto = state.isPhoto
            state.isPhoto = false
            state.photoLocation = nil
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
        return
    end
    local target = M.hitTestButton(lx, ly) and 1.0 or 0.0
    state.btnHoverT = state.btnHoverT + (target - state.btnHoverT) * math.min(1, dt * 12)
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
-- 渲染: 相片预览模式 (拍立得风格)
-- ---------------------------------------------------------------------------

-- 相片尺寸 (拍立得比例: 宽略窄, 底部留白多)
local PHOTO_W       = 200
local PHOTO_H       = 260
local PHOTO_BORDER  = 10      -- 上/左/右白边
local PHOTO_BOTTOM  = 40      -- 底部白边 (拍立得特征)
local PHOTO_R       = 3       -- 相片圆角 (很小, 偏硬朗)
local PHOTO_IMG_R   = 2       -- 内部照片区圆角

function M.drawPhoto(vg, logicalW, logicalH, gameTime)
    local t = Theme.current
    local tc = Theme.cardTypeColor(state.cardType)
    local info = Theme.cardTypeInfo(state.cardType)

    -- === 遮罩层 (比普通弹窗更暗) ===
    if state.overlayAlpha > 0.01 then
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(state.overlayAlpha * 255)))
        nvgFill(vg)
    end

    -- === 相片主体 ===
    nvgSave(vg)
    nvgTranslate(vg, state.cx, state.cy)
    nvgRotate(vg, state.photoRotation * math.pi / 180)  -- 微倾
    nvgScale(vg, state.popupScale, state.popupScale)
    nvgGlobalAlpha(vg, state.popupAlpha)

    local hw = PHOTO_W / 2
    local hh = PHOTO_H / 2

    -- 阴影 (更柔和, 偏暖)
    local shadowP = nvgBoxGradient(vg, -hw + 1, -hh + 3, PHOTO_W, PHOTO_H, PHOTO_R, 20,
        nvgRGBA(30, 20, 10, 90), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, -hw - 25, -hh - 20, PHOTO_W + 50, PHOTO_H + 45)
    nvgFillPaint(vg, shadowP)
    nvgFill(vg)

    -- 相片白底 (略带暖白, 模拟相纸)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, PHOTO_W, PHOTO_H, PHOTO_R)
    nvgFillColor(vg, nvgRGBA(252, 250, 245, 250))
    nvgFill(vg)

    -- 相片边框 (极细, 模拟纸张边缘)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, PHOTO_W, PHOTO_H, PHOTO_R)
    nvgStrokeColor(vg, nvgRGBA(210, 200, 185, 120))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- === 内部照片区 (深色背景, 模拟冲印画面) ===
    local imgX = -hw + PHOTO_BORDER
    local imgY = -hh + PHOTO_BORDER
    local imgW = PHOTO_W - PHOTO_BORDER * 2
    local imgH = PHOTO_H - PHOTO_BORDER - PHOTO_BOTTOM

    -- 照片底色 (暗蓝灰, 像夜间拍摄)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, imgX, imgY, imgW, imgH, PHOTO_IMG_R)
    nvgFillColor(vg, nvgRGBA(25, 30, 40, 240))
    nvgFill(vg)

    -- 照片内氛围渐变 (事件类型颜色从中心扩散)
    local atmosPaint = nvgRadialGradient(vg,
        imgX + imgW / 2, imgY + imgH * 0.4,
        10, imgW * 0.6,
        nvgRGBA(tc.r, tc.g, tc.b, 50),
        nvgRGBA(tc.r, tc.g, tc.b, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, imgX, imgY, imgW, imgH, PHOTO_IMG_R)
    nvgFillPaint(vg, atmosPaint)
    nvgFill(vg)

    -- === 照片内容 ===
    local imgCX = imgX + imgW / 2
    local imgCY = imgY + imgH / 2

    -- 事件图标 (大号, 居中)
    if state.iconT > 0.01 then
        nvgSave(vg)
        local iconScale = state.iconT
        nvgTranslate(vg, imgCX, imgCY - 18)
        nvgScale(vg, iconScale, iconScale)
        nvgGlobalAlpha(vg, state.popupAlpha * state.iconT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, 0, 0, info and info.icon or "❓", nil)
        nvgRestore(vg)
    end

    -- 事件标题 (图标下方, 白色)
    if state.titleT > 0.01 then
        nvgSave(vg)
        local titleOff = (1 - state.titleT) * 10
        nvgGlobalAlpha(vg, state.popupAlpha * state.titleT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(tc.r, tc.g, tc.b, 230))
        nvgText(vg, imgCX, imgCY + 14 + titleOff, state.title, nil)
        nvgRestore(vg)
    end

    -- 描述 (照片区下部, 浅色小字)
    if state.descT > 0.01 then
        nvgSave(vg)
        local descOff = (1 - state.descT) * 8
        nvgGlobalAlpha(vg, state.popupAlpha * state.descT)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 180))

        local textPad = 10
        local descY = imgCY + 36 + descOff
        nvgTextBox(vg, imgX + textPad, descY, imgW - textPad * 2, state.desc, nil)
        nvgRestore(vg)
    end

    -- 照片区四角暗角 (模拟镜头暗角)
    local vigPaint = nvgBoxGradient(vg, imgX, imgY, imgW, imgH, PHOTO_IMG_R, imgW * 0.35,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 80))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, imgX, imgY, imgW, imgH, PHOTO_IMG_R)
    nvgFillPaint(vg, vigPaint)
    nvgFill(vg)

    -- 胶片颗粒模拟 (随机小点)
    nvgSave(vg)
    nvgScissor(vg, imgX, imgY, imgW, imgH)
    for i = 1, 12 do
        local gx = imgX + math.sin(gameTime * 0.7 + i * 47.3) * imgW * 0.5 + imgW * 0.5
        local gy = imgY + math.cos(gameTime * 0.5 + i * 31.7) * imgH * 0.5 + imgH * 0.5
        local gr = 0.5 + math.sin(i * 17.1) * 0.3
        nvgBeginPath(vg)
        nvgCircle(vg, gx, gy, gr)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 15 + math.floor(math.sin(i * 7.3) * 10)))
        nvgFill(vg)
    end
    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 照片区内边框 (模拟冲印边缘)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, imgX, imgY, imgW, imgH, PHOTO_IMG_R)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 40))
    nvgStrokeWidth(vg, 0.6)
    nvgStroke(vg)

    -- === 底部白边区域 (拍立得签名区) ===
    local bottomY = imgY + imgH + 6

    -- 📷 图标 + 地点名 (手写感)
    if state.buttonT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, state.popupAlpha * state.buttonT)

        -- 地点图标和名称
        local locInfo = state.photoLocation and Card.LOCATION_INFO[state.photoLocation]
        local locLabel = locInfo and (locInfo.icon .. " " .. locInfo.label) or ""

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(80, 75, 65, 200))
        nvgText(vg, -hw + PHOTO_BORDER + 2, bottomY + 10, locLabel, nil)

        -- 右下角 "📷 侦察" 标记
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 140, 125, 160))
        nvgText(vg, hw - PHOTO_BORDER - 2, bottomY + 10, "📷 侦察", nil)

        nvgRestore(vg)
    end

    -- === 顶部小胶带装饰 (模拟贴在桌上的效果) ===
    nvgSave(vg)
    nvgGlobalAlpha(vg, state.popupAlpha * 0.6)
    local tapeW = 36
    local tapeH = 10
    local tapeX = -tapeW / 2
    local tapeY = -hh - tapeH / 2
    nvgBeginPath(vg)
    nvgRect(vg, tapeX, tapeY, tapeW, tapeH)
    nvgFillColor(vg, nvgRGBA(220, 210, 180, 160))
    nvgFill(vg)
    -- 胶带纹理线
    nvgBeginPath(vg)
    nvgMoveTo(vg, tapeX, tapeY + tapeH * 0.5)
    nvgLineTo(vg, tapeX + tapeW, tapeY + tapeH * 0.5)
    nvgStrokeColor(vg, nvgRGBA(200, 190, 165, 60))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)
    nvgRestore(vg)

    -- === 点击关闭提示 (底部) ===
    if state.buttonT > 0.01 then
        nvgSave(vg)
        nvgGlobalAlpha(vg, state.popupAlpha * state.buttonT * 0.5)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 170, 155, 180))
        nvgText(vg, 0, hh + 8, "点击任意处关闭", nil)
        nvgRestore(vg)
    end

    nvgRestore(vg)  -- 相片整体 transform
end

-- ===========================================================================
-- Toast 子系统 (非阻塞卡牌通知)
-- ===========================================================================

-- 哪些事件使用阻塞模态弹窗 (其余走 toast)
local BLOCKING_EVENTS = {
    shop = true,
    -- 未来: 带有选择的 plot 事件
}

--- 判断事件类型是否需要阻塞模态
---@param cardType string
---@param hasChoices boolean|nil  未来: 剧情选择
---@return boolean
function M.isBlockingEvent(cardType, hasChoices)
    if BLOCKING_EVENTS[cardType] then return true end
    if cardType == "plot" and hasChoices then return true end
    return false
end

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
function M.toast(cardType, appliedEffects, shieldUsed, location)
    -- 随机文案
    local pool = M.templates[cardType]
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    -- 暗面世界标题
    local darkInfo = location and Card.getDarksideInfo(location, cardType) or nil
    local displayTitle = darkInfo and darkInfo.label or tmpl.title

    local id = toastNextId
    toastNextId = toastNextId + 1

    ---@class ToastInstance
    local toast = {
        id = id,
        cardType = cardType,
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
        nvgFontFace(vg, "sans")

        -- 图标
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, Theme.rgba(tc_theme.textPrimary))
        nvgText(vg, contentX, contentY + 8, info and info.icon or "❓", nil)

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

return M
