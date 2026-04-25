-- ============================================================================
-- Token.lua - 玩家棋子 (chibi 风格)
-- 纯 NanoVG 矢量绘制的可爱棋子，Balatro 风格移动动效
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
M.SIZE = 20          -- 基础尺寸半径
M.BODY_H = 14       -- 身体高度

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

function M.new()
    return {
        x = 0, y = 0,          -- 当前位置 (逻辑像素)
        targetRow = 1,
        targetCol = 1,
        scaleX = 1.0,
        scaleY = 1.0,
        alpha = 0,              -- 初始隐藏
        bounceY = 0,            -- 弹跳偏移
        squashX = 1.0,          -- 挤压 X
        squashY = 1.0,          -- 挤压 Y
        isMoving = false,
        visible = false,
        idleTimer = 0,          -- idle 呼吸动画
    }
end

-- ---------------------------------------------------------------------------
-- 动画: 出现
-- ---------------------------------------------------------------------------

function M.show(token, x, y)
    token.x = x
    token.y = y + 30   -- 从下方弹入
    token.visible = true
    Tween.to(token, { x = x, y = y, alpha = 1.0, scaleX = 1.0, scaleY = 1.0 }, 0.4, {
        easing = Tween.Easing.easeOutBack,
        tag = "token",
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 移动到目标位置
-- ---------------------------------------------------------------------------

function M.moveTo(token, targetX, targetY, onComplete)
    if token.isMoving then return end
    token.isMoving = true

    local dx = targetX - token.x
    local dy = targetY - token.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local duration = math.min(0.6, math.max(0.25, dist / 300))

    -- 起跳挤压
    Tween.to(token, { squashX = 1.2, squashY = 0.8 }, 0.08, {
        easing = Tween.Easing.easeOutQuad,
        tag = "tokenmove",
        onComplete = function()
            -- 弹起
            Tween.to(token, { squashX = 0.85, squashY = 1.15 }, 0.06, {
                easing = Tween.Easing.easeOutQuad,
                tag = "tokenmove",
            })
        end
    })

    -- 主移动 (含弧形: bounceY 先升后降)
    Tween.to(token, { x = targetX, y = targetY }, duration, {
        delay = 0.06,
        easing = Tween.Easing.easeInOutCubic,
        tag = "tokenmove",
    })

    -- 弧形跳跃 (Y 偏移)
    local jumpHeight = math.min(40, dist * 0.3 + 15)
    Tween.to(token, { bounceY = -jumpHeight }, duration * 0.45, {
        delay = 0.06,
        easing = Tween.Easing.easeOutQuad,
        tag = "tokenmove",
        onComplete = function()
            Tween.to(token, { bounceY = 0 }, duration * 0.55, {
                easing = Tween.Easing.easeOutBounce,
                tag = "tokenmove",
            })
        end
    })

    -- 落地 (延迟到主移动完成)
    Tween.to(token, { squashX = 1.0, squashY = 1.0 }, 0.01, {
        delay = duration + 0.06,
        tag = "tokenmove",
        onComplete = function()
            -- 落地挤压
            Tween.to(token, { squashX = 1.25, squashY = 0.75 }, 0.06, {
                easing = Tween.Easing.easeOutQuad,
                tag = "tokenmove",
                onComplete = function()
                    Tween.to(token, { squashX = 1.0, squashY = 1.0 }, 0.2, {
                        easing = Tween.Easing.easeOutElastic,
                        tag = "tokenmove",
                        onComplete = function()
                            token.isMoving = false
                            if onComplete then onComplete() end
                        end
                    })
                end
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 更新 (idle 动画计时)
-- ---------------------------------------------------------------------------

function M.update(token, dt)
    if not token.visible then return end
    token.idleTimer = token.idleTimer + dt
end

-- ---------------------------------------------------------------------------
-- 渲染: 可爱棋子
-- ---------------------------------------------------------------------------

function M.draw(vg, token, gameTime)
    if not token.visible or token.alpha <= 0.01 then return end

    local t = Theme.current
    local sz = M.SIZE

    -- idle 呼吸
    local breathe = 0
    if not token.isMoving then
        breathe = math.sin(gameTime * 2.5) * 2.0
    end

    nvgSave(vg)
    nvgTranslate(vg, token.x, token.y + token.bounceY + breathe)
    nvgScale(vg, token.scaleX * token.squashX, token.scaleY * token.squashY)
    nvgGlobalAlpha(vg, token.alpha)

    -- === 身体 (梯形/裙摆) ===
    local bodyW = sz * 0.7
    local bodyH = M.BODY_H
    local bodyTop = 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, -bodyW * 0.5, bodyTop)
    nvgLineTo(vg, -bodyW * 0.7, bodyTop + bodyH)
    nvgLineTo(vg, bodyW * 0.7, bodyTop + bodyH)
    nvgLineTo(vg, bodyW * 0.5, bodyTop)
    nvgClosePath(vg)

    -- 身体渐变 (校服深蓝)
    local bodyPaint = nvgLinearGradient(vg, 0, bodyTop, 0, bodyTop + bodyH,
        nvgRGBA(45, 60, 85, 255),
        nvgRGBA(35, 48, 70, 255))
    nvgFillPaint(vg, bodyPaint)
    nvgFill(vg)

    -- === 头部 (圆) ===
    local headR = sz * 0.52
    local headY = -headR + 4
    nvgBeginPath(vg)
    nvgCircle(vg, 0, headY, headR)

    -- 头部填充 (肤色)
    nvgFillColor(vg, nvgRGBA(255, 228, 205, 255))
    nvgFill(vg)

    -- === 头发 (半圆 + 刘海) ===
    local hairColor = t.accent
    nvgBeginPath(vg)
    nvgArc(vg, 0, headY, headR + 1, -math.pi, 0, NVG_CW)
    nvgClosePath(vg)
    nvgFillColor(vg, Theme.rgba(hairColor))
    nvgFill(vg)

    -- 刘海 (小三角)
    nvgBeginPath(vg)
    nvgMoveTo(vg, -headR * 0.6, headY - headR * 0.3)
    nvgLineTo(vg, -headR * 0.1, headY + headR * 0.1)
    nvgLineTo(vg, headR * 0.1, headY - headR * 0.4)
    nvgLineTo(vg, headR * 0.5, headY + headR * 0.05)
    nvgLineTo(vg, headR * 0.7, headY - headR * 0.35)
    nvgLineTo(vg, headR + 1, headY)
    nvgLineTo(vg, -headR - 1, headY)
    nvgClosePath(vg)
    nvgFillColor(vg, Theme.rgba(hairColor))
    nvgFill(vg)

    -- === 眼睛 ===
    local eyeY = headY + 1
    local eyeSpacing = headR * 0.35
    local eyeR = 2.5

    -- 左眼
    nvgBeginPath(vg)
    nvgCircle(vg, -eyeSpacing, eyeY, eyeR)
    nvgFillColor(vg, nvgRGBA(40, 50, 65, 255))
    nvgFill(vg)
    -- 左眼高光
    nvgBeginPath(vg)
    nvgCircle(vg, -eyeSpacing + 1, eyeY - 1, 1.0)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgFill(vg)

    -- 右眼
    nvgBeginPath(vg)
    nvgCircle(vg, eyeSpacing, eyeY, eyeR)
    nvgFillColor(vg, nvgRGBA(40, 50, 65, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, eyeSpacing + 1, eyeY - 1, 1.0)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgFill(vg)

    -- === 嘴巴 ===
    nvgBeginPath(vg)
    nvgArc(vg, 0, eyeY + 4, 2.5, 0.2, math.pi - 0.2, NVG_CW)
    nvgStrokeColor(vg, nvgRGBA(180, 100, 100, 180))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- === 腮红 ===
    local blushAlpha = 0.25 + 0.1 * math.sin(gameTime * 1.5)
    nvgBeginPath(vg)
    nvgEllipse(vg, -eyeSpacing - 2, eyeY + 4, 3.5, 2.5)
    nvgFillColor(vg, nvgRGBA(255, 150, 150, math.floor(blushAlpha * 255)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, eyeSpacing + 2, eyeY + 4, 3.5, 2.5)
    nvgFillColor(vg, nvgRGBA(255, 150, 150, math.floor(blushAlpha * 255)))
    nvgFill(vg)

    -- === 底部阴影 ===
    local shadowW = bodyW * 0.8
    local shadowH = 3
    local shadowY = bodyTop + bodyH + 2
    local shadowPaint = nvgRadialGradient(vg, 0, shadowY, 0, shadowW,
        nvgRGBA(0, 0, 0, 35),
        nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, shadowY, shadowW, shadowH)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    nvgRestore(vg)
end

return M
