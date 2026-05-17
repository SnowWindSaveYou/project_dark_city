-- ============================================================================
-- SideBubble.lua - 右侧堆叠教程气泡（便签条风格）
-- 对应 Godot 版 side_bubble.gd
-- 气泡从右侧滑入，向下堆叠，自动消失
-- ============================================================================

local Tween = require "lib.Tween"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
M.IDLE_TIME      = 3.0    -- 普通气泡默认显示时长（秒）
M.IDLE_TIME_LONG = 4.5    -- 长气泡（重要提示）显示时长

local ITEM_W      = 200    -- 气泡宽度
local ITEM_H      = 78     -- 气泡高度（头像区41px + 单行文字约37px）
local ITEM_H_TALL = 100    -- 长文本气泡高度（多行）
local ITEM_GAP    = 8      -- 堆叠间距
local CORNER_R    = 8      -- 圆角半径
local SIDE_PAD    = 10     -- 右边距（距屏幕右侧）
local TOP_PAD     = 60     -- 顶边距（ResourceBar 下方）

local ENTER_DURATION = 0.35  -- 滑入时长
local EXIT_DURATION  = 0.25  -- 滑出时长
-- 序列气泡间隔由文本长度动态计算，此为最短间隔
local STAGGER_MIN    = 0.4   -- 最短间隔（秒）
local STAGGER_PER_CH = 0.04  -- 每个字符额外增加的等待时间（秒）

-- 颜色
local BG_COLOR   = { 248, 244, 230 }  -- 米黄纸色
local BG_ALPHA   = 235
local BORDER_COL = { 180, 165, 140 }  -- 纸边颜色
local TAPE_COL   = { 210, 200, 180 }  -- 胶带颜色
local TEXT_COL   = {  60,  48,  36 }  -- 正文颜色
local SPKR_COL   = { 120,  80,  40 }  -- 说话人颜色

-- 说话人名字→颜色映射（暖色系）
local SPEAKER_COLORS = {
    ["白夜"] = { 180, 140, 200 },  -- 紫色调
    ["苏柚"] = { 200, 120,  80 },  -- 橙色调
    ["琴馨"] = { 100, 160, 200 },  -- 蓝色调
    ["系统"] = { 140, 180, 140 },  -- 绿色调
}

-- 说话人头像路径
local SPEAKER_AVATAR_PATHS = {
    ["白夜"] = "image/白夜_chibi_20260506003802.png",
    ["苏柚"] = "image/zhujiao_avater.png",
}

local AVATAR_SIZE = 28   -- 头像圆形直径（px）

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local items_ = {}          -- 当前所有气泡列表
local logicalW_ = 800      -- 每帧从 draw 更新
local logicalH_ = 600

local fontReady_   = false   -- 字体是否已创建
local vg_          = nil     -- NanoVG context（init 注入）
local avatarImages_ = {}     -- speaker → nvg image handle

-- ---------------------------------------------------------------------------
-- 内部工具
-- ---------------------------------------------------------------------------

--- 计算目标 Y（从上往下堆叠）
local function getTargetY(index)
    local y = TOP_PAD
    for i = 1, index - 1 do
        local item = items_[i]
        if item and item.phase ~= "done" then
            y = y + item.height + ITEM_GAP
        end
    end
    return y
end

--- 重新排列所有气泡的 Y 坐标（某个气泡消失后上移）
local function rearrangeItems()
    local y = TOP_PAD
    for _, item in ipairs(items_) do
        if item.phase ~= "done" then
            local targetY = y
            if math.abs(item.currentY - targetY) > 1 then
                Tween.to(item, { currentY = targetY }, 0.22, {
                    easing = Tween.Easing.easeOutQuad,
                    tag = "sidebubble_arrange",
                })
            end
            y = y + item.height + ITEM_GAP
        end
    end
end

--- 开始某个气泡的退出动画
local function startItemExit(item)
    if item.phase == "exiting" or item.phase == "done" then return end
    item.phase = "exiting"
    -- 滑出到右侧屏幕外
    Tween.to(item, { offsetX = ITEM_W + SIDE_PAD + 20 }, EXIT_DURATION, {
        easing = Tween.Easing.easeInQuad,
        tag = "sidebubble_exit",
        onComplete = function()
            item.phase = "done"
            -- 移除已完成项
            for i = #items_, 1, -1 do
                if items_[i].phase == "done" then
                    table.remove(items_, i)
                end
            end
            rearrangeItems()
        end,
    })
end

--- 计算气泡高度（根据文本长度自适应）
local function calcItemHeight(text)
    -- 简单估算：超过 18 个字符就用高版本
    if #text > 18 then
        return ITEM_H_TALL
    end
    return ITEM_H
end

--- 创建一个新气泡 item
local function createItem(text, speaker, duration)
    speaker  = speaker  or "白夜"
    duration = duration or M.IDLE_TIME

    local rightEdge = logicalW_ - SIDE_PAD
    local startX = rightEdge  -- 从右边缘外开始（offsetX = 0 表示完全入场）
    local itemH = calcItemHeight(text)

    -- 计算本次入场的目标 Y
    local targetY = TOP_PAD
    for _, existing in ipairs(items_) do
        if existing.phase ~= "done" then
            targetY = targetY + existing.height + ITEM_GAP
        end
    end

    local item = {
        text       = text,
        speaker    = speaker,
        duration   = duration,
        phase      = "entering",  -- entering | visible | exiting | done
        idle_timer = 0.0,
        height     = itemH,
        currentY   = targetY,
        -- offsetX: 0=完全显示, >0=向右移出（从 ITEM_W+SIDE_PAD 滑入到 0）
        offsetX    = ITEM_W + SIDE_PAD + 20,
    }

    table.insert(items_, item)

    -- 滑入动画
    Tween.to(item, { offsetX = 0 }, ENTER_DURATION, {
        easing = Tween.Easing.easeOutBack,
        tag = "sidebubble_enter",
        onComplete = function()
            item.phase = "visible"
        end,
    })

    return item
end

-- ---------------------------------------------------------------------------
-- 公开 API
-- ---------------------------------------------------------------------------

--- 初始化：在 Start() 中调用一次，需传入 NanoVG context
---@param vg userdata NanoVG context
function M.init(vg)
    vg_         = vg
    items_      = {}
    fontReady_  = false
    avatarImages_ = {}
    -- 预加载所有说话人头像
    for speaker, path in pairs(SPEAKER_AVATAR_PATHS) do
        local handle = nvgCreateImage(vg_, path, 0)
        if handle and handle > 0 then
            avatarImages_[speaker] = handle
            print(string.format("[SideBubble] Loaded avatar: %s → handle %d", speaker, handle))
        else
            print(string.format("[SideBubble] WARNING: Failed to load avatar: %s (%s)", speaker, path))
        end
    end
end

--- 显示单条教程气泡
---@param text string 内容
---@param speaker string|nil 说话人（默认"白夜"）
---@param duration number|nil 显示时长（默认 M.IDLE_TIME）
function M.show(text, speaker, duration)
    createItem(text, speaker, duration)
end

--- 计算一句话的阅读时间（作为下一句出现前的等待时长）
---@param text string
---@return number 秒
local function calcReadDelay(text)
    -- 按字符数估算：每字 0.12s，下限 1.2s
    return math.max(STAGGER_MIN, #text * STAGGER_PER_CH)
end

--- 显示序列气泡（Godot 的 show_sequence）
--- 每条气泡在上一条"读完"后才出现，营造自然对话节奏
---@param lines table  每条 { speaker=, text= }
---@param duration_last number|nil 最后一条的额外时长（默认 M.IDLE_TIME_LONG）
function M.showSequence(lines, duration_last)
    duration_last = duration_last or M.IDLE_TIME_LONG
    local cumulativeDelay = 0
    for i, line in ipairs(lines) do
        local dur = (i == #lines) and duration_last or M.IDLE_TIME
        local delayTime = cumulativeDelay
        if delayTime <= 0 then
            createItem(line.text, line.speaker, dur)
        else
            local dummy = { t = 0 }
            Tween.to(dummy, { t = 1 }, delayTime, {
                tag = "sidebubble_stagger",
                onComplete = function()
                    createItem(line.text, line.speaker, dur)
                end,
            })
        end
        -- 下一条等待当前这条被阅读完的时间
        cumulativeDelay = cumulativeDelay + calcReadDelay(line.text)
    end
end

--- 清除所有气泡
function M.clear()
    for _, item in ipairs(items_) do
        item.phase = "done"
    end
    items_ = {}
end

-- ---------------------------------------------------------------------------
-- 更新
-- ---------------------------------------------------------------------------

function M.update(dt)
    for _, item in ipairs(items_) do
        if item.phase == "visible" then
            item.idle_timer = item.idle_timer + dt
            if item.idle_timer >= item.duration then
                startItemExit(item)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

function M.draw(vg, logicalW, logicalH)
    if #items_ == 0 then return end

    logicalW_ = logicalW
    logicalH_ = logicalH

    -- 确保字体已创建
    if not fontReady_ then
        fontReady_ = true
        -- 字体已由 main.lua 创建，此处仅标记
    end

    local rightEdge = logicalW - SIDE_PAD

    nvgSave(vg)

    for _, item in ipairs(items_) do
        if item.phase == "done" then goto continue end

        -- 气泡左上角坐标
        local bx = rightEdge - ITEM_W + item.offsetX
        local by = item.currentY

        -- 整体透明度（滑出时渐变消失）
        local alpha = 1.0
        if item.phase == "exiting" then
            -- offsetX 从 0→ITEM_W+...，线性映射到 alpha 1→0
            local maxOffset = ITEM_W + SIDE_PAD + 20
            alpha = 1.0 - math.min(1.0, item.offsetX / maxOffset)
        end

        nvgSave(vg)
        nvgGlobalAlpha(vg, alpha)

        -- ---- 投影 ----
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + 2, by + 3, ITEM_W, item.height, CORNER_R)
        nvgFillColor(vg, nvgRGBA(60, 45, 30, 28))
        nvgFill(vg)

        -- ---- 气泡主体 ----
        local bc = BG_COLOR
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, ITEM_W, item.height, CORNER_R)
        nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], BG_ALPHA))
        nvgFill(vg)

        -- ---- 边框 ----
        local bdc = BORDER_COL
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, ITEM_W, item.height, CORNER_R)
        nvgStrokeColor(vg, nvgRGBA(bdc[1], bdc[2], bdc[3], 100))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- ---- 顶部胶带装饰 ----
        local tapeW = 32
        local tape  = TAPE_COL
        nvgBeginPath(vg)
        nvgRect(vg, bx + ITEM_W / 2 - tapeW / 2, by - 4, tapeW, 8)
        nvgFillColor(vg, nvgRGBA(tape[1], tape[2], tape[3], 90))
        nvgFill(vg)

        -- ---- 左侧书脊竖条 ----
        nvgBeginPath(vg)
        nvgRoundedRectVarying(vg, bx, by, 5, item.height, CORNER_R, 0, 0, CORNER_R)
        -- 使用说话人颜色
        local spkrColorArr = SPEAKER_COLORS[item.speaker] or SPKR_COL
        nvgFillColor(vg, nvgRGBA(spkrColorArr[1], spkrColorArr[2], spkrColorArr[3], 180))
        nvgFill(vg)

        -- ---- 头像 + 说话人姓名 ----
        local padL = 12
        local padT = 8
        local avatarR = AVATAR_SIZE / 2   -- 头像半径
        local avatarCX = bx + padL + avatarR
        local avatarCY = by + padT + avatarR

        -- 头像圆形（有图用图，无图用颜色圆饼）
        local avatarImg = avatarImages_[item.speaker]
        if avatarImg and avatarImg > 0 then
            -- 圆形裁剪：先画圆路径，再用 imagePattern 填充
            local imgX = avatarCX - avatarR
            local imgY = avatarCY - avatarR
            local paint = nvgImagePattern(vg, imgX, imgY, AVATAR_SIZE, AVATAR_SIZE, 0, avatarImg, 1.0)
            nvgBeginPath(vg)
            nvgCircle(vg, avatarCX, avatarCY, avatarR)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        else
            -- 无图：纯色圆饼作为占位
            nvgBeginPath(vg)
            nvgCircle(vg, avatarCX, avatarCY, avatarR)
            nvgFillColor(vg, nvgRGBA(spkrColorArr[1], spkrColorArr[2], spkrColorArr[3], 160))
            nvgFill(vg)
        end

        -- 头像外圈描边
        nvgBeginPath(vg)
        nvgCircle(vg, avatarCX, avatarCY, avatarR)
        nvgStrokeColor(vg, nvgRGBA(spkrColorArr[1], spkrColorArr[2], spkrColorArr[3], 140))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)

        -- 说话人姓名（头像右侧，垂直居中）
        local nameX = avatarCX + avatarR + 6
        local nameY = avatarCY
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(spkrColorArr[1], spkrColorArr[2], spkrColorArr[3], 220))
        nvgText(vg, nameX, nameY, item.speaker, nil)

        -- ---- 分隔线 ----
        local divY = by + padT + AVATAR_SIZE + 5
        nvgBeginPath(vg)
        nvgMoveTo(vg, bx + padL, divY)
        nvgLineTo(vg, bx + ITEM_W - 10, divY)
        nvgStrokeColor(vg, nvgRGBA(bdc[1], bdc[2], bdc[3], 50))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        -- ---- 正文 ----
        local tc = TEXT_COL
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 220))

        local textX = bx + padL
        local textY = divY + 5
        local maxW  = ITEM_W - padL - 10

        -- 用 nvgTextBox 自动换行
        nvgTextBox(vg, textX, textY, maxW, item.text, nil)

        nvgRestore(vg)

        ::continue::
    end

    nvgRestore(vg)
end

-- 惰性加载 Theme（避免循环依赖）
local Theme = nil
local function getTheme()
    if not Theme then
        local ok, t = pcall(require, "Theme")
        if ok then Theme = t end
    end
    return Theme
end

return M
