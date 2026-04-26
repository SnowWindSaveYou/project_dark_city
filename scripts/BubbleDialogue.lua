-- ============================================================================
-- BubbleDialogue.lua - 气泡对话系统
-- 角色头顶白色气泡框 (带三角箭头)，NanoVG 绘制
-- 触发: 静止一段时间 / 点击角色
-- 支持多角色复用
-- ============================================================================

local Tween  = require "lib.Tween"
local Theme  = require "Theme"

local M = {}

-- ---------------------------------------------------------------------------
-- 配置
-- ---------------------------------------------------------------------------
local IDLE_TRIGGER_TIME  = 4.0   -- 静止多久后自动弹出 (秒)
local DISPLAY_DURATION   = 3.5   -- 气泡显示时长 (秒)
local COOLDOWN           = 5.0   -- 自动触发冷却 (秒), 防止频繁弹出
local CLICK_COOLDOWN     = 1.5   -- 点击触发冷却 (秒)

local BUBBLE_MAX_W       = 180   -- 气泡最大宽度 (逻辑像素)
local BUBBLE_PAD_H       = 10    -- 水平内边距
local BUBBLE_PAD_V       = 8     -- 垂直内边距
local BUBBLE_RADIUS      = 8     -- 圆角半径
local BUBBLE_ARROW_W     = 10    -- 箭头宽度
local BUBBLE_ARROW_H     = 8     -- 箭头高度
local BUBBLE_OFFSET_Y    = 12    -- 气泡底部到角色头顶的间距
local FONT_SIZE          = 13    -- 字体大小
local LINE_HEIGHT        = 1.3   -- 行高倍数

-- ---------------------------------------------------------------------------
-- 通用对话池 (任何区域/任何时候都可能出现)
-- ---------------------------------------------------------------------------
local COMMON_LINES = {
    "这座城市……总感觉哪里不对劲。",
    "还好手机没电了，不然肯定会看到更可怕的东西。",
    "脚步声……是我自己的吧？",
    "深呼吸……再深呼吸……",
    "口袋里的零钱越来越少了。",
    "要是有杯热咖啡就好了……",
    "……我为什么在这里来着？",
    "总觉得有人在看我。",
    "记忆好像有些模糊了。",
    "别慌，这一切都有解释的。一定有。",
    "唔……好困。但是不能睡着。",
    "这条路我走过吗？都长一个样。",
    "明天一定会好起来的……吧？",
    "嗯？那边的影子动了一下？",
    "还有胶卷吗……得省着点用。",
    "风好冷。",
    "如果能回到正常的日子就好了。",
}

-- ---------------------------------------------------------------------------
-- 区域/地点相关对话池
-- ---------------------------------------------------------------------------
local LOCATION_LINES = {
    home = {
        "至少家里还算安全……大概。",
        "门锁好了吗？再检查一遍。",
        "终于能歇一会儿了。",
    },
    company = {
        "加班到这个时候，同事们都去哪了？",
        "电脑屏幕上的文字……好像在变。",
        "茶水间的灯又闪了。",
    },
    school = {
        "放学后的走廊好安静。",
        "黑板上多了一行字，不是老师写的。",
        "储物柜里传来敲击声。",
    },
    park = {
        "公园的长椅上有个人……还是说那是个影子？",
        "秋千自己在晃。",
        "这棵树好像比昨天高了。",
    },
    alley = {
        "这条巷子怎么走不到头？",
        "涂鸦在月光下好像会动。",
        "垃圾桶后面有响动。",
    },
    station = {
        "末班车早就过了，可广播还在响。",
        "月台上只有我一个人。",
        "铁轨上传来嗡嗡声。",
    },
    hospital = {
        "消毒水的味道让人清醒。",
        "走廊尽头的灯一直在闪。",
        "护士台空无一人。",
    },
    library = {
        "书架后面好像有人在翻书。",
        "这本书的作者名字是我的？",
        "安静得能听见心跳。",
    },
    convenience = {
        "店员的笑容怎么一直没变？",
        "货架上的东西似乎和昨天不一样。",
        "收银台的时钟停了。",
    },
    church = {
        "在这里心情能平静一些。",
        "烛光摇曳，影子在墙上跳舞。",
        "祈祷真的有用吗？",
    },
    police = {
        "巡逻车停在路边，但没人在里面。",
        "公告栏上贴着奇怪的寻人启事。",
        "这里应该是安全的。",
    },
    shrine = {
        "鸟居下面的风好像暖一些。",
        "绘马上写着看不懂的文字。",
        "铃铛的声音在耳边回荡。",
    },
    market = {
        "摊位都收了，只剩一个在营业。",
        "这些蔬果的颜色不太对劲。",
        "老板娘说这是最后一批了。",
    },
    cinema = {
        "海报上的人好像在朝我笑。",
        "空荡荡的放映厅传来笑声。",
        "这部电影我看过，但剧情不是这样的。",
    },
    apartment = {
        "隔壁房间传来搬家的声音，但那里已经空了很久。",
        "楼道的灯总是坏。",
        "信箱里有一封没有署名的信。",
    },
    factory = {
        "机器不知为何还在运转。",
        "这里早就停产了才对。",
        "烟囱冒出的不是烟。",
    },
}

-- ---------------------------------------------------------------------------
-- 事件类型相关对话 (翻牌后, 根据上一次事件类型触发)
-- ---------------------------------------------------------------------------
local EVENT_LINES = {
    monster = {
        "刚才那个东西……不要再想了。",
        "心跳还没平复下来。",
        "理智值掉了不少……得小心。",
        "下次得绕着走。",
    },
    trap = {
        "这里的地面不太稳。",
        "还好没受重伤。",
        "得注意脚下。",
    },
    safe = {
        "嗯，这里安全。暂时的。",
        "喘口气再继续。",
    },
    clue = {
        "这条线索……似乎很重要。",
        "传闻背后的真相是什么？",
        "越来越接近答案了。",
    },
    reward = {
        "运气不错，捡到好东西了。",
        "这些物资很有用。",
    },
    shop = {
        "价格有点黑……但没得选。",
        "那个商人到底是什么来头？",
    },
    plot = {
        "这座城市藏着太多秘密。",
        "有人在帮我？还是在算计我？",
    },
}

-- ---------------------------------------------------------------------------
-- 气泡实例
-- ---------------------------------------------------------------------------

---@class BubbleInstance
---@field text string 当前显示的文字
---@field alpha number 透明度 0~1
---@field scale number 缩放 0~1
---@field offsetY number 额外 Y 偏移 (弹出动画)
---@field timer number 显示计时
---@field state string "hidden" | "showing" | "visible" | "hiding"
---@field idleAccum number 累计静止时间
---@field cooldownTimer number 冷却计时

--- 创建气泡实例 (每个角色一个)
---@return BubbleInstance
function M.newBubble()
    return {
        text = "",
        alpha = 0,
        scale = 0,
        offsetY = 5,    -- 弹出时向上偏移
        timer = 0,
        state = "hidden",
        idleAccum = 0,
        cooldownTimer = 0,
        lastEventType = nil,   -- 上一次翻牌的事件类型
        lastLocation = nil,    -- 当前所在地点
    }
end

-- ---------------------------------------------------------------------------
-- 对话选取
-- ---------------------------------------------------------------------------

--- 根据上下文选取一条随机对话
---@param bubble BubbleInstance
---@return string
local function pickLine(bubble)
    -- 候选池: 通用 + 地点 + 事件
    local candidates = {}

    -- 通用对话 (权重 1)
    for _, line in ipairs(COMMON_LINES) do
        candidates[#candidates + 1] = line
    end

    -- 当前地点对话 (权重 2, 加两遍提高概率)
    if bubble.lastLocation and LOCATION_LINES[bubble.lastLocation] then
        for _, line in ipairs(LOCATION_LINES[bubble.lastLocation]) do
            candidates[#candidates + 1] = line
            candidates[#candidates + 1] = line
        end
    end

    -- 最近事件对话 (权重 2)
    if bubble.lastEventType and EVENT_LINES[bubble.lastEventType] then
        for _, line in ipairs(EVENT_LINES[bubble.lastEventType]) do
            candidates[#candidates + 1] = line
            candidates[#candidates + 1] = line
        end
    end

    if #candidates == 0 then
        return "……"
    end

    return candidates[math.random(1, #candidates)]
end

-- ---------------------------------------------------------------------------
-- 触发 / 关闭
-- ---------------------------------------------------------------------------

--- 显示气泡 (外部调用: 点击角色 / 事件触发)
---@param bubble BubbleInstance
---@param location string|nil 当前地点
---@param eventType string|nil 最近事件类型
function M.show(bubble, location, eventType)
    if bubble.state == "showing" or bubble.state == "visible" then
        return  -- 已在显示中, 不重复触发
    end

    if bubble.cooldownTimer > 0 then
        return  -- 冷却中
    end

    -- 更新上下文
    if location then bubble.lastLocation = location end
    if eventType then bubble.lastEventType = eventType end

    bubble.text = pickLine(bubble)
    bubble.timer = 0
    bubble.state = "showing"

    -- 弹入动画
    Tween.cancelTag("bubble")
    bubble.alpha = 0
    bubble.scale = 0.3
    bubble.offsetY = 8

    Tween.to(bubble, { alpha = 1, scale = 1, offsetY = 0 }, 0.3, {
        easing = Tween.Easing.easeOutBack,
        tag = "bubble",
        onComplete = function()
            bubble.state = "visible"
        end
    })
end

--- 隐藏气泡
---@param bubble BubbleInstance
function M.hide(bubble)
    if bubble.state == "hidden" or bubble.state == "hiding" then
        return
    end

    bubble.state = "hiding"
    Tween.cancelTag("bubble")

    Tween.to(bubble, { alpha = 0, scale = 0.6, offsetY = -5 }, 0.2, {
        easing = Tween.Easing.easeInQuad,
        tag = "bubble",
        onComplete = function()
            bubble.state = "hidden"
            bubble.cooldownTimer = COOLDOWN
        end
    })
end

--- 强制立即隐藏 (场景切换等)
---@param bubble BubbleInstance
function M.forceHide(bubble)
    Tween.cancelTag("bubble")
    bubble.state = "hidden"
    bubble.alpha = 0
    bubble.scale = 0
    bubble.timer = 0
    bubble.idleAccum = 0
end

-- ---------------------------------------------------------------------------
-- 上下文更新 (main.lua 中事件发生时调用)
-- ---------------------------------------------------------------------------

--- 更新最近事件上下文 (翻牌后调用)
function M.setContext(bubble, location, eventType)
    if location then bubble.lastLocation = location end
    if eventType then bubble.lastEventType = eventType end
end

-- ---------------------------------------------------------------------------
-- 每帧更新
-- ---------------------------------------------------------------------------

--- 每帧更新 (检测静止触发 / 显示计时 / 冷却)
---@param bubble BubbleInstance
---@param dt number 帧间隔
---@param isIdle boolean 角色是否静止 (不在移动/翻牌/弹窗中)
---@param canTrigger boolean 是否允许自动触发 (playing + ready 状态)
function M.update(bubble, dt, isIdle, canTrigger)
    -- 冷却
    if bubble.cooldownTimer > 0 then
        bubble.cooldownTimer = bubble.cooldownTimer - dt
    end

    -- 显示计时 → 自动隐藏
    if bubble.state == "visible" then
        bubble.timer = bubble.timer + dt
        if bubble.timer >= DISPLAY_DURATION then
            M.hide(bubble)
        end
    end

    -- 静止触发
    if isIdle and canTrigger then
        bubble.idleAccum = bubble.idleAccum + dt
        if bubble.idleAccum >= IDLE_TRIGGER_TIME and bubble.state == "hidden" then
            M.show(bubble)
            bubble.idleAccum = 0  -- 重置，下次再等
        end
    else
        bubble.idleAccum = 0  -- 移动/操作中重置累计
    end

    -- 角色移动时立即关闭
    if not isIdle and bubble.state ~= "hidden" then
        M.hide(bubble)
    end
end

-- ---------------------------------------------------------------------------
-- 点击角色触发
-- ---------------------------------------------------------------------------

--- 点击触发 (外部检测到点击角色后调用)
---@param bubble BubbleInstance
function M.clickTrigger(bubble)
    if bubble.state == "visible" or bubble.state == "showing" then
        -- 已在显示, 换一条
        M.hide(bubble)
        bubble.cooldownTimer = CLICK_COOLDOWN
        -- 短延迟后弹出新的
        local tmp = { t = 0 }
        Tween.to(tmp, { t = 1 }, 0.35, {
            tag = "bubble",
            onComplete = function()
                bubble.cooldownTimer = 0
                M.show(bubble)
            end
        })
        return
    end

    -- 未显示 → 直接弹出
    bubble.cooldownTimer = 0
    M.show(bubble)
end

-- ---------------------------------------------------------------------------
-- NanoVG 绘制
-- ---------------------------------------------------------------------------

--- 绘制气泡 (在 NanoVGRender 中调用)
---@param bubble BubbleInstance
---@param vg userdata NanoVG 上下文
---@param screenX number 角色头顶投影的屏幕 X (逻辑像素)
---@param screenY number 角色头顶投影的屏幕 Y (逻辑像素)
function M.draw(bubble, vg, screenX, screenY)
    if bubble.state == "hidden" or bubble.alpha < 0.01 then
        return
    end

    local text = bubble.text
    if not text or text == "" then return end

    local alpha = math.max(0, math.min(1, bubble.alpha))
    local sc = bubble.scale

    -- 文字换行测量
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 测量文字宽度 (限制最大宽度)
    local textMaxW = BUBBLE_MAX_W - BUBBLE_PAD_H * 2
    local bounds = nvgTextBoxBounds(vg, 0, 0, textMaxW, text)

    local textW = (bounds and bounds[3] or textMaxW) - (bounds and bounds[1] or 0)
    local textH = (bounds and bounds[4] or FONT_SIZE) - (bounds and bounds[2] or 0)

    -- 气泡尺寸
    local bw = textW + BUBBLE_PAD_H * 2
    local bh = textH + BUBBLE_PAD_V * 2

    -- 气泡位置 (居中于角色头顶上方)
    local bx = screenX - bw / 2
    local by = screenY - bh - BUBBLE_ARROW_H - BUBBLE_OFFSET_Y + bubble.offsetY

    -- 缩放变换 (以气泡底部中点为缩放中心)
    nvgSave(vg)
    local pivotX = screenX
    local pivotY = by + bh + BUBBLE_ARROW_H
    nvgTranslate(vg, pivotX, pivotY)
    nvgScale(vg, sc, sc)
    nvgTranslate(vg, -pivotX, -pivotY)

    -- 半透明阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx + 2, by + 2, bw, bh, BUBBLE_RADIUS)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(30 * alpha)))
    nvgFill(vg)

    -- 白色气泡背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bw, bh, BUBBLE_RADIUS)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(240 * alpha)))
    nvgFill(vg)

    -- 细边框
    nvgStrokeColor(vg, nvgRGBA(180, 180, 180, math.floor(120 * alpha)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 三角箭头 (在气泡底部中间, 指向角色)
    local arrowCX = screenX
    local arrowTop = by + bh
    nvgBeginPath(vg)
    nvgMoveTo(vg, arrowCX - BUBBLE_ARROW_W / 2, arrowTop)
    nvgLineTo(vg, arrowCX, arrowTop + BUBBLE_ARROW_H)
    nvgLineTo(vg, arrowCX + BUBBLE_ARROW_W / 2, arrowTop)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(240 * alpha)))
    nvgFill(vg)

    -- 箭头边框 (只画两条斜边, 不画顶边)
    nvgBeginPath(vg)
    nvgMoveTo(vg, arrowCX - BUBBLE_ARROW_W / 2, arrowTop)
    nvgLineTo(vg, arrowCX, arrowTop + BUBBLE_ARROW_H)
    nvgLineTo(vg, arrowCX + BUBBLE_ARROW_W / 2, arrowTop)
    nvgStrokeColor(vg, nvgRGBA(180, 180, 180, math.floor(120 * alpha)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 覆盖箭头与气泡接合处的边框线 (白色填充条)
    nvgBeginPath(vg)
    nvgRect(vg, arrowCX - BUBBLE_ARROW_W / 2 - 1, arrowTop - 1,
               BUBBLE_ARROW_W + 2, 2)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(240 * alpha)))
    nvgFill(vg)

    -- 文字
    nvgFillColor(vg, nvgRGBA(50, 50, 50, math.floor(220 * alpha)))
    nvgTextBox(vg, bx + BUBBLE_PAD_H, by + BUBBLE_PAD_V, textMaxW, text)

    nvgRestore(vg)
end

return M
