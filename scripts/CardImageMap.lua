-- ============================================================================
-- CardImageMap.lua - 卡面插画路径映射表
-- 维护 (location, eventType) → PNG文件名 的映射关系
-- 同一个 key 可以有多张图，运行时随机选取一张
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- 地点卡面 (location card face) - 未翻开时显示
-- key: locKey → 图片文件名 (位于 image/ 目录下)
-- ---------------------------------------------------------------------------
M.LOCATION_IMAGES = {
    home        = "loc_home_v2_20260514080830.png",
    convenience = "loc_convenience_v2_20260514120100.png",
    church      = "loc_church_v2_20260514080708.png",
    police      = "loc_police_v3_20260514094153.png",
    company     = "loc_company_20260514064210.png",
    school      = "loc_school_v2_20260514075526.png",
    park        = "loc_park_v7_20260514123205.png",
    alley       = "loc_alley_v3_20260514062422.png",
    station     = "loc_station_20260514064028.png",
    hospital    = "loc_hospital_v2_20260514054038.png",
    library     = "card_library_location_v6_20260512094701.png",
    bank        = "loc_bank_v4_20260514115241.png",
    cemetery    = "loc_cemetery_20260514064421.png",
    gym         = "loc_gym_v2_20260514075948.png",
}

-- ---------------------------------------------------------------------------
-- 事件卡面 (event card face) - 翻开后显示
-- key: "locKey_eventType" → { 图片文件名列表 }
-- 若有多张图，运行时随机选一张 (在 getEventImages 时已固定)
-- ---------------------------------------------------------------------------
-- 2-A 通用事件 (fallback，无地点前缀)
local GENERIC = {
    safe    = { "evt_safe_rest_shaft_v1_20260515073125.png" },
    monster = { "evt_monster_shadow_shaft_v2_20260515073514.png",
                "evt_monster_whisper_shaft_v1_20260515072928.png" },
    trap    = { "evt_trap_generic_shaft_v2_20260515074928.png" },
    reward  = { "evt_reward_supply_shaft_v4_20260515075458.png" },
    plot    = { "evt_plot_missing_person_shaft_v1_20260515072942.png",
                "evt_plot_symbol_wall_shaft_v1_20260515072932.png",
                "evt_plot_deep_rumble_shaft_v1_20260515073027.png",
                "evt_plot_find_photo_shaft_v1_20260515072928.png",
                "evt_plot_inscription_shaft_v1_20260515072927.png" },
    clue    = { "evt_clue_footprints_shaft_v1_20260515073029.png",
                "evt_clue_blood_trail_shaft_v1_20260515073026.png",
                "evt_clue_diary_shaft_v6_20260515074137.png",
                "evt_clue_talisman_shaft_v1_20260515073024.png",
                "evt_clue_generic_shaft_v1_20260515073027.png" },
}

-- 2-B 地点专属事件 (按地点 + 类型分组)
M.LOCATION_EVENT_IMAGES = {
    -- 公司
    company = {
        safe    = { "evt_company_safe_bonus_20260512103420.png" },
        plot    = { "evt_company_overtime_20260512104442.png" },
        clue    = { "evt_company_email_clue_20260512105926.png" },
    },
    -- 学校
    school = {
        safe    = { "evt_school_quiet_study_20260512104512.png" },
        reward  = { "evt_school_supply_find_20260512111521.png" },
        clue    = { "evt_school_old_notebook_20260512104523.png" },
    },
    -- 公园
    park = {
        safe    = { "evt_park_healing_breeze_20260512102843.png" },
        reward  = { "evt_park_herb_find_20260512102843.png" },
        clue    = { "evt_park_nature_clue_20260512102840.png" },
    },
    -- 小巷
    alley = {
        monster = { "evt_alley_ambush_20260512102854.png" },
        trap    = { "evt_alley_thugs_trap_20260512111733.png" },
        reward  = { "evt_alley_stash_20260512111843.png" },
        clue    = { "evt_alley_graffiti_clue_20260512111815.png" },
    },
    -- 车站
    station = {
        monster = { "evt_station_ghost_train_20260512111935.png" },
        trap    = { "evt_station_warp_trap_20260512111913.png" },
        reward  = { "evt_station_lost_luggage_20260512112002.png" },
        clue    = { "evt_station_schedule_clue_20260512112025.png" },
    },
    -- 医院
    hospital = {
        safe    = { "evt_hospital_treatment_20260512112328.png" },
        reward  = { "evt_hospital_medicine_reward_20260512180027.png" },
        clue    = { "evt_hospital_medical_record_20260512180052.png" },
    },
    -- 图书馆
    library = {
        safe    = { "evt_library_deep_read_20260512181125.png" },
        monster = { "evt_library_self_turning_book_20260512181226.png" },
        trap    = { "evt_library_forbidden_book_20260512181254.png" },
        clue    = { "evt_library_ancient_scroll_20260512181313.png" },
    },
    -- 银行
    bank = {
        reward  = { "evt_bank_vault_find_20260512181335.png" },
        trap    = { "evt_bank_vault_trap_20260512181356.png" },
        clue    = { "evt_bank_suspicious_record_20260512181419.png" },
    },
    -- 墓地
    cemetery = {
        safe    = { "evt_cemetery_quiet_20260512181440.png" },
        trap    = { "evt_cemetery_sinkhole_20260512181712.png" },
        reward  = { "evt_cemetery_ancient_amulet_20260512182052.png" },
        clue    = { "evt_cemetery_epitaph_clue_20260512182458.png" },
    },
    -- 健身房
    gym = {
        safe    = { "evt_gym_training_20260512182533.png" },
        monster = { "evt_gym_berserk_machine_20260512182553.png" },
        trap    = { "evt_gym_locked_equipment_20260512182747.png" },
        reward  = { "evt_gym_power_crystal_20260512182808.png" },
        clue    = { "evt_gym_bandage_clue_20260512182832.png" },
    },
}

-- ---------------------------------------------------------------------------
-- 公共 API
-- ---------------------------------------------------------------------------

--- 获取地点卡图片文件名（位于 image/ 目录下）
--- 返回 nil 表示无专属插画，使用 NanoVG fallback
---@param locKey string
---@return string|nil
function M.getLocationImage(locKey)
    return M.LOCATION_IMAGES[locKey]
end

--- 获取事件卡图片列表，随机返回一张的文件名
--- 优先使用地点专属图，fallback 到通用图，最后 fallback 返回 nil（用 NanoVG）
---@param locKey string
---@param eventType string
---@return string|nil
function M.getEventImage(locKey, eventType)
    -- 优先地点专属
    local locMap = M.LOCATION_EVENT_IMAGES[locKey]
    if locMap then
        local imgs = locMap[eventType]
        if imgs and #imgs > 0 then
            return imgs[math.random(1, #imgs)]
        end
    end
    -- fallback 通用
    local generic = GENERIC[eventType]
    if generic and #generic > 0 then
        return generic[math.random(1, #generic)]
    end
    return nil
end

return M
