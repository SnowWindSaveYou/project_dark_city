## CardImageMap.gd - 卡面插画路径映射表
## 静态工具类，提供 (location, eventType) → Texture2D 的映射
## 对标 Lua 版 CardImageMap.lua，三张表: LOCATION_IMAGES / LOCATION_EVENT_IMAGES / GENERIC
##
## 用法（静态调用，无需 autoload）：
##   var tex := CardImageMap.get_event_texture("alley", "monster")  # → Texture2D or null
##   var path := CardImageMap.get_event_image_path("park", "safe")  # → "res://..." or ""
class_name CardImageMap

const IMAGE_BASE := "res://assets/image/"

# ---------------------------------------------------------------------------
# 地点卡面 (location card face) - 未翻开时显示
# key: locKey → 图片文件名
# ---------------------------------------------------------------------------
const LOCATION_IMAGES: Dictionary = {
	"home":        "loc_home_v2_20260514080830.png",
	"convenience": "loc_convenience_v2_20260514120100.png",
	"church":      "loc_church_v2_20260514080708.png",
	"police":      "loc_police_v3_20260514094153.png",
	"company":     "loc_company_20260514064210.png",
	"school":      "loc_school_v2_20260514075526.png",
	"park":        "loc_park_v7_20260514123205.png",
	"alley":       "loc_alley_v3_20260514062422.png",
	"station":     "loc_station_20260514064028.png",
	"hospital":    "loc_hospital_v2_20260514054038.png",
	"library":     "card_library_location_v6_20260512094701.png",
	"bank":        "loc_bank_v4_20260514115241.png",
	"cemetery":    "loc_cemetery_20260514064421.png",
	"gym":         "loc_gym_v2_20260514075948.png",
}

# ---------------------------------------------------------------------------
# 通用事件图 (fallback，无地点前缀)
# ---------------------------------------------------------------------------
const GENERIC: Dictionary = {
	"safe":    ["evt_safe_rest_shaft_20260515084013.png"],
	"monster": [
		"evt_monster_shadow_shaft_v2_20260515073514.png",
		"evt_monster_whisper_shaft_v1_20260515072928.png",
	],
	"trap":    ["evt_trap_generic_shaft_v2_20260515074928.png"],
	"reward":  ["evt_reward_supply_shaft_v4_20260515075458.png"],
	"plot": [
		"evt_plot_missing_person_shaft_v1_20260515072942.png",
		"evt_plot_symbol_wall_shaft_v1_20260515072932.png",
		"evt_plot_deep_rumble_shaft_v1_20260515073027.png",
		"evt_plot_find_photo_shaft_v2_20260515080100.png",
		"evt_plot_inscription_shaft_v1_20260515072927.png",
	],
	"clue": [
		"evt_clue_footprints_shaft_v1_20260515073029.png",
		"evt_clue_blood_trail_shaft_v1_20260515073026.png",
		"evt_clue_diary_shaft_v6_20260515074137.png",
		"evt_clue_talisman_shaft_v1_20260515073024.png",
		"evt_clue_generic_shaft_v1_20260515073027.png",
	],
}

# ---------------------------------------------------------------------------
# 地点专属事件图
# key: "locKey" → { "eventType": ["文件名", ...], ... }
# ---------------------------------------------------------------------------
const LOCATION_EVENT_IMAGES: Dictionary = {
	"company": {
		"safe":   ["evt_company_safe_bonus_20260512103420.png"],
		"trap":   ["evt_company_overtime_20260512104442.png"],
		"reward": ["evt_company_reward_briefcase_20260515100611.png"],
		"clue":   ["evt_company_email_clue_20260512105926.png"],
	},
	"school": {
		"safe":   ["evt_school_quiet_study_20260512104512.png"],
		"plot":   ["evt_school_plot_backpack_20260515100613.png"],
		"reward": ["evt_school_supply_find_20260512111521.png"],
		"clue":   ["evt_school_old_notebook_20260512104523.png"],
	},
	"park": {
		"safe":   ["evt_park_healing_breeze_20260512102843.png"],
		"trap":   ["evt_park_trap_vines_20260515100608.png"],
		"reward": ["evt_park_herb_find_20260512102843.png"],
		"clue":   ["evt_park_nature_clue_shaft_20260515083206.png"],
	},
	"alley": {
		"safe":    ["evt_alley_safe_20260515100612.png"],
		"monster": ["evt_alley_ambush_20260512102854.png"],
		"trap":    ["evt_alley_thugs_trap_shaft_20260515083207.png"],
		"reward":  ["evt_alley_stash_20260512111843.png"],
		"clue":    ["evt_alley_graffiti_clue_shaft_20260515083204.png"],
	},
	"station": {
		"safe":    ["evt_station_safe_20260515100633.png"],
		"monster": ["evt_station_ghost_train_20260512111935.png"],
		"trap":    ["evt_station_warp_trap_20260512111913.png"],
		"reward":  ["evt_station_lost_luggage_20260512112002.png"],
		"clue":    ["evt_station_schedule_clue_20260512112025.png"],
	},
	"hospital": {
		"safe":    ["evt_hospital_treatment_20260512112328.png"],
		"monster": ["evt_hospital_monster_nurse_20260515100605.png"],
		"reward":  ["evt_hospital_medicine_reward_20260512180027.png"],
		"clue":    ["evt_hospital_medical_record_20260512180052.png"],
	},
	"library": {
		"safe":    ["evt_library_deep_read_20260512181125.png"],
		"monster": ["evt_library_self_turning_book_20260512181226.png"],
		"plot":    ["evt_library_forbidden_book_20260512181254.png"],
		"reward":  ["evt_library_ancient_scroll_20260512181313.png"],
	},
	"bank": {
		"safe":  ["evt_bank_vault_find_20260512181335.png"],
		"trap":  ["evt_bank_vault_trap_20260512181356.png"],
		"clue":  ["evt_bank_suspicious_record_20260512181419.png"],
	},
	"cemetery": {
		"safe":   ["evt_cemetery_quiet_20260512181440.png"],
		"trap":   ["evt_cemetery_sinkhole_20260512181712.png"],
		"reward": ["evt_cemetery_ancient_amulet_20260512182052.png"],
		"clue":   ["evt_cemetery_epitaph_clue_20260512182458.png"],
	},
	"gym": {
		"safe":    ["evt_gym_training_20260512182533.png"],
		"monster": ["evt_gym_berserk_machine_20260512182553.png"],
		"trap":    ["evt_gym_locked_equipment_20260512182747.png"],
		"reward":  ["evt_gym_power_crystal_20260512182808.png"],
		"clue":    ["evt_gym_bandage_clue_20260512182832.png"],
	},
}

# ---------------------------------------------------------------------------
# 公共 API
# ---------------------------------------------------------------------------

## 获取地点卡图片的 res:// 完整路径（无图返回空字符串）
static func get_location_image_path(loc_key: String) -> String:
	var filename: String = LOCATION_IMAGES.get(loc_key, "")
	if filename.is_empty():
		return ""
	return IMAGE_BASE + filename

## 获取地点卡 Texture2D（无图返回 null）
static func get_location_texture(loc_key: String) -> Texture2D:
	var path := get_location_image_path(loc_key)
	if path.is_empty():
		return null
	return load(path) as Texture2D

## 获取事件卡图片的 res:// 完整路径（随机从列表中选取一张）
## 优先地点专属图，fallback 通用图，全无则返回空字符串
static func get_event_image_path(loc_key: String, event_type: String) -> String:
	# 优先地点专属
	var loc_map: Dictionary = LOCATION_EVENT_IMAGES.get(loc_key, {})
	var imgs: Array = loc_map.get(event_type, [])
	if not imgs.is_empty():
		return IMAGE_BASE + (imgs[randi() % imgs.size()] as String)
	# fallback 通用
	var generic_imgs: Array = GENERIC.get(event_type, [])
	if not generic_imgs.is_empty():
		return IMAGE_BASE + (generic_imgs[randi() % generic_imgs.size()] as String)
	return ""

## 获取事件卡 Texture2D（无图返回 null）
static func get_event_texture(loc_key: String, event_type: String) -> Texture2D:
	var path := get_event_image_path(loc_key, event_type)
	if path.is_empty():
		return null
	return load(path) as Texture2D
