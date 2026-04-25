-- ============================================================================
-- GameOver.lua - 游戏结算画面
-- 失败/胜利结算，统计展示 + 重新开始
-- ============================================================================

local Tween = require "lib.Tween"
local VFX   = require "lib.VFX"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

local state = {
    active   = false,
    phase    = "none",   -- "enter"|"idle"|"exit"
    isVictory = false,

    -- 统计
    stats = {
        daysSurvived   = 1,
        cardsRevealed  = 0,
        monstersSlain  = 0,
        photosUsed     = 0,
    },

    -- 动画值
    overlayAlpha  = 0,
    titleScale    = 0,
    titleAlpha    = 0,
    subtitleAlpha = 0,
    statsAlpha    = 0,
    buttonT       = 0,
    btnHoverT     = 0,

    -- 回调
    onRestart = nil,

    -- 粒子定时
    particleTimer = 0,
}

-- Tag
local TAG = "gameover"

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- 显示结算画面
---@param isVictory boolean 是否胜利
---@param stats table { daysSurvived, cardsRevealed, monstersSlain, photosUsed }
---@param onRestart function 重新开始回调
function M.show(isVictory, stats, onRestart)
    state.active    = true
    state.phase     = "enter"
    state.isVictory = isVictory
    state.stats     = stats or state.stats
    state.onRestart = onRestart

    -- 重置
    state.overlayAlpha  = 0
    state.titleScale    = 0
    state.titleAlpha    = 0
    state.subtitleAlpha = 0
    state.statsAlpha    = 0
    state.buttonT       = 0
    state.btnHoverT     = 0
    state.particleTimer = 0

    -- 入场动画序列
    -- 1. 遮罩淡入
    Tween.to(state, { overlayAlpha = 0.7 }, 0.6, {
        easing = Tween.Easing.easeOutQuad, tag = TAG,
    })

    -- 2. 标题弹入
    Tween.to(state, { titleScale = 1.0, titleAlpha = 1.0 }, 0.5, {
        delay = 0.3,
        easing = Tween.Easing.easeOutBack, tag = TAG,
        onComplete = function()
            state.phase = "idle"
        end
    })

    -- 3. 副标题
    Tween.to(state, { subtitleAlpha = 1.0 }, 0.4, {
        delay = 0.6,
        easing = Tween.Easing.easeOutQuad, tag = TAG,
    })

    -- 4. 统计数据
    Tween.to(state, { statsAlpha = 1.0 }, 0.4, {
        delay = 0.8,
        easing = Tween.Easing.easeOutQuad, tag = TAG,
    })

    -- 5. 按钮
    Tween.to(state, { buttonT = 1.0 }, 0.35, {
        delay = 1.1,
        easing = Tween.Easing.easeOutBack, tag = TAG,
    })
end

function M.dismiss()
    if not state.active then return end
    state.phase = "exit"

    Tween.cancelTag(TAG)

    Tween.to(state, {
        overlayAlpha = 0, titleAlpha = 0, subtitleAlpha = 0,
        statsAlpha = 0, buttonT = 0,
    }, 0.35, {
        easing = Tween.Easing.easeInQuad, tag = TAG,
        onComplete = function()
            state.active = false
            state.phase  = "none"
            if state.onRestart then state.onRestart() end
        end
    })
end

function M.isActive()
    return state.active
end

-- ---------------------------------------------------------------------------
-- 交互
-- ---------------------------------------------------------------------------

--- 按钮矩形 (居中)
local function getButtonRect(logicalW, logicalH)
    local bw, bh = 120, 38
    return logicalW / 2 - bw / 2, logicalH * 0.72, bw, bh
end

function M.handleClick(lx, ly, logicalW, logicalH)
    if not state.active then return false end
    if state.phase == "exit" then return true end

    -- 按钮检测
    if state.buttonT > 0.5 then
        local bx, by, bw, bh = getButtonRect(logicalW, logicalH)
        if lx >= bx and lx <= bx + bw and ly >= by and ly <= by + bh then
            M.dismiss()
            return true
        end
    end

    return true  -- 吞掉一切点击
end

function M.handleKey(key)
    if not state.active then return false end
    if state.phase ~= "idle" then return true end

    if key == KEY_RETURN or key == KEY_SPACE then
        M.dismiss()
        return true
    end
    return true
end

function M.updateHover(lx, ly, dt, logicalW, logicalH)
    if not state.active or state.buttonT < 0.5 then return end
    local bx, by, bw, bh = getButtonRect(logicalW, logicalH)
    local over = (lx >= bx and lx <= bx + bw and ly >= by and ly <= by + bh) and 1.0 or 0.0
    state.btnHoverT = state.btnHoverT + (over - state.btnHoverT) * math.min(1, dt * 12)
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.active then return end

    local t = Theme.current

    -- === 遮罩 ===
    if state.overlayAlpha > 0.01 then
        local overlayR, overlayG, overlayB
        if state.isVictory then
            overlayR, overlayG, overlayB = 15, 25, 45
        else
            overlayR, overlayG, overlayB = 40, 10, 10
        end
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, logicalW + 100, logicalH + 100)
        nvgFillColor(vg, nvgRGBA(overlayR, overlayG, overlayB,
            math.floor(state.overlayAlpha * 255)))
        nvgFill(vg)
    end

    local cx = logicalW / 2

    -- === 标题 ===
    if state.titleAlpha > 0.01 then
        local titleText = state.isVictory and "任务完成" or "意识崩溃"
        local titleColor = state.isVictory and t.safe or t.danger

        nvgSave(vg)
        nvgTranslate(vg, cx, logicalH * 0.28)
        nvgScale(vg, state.titleScale, state.titleScale)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        VFX.drawLayeredText(0, 0, titleText,
            titleColor.r, titleColor.g, titleColor.b, state.titleAlpha)

        nvgRestore(vg)

        -- 光晕
        if state.titleAlpha > 0.3 then
            local glowR = 80 + 10 * math.sin(gameTime * 2)
            local glow = nvgRadialGradient(vg, cx, logicalH * 0.28, 0, glowR,
                nvgRGBA(titleColor.r, titleColor.g, titleColor.b,
                    math.floor(state.titleAlpha * 40)),
                nvgRGBA(titleColor.r, titleColor.g, titleColor.b, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, logicalH * 0.28, glowR)
            nvgFillPaint(vg, glow)
            nvgFill(vg)
        end
    end

    -- === 副标题 ===
    if state.subtitleAlpha > 0.01 then
        local subText = state.isVictory
            and "你在暗面都市中幸存了下来。"
            or  "黑暗吞噬了你最后的理智..."

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(t.textSecondary.r, t.textSecondary.g, t.textSecondary.b,
            math.floor(state.subtitleAlpha * 200)))
        nvgText(vg, cx, logicalH * 0.36, subText, nil)
    end

    -- === 统计 ===
    if state.statsAlpha > 0.01 then
        local stats = state.stats
        local lines = {
            { icon = "📅", label = "存活天数", value = tostring(stats.daysSurvived) },
            { icon = "🃏", label = "翻开卡牌", value = tostring(stats.cardsRevealed) },
            { icon = "👻", label = "驱除怪物", value = tostring(stats.monstersSlain) },
            { icon = "📷", label = "消耗胶卷", value = tostring(stats.photosUsed) },
        }

        local lineH  = 24
        local startY = logicalH * 0.44
        local alpha  = math.floor(state.statsAlpha * 255)

        for i, line in ipairs(lines) do
            local ly = startY + (i - 1) * lineH

            -- 图标
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(t.textSecondary.r, t.textSecondary.g, t.textSecondary.b, alpha))
            nvgText(vg, cx - 10, ly, line.icon .. " " .. line.label, nil)

            -- 数值
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(t.textPrimary.r, t.textPrimary.g, t.textPrimary.b, alpha))
            nvgText(vg, cx + 10, ly, line.value, nil)
        end
    end

    -- === 重新开始按钮 ===
    if state.buttonT > 0.01 then
        local bx, by, bw, bh = getButtonRect(logicalW, logicalH)
        local btnScale = state.buttonT
        local hoverT = state.btnHoverT

        nvgSave(vg)
        nvgTranslate(vg, bx + bw / 2, by + bh / 2)
        nvgScale(vg, btnScale, btnScale)

        -- 按钮背景
        local btnColor = state.isVictory and t.safe or t.accent
        local lift = hoverT * 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -bw / 2, -bh / 2 - lift, bw, bh, 8)
        nvgFillColor(vg, nvgRGBA(
            math.floor(btnColor.r + (255 - btnColor.r) * hoverT * 0.15),
            math.floor(btnColor.g + (255 - btnColor.g) * hoverT * 0.15),
            math.floor(btnColor.b + (255 - btnColor.b) * hoverT * 0.15),
            math.floor(state.buttonT * 240)))
        nvgFill(vg)

        -- 按钮文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(state.buttonT * 255)))
        nvgText(vg, 0, -lift, "重新开始", nil)

        nvgRestore(vg)
    end

    -- === 胜利粒子 ===
    if state.isVictory and state.phase == "idle" then
        state.particleTimer = state.particleTimer + 0.016
        if state.particleTimer > 0.4 then
            state.particleTimer = 0
            local px = math.random() * logicalW
            VFX.spawnBurst(px, -10, 3, t.highlight.r, t.highlight.g, t.highlight.b, {
                speed = 15, speedVar = 10, life = 1.5, lifeVar = 0.5,
                gravity = 30, upward = -40, size = 2, sizeVar = 2,
            })
        end
    end
end

return M
