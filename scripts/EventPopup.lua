-- ============================================================================
-- EventPopup.lua - 事件弹窗系统
-- 翻牌后弹出动画弹窗，展示事件内容、资源变化预览、确认按钮
-- 入场: 缩放弹入(easeOutBack) + 内容逐行错时渐入
-- 退场: 缩放收回(easeInBack) + 淡出
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

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
    safe     = { { "san", 5 } },
    landmark = {},
    shop     = { { "money", -10 } },
    monster  = { { "san", -15 }, { "order", -5 } },
    trap     = { { "san", -10 }, { "order", -10 } },
    reward   = { { "money", 20 }, { "film", 1 } },
    plot     = { { "order", 10 } },
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

local state = {
    active = false,
    phase = "done",
    cardType = "safe",
    title = "",
    desc = "",
    effects = {},
    cx = 0, cy = 0,
    onDismiss = nil,

    -- 动画参数
    overlayAlpha = 0,
    popupScale = 0,
    popupAlpha = 0,

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
function M.show(cardType, cx, cy, onDismiss)
    -- 随机选取文案
    local pool = M.templates[cardType]
    if not pool or #pool == 0 then
        pool = { { title = "未知事件", desc = "你遇到了无法描述的事情。" } }
    end
    local tmpl = pool[math.random(1, #pool)]

    state.active = true
    state.phase = "enter"
    state.cardType = cardType
    state.title = tmpl.title
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

return M
