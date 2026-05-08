## EndingSystem - 多结局判定系统
## 从 story_config.json 加载结局定义，按优先级匹配首个满足条件的结局
## 由 GameData.check_victory() / check_defeat() 触发时调用
class_name EndingSystem
extends RefCounted

# ---------------------------------------------------------------------------
# 结局判定
# ---------------------------------------------------------------------------

## 评估当前状态，返回最佳匹配结局
## 遍历 StoryManager._endings (已按 priority 升序排列)
## 返回第一个条件满足的结局 Dictionary，或 default 兜底
static func evaluate() -> Dictionary:
	var endings: Array = StoryManager._endings
	for ending in endings:
		var cond = ending.get("conditions")
		if StoryManager.check_condition(cond):
			return ending
	# 不应该到这里 (default 结局的 conditions 是 null → 总是匹配)
	return {
		"id": "default",
		"title": "迷雾中的日常",
		"subtitle": "你活了下来。",
		"priority": 99,
		"conditions": null,
		"is_victory": true,
	}

## 检查是否为胜利结局
static func is_victory_ending(ending: Dictionary) -> bool:
	return ending.get("is_victory", true)

## 获取结局展示数据 (供 UI 使用)
static func get_ending_display(ending: Dictionary) -> Dictionary:
	var ending_id: String = ending.get("id", "default")

	# 结局配色方案
	var color_schemes: Dictionary = {
		"companion": { "primary": Color(0.6, 0.8, 1.0), "bg": Color(0.05, 0.1, 0.2) },
		"seal":      { "primary": Color(0.8, 0.6, 1.0), "bg": Color(0.15, 0.05, 0.2) },
		"substitute":{ "primary": Color(1.0, 0.8, 0.6), "bg": Color(0.2, 0.1, 0.05) },
		"dark_lord": { "primary": Color(1.0, 0.3, 0.3), "bg": Color(0.2, 0.02, 0.02) },
		"default":   { "primary": Color(0.7, 0.7, 0.7), "bg": Color(0.1, 0.1, 0.1) },
	}

	var scheme: Dictionary = color_schemes.get(ending_id, color_schemes["default"])

	return {
		"id": ending_id,
		"title": ending.get("title", "未知结局"),
		"subtitle": ending.get("subtitle", ""),
		"is_victory": ending.get("is_victory", true),
		"primary_color": scheme["primary"],
		"bg_color": scheme["bg"],
	}

## 获取所有结局的解锁状态 (用于结局画廊)
## unlocked_endings: Array of ending_id (String) 从存档读取
static func get_endings_gallery(unlocked_endings: Array) -> Array:
	var result: Array = []
	for ending in StoryManager._endings:
		var eid: String = ending.get("id", "")
		var unlocked: bool = eid in unlocked_endings
		result.append({
			"id": eid,
			"title": ending.get("title", "???") if unlocked else "???",
			"subtitle": ending.get("subtitle", "") if unlocked else "尚未解锁",
			"is_victory": ending.get("is_victory", true),
			"unlocked": unlocked,
		})
	return result
