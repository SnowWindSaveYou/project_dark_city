-- ============================================================================
-- CameraButton.lua - 相机模式悬浮按钮 + 取景器叠加层
-- 底部右侧悬浮按钮，点击进入/退出相机模式
-- 相机模式下：取景器暗角、角标线、扫描线、REC 指示器、胶卷计数
-- Tags: "camerabtn", "cameramode", "camerabtn_shake"
-- ============================================================================

local Tween       = require "lib.Tween"
local Theme       = require "Theme"
local ResourceBar = require "ResourceBar"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
local BTN_SIZE       = 44    -- 按钮直径
local BTN_MARGIN_R   = 20   -- 右边距
local BTN_MARGIN_B   = 90   -- 底边距 (避开 ResourceBar)
local BRACKET_LEN    = 28   -- 取景器角标线长度
local BRACKET_MARGIN = 20   -- 取景器角标边距
local SCANLINE_SPEED = 60   -- 扫描线速度 px/s

-- ---------------------------------------------------------------------------
-- 外部回调 (进入/退出相机模式时触发)
-- ---------------------------------------------------------------------------
local onEnterCallback = nil
local onExitCallback  = nil

--- 注入进入相机模式回调 (main.lua 用来翻开已侦察卡牌)
function M.setOnEnterCallback(fn)
    onEnterCallback = fn
end

--- 注入退出相机模式回调 (main.lua 用来翻回已侦察卡牌)
function M.setOnExitCallback(fn)
    onExitCallback = fn
end

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

local state = {
    visible = false,
    active  = false,       -- 是否在相机模式中

    -- 按钮位置 (逻辑坐标)
    btnCX = 0,
    btnCY = 0,

    -- 动画参数
    btnScale  = 0,         -- 按钮入场缩放 0→1
    btnAlpha  = 0,         -- 按钮透明度
    iconRot   = 0,         -- 图标旋转角度 (deg)

    -- 取景器叠加层
    overlayAlpha = 0,      -- 叠加层整体透明度
    scanlineY    = 0,      -- 扫描线 Y 位置
    recBlink     = 0,      -- REC 闪烁计时

    -- hover
    hoverT = 0,

    -- shake (胶卷不足反馈)
    shakeX    = 0,
    _shaking  = false,
    _shakeT   = 0,

    -- 内部计时
    _time = 0,

    -- 缓存的屏幕尺寸
    _logicalW = 0,
    _logicalH = 0,
}

-- ---------------------------------------------------------------------------
-- 布局
-- ---------------------------------------------------------------------------

function M.recalcLayout(logicalW, logicalH)
    state._logicalW = logicalW
    state._logicalH = logicalH
    state.btnCX = logicalW - BTN_MARGIN_R - BTN_SIZE / 2
    state.btnCY = logicalH - BTN_MARGIN_B - BTN_SIZE / 2
end

-- ---------------------------------------------------------------------------
-- 显示 / 隐藏
-- ---------------------------------------------------------------------------

function M.show()
    if state.visible then return end
    state.visible = true
    state.btnScale = 0.3
    state.btnAlpha = 0

    Tween.to(state, { btnScale = 1.0, btnAlpha = 1.0 }, 0.3, {
        easing = Tween.Easing.easeOutBack,
        tag = "camerabtn",
    })
end

function M.hide()
    if not state.visible then return end

    -- 如果在相机模式中，立即清理
    if state.active then
        state.active = false
        state.overlayAlpha = 0
        state.iconRot = 0
        Tween.cancelTag("cameramode")
    end

    Tween.cancelTag("camerabtn")

    Tween.to(state, { btnScale = 0.3, btnAlpha = 0 }, 0.2, {
        easing = Tween.Easing.easeInBack,
        tag = "camerabtn",
        onComplete = function()
            state.visible = false
        end
    })
end

-- ---------------------------------------------------------------------------
-- 进入 / 退出 相机模式
-- ---------------------------------------------------------------------------

function M.enterCameraMode()
    if state.active then return end
    state.active = true
    state.recBlink = 0
    state.scanlineY = 0

    Tween.cancelTag("cameramode")

    -- 按钮图标旋转
    Tween.to(state, { iconRot = 15 }, 0.25, {
        easing = Tween.Easing.easeOutBack,
        tag = "cameramode",
    })

    -- 取景器叠加层渐入
    Tween.to(state, { overlayAlpha = 1.0 }, 0.3, {
        easing = Tween.Easing.easeOutQuad,
        tag = "cameramode",
    })

    -- 通知外部 (翻开已侦察卡牌)
    if onEnterCallback then onEnterCallback() end

    print("[CameraButton] Enter camera mode")
end

function M.exitCameraMode(onComplete)
    if not state.active then
        if onComplete then onComplete() end
        return
    end
    state.active = false

    Tween.cancelTag("cameramode")

    -- 按钮恢复
    Tween.to(state, { iconRot = 0 }, 0.2, {
        easing = Tween.Easing.easeInQuad,
        tag = "cameramode",
    })

    -- 通知外部 (翻回已侦察卡牌)
    if onExitCallback then onExitCallback() end

    -- 取景器渐出
    Tween.to(state, { overlayAlpha = 0 }, 0.25, {
        easing = Tween.Easing.easeInQuad,
        tag = "cameramode",
        onComplete = function()
            if onComplete then onComplete() end
        end
    })

    print("[CameraButton] Exit camera mode")
end

-- ---------------------------------------------------------------------------
-- 查询
-- ---------------------------------------------------------------------------

function M.isActive()
    return state.active
end

function M.isVisible()
    return state.visible
end

-- ---------------------------------------------------------------------------
-- 胶卷不足反馈 — 按钮抖动
-- ---------------------------------------------------------------------------

function M.shakeNoFilm()
    if state._shaking then return end
    state._shaking = true
    state._shakeT = 0

    Tween.to(state, { _shakeT = 1 }, 0.4, {
        easing = Tween.Easing.linear,
        tag = "camerabtn_shake",
        onUpdate = function(_, t)
            local decay = (1 - t) ^ 2
            state.shakeX = math.sin(t * math.pi * 7) * 6 * decay
        end,
        onComplete = function()
            state.shakeX = 0
            state._shaking = false
        end
    })
end

-- ---------------------------------------------------------------------------
-- 碰撞检测
-- ---------------------------------------------------------------------------

function M.hitTestButton(lx, ly)
    if not state.visible then return false end
    local dx = lx - state.btnCX
    local dy = ly - state.btnCY
    local r = BTN_SIZE / 2 + 4  -- 稍微扩大点击区域
    return (dx * dx + dy * dy) <= r * r
end

-- ---------------------------------------------------------------------------
-- 点击处理 (由 main.lua 调用)
-- 返回: consumed (bool), reason (string|nil)
--   reason = "no_film" 表示胶卷不足无法进入
-- ---------------------------------------------------------------------------

function M.handleClick(lx, ly)
    if not state.visible then return false, nil end

    if M.hitTestButton(lx, ly) then
        if state.active then
            -- 退出相机模式
            M.exitCameraMode()
        else
            -- 允许无胶卷进入相机模式 (可查看已侦察卡牌)
            -- 实际拍摄时 handleCameraModeClick 会检查胶卷
            M.enterCameraMode()
        end
        return true, nil
    end

    return false, nil
end

-- ---------------------------------------------------------------------------
-- Hover 更新
-- ---------------------------------------------------------------------------

function M.updateHover(lx, ly, dt)
    if not state.visible then
        state.hoverT = 0
        return
    end

    local inside = M.hitTestButton(lx, ly)
    local target = inside and 1.0 or 0.0
    state.hoverT = state.hoverT + (target - state.hoverT) * math.min(1, dt * 12)
    if math.abs(state.hoverT - target) < 0.005 then
        state.hoverT = target
    end
end

-- ---------------------------------------------------------------------------
-- 每帧更新
-- ---------------------------------------------------------------------------

function M.update(dt)
    if not state.visible then return end

    state._time = state._time + dt

    -- 相机模式下的持续动画
    if state.active then
        -- 扫描线循环 (在 area 高度内)
        local areaH = state._logicalH - 14 - 80  -- areaBottom - areaTop
        state.scanlineY = state.scanlineY + SCANLINE_SPEED * dt
        if state.scanlineY > areaH then
            state.scanlineY = 0
        end

        -- REC 闪烁
        state.recBlink = state.recBlink + dt
    end
end

-- ---------------------------------------------------------------------------
-- 渲染: 取景器叠加层 (在 Token 之后、VFX 之前)
-- ---------------------------------------------------------------------------

function M.drawOverlay(vg, logicalW, logicalH, gameTime)
    if state.overlayAlpha <= 0.01 then return end

    local t = Theme.current
    local alpha = state.overlayAlpha
    local tintC = t.cameraTint

    -- 取景器区域：在顶部资源栏和底部边缘内侧
    local areaTop    = 80   -- ResourceBar 下方
    local areaBottom = logicalH - 14  -- 底部留小间距
    local areaH = areaBottom - areaTop

    nvgSave(vg)
    nvgGlobalAlpha(vg, alpha)

    -- === 四角暗角 (径向渐变，全屏范围) ===
    local vigR = math.max(logicalW, logicalH) * 0.8
    local vigPaint = nvgRadialGradient(vg,
        logicalW / 2, logicalH / 2,
        vigR * 0.5, vigR,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(tintC.r, tintC.g, tintC.b, 80))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    nvgFillPaint(vg, vigPaint)
    nvgFill(vg)

    -- === 四角 L 型角标 (相对于 area 边界) ===
    local bm = BRACKET_MARGIN - 6  -- 稍微紧凑一些
    local bl = BRACKET_LEN
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 180))
    nvgStrokeWidth(vg, 2.0)
    nvgLineCap(vg, NVG_SQUARE)

    local left   = bm
    local right  = logicalW - bm
    local top    = areaTop + bm
    local bottom = areaBottom - bm

    -- 左上
    nvgBeginPath(vg)
    nvgMoveTo(vg, left, top + bl)
    nvgLineTo(vg, left, top)
    nvgLineTo(vg, left + bl, top)
    nvgStroke(vg)

    -- 右上
    nvgBeginPath(vg)
    nvgMoveTo(vg, right - bl, top)
    nvgLineTo(vg, right, top)
    nvgLineTo(vg, right, top + bl)
    nvgStroke(vg)

    -- 左下
    nvgBeginPath(vg)
    nvgMoveTo(vg, left, bottom - bl)
    nvgLineTo(vg, left, bottom)
    nvgLineTo(vg, left + bl, bottom)
    nvgStroke(vg)

    -- 右下
    nvgBeginPath(vg)
    nvgMoveTo(vg, right - bl, bottom)
    nvgLineTo(vg, right, bottom)
    nvgLineTo(vg, right, bottom - bl)
    nvgStroke(vg)

    -- === 扫描线 (限定在 area 内循环) ===
    local scanAbsY = areaTop + state.scanlineY
    if scanAbsY > areaBottom then
        -- 重置在 update 中处理，这里做裁剪
        scanAbsY = areaBottom
    end

    if state.scanlineY > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, scanAbsY - 1, logicalW, 2)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 25))
        nvgFill(vg)

        -- 尾迹渐变
        local trailH = 30
        local trailTop = math.max(areaTop, scanAbsY - trailH)
        local trailPaint = nvgLinearGradient(vg,
            0, trailTop, 0, scanAbsY,
            nvgRGBA(255, 255, 255, 0),
            nvgRGBA(255, 255, 255, 12))
        nvgBeginPath(vg)
        nvgRect(vg, 0, trailTop, logicalW, scanAbsY - trailTop)
        nvgFillPaint(vg, trailPaint)
        nvgFill(vg)
    end

    -- === REC 指示器 (左上角标下方) ===
    local recX = left + 8
    local recY = top + bl + 12

    -- 闪烁红点
    local recVisible = math.sin(state.recBlink * 3.0) > -0.3
    if recVisible then
        nvgBeginPath(vg)
        nvgCircle(vg, recX, recY, 4)
        nvgFillColor(vg, nvgRGBA(220, 50, 50, 220))
        nvgFill(vg)

        -- 红点光晕
        nvgBeginPath(vg)
        nvgCircle(vg, recX, recY, 7)
        nvgFillColor(vg, nvgRGBA(220, 50, 50, 40))
        nvgFill(vg)
    end

    -- "CAMERA MODE" 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 160))
    nvgText(vg, recX + 10, recY, "CAMERA MODE", nil)

    nvgRestore(vg)
end

-- ---------------------------------------------------------------------------
-- 渲染: 悬浮按钮 (在 HUD 之后、Flash 之前)
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH, gameTime)
    if not state.visible or state.btnAlpha <= 0.01 then return end

    local t = Theme.current
    local cx = state.btnCX + state.shakeX
    local cy = state.btnCY
    local r = BTN_SIZE / 2

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, state.btnScale, state.btnScale)
    nvgGlobalAlpha(vg, state.btnAlpha)

    -- hover 放大
    local hoverScale = 1.0 + state.hoverT * 0.1
    nvgScale(vg, hoverScale, hoverScale)

    -- === 阴影 ===
    local shadowP = nvgRadialGradient(vg, 1, 2, r * 0.5, r * 1.4,
        nvgRGBA(0, 0, 0, 50),
        nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, 1, 2, r * 1.5)
    nvgFillPaint(vg, shadowP)
    nvgFill(vg)

    -- === 按钮背景 ===
    local btnColor
    if state.active then
        btnColor = t.cameraBtnActive
    else
        btnColor = t.cameraBtn
    end

    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r)
    nvgFillColor(vg, Theme.rgba(btnColor))
    nvgFill(vg)

    -- === 激活态脉冲光晕 ===
    if state.active then
        local glowPhase = 0.4 + 0.6 * math.abs(math.sin(state._time * 2.5))
        local glowR = r + 4 + glowPhase * 3
        local glowPaint = nvgRadialGradient(vg, 0, 0, r - 2, glowR,
            nvgRGBA(btnColor.r, btnColor.g, btnColor.b, math.floor(glowPhase * 60)),
            nvgRGBA(btnColor.r, btnColor.g, btnColor.b, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, glowR)
        nvgFillPaint(vg, glowPaint)
        nvgFill(vg)
    end

    -- === hover 高光 ===
    if state.hoverT > 0.01 then
        local hlPaint = nvgRadialGradient(vg, 0, -r * 0.3, r * 0.2, r * 0.8,
            nvgRGBA(255, 255, 255, math.floor(state.hoverT * 60)),
            nvgRGBA(255, 255, 255, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, r)
        nvgFillPaint(vg, hlPaint)
        nvgFill(vg)
    end

    -- === 边框 ===
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, r)
    local borderAlpha = state.active and 200 or 150
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(borderAlpha + state.hoverT * 55)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- === 图标 (📷) ===
    nvgSave(vg)
    nvgRotate(vg, state.iconRot * math.pi / 180)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, 0, 0, "📷", nil)
    nvgRestore(vg)

    -- === 胶卷计数 (按钮左侧，始终可见) ===
    local film = ResourceBar.get("film")
    local filmStr = "🎞️" .. film

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    if film <= 1 then
        nvgFillColor(vg, nvgRGBA(220, 80, 80, 220))
    else
        nvgFillColor(vg, nvgRGBA(t.textSecondary.r, t.textSecondary.g, t.textSecondary.b, 200))
    end
    nvgText(vg, -(r + 6), 0, filmStr, nil)

    nvgRestore(vg)
end

return M
