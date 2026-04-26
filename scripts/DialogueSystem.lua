-- ============================================================================
-- DialogueSystem.lua - Gal 风格对话系统
-- 笔记本美学 + 视觉小说风格的模态对话界面
-- 立绘在对话框背后，打字机效果，NanoVG 绘制
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 配置
-- ---------------------------------------------------------------------------
local TYPEWRITER_SPEED   = 18    -- 每秒显示字符数
local OVERLAY_ALPHA_MAX  = 100   -- 暗色遮罩最大 alpha (0~255)

-- 对话框
local BOX_H_RATIO        = 0.28  -- 对话框占屏幕高度比例
local BOX_MARGIN_X       = 20    -- 左右边距
local BOX_MARGIN_BOTTOM  = 16    -- 底部边距
local BOX_PAD_X           = 28   -- 文字左右内边距
local BOX_PAD_TOP         = 36   -- 文字上内边距 (给名牌留空间)
local BOX_PAD_BOTTOM      = 16   -- 文字下内边距
local BOX_RADIUS          = 12   -- 圆角
local BOX_LINE_SPACING    = 22   -- 横线间距 (笔记本风)

-- 名牌
local NAME_TAG_H          = 26
local NAME_TAG_PAD_X      = 14
local NAME_TAG_RADIUS     = 6
local NAME_TAG_OFFSET_Y   = -14  -- 名牌相对对话框顶部的偏移

-- 立绘
local PORTRAIT_H_RATIO    = 0.75  -- 立绘高度占屏幕比例
local PORTRAIT_MARGIN_LEFT = 0.05 -- 立绘左边缘占屏幕宽度比例

-- 继续提示
local ADVANCE_BLINK_SPEED = 2.5  -- "▼" 闪烁频率

-- 字体
local FONT_SIZE_TEXT       = 16
local FONT_SIZE_NAME       = 14
local LINE_H_MULT          = 1.5  -- 行高倍数

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------
---@type userdata NanoVG context
local vg_ = nil

-- 对话脚本
local script_ = nil           -- 当前对话脚本 (array of lines)
local scriptIndex_ = 0        -- 当前行索引
local onComplete_ = nil       -- 对话结束回调

-- 立绘
local portraitTexPath_ = nil  -- 立绘纹理路径
local portraitImage_ = -1     -- NanoVG 图片句柄

-- 状态机: "idle" → "entering" → "typing" → "waiting" → "exiting" → "idle"
local state_ = "idle"

-- 动画属性 (Tween 目标)
local anim_ = {
    overlayAlpha = 0,     -- 遮罩透明度 0~1
    boxOffsetY = 80,      -- 对话框从底部上滑 (正值=偏下)
    boxAlpha = 0,         -- 对话框透明度 0~1
    portraitAlpha = 0,    -- 立绘透明度 0~1
    portraitOffsetY = 40, -- 立绘从底部上浮
    portraitScale = 0.9,  -- 立绘缩放
}

-- 打字机
local typewriterPos_ = 0       -- 当前显示到第几个 UTF-8 字符
local typewriterTotal_ = 0     -- 当前行总字符数
local typewriterAccum_ = 0     -- 时间累计

-- 当前行数据
local currentSpeaker_ = ""
local currentText_ = ""

-- ---------------------------------------------------------------------------
-- UTF-8 工具
-- ---------------------------------------------------------------------------

--- 计算 UTF-8 字符串的字符数
local function utf8Len(s)
    local len = 0
    local i = 1
    local n = #s
    while i <= n do
        local b = s:byte(i)
        if b < 0x80 then i = i + 1
        elseif b < 0xE0 then i = i + 2
        elseif b < 0xF0 then i = i + 3
        else i = i + 4
        end
        len = len + 1
    end
    return len
end

--- 截取 UTF-8 字符串前 N 个字符
local function utf8Sub(s, charCount)
    local i = 1
    local count = 0
    local n = #s
    while i <= n and count < charCount do
        local b = s:byte(i)
        if b < 0x80 then i = i + 1
        elseif b < 0xE0 then i = i + 2
        elseif b < 0xF0 then i = i + 3
        else i = i + 4
        end
        count = count + 1
    end
    return s:sub(1, i - 1)
end

-- ---------------------------------------------------------------------------
-- 内部: 载入当前行
-- ---------------------------------------------------------------------------
local function loadLine(index)
    if not script_ or index < 1 or index > #script_ then return false end

    local line = script_[index]
    currentSpeaker_ = line.speaker or ""
    currentText_ = line.text or ""
    typewriterTotal_ = utf8Len(currentText_)
    typewriterPos_ = 0
    typewriterAccum_ = 0
    state_ = "typing"
    return true
end

-- ---------------------------------------------------------------------------
-- 内部: 推进对话
-- ---------------------------------------------------------------------------
local function advance()
    if state_ == "typing" then
        -- 打字中 → 跳过，直接显示全部
        typewriterPos_ = typewriterTotal_
        state_ = "waiting"
        return
    end

    if state_ == "waiting" then
        -- 等待中 → 下一句或结束
        scriptIndex_ = scriptIndex_ + 1
        if scriptIndex_ <= #script_ then
            loadLine(scriptIndex_)
        else
            -- 对话结束 → 退场动画
            state_ = "exiting"
            Tween.cancelTag("dialogue")

            Tween.to(anim_, {
                overlayAlpha = 0,
                boxOffsetY = 60,
                boxAlpha = 0,
                portraitAlpha = 0,
                portraitOffsetY = 20,
            }, 0.3, {
                easing = Tween.Easing.easeInCubic,
                tag = "dialogue",
                onComplete = function()
                    state_ = "idle"
                    script_ = nil
                    scriptIndex_ = 0
                    if portraitImage_ >= 0 and vg_ then
                        nvgDeleteImage(vg_, portraitImage_)
                        portraitImage_ = -1
                    end
                    if onComplete_ then
                        local cb = onComplete_
                        onComplete_ = nil
                        cb()
                    end
                end
            })
        end
    end
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化 (Start 中调用一次)
function M.init(vg)
    vg_ = vg
end

--- 开始对话
---@param dialogueScript table 对话脚本
---@param portraitTexPath string 立绘纹理路径
---@param onComplete function|nil 对话结束回调
function M.start(dialogueScript, portraitTexPath, onComplete)
    if state_ ~= "idle" then return end
    if not dialogueScript or #dialogueScript == 0 then
        if onComplete then onComplete() end
        return
    end

    script_ = dialogueScript
    scriptIndex_ = 1
    onComplete_ = onComplete
    portraitTexPath_ = portraitTexPath

    -- 加载立绘为 NanoVG 图片
    if vg_ and portraitTexPath then
        if portraitImage_ >= 0 then
            nvgDeleteImage(vg_, portraitImage_)
        end
        portraitImage_ = nvgCreateImage(vg_, portraitTexPath, 0)
        if portraitImage_ < 0 then
            print("[DialogueSystem] WARNING: Failed to load portrait: " .. portraitTexPath)
        end
    end

    -- 重置动画属性
    anim_.overlayAlpha = 0
    anim_.boxOffsetY = 80
    anim_.boxAlpha = 0
    anim_.portraitAlpha = 0
    anim_.portraitOffsetY = 40
    anim_.portraitScale = 0.9

    state_ = "entering"
    Tween.cancelTag("dialogue")

    -- 进场动画: 遮罩 + 立绘 + 对话框同时滑入
    Tween.to(anim_, {
        overlayAlpha = 1,
        boxOffsetY = 0,
        boxAlpha = 1,
        portraitAlpha = 1,
        portraitOffsetY = 0,
        portraitScale = 1.0,
    }, 0.4, {
        easing = Tween.Easing.easeOutCubic,
        tag = "dialogue",
        onComplete = function()
            loadLine(scriptIndex_)
        end
    })

    print("[DialogueSystem] Started dialogue with " .. #dialogueScript .. " lines")
end

--- 是否正在对话
function M.isActive()
    return state_ ~= "idle"
end

--- 点击处理 (推进对话)
function M.handleClick(lx, ly)
    if state_ == "idle" then return false end
    advance()
    return true
end

--- 按键处理
function M.handleKey(key)
    if state_ == "idle" then return false end
    if key == KEY_RETURN or key == KEY_SPACE then
        advance()
        return true
    end
    return false
end

--- 每帧更新 (打字机效果)
function M.update(dt)
    if state_ ~= "typing" then return end

    typewriterAccum_ = typewriterAccum_ + dt
    local charsToShow = math.floor(typewriterAccum_ * TYPEWRITER_SPEED)
    if charsToShow > typewriterPos_ then
        typewriterPos_ = math.min(charsToShow, typewriterTotal_)
    end

    if typewriterPos_ >= typewriterTotal_ then
        state_ = "waiting"
    end
end

--- 重置 (场景切换时)
function M.reset()
    Tween.cancelTag("dialogue")
    state_ = "idle"
    script_ = nil
    scriptIndex_ = 0
    onComplete_ = nil
    anim_.overlayAlpha = 0
    anim_.boxAlpha = 0
    anim_.portraitAlpha = 0
    if portraitImage_ >= 0 and vg_ then
        nvgDeleteImage(vg_, portraitImage_)
        portraitImage_ = -1
    end
end

-- ---------------------------------------------------------------------------
-- NanoVG 绘制
-- ---------------------------------------------------------------------------

function M.draw(vg, w, h, gameTime)
    if state_ == "idle" then return end
    if not vg then return end

    local tc = Theme.current
    if not tc then return end

    -- ===== 1. 暗色遮罩 =====
    local oAlpha = math.floor(OVERLAY_ALPHA_MAX * anim_.overlayAlpha)
    if oAlpha > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(10, 8, 18, oAlpha))
        nvgFill(vg)
    end

    -- ===== 2. 立绘 (在对话框背后) =====
    if portraitImage_ >= 0 and anim_.portraitAlpha > 0.01 then
        local pAlpha = anim_.portraitAlpha
        local pScale = anim_.portraitScale
        local pH = h * PORTRAIT_H_RATIO * pScale
        local pW = pH * (515 / 768)  -- 保持原始宽高比

        local pX = w * PORTRAIT_MARGIN_LEFT
        local pY = h - pH + anim_.portraitOffsetY  -- 底部对齐

        nvgSave(vg)
        nvgGlobalAlpha(vg, pAlpha)

        -- 立绘图片
        local imgPaint = nvgImagePattern(vg, pX, pY, pW, pH, 0, portraitImage_, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, pX, pY, pW, pH)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)

        nvgRestore(vg)
    end

    -- ===== 3. 对话框 =====
    if anim_.boxAlpha < 0.01 then return end

    local boxH = h * BOX_H_RATIO
    local boxX = BOX_MARGIN_X
    local boxW = w - BOX_MARGIN_X * 2
    local boxY = h - boxH - BOX_MARGIN_BOTTOM + anim_.boxOffsetY
    local bAlpha = anim_.boxAlpha

    nvgSave(vg)
    nvgGlobalAlpha(vg, bAlpha)

    -- 对话框阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, boxX + 2, boxY + 3, boxW, boxH, BOX_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
    nvgFill(vg)

    -- 对话框背景 (笔记本纸色)
    local paper = tc.notebookPaper or { r = 250, g = 246, b = 238 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, boxX, boxY, boxW, boxH, BOX_RADIUS)
    nvgFillColor(vg, nvgRGBA(paper.r, paper.g, paper.b, 240))
    nvgFill(vg)

    -- 边框
    local border = tc.notebookBorder or { r = 196, g = 184, b = 164 }
    nvgStrokeColor(vg, nvgRGBA(border.r, border.g, border.b, 160))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 笔记本横线装饰 (裁剪到对话框区域)
    nvgSave(vg)
    nvgScissor(vg, boxX, boxY, boxW, boxH)
    local lineColor = tc.notebookLine or { r = 197, g = 212, b = 232 }
    nvgStrokeColor(vg, nvgRGBA(lineColor.r, lineColor.g, lineColor.b, 60))
    nvgStrokeWidth(vg, 0.8)
    local lineY = boxY + BOX_PAD_TOP
    while lineY < boxY + boxH - BOX_PAD_BOTTOM do
        nvgBeginPath(vg)
        nvgMoveTo(vg, boxX + 12, lineY)
        nvgLineTo(vg, boxX + boxW - 12, lineY)
        nvgStroke(vg)
        lineY = lineY + BOX_LINE_SPACING
    end
    nvgRestore(vg)

    -- 左侧红色竖线 (笔记本风)
    nvgBeginPath(vg)
    nvgMoveTo(vg, boxX + 20, boxY + 8)
    nvgLineTo(vg, boxX + 20, boxY + boxH - 8)
    nvgStrokeColor(vg, nvgRGBA(220, 120, 120, 50))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- ===== 4. 名牌 =====
    if currentSpeaker_ and currentSpeaker_ ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, FONT_SIZE_NAME)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        -- 测量名字宽度
        local nameW = nvgTextBounds(vg, 0, 0, currentSpeaker_, nil) or 60
        local tagW = nameW + NAME_TAG_PAD_X * 2
        local tagX = boxX + 24
        local tagY = boxY + NAME_TAG_OFFSET_Y

        -- 名牌背景 (深色)
        local textPri = tc.textPrimary or { r = 35, g = 45, b = 60 }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tagX, tagY, tagW, NAME_TAG_H, NAME_TAG_RADIUS)
        nvgFillColor(vg, nvgRGBA(textPri.r, textPri.g, textPri.b, 220))
        nvgFill(vg)

        -- 名牌文字 (白色)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, tagX + NAME_TAG_PAD_X, tagY + NAME_TAG_H / 2, currentSpeaker_)
    end

    -- ===== 5. 对话文字 (打字机效果) =====
    if currentText_ and currentText_ ~= "" then
        local displayText = currentText_
        if state_ == "typing" and typewriterPos_ < typewriterTotal_ then
            displayText = utf8Sub(currentText_, typewriterPos_)
        end

        local textX = boxX + BOX_PAD_X
        local textY = boxY + BOX_PAD_TOP + 4
        local textMaxW = boxW - BOX_PAD_X * 2

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, FONT_SIZE_TEXT)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        -- 文字颜色 (深色墨水)
        local txtCol = tc.textPrimary or { r = 35, g = 45, b = 60 }
        nvgFillColor(vg, nvgRGBA(txtCol.r, txtCol.g, txtCol.b, 230))
        nvgTextLineHeight(vg, LINE_H_MULT)
        nvgTextBox(vg, textX, textY, textMaxW, displayText)
    end

    -- ===== 6. 继续提示 "▼" =====
    if state_ == "waiting" then
        local blinkAlpha = math.floor(128 + 127 * math.sin(gameTime * ADVANCE_BLINK_SPEED * 3.14159))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 100, 100, blinkAlpha))
        nvgText(vg, boxX + boxW / 2, boxY + boxH - 12, "▼")
    end

    nvgRestore(vg)
end

return M
