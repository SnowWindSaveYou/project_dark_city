-- ============================================================================
-- Token.lua - 玩家棋子 (贴图表情版)
-- 15 种表情贴图 + 呼吸/弹跳/挤压/翻面动效
-- 放置在卡牌中心，叠加半透明阴影增加可见度
-- ============================================================================

local Tween = require "lib.Tween"
local Theme = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
M.SIZE = 20          -- 基础尺寸半径 (兼容旧引用)
M.BODY_H = 14       -- 身体高度 (兼容旧引用)

-- 精灵渲染尺寸 (逻辑像素) — 适配卡牌内显示
local SPRITE_W = 40
local SPRITE_H = math.floor(SPRITE_W * (768 / 515) + 0.5)  -- ≈ 60

-- 躺尸图是横版 768x515，需要特殊宽高
local DEAD_W = math.floor(SPRITE_H * (768 / 515) + 0.5)    -- ≈ 89
local DEAD_H = SPRITE_H                                      -- 60



-- ---------------------------------------------------------------------------
-- 表情映射
-- ---------------------------------------------------------------------------
local EMOTIONS = {
    default    = "image/主角chibi恐怖风v5_20260425143954.png",
    happy      = "image/主角_开心_20260425144434.png",
    scared     = "image/主角_惊恐v3_20260425145053.png",
    surprised  = "image/主角_惊讶_20260425152052.png",
    nervous    = "image/主角_紧张_20260425152033.png",
    angry      = "image/主角_愤怒_20260425152036.png",
    determined = "image/主角_坚定_20260425152030.png",
    relieved   = "image/主角_释然_20260425152041.png",
    sleepy     = "image/主角_困倦_20260425152033.png",
    confused   = "image/主角_疑惑v5_20260425150409.png",
    sad        = "image/主角_伤心_20260425144628.png",
    dead       = "image/主角_躺尸_20260425154955.png",
    disgusted  = "image/主角_厌恶_20260425152036.png",
    dazed      = "image/主角_呆滞_20260425144455.png",
    running    = "image/主角_奔跑v3_20260425153021.png",
}

-- ---------------------------------------------------------------------------
-- 构造
-- ---------------------------------------------------------------------------

function M.new()
    return {
        x = 0, y = 0,
        targetRow = 1,
        targetCol = 1,
        scaleX = 1.0,
        scaleY = 1.0,
        alpha = 0,
        bounceY = 0,
        squashX = 1.0,
        squashY = 1.0,
        isMoving = false,
        visible = false,
        idleTimer = 0,

        -- 3D 世界坐标 (用于屏幕位置跟随)
        worldX = 0,
        worldZ = 0,

        -- 表情系统
        emotion = "default",
        pendingEmotion = nil,   -- 翻面动画中途待切换的表情
        imageHandles = {},      -- 由 loadImages() 填充
    }
end

-- ---------------------------------------------------------------------------
-- 图片资源管理
-- ---------------------------------------------------------------------------

--- 一次性加载全部表情贴图 (在 Start() 中调用)
---@param vg userdata NanoVG context
---@return table handles  表情名 → nvg image handle
function M.loadImages(vg)
    local handles = {}
    local loaded, failed = 0, 0
    for key, path in pairs(EMOTIONS) do
        -- 同路径不重复加载 (happy 和 default 共享)
        local existing = nil
        for k2, p2 in pairs(EMOTIONS) do
            if p2 == path and handles[k2] then
                existing = handles[k2]
                break
            end
        end
        if existing then
            handles[key] = existing
            loaded = loaded + 1
        else
            local h = nvgCreateImage(vg, path, 0)
            if h and h > 0 then
                handles[key] = h
                loaded = loaded + 1
            else
                print("[Token] ERROR: Failed to load " .. path)
                failed = failed + 1
            end
        end
    end
    print("[Token] Loaded " .. loaded .. " emotions, " .. failed .. " failed")
    return handles
end

--- 清理图片资源 (在 Stop() 中调用)
---@param vg userdata
---@param token table
function M.cleanup(vg, token)
    if not token or not token.imageHandles then return end
    -- 收集去重 (同句柄只删一次)
    local deleted = {}
    for _, handle in pairs(token.imageHandles) do
        if handle and handle > 0 and not deleted[handle] then
            nvgDeleteImage(vg, handle)
            deleted[handle] = true
        end
    end
    token.imageHandles = {}
    print("[Token] Cleaned up " .. #deleted .. " image handles")
end

-- ---------------------------------------------------------------------------
-- 表情切换 (带翻面动效)
-- ---------------------------------------------------------------------------

--- 切换表情
---@param token table
---@param emotion string 表情名
function M.setEmotion(token, emotion)
    if not token.imageHandles[emotion] then
        emotion = "default"
    end
    if token.emotion == emotion then return end

    -- 移动中直接切换，不做翻面
    if token.isMoving then
        token.emotion = emotion
        return
    end

    -- 翻面动效：压扁 → 切图 → 展开
    token.pendingEmotion = emotion
    Tween.to(token, { squashX = 0.0 }, 0.07, {
        easing = Tween.Easing.easeInQuad,
        tag = "tokenflip",
        onComplete = function()
            token.emotion = token.pendingEmotion or emotion
            token.pendingEmotion = nil
            Tween.to(token, { squashX = 1.0 }, 0.09, {
                easing = Tween.Easing.easeOutBack,
                tag = "tokenflip",
            })
        end
    })
end

-- ---------------------------------------------------------------------------
-- 动画: 出现
-- ---------------------------------------------------------------------------

function M.show(token, x, y)
    token.x = x
    token.y = y + 30
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
            Tween.to(token, { squashX = 0.85, squashY = 1.15 }, 0.06, {
                easing = Tween.Easing.easeOutQuad,
                tag = "tokenmove",
            })
        end
    })

    -- 主移动
    Tween.to(token, { x = targetX, y = targetY }, duration, {
        delay = 0.06,
        easing = Tween.Easing.easeInOutCubic,
        tag = "tokenmove",
    })

    -- 弧形跳跃
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

    -- 落地
    Tween.to(token, { squashX = 1.0, squashY = 1.0 }, 0.01, {
        delay = duration + 0.06,
        tag = "tokenmove",
        onComplete = function()
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
-- 渲染: 贴图精灵
-- ---------------------------------------------------------------------------

function M.draw(vg, token, gameTime)
    if not token.visible or token.alpha <= 0.01 then return end

    local imgHandle = token.imageHandles[token.emotion]
        or token.imageHandles["default"]
    if not imgHandle or imgHandle <= 0 then return end

    -- 判断是否为躺尸 (横版图)
    local isDead = (token.emotion == "dead")
    local sw = isDead and DEAD_W or SPRITE_W
    local sh = isDead and DEAD_H or SPRITE_H

    -- idle 呼吸 (非移动时轻微上下浮动)
    local breathe = 0
    if not token.isMoving then
        breathe = math.sin(gameTime * 2.5) * 1.5
    end

    -- 呼吸缩放 (微幅)
    local breatheScale = 1.0
    if not token.isMoving then
        breatheScale = 1.0 + math.sin(gameTime * 2.5) * 0.02
    end

    nvgSave(vg)

    -- 定位到卡牌中心
    local cx = token.x
    local cy = token.y + token.bounceY + breathe
    nvgTranslate(vg, cx, cy)
    nvgGlobalAlpha(vg, token.alpha)

    -- === 精灵贴图 (居中) ===
    nvgScale(vg,
        token.scaleX * token.squashX * breatheScale,
        token.scaleY * token.squashY * breatheScale)

    local imgX = -sw / 2
    local imgY = -sh / 2

    -- 角色阴影: 同图偏移 + 放大 + 低透明度
    local shScale = 1.08
    local shOff = 2
    local shW = sw * shScale
    local shH = sh * shScale
    local shX = -shW / 2 + shOff
    local shY = -shH / 2 + shOff
    local shadowPaint = nvgImagePattern(vg, shX, shY, shW, shH, 0, imgHandle, 0.3)
    nvgBeginPath(vg)
    nvgRect(vg, shX, shY, shW, shH)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    -- 主贴图
    local imgPaint = nvgImagePattern(vg, imgX, imgY, sw, sh, 0, imgHandle, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, imgX, imgY, sw, sh)
    nvgFillPaint(vg, imgPaint)
    nvgFill(vg)

    nvgRestore(vg)
end

return M
