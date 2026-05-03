-- ============================================================================
-- AudioManager.lua — 暗面都市 · 音频管理器
-- 统一管理 BGM 和 SFX 的加载、播放、淡入淡出
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------
---@type Scene
local scene_ = nil

-- BGM
---@type SoundSource
local bgmSource_ = nil
local bgmCurrentKey_ = nil
local bgmFading_ = false       -- 正在淡入淡出
local bgmFadeDir_ = 0          -- 1=淡入, -1=淡出
local bgmFadeSpeed_ = 0
local bgmFadeTarget_ = 0
local bgmPendingKey_ = nil     -- 淡出完成后切到这首
local bgmVolume_ = 0.35        -- BGM 基础音量

-- 环境音
---@type SoundSource
local ambientSource_ = nil
local ambientCurrentKey_ = nil
local ambientVolume_ = 0.30

-- SFX 对象池 (SoundSource 复用, 减少 GC)
local sfxPool_ = {}
local SFX_POOL_MAX = 12

-- ---------------------------------------------------------------------------
-- 资源路径映射
-- ---------------------------------------------------------------------------

local BGM_PATHS = {
    day_light   = "audio/bgm_day_light.ogg",
    day_dark    = "audio/bgm_day_dark.ogg",
    dark_world  = "audio/bgm_dark_world.ogg",
    victory     = "audio/bgm_victory.ogg",
    defeat      = "audio/bgm_defeat.ogg",
}

local AMBIENT_PATHS = {
    rain        = "audio/sfx/weather_rain.ogg",
    wind        = "audio/sfx/weather_wind.ogg",
    dark        = "audio/sfx/dark_ambient.ogg",
}

local SFX_PATHS = {
    -- 卡牌
    card_deal       = "audio/sfx/card_deal.ogg",
    card_flip       = "audio/sfx/card_flip.ogg",
    card_shake      = "audio/sfx/card_shake.ogg",
    card_transform  = "audio/sfx/card_transform.ogg",
    -- 角色
    token_jump      = "audio/sfx/token_jump.ogg",
    item_pickup     = "audio/sfx/item_pickup.ogg",
    -- 相机
    camera_shutter  = "audio/sfx/camera_shutter.ogg",
    camera_enter    = "audio/sfx/camera_enter.ogg",
    camera_exit     = "audio/sfx/camera_exit.ogg",
    viewfinder_hum  = "audio/sfx/viewfinder_hum.ogg",
    film_empty      = "audio/sfx/film_empty.ogg",
    exorcise        = "audio/sfx/exorcise.ogg",
    -- 事件
    evt_safe        = "audio/sfx/evt_safe.ogg",
    evt_monster     = "audio/sfx/evt_monster.ogg",
    evt_trap        = "audio/sfx/evt_trap.ogg",
    evt_reward      = "audio/sfx/evt_reward.ogg",
    evt_clue        = "audio/sfx/evt_clue.ogg",
    evt_plot        = "audio/sfx/evt_plot.ogg",
    evt_photo       = "audio/sfx/evt_photo.ogg",
    -- UI
    popup_open      = "audio/sfx/popup_open.ogg",
    popup_close     = "audio/sfx/popup_close.ogg",
    btn_click       = "audio/sfx/btn_click.ogg",
    notebook_open   = "audio/sfx/notebook_open.ogg",
    notebook_close  = "audio/sfx/notebook_close.ogg",
    resource_gain   = "audio/sfx/resource_gain.ogg",
    resource_lose   = "audio/sfx/resource_lose.ogg",
    -- 商店
    shop_buy        = "audio/sfx/shop_buy.ogg",
    shop_reject     = "audio/sfx/shop_reject.ogg",
    shop_refresh    = "audio/sfx/shop_refresh.ogg",
    -- 天气
    weather_thunder = "audio/sfx/weather_thunder.ogg",
    -- 暗面
    rift_enter      = "audio/sfx/rift_enter.ogg",
    rift_exit       = "audio/sfx/rift_exit.ogg",
    ghost_hit       = "audio/sfx/ghost_hit.ogg",
    ghost_dispel    = "audio/sfx/ghost_dispel.ogg",
    layer_transition = "audio/sfx/layer_transition.ogg",
    -- 道具使用
    item_use_coffee   = "audio/sfx/item_use_coffee.ogg",
    item_use_sedative = "audio/sfx/item_use_sedative.ogg",
    item_use_order    = "audio/sfx/item_use_order.ogg",
    item_use_shield   = "audio/sfx/item_use_shield.ogg",
    item_use_map      = "audio/sfx/item_use_map.ogg",
    item_use_fail     = "audio/sfx/item_use_fail.ogg",
    -- 特效/转场
    screen_shake    = "audio/sfx/screen_shake.ogg",
    screen_flash    = "audio/sfx/screen_flash.ogg",
    banner_text     = "audio/sfx/banner_text.ogg",
    day_transition  = "audio/sfx/day_transition.ogg",
    victory_sting   = "audio/sfx/victory_sting.ogg",
    defeat_sting    = "audio/sfx/defeat_sting.ogg",
}

-- 预加载的 Sound 资源缓存
local soundCache_ = {}

-- SFX 随机化 (消除机械重复感)
local gameTime_ = 0

-- ---------------------------------------------------------------------------
-- Combo SFX (连续触发逐级增强)
-- ---------------------------------------------------------------------------

--- combo 状态按 comboId 独立追踪
--- { [comboId] = { level = 0, lastTime = 0 } }
local comboStates_ = {}

--- combo 配置
local COMBO_CONFIG = {
    window       = 3.0,     -- 两次触发间隔 ≤ 此值视为连击 (秒)
    maxLevel     = 5,       -- 最大 combo 等级
    pitchStep    = 0.06,    -- 每级音调升高比例 (≈1个半音)
    gainStep     = 0.05,    -- 每级音量增加值
    gainBase     = 0.70,    -- 基础音量
    gainMax      = 0.95,    -- 音量上限
}

-- ---------------------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------------------

function M.init(scene)
    scene_ = scene

    -- BGM SoundSource (持久)
    bgmSource_ = scene_:CreateComponent("SoundSource")
    bgmSource_.soundType = "Music"
    bgmSource_.gain = 0

    -- 环境音 SoundSource (持久)
    ambientSource_ = scene_:CreateComponent("SoundSource")
    ambientSource_.soundType = "Ambient"
    ambientSource_.gain = 0

    -- 设置主音量
    local audioSys = GetAudio()
    audioSys:SetMasterGain("Effect", 0.75)
    audioSys:SetMasterGain("Music", 0.50)
    audioSys:SetMasterGain("Ambient", 0.50)

    print("[AudioManager] Initialized")
end

-- ---------------------------------------------------------------------------
-- Sound 加载 (带缓存)
-- ---------------------------------------------------------------------------

local function loadSound(path, looped)
    local key = path .. (looped and "_loop" or "")
    if soundCache_[key] then return soundCache_[key] end

    local snd = cache:GetResource("Sound", path)
    if not snd then
        print("[AudioManager] WARNING: Sound not found: " .. path)
        return nil
    end
    if looped then
        snd.looped = true
    end
    soundCache_[key] = snd
    return snd
end

-- ---------------------------------------------------------------------------
-- SFX 对象池
-- ---------------------------------------------------------------------------

--- 获取一个空闲 SoundSource (或创建新的)
local function acquireSFXSource()
    -- 回收已停止的
    for i = #sfxPool_, 1, -1 do
        if not sfxPool_[i]:IsPlaying() then
            return sfxPool_[i]
        end
    end
    -- 池未满, 创建新的
    if #sfxPool_ < SFX_POOL_MAX then
        local src = scene_:CreateComponent("SoundSource")
        src.soundType = "Effect"
        src.gain = 0.7
        sfxPool_[#sfxPool_ + 1] = src
        return src
    end
    -- 池满, 抢占最早的
    local oldest = sfxPool_[1]
    oldest:Stop()
    return oldest
end

-- ---------------------------------------------------------------------------
-- 公开 API: SFX
-- ---------------------------------------------------------------------------

--- 播放一次性音效 (带冷却 / 连发衰减 / 音调随机化)
---@param key string SFX_PATHS 中的键名
---@param gain? number 音量覆盖 (默认 0.7)
function M.playSFX(key, gain)
    if not scene_ then return end
    local path = SFX_PATHS[key]
    if not path then
        print("[AudioManager] Unknown SFX key: " .. tostring(key))
        return
    end

    local snd = loadSound(path, false)
    if not snd then return end

    -- 微小音量随机 (±5%)
    local baseGain = (gain or 0.7) * (0.95 + math.random() * 0.10)

    local src = acquireSFXSource()
    src.gain = baseGain

    -- 音调微随机 (±4%), 避免机械重复感
    src.frequency = snd.frequency * (0.96 + math.random() * 0.08)

    src:Play(snd)
end

--- 播放 combo 音效 — 同一 comboId 短时间内连续触发时逐级增强
--- 音调逐级升高 (半音阶)、音量递增、保留微随机
--- 超过 window 未触发自动 reset 回 level 0
---@param key string     SFX_PATHS 中的键名
---@param comboId string combo 组标识 (不同来源互不干扰)
---@return number level  本次 combo 等级 (0 = 首次, 1~maxLevel = 连击)
function M.playSFXCombo(key, comboId)
    if not scene_ then return 0 end
    local path = SFX_PATHS[key]
    if not path then
        print("[AudioManager] Unknown SFX key: " .. tostring(key))
        return 0
    end

    local snd = loadSound(path, false)
    if not snd then return 0 end

    -- 更新 combo 状态
    local now   = gameTime_
    local cs    = comboStates_[comboId]
    if not cs then
        cs = { level = 0, lastTime = 0 }
        comboStates_[comboId] = cs
    end

    local elapsed = now - cs.lastTime
    if elapsed <= COMBO_CONFIG.window and cs.lastTime > 0 then
        -- 在窗口内 → 提升等级
        cs.level = math.min(cs.level + 1, COMBO_CONFIG.maxLevel)
    else
        -- 超时 → 重置
        cs.level = 0
    end
    cs.lastTime = now

    local level = cs.level

    -- 计算 combo 增强后的音调和音量
    local pitchMul = 1.0 + level * COMBO_CONFIG.pitchStep
    local comboGain = math.min(
        COMBO_CONFIG.gainBase + level * COMBO_CONFIG.gainStep,
        COMBO_CONFIG.gainMax
    )

    -- 保留微随机 (±3%, combo 等级越高随机幅度越小，手感更稳)
    local randRange = 0.03 * (1 - level / (COMBO_CONFIG.maxLevel + 1))
    local gainFinal = comboGain * (1.0 - randRange + math.random() * randRange * 2)
    local freqFinal = snd.frequency * pitchMul * (1.0 - randRange + math.random() * randRange * 2)

    local src = acquireSFXSource()
    src.gain      = gainFinal
    src.frequency = freqFinal
    src:Play(snd)

    return level
end

--- 手动重置指定 combo 组
---@param comboId string
function M.resetCombo(comboId)
    comboStates_[comboId] = nil
end

-- ---------------------------------------------------------------------------
-- 公开 API: BGM
-- ---------------------------------------------------------------------------

--- 切换 BGM (交叉淡入淡出)
---@param key string|nil BGM_PATHS 中的键名, nil 则停止
---@param fadeTime? number 淡入淡出时长 (默认 1.5s)
function M.playBGM(key, fadeTime)
    if not scene_ or not bgmSource_ then return end
    if key == bgmCurrentKey_ and not bgmFading_ then return end

    fadeTime = fadeTime or 1.5

    if not key then
        -- 淡出停止
        bgmFading_ = true
        bgmFadeDir_ = -1
        bgmFadeSpeed_ = bgmVolume_ / math.max(fadeTime, 0.1)
        bgmFadeTarget_ = 0
        bgmPendingKey_ = nil
        bgmCurrentKey_ = nil
        return
    end

    local path = BGM_PATHS[key]
    if not path then
        print("[AudioManager] Unknown BGM key: " .. tostring(key))
        return
    end

    if bgmSource_:IsPlaying() then
        -- 淡出当前 → 淡入新的
        bgmFading_ = true
        bgmFadeDir_ = -1
        bgmFadeSpeed_ = bgmVolume_ / math.max(fadeTime * 0.5, 0.1)
        bgmFadeTarget_ = 0
        bgmPendingKey_ = key
    else
        -- 直接淡入
        local snd = loadSound(path, true)
        if not snd then return end
        bgmSource_:Play(snd)
        bgmSource_.gain = 0
        bgmFading_ = true
        bgmFadeDir_ = 1
        bgmFadeSpeed_ = bgmVolume_ / math.max(fadeTime, 0.1)
        bgmFadeTarget_ = bgmVolume_
        bgmCurrentKey_ = key
        bgmPendingKey_ = nil
    end
end

--- 播放一次性音乐 (胜利/失败短乐句, 不循环, 不影响 BGM 状态)
function M.playStinger(key, gain)
    if not scene_ then return end
    local path = SFX_PATHS[key]
    if not path then return end
    local snd = loadSound(path, false)
    if not snd then return end
    local src = acquireSFXSource()
    src.gain = gain or 0.8
    src:Play(snd)
end

-- ---------------------------------------------------------------------------
-- 公开 API: 环境音
-- ---------------------------------------------------------------------------

--- 播放环境音 (循环, 淡入)
---@param key string|nil AMBIENT_PATHS 中的键名, nil 则停止
function M.playAmbient(key)
    if not scene_ or not ambientSource_ then return end
    if key == ambientCurrentKey_ then return end

    if not key then
        ambientSource_:Stop()
        ambientSource_.gain = 0
        ambientCurrentKey_ = nil
        return
    end

    local path = AMBIENT_PATHS[key]
    if not path then return end
    local snd = loadSound(path, true)
    if not snd then return end

    ambientSource_:Play(snd)
    ambientSource_.gain = ambientVolume_
    ambientCurrentKey_ = key
end

--- 停止环境音
function M.stopAmbient()
    M.playAmbient(nil)
end

-- ---------------------------------------------------------------------------
-- 每帧更新 (BGM 淡入淡出)
-- ---------------------------------------------------------------------------

function M.update(dt)
    gameTime_ = gameTime_ + dt

    if not bgmFading_ or not bgmSource_ then return end

    local g = bgmSource_.gain + bgmFadeDir_ * bgmFadeSpeed_ * dt

    if bgmFadeDir_ > 0 then
        -- 淡入
        if g >= bgmFadeTarget_ then
            g = bgmFadeTarget_
            bgmFading_ = false
        end
    else
        -- 淡出
        if g <= 0 then
            g = 0
            bgmSource_:Stop()
            bgmFading_ = false

            -- 有待播放的新曲
            if bgmPendingKey_ then
                local nextKey = bgmPendingKey_
                bgmPendingKey_ = nil
                local path = BGM_PATHS[nextKey]
                if path then
                    local snd = loadSound(path, true)
                    if snd then
                        bgmSource_:Play(snd)
                        bgmSource_.gain = 0
                        bgmFading_ = true
                        bgmFadeDir_ = 1
                        bgmFadeSpeed_ = bgmVolume_ / 1.0  -- 1s 淡入
                        bgmFadeTarget_ = bgmVolume_
                        bgmCurrentKey_ = nextKey
                    end
                end
            end
        end
    end

    bgmSource_.gain = g
end

-- ---------------------------------------------------------------------------
-- 重置
-- ---------------------------------------------------------------------------

function M.reset()
    if bgmSource_ then
        bgmSource_:Stop()
        bgmSource_.gain = 0
    end
    if ambientSource_ then
        ambientSource_:Stop()
        ambientSource_.gain = 0
    end
    bgmCurrentKey_ = nil
    bgmFading_ = false
    bgmPendingKey_ = nil
    ambientCurrentKey_ = nil
end

-- ---------------------------------------------------------------------------
-- 便捷方法: 资源变化音效
-- ---------------------------------------------------------------------------

function M.playResourceChange(delta)
    if delta > 0 then
        M.playSFX("resource_gain")
    elseif delta < 0 then
        M.playSFX("resource_lose")
    end
end

-- ---------------------------------------------------------------------------
-- 便捷方法: 道具使用音效
-- ---------------------------------------------------------------------------

--- 道具 key → 使用音效 key 映射
local ITEM_USE_SFX = {
    coffee    = "item_use_coffee",
    sedative  = "item_use_sedative",
    orderManual = "item_use_order",
    shield    = "item_use_shield",
    mapReveal = "item_use_map",
    exorcism  = "exorcise",  -- 驱魔香复用已有的 exorcise 音效
}

--- 播放道具使用音效 (根据道具 key 自动选择)
---@param itemKey string 道具 key (coffee/sedative/orderManual/shield/mapReveal/exorcism)
function M.playItemUse(itemKey)
    local sfxKey = ITEM_USE_SFX[itemKey]
    if sfxKey then
        M.playSFX(sfxKey)
    else
        M.playSFX("item_pickup")  -- fallback
    end
end

--- 播放道具使用失败音效
function M.playItemUseFail()
    M.playSFX("item_use_fail")
end

return M
